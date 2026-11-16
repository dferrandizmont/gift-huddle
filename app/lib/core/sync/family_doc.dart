/// The family document: a set of collections of records where every field
/// carries its own hybrid logical clock stamp.
///
/// Merging two documents keeps the newest stamp of every field, so two phones
/// can edit the same list without losing changes.
library;

import 'dart:convert';

import 'hlc.dart';

/// Version of the JSON format of the family document.
const int kFamilyDocVersion = 1;

/// Deepest nesting a value of a field can have.
///
/// A field holds JSON, and JSON can nest forever. Past this depth the value
/// is refused, so a document that is read is always one that can be written
/// again.
const int kMaxJsonDepth = 32;

/// Name of the field that turns a record into a tombstone.
const String kDeletedField = 'deleted';

/// A value of a field together with the stamp that wrote it.
class FieldValue {
  /// The value: JSON only (null, bool, num, String, List or Map).
  final Object? value;

  /// When this value was written.
  final Hlc stamp;

  /// Creates a stamped value.
  const FieldValue({required this.value, required this.stamp});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldValue && other.value == value && other.stamp == stamp;

  @override
  int get hashCode => Object.hash(value, stamp);

  @override
  String toString() => 'FieldValue(${canonicalJsonOf(value)}, ${stamp.pack()})';
}

/// One record of a collection: an id and its stamped fields.
class SyncRecord {
  /// Id of the record, unique inside its collection.
  final String id;

  /// The fields of the record, by name.
  final Map<String, FieldValue> fields;

  /// Creates an immutable record.
  SyncRecord({required this.id, Map<String, FieldValue>? fields})
    : fields = Map<String, FieldValue>.unmodifiable(
        fields ?? const <String, FieldValue>{},
      );

  /// The plain value of a field, or null when the field is not there.
  Object? operator [](String name) => fields[name]?.value;

  /// The stamped value of a field, or null when the field is not there.
  FieldValue? field(String name) => fields[name];

  /// Whether the record is a tombstone.
  bool get isDeleted => this[kDeletedField] == true;

  /// Whether the record is a tombstone that still holds content: some field
  /// other than `deleted` keeps a value. A tombstone written by this version
  /// has none; one from an older phone can.
  bool get hasTombstoneContent =>
      isDeleted &&
      fields.entries.any(
        (entry) => entry.key != kDeletedField && entry.value.value != null,
      );

  /// This record with the content of a tombstone cleared.
  ///
  /// A record that is not deleted, or that has nothing to clear, is returned
  /// as it is. Every other field keeps its stamp and loses its value, so the
  /// result is a function of the merged fields only and the merge stays
  /// commutative, associative and idempotent.
  SyncRecord scrubbed() {
    if (!hasTombstoneContent) {
      return this;
    }
    return SyncRecord(
      id: id,
      fields: <String, FieldValue>{
        for (final entry in fields.entries)
          entry.key: entry.key == kDeletedField || entry.value.value == null
              ? entry.value
              : FieldValue(value: null, stamp: entry.value.stamp),
      },
    );
  }

  @override
  String toString() => 'SyncRecord($id, ${fields.length} fields)';
}

/// The document of one family list.
///
/// It does not know anything about the domain: it only knows collections of
/// records and stamped fields. Collections and fields that this version of
/// the app does not know are kept untouched, so an old phone never drops the
/// work of a newer one.
class FamilyDoc {
  /// Id of the list. Two documents of the same family share it.
  final String listId;

  /// The records, by collection and then by id.
  final Map<String, Map<String, SyncRecord>> collections;

  /// Creates an immutable document.
  FamilyDoc({
    required this.listId,
    Map<String, Map<String, SyncRecord>>? collections,
  }) : collections = Map<String, Map<String, SyncRecord>>.unmodifiable({
         for (final entry in (collections ?? const {}).entries)
           entry.key: Map<String, SyncRecord>.unmodifiable(entry.value),
       });

  /// An empty document.
  factory FamilyDoc.empty(String listId) => FamilyDoc(listId: listId);

