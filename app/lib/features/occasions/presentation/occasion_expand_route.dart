import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/layout/pane_scope.dart';
import '../../../core/layout/two_pane.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/countdown_card.dart';

/// De dónde sale el vuelo: la tarjeta de la cuenta atrás del carrusel.
///
/// Las dos claves miden la tarjeta y su número en cada fotograma; los
/// rectángulos [card] y [number] son los de cuando se tocó (respaldo si la
/// tarjeta ya no está montada).
@immutable
class OccasionExpandSource {
  /// Crea el origen.
  const OccasionExpandSource({
    required this.cardKey,
    required this.numberKey,
    required this.card,
    required this.number,
    required this.days,
    required this.numberStyle,
    required this.soft,
    required this.surface,
    this.border,
  });

  /// La superficie de la tarjeta.
  final GlobalKey cardKey;

  /// El número de la tarjeta.
  final GlobalKey numberKey;

  /// El rectángulo de la tarjeta al tocarla.
  final Rect card;

  /// El rectángulo del número al tocarlo.
  final Rect number;

  /// Los días que faltan.
  final int days;

  /// El estilo del número en la tarjeta.
  final TextStyle numberStyle;

  /// El pastel de la tarjeta y de la franja de la cabecera.
  final Color soft;

  /// El borde fino de la tarjeta (el tema de la ocasión), si lo tiene.
  final Color? border;

  /// El fondo de la pantalla del detalle.
  final Color surface;
}

/// Mide el rectángulo de [key] en las coordenadas de [ancestor], o `null` si
/// no está montado.
Rect? measureRect(GlobalKey key, RenderObject ancestor) {
  final object = key.currentContext?.findRenderObject();
  if (object is! RenderBox || !object.attached || !object.hasSize) {
    return null;
  }
  try {
    return MatrixUtils.transformRect(
      object.getTransformTo(ancestor),
      Offset.zero & object.size,
    );
  } on Object {
    return null;
  }
}

/// Abre el detalle de una ocasión **creciendo desde su tarjeta** del carrusel
/// (§3.1 y «momento K» de la guía de movimiento).
///
/// Es una `PageRoute` que se empuja en el `Navigator` raíz (la ruta del detalle
/// vive en otra rama, así que un `Hero` no volaría). En `buildTransitions`,
/// mientras dura el viaje, pinta **debajo del detalle**:
///
/// - un velo del 12 % sobre Personas (no retrocede ni se encoge nada);
/// - la superficie del fondo, cuyo rectángulo va de la tarjeta a la pantalla
///   entera con `snap` y cuyo radio va de 8 a 0;
/// - dentro, una franja pastel que va del rectángulo de la tarjeta al de la
///   tarjeta de cuenta atrás del detalle;
///
/// y **encima**, el número, que vuela de su sitio al de la cabecera cambiando
/// de tamaño de letra fotograma a fotograma (`TextStyle.lerp`, no escala de
/// mapa de bits). El detalle, con el fondo transparente mientras tanto, pone
/// el resto de su cabecera con un fundido y las filas con la entrada
/// escalonada. Al terminar se quita la capa y queda la cabecera real.
///
/// Volver lo hace todo al revés en 220 ms con `fold`, sin muelle: el detalle se
/// funde en 120 ms, la capa encoge hasta la tarjeta y el número vuelve a su
/// tamaño. Con «Reducir movimiento»: fundido de 150 ms.
class OccasionExpandRoute extends PageRoute<void> {
  /// Crea la ruta.
  OccasionExpandRoute({
    required this.source,
    required this.reduce,
    required this.builder,
    super.settings,
  }) : _hidden = ValueNotifier<bool>(!reduce) {
    flight = CountdownFlight(hidden: _hidden, progress: _progress);
  }

  /// De dónde sale el vuelo.
  final OccasionExpandSource source;

  /// Si el sistema pide reducir el movimiento.
  final bool reduce;

  /// Construye el detalle.
  final WidgetBuilder builder;

  /// Lo que comparte con la tarjeta del detalle.
  late final CountdownFlight flight;

  /// El panel de detalle de la ventana (en sus coordenadas) cuando hay dos
  /// paneles a la vez: ahí termina el vuelo y ahí se maqueta el detalle, de
  /// modo que la lista, el raíl y el resto no se mueven. `null` con un solo
  /// panel (el móvil): el detalle ocupa la ventana entera, como siempre.
  Rect? get pane => _pane;
  Rect? _pane;

  final ValueNotifier<bool> _hidden;
  final ProxyAnimation _progress = ProxyAnimation(kAlwaysCompleteAnimation);

  /// Lo que dura volver (220 ms con `fold`).
  static const Duration backDuration = Duration(milliseconds: 220);

  @override
  Duration get transitionDuration =>
      reduce ? RegalosMotion.fade : RegalosSprings.snapDuration;

