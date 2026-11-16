import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/regalos_motion.dart';

/// De dónde salen los vuelos pendientes (la fila que viaja de un carril a
/// otro, el avatar que vuela de la barra lateral a la cabecera).
///
/// Quien se va ([depart]) deja aquí el rectángulo que ocupaba, en coordenadas
/// de la ventana; el [FlightTarget] que aparece con la misma clave lo recoge,
/// se esconde y deja volar un duplicado desde ese rectángulo hasta su sitio.
class FlightRegistry {
  final Map<Object, _Origin> _origins = <Object, _Origin>{};

  /// Cuánto vive una salida sin que nadie la recoja.
  static const Duration lifetime = Duration(seconds: 4);

  /// Anota que [key] sale de [from] (en coordenadas de la ventana).
  void depart(Object key, Rect from) {
    _origins[key] = _Origin(from, DateTime.now());
  }

  /// Si hay una salida pendiente de [key].
  bool has(Object key) => peek(key) != null;

  /// El rectángulo de la salida pendiente de [key], sin gastarla.
  Rect? peek(Object key) {
    final origin = _origins[key];
    if (origin == null) {
      return null;
    }
    if (DateTime.now().difference(origin.at) > lifetime) {
      _origins.remove(key);
      return null;
    }
    return origin.rect;
  }

  /// Gasta la salida pendiente de [key].
  void consume(Object key) => _origins.remove(key);
}

class _Origin {
  _Origin(this.rect, this.at);

  final Rect rect;
  final DateTime at;
}

/// El registro de vuelos de la sesión.
final flightRegistryProvider = Provider<FlightRegistry>(
  (ref) => FlightRegistry(),
);

/// El rectángulo de [context] en coordenadas de la ventana, o `null` si aún no
/// tiene tamaño.
Rect? globalRectOf(BuildContext context) {
  if (!context.mounted) {
    return null;
  }
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) {
    return null;
  }
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

/// Quien recibe un vuelo: el widget que aparece donde llega lo que vuela.
///
/// Al montarse, o al cambiar de sitio, mira si [FlightRegistry] tiene una
/// salida con su [flightKey] y, si el rectángulo de esta salida está lejos de
/// donde está él ahora, hace volar [ghost] (por defecto, [child]) desde allí
/// hasta aquí con el muelle `flight`. Mientras vuela, el widget de verdad
/// espera escondido; al llegar, se muestra.
///
/// Con «Reducir movimiento» no hay vuelo: aparece con un fundido de 150 ms.
class FlightTarget extends ConsumerStatefulWidget {
  /// Crea el destino.
  const FlightTarget({
    super.key,
    required this.flightKey,
    required this.child,
    this.ghost,
  });

  /// La clave que une la salida con la llegada.
  final Object flightKey;

  /// Lo que se ve cuando no hay vuelo.
  final Widget child;

  /// Lo que vuela, con el tamaño que lleva en cada fotograma; sin él vuela
  /// [child].
  final Widget Function(BuildContext context, Size size)? ghost;

  /// Lo mínimo que tiene que haberse movido el destino para que haya vuelo.
  static const double minDistance = 24;

  @override
  ConsumerState<FlightTarget> createState() => _FlightTargetState();
}

class _FlightTargetState extends ConsumerState<FlightTarget>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  OverlayEntry? _entry;
  bool _hidden = false;
  bool _fadeIn = false;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _checkSoon();
  }

  @override
  void didUpdateWidget(FlightTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkSoon();
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _checkSoon() {
    if (_scheduled || _controller != null) {
      return;
    }
    final registry = ref.read(flightRegistryProvider);
    if (!registry.has(widget.flightKey)) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) {
        _check();
      }
    });
  }

  void _check() {
    final registry = ref.read(flightRegistryProvider);
    final from = registry.peek(widget.flightKey);
    final to = globalRectOf(context);
    if (from == null || to == null) {
      return;
    }
    // Todavía no ha llegado a su sitio (el dato tarda en guardarse): la salida
    // espera a que este widget se mueva.
    if ((to.topLeft - from.topLeft).distance < FlightTarget.minDistance) {
      return;
    }
    registry.consume(widget.flightKey);
    if (RegalosMotion.of(context).reduce) {
      setState(() => _fadeIn = true);
      return;
    }
    _fly(from);
  }

  void _fly(Rect from) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject();
    if (overlay == null || overlayBox is! RenderBox || !overlayBox.attached) {
      return;
    }
    final themes = InheritedTheme.capture(from: context, to: overlay.context);
    final controller = AnimationController(
      vsync: this,
      duration: RegalosSprings.flightDuration,
      animationBehavior: AnimationBehavior.preserve,
    );
    _controller = controller;
    Rect toLocal(Rect global) => Rect.fromPoints(
      overlayBox.globalToLocal(global.topLeft),
      overlayBox.globalToLocal(global.bottomRight),
    );
    final start = toLocal(from);
    var last = toLocal(globalRectOf(context) ?? from);
    _entry = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          // Vuela hacia donde está el destino ahora: si la lista se mueve
          // mientras tanto (una fila que se despliega), no se queda atrás.
          final now = globalRectOf(this.context);
          if (now != null) {
            last = toLocal(now);
          }
          final t = RegalosCurves.flight.transform(controller.value);
          final left = lerpDouble(start.left, last.left, t)!;
          final top = lerpDouble(start.top, last.top, t)!;
          final width = lerpDouble(start.width, last.width, t)!;
          final height = lerpDouble(start.height, last.height, t)!;
          final size = Size(width, height);
          return Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: IgnorePointer(
              child: themes.wrap(
                Material(
                  type: MaterialType.transparency,
                  child: widget.ghost?.call(context, size) ?? widget.child,
                ),
              ),
            ),
          );
        },
      ),
    );
    overlay.insert(_entry!);
    setState(() => _hidden = true);
    controller.forward().whenComplete(() {
      _entry?.remove();
      _entry?.dispose();
      _entry = null;
      _controller?.dispose();
      _controller = null;
      if (mounted) {
        setState(() => _hidden = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_fadeIn) {
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: RegalosMotion.fade,
        child: widget.child,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
      );
    }
    return Opacity(opacity: _hidden ? 0 : 1, child: widget.child);
  }
}