  /// The record of a collection, or null when there is none.
  SyncRecord? record(String collection, String id) =>
      collections[collection]?[id];

  /// Writes [changes] in a record and returns a new document.
  ///
  /// Every field of [changes] gets the same stamp, taken from [clock]. When
  /// the record does not exist yet it is created.
  ///
  /// A field with a null value is a tombstone: the field is gone but the
  /// record stays. Throws [ArgumentError] when a value of [changes] is not
  /// something JSON can hold.
  FamilyDoc set(
    HlcClock clock,
    String collection,
    String id,
    Map<String, Object?> changes,
  ) {
    _checkJsonValues(changes);
    final stamp = clock.now();
    final nextCollections = Map<String, Map<String, SyncRecord>>.of(
      collections,
    );
    final nextRecords = Map<String, SyncRecord>.of(
      nextCollections[collection] ?? const <String, SyncRecord>{},
    );
    final previous = nextRecords[id];
    final nextFields = <String, FieldValue>{...?previous?.fields};
    for (final entry in changes.entries) {
      if (entry.key == kDeletedField &&
          entry.value != true &&
          previous != null &&
          previous.isDeleted) {
        // A deletion is final: nothing written here takes a tombstone away.
        continue;
      }
      nextFields[entry.key] = FieldValue(value: entry.value, stamp: stamp);
    }
    // A tombstone wins over any content written afterwards: it stays empty.
    nextRecords[id] = SyncRecord(id: id, fields: nextFields).scrubbed();
    nextCollections[collection] = nextRecords;
    return FamilyDoc(listId: listId, collections: nextCollections);
  }

  /// Writes only the fields of [changes] that are different from the ones
  /// the record has now, and returns a new document.
  ///
  /// The fields that did not change keep their mark, so saving a gift does
  /// not steal the changes another phone made to the other fields of the
  /// same gift. When nothing changes the very same document is returned.
  ///
  /// Throws [ArgumentError] when a value of [changes] is not something JSON
  /// can hold.
  FamilyDoc setChanged(
    HlcClock clock,
    String collection,
    String id,
    Map<String, Object?> changes,
  ) {
    _checkJsonValues(changes);
    final previous = record(collection, id);
    final changed = <String, Object?>{};
    for (final entry in changes.entries) {
      final current = previous?.fields[entry.key]?.value;
      if (canonicalJsonOf(current) != canonicalJsonOf(entry.value)) {
        changed[entry.key] = entry.value;
      }
    }
    if (changed.isEmpty) {
      return this;
    }
    return set(clock, collection, id, changed);
  }

  /// Marks a record as deleted and returns a new document.
  ///
  /// The record becomes a tombstone: `deleted` is true and every other field
  /// it had is cleared (value null) with the same new stamp, so the name, the
  /// notes, the prices and the links are not readable any more and the
  /// clearing travels to the other phones like any other change. A tombstone
  /// is final: [merge] keeps it deleted and empty whatever is edited later or
  /// concurrently on another phone.
  FamilyDoc delete(HlcClock clock, String collection, String id) {
    final previous = record(collection, id);
    return set(clock, collection, id, <String, Object?>{
      for (final name in previous?.fields.keys ?? const <String>[])
        if (name != kDeletedField) name: null,
      kDeletedField: true,
    });
  }

  /// The tombstones of this document that still hold content, as
  /// (collection, id) pairs. Only documents written by an older version have
  /// them.
  List<(String, String)> tombstonesWithContent() => [
    for (final collection in collections.entries)
      for (final record in collection.value.values)
        if (record.hasTombstoneContent) (collection.key, record.id),
  ];

