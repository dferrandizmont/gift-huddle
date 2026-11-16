import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../layout/pane_scope.dart';
import '../layout/window_class.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'haptics.dart';
import 'sheet_motion.dart';

/// Abre una tarjeta que sube desde abajo hasta ocupar la pantalla menos 12 px
/// arriba, como las hojas de Reparto (§2.1 de
/// la guía de movimiento y las «Decisiones de producto» del final:
/// el editor no crece desde lo que se toca).
///
/// Llega con `snap` sobre el velo de Reparto, con radio 8 arriba (nada pasa
/// de 8), y se cierra deslizando hacia abajo en 240 ms con
/// `sheetExit`, o arrastrando su cabecera ([CardSheetHandle]). **No hace
/// retroceder la app**: el fondo no se encoge ni se escala; solo se oscurece
/// con el velo. Con «Reducir movimiento» es una pantalla completa que se
/// funde en 150 ms.
///
/// Mide [maxWidth] como mucho (640, el editor) y se centra en el panel desde
/// el que se abre, como las hojas (`showRegalosSheet`). En el móvil va de
/// lado a lado, como siempre.
Future<T?> showCardSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = RegalosLayout.editorWidth,
}) => Navigator.of(context, rootNavigator: true).push<T>(
  CardSheetRoute<T>(
    reduce: RegalosMotion.of(context).reduce,
    builder: builder,
    scrim: RegalosTokens.of(context).scrim,
    anchor: SheetPane.anchorOf(context),
    maxWidth: maxWidth,
  ),
);

/// La ruta de [showCardSheet].
class CardSheetRoute<T> extends PopupRoute<T> {
  /// Crea la ruta.
  CardSheetRoute({
    required this.reduce,
    required this.builder,
    this.scrim = kSheetBarrierColor,
    this.anchor,
    this.maxWidth = RegalosLayout.editorWidth,
  });

  /// Si el sistema pide reducir el movimiento.
  final bool reduce;

  /// Construye el contenido de la tarjeta.
  final WidgetBuilder builder;

  /// El velo (token `scrim` del tema).
  final Color scrim;

  /// El ancla del panel en el que se centra la tarjeta; `null`, la ventana.
  final PaneAnchor? anchor;

  /// Ancho máximo de la tarjeta.
  final double maxWidth;

  @override
  Color get barrierColor => scrim;

  // El editor tiene datos sin guardar: no se cierra tocando fuera.
  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration =>
      reduce ? RegalosMotion.fade : RegalosSprings.snapDuration;

  @override
  Duration get reverseTransitionDuration =>
      reduce ? RegalosMotion.fade : RegalosCurves.sheetExitDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    // La tarjeta, en su columna dentro del panel. El velo es de la ruta y
    // cubre la ventana entera.
    child: PaneAligned(
      anchor: anchor,
      maxWidth: maxWidth,
      child: _CardSheetPage(
        animation: animation,
        reduce: reduce,
        child: SheetPane(
          anchor: anchor,
          child: Builder(builder: builder),
        ),
      ),
    ),
  );

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
    final curved = CurvedAnimation(
      parent: animation,
      curve: RegalosCurves.snap,
      reverseCurve: RegalosCurves.sheetExit,
    );
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) => FractionalTranslation(
        translation: Offset(0, 1 - curved.value),
        child: child,
      ),
    );
  }
}

/// Abre una tarjeta como un diálogo centrado, para el editor en una ventana
/// de escritorio (desde 1280; la guía de diseño de escritorio,
/// §2 y las decisiones de producto). En el móvil y en la tablet el editor sigue
/// subiendo desde abajo con [showCardSheet].
///
/// Mide [width] como mucho (880) y el alto de su contenido, a un 10 % del
/// borde superior de la ventana; si no cabe, el contenido se desplaza por
/// dentro (el constructor del contenido lo hace con un `Flexible`). Se centra
/// en el panel desde el que se abre, como la hoja, y el velo cubre la ventana
/// entera, el mismo que el de los diálogos de confirmación.
///
/// Entra con un fundido y una escala de 0,97 a 1 en 180 ms con `snap`, y sale
/// en 120 ms. Con «Reducir movimiento» solo se funde en 150 ms. No se cierra
/// tocando fuera (tiene datos sin guardar): se cierra con Esc, «Cancelar» o
/// «Guardar».
Future<T?> showCardDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = RegalosLayout.desktopEditorWidth,
}) => Navigator.of(context, rootNavigator: true).push<T>(
  CardDialogRoute<T>(
    reduce: RegalosMotion.of(context).reduce,
    builder: builder,
    scrim: CardDialogRoute.scrimFor(RegalosTokens.of(context)),
    anchor: SheetPane.anchorOf(context),
    maxWidth: width,
  ),
);

