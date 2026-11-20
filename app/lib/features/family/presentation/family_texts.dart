import '../../../core/format/dates.dart';
import '../../../core/format/money.dart';
import '../../../core/sync/model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_ca.dart';
import '../../../l10n/app_localizations_en.dart';
import '../../../l10n/app_localizations_es.dart';
import '../domain/family_errors.dart';

/// El texto del importe de un regalo: «49,99 € (previsto 55 €)», «180 €», o
/// `null` si no tiene precio.
String? giftPriceText(AppLocalizations l10n, Gift gift) {
  final actual = gift.actualCents;
  final planned = gift.plannedCents;
  final locale = l10n.localeName;
  if (actual != null && planned != null && actual != planned) {
    return l10n.giftPriceActualPlanned(
      formatCents(actual, locale),
      formatCents(planned, locale),
    );
  }
  final cents = actual ?? planned;
  return cents == null ? null : formatCents(cents, locale);
}

/// Los nombres de serie de quién regala («Nosotros» y sus traducciones), para
/// reconocerlos aunque se guardaran en otro idioma.
final Set<String> _seedGiverNames = <String>{
  for (final l in _everyLanguage) ...<String>[
    l.giverUs,
    l.obGiverGrandparents,
    l.obGiverUncles,
    l.obGiverFriends,
  ],
};

/// Traduce al idioma activo el nombre guardado de quién regala cuando es el de
/// serie: si el nombre guardado coincide exactamente con alguna de las
/// traducciones de `giverUs` (es, ca, en), se muestra la del idioma activo.
/// Si se renombró, se muestra el nombre guardado. Función pura.
String giverDisplayName(AppLocalizations l10n, String storedName) {
  final trimmed = storedName.trim();
  if (trimmed.isEmpty) {
    return storedName;
  }
  if (!_seedGiverNames.contains(trimmed)) {
    return storedName;
  }
  // Reconoce qué nombre de serie es, para traducirlo a la lengua activa en
  // lugar de caer siempre en «Nosotros».
  for (final l in _everyLanguage) {
    if (trimmed == l.giverUs) {
      return l10n.giverUs;
    }
    if (trimmed == l.obGiverGrandparents) {
      return l10n.obGiverGrandparents;
    }
    if (trimmed == l.obGiverUncles) {
      return l10n.obGiverUncles;
    }
    if (trimmed == l.obGiverFriends) {
      return l10n.obGiverFriends;
    }
  }
  return storedName;
}

/// Quién regala: su nombre (traducido si es el de serie), o «Sin asignar».
String giverNameFor(AppLocalizations l10n, Giver? giver) {
  if (giver == null) return l10n.giverUnassigned;
  return giver.recipientId == null
      ? giverDisplayName(l10n, giver.name)
      : giver.name;
}

/// La edad de una persona escrita, o `null` si no se sabe su año.
String? ageText(AppLocalizations l10n, Recipient person, DateTime now) {
  final age = ageOf(person, now);
  return age == null ? null : l10n.ageYears(age);
}

/// El resumen de un envío importado: «3 regalos nuevos, 2 cambiados».
String importSummaryText(AppLocalizations l10n, ImportSummary summary) {
  final pieces = <String>[
    if (summary.giftsAdded > 0) l10n.importAdded(summary.giftsAdded),
    if (summary.giftsChanged > 0) l10n.importChanged(summary.giftsChanged),
    if (summary.giftsDeleted > 0) l10n.importDeleted(summary.giftsDeleted),
  ];
  if (pieces.isNotEmpty) {
    return pieces.join(', ');
  }
  return summary.docChanged ? l10n.incomingOtherChanges : l10n.incomingNothing;
}

/// Los tres idiomas de la app, para reconocer los nombres de serie que
/// guardaron las versiones anteriores (en el idioma del móvil que los creó).
final List<AppLocalizations> _everyLanguage = <AppLocalizations>[
  AppLocalizationsEs(),
  AppLocalizationsCa(),
  AppLocalizationsEn(),
];

/// Nombres de serie que tuvo la ocasión de Navidad (`OccasionKind.santa`)
/// antes del 16-11-2026 (commit 44737c4), en es, ca y en. Las ocasiones que
/// guardaron las versiones anteriores siguen con ese nombre y se reconocen
/// como de serie, así que se ven como «Navidad» en el idioma del móvil.
const List<String> kLegacySantaOccasionNames = <String>[
  'Papá Noel',
  'Pare Noel',
  'Santa Claus',
];

