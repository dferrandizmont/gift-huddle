import '../../../core/sync/model.dart';
import 'chinese_new_year.dart';

/// Los tipos de ocasión que se ofrecen al crear una, en el orden de la lista.
/// El cumpleaños no está: sale de la fecha de cada persona.
const List<OccasionKind> kCreatableKinds = [
  OccasionKind.tio,
  OccasionKind.santa,
  OccasionKind.kings,
  OccasionKind.chineseNewYear,
  OccasionKind.wedding,
  OccasionKind.anniversary,
  OccasionKind.santJordi,
  OccasionKind.valentine,
  OccasionKind.baptism,
  OccasionKind.communion,
  OccasionKind.graduation,
  OccasionKind.custom,
];

/// Lo que se rellena solo al elegir un tipo de ocasión.
class OccasionPreset {
  /// Crea los valores de un tipo.
  const OccasionPreset({
    this.month,
    this.day,
    required this.recurring,
    this.autoDate = false,
  });

  /// Mes y día fijos del tipo, o `null` si los elige la persona.
  final int? month;
  final int? day;

  /// Si la fiesta se repite cada año.
  final bool recurring;

  /// Si la fecha se calcula sola (Año Nuevo Chino) y no se elige.
  final bool autoDate;

  /// Si el tipo trae su fecha.
  bool get hasDate => month != null && day != null || autoDate;

  /// El mes y el día que le tocan desde [now]: los fijos o, en el Año Nuevo
  /// Chino, los de su próxima celebración. `null` si hay que elegirlos.
  ({int month, int day})? dateFrom(DateTime now) {
    if (autoDate) {
      final next = nextChineseNewYear(now);
      return (month: next.month, day: next.day);
    }
    final m = month;
    final d = day;
    return m == null || d == null ? null : (month: m, day: d);
  }
}

/// Los valores de serie de [kind].
OccasionPreset presetFor(OccasionKind kind) => switch (kind) {
  OccasionKind.tio => const OccasionPreset(month: 12, day: 24, recurring: true),
  OccasionKind.santa => const OccasionPreset(
    month: 12,
    day: 25,
    recurring: true,
  ),
  OccasionKind.kings => const OccasionPreset(month: 1, day: 6, recurring: true),
  OccasionKind.chineseNewYear => const OccasionPreset(
    recurring: true,
    autoDate: true,
  ),
  OccasionKind.santJordi => const OccasionPreset(
    month: 4,
    day: 23,
    recurring: true,
  ),
  OccasionKind.valentine => const OccasionPreset(
    month: 2,
    day: 14,
    recurring: true,
  ),
  OccasionKind.anniversary => const OccasionPreset(recurring: true),
  OccasionKind.wedding ||
  OccasionKind.baptism ||
  OccasionKind.communion ||
  OccasionKind.graduation => const OccasionPreset(recurring: false),
  OccasionKind.birthday ||
  OccasionKind.custom => const OccasionPreset(recurring: true),
};
