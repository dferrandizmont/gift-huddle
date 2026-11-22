/// The domain of the app seen as typed views over the family document.
///
/// Every class here is immutable and knows how to read itself from a
/// [SyncRecord] and how to write its fields back. Prices are always in cents
/// and the dates of an occasion are a month and a day, plus a year for the
/// ones that do not repeat.
library;

import 'dart:convert';

import 'package:cryptography/dart.dart';

import 'family_doc.dart';
import 'hlc.dart';

/// The collections of the family document.
abstract final class Collections {
  /// The people the gifts are for: children, relatives, friends...
  static const String recipients = 'recipients';

  /// The people who give gifts.
  static const String givers = 'givers';

  /// The occasions of the year.
  static const String occasions = 'occasions';

  /// The gifts themselves.
  static const String gifts = 'gifts';

  /// Free form data of the list (year of the list, settings...).
  static const String meta = 'meta';

  /// La política de sorpresas de cada persona (`hideOwnGifts` y su
  /// revisión), con el id de la persona como id del registro. ADR 0004.
  /// Los móviles anteriores la conservan sin entenderla.
  static const String policies = 'policies';
}

/// Where a gift is in its way to the recipient.
enum GiftStatus {
  /// Only an idea, nobody decided anything yet.
  idea,

  /// Somebody decided what to give.
  decided,

  /// It has been bought.
  bought,

  /// It has arrived at the house.
  arrived,

  /// It has been wrapped.
  wrapped,

  /// It has been given.
  delivered;

  /// Reads a status by name. An unknown name is read as [GiftStatus.idea].
  static GiftStatus fromName(String? name) => tryParse(name) ?? GiftStatus.idea;

  /// Reads a status by name, or null when the name is not known.
  static GiftStatus? tryParse(String? name) {
    if (name == null) {
      return null;
    }
    for (final status in GiftStatus.values) {
      if (status.name == name) {
        return status;
      }
    }
    return null;
  }

  /// Whether the gift is already bought or further along.
  bool get isBoughtOrLater => index >= GiftStatus.bought.index;
}

/// The kind of an occasion.
enum OccasionKind {
  /// The Catalan tradition of the Tió.
  tio,

  /// Santa Claus.
  santa,

  /// The Three Kings.
  kings,

  /// A birthday.
  birthday,

  /// The Chinese New Year. Its date changes every year.
  chineseNewYear,

  /// A wedding gift.
  wedding,

  /// A wedding anniversary or any other anniversary.
  anniversary,

  /// Sant Jordi (23 April): a book and a rose.
  santJordi,

  /// Valentine's Day (14 February).
  valentine,

  /// A baptism or the birth of a baby.
  baptism,

  /// A first communion.
  communion,

  /// A graduation or the end of a school year.
  graduation,

  /// Anything else.
  custom;

  /// Reads a kind by name. An unknown name is read as [OccasionKind.custom].
  static OccasionKind fromName(String? name) =>
      tryParse(name) ?? OccasionKind.custom;

  /// Reads a kind by name, or null when the name is not known.
  static OccasionKind? tryParse(String? name) {
    if (name == null) {
      return null;
    }
    for (final kind in OccasionKind.values) {
      if (kind.name == name) {
        return kind;
      }
    }
    return null;
  }
}

/// Somebody the family gives gifts to: a child, a relative, a friend...
class Recipient {
  /// Id of the recipient.
  final String id;

  /// Short name of the recipient.
  final String name;

  /// Index of the colour of the recipient in the palette of the design.
  final int colorIndex;

  /// Free text with the relation to the family, like "son" or "niece".
  /// It may be missing.
  final String? relation;

  /// Month of the birthday, from 1 to 12.
  final int? birthMonth;

  /// Day of the birthday.
  final int? birthDay;

  /// Year of the birthday, only when it is known.
  final int? birthYear;

  /// Whether the recipient is kept out of the current list.
  final bool archived;

  /// Whether the recipient appears in Reparto. Does not archive their gifts.
  final bool inReparto;

  /// A person who only gives gifts and never receives them (1.0.6: the
  /// "Nobody" answer to "Who are you?" is a real person with this mark, so
  /// their phone keeps every right). They are not a gift recipient: not in
  /// the recipient picker, Reparto or the budget ([FamilyView.giftRecipients]),
  /// but they stay in People. Older phones show them as an ordinary person.
  final bool noGifts;

  /// The wire field of [noGifts]. Written only when true; null clears it.
  static const String noGiftsField = 'noGifts';

  /// Occasion ids excluded from Reparto (`true`) or explicitly included
  /// again (`false`). Missing entries mean included. False entries must be
  /// retained: they are the tombstones of previous exclusions.
  /// Must be immutable; see the const constructor's ownership contract.
  final Map<String, bool> skipOccasions;

  /// Each entry is a separate ordinary stamped field on the wire. Older
  /// phones preserve unknown fields without needing a new document version.
  static const String skipOccasionFieldPrefix = 'skipOccasions:';

  /// The wire field for one stable occasion id (not its translated name).
  static String skipOccasionField(String occasionKey) =>
      '$skipOccasionFieldPrefix$occasionKey';

  /// Whether the recipient does not receive gifts for this occasion.
  bool skipsOccasion(String occasionKey) => skipOccasions[occasionKey] == true;

  /// The excluded ids, for labels such as "Without Christmas" in All.
  Set<String> get skippedOccasionKeys =>
      Set<String>.unmodifiable(skipOccasions.keys.where(skipsOccasion));

  /// Creates a recipient.
  ///
  /// To keep this constructor const, [skipOccasions] is not copied. Pass a
  /// const map or a defensive `Map<String, bool>.unmodifiable(source)` copy,
  /// never a mutable map: changing it would invalidate equality and hashCode.
  /// [fromRecord] always makes that defensive copy for received data.
  const Recipient({
    required this.id,
    required this.name,
    required this.colorIndex,
    this.relation,
    this.birthMonth,
    this.birthDay,
    this.birthYear,
    required this.archived,
    this.inReparto = true,
    this.skipOccasions = const <String, bool>{},
    this.noGifts = false,
  });

  /// Reads a recipient from a record, or null when the record is deleted or
  /// is missing something mandatory.
  ///
  /// A month or a day out of range is treated as missing: it comes from
  /// another phone and cannot be trusted.
  static Recipient? fromRecord(SyncRecord record) {
    if (record.isDeleted) {
      return null;
    }
    final name = _string(record['name']);
    final colorIndex = _int(record['colorIndex']);
    final archived = _bool(record['archived']);
    if (name == null || colorIndex == null || archived == null) {
      return null;
    }
    return Recipient(
      id: record.id,
      name: name,
      colorIndex: colorIndex,
      relation: _string(record['relation']),
      birthMonth: _month(record['birthMonth']),
      birthDay: _day(record['birthDay']),
      birthYear: _int(record['birthYear']),
      archived: archived,
      inReparto: _bool(record['inReparto']) ?? true,
      noGifts: record[noGiftsField] == true,
      skipOccasions: Map<String, bool>.unmodifiable({
        for (final entry in record.fields.entries)
          if (entry.key.startsWith(skipOccasionFieldPrefix) &&
              entry.value.value is bool)
            entry.key.substring(skipOccasionFieldPrefix.length):
                entry.value.value as bool,
      }),
    );
  }

