import 'package:uuid/uuid.dart';

import '../../../core/sync/model.dart';
import '../domain/next_occasion.dart';

const Uuid _uuid = Uuid();

/// Un id nuevo para una persona, quien regala, ocasión o regalo.
String newId() => _uuid.v4();

/// Si al regalo todavía le falta comprarlo: es solo una idea o está decidido.
bool needsBuying(Gift gift) => gift.status.index < GiftStatus.bought.index;

/// Si el regalo está en casa y sin envolver.
bool needsWrapping(Gift gift) => gift.status == GiftStatus.arrived;

/// Valor del filtro de quien regala para los regalos sin nadie asignado.
const String kUnassignedGiver = '';

/// Los filtros de la lista de una persona.
class GiftFilter {
  /// Crea un filtro; sin argumentos no filtra nada.
  const GiftFilter({
    this.occasionId,
    this.giverId,
    this.status,
    this.needsBuy = false,
    this.needsWrap = false,
  });

  /// Solo los regalos de esta ocasión; [kNoOccasion] para los que no tienen.
  final String? occasionId;

  /// Solo los de quien regala; [kUnassignedGiver] para los sin asignar.
  final String? giverId;

  /// Solo los que están en este estado.
  final GiftStatus? status;

  /// Solo los que faltan por comprar.
  final bool needsBuy;

  /// Solo los que faltan por envolver.
  final bool needsWrap;

  /// Valor de [occasionId] para los regalos sin ocasión.
  static const String kNoOccasion = '';

  /// Si hay algún filtro puesto.
  bool get isActive =>
      occasionId != null ||
      giverId != null ||
      status != null ||
      needsBuy ||
      needsWrap;

  /// Cuántos filtros hay puestos.
  int get count =>
      (occasionId != null ? 1 : 0) +
      (giverId != null ? 1 : 0) +
      (status != null ? 1 : 0) +
      (needsBuy ? 1 : 0) +
      (needsWrap ? 1 : 0);

  /// Si el regalo pasa todos los filtros.
  bool matches(Gift gift) {
    if (occasionId != null && (gift.occasionId ?? kNoOccasion) != occasionId) {
      return false;
    }
    if (giverId != null && (gift.giverId ?? kUnassignedGiver) != giverId) {
      return false;
    }
    if (status != null && gift.status != status) {
      return false;
    }
    if (needsBuy && !needsBuying(gift)) {
      return false;
    }
    if (needsWrap && !needsWrapping(gift)) {
      return false;
    }
    return true;
  }

  /// Copia cambiando lo que se pide. Un `clear…` quita ese filtro.
  GiftFilter copyWith({
    String? occasionId,
    bool clearOccasion = false,
    String? giverId,
    bool clearGiver = false,
    GiftStatus? status,
    bool clearStatus = false,
    bool? needsBuy,
    bool? needsWrap,
  }) => GiftFilter(
    occasionId: clearOccasion ? null : (occasionId ?? this.occasionId),
    giverId: clearGiver ? null : (giverId ?? this.giverId),
    status: clearStatus ? null : (status ?? this.status),
    needsBuy: needsBuy ?? this.needsBuy,
    needsWrap: needsWrap ?? this.needsWrap,
  );
}

/// Los pares de regalos casi iguales en que entra [candidate] si se guarda.
///
/// Compara con los demás regalos de la misma persona, sin contar el propio
/// regalo si ya existe.
List<DuplicatePair> duplicatesOf(FamilyView view, Gift candidate) {
  final others = [
    for (final gift in view.gifts)
      if (gift.id != candidate.id) gift,
  ];
  final probe = FamilyView(
    recipients: [
      for (final r in view.recipients)
        if (r.id == candidate.recipientId) r,
    ],
    givers: view.givers,
    occasions: view.occasions,
    gifts: [
      for (final gift in others)
        if (gift.recipientId == candidate.recipientId) gift,
      candidate,
    ],
  );
  return [
    for (final pair in probe.possibleDuplicates())
      if (pair.first.id == candidate.id || pair.second.id == candidate.id) pair,
  ];
}

/// Las ocasiones por orden de próxima fecha; las que ya pasaron, al final.
List<Occasion> occasionsByNextDate(Iterable<Occasion> occasions, DateTime now) {
  final dated = <(Occasion, DateTime?)>[
    for (final o in occasions) (o, nextDateOf(o, now)),
  ];
  dated.sort((a, b) {
    final da = a.$2;
    final db = b.$2;
    if (da == null && db == null) {
      return a.$1.name.toLowerCase().compareTo(b.$1.name.toLowerCase());
    }
    if (da == null) {
      return 1;
    }
    if (db == null) {
      return -1;
    }
    final byDate = da.compareTo(db);
    return byDate != 0
        ? byDate
        : a.$1.name.toLowerCase().compareTo(b.$1.name.toLowerCase());
  });
  return [for (final entry in dated) entry.$1];
}

/// Días que faltan para [occasion] desde [now], o `null` si ya pasó.
int? daysUntil(Occasion occasion, DateTime now) {
  final date = nextDateOf(occasion, now);
  if (date == null) {
    return null;
  }
  return DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
}

/// Cuánto gasta y prevé la casa en un grupo de regalos.
BudgetTotals totalsOf(Iterable<Gift> gifts) {
  var planned = 0;
  var spent = 0;
  for (final gift in gifts) {
    planned += gift.plannedCents ?? 0;
    spent += gift.spentCents;
  }
  return BudgetTotals(plannedCents: planned, spentCents: spent);
}