/// La ruta de [showCardDialog].
class CardDialogRoute<T> extends PopupRoute<T> {
  /// Crea la ruta.
  CardDialogRoute({
    required this.reduce,
    required this.builder,
    this.scrim = kSheetBarrierColor,
    this.anchor,
    this.maxWidth = RegalosLayout.desktopEditorWidth,
  });

  /// Si el sistema pide reducir el movimiento.
  final bool reduce;

  /// Construye el contenido del diálogo.
  final WidgetBuilder builder;

  /// El velo (token `scrim` del tema).
  final Color scrim;

  /// El ancla del panel en el que se centra el diálogo; `null`, la ventana.
  final PaneAnchor? anchor;

  /// Ancho máximo del diálogo.
  final double maxWidth;

  /// El velo del diálogo: el token `scrim` en claro y, en oscuro, un negro al
  /// 40 % (el del tema se perdía contra la banda oscura de detrás).
  static Color scrimFor(RegalosTokens t) =>
      t.isDark ? const Color(0x66000000) : t.scrim;

  /// Lo que baja el diálogo desde el borde superior de la ventana.
  static const double topFraction = 0.10;

  /// El hueco que se deja debajo del diálogo cuando no cabe.
  static const double bottomMargin = 24;

  /// La escala de la que entra y a la que sale.
  static const double enterScale = 0.97;

  /// Lo que dura la salida.
  static const Duration exitDuration = Duration(milliseconds: 120);

  /// `snap` comprimido a los 180 ms de la entrada: el mismo muelle (520 / 38,
  /// que se asienta en 375 ms) con el tiempo dividido entre 375 / 180, así que
  /// rigidez y amortiguación suben con la razón al cuadrado y a secas.
  static final SpringCurve _enter = SpringCurve(
    SpringDescription(
      mass: 1,
      stiffness: RegalosSprings.snap.stiffness * _timeRatio * _timeRatio,
      damping: RegalosSprings.snap.damping * _timeRatio,
    ),
    const Duration(milliseconds: 180),
  );

  static const double _timeRatio = 375 / 180;

  @override
  Color get barrierColor => scrim;

  // El editor tiene datos sin guardar: no se cierra tocando fuera.
  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration =>
      reduce ? RegalosMotion.fade : const Duration(milliseconds: 180);

  @override
  Duration get reverseTransitionDuration =>
      reduce ? RegalosMotion.fade : exitDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final t = RegalosTokens.of(context);
    final surface = Material(
      color: t.sheet,
      shape: RoundedRectangleBorder(
        borderRadius: RegalosShape.card,
        // Filete de 1 px: en oscuro, el de los controles, que sí se ve.
        side: BorderSide(color: t.isDark ? t.outline : t.separator),
      ),
      clipBehavior: Clip.antiAlias,
      child: SheetPane(
        anchor: anchor,
        child: Builder(builder: builder),
      ),
    );
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      // Un `Scaffold` transparente a toda la ventana: los avisos del editor
      // («No se ha guardado…») salen por encima del velo, no por debajo. De
      // paso sube el diálogo con el teclado.
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LayoutBuilder(
          builder: (context, box) {
            final top = MediaQuery.sizeOf(context).height * topFraction;
            final maxHeight = math.max(0.0, box.maxHeight - top - bottomMargin);
            return PaneAligned(
              anchor: anchor,
              maxWidth: maxWidth,
              child: Padding(
                padding: EdgeInsets.only(top: top),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: double.infinity,
                      maxHeight: maxHeight,
                    ),
                    child: _CardDialogTransition(
                      animation: animation,
                      reduce: reduce,
                      enter: _enter,
                      child: surface,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CardDialogTransition extends StatelessWidget {
  const _CardDialogTransition({
    required this.animation,
    required this.reduce,
    required this.enter,
    required this.child,
  });

  final Animation<double> animation;
  final bool reduce;
  final Curve enter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduce) {
      return FadeTransition(opacity: animation, child: child);
    }
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final v = animation.value.clamp(0.0, 1.0);
        final leaving = animation.status == AnimationStatus.reverse;
        // La entrada sigue el muelle en la escala y un `easeOut` en el
        // fundido (el muelle pasa de 1 y la opacidad no); la salida, un
        // `easeIn` en las dos.
        final k = leaving ? Curves.easeIn.transform(v) : enter.transform(v);
        final opacity = leaving ? k : Curves.easeOut.transform(v);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale:
                CardDialogRoute.enterScale +
                (1 - CardDialogRoute.enterScale) * k,
            child: child,
          ),
        );
      },
    );
  }
}