  /// The fields of the recipient.
  ///
  /// Every field is written, also the ones that are not there: a null value
  /// is the tombstone of a field that is gone.
  Map<String, Object?> toFields() => <String, Object?>{
    'name': name,
    'colorIndex': colorIndex,
    'relation': relation,
    'birthMonth': birthMonth,
    'birthDay': birthDay,
    'birthYear': birthYear,
    'archived': archived,
    'inReparto': inReparto,
    for (final entry in skipOccasions.entries)
      skipOccasionField(entry.key): entry.value,
    if (noGifts) noGiftsField: true,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Recipient &&
          other.id == id &&
          other.name == name &&
          other.colorIndex == colorIndex &&
          other.relation == relation &&
          other.birthMonth == birthMonth &&
          other.birthDay == birthDay &&
          other.birthYear == birthYear &&
          other.archived == archived &&
          other.inReparto == inReparto &&
          other.noGifts == noGifts &&
          canonicalJsonOf(other.skipOccasions) ==
              canonicalJsonOf(skipOccasions);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    colorIndex,
    relation,
    birthMonth,
    birthDay,
    birthYear,
    archived,
    inReparto,
    noGifts,
    canonicalJsonOf(skipOccasions),
  );

  @override
  String toString() => 'Recipient($id, $name)';
}

/// Somebody who gives gifts.
class Giver {
  static const recipientIdField = 'recipientId';

  /// Manual ids are UUIDs. This namespace is reserved for creation from People.
  static const personIdPrefix = 'person-giver:';

  /// Finds the first unused generation. Occupied ids include tombstones and
  /// previous generations that have since been unlinked.
  static String nextPersonGiverId(FamilyDoc doc, String recipientId) {
    final input = utf8.encode(jsonEncode([doc.listId, recipientId]));
    final digest = const DartSha256().hashSync(input).bytes.sublist(0, 16);
    final identity = base64Url.encode(digest).replaceAll('=', '');
    for (var generation = 0; ; generation++) {
      final id = '$personIdPrefix$identity:$generation';
      if (doc.record(Collections.givers, id) == null) return id;
    }
  }

  /// Id of the giver.
  final String id;

  /// Free name of the giver, never a role like "mum" or "dad".
  final String name;

  /// Index of the colour of the giver in the palette of the design.
  final int colorIndex;

  /// Whether the gifts of this giver are paid by the house, so they count as
  /// an expense of the family.
  final bool householdPays;

  /// Whether the giver is kept out of the current list.
  final bool archived;

  /// The person linked to this giver. Name and color remain on the record
  /// for older clients and for history after the person is deleted.
  final String? recipientId;

  /// Creates a giver.
  const Giver({
    required this.id,
    required this.name,
    required this.colorIndex,
    required this.householdPays,
    required this.archived,
    this.recipientId,
  });

  /// Reads a giver from a record, or null when the record is deleted or is
  /// missing something mandatory.
  static Giver? fromRecord(SyncRecord record) {
    if (record.isDeleted) {
      return null;
    }
    final name = _string(record['name']);
    final colorIndex = _int(record['colorIndex']);
    final householdPays = _bool(record['householdPays']);
    final archived = _bool(record['archived']);
    if (name == null ||
        colorIndex == null ||
        householdPays == null ||
        archived == null) {
      return null;
    }
    return Giver(
      id: record.id,
      name: name,
      colorIndex: colorIndex,
      householdPays: householdPays,
      archived: archived,
      recipientId: _string(record[recipientIdField]),
    );
  }

  /// The fields of the giver.
  ///
  /// Use a separate stamped null to explicitly remove a link.
  Map<String, Object?> toFields() => <String, Object?>{
    'name': name,
    'colorIndex': colorIndex,
    'householdPays': householdPays,
    'archived': archived,
    if (recipientId != null) recipientIdField: recipientId,
  };

  Giver withPersonDetails(Recipient person) => Giver(
    id: id,
    name: person.name,
    colorIndex: person.colorIndex,
    householdPays: householdPays,
    archived: archived,
    recipientId: recipientId,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Giver &&
          other.id == id &&
          other.name == name &&
          other.colorIndex == colorIndex &&
          other.householdPays == householdPays &&
          other.archived == archived &&
          other.recipientId == recipientId;

  @override
  int get hashCode =>
      Object.hash(id, name, colorIndex, householdPays, archived, recipientId);

  @override
  String toString() => 'Giver($id, $name)';
}

/// Repairs the copies after merging independently stamped person fields.
/// The caller's clock has observed the incoming document before writing.
FamilyDoc reconcileGiverCopies(
  FamilyDoc doc,
  HlcClock clock, {
  String? onlyPersonId,
}) {
  var next = doc;
  for (final record
      in doc.collections[Collections.givers]?.values ?? const <SyncRecord>[]) {
    final giver = Giver.fromRecord(record);
    final personId = giver?.recipientId;
    if (personId == null ||
        (onlyPersonId != null && personId != onlyPersonId)) {
      continue;
    }
    final personRecord = doc.record(Collections.recipients, personId);
    final person = personRecord == null
        ? null
        : Recipient.fromRecord(personRecord);
    if (person == null) continue;
    next = next.setChanged(clock, Collections.givers, record.id, {
      'name': person.name,
      'colorIndex': person.colorIndex,
    });
  }
  return next;
}

/// A day of the year the family gives gifts.
class Occasion {
  /// Id of the occasion.
  final String id;

  /// The kind of the occasion.
  final OccasionKind kind;

  /// The name written in the record, kept even when the kind is not known.
  final String rawKind;

  /// Name of the occasion, for the ones that are not one of the kinds.
  final String name;

  /// Month of the occasion, from 1 to 12.
  final int month;

  /// Day of the occasion.
  final int day;

  /// Year of the occasion, only when it does not repeat.
  final int? year;

  /// Whether the occasion repeats every year.
  final bool recurring;

  /// The recipient whose birthday it is, when the occasion is a birthday.
  final String? recipientId;

  /// Whether the occasion is kept out of the current list.
  final bool archived;

  /// The colour chosen for an occasion of the kind [OccasionKind.custom]: the
  /// name of one of the colours of the app. Any other value is ignored.
  final String? color;

  /// The icon chosen for an occasion of the kind [OccasionKind.custom]: the
  /// name of one of the icons of the app. Any other value is ignored.
  final String? icon;

  /// The household's budget in cents, or null when none has been set.
  final int? budgetCents;

  /// The stable wire field for [budgetCents].
  static const String budgetField = 'budgetCents';