  /// The records that [merged] (the result of merging this document with
  /// [other]) holds as tombstones, and that [other] still fills with content
  /// that this document does not beat with a strictly newer stamp.
  ///
  /// [merge] already empties them, but keeping the stamp of the content: a
  /// phone running an older version, that settles ties by the text of the
  /// value, could keep a value (an object or `true`) forever and the two
  /// documents would never be equal. Deleting them again with a fresh stamp
  /// makes the clearing win by stamp on every version.
  List<(String, String)> staleTombstonesIn(FamilyDoc other, FamilyDoc merged) {
    final stale = <(String, String)>[];
    for (final collection in other.collections.entries) {
      for (final theirs in collection.value.values) {
        final result = merged.record(collection.key, theirs.id);
        if (result == null || !result.isDeleted) {
          continue;
        }
        final mine = record(collection.key, theirs.id);
        final dirty = theirs.fields.entries.any((field) {
          if (field.key == kDeletedField || field.value.value == null) {
            return false;
          }
          final own = mine?.fields[field.key];
          return own == null || own.stamp.compareTo(field.value.stamp) <= 0;
        });
        if (dirty) {
          stale.add((collection.key, theirs.id));
        }
      }
    }
    return stale;
  }

  /// This document with the content of every tombstone cleared.
  ///
  /// It brings the tombstones of an older version of the app (that kept the
  /// content of what was deleted) to the current shape. The same document is
  /// returned when there is nothing to clear.
  FamilyDoc scrubbed() {
    var changed = false;
    final nextCollections = <String, Map<String, SyncRecord>>{};
    for (final entry in collections.entries) {
      final nextRecords = <String, SyncRecord>{};
      for (final record in entry.value.entries) {
        final clean = record.value.scrubbed();
        changed = changed || !identical(clean, record.value);
        nextRecords[record.key] = clean;
      }
      nextCollections[entry.key] = nextRecords;
    }
    return changed
        ? FamilyDoc(listId: listId, collections: nextCollections)
        : this;
  }

  /// Merges [other] into this document and returns a new document.
  ///
  /// Throws [ArgumentError] when the two documents belong to different lists.
  /// The merge keeps the newest stamp of every field, except for `deleted`:
  /// a true value wins over any other whatever its stamp, because a deletion
  /// is final. A record that ends up deleted loses the value of every other
  /// field (their stamps stay), so a concurrent edit on another phone cannot
  /// bring a deleted record back or make its content readable again. All of
  /// it depends only on the set of fields merged, so the merge is
  /// commutative, associative and idempotent.
  FamilyDoc merge(FamilyDoc other) {
    if (other.listId != listId) {
      throw ArgumentError.value(
        other.listId,
        'other.listId',
        'cannot merge documents of different lists ($listId)',
      );
    }
    final nextCollections = <String, Map<String, SyncRecord>>{};
    final collectionNames = <String>{
      ...collections.keys,
      ...other.collections.keys,
    };
    for (final collection in collectionNames) {
      final mine = collections[collection] ?? const <String, SyncRecord>{};
      final theirs =
          other.collections[collection] ?? const <String, SyncRecord>{};
      final nextRecords = <String, SyncRecord>{};
      for (final id in <String>{...mine.keys, ...theirs.keys}) {
        final myRecord = mine[id];
        final theirRecord = theirs[id];
        if (myRecord == null) {
          nextRecords[id] = theirRecord!.scrubbed();
          continue;
        }
        if (theirRecord == null) {
          nextRecords[id] = myRecord.scrubbed();
          continue;
        }
        final nextFields = <String, FieldValue>{...myRecord.fields};
        for (final entry in theirRecord.fields.entries) {
          final current = nextFields[entry.key];
          if (current == null ||
              _compareField(entry.key, current, entry.value) < 0) {
            nextFields[entry.key] = entry.value;
          }
        }
        nextRecords[id] = SyncRecord(id: id, fields: nextFields).scrubbed();
      }
      nextCollections[collection] = nextRecords;
    }
    return FamilyDoc(listId: listId, collections: nextCollections);
  }

  /// The newest stamp of the document, or null when it is empty.
  ///
  /// The receiver of the document calls `clock.receive(maxStamp)` so its own
  /// stamps stay newer than everything it has seen.
  Hlc? get maxStamp {
    Hlc? newest;
    for (final records in collections.values) {
      for (final record in records.values) {
        for (final field in record.fields.values) {
          if (newest == null || field.stamp > newest) {
            newest = field.stamp;
          }
        }
      }
    }
    return newest;
  }

