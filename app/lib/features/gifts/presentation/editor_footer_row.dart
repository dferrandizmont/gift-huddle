import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// El pie del editor: [start] a la izquierda y [end] a la derecha, en una
/// sola fila. Ninguno se encoge: si no caben juntos, [start] queda en una fila
/// propia encima y [end] debajo, a la derecha, en vez de partir su texto.
class EditorFooterRow extends MultiChildRenderObjectWidget {
  /// Crea el pie. Con [start] nulo, [end] va solo a la derecha.
  EditorFooterRow({
    super.key,
    Widget? start,
    required Widget end,
    this.gap = 12,
    this.rowGap = 4,
  }) : super(children: [?start, end]);

  /// Hueco mínimo entre los dos en la misma fila.
  final double gap;

  /// Hueco entre las dos filas cuando no caben juntos.
  final double rowGap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderEditorFooterRow(gap, rowGap);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as RenderEditorFooterRow)
      ..gap = gap
      ..rowGap = rowGap;
  }
}

/// Datos de posición de cada hijo.
class EditorFooterParentData extends ContainerBoxParentData<RenderBox> {}

/// El render del pie del editor.
class RenderEditorFooterRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, EditorFooterParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, EditorFooterParentData> {
  RenderEditorFooterRow(this._gap, this._rowGap);

  double _gap;
  double _rowGap;

  set gap(double v) {
    if (v != _gap) {
      _gap = v;
      markNeedsLayout();
    }
  }

  set rowGap(double v) {
    if (v != _rowGap) {
      _rowGap = v;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! EditorFooterParentData) {
      child.parentData = EditorFooterParentData();
    }
  }

  List<RenderBox> get _kids {
    final out = <RenderBox>[];
    var c = firstChild;
    while (c != null) {
      out.add(c);
      c = (c.parentData! as EditorFooterParentData).nextSibling;
    }
    return out;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, dry: true);

  @override
  void performLayout() {
    size = _layout(constraints, dry: false);
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final kids = _kids;
    final width = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: width);
    Size sizeOf(RenderBox b) => dry
        ? b.getDryLayout(loose)
        : (b..layout(loose, parentUsesSize: true)).size;
    final end = kids.last;
    final endSize = sizeOf(end);
    if (kids.length == 1) {
      if (!dry) {
        (end.parentData! as EditorFooterParentData).offset = Offset(
          width - endSize.width,
          0,
        );
      }
      return constraints.constrain(Size(width, endSize.height));
    }
    final start = kids.first;
    final startSize = sizeOf(start);
    final together = startSize.width + _gap + endSize.width <= width;
    if (together) {
      final h = math.max(startSize.height, endSize.height);
      if (!dry) {
        (start.parentData! as EditorFooterParentData).offset = Offset(
          0,
          (h - startSize.height) / 2,
        );
        (end.parentData! as EditorFooterParentData).offset = Offset(
          width - endSize.width,
          (h - endSize.height) / 2,
        );
      }
      return constraints.constrain(Size(width, h));
    }
    if (!dry) {
      (start.parentData! as EditorFooterParentData).offset = Offset.zero;
      (end.parentData! as EditorFooterParentData).offset = Offset(
        width - endSize.width,
        startSize.height + _rowGap,
      );
    }
    return constraints.constrain(
      Size(width, startSize.height + _rowGap + endSize.height),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double computeMinIntrinsicWidth(double height) => _kids
      .map((k) => k.getMinIntrinsicWidth(height))
      .fold<double>(0, math.max);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _kids
          .map((k) => k.getMaxIntrinsicWidth(height))
          .fold<double>(0, (a, b) => a + b) +
      (_kids.length > 1 ? _gap : 0);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
