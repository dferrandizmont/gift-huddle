import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/model.dart';
import '../../family/application/family_providers.dart';

/// Cuánto lleva comprado una persona de su próxima ocasión.
typedef PersonCompletion = ({
  /// Regalos ya comprados (comprado, llegó, envuelto o entregado).
  int bought,

  /// Regalos de la ocasión que no son una idea.
  int total,

  /// Todos comprados y al menos uno que no es idea.
  bool complete,

  /// La próxima ocasión con regalos de esta persona, o `null` si no hay.
  Occasion? occasion,
});

/// Lo que lleva comprado [personId] de su próxima ocasión (§2.11 de
/// la guía de movimiento).
///
/// - La próxima ocasión es la más cercana, de las que no han pasado, que tiene
///   algún regalo de esta persona que no sea una idea.
/// - Las **ideas no cuentan**: todavía no son regalos.
/// - Decidido cuenta como pendiente.
/// - Está completa si hay al menos un regalo y todos están comprados.
final personCompletionProvider = Provider.family<PersonCompletion, String>((
  ref,
  personId,
) {
  final gifts = [
    for (final g in ref.watch(familyViewProvider).giftsFor(personId))
      if (g.status != GiftStatus.idea && g.occasionId != null) g,
  ];
  for (final next in ref.watch(upcomingOccasionsProvider)) {
    final mine = [
      for (final g in gifts)
        if (g.occasionId == next.occasion.id) g,
    ];
    if (mine.isEmpty) {
      continue;
    }
    final bought = mine.where((g) => g.status.isBoughtOrLater).length;
    return (
      bought: bought,
      total: mine.length,
      complete: bought == mine.length,
      occasion: next.occasion,
    );
  }
  return (bought: 0, total: 0, complete: false, occasion: null);
});

/// Quién acaba de recibir una acción del usuario que puede completarle (la
/// casilla de estado o el selector). La cabecera solo celebra si el cambio de
/// «completa» llega con esto armado; si no, vino por sincronización.
typedef CelebrationArm = ({String personId, DateTime at});

/// Cuánto vale un armado.
const Duration kCelebrationArmWindow = Duration(seconds: 3);

/// El armado de la celebración (`celebrationArmedProvider`).
class CelebrationArmed extends Notifier<CelebrationArm?> {
  @override
  CelebrationArm? build() => null;

  /// Arma la celebración de [personId] justo antes de guardar el cambio.
  void arm(String personId) => state = (personId: personId, at: clock.now());

  /// Si la celebración de [personId] sigue armada, y la desarma.
  bool consume(String personId) {
    final armed = state;
    if (armed == null) {
      return false;
    }
    final fresh =
        armed.personId == personId &&
        clock.now().difference(armed.at) <= kCelebrationArmWindow;
    state = null;
    return fresh;
  }
}

/// Dónde se arma la celebración de una persona.
final celebrationArmedProvider =
    NotifierProvider<CelebrationArmed, CelebrationArm?>(CelebrationArmed.new);