  /// Creates an occasion.
  const Occasion({
    required this.id,
    required this.kind,
    required this.rawKind,
    required this.name,
    required this.month,
    required this.day,
    this.year,
    required this.recurring,
    this.recipientId,
    required this.archived,
    this.color,
    this.icon,
    this.budgetCents,
  });

  /// Copies the occasion with a new budget. Pass null to clear it.
  Occasion copyWith({required int? budgetCents}) => Occasion(
    id: id,
    kind: kind,
    rawKind: rawKind,
    name: name,
    month: month,
    day: day,
    year: year,
    recurring: recurring,
    recipientId: recipientId,
    archived: archived,
    color: color,
    icon: icon,
    budgetCents: budgetCents,
  );

  /// Reads an occasion from a record, or null when the record is deleted or
  /// is missing something mandatory.
  ///
  /// A month or a day out of range is not a date, and a birthday without a
  /// person is not a birthday: both make the record invalid.
  static Occasion? fromRecord(SyncRecord record) {
    if (record.isDeleted) {
      return null;
    }
    final rawKind = _string(record['kind']);
    final name = _string(record['name']);
    final month = _int(record['month']);
    final day = _int(record['day']);
    final recurring = _bool(record['recurring']);
    final archived = _bool(record['archived']);
    if (rawKind == null ||
        name == null ||
        month == null ||
        day == null ||
        recurring == null ||
        archived == null) {
      return null;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final recipientId = _string(record['recipientId']);
    if (rawKind == OccasionKind.birthday.name &&
        (recipientId == null || recipientId.isEmpty)) {
      return null;
    }
    return Occasion(
      id: record.id,
      kind: OccasionKind.fromName(rawKind),
      rawKind: rawKind,
      name: name,
      month: month,
      day: day,
      year: _int(record['year']),
      recurring: recurring,
      recipientId: recipientId,
      archived: archived,
      color: _string(record['color']),
      icon: _string(record['icon']),
      budgetCents: _cents(record[budgetField]),
    );
  }

  /// The fields of the occasion.
  ///
  /// Every field is written, also the ones that are not there: a null value
  /// is the tombstone of a field that is gone.
  Map<String, Object?> toFields() => <String, Object?>{
    'kind': rawKind,
    'name': name,
    'month': month,
    'day': day,
    'year': year,
    'recurring': recurring,
    'recipientId': recipientId,
    'archived': archived,
    'color': color,
    'icon': icon,
    budgetField: checkedBudgetCents(budgetCents),
  };

  /// Checks a budget before writing it. Null clears the budget.
  static int? checkedBudgetCents(int? cents) => cents == null
      ? null
      : RangeError.checkValueInInterval(cents, 0, kMaxCents, budgetField);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Occasion &&
          other.id == id &&
          other.kind == kind &&
          other.rawKind == rawKind &&
          other.name == name &&
          other.month == month &&
          other.day == day &&
          other.year == year &&
          other.recurring == recurring &&
          other.recipientId == recipientId &&
          other.archived == archived &&
          other.color == color &&
          other.icon == icon &&
          other.budgetCents == budgetCents;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    rawKind,
    name,
    month,
    day,
    year,
    recurring,
    recipientId,
    archived,
    color,
    icon,
    budgetCents,
  );

  @override
  String toString() => 'Occasion($id, $name, budgetCents: $budgetCents)';
}

/// Who asked for a gift.
///
/// It is either somebody with a card in the list of recipients or somebody
/// that is only known by name.
sealed class RequestedBy {
  /// Creates a requested by.
  const RequestedBy();

  /// The fields written in the record.
  ///
  /// This is the value of the field `requestedBy`, not the fields of the
  /// record: each variant writes only the one it needs.
  Map<String, Object?> toFields();

  /// Reads a requested by from the value of a field, or null when there is
  /// none or when it is not understood.
  static RequestedBy? fromFields(Object? value) {
    if (value is! Map) {
      return null;
    }
    final recipientId = value['recipientId'];
    if (recipientId is String && recipientId.isNotEmpty) {
      return RequestedByRecipient(recipientId);
    }
    final name = value['name'];
    if (name is String && name.isNotEmpty) {
      return RequestedByName(name);
    }
    return null;
  }
}

/// Somebody with a card in the list of recipients asked for the gift.
final class RequestedByRecipient extends RequestedBy {
  /// Id of the recipient that asked.
  final String recipientId;

  /// Creates the requested by of a recipient.
  const RequestedByRecipient(this.recipientId);

  /// The fields written in the record.
  @override
  Map<String, Object?> toFields() => <String, Object?>{
    'recipientId': recipientId,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RequestedByRecipient && other.recipientId == recipientId;

  @override
  int get hashCode => recipientId.hashCode;

  @override
  String toString() => 'RequestedByRecipient($recipientId)';
}

/// Somebody without a card in the list of recipients asked for the gift, so
/// only the name is known.
final class RequestedByName extends RequestedBy {
  /// Name of the person that asked.
  final String name;

  /// Creates the requested by of a name.
  const RequestedByName(this.name);

  /// The fields written in the record.
  @override
  Map<String, Object?> toFields() => <String, Object?>{'name': name};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RequestedByName && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'RequestedByName($name)';
}

/// A gift for a recipient.
class Gift {
  /// Id of the gift.
  final String id;

  /// The recipient the gift is for.
  final String recipientId;

  /// What the gift is.
  final String title;

  /// Who gives the gift.
  final String? giverId;

  /// The occasion the gift belongs to.
  final String? occasionId;

  /// Where the gift is in its way to the recipient.
  final GiftStatus status;

  /// The status written in the record, kept even when it is not known.
  final String rawStatus;

  /// What the gift is expected to cost, in cents.
  final int? plannedCents;

  /// What the gift really cost, in cents.
  final int? actualCents;

  /// Where the gift was bought.
  final String? store;

  /// Link to the gift.
  final String? url;

  /// A free note about the gift.
  final String? note;

  /// Size or age of the toy.
  final String? size;

  /// Who asked for the gift, when somebody asked for it.
  ///
  /// When the recipient asked for its own gift, this points to the same
  /// recipient.
  final RequestedBy? requestedBy;

  /// A free note about the request.
  final String? requestNote;

  /// Whether the gift is a surprise.
  final bool surprise;

  /// The year the gift belongs to.
  final int year;

  /// Creates a gift.
  const Gift({
    required this.id,
    required this.recipientId,
    required this.title,
    this.giverId,
    this.occasionId,
    required this.status,
    required this.rawStatus,
    this.plannedCents,
    this.actualCents,
    this.store,
    this.url,
    this.note,
    this.size,
    this.requestedBy,
    this.requestNote,
    required this.surprise,
    required this.year,
  });

