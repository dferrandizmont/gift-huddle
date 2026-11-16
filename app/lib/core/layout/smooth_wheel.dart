import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// La rueda del ratón desplaza con suavidad (la guía de diseño de escritorio, §4.3).
///
/// Flutter mueve una lista de golpe, 100 px por muesca (`forcePixels`), y en
/// una pantalla grande eso se ve a saltos. Este envoltorio, puesto encima de
/// las listas de una pestaña, deja que `Scrollable` haga su trabajo (decide
/// qué lista recibe la rueda, el límite, los anidados) y, en cuanto avisa de
/// que se movió por una rueda, devuelve la lista a donde estaba y la va
/// acercando al mismo sitio fotograma a fotograma, con un amortiguado
/// exponencial que llega en unos [duration] (160 ms). Como todo ocurre en el
/// mismo fotograma, no se ve el salto.
///
/// Varias muescas seguidas se suman: cada una desplaza el destino de la
/// anterior, y la lista sigue hacia el nuevo sin reiniciar nada (por eso no es
/// una animación por muesca: cada reinicio costaría un fotograma parado).
///
/// Solo mira eventos de **ratón** (`PointerDeviceKind.mouse`): el trackpad y el
/// dedo, que ya son continuos, no cambian. Solo listas verticales. Con
/// «Reducir movimiento» no hace nada y la rueda salta, como siempre.
class SmoothWheel extends StatefulWidget {
  /// Suaviza la rueda sobre las listas de [child].
  const SmoothWheel({super.key, required this.child});

  final Widget child;

  /// Lo que dura el desplazamiento de una muesca.
  static const Duration duration = Duration(milliseconds: 160);

  @override
  State<SmoothWheel> createState() => _SmoothWheelState();
}

class _SmoothWheelState extends State<SmoothWheel>
    with SingleTickerProviderStateMixin {
  // El evento que se está despachando es una rueda de ratón. Se enciende al ver
  // el evento (esta escucha corre antes de que `Scrollable` mueva nada: la
  // resolución de señales va al final del despacho) y se apaga en cuanto acaba
  // el despacho.
  bool _wheel = false;

  // Adónde va cada lista que se está deslizando.
  final Map<ScrollPosition, double> _targets = <ScrollPosition, double>{};
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;

  // Lo que se tarda en recorrer ~63 % de la distancia que falta; con 3 veces
  // eso (la duración) queda a menos del 5 %.
  static final double _tau = SmoothWheel.duration.inMicroseconds / 3;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.kind != PointerDeviceKind.mouse) {
      return;
    }
    _wheel = true;
    scheduleMicrotask(() => _wheel = false);
  }

  bool _onScroll(ScrollUpdateNotification n) {
    // Solo lo que hizo la rueda: sin gesto de arrastre y dentro del despacho.
    if (!_wheel ||
        n.dragDetails != null ||
        n.metrics.axis != Axis.vertical ||
        RegalosMotion.of(context).reduce) {
      return false;
    }
    final scrollContext = n.context;
    final position = scrollContext == null
        ? null
        : Scrollable.maybeOf(scrollContext)?.position;
    final applied = n.scrollDelta;
    if (position == null || applied == null || applied == 0) {
      return false;
    }
    // Dónde estaba la lista antes de este salto, y adónde iba si ya iba.
    final before = position.pixels - applied;
    final base = _targets[position] ?? before;
    final target = (base + applied).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _targets[position] = target;
    // Cuando acabe el despacho de este evento: se deshace el salto y la lista
    // sigue desde donde estaba.
    scheduleMicrotask(() {
      if (!mounted || !position.hasPixels || !_targets.containsKey(position)) {
        _targets.remove(position);
        return;
      }
      position.jumpTo(before);
      if (!_ticker.isActive) {
        _last = Duration.zero;
        unawaited(_ticker.start());
      }
    });
    return false;
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds.toDouble();
    _last = elapsed;
    final k = 1 - math.exp(-dt / _tau);
    for (final position in _targets.keys.toList()) {
      final target = _targets[position]!;
      // Otro movimiento (un arrastre, la barra) toma el relevo: se suelta.
      if (!position.hasPixels || position.isScrollingNotifier.value) {
        _targets.remove(position);
        continue;
      }
      final remaining = target - position.pixels;
      if (remaining.abs() < 0.5) {
        position.jumpTo(target);
        _targets.remove(position);
      } else {
        position.jumpTo(position.pixels + remaining * k);
      }
    }
    if (_targets.isEmpty) {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _onSignal,
    child: NotificationListener<ScrollUpdateNotification>(
      onNotification: _onScroll,
      child: widget.child,
    ),
  );
}
