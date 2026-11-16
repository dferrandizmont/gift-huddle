import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// Un controlador por pantalla para las entradas escalonadas (§1.6 de
/// la guía de movimiento): los bloques entran de arriba abajo,
/// cada uno [step] después del anterior, una sola vez por visita.
///
/// El controlador arranca en el primer fotograma y no se repite al
/// reconstruir, al volver a una pestaña ni cuando llegan datos nuevos: los
/// [StaggerItem] que se construyen después, con el controlador ya parado, salen
/// enteros. Del elemento [maxItems] en adelante todos entran con el último
/// retardo.
///
/// [StaggerScopeState.replay] vuelve a lanzar la entrada de los bloques que ya
/// estaban (el desbloqueo en cascada, §1+.4): se repite solo desde fuera, nunca
/// por reconstruir.
class StaggerScope extends StatefulWidget {
  /// Crea el ámbito.
  const StaggerScope({
    super.key,
    required this.child,
    this.step = const Duration(milliseconds: 24),
    this.delay = Duration.zero,
    this.maxItems = 10,
    this.animate = true,
  });

  /// Lo que contiene los [StaggerItem].
  final Widget child;

  /// Retardo entre un elemento y el siguiente.
  final Duration step;

  /// Retardo del primer elemento.
  final Duration delay;

  /// Cuántos elementos tienen retardo propio.
  final int maxItems;

  /// Si la entrada se anima. Con `false` todo sale ya entero (por ejemplo, el
  /// panel de detalle de dos paneles, que ya cambia con su propio eje).
  final bool animate;

  /// La animación de la entrada del [StaggerScope] más cercano (sin
  /// suscribirse a él), o `null` si no hay. Avanza en cada fotograma de la
  /// entrada, también en sus repeticiones, y su último valor es el de los
  /// bloques ya asentados: quien pinta algo que depende de dónde están los
  /// bloques (el recuadro de selección) se repinta con ella.
  static Listenable? animationOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_StaggerData>()?.controller;

  /// Los ámbitos montados, para [replayVisible].
  static final Set<StaggerScopeState> _live = <StaggerScopeState>{};

  /// Vuelve a lanzar la entrada de los ámbitos de las pantallas que se ven
  /// ahora (los que no están ocultos ni parados por una pestaña o una ruta de
  /// encima), con [delay] de retardo base sobre el suyo.
  ///
  /// Con «Reducir movimiento» no hace nada: ahí no hay cascada.
  static void replayVisible({Duration delay = Duration.zero}) {
    for (final scope in _live.toList()) {
      if (scope.mounted && scope.isVisible) {
        scope.replay(delay: delay);
      }
    }
  }

  @override
  State<StaggerScope> createState() => StaggerScopeState();
}