  /// Reads a gift from a record, or null when the record is deleted or is
  /// missing something mandatory.
  ///
  /// An amount of money out of range is treated as missing: it comes from
  /// another phone and cannot be trusted.
  static Gift? fromRecord(
    SyncRecord record, {
    Set<String> deletedPeople = const {},
  }) {
    if (record.isDeleted) {
      return null;
    }
    final recipientId = _string(record['recipientId']);
    final title = _string(record['title']);
    final rawStatus = _string(record['status']);
    final surprise = _bool(record['surprise']);
    final year = _int(record['year']);
    if (recipientId == null ||
        title == null ||
        rawStatus == null ||
        surprise == null ||
        year == null) {
      return null;
    }
    final requester = RequestedBy.fromFields(record['requestedBy']);
    return Gift(
      id: record.id,
      recipientId: recipientId,
      title: title,
      giverId: _string(record['giverId']),
      occasionId: _string(record['occasionId']),
      status: GiftStatus.fromName(rawStatus),
      rawStatus: rawStatus,
      plannedCents: _cents(record['plannedCents']),
      actualCents: _cents(record['actualCents']),
      store: _string(record['store']),
      url: _string(record['url']),
      note: _string(record['note']),
      size: _string(record['size']),
      requestedBy:
          requester is RequestedByRecipient &&
              deletedPeople.contains(requester.recipientId)
          ? null
          : requester,
      requestNote: _string(record['requestNote']),
      surprise: surprise,
      year: year,
    );
  }

  /// The fields of the gift.
  ///
  /// Every field is written, also the ones that are not there: a null value
  /// is the tombstone of a field that is gone, so a shop that is cleared is
  /// really cleared.
  Map<String, Object?> toFields() {
    final requester = requestedBy;
    return <String, Object?>{
      'recipientId': recipientId,
      'title': title,
      'giverId': giverId,
      'occasionId': occasionId,
      'status': rawStatus,
      'plannedCents': plannedCents,
      'actualCents': actualCents,
      'store': store,
      'url': url,
      'note': note,
      'size': size,
      'requestedBy': requester?.toFields(),
      'requestNote': requestNote,
      'surprise': surprise,
      'year': year,
    };
  }

  /// What the gift costs the house: the real price, or the planned one once
  /// the gift is bought.
  int get spentCents =>
      actualCents ?? (status.isBoughtOrLater ? (plannedCents ?? 0) : 0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Gift &&
          other.id == id &&
          other.recipientId == recipientId &&
          other.title == title &&
          other.giverId == giverId &&
          other.occasionId == occasionId &&
          other.status == status &&
          other.rawStatus == rawStatus &&
          other.plannedCents == plannedCents &&
          other.actualCents == actualCents &&
          other.store == store &&
          other.url == url &&
          other.note == note &&
          other.size == size &&
          other.requestedBy == requestedBy &&
          other.requestNote == requestNote &&
          other.surprise == surprise &&
          other.year == year;

  @override
  int get hashCode => Object.hash(
    id,
    recipientId,
    title,
    giverId,
    occasionId,
    status,
    rawStatus,
    plannedCents,
    actualCents,
    store,
    url,
    note,
    size,
    requestedBy,
    requestNote,
    surprise,
    year,
  );

  @override
  String toString() => 'Gift($id, $title)';
}

/// Totals of money, in cents.
class BudgetTotals {
  /// The amount set by the household, or null when no budget has been set.
  final int? budgetCents;

  /// What is expected to be spent.
  final int plannedCents;

  /// What has been spent.
  final int spentCents;

  /// Planned prices of gifts that have yet to be bought, for occasions and
  /// the household total.
  final int pendingCents;

  /// Creates the totals.
  const BudgetTotals({
    this.budgetCents,
    this.plannedCents = 0,
    this.spentCents = 0,
    this.pendingCents = 0,
  });

  /// The budget left after spending, or null when there is no budget.
  int? get leftCents {
    final budget = budgetCents;
    return budget == null ? null : budget - spentCents;
  }

  /// The budget left after buying the pending gifts at their planned prices.
  int? get leftIfBoughtCents {
    final left = leftCents;
    return left == null ? null : left - pendingCents;
  }

  /// Whether actual spending exceeds the budget.
  bool get isOver => (leftCents ?? 0) < 0;

  /// Adds two sets of totals.
  BudgetTotals operator +(BudgetTotals other) => BudgetTotals(
    budgetCents: budgetCents == null && other.budgetCents == null
        ? null
        : (budgetCents ?? 0) + (other.budgetCents ?? 0),
    plannedCents: plannedCents + other.plannedCents,
    spentCents: spentCents + other.spentCents,
    pendingCents: pendingCents + other.pendingCents,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BudgetTotals &&
          other.budgetCents == budgetCents &&
          other.plannedCents == plannedCents &&
          other.spentCents == spentCents &&
          other.pendingCents == pendingCents;

  @override
  int get hashCode =>
      Object.hash(budgetCents, plannedCents, spentCents, pendingCents);

  @override
  String toString() =>
      'BudgetTotals(budget: $budgetCents, planned: $plannedCents, '
      'spent: $spentCents, pending: $pendingCents)';
}

/// The budget of the list: by recipient, by occasion and the total.
///
/// Only the gifts paid by the house count. What the uncles and the
/// grandparents give is a gift, not an expense.
///
/// Archived occasions do not count in [total], [budgeted],
/// [spentOutsideBudgetCents] or [byRecipient]; [byOccasion] keeps their
/// figures so their own row can still show them.
class Budget {
  /// Planned and spent totals by recipient id, of the gifts of occasions that
  /// are not archived and of the gifts without an occasion.
  final Map<String, BudgetTotals> byRecipient;

  /// Totals by occasion id, including budgets for occasions without gifts and
  /// the archived occasions, which keep their full figures here.
  /// Gifts without an existing occasion go to [noOccasion].
  final Map<String, BudgetTotals> byOccasion;

  /// Household gift totals and the sum of budgets of the occasions that are
  /// not archived, plus the gifts without an occasion.
  final BudgetTotals total;

  /// Ids of the archived occasions: they are in [byOccasion] but not in
  /// [total], [budgeted] or [byRecipient].
  final Set<String> archivedOccasionIds;

  /// Key used for the gifts that do not belong to any occasion.
  static const String noOccasion = '';

  /// Creates the budget.
  const Budget({
    required this.byRecipient,
    required this.byOccasion,
    required this.total,
    this.archivedOccasionIds = const <String>{},
  });

  /// The totals of one recipient, or empty totals when there is none.
  BudgetTotals ofRecipient(String recipientId) =>
      byRecipient[recipientId] ?? const BudgetTotals();

  /// The totals of one occasion, or empty totals when there is none.
  BudgetTotals ofOccasion(String occasionId) =>
      byOccasion[occasionId] ?? const BudgetTotals();

  /// Whether the occasion is archived and so left out of the household
  /// figures.
  bool isArchivedOccasion(String occasionId) =>
      archivedOccasionIds.contains(occasionId);