/// Si el nombre de [occasion] es el de serie: vacío (marcador) o, por
/// compatibilidad, el nombre de su tipo en cualquiera de los tres idiomas
/// (en un cumpleaños, el de «cumpleaños de» la persona [personName]).
bool hasSeedOccasionName(Occasion occasion, {String? personName}) {
  final stored = occasion.name.trim();
  if (stored.isEmpty) {
    return true;
  }
  if (occasion.kind == OccasionKind.santa &&
      kLegacySantaOccasionNames.contains(stored)) {
    return true;
  }
  switch (occasion.kind) {
    case OccasionKind.custom:
      return false;
    case OccasionKind.birthday:
      return personName != null &&
          _everyLanguage.any((l) => l.occasionBirthdayOf(personName) == stored);
    default:
      return _everyLanguage.any(
        (l) => occasionKindLabel(l, occasion.kind) == stored,
      );
  }
}

/// El nombre con que se enseña una ocasión: el que le puso la persona o, si es
/// de serie, el de su tipo en el idioma de este móvil («Cumpleaños de Nora»
/// en los cumpleaños; [personName] es quien cumple).
String occasionTitle(
  AppLocalizations l10n,
  Occasion occasion, {
  String? personName,
}) {
  if (!hasSeedOccasionName(occasion, personName: personName)) {
    return occasion.name;
  }
  if (occasion.kind == OccasionKind.birthday && personName != null) {
    return l10n.occasionBirthdayOf(personName);
  }
  return occasionKindLabel(l10n, occasion.kind);
}

/// Pone nombre a las ocasiones según las personas de la familia.
class OccasionLabels {
  /// Crea el nombrador con las personas por id.
  const OccasionLabels(this.l10n, this.people);

  /// El idioma de este móvil.
  final AppLocalizations l10n;

  /// Las personas por id (también las archivadas).
  final Map<String, Recipient> people;

  /// El nombre de [occasion].
  String of(Occasion occasion) => occasionTitle(
    l10n,
    occasion,
    personName: people[occasion.recipientId]?.name,
  );
}

/// El título de la cuenta atrás: «días para Reyes», «días para el cumpleaños
/// de Nora».
String countdownTitleFor(
  AppLocalizations l10n,
  Occasion occasion,
  int days,
  Map<String, Recipient> recipientsById,
) {
  if (occasion.kind == OccasionKind.birthday) {
    final person = recipientsById[occasion.recipientId];
    return l10n.countdownDaysForBirthday(
      days,
      person?.name ?? occasionTitle(l10n, occasion),
    );
  }
  return l10n.countdownDaysFor(days, occasionTitle(l10n, occasion));
}

/// El nombre de un tipo de ocasión («Boda», «Reyes»...), que también es el
/// nombre con que se propone la ocasión al crearla. Para «Otra» sale «Otra»;
/// el nombre de la ocasión lo escribe la persona.
String occasionKindLabel(AppLocalizations l10n, OccasionKind kind) =>
    switch (kind) {
      OccasionKind.tio => l10n.occasionNameTio,
      OccasionKind.santa => l10n.occasionNameSanta,
      OccasionKind.kings => l10n.occasionNameKings,
      OccasionKind.birthday => l10n.familyChipBirthdays,
      OccasionKind.chineseNewYear => l10n.occasionKindChineseNewYear,
      OccasionKind.wedding => l10n.occasionKindWedding,
      OccasionKind.anniversary => l10n.occasionKindAnniversary,
      OccasionKind.santJordi => l10n.occasionKindSantJordi,
      OccasionKind.valentine => l10n.occasionKindValentine,
      OccasionKind.baptism => l10n.occasionKindBaptism,
      OccasionKind.communion => l10n.occasionKindCommunion,
      OccasionKind.graduation => l10n.occasionKindGraduation,
      OccasionKind.custom => l10n.occasionKindCustom,
    };

/// El nombre de uno de los colores de una ocasión «Otra».
String occasionColorLabel(AppLocalizations l10n, String name) => switch (name) {
  'lavender' => l10n.accentLavender,
  'sage' => l10n.accentSage,
  'peach' => l10n.accentPeach,
  'sky' => l10n.accentSky,
  'rose' => l10n.accentRose,
  'butter' => l10n.accentButter,
  'teal' => l10n.occasionColorTeal,
  'slate' => l10n.occasionColorSlate,
  _ => name,
};

/// El nombre de uno de los iconos de una ocasión «Otra».
String occasionIconLabel(AppLocalizations l10n, String name) => switch (name) {
  'star' => l10n.occasionIconStar,
  'heart' => l10n.occasionIconHeart,
  'home' => l10n.occasionIconHome,
  'trip' => l10n.occasionIconTrip,
  'school' => l10n.occasionIconSchool,
  'pets' => l10n.occasionIconPets,
  'baby' => l10n.occasionIconBaby,
  'work' => l10n.occasionIconWork,
  'music' => l10n.occasionIconMusic,
  'sport' => l10n.occasionIconSport,
  'flower' => l10n.occasionIconFlower,
  'party' => l10n.occasionIconParty,
  _ => name,
};
