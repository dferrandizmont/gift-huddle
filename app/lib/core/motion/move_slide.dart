import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// Una fila que se desliza hasta su nuevo sitio cuando la lista se reordena
/// (por ejemplo, una ocasión cuya fecha cambia y salta de lugar).
///
/// [slot] es el puesto de la fila entre sus hermanas. Cuando cambia, la fila
/// compara el sitio donde se pintó antes con el que le toca ahora (medidos
/// dentro de su columna, así que desplazarse no cuenta) y viaja del uno al otro
/// con `snap`, parada en 0 al llegar. El primer fotograma ya se pinta en el
/// sitio de partida: no hay un destello en el destino. Si los puestos cambian
/// solo porque otra fila entra o sale (que ya se pliega o se despliega por su
/// cuenta), el desfase medido es casi cero y no se mueve nada.
///
/// Debe ir directamente en una columna (o en el hijo de una fila de
/// `AnimatedRows`). Con «Reducir movimiento» la fila cambia de sitio sin
/// viajar.
class MoveSlide extends StatefulWidget {
  /// Crea la fila.
  const MoveSlide({
    super.key,
    required this.slot,
    required this.child,
    this.onMoved,
  });

  /// El puesto de la fila entre sus hermanas.
  final int slot;

  /// La fila.
  final Widget child;

  /// Se llama (tras el fotograma) cuando la fila acaba en otro sitio de verdad
  /// (más de un píxel), viaje o no: una lista lo usa para iluminarla y
  /// llevarla a la vista si el destino queda fuera.
  final VoidCallback? onMoved;

  @override
  State<MoveSlide> createState() => _MoveSlideState();
}

class _MoveSlideState extends State<MoveSlide>
    with SingleTickerProviderStateMixin {
  /// El desfase vertical que queda por recorrer; se lleva a 0.
  late final AnimationController _shift = AnimationController.unbounded(
    vsync: this,
    value: 0,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void dispose() {
    _shift.dispose();
    super.dispose();
  }

  /// El render ya ha pintado el primer fotograma desde [delta]: ahora el
  /// muelle lo lleva a 0.
  void _start(double delta) {
    // Si ya viajaba, el muelle nuevo sigue con la velocidad que llevaba.
    final velocity = _shift.isAnimating ? _shift.velocity : 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _shift
        ..value = delta
        ..animateWith(
          SpringSimulation(
            RegalosSprings.snap,
            delta,
            0,
            velocity,
            snapToEnd: true,
          ),
        );
    });
  }

  void _moved() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onMoved?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) => _SlideBox(
    slot: widget.slot,
    shift: _shift,
    reduce: RegalosMotion.of(context).reduce,
    scroll: Scrollable.maybeOf(context)?.position,
    onStart: _start,
    onMoved: _moved,
    child: widget.child,
  );
}

class _SlideBox extends SingleChildRenderObjectWidget {
  const _SlideBox({
    required this.slot,
    required this.shift,
    required this.reduce,
    required this.scroll,
    required this.onStart,
    required this.onMoved,
    required super.child,
  });

  final int slot;
  final AnimationController shift;
  final bool reduce;
  final ScrollPosition? scroll;
  final ValueChanged<double> onStart;
  final VoidCallback onMoved;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSlideBox(
    slot,
    shift,
    reduce: reduce,
    scroll: scroll,
    onStart: onStart,
    onMoved: onMoved,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderSlideBox renderObject) {
    renderObject
      ..reduce = reduce
      ..scroll = scroll
      ..onStart = onStart
      ..onMoved = onMoved
      ..slot = slot;
  }
}

class _RenderSlideBox extends RenderProxyBox {
  _RenderSlideBox(
    this._slot,
    this._shift, {
    required this.reduce,
    required this.scroll,
    required this.onStart,
    required this.onMoved,
  });

  final AnimationController _shift;
  bool reduce;
  ScrollPosition? scroll;
  ValueChanged<double> onStart;
  VoidCallback onMoved;

  int _slot;
  bool _pending = false;

  /// Dónde (dentro de la columna) se pintó la fila el último fotograma.
  double? _lastY;

  /// Lo que se aplica al pintar: el valor del muelle, o el de partida del
  /// primer fotograma, que aún no ha arrancado el muelle.
  double? _first;

  set slot(int value) {
    if (_slot != value) {
      _slot = value;
      _pending = true;
      markNeedsPaint();
    }
  }

  double get _offset => _first ?? _shift.value;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _shift.addListener(_onTick);
  }

  @override
  void detach() {
    _shift.removeListener(_onTick);
    super.detach();
  }

  void _onTick() {
    _first = null;
    markNeedsPaint();
  }

  /// La altura de la fila dentro del contenido de la lista: la posición en
  /// pantalla más lo que se haya desplazado.
  double _contentY() {
    final position = scroll;
    final scrolled =
        position != null && position.hasPixels && position.axis == Axis.vertical
        ? position.pixels
        : 0.0;
    return localToGlobal(Offset.zero).dy + scrolled;
  }

  /// Si el puesto cambió, compara dónde estaba con dónde queda y fija el
  /// desfase de partida. Se llama desde todo lo que lee el desfase (pintar,
  /// transformar, tocar), para que quien mide la fila antes de pintarla (el
  /// recuadro de selección) vea el mismo sitio que luego se pinta.
  void _resolve() {
    if (!_pending) {
      return;
    }
    _pending = false;
    final last = _lastY;
    if (last == null) {
      return;
    }
    final delta = last + _shift.value - _contentY();
    if (delta.abs() < 1) {
      return;
    }
    onMoved();
    if (!reduce) {
      _first = delta;
      onStart(delta);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _resolve();
    _lastY = _contentY();
    final dy = _offset;
    if (dy == 0) {
      super.paint(context, offset);
    } else {
      context.paintChild(child!, offset + Offset(0, dy));
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    _resolve();
    transform.translateByDouble(0, _offset, 0, 1);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    _resolve();
    // La fila se ve desplazada: se comprueba el toque contra donde está
    // pintada, no contra donde la maquetó la columna.
    if (!size.contains(position - Offset(0, _offset))) {
      return false;
    }
    if (hitTestChildren(result, position: position) || hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    _resolve();
    return result.addWithPaintOffset(
      offset: Offset(0, _offset),
      position: position,
      hitTest: (result, transformed) =>
          child?.hitTest(result, position: transformed) ?? false,
    );
  }
}