  /// The sum of the active occasions that have a budget (0 is a valid
  /// budget); archived ones are left out. Its [BudgetTotals.budgetCents] is
  /// null when no active occasion has one. Unlike [total], gifts of occasions
  /// without a budget and gifts without an occasion are left out, so the
  /// budget, the spending and what is left refer to the same gifts.
  BudgetTotals get budgeted {
    var sum = const BudgetTotals();
    for (final entry in byOccasion.entries) {
      if (entry.key != noOccasion &&
          !isArchivedOccasion(entry.key) &&
          entry.value.budgetCents != null) {
        sum += entry.value;
      }
    }
    return sum;
  }

  /// Whether at least one active occasion has a budget.
  bool get hasBudgeted => budgeted.budgetCents != null;

  /// What the household spent on gifts outside [budgeted]: active occasions
  /// without a budget and gifts without an occasion. Archived occasions are
  /// not counted at all.
  int get spentOutsideBudgetCents {
    var spent = 0;
    for (final entry in byOccasion.entries) {
      if (isArchivedOccasion(entry.key)) {
        continue;
      }
      if (entry.key == noOccasion || entry.value.budgetCents == null) {
        spent += entry.value.spentCents;
      }
    }
    return spent;
  }
}

/// How a cell of the family grid looks.
enum GridStatus {
  /// The recipient does not receive gifts in the selected occasions.
  excluded,

  /// Nobody gives anything to that recipient.
  none,

  /// There are gifts that are not bought yet.
  pending,

  /// Every gift is already bought.
  allBought,
}

/// One cell of the family grid: a giver and a recipient.
class GridCell {
  /// Number of gifts.
  final int giftCount;

  /// What the gifts are expected to cost, in cents.
  final int plannedCents;

  /// What the gifts have cost, in cents.
  final int spentCents;

  /// How the cell looks.
  final GridStatus status;

  /// Creates a cell.
  const GridCell({
    this.giftCount = 0,
    this.plannedCents = 0,
    this.spentCents = 0,
    this.status = GridStatus.none,
  });

  /// The amount to show in the cell: what is really spent, or what is planned
  /// when the gift is not bought yet.
  int get cents => spentCents > 0 ? spentCents : plannedCents;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridCell &&
          other.giftCount == giftCount &&
          other.plannedCents == plannedCents &&
          other.spentCents == spentCents &&
          other.status == status;

  @override
  int get hashCode => Object.hash(giftCount, plannedCents, spentCents, status);

  @override
  String toString() =>
      'GridCell($giftCount gifts, $plannedCents planned, $spentCents spent, '
      '$status)';
}

/// The grid of the family: rows are recipients, columns are givers.
class FamilyGrid {
  /// The recipients, in order.
  final List<Recipient> recipients;

  /// Active people kept outside Reparto, for the collapsed section.
  final List<Recipient> outsideReparto;

  /// People in the grid who skip every selected occasion. In All this is
  /// empty, even when a person skips some (or all known) occasions.
  final List<Recipient> excludedRecipients;

  /// The givers, in order.
  final List<Giver> givers;

  /// The cells, by recipient id and then by giver id.
  final Map<String, Map<String, GridCell>> cells;

  /// Key of the gifts whose giver is not in the list of givers.
  ///
  /// Those gifts are shown in a row of their own, the one of the people that
  /// are not assigned yet.
  static const String unassignedGiverId = '';

  /// Creates the grid.
  const FamilyGrid({
    required this.recipients,
    required this.givers,
    required this.cells,
    this.outsideReparto = const <Recipient>[],
    this.excludedRecipients = const <Recipient>[],
  });

  /// The cell of a giver and a recipient. Empty cells are returned too.
  GridCell cell(String recipientId, String giverId) =>
      cells[recipientId]?[giverId] ??
      (excludedRecipients.any((r) => r.id == recipientId)
          ? const GridCell(status: GridStatus.excluded)
          : const GridCell());

  /// The cell of the gifts that have no known giver.
  GridCell unassignedCell(String recipientId) =>
      cell(recipientId, unassignedGiverId);

  /// Whether some gift of the grid has no known giver.
  bool get hasUnassignedGifts =>
      cells.values.any((row) => (row[unassignedGiverId]?.giftCount ?? 0) > 0);
}

/// Two gifts of the same recipient with almost the same name.
class DuplicatePair {
  /// The recipient both gifts are for.
  final String recipientId;

  /// The first gift.
  final Gift first;

  /// The second gift.
  final Gift second;

  /// Creates the pair.
  const DuplicatePair({
    required this.recipientId,
    required this.first,
    required this.second,
  });

  @override
  String toString() =>
      'DuplicatePair($recipientId, ${first.title}, ${second.title})';
}

/// A person offered in a giver picker and their current public link.
class GiverPersonCandidate {
  const GiverPersonCandidate(
    this.person,
    this.giver, {
    required this.needsPublicAdd,
  });

  final Recipient person;

  /// The active giver, an archived giver to recover, or null for a new link.
  final Giver? giver;

  /// A protected gift can use this person only after an explicit public add.
  final bool needsPublicAdd;
}

/// The list of the family seen as typed lists.
///
/// Everything deleted is left out. The lists are sorted by name, or by title
/// for the gifts.
class FamilyView {
  /// The recipients, sorted by name.
  final List<Recipient> recipients;

  /// The active giver columns, sorted by name. A linked person has one
  /// column. In a view including archives, wholly archived groups also
  /// have one representative.
  late final List<Giver> givers;

  /// The occasions, sorted by name.
  final List<Occasion> occasions;

  /// The gifts of the year in view, sorted by title.
  final List<Gift> gifts;

  /// Every gift of the list, of every year, sorted by title.
  ///
  /// The [gifts] list only has the year in view; this one is what
  /// [previousYearsGifts] looks at.
  final List<Gift> allGifts;

  /// Every original giver record, including aliases and archived givers.
  final List<Giver> allGivers;

  /// Whether the grid includes archived giver assignments.
  final bool includeArchived;

  /// Creates the view.
  FamilyView({
    required this.recipients,
    required List<Giver> givers,
    required this.occasions,
    required this.gifts,
    this.allGifts = const <Gift>[],
    List<Giver> allGivers = const <Giver>[],
    this.includeArchived = false,
    Map<String, Recipient>? allRecipientsById,
  }) : allGivers = allGivers.isEmpty ? givers : allGivers,
       allRecipientsById =
           allRecipientsById ??
           Map.unmodifiable({
             for (final person in recipients) person.id: person,
           }) {
    this.givers = _sortedByName([
      for (final giver in giversByOriginalId.values)
        if ((includeArchived || !giver.archived) &&
            resolveGiver(giver.id)?.id == giver.id)
          giver,
    ]);
  }

  /// Every live person, including archived people.
  final Map<String, Recipient> allRecipientsById;

  /// Original records hold the payer and archive state of each gift.
  late final Map<String, Giver> giversByOriginalId = Map.unmodifiable({
    for (final giver in allGivers) giver.id: giver,
  });

