import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/model.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/gift_logic.dart';

/// Los carriles del tablero: lo que le falta a cada regalo
/// (la guía de diseño de escritorio, A). Salen de los estados que ya
/// tiene el modelo, sin campos nuevos.
enum BoardLane {
  /// Todavía es una idea: falta decidirlo.
  decide(GiftStatus.idea),

  /// Decidido: falta comprarlo.
  buy(GiftStatus.decided),

  /// Comprado: falta que llegue.
  arrive(GiftStatus.bought),

  /// En casa: falta envolverlo.
  wrap(GiftStatus.arrived),

  /// Envuelto: listo para entregar.
  ready(GiftStatus.wrapped);

  const BoardLane(this.status);

  /// El estado de los regalos de este carril.
  final GiftStatus status;

  /// El carril de un regalo en [status], o `null` si ya se entregó (ya no
  /// falta nada).
  static BoardLane? of(GiftStatus status) {
    for (final lane in values) {
      if (lane.status == status) {
        return lane;
      }
    }
    return null;
  }
}

/// Los regalos agrupados por carril, cada uno por orden de próxima ocasión y,
/// dentro de la misma, por título.
typedef BoardGroups = Map<BoardLane, List<Gift>>;

/// Reparte [gifts] en carriles. Los entregados no salen.
BoardGroups groupIntoLanes(
  Iterable<Gift> gifts,
  List<Occasion> occasions,
  DateTime now,
) {
  final rank = <String, int>{};
  final ordered = occasionsByNextDate(occasions, now);
  for (var i = 0; i < ordered.length; i++) {
    rank[ordered[i].id] = i;
  }
  int rankOf(Gift g) => rank[g.occasionId] ?? ordered.length;
  final groups = <BoardLane, List<Gift>>{
    for (final lane in BoardLane.values) lane: <Gift>[],
  };
  for (final gift in gifts) {
    final lane = BoardLane.of(gift.status);
    if (lane != null) {
      groups[lane]!.add(gift);
    }
  }
  for (final list in groups.values) {
    list.sort((a, b) {
      final byOccasion = rankOf(a).compareTo(rankOf(b));
      if (byOccasion != 0) {
        return byOccasion;
      }
      final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
    });
  }
  return groups;
}

/// Los regalos de las personas activas (sin archivadas), de todos los años.
final boardGiftsProvider = Provider<List<Gift>>((ref) {
  final view = ref.watch(familyViewProvider);
  final active = {for (final r in view.recipients) r.id};
  return [
    for (final gift in view.gifts)
      if (active.contains(gift.recipientId)) gift,
  ];
});

/// Los carriles del tablero. Con una ocasión ([occasionId]), solo sus regalos.
final boardLanesProvider = Provider.family<BoardGroups, String?>((
  ref,
  occasionId,
) {
  final gifts = ref.watch(boardGiftsProvider);
  final occasions = ref.watch(occasionsProvider);
  return groupIntoLanes(
    [
      for (final gift in gifts)
        if (occasionId == null || gift.occasionId == occasionId) gift,
    ],
    occasions,
    clock.now(),
  );
});

/// Cuántos regalos hay y cuántos ya están comprados (o más allá).
class BoardCount {
  /// Crea el recuento.
  const BoardCount({required this.bought, required this.total});

  /// Los comprados, llegados, envueltos o entregados.
  final int bought;

  /// Todos.
  final int total;
}

/// El recuento de [gifts].
BoardCount countOf(Iterable<Gift> gifts) {
  var bought = 0;
  var total = 0;
  for (final gift in gifts) {
    total++;
    if (gift.status.isBoughtOrLater) {
      bought++;
    }
  }
  return BoardCount(bought: bought, total: total);
}

/// El recuento de todos los regalos de las personas activas.
final boardCountProvider = Provider<BoardCount>(
  (ref) => countOf(ref.watch(boardGiftsProvider)),
);

/// El recuento de una persona.
final boardPersonCountProvider = Provider.family<BoardCount, String>(
  (ref, personId) => countOf([
    for (final gift in ref.watch(boardGiftsProvider))
      if (gift.recipientId == personId) gift,
  ]),
);

/// El recuento de una ocasión.
final boardOccasionCountProvider = Provider.family<BoardCount, String>(
  (ref, occasionId) => countOf([
    for (final gift in ref.watch(boardGiftsProvider))
      if (gift.occasionId == occasionId) gift,
  ]),
);

/// Lo que se ha gastado o se prevé gastar en [gifts], en céntimos.
int centsOf(Iterable<Gift> gifts) {
  var cents = 0;
  for (final gift in gifts) {
    cents += gift.actualCents ?? gift.plannedCents ?? 0;
  }
  return cents;
}