  @override
  Duration get reverseTransitionDuration =>
      reduce ? RegalosMotion.fade : backDuration;

  // Con «Quitar animaciones» el controlador normal de una ruta se acortaría a
  // casi nada y el fundido de 150 ms sería un corte: se conserva su duración.
  @override
  AnimationController createAnimationController() => AnimationController(
    duration: transitionDuration,
    reverseDuration: reverseTransitionDuration,
    debugLabel: debugLabel,
    vsync: navigator!,
    animationBehavior: AnimationBehavior.preserve,
  );

  // Con el detalle en su panel, la lista y el raíl se quedan a la vista.
  @override
  bool get opaque => _pane == null;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  // Se escucha el controlador y no `animation`: la ruta del `Navigator` pone a
  // veces su `animation` en «completada» durante un fotograma (el
  // `HeroController` la deja fuera de pantalla para medir el botón de añadir,
  // que es un `Hero`) y la cabecera real se vería parpadear.
  @override
  void install() {
    super.install();
    final from = source.cardKey.currentContext;
    _pane = from == null || !from.mounted ? null : TwoPane.detailRectOf(from);
    if (!reduce) {
      _progress.parent = controller!.view;
      controller!.addStatusListener(_onStatus);
    }
  }

  void _onStatus(AnimationStatus status) {
    // La cabecera real solo se ve cuando el viaje ha terminado.
    _hidden.value = status != AnimationStatus.completed;
  }

  @override
  void dispose() {
    if (!reduce) {
      controller?.removeStatusListener(_onStatus);
    }
    _hidden.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final page = OccasionExpandScope(
      route: this,
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: Builder(builder: builder),
      ),
    );
    final pane = _pane;
    return pane == null ? page : _PaneFrame(pane: pane, child: page);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduce) {
      return FadeTransition(opacity: animation, child: child);
    }
    return _ExpandTransition(route: this, animation: animation, child: child);
  }
}

/// Lo que el detalle de la ocasión sabe del vuelo que lo trajo.
class OccasionExpandScope extends InheritedWidget {
  /// Crea el ámbito.
  const OccasionExpandScope({
    super.key,
    required this.route,
    required super.child,
  });

  /// La ruta que hace crecer el detalle.
  final OccasionExpandRoute route;

  /// El vuelo, si el detalle se abrió desde la tarjeta del carrusel.
  static OccasionExpandScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OccasionExpandScope>();

  /// Lo mismo, sin suscribirse (para los manejadores de toques).
  static OccasionExpandScope? peek(BuildContext context) =>
      context.getInheritedWidgetOfExactType<OccasionExpandScope>();

  /// El vuelo para la tarjeta de cuenta atrás del detalle, o `null` con
  /// «Reducir movimiento» (ahí no hay vuelo).
  CountdownFlight? get flight => route.reduce ? null : route.flight;

  /// Si el viaje sigue en marcha: el detalle no pinta su fondo ni el botón de
  /// añadir hasta que acaba.
  ValueListenable<bool> get flying => route._hidden;

  /// El avance de la ruta (0 a 1).
  Animation<double> get progress => route._progress;

  @override
  bool updateShouldNotify(OccasionExpandScope old) => route != old.route;
}

/// El resto de la cabecera del detalle (flecha, títulos, guirnalda): opacidad
/// en `Interval(0.5, 0.9)` y subida de 6 a 0 px en `Interval(0.45, 0.95)` de la
/// ruta que la hace crecer. Sin vuelo, o con «Reducir movimiento», deja pasar
/// al hijo.
class OccasionExpandReveal extends StatelessWidget {
  /// Crea el envoltorio.
  const OccasionExpandReveal({super.key, required this.child});