  late final Map<String, Giver> _giverByPerson = _indexGiversByPerson();

  Map<String, Giver> _indexGiversByPerson() {
    final byPerson = <String, Giver>{};
    for (final giver in giversByOriginalId.values) {
      final personId = giver.recipientId;
      if (personId == null) continue;
      final existing = byPerson[personId];
      if (existing == null ||
          (existing.archived && !giver.archived) ||
          (existing.archived == giver.archived &&
              giver.id.compareTo(existing.id) < 0)) {
        byPerson[personId] = giver;
      }
    }
    return byPerson;
  }

  /// The active representative, or the archived representative to recover.
  Giver? giverForPerson(String personId) => _giverByPerson[personId];

  /// The current label for a People choice, even before it has a giver.
  /// Returns null if the person no longer exists.
  String? giverForPersonLabel(String personId) =>
      allRecipientsById[personId]?.name;

  /// People that may be added as givers, with an archived giver recoverable
  /// via [giverForPerson] when there is one.
  List<Recipient> giverPeopleFor(String recipientId) => _sortedByName([
    for (final person in allRecipientsById.values)
      if (!person.archived &&
          person.id != recipientId &&
          giverForPerson(person.id)?.archived != false)
        person,
  ]);

  /// For protected gifts, include people who already have an active giver
  /// alongside people who need a separate public add or recovery.
  List<GiverPersonCandidate> giverPersonCandidatesFor(
    String recipientId, {
    required bool protected,
  }) {
    final people = protected
        ? _sortedByName([
            for (final person in allRecipientsById.values)
              if (!person.archived && person.id != recipientId) person,
          ])
        : giverPeopleFor(recipientId);
    return people.map((person) {
      final giver = giverForPerson(person.id);
      return GiverPersonCandidate(
        person,
        giver,
        needsPublicAdd: protected && giver?.archived != false,
      );
    }).toList();
  }

  /// Active giver choices for a gift. An existing self-assignment remains
  /// readable through [resolveGiver] but is not offered as a new choice.
  List<Giver> selectableGiversFor(String recipientId) => [
    for (final giver in givers)
      if (!giver.archived && giver.recipientId != recipientId) giver,
  ];

  /// Resolves an original id to its display representative.
  Giver? resolveGiver(String? id) => giversById[id];

  /// The grid column for this gift. Archived assignments have no cell.
  String? repartoGiverId(Gift gift) {
    if (!includeArchived &&
        giversByOriginalId[gift.giverId]?.archived == true) {
      return null;
    }
    return resolveGiver(gift.giverId)?.id ?? FamilyGrid.unassignedGiverId;
  }

  /// All live records in the same column, including archived aliases.
  Set<String> giverAliasIds(String id) {
    final giver = giversByOriginalId[id];
    if (giver == null) return const {};
    final personId = giver.recipientId;
    if (personId == null) return {id};
    return {
      for (final alias in giversByOriginalId.values)
        if (alias.recipientId == personId) alias.id,
    };
  }

  /// Reads the view of a document.
  ///
  /// Records that are deleted or that do not have everything mandatory are
  /// left out.
  ///
  /// With [year] only the gifts of that year are counted. The people that
  /// are archived are left out too, unless [includeArchived] says the other
  /// way; their gifts do not reach the grid either.
  /// Archiving an occasion leaves its gifts in the view.
  ///
  /// A gift whose person is not there any more (the person was deleted, for
  /// instance on another phone while this one was creating the gift) is left
  /// out, and so is the birthday of that person: nothing is left pointing to a
  /// tombstone. An archived person still exists. Nothing is written, so it
  /// heals by itself. The gifts in [hiddenGiftIds] are left out too: they are
  /// waiting for the "Undo" notice to expire before their tombstone is
  /// written.
  factory FamilyView.fromDoc(
    FamilyDoc doc, {
    int? year,
    bool includeArchived = false,
    Set<String> hiddenGiftIds = const <String>{},
  }) {
    final deletedPeople = <String>{
      for (final record
          in doc.collections[Collections.recipients]?.values ??
              const <SyncRecord>[])
        if (record.isDeleted) record.id,
    };
    final recipients = <Recipient>[];
    final allRecipientsById = <String, Recipient>{};
    for (final record
        in doc.collections[Collections.recipients]?.values ??
            const <SyncRecord>[]) {
      final recipient = Recipient.fromRecord(record);
      if (recipient != null) {
        allRecipientsById[recipient.id] = recipient;
        if (includeArchived || !recipient.archived) recipients.add(recipient);
      }
    }
    final everyGiver = <Giver>[];
    for (final record
        in doc.collections[Collections.givers]?.values ??
            const <SyncRecord>[]) {
      final giver = Giver.fromRecord(record);
      if (giver != null) {
        final person = allRecipientsById[giver.recipientId];
        everyGiver.add(
          person == null ? giver : giver.withPersonDetails(person),
        );
      }
    }
    final occasions = <Occasion>[];
    for (final record
        in doc.collections[Collections.occasions]?.values ??
            const <SyncRecord>[]) {
      final occasion = Occasion.fromRecord(record);
      if (occasion != null &&
          (occasion.kind != OccasionKind.birthday ||
              !deletedPeople.contains(occasion.recipientId))) {
        occasions.add(occasion);
      }
    }
    final everyGift = <Gift>[];
    for (final record
        in doc.collections[Collections.gifts]?.values ?? const <SyncRecord>[]) {
      final gift = Gift.fromRecord(record, deletedPeople: deletedPeople);
      if (gift != null &&
          !deletedPeople.contains(gift.recipientId) &&
          !hiddenGiftIds.contains(gift.id)) {
        everyGift.add(gift);
      }
    }
    final gifts = everyGift
        .where((gift) => year == null || gift.year == year)
        .toList();
    return FamilyView(
      recipients: _sortedByName(recipients),
      givers: const [],
      occasions: _sortedByName(occasions),
      gifts: _sortedByName(gifts),
      allGifts: _sortedByName(everyGift),
      allGivers: _sortedByName(everyGiver),
      includeArchived: includeArchived,
      allRecipientsById: Map.unmodifiable(allRecipientsById),
    );
  }

  /// The gifts of one recipient, sorted by title.
  List<Gift> giftsFor(String recipientId) =>
      gifts.where((gift) => gift.recipientId == recipientId).toList();

  /// The gifts of one recipient from the year before [year], sorted by
  /// title.
  ///
  /// This is the warning "last year they were already given this one". It is
  /// not the warning of a possible duplicate: those two gifts can be from
  /// different people and be perfectly fine.
  List<Gift> previousYearsGifts(String recipientId, int year) {
    // A view built by hand has no list of every year: then the gifts of the
    // view are all there is.
    final source = allGifts.isEmpty ? gifts : allGifts;
    final previous = source
        .where(
          (gift) => gift.recipientId == recipientId && gift.year == year - 1,
        )
        .toList();
    return _sortedByName(previous);
  }

