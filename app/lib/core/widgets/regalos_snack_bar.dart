import 'package:flutter/material.dart';

import '../layout/pane_scope.dart';
import '../layout/window_class.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';

/// Muestra un aviso con el movimiento de la app (§2.5 de
/// la guía de movimiento): entra con `snap` en 375 ms y se va con
/// `fold` en 200 ms. Si ya había un aviso, el viejo se va y entra el nuevo.
/// Con «Reducir movimiento», fundido de 150 ms.
///
/// Desde 600 dp mide 480 y va centrado en el área de contenido
/// ([regalosSnackBar]). En el móvil, de lado a lado con su margen, como
/// siempre.
///
/// Todas las llamadas a `showSnackBar` de la app pasan por aquí.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showRegalosSnackBar(
  BuildContext context,
  SnackBar snackBar,
) {
  final style = regalosSnackBarStyle(context);
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return messenger.showSnackBar(
    regalosSnackBar(context, snackBar),
    snackBarAnimationStyle: style,
  );
}

/// El estilo de animación de los avisos (para quien ya tiene su
/// `ScaffoldMessenger`).
AnimationStyle regalosSnackBarStyle(BuildContext context) {
  final motion = RegalosMotion.of(context);
  return motion.reduce
      ? const AnimationStyle(
          duration: RegalosMotion.fade,
          reverseDuration: RegalosMotion.fade,
          curve: Curves.linear,
          reverseCurve: Curves.linear,
        )
      : AnimationStyle(
          duration: RegalosSprings.snapDuration,
          curve: RegalosCurves.snap,
          reverseDuration: const Duration(milliseconds: 200),
          reverseCurve: RegalosCurves.fold,
        );
}

/// [snackBar] con las medidas de tablet (la guía de diseño para tablet,
/// §2.2): 480 de ancho, abajo y centrado en el área de contenido. En una
/// ventana de menos de 600 dp de ancho lo devuelve tal cual.
///
/// El aviso lo pinta el `Scaffold` raíz, que con pestañas es el de la app
/// entera, raíl incluido: [besideRail] dice si es ese (por defecto, si
/// [context] está en un panel) y entonces el aviso se desplaza medio raíl
/// para quedar centrado en el área de contenido y no en la ventana. Una ruta
/// con su propio `Scaffold` (el editor, el primer uso) lo centra en sí misma.
///
/// Para quien enseña el aviso con su propio `ScaffoldMessenger`; lo demás usa
/// [showRegalosSnackBar].
SnackBar regalosSnackBar(
  BuildContext context,
  SnackBar snackBar, {
  bool? besideRail,
}) {
  // Como las columnas y las hojas, va por ancho: por debajo de 600 dp no
  // cambia nada.
  if (MediaQuery.sizeOf(context).width < RegalosBreakpoints.medium ||
      snackBar.width != null ||
      snackBar.margin != null ||
      snackBar.behavior == SnackBarBehavior.fixed) {
    return snackBar;
  }
  final shifted =
      WindowClass.of(context).usesRail &&
      (besideRail ?? PaneScope.anchorOf(context) != null);
  if (!shifted) {
    return _resized(snackBar, width: RegalosLayout.snackBarWidth);
  }
  // El `Scaffold` solo sabe centrar el aviso en sí mismo. Se le da un aviso
  // un raíl más ancho, centrado en la ventana, que solo pinta (y solo recibe
  // toques) en la parte que no cae del lado del raíl: esa parte mide 480 y
  // queda centrada en el área de contenido, también al girar.
  const rail = EdgeInsetsDirectional.only(start: RegalosLayout.railWidth);
  final shape =
      snackBar.shape ??
      Theme.of(context).snackBarTheme.shape ??
      const RoundedRectangleBorder(borderRadius: RegalosShape.card);
  return _resized(
    snackBar,
    width: RegalosLayout.snackBarWidth + RegalosLayout.railWidth,
    shape: _InsetShape(shape, rail),
    content: Padding(padding: rail, child: snackBar.content),
    hitTestBehavior: HitTestBehavior.deferToChild,
  );
}

/// Una copia de [snackBar] con otro ancho y, si se dan, otra forma, otro
/// contenido y otra manera de recibir toques.
SnackBar _resized(
  SnackBar snackBar, {
  required double width,
  ShapeBorder? shape,
  Widget? content,
  HitTestBehavior? hitTestBehavior,
}) => SnackBar(
  key: snackBar.key,
  content: content ?? snackBar.content,
  backgroundColor: snackBar.backgroundColor,
  elevation: snackBar.elevation,
  padding: snackBar.padding,
  width: width,
  shape: shape ?? snackBar.shape,
  hitTestBehavior: hitTestBehavior ?? snackBar.hitTestBehavior,
  behavior: snackBar.behavior,
  action: snackBar.action,
  actionOverflowThreshold: snackBar.actionOverflowThreshold,
  showCloseIcon: snackBar.showCloseIcon,
  closeIconColor: snackBar.closeIconColor,
  duration: snackBar.duration,
  persist: snackBar.persist,
  animation: snackBar.animation,
  onVisible: snackBar.onVisible,
  dismissDirection: snackBar.dismissDirection,
  clipBehavior: snackBar.clipBehavior,
);

/// La forma [shape] metida [inset] hacia dentro de su rectángulo: lo que queda
/// fuera no se pinta, no hace sombra y deja pasar los toques.
class _InsetShape extends ShapeBorder {
  const _InsetShape(this.shape, this.inset);

  final ShapeBorder shape;
  final EdgeInsetsGeometry inset;

  Rect _inner(Rect rect, TextDirection? textDirection) =>
      inset.resolve(textDirection ?? TextDirection.ltr).deflateRect(rect);

  @override
  EdgeInsetsGeometry get dimensions => shape.dimensions.add(inset);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => shape
      .getInnerPath(_inner(rect, textDirection), textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => shape
      .getOuterPath(_inner(rect, textDirection), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) => shape
      .paint(canvas, _inner(rect, textDirection), textDirection: textDirection);

  @override
  ShapeBorder scale(double t) => _InsetShape(shape.scale(t), inset * t);

  @override
  bool operator ==(Object other) =>
      other is _InsetShape && other.shape == shape && other.inset == inset;

  @override
  int get hashCode => Object.hash(shape, inset);
}