  /// La parte de la cabecera.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = OccasionExpandScope.maybeOf(context);
    if (scope == null || scope.route.reduce) {
      return child;
    }
    return AnimatedBuilder(
      animation: scope.progress,
      child: child,
      builder: (context, child) {
        final p = scope.progress.value;
        return Opacity(
          opacity: const Interval(0.5, 0.9).transform(p),
          child: Transform.translate(
            offset: Offset(
              0,
              6 * (1 - const Interval(0.45, 0.95).transform(p)),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _ExpandTransition extends StatefulWidget {
  const _ExpandTransition({
    required this.route,
    required this.animation,
    required this.child,
  });

  final OccasionExpandRoute route;
  final Animation<double> animation;
  final Widget child;

  @override
  State<_ExpandTransition> createState() => _ExpandTransitionState();
}

class _ExpandTransitionState extends State<_ExpandTransition> {
  late CurvedAnimation _curved;

  @override
  void initState() {
    super.initState();
    _curved = CurvedAnimation(
      parent: widget.animation,
      curve: RegalosCurves.snap,
      reverseCurve: RegalosCurves.fold,
    );
  }

  @override
  void didUpdateWidget(_ExpandTransition old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      _curved.dispose();
      _curved = CurvedAnimation(
        parent: widget.animation,
        curve: RegalosCurves.snap,
        reverseCurve: RegalosCurves.fold,
      );
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final source = route.source;
    return LayoutBuilder(
      builder: (context, constraints) {
        // El destino del vuelo: el panel de detalle, o la ventana entera.
        final screen = route.pane ?? (Offset.zero & constraints.biggest);
        return AnimatedBuilder(
          animation: Listenable.merge([_curved, route._hidden]),
          child: widget.child,
          builder: (context, child) {
            final raw = widget.animation;
            final flying =
                route._hidden.value || raw.status != AnimationStatus.completed;
            if (!flying) {
              // La misma cadena (opacidad, recorte, detalle) que en pleno
              // vuelo, para que el detalle no pierda su estado al acabar.
              return Stack(
                fit: StackFit.passthrough,
                children: [
                  const SizedBox.shrink(),
                  const SizedBox.shrink(),
                  const SizedBox.shrink(),
                  Opacity(
                    opacity: 1,
                    child: ClipRect(
                      clipper: _RectClipper(screen),
                      child: child,
                    ),
                  ),
                  const SizedBox.shrink(),
                ],
              );
            }
            final p = _curved.value;
            final t = p.clamp(0.0, 1.0);
            final here = context.findRenderObject();
            final ancestor = here is RenderBox ? here : null;
            Rect? live(GlobalKey key) =>
                ancestor == null ? null : measureRect(key, ancestor);
            final from = live(source.cardKey) ?? source.card;
            final fromNumber = live(source.numberKey) ?? source.number;
            final toCard = live(route.flight.cardKey);
            final toNumber = live(route.flight.numberKey);

            final surfaceRect = Rect.lerp(from, screen, p)!;
            final radius = lerpDouble(8, 0, t)!;
            // La franja pastel: de la tarjeta a la tarjeta de cuenta atrás del
            // detalle. Si el detalle no la tiene (ocasión pasada), se queda y
            // se va apagando.
            final stripRect = Rect.lerp(from, toCard ?? from, p)!;
            final stripOpacity = toCard == null ? 1 - t : 1.0;

            final startStyle = source.numberStyle;
            final endStyle = route.flight.numberStyle ?? startStyle;
            final numberStyle = TextStyle.lerp(startStyle, endStyle, p)!;
            final numberAt = Offset.lerp(
              fromNumber.topLeft,
              (toNumber ?? fromNumber).topLeft,
              p,
            )!;
            final numberOpacity = toNumber == null ? 1 - t : 1.0;

            // Al volver, el detalle se funde en los primeros 120 ms.
            var contentOpacity = 1.0;
            if (raw.status == AnimationStatus.reverse) {
              final fadeShare =
                  120 / OccasionExpandRoute.backDuration.inMilliseconds;
              contentOpacity = ((raw.value - (1 - fadeShare)) / fadeShare)
                  .clamp(0.0, 1.0);
            }

            return Stack(
              fit: StackFit.passthrough,
              children: [
                // Personas no retrocede: como mucho, un velo del 12 %.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      // El token del velo (claro y oscuro), al 12 %.
                      color: RegalosTokens.of(
                        context,
                      ).scrim.withValues(alpha: 0.12 * t),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: surfaceRect,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: source.surface,
                        borderRadius: BorderRadius.circular(radius),
                      ),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: stripRect,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: stripOpacity.clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: source.soft,
                          borderRadius: BorderRadius.circular(8),
                          border: source.border == null
                              ? null
                              : Border.all(color: source.border!),
                        ),
                      ),
                    ),
                  ),
                ),
                Opacity(
                  opacity: contentOpacity,
                  child: ClipRect(
                    clipper: _RectClipper(surfaceRect),
                    child: child,
                  ),
                ),
                Positioned(
                  left: numberAt.dx,
                  top: numberAt.dy,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: (numberOpacity * contentOpacity).clamp(0.0, 1.0),
                      child: Text(
                        '${source.days}',
                        style: numberStyle.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Recorta el detalle al rectángulo de la superficie que crece.
class _RectClipper extends CustomClipper<Rect> {
  const _RectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_RectClipper old) => old.rect != rect;
}

/// Deja el detalle solo en el rectángulo del panel de detalle, como un panel
/// más (`PaneRole.detail`: lo que se abra desde él, como el editor, se centra
/// ahí). Lo de fuera de ese rectángulo queda a la vista.
class _PaneFrame extends StatelessWidget {
  const _PaneFrame({required this.pane, required this.child});

  final Rect pane;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    double atLeastZero(double v) => v < 0 ? 0 : v;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        pane.left,
        pane.top,
        atLeastZero(window.width - pane.right),
        atLeastZero(window.height - pane.bottom),
      ),
      child: PaneScope(role: PaneRole.detail, child: child),
    );
  }
}