  /// Display representatives keyed by every original id, for history and
  /// filters as well as the active columns.
  late final Map<String, Giver> giversById = Map.unmodifiable({
    for (final giver in giversByOriginalId.values)
      giver.id: _giverByPerson[giver.recipientId] ?? giver,
  });

  /// The recipients by id.
  Map<String, Recipient> get recipientsById => <String, Recipient>{
    for (final recipient in recipients) recipient.id: recipient,
  };

  /// The occasions by id.
  Map<String, Occasion> get occasionsById => <String, Occasion>{
    for (final occasion in occasions) occasion.id: occasion,
  };

  /// The people who can receive gifts: [recipients] without the ones who
  /// only give ([Recipient.noGifts]). For the recipient picker and totals.
  List<Recipient> get giftRecipients => [
    for (final recipient in recipients)
      if (!recipient.noGifts) recipient,
  ];

  /// Active recipients that appear as rows in Reparto, in name order. People
  /// who only give ([Recipient.noGifts]) are never rows.
  List<Recipient> get repartoRecipients => [
    for (final recipient in recipients)
      if (!recipient.archived && recipient.inReparto && !recipient.noGifts)
        recipient,
  ];

  /// Active recipients kept out of Reparto, without deleting their data.
  /// People who only give are not listed: they are not recipients.
  List<Recipient> get outsideReparto => [
    for (final recipient in recipients)
      if (!recipient.archived && !recipient.inReparto && !recipient.noGifts)
        recipient,
  ];

  /// A projection for Reparto lists and totals. Other views (People, gift
  /// history and the household budget) retain all their data.
  ///
  /// Keys are stable occasion ids. Null means All; an empty set selects no
  /// occasions. A group (for example birthdays) supplies all its ids. Gifts
  /// in skipped occasions never count, including when viewing All. Gifts
  /// without an occasion count only in All.
  /// The same filters apply to [allGifts], so history queried on this
  /// projection also respects Reparto exclusions.
  FamilyView forReparto({Set<String>? occasionKeys}) {
    final visible = {for (final r in repartoRecipients) r.id: r};
    bool includes(Gift gift) =>
        visible.containsKey(gift.recipientId) &&
        repartoGiverId(gift) != null &&
        (occasionKeys == null || occasionKeys.contains(gift.occasionId)) &&
        (gift.occasionId == null ||
            !visible[gift.recipientId]!.skipsOccasion(gift.occasionId!));
    return FamilyView(
      recipients: repartoRecipients,
      givers: givers,
      occasions: occasions,
      gifts: gifts.where(includes).toList(),
      allGifts: allGifts.where(includes).toList(),
      allGivers: allGivers,
      includeArchived: includeArchived,
      allRecipientsById: allRecipientsById,
    );
  }

  /// The budget of the list: by recipient, by occasion and the total.
  ///
  /// Only the gifts of the givers that pay from the house are counted,
  /// whatever the recipient is: a gift of the house to a nephew is an
  /// expense too, and a gift asked for by somebody does not make the gift
  /// of somebody else an expense of the house.
  /// Archived occasions keep their own figures in [Budget.byOccasion] but do
  /// not count in the total, the budgeted sum or the recipients.
  Budget budget() {
    final occasionIds = {for (final occasion in occasions) occasion.id};
    final archivedIds = {
      for (final occasion in occasions)
        if (occasion.archived) occasion.id,
    };
    final byRecipient = <String, BudgetTotals>{};
    final byOccasion = <String, BudgetTotals>{};
    var total = const BudgetTotals();
    for (final occasion in occasions) {
      final budgetCents = occasion.budgetCents;
      if (budgetCents == null || occasion.id == Budget.noOccasion) {
        continue;
      }
      final totals = BudgetTotals(budgetCents: budgetCents);
      byOccasion[occasion.id] = totals;
      if (!occasion.archived) {
        total += totals;
      }
    }
    for (final gift in gifts) {
      final giver = giversByOriginalId[gift.giverId];
      if (giver == null || giver.archived || !giver.householdPays) {
        continue;
      }
      final planned = gift.plannedCents ?? 0;
      final spent = gift.spentCents;
      final totals = BudgetTotals(
        plannedCents: planned,
        spentCents: spent,
        pendingCents: gift.status.isBoughtOrLater ? 0 : planned,
      );
      final requested = gift.occasionId ?? Budget.noOccasion;
      final occasionId = occasionIds.contains(requested)
          ? requested
          : Budget.noOccasion;
      _addTotals(byOccasion, occasionId, totals);
      if (archivedIds.contains(occasionId)) {
        // Archived: the row of the occasion keeps it, the household does not.
        continue;
      }
      _addTotals(
        byRecipient,
        gift.recipientId,
        BudgetTotals(plannedCents: planned, spentCents: spent),
      );
      total += totals;
    }
    return Budget(
      byRecipient: byRecipient,
      byOccasion: byOccasion,
      total: total,
      archivedOccasionIds: archivedIds,
    );
  }

  /// The grid of the family: a cell for every giver and recipient.
  ///
  /// The gifts of a giver that is not in the list go to the cell of the
  /// people that are not assigned yet. The gifts of an archived giver do not
  /// reach the grid unless [includeArchived] is enabled.
  /// [occasionKeys] filters by stable occasion ids; null means All.
  FamilyGrid grid({Set<String>? occasionKeys}) {
    final giftsByRecipient = <String, List<Gift>>{};
    for (final gift in forReparto(occasionKeys: occasionKeys).gifts) {
      giftsByRecipient.putIfAbsent(gift.recipientId, () => <Gift>[]).add(gift);
    }
    final cells = <String, Map<String, GridCell>>{};
    final visibleRecipients = repartoRecipients;
    final excluded = <Recipient>[];
    for (final recipient in visibleRecipients) {
      if (occasionKeys != null &&
          occasionKeys.isNotEmpty &&
          occasionKeys.every(recipient.skipsOccasion)) {
        excluded.add(recipient);
        cells[recipient.id] = {
          for (final giver in givers)
            giver.id: const GridCell(status: GridStatus.excluded),
        };
        continue;
      }
      final byGiver = <String, List<Gift>>{};
      for (final gift in giftsByRecipient[recipient.id] ?? const <Gift>[]) {
        final id = repartoGiverId(gift);
        if (id == null) continue;
        byGiver.putIfAbsent(id, () => <Gift>[]).add(gift);
      }
      final row = <String, GridCell>{};
      for (final giver in givers) {
        row[giver.id] = _cellOf(byGiver[giver.id] ?? const <Gift>[]);
      }
      final unassigned = byGiver[FamilyGrid.unassignedGiverId];
      if (unassigned != null) {
        row[FamilyGrid.unassignedGiverId] = _cellOf(unassigned);
      }
      cells[recipient.id] = row;
    }
    return FamilyGrid(
      recipients: visibleRecipients,
      givers: givers,
      cells: cells,
      outsideReparto: outsideReparto,
      excludedRecipients: excluded,
    );
  }