/// El estado de [StaggerScope]: [replay].
class StaggerScopeState extends State<StaggerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
    // Con «Quitar animaciones» el controlador normal se acortaría a casi 0 y el
    // fundido de 150 ms sería un corte: se conserva su duración.
    animationBehavior: AnimationBehavior.preserve,
  );

  /// El retardo extra de la última repetición.
  final _StaggerTiming _timing = _StaggerTiming();

  Duration get _total =>
      _timing.extra +
      widget.delay +
      widget.step * (widget.maxItems - 1) +
      RegalosSprings.flightDuration;

  /// Si la pantalla se ve ahora (sus animaciones no están paradas).
  bool get isVisible => TickerMode.getValuesNotifier(context).value.enabled;

  @override
  void initState() {
    super.initState();
    StaggerScope._live.add(this);
    // En el primer fotograma, no en `initState`: así se ve la entrada.
    if (!widget.animate) {
      _controller.value = 1;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  /// Vuelve a lanzar la entrada de todos los bloques que ya estaban, con
  /// [delay] más de retardo. Los bloques que llegaron después de la primera
  /// entrada no se mueven.
  void replay({Duration delay = Duration.zero}) {
    if (!mounted || RegalosMotion.of(context).reduce) {
      return;
    }
    _timing.extra = delay;
    _controller
      ..duration = _total
      ..forward(from: 0);
  }

  @override
  void dispose() {
    StaggerScope._live.remove(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _StaggerData(
    controller: _controller,
    step: widget.step,
    delay: widget.delay,
    maxItems: widget.maxItems,
    timing: _timing,
    child: widget.child,
  );
}

/// Lo que cambia entre una entrada y su repetición.
class _StaggerTiming {
  Duration extra = Duration.zero;
}

class _StaggerData extends InheritedWidget {
  const _StaggerData({
    required this.controller,
    required this.step,
    required this.delay,
    required this.maxItems,
    required this.timing,
    required super.child,
  });

  final AnimationController controller;
  final Duration step;
  final Duration delay;
  final int maxItems;
  final _StaggerTiming timing;

  @override
  bool updateShouldNotify(_StaggerData old) => controller != old.controller;
}

/// Un bloque que entra con el [StaggerScope] más cercano: opacidad de 0 a 1
/// y desplazamiento vertical de [dy] a 0 con el muelle `flight`.
///
/// [index] es su orden de arriba abajo. Sin [StaggerScope] encima, o si se
/// construye cuando la entrada ya acabó, se pinta tal cual. Con «Reducir
/// movimiento» solo se funde en 150 ms, sin retardo ni traslación.
class StaggerItem extends StatefulWidget {
  /// Crea el elemento.
  const StaggerItem({
    super.key,
    required this.index,
    required this.child,
    this.dy = 12,
  });

  /// Orden de entrada (0 es el primero).
  final int index;

  /// Lo que entra.
  final Widget child;

  /// Cuánto sube, en píxeles.
  final double dy;

  @override
  State<StaggerItem> createState() => _StaggerItemState();
}

class _StaggerItemState extends State<StaggerItem> {
  _StaggerData? _data;
  bool _decided = false;
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) {
      return;
    }
    _decided = true;
    final data = context.getInheritedWidgetOfExactType<_StaggerData>();
    if (data == null || data.controller.isCompleted) {
      return;
    }
    _reduce = RegalosMotion.of(context).reduce;
    _data = data;
  }

  /// Cuánto de su entrada lleva (0 a 1), con el controlador en [value].
  double _progress(_StaggerData data, double value) {
    final controller = data.controller;
    final total = (controller.duration ?? Duration.zero).inMicroseconds;
    if (total == 0) {
      return 1;
    }
    final elapsed = value * total;
    if (_reduce) {
      return (elapsed / RegalosMotion.fade.inMicroseconds).clamp(0.0, 1.0);
    }
    final start =
        (data.timing.extra +
                data.delay +
                data.step * widget.index.clamp(0, data.maxItems - 1))
            .inMicroseconds;
    final t = ((elapsed - start) / RegalosSprings.flightDuration.inMicroseconds)
        .clamp(0.0, 1.0);
    return RegalosCurves.flight.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return widget.child;
    }
    // La estructura (opacidad y traslación) no cambia nunca, para que al
    // repetir la entrada el hijo no pierda su estado. La opacidad va con
    // `FadeTransition` (no reconstruye la fila ni deja una capa a 1); solo la
    // traslación se recalcula en cada fotograma.
    final progress = data.controller.drive(
      _ProgressAnimatable((value) => _progress(data, value).clamp(0.0, 1.0)),
    );
    return FadeTransition(
      opacity: progress,
      child: AnimatedBuilder(
        animation: progress,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _reduce ? 0 : widget.dy * (1 - progress.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Convierte el valor del controlador en el avance de un bloque.
class _ProgressAnimatable extends Animatable<double> {
  const _ProgressAnimatable(this._progress);

  final double Function(double value) _progress;

  @override
  double transform(double t) => _progress(t);
}
