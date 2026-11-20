import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/motion/rect_flight.dart';
import '../../../core/sync/model.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../gifts/application/person_completion.dart';
import '../application/board_lanes.dart';

/// El nombre de un carril.
String boardLaneTitle(AppLocalizations l10n, BoardLane lane) => switch (lane) {
  BoardLane.decide => l10n.boardLaneDecide,
  BoardLane.buy => l10n.boardLaneBuy,
  BoardLane.arrive => l10n.boardLaneArrive,
  BoardLane.wrap => l10n.boardLaneWrap,
  BoardLane.ready => l10n.boardLaneReady,
};

/// La clave con la que vuela la fila de un regalo de un carril a otro.
Object boardGiftFlightKey(String giftId) => ('board-gift', giftId);

/// Lo que lleva una tarjeta mientras se arrastra de un carril a otro.
class BoardDragData {
  /// Crea los datos de la tarjeta de [gift].
  BoardDragData(this.gift);

  /// El regalo (el último dato que se conoce de él).
  Gift gift;

  /// Lo que mide la tarjeta en la ventana (con la escala de interfaz); se
  /// anota al empezar a arrastrar y sirve para que, al soltar, la tarjeta
  /// vuele de donde se soltó a su sitio.
  Size? size;
}

/// Dónde está cada fila de regalo del tablero, para saber de dónde sale la
/// tarjeta que se mueve con el teclado o con un lector de pantalla (el vuelo
/// la lleva de su sitio al del carril nuevo).
class BoardRowAnchors {
  final Map<String, BuildContext> _rows = <String, BuildContext>{};

  /// Anota la fila de [giftId].
  void register(String giftId, BuildContext context) => _rows[giftId] = context;

  /// Quita la fila de [giftId] si sigue siendo la de [context] (la fila que se
  /// va no borra a la que llega).
  void unregister(String giftId, BuildContext context) {
    if (identical(_rows[giftId], context)) {
      _rows.remove(giftId);
    }
  }

  /// El rectángulo de la fila de [giftId] en la ventana, o `null` si no se ve.
  Rect? rectOf(String giftId) {
    final context = _rows[giftId];
    return context == null ? null : globalRectOf(context);
  }
}

/// Las filas del tablero.
final boardRowAnchorsProvider = Provider<BoardRowAnchors>(
  (ref) => BoardRowAnchors(),
);

/// Anota su hijo como la fila de [giftId] mientras esté en pantalla.
class BoardRowAnchor extends ConsumerStatefulWidget {
  /// Crea el ancla.
  const BoardRowAnchor({super.key, required this.giftId, required this.child});

  /// El regalo de la fila.
  final String giftId;

  /// La fila.
  final Widget child;

  @override
  ConsumerState<BoardRowAnchor> createState() => _BoardRowAnchorState();
}

class _BoardRowAnchorState extends ConsumerState<BoardRowAnchor> {
  late final BoardRowAnchors _anchors = ref.read(boardRowAnchorsProvider);

  @override
  void initState() {
    super.initState();
    _anchors.register(widget.giftId, context);
  }

  @override
  void didUpdateWidget(BoardRowAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.giftId != widget.giftId) {
      _anchors.unregister(oldWidget.giftId, context);
      _anchors.register(widget.giftId, context);
    }
  }

  @override
  void dispose() {
    _anchors.unregister(widget.giftId, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Pasa [gift] al estado de [target]: lo que hace soltar su tarjeta en otro
/// carril, o moverla con el teclado o con las acciones del lector de pantalla.
///
/// Es el mismo camino que la casilla de estado (`setGiftStatus` del
/// controlador de la familia, con la celebración armada por si completa a la
/// persona) y avisa igual: un aviso «Kit de pintura: Por comprar» con
/// «Deshacer». El aviso es una región viva, así que el lector de pantalla lo
/// anuncia solo.
///
/// Con [reveal], el tablero enseña el carril de destino (ver
/// [boardLaneRevealProvider]).
///
/// [from] es dónde estaba la tarjeta al soltarla (en la ventana); sin él, la
/// del sitio que tenía la fila. [context] ha de seguir en pantalla cuando el
/// regalo ya está en el otro carril: el de un carril o el de la pantalla, no
/// el de la fila que se va.
///
/// Devuelve si lo movió. No hace nada si ya está en ese estado.
Future<bool> moveGiftToLane(
  BuildContext context,
  WidgetRef ref,
  Gift gift,
  BoardLane target, {
  Rect? from,
  bool reveal = false,
}) async {
  if (gift.status == target.status) {
    return false;
  }
  final controller = ref.read(familyControllerProvider.notifier);
  final l10n = AppLocalizations.of(context);
  final haptics = ref.read(hapticsProvider);
  final previous = gift.status;
  final origin = from ?? ref.read(boardRowAnchorsProvider).rectOf(gift.id);
  if (origin != null) {
    ref
        .read(flightRegistryProvider)
        .depart(boardGiftFlightKey(gift.id), origin);
  }
  haptics.light();
  // Con el teclado o el lector de pantalla, el carril de destino se enseña
  // (el de «Listo» plegado se abre) antes de que llegue el regalo.
  if (reveal) {
    ref.read(boardLaneRevealProvider).value = target;
  }
  // Una acción de la persona puede completar a quien recibe: se arma la
  // celebración antes de guardar, como con la casilla.
  ref.read(celebrationArmedProvider.notifier).arm(gift.recipientId);
  final saved = await controller.setGiftStatus(gift.id, target.status);
  if (!context.mounted) {
    return saved;
  }
  if (!saved) {
    // Otro móvil lo borró: se avisa en vez de contar un cambio que no existe.
    showRegalosSnackBar(context, SnackBar(content: Text(l10n.giftNotSaved)));
    return false;
  }
  showRegalosSnackBar(
    context,
    SnackBar(
      // Con acción, Flutter la deja fija hasta que se toca: que se vaya sola.
      persist: false,
      duration: const Duration(seconds: 4),
      content: Text(
        l10n.boardGiftMoved(gift.title, boardLaneTitle(l10n, target)),
      ),
      action: SnackBarAction(
        label: l10n.actionUndo,
        onPressed: () {
          haptics.light();
          controller.setGiftStatus(gift.id, previous);
        },
      ),
    ),
  );
  return true;
}

/// Pide al tablero que enseñe un carril: al pasar un regalo a «Listo» con
/// el teclado estando plegado, abre su panel para que el regalo movido se vea
/// y siga marcado. Quien lo atiende lo vuelve a poner a `null`.
final boardLaneRevealProvider = Provider<ValueNotifier<BoardLane?>>((ref) {
  final reveal = ValueNotifier<BoardLane?>(null);
  ref.onDispose(reveal.dispose);
  return reveal;
});

/// Dónde está el puntero mientras se arrastra una tarjeta (`null` si no se
/// arrastra ninguna): los carriles lo leen para desplazarse solos cuando se
/// acerca a su borde.
final boardDragPointerProvider = Provider<ValueNotifier<Offset?>>((ref) {
  final pointer = ValueNotifier<Offset?>(null);
  ref.onDispose(pointer.dispose);
  return pointer;
});