  /// Pairs of gifts of the same recipient with almost the same name.
  List<DuplicatePair> possibleDuplicates() {
    final pairs = <DuplicatePair>[];
    for (final recipient in recipients) {
      final giftsOfRecipient = giftsFor(recipient.id);
      // Every title is normalized once, not once per pair.
      final titles = <String, String>{
        for (final gift in giftsOfRecipient)
          gift.id: _normalizeTitle(gift.title),
      };
      for (var i = 0; i < giftsOfRecipient.length; i++) {
        for (var j = i + 1; j < giftsOfRecipient.length; j++) {
          final first = giftsOfRecipient[i];
          final second = giftsOfRecipient[j];
          if (_areSimilarTitles(titles[first.id]!, titles[second.id]!)) {
            pairs.add(
              DuplicatePair(
                recipientId: recipient.id,
                first: first,
                second: second,
              ),
            );
          }
        }
      }
    }
    return pairs;
  }
}

/// A cell from the gifts of one giver for one recipient.
GridCell _cellOf(List<Gift> gifts) {
  if (gifts.isEmpty) {
    return const GridCell();
  }
  var planned = 0;
  var spent = 0;
  var allBought = true;
  for (final gift in gifts) {
    planned += gift.plannedCents ?? 0;
    spent += gift.spentCents;
    if (!gift.status.isBoughtOrLater) {
      allBought = false;
    }
  }
  return GridCell(
    giftCount: gifts.length,
    plannedCents: planned,
    spentCents: spent,
    status: allBought ? GridStatus.allBought : GridStatus.pending,
  );
}

/// Adds [totals] to the bucket [key] of [buckets].
void _addTotals(
  Map<String, BudgetTotals> buckets,
  String key,
  BudgetTotals totals,
) {
  buckets[key] = (buckets[key] ?? const BudgetTotals()) + totals;
}

/// Sorts a list of named things by name, ignoring the case.
List<T> _sortedByName<T extends Object>(List<T> items) {
  final sorted = List<T>.of(items);
  sorted.sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
  return sorted;
}

/// The text used to sort a recipient, giver, occasion or gift.
String _sortKey(Object item) {
  if (item is Recipient) {
    return item.name.toLowerCase();
  }
  if (item is Giver) {
    return item.name.toLowerCase();
  }
  if (item is Occasion) {
    return item.name.toLowerCase();
  }
  if (item is Gift) {
    return item.title.toLowerCase();
  }
  return '';
}

/// Whether two titles are almost the same.
///
/// The titles come already normalized: no case, no accents and no spaces.
bool _areSimilarTitles(String a, String b) {
  if (a.isEmpty || b.isEmpty) {
    return false;
  }
  if (a == b) {
    return true;
  }
  final shorter = a.length <= b.length ? a : b;
  final longer = a.length <= b.length ? b : a;
  if (shorter.length >= 5 && longer.contains(shorter)) {
    return true;
  }
  final threshold = _duplicateThreshold(shorter.length);
  if (longer.length - shorter.length > threshold) {
    return false;
  }
  if (a.codeUnitAt(0) != b.codeUnitAt(0)) {
    // Two titles that do not even start the same are not the same gift.
    return false;
  }
  return _levenshtein(a, b) <= threshold;
}

/// How different two titles can be and still be the same gift.
///
/// The longer the title, the more differences it takes: two short titles
/// that are almost the same are usually two different gifts, and two long
/// ones can be the same gift with a word more or less.
int _duplicateThreshold(int shorterLength) {
  if (shorterLength < 8) {
    return 1;
  }
  if (shorterLength <= 14) {
    return 2;
  }
  return 3;
}

/// The letters of a title without case, accents or spaces.
String _normalizeTitle(String title) {
  final buffer = StringBuffer();
  for (final rune in title.toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    final plain = _accents[character] ?? character;
    for (final plainRune in plain.runes) {
      if (!_isWhitespace(plainRune)) {
        buffer.writeCharCode(plainRune);
      }
    }
  }
  return buffer.toString();
}

/// Whether the rune is a space or a tab.
bool _isWhitespace(int rune) =>
    rune == 0x20 || rune == 0x09 || rune == 0x0a || rune == 0x0d;

/// The letters of the latin alphabet with their accent.
const Map<String, String> _accents = <String, String>{
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'ē': 'e',
  'ę': 'e',
  'ė': 'e',
  'ě': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ī': 'i',
  'į': 'i',
  'ı': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ø': 'o',
  'ō': 'o',
  'ő': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ū': 'u',
  'ů': 'u',
  'ű': 'u',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ņ': 'n',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ý': 'y',
  'ÿ': 'y',
  'š': 's',
  'ś': 's',
  'ş': 's',
  'ș': 's',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
  'ď': 'd',
  'đ': 'd',
  'ð': 'd',
  'þ': 'th',
  'ł': 'l',
  'ĺ': 'l',
  'ļ': 'l',
  'ŀ': 'l',
  'ğ': 'g',
  'ģ': 'g',
  'ĝ': 'g',
  'ġ': 'g',
  'ħ': 'h',
  'ĥ': 'h',
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
  'µ': 'u',
};

/// The number of letters to change to turn [a] into [b].
int _levenshtein(String a, String b) {
  if (a == b) {
    return 0;
  }
  if (a.isEmpty) {
    return b.length;
  }
  if (b.isEmpty) {
    return a.length;
  }
  var previous = List<int>.generate(b.length + 1, (index) => index);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final deletion = current[j - 1] + 1;
      final insertion = previous[j] + 1;
      final substitution = previous[j - 1] + cost;
      var best = deletion;
      if (insertion < best) {
        best = insertion;
      }
      if (substitution < best) {
        best = substitution;
      }
      current[j] = best;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// Reads a string field.
String? _string(Object? value) => value is String ? value : null;

/// Reads a number field as an integer.
int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}

/// Reads a boolean field.
bool? _bool(Object? value) => value is bool ? value : null;

/// Reads a month, from 1 to 12.
///
/// A month out of range comes from another phone and is treated as missing.
int? _month(Object? value) {
  final month = _int(value);
  if (month == null || month < 1 || month > 12) {
    return null;
  }
  return month;
}

/// Reads a day, from 1 to 31.
///
/// A day out of range comes from another phone and is treated as missing.
int? _day(Object? value) {
  final day = _int(value);
  if (day == null || day < 1 || day > 31) {
    return null;
  }
  return day;
}

/// Biggest amount of money a gift or occasion budget can have, in cents.
const int kMaxCents = 1000000000;

/// Reads an amount of money in cents.
///
/// An amount out of range comes from another phone and is treated as
/// missing.
int? _cents(Object? value) {
  final cents = _int(value);
  if (cents == null || cents < 0 || cents > kMaxCents) {
    return null;
  }
  return cents;
}
