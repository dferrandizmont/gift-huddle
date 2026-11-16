import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Limita el ancho de [child] a [maxWidth] y lo centra en el sitio que le dan.
///
/// **Por debajo del máximo no hace nada:** el hijo recibe las mismas
/// restricciones y queda en el mismo sitio que sin este widget, así que en el
/// móvil no cambia un píxel. Por encima, equivale a un `Padding` con el mismo
/// margen a cada lado: la columna mide [maxWidth] y lo que sobra se reparte
/// entre los dos lados.
///
/// Mide el sitio que le da su padre (el panel), no la ventana, y el árbol de
/// widgets es el mismo a cualquier ancho: cruzar el máximo al girar no pierde
/// el estado del hijo.
///
/// Para una lista que deba seguir desplazándose al arrastrar por los márgenes,
/// en vez de envolverla se le da el margen como `padding`, con [gutter] y el
/// ancho del panel (`PaneScope.widthOf`).
class ContentWidth extends SingleChildRenderObjectWidget {
  const ContentWidth({super.key, required this.maxWidth, super.child})
    : assert(maxWidth >= 0);

  /// Ancho máximo del hijo. Las medidas están en `RegalosLayout`.
  final double maxWidth;

  /// El margen que queda a cada lado de una columna de [maxWidth] centrada en
  /// [available]. Cero si cabe entera o si [available] no está acotado.
  static double gutter(double available, double maxWidth) =>
      available.isFinite && available > maxWidth
      ? (available - maxWidth) / 2
      : 0;

  @override
  RenderContentWidth createRenderObject(BuildContext context) =>
      RenderContentWidth(maxWidth: maxWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderContentWidth renderObject,
  ) {
    renderObject.maxWidth = maxWidth;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('maxWidth', maxWidth));
  }
}

/// El `RenderObject` de [ContentWidth].
class RenderContentWidth extends RenderShiftedBox {
  RenderContentWidth({required this._maxWidth, RenderBox? child})
    : super(child);

  double get maxWidth => _maxWidth;
  double _maxWidth;
  set maxWidth(double value) {
    if (value == _maxWidth) {
      return;
    }
    _maxWidth = value;
    markNeedsLayout();
  }

  double _gutter(double available) => ContentWidth.gutter(available, _maxWidth);

  /// Las restricciones del hijo: las de fuera menos el margen de los dos
  /// lados. Sin margen, las mismas.
  BoxConstraints _inner(BoxConstraints outer) {
    final gutter = _gutter(outer.maxWidth);
    return gutter == 0
        ? outer
        : outer.deflate(EdgeInsets.symmetric(horizontal: gutter));
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(width - 2 * _gutter(width)) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(width - 2 * _gutter(width)) ?? 0;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final gutter = _gutter(constraints.maxWidth);
    final child = this.child;
    if (child == null) {
      return constraints.constrain(Size(2 * gutter, 0));
    }
    final childSize = child.getDryLayout(_inner(constraints));
    return constraints.constrain(
      Size(childSize.width + 2 * gutter, childSize.height),
    );
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) => child?.getDryBaseline(_inner(constraints), baseline);

  @override
  void performLayout() {
    final constraints = this.constraints;
    final gutter = _gutter(constraints.maxWidth);
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(2 * gutter, 0));
      return;
    }
    child.layout(_inner(constraints), parentUsesSize: true);
    (child.parentData! as BoxParentData).offset = Offset(gutter, 0);
    size = constraints.constrain(
      Size(child.size.width + 2 * gutter, child.size.height),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('maxWidth', maxWidth));
  }
}