  /// The document as plain JSON, with the keys of every level sorted.
  Map<String, Object?> toJson() {
    final nextCollections = <String, Object?>{};
    final collectionNames = collections.keys.toList()..sort();
    for (final collection in collectionNames) {
      final records = collections[collection]!;
      final nextRecords = <String, Object?>{};
      final ids = records.keys.toList()..sort();
      for (final id in ids) {
        final record = records[id]!;
        final nextFields = <String, Object?>{};
        final names = record.fields.keys.toList()..sort();
        for (final name in names) {
          final field = record.fields[name]!;
          nextFields[name] = <Object?>[field.value, field.stamp.pack()];
        }
        nextRecords[id] = nextFields;
      }
      nextCollections[collection] = nextRecords;
    }
    return <String, Object?>{
      'v': kFamilyDocVersion,
      'listId': listId,
      'c': nextCollections,
    };
  }

  /// Reads a document written by [toJson].
  ///
  /// Throws [FormatException] when the structure is not valid.
  factory FamilyDoc.fromJson(Map<String, Object?> json) {
    final version = json['v'];
    if (version is! int || version != kFamilyDocVersion) {
      throw FormatException(
        'Unsupported family document version: $version '
        '(expected $kFamilyDocVersion)',
      );
    }
    final listId = json['listId'];
    if (listId is! String || listId.isEmpty) {
      throw FormatException(
        'Family document field "listId" must be a non-empty string',
      );
    }
    final rawCollections = json['c'];
    if (rawCollections is! Map) {
      throw FormatException(
        'Family document field "c" must be an object of collections',
      );
    }
    final collections = <String, Map<String, SyncRecord>>{};
    for (final collectionEntry in rawCollections.entries) {
      final collectionName = collectionEntry.key;
      if (collectionName is! String) {
        throw FormatException('Collection names must be strings');
      }
      final rawRecords = collectionEntry.value;
      if (rawRecords is! Map) {
        throw FormatException(
          'Collection "$collectionName" must be an object of records',
        );
      }
      final records = <String, SyncRecord>{};
      for (final recordEntry in rawRecords.entries) {
        final recordId = recordEntry.key;
        if (recordId is! String) {
          throw FormatException(
            'Record ids must be strings in collection "$collectionName"',
          );
        }
        final rawFields = recordEntry.value;
        if (rawFields is! Map) {
          throw FormatException(
            'Record "$recordId" of collection "$collectionName" must be an '
            'object of fields',
          );
        }
        final fields = <String, FieldValue>{};
        for (final fieldEntry in rawFields.entries) {
          final fieldName = fieldEntry.key;
          if (fieldName is! String) {
            throw FormatException(
              'Field names must be strings in record "$recordId"',
            );
          }
          final rawField = fieldEntry.value;
          if (rawField is! List || rawField.length != 2) {
            throw FormatException(
              'Field "$fieldName" of record "$recordId" must be a '
              '[value, stamp] pair',
            );
          }
          final rawValue = rawField[0];
          if (!_isJsonValue(rawValue)) {
            throw FormatException(
              'Field "$fieldName" of record "$recordId" holds a value that is '
              'not JSON',
            );
          }
          final packedStamp = rawField[1];
          if (packedStamp is! String) {
            throw FormatException(
              'Field "$fieldName" of record "$recordId" must have its stamp '
              'as a string',
            );
          }
          final Hlc stamp;
          try {
            stamp = Hlc.parse(packedStamp);
          } on FormatException catch (error) {
            throw FormatException(
              'Field "$fieldName" of record "$recordId" has an invalid stamp '
              '"$packedStamp": ${error.message}',
            );
          }
          fields[fieldName] = FieldValue(value: rawValue, stamp: stamp);
        }
        records[recordId] = SyncRecord(id: recordId, fields: fields);
      }
      collections[collectionName] = records;
    }
    return FamilyDoc(listId: listId, collections: collections);
  }

  /// The document as canonical JSON text: the same document always gives the
  /// same bytes.
  String canonicalJson() => canonicalJsonOf(toJson());