class _CardDragScope extends InheritedWidget {
  const _CardDragScope({required this.state, required super.child});

  final _CardSheetPageState state;

  @override
  bool updateShouldNotify(_CardDragScope old) => state != old.state;
}

class _CardSheetPage extends StatefulWidget {
  const _CardSheetPage({
    required this.animation,
    required this.reduce,
    required this.child,
  });

  final Animation<double> animation;
  final bool reduce;
  final Widget child;

  @override
  State<_CardSheetPage> createState() => _CardSheetPageState();
}

class _CardSheetPageState extends State<_CardSheetPage>
    with SingleTickerProviderStateMixin {
  // Cuánto se ha arrastrado la tarjeta hacia abajo, en píxeles.
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );
  double _height = 0;
  bool _dismissing = false;

  void _onUpdate(DragUpdateDetails details) {
    if (widget.reduce || _dismissing) {
      return;
    }
    _drag.stop();
    _drag.value = (_drag.value + details.delta.dy).clamp(0.0, double.infinity);
  }

  void _onEnd(DragEndDetails details) {
    if (widget.reduce || _dismissing) {
      return;
    }
    final v = details.velocity.pixelsPerSecond.dy;
    if (v > 700 || (_height > 0 && _drag.value > _height * 0.35)) {
      // Se cierra desde donde está: la ruta baja el resto. La vibración
      // llega cuando la hoja toca fondo.
      _dismissing = true;
      context.haptics.light(after: RegalosCurves.sheetExitDuration);
      Navigator.of(context).maybePop();
    } else if (_drag.value > 0) {
      // Soltarla a medias: vuelve con un clic cuando el muelle se asienta (un
      // roce de pocos píxeles no vibra).
      if (_drag.value > kHapticMinDrag) {
        context.haptics.selection(after: kHapticSpringArrival);
      }
      _drag.animateWith(
        SpringSimulation(
          RegalosSprings.snap,
          _drag.value,
          0,
          v,
          snapToEnd: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final media = MediaQuery.of(context);
    final top = widget.reduce ? 0.0 : media.padding.top + 12;
    final radius = widget.reduce
        ? BorderRadius.zero
        : const BorderRadius.vertical(
            top: Radius.circular(RegalosShape.sheetRadius),
          );
    return _CardDragScope(
      state: this,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: LayoutBuilder(
          builder: (context, box) {
            _height = box.maxHeight;
            return AnimatedBuilder(
              animation: _drag,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, _drag.value),
                child: child,
              ),
              child: Material(
                color: t.sheet,
                // Filo de 1 px arriba (solo se ve en oscuro).
                shape: RoundedRectangleBorder(
                  borderRadius: radius,
                  side: BorderSide(color: t.sheetEdge),
                ),
                clipBehavior: Clip.antiAlias,
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: AnimatedBuilder(
                    animation: widget.animation,
                    child: widget.child,
                    builder: (context, child) {
                      // El contenido entra en el 70 % final de la ruta y no
                      // se desvanece al cerrar.
                      final closing =
                          widget.animation.status == AnimationStatus.reverse;
                      final p = closing || widget.reduce
                          ? 1.0
                          : const Interval(
                              0.3,
                              1,
                              curve: Curves.easeOut,
                            ).transform(widget.animation.value);
                      return Opacity(
                        opacity: p,
                        child: Transform.translate(
                          offset: Offset(0, 8 * (1 - p)),
                          child: child,
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// La cabecera de una tarjeta de [showCardSheet]: arrastrarla hacia abajo
/// cierra la tarjeta (más de 700 px/s o más del 35 %); si no, vuelve a su
/// sitio con `snap` y la velocidad del dedo.
class CardSheetHandle extends StatelessWidget {
  /// Envuelve la cabecera.
  const CardSheetHandle({super.key, required this.child});

  /// La cabecera.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_CardDragScope>();
    if (scope == null) {
      return child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: scope.state._onUpdate,
      onVerticalDragEnd: scope.state._onEnd,
      child: child,
    );
  }
}
