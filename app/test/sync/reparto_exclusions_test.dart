import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';

const _aritz = Recipient(
  id: 'aritz',
  name: 'Aritz',
  colorIndex: 0,
  archived: false,
);

// Fields written by the recipient editor in pre.6–pre.12. It does not
// reconstruct a document from typed recipients: it patches these fields.
Map<String, Object?> _legacyFields({String name = 'Aritz'}) => {
  'name': name,
  'colorIndex': 0,
  'relation': null,
  'birthMonth': null,
  'birthDay': null,
  'birthYear': null,
  'archived': false,
};

FamilyDoc _oldDoc() => FamilyDoc.empty(
  'family',
).set(HlcClock(node: 'old'), Collections.recipients, 'aritz', _legacyFields());

Recipient _recipient(FamilyDoc doc) =>
    Recipient.fromRecord(doc.record(Collections.recipients, 'aritz')!)!;

FamilyDoc _change(FamilyDoc doc, String node, Map<String, Object?> fields) =>
    doc.set(
      HlcClock(node: node, last: doc.maxStamp),
      Collections.recipients,
      'aritz',
      fields,
    );

void main() {
  final santa = Recipient.skipOccasionField('seed-santa');
  final kings = Recipient.skipOccasionField('seed-kings');

  test('old document defaults to included and no skipped occasions', () {
    final doc = FamilyDoc.fromJson(_oldDoc().toJson());
    expect(_recipient(doc), _aritz);
    expect(_recipient(doc).inReparto, isTrue);
    expect(_recipient(doc).skipOccasions, isEmpty);
  });

  test('constructor ownership contract protects map equality and hash', () {
    final source = {'seed-santa': true};
    final recipient = Recipient(
      id: 'aritz',
      name: 'Aritz',
      colorIndex: 0,
      archived: false,
      skipOccasions: Map<String, bool>.unmodifiable(source),
    );
    final hash = recipient.hashCode;
    source['seed-santa'] = false;
    source['seed-kings'] = true;
    expect(recipient.skipOccasions, {'seed-santa': true});
    expect(recipient.hashCode, hash);
    expect(() => recipient.skipOccasions.clear(), throwsUnsupportedError);
    expect(
      recipient,
      const Recipient(
        id: 'aritz',
        name: 'Aritz',
        colorIndex: 0,
        archived: false,
        skipOccasions: {'seed-santa': true},
      ),
    );
  });

  test(
    'concurrent fields and entries survive independently with their HLC',
    () {
      final base = _oldDoc();
      final a = _change(base, 'a', {'inReparto': false, santa: true});
      final b = _change(base, 'b', {'name': 'Nora', kings: true});
      final merged = a.merge(b);
      final r = _recipient(merged);
      expect(r.name, 'Nora');
      expect(r.inReparto, isFalse);
      expect(r.skipOccasions, {'seed-santa': true, 'seed-kings': true});
      final record = merged.record(Collections.recipients, 'aritz')!;
      expect(
        record.field(santa),
        a.record(Collections.recipients, 'aritz')!.field(santa),
      );
      expect(
        record.field(kings),
        b.record(Collections.recipients, 'aritz')!.field(kings),
      );
      expect(merged.maxStamp, ([a.maxStamp!, b.maxStamp!]..sort()).last);
    },
  );

  test(
    'merge is idempotent, commutative and associative including conflicts',
    () {
      final base = _oldDoc();
      final a = _change(base, 'a', {'inReparto': false, santa: true});
      final b = _change(base, 'b', {
        'inReparto': true,
        santa: false,
        kings: true,
      });
      final c = _change(a, 'c', {kings: false});
      for (final doc in [a, b, c, a.merge(b)]) {
        expect(doc.merge(doc).canonicalJson(), doc.canonicalJson());
      }
      expect(a.merge(b).canonicalJson(), b.merge(a).canonicalJson());
      expect(a.merge(c).canonicalJson(), c.merge(a).canonicalJson());
      expect(
        a.merge(b).merge(c).canonicalJson(),
        a.merge(b.merge(c)).canonicalJson(),
      );
      final merged = a.merge(b);
      final aField = a.record(Collections.recipients, 'aritz')!.field(santa)!;
      final bField = b.record(Collections.recipients, 'aritz')!.field(santa)!;
      expect(
        _recipient(merged).skipsOccasion('seed-santa'),
        aField.stamp > bField.stamp,
      );
    },
  );

  test('false is a retained tombstone and stale exclusions cannot return', () {
    final excluded = _change(_oldDoc(), 'a', {santa: true, kings: true});
    final included = _change(excluded, 'b', {santa: false});
    final returned = FamilyDoc.fromJson(included.toJson()).merge(excluded);
    expect(_recipient(returned).skipOccasions, {
      'seed-santa': false,
      'seed-kings': true,
    });
    expect(_recipient(returned).skippedOccasionKeys, {'seed-kings'});
    expect(_recipient(returned).toFields()[santa], isFalse);
    final deleted = returned.delete(
      HlcClock(node: 'c', last: returned.maxStamp),
      Collections.recipients,
      'aritz',
    );
    expect(FamilyView.fromDoc(deleted.merge(excluded)).recipients, isEmpty);
    // Una lápida no conserva contenido: ni siquiera la exclusión retenida.
    expect(deleted.record(Collections.recipients, 'aritz')![santa], isNull);
    expect(
      deleted.merge(excluded).record(Collections.recipients, 'aritz')![santa],
      isNull,
    );
  });

  test(
    'typed fields round trip, equality and hash are map-order independent',
    () {
      const a = Recipient(
        id: 'aritz',
        name: 'Aritz',
        colorIndex: 0,
        archived: false,
        inReparto: false,
        skipOccasions: {'seed-santa': true, 'seed-kings': false},
      );
      const b = Recipient(
        id: 'aritz',
        name: 'Aritz',
        colorIndex: 0,
        archived: false,
        inReparto: false,
        skipOccasions: {'seed-kings': false, 'seed-santa': true},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(_aritz));
      final doc = _change(_oldDoc(), 'a', a.toFields());
      expect(_recipient(doc), a);
      expect(
        () => _recipient(doc).skipOccasions.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'legacy reader, edit and encrypted re-send preserve unknown fields',
    () async {
      final original = _change(_oldDoc(), 'a', {
        'inReparto': false,
        santa: true,
        kings: false,
        'futureRecipientField': {'value': 7},
      });
      final key = FamilyKey(List<int>.generate(32, (i) => i));
      Future<FamilyDoc> roundTrip(FamilyDoc doc) async {
        final bytes = await seal(
          doc: doc.toJson(),
          listId: doc.listId,
          fromNode: 'a',
          at: doc.maxStamp!.pack(),
          key: key,
        );
        final opened = await open(bytes, key: key, expectedListId: 'family');
        expect(opened.header.version, 1);
        return FamilyDoc.fromJson(opened.doc);
      }

      final received = await roundTrip(original);
      expect(received.canonicalJson(), original.canonicalJson());
      // The generic parser and merge are unchanged since pre.6. A typed old
      // editor writes only known fields; all unknown stamped fields stay put.
      final legacy = FamilyDoc.fromJson(
        Map<String, Object?>.from(jsonDecode(received.canonicalJson()) as Map),
      );
      final edited = legacy.setChanged(
        HlcClock(node: 'old', last: legacy.maxStamp),
        Collections.recipients,
        'aritz',
        _legacyFields(name: 'Nora'),
      );
      final returned = await roundTrip(edited);
      expect(_recipient(returned).name, 'Nora');
      for (final field in ['inReparto', santa, kings, 'futureRecipientField']) {
        final returnedField = returned
            .record(Collections.recipients, 'aritz')!
            .field(field)!;
        final originalField = original
            .record(Collections.recipients, 'aritz')!
            .field(field)!;
        expect(
          canonicalJsonOf(returnedField.value),
          canonicalJsonOf(originalField.value),
          reason: field,
        );
        expect(returnedField.stamp, originalField.stamp, reason: field);
      }
      expect(
        original.merge(returned).canonicalJson(),
        returned.canonicalJson(),
      );
    },
  );
}