  @override
  String toString() => 'FamilyDoc($listId, ${collections.length} collections)';
}

/// Orders two fields of the same name: newer stamp first, and when the
/// stamps are the same the bigger canonical value wins.
///
/// The field `deleted` is the exception: a true value is above any other one
/// before the stamps are looked at, so nobody can undo a deletion.
///
/// The order is total, so merging is commutative, associative and idempotent.
int _compareField(String name, FieldValue a, FieldValue b) {
  if (name == kDeletedField) {
    final aDeleted = a.value == true;
    if (aDeleted != (b.value == true)) {
      return aDeleted ? 1 : -1;
    }
  }
  final byStamp = a.stamp.compareTo(b.stamp);
  if (byStamp != 0) {
    return byStamp;
  }
  return canonicalJsonOf(a.value).compareTo(canonicalJsonOf(b.value));
}

/// Whether [value] is something JSON can hold.
///
/// The value cannot be nested more than [kMaxJsonDepth] levels and cannot
/// hold a number that is not finite.
bool _isJsonValue(Object? value, [int depth = 1]) {
  if (value == null || value is bool || value is String) {
    return true;
  }
  if (value is num) {
    return value is! double || value.isFinite;
  }
  if (value is List) {
    if (depth > kMaxJsonDepth) {
      return false;
    }
    return value.every((item) => _isJsonValue(item, depth + 1));
  }
  if (value is Map) {
    if (depth > kMaxJsonDepth) {
      return false;
    }
    for (final entry in value.entries) {
      if (entry.key is! String || !_isJsonValue(entry.value, depth + 1)) {
        return false;
      }
    }
    return true;
  }
  return false;
}

/// Checks that every value of [changes] is something JSON can hold.
///
/// Throws [ArgumentError] when one of them is not, so a bug in the caller
/// cannot write a document that cannot be read back.
void _checkJsonValues(Map<String, Object?> changes) {
  for (final entry in changes.entries) {
    if (!_isJsonValue(entry.value)) {
      throw ArgumentError.value(
        entry.value,
        'changes["${entry.key}"]',
        'a field of the document can only hold a JSON value',
      );
    }
  }
}

/// The canonical JSON text of a value: the keys of every object sorted, so
/// two equal values always give the same text.
String canonicalJsonOf(Object? value) {
  final buffer = StringBuffer();
  _writeCanonical(buffer, value);
  return buffer.toString();
}

void _writeCanonical(StringBuffer buffer, Object? value, [int depth = 1]) {
  if (value == null) {
    buffer.write('null');
    return;
  }
  if (value is bool) {
    buffer.write(value ? 'true' : 'false');
    return;
  }
  if (value is num) {
    if (value is double && (value.isNaN || value.isInfinite)) {
      throw FormatException('A number that is not finite cannot be JSON');
    }
    buffer.write(jsonEncode(value));
    return;
  }
  if (value is String) {
    buffer.write(jsonEncode(value));
    return;
  }
  if (value is List) {
    if (depth > kMaxJsonDepth) {
      throw FormatException(
        'A value cannot be nested more than $kMaxJsonDepth levels deep',
      );
    }
    buffer.write('[');
    for (var i = 0; i < value.length; i++) {
      if (i > 0) {
        buffer.write(',');
      }
      _writeCanonical(buffer, value[i], depth + 1);
    }
    buffer.write(']');
    return;
  }
  if (value is Map) {
    if (depth > kMaxJsonDepth) {
      throw FormatException(
        'A value cannot be nested more than $kMaxJsonDepth levels deep',
      );
    }
    final keys = <String>[];
    for (final key in value.keys) {
      if (key is! String) {
        throw FormatException('The keys of a JSON object must be strings');
      }
      keys.add(key);
    }
    keys.sort();
    buffer.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) {
        buffer.write(',');
      }
      buffer.write(jsonEncode(keys[i]));
      buffer.write(':');
      _writeCanonical(buffer, value[keys[i]], depth + 1);
    }
    buffer.write('}');
    return;
  }
  throw FormatException('A value of type ${value.runtimeType} cannot be JSON');
}
