import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../layout/window_class.dart';
import '../motion/haptics.dart';
import '../theme/app_scrollbar.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'picker_option.dart';
import 'pointer_surface.dart';
import 'section_header.dart';
import 'stroke_icon.dart';

/// Si un selector se abre como desplegable anclado al campo (escritorio) en
/// vez de como hoja inferior (móvil).
///
/// Hace falta una ventana ancha (la del raíl lateral, desde 600) **y** un
/// ratón o trackpad conectado: con el dedo, en el móvil y en la tablet táctil,
/// sigue la hoja de siempre. Un [context] sin pintar (sin tamaño) tampoco se
/// puede anclar.
bool usesAnchoredPicker(BuildContext context) {
  if (!WindowClass.of(context).usesRail) return false;
  if (!RendererBinding.instance.mouseTracker.mouseIsConnected) return false;
  final box = context.findRenderObject();
  return box is RenderBox && box.attached && box.hasSize;
}

/// La clave de la superficie del desplegable (para las pruebas).
@visibleForTesting
const Key kAnchoredPickerKey = ValueKey<String>('anchored-picker');

/// El alto máximo del desplegable; pasado esto se desplaza por dentro.
const double kAnchoredPickerMaxHeight = 400;

/// Abre un desplegable anclado al campo de [anchor] para elegir una de
/// [options] y devuelve su valor, o `null` si se cierra sin elegir.
///
/// Mide lo que el campo (o [maxWidth], si es menor: entonces se pega a su
/// borde final con [alignEnd] y a su borde inicial si no), sale justo debajo
/// y, si no cabe, encima; nunca se sale de la ventana ni de la zona visible
/// del panel que desplaza al campo. Pasa de [kAnchoredPickerMaxHeight] y se
/// desplaza con la barra de la app.
///
/// Entra desde el borde del campo con una escala de 0,96 a 1 y un fundido
/// (150 ms); sale con un fundido rápido. Con «Reducir movimiento», solo
/// fundido.
///
/// Teclado: arriba y abajo mueven entre las opciones activas (saltan las
/// cabeceras), Inicio y Fin van a la primera y la última, Intro o Espacio
/// eligen y Esc cierra sin elegir. Tab y Mayús+Tab, como un `<select>` del
/// navegador (el «select-only combobox» del APG), eligen la opción enfocada,
/// cierran y llevan el foco al campo siguiente o al anterior. Al abrir queda
/// enfocada la elegida (a la vista) y al cerrar el foco vuelve a
/// [returnFocusTo], o a lo que lo tenía.
///
/// [label] nombra el desplegable (lo lee el lector de pantalla); [description]
/// es una frase fija encima de la lista.
Future<T?> showAnchoredPicker<T>(
  BuildContext anchor, {
  required String label,
  required List<PickerOption<T>> options,
  T? selected,
  String? description,
  double? maxWidth,
  bool alignEnd = false,
  FocusNode? returnFocusTo,
}) async {
  final box = anchor.findRenderObject();
  assert(
    box is RenderBox && box.attached,
    'showAnchoredPicker necesita un ancla pintada',
  );
  if (box is! RenderBox || !box.attached) return null;
  final navigator = Navigator.of(anchor, rootNavigator: true);
  final previousFocus = returnFocusTo ?? FocusManager.instance.primaryFocus;
  // La lista vertical que desplaza al campo (el panel del editor): recorta
  // dónde cabe el desplegable.
  var scrollable = Scrollable.maybeOf(anchor);
  while (scrollable != null &&
      axisDirectionToAxis(scrollable.axisDirection) == Axis.horizontal) {
    scrollable = Scrollable.maybeOf(scrollable.context);
  }
  final route = _AnchoredPickerRoute<T>(
    anchor: anchor,
    anchorBox: box,
    scrollable: scrollable,
    label: label,
    options: options,
    selected: selected,
    description: description,
    maxWidth: maxWidth,
    alignEnd: alignEnd,
    reduce: RegalosMotion.of(anchor).reduce,
    capturedThemes: InheritedTheme.capture(from: anchor, to: navigator.context),
    dismissLabel: MaterialLocalizations.of(anchor).modalBarrierDismissLabel,
  );
  final result = await navigator.push<T>(route);
  if (previousFocus != null && (previousFocus.context?.mounted ?? false)) {
    final step = route.tabStep;
    if (step != 0) {
      // Tab: el foco sigue desde el campo hacia el siguiente (o el anterior
      // con Mayús), como al salir de un `<select>`. Primero vuelve al campo y
      // el valor se devuelve a quien llamó; el foco se mueve cuando el
      // formulario ya lo ha incorporado y pintado (un campo que aparece con
      // la elección, como «Nombre de quien lo pidió», no se salta).
      previousFocus.requestFocus();
      unawaited(_stepFocusAfterFrame(previousFocus, step));
    } else if (result != null && route.pickedByPointer) {
      // Elegida con el ratón o el dedo: el campo vuelve a su borde normal. Con
      // el foco devuelto al campo, el filete del teclado (el modo «teclado»
      // sigue activo desde la última tecla pulsada en el formulario) lo
      // dejaba marcado como si se estuviese editando.
      previousFocus.unfocus(disposition: UnfocusDisposition.scope);
    } else if (previousFocus.canRequestFocus) {
      previousFocus.requestFocus();
    }
  }
  return result;
}

/// Mueve el foco desde [from] al campo siguiente ([step] > 0) o al anterior,
/// pero después de que quien llamó haya recibido el valor y el fotograma que
/// lo incorpora esté pintado. Si el campo ya no está (la elección lo quitó),
/// no hay desde dónde seguir y no se mueve nada.
Future<void> _stepFocusAfterFrame(FocusNode from, int step) async {
  // Quien esperaba el valor lo recibe en este turno y pide su reconstrucción.
  await Future<void>.delayed(Duration.zero);
  WidgetsBinding.instance.scheduleFrame();
  await WidgetsBinding.instance.endOfFrame;
  if (!(from.context?.mounted ?? false)) return;
  if (step > 0) {
    from.nextFocus();
  } else {
    from.previousFocus();
  }
}

/// Lo que se separa el desplegable del campo y de los bordes de la ventana.
const double _gap = 4;
const double _edge = 8;

/// El sitio mínimo (unas 3 filas) que debe quedar en el panel que desplaza al
/// campo, por el lado con más sitio, para que el desplegable se limite a él.
const double _minClippedRoom = 150;

/// La escala de la que entra.
const double _enterScale = 0.96;

const Duration _enterDuration = RegalosMotion.fade;
const Duration _exitDuration = RegalosMotion.popoverExit;

/// `snap` comprimido a los 150 ms de la entrada: el mismo muelle (520 / 38,
/// 375 ms) con el tiempo dividido entre 375 / 150, como el diálogo del editor.
final SpringCurve _enterCurve = () {
  const ratio = 375 / 150;
  return SpringCurve(
    SpringDescription(
      mass: 1,
      stiffness: RegalosSprings.snap.stiffness * ratio * ratio,
      damping: RegalosSprings.snap.damping * ratio,
    ),
    _enterDuration,
  );
}();

class _AnchoredPickerRoute<T> extends PopupRoute<T> {
  _AnchoredPickerRoute({
    required this.anchor,
    required this.anchorBox,
    required this.scrollable,
    required this.label,
    required this.options,
    required this.selected,
    required this.description,
    required this.maxWidth,
    required this.alignEnd,
    required this.reduce,
    required this.capturedThemes,
    required this.dismissLabel,
  });

  final BuildContext anchor;
  final RenderBox anchorBox;
  final ScrollableState? scrollable;
  final String label;
  final List<PickerOption<T>> options;
  final T? selected;
  final String? description;
  final double? maxWidth;
  final bool alignEnd;
  final bool reduce;
  final CapturedThemes capturedThemes;
  final String dismissLabel;

  /// Si la opción se eligió con un puntero (ratón o dedo) y no con el teclado.
  bool pickedByPointer = false;

  /// Si se cerró con Tab (1) o con Mayús+Tab (-1): el foco pasa al campo
  /// siguiente o al anterior en vez de volver al de este desplegable.
  int tabStep = 0;

  // Sin velo: solo recoge el clic de fuera para cerrar.
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => dismissLabel;

  @override
  Duration get transitionDuration =>
      reduce ? RegalosMotion.fade : _enterDuration;

  @override
  Duration get reverseTransitionDuration =>
      reduce ? RegalosMotion.fade : _exitDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => capturedThemes.wrap(
    _AnchoredPage(
      anchor: anchor,
      anchorBox: anchorBox,
      scrollable: scrollable,
      maxWidth: maxWidth,
      alignEnd: alignEnd,
      animation: animation,
      reduce: reduce,
      child: _PickerPanel<T>(
        label: label,
        options: options,
        selected: selected,
        description: description,
      ),
    ),
  );
}

/// Mide dónde está el campo (y la zona que lo recorta) y se lo da al
/// desplegable. Mide fuera de la maquetación: al abrir y, si la ventana
/// cambia, al acabar el fotograma.
class _AnchoredPage extends StatefulWidget {
  const _AnchoredPage({
    required this.anchor,
    required this.anchorBox,
    required this.scrollable,
    required this.maxWidth,
    required this.alignEnd,
    required this.animation,
    required this.reduce,
    required this.child,
  });

  final BuildContext anchor;
  final RenderBox anchorBox;
  final ScrollableState? scrollable;
  final double? maxWidth;
  final bool alignEnd;
  final Animation<double> animation;
  final bool reduce;
  final Widget child;

  @override
  State<_AnchoredPage> createState() => _AnchoredPageState();
}

class _AnchoredPageState extends State<_AnchoredPage> {
  Rect? _field;
  Rect? _clip;

  @override
  void initState() {
    super.initState();
    _measure();
    _watch();
  }

  /// Vuelve a medir al acabar cada fotograma (la ventana cambia, el panel se
  /// desplaza o se anima, la pantalla de debajo se reconstruye) y comprueba
  /// que el campo sigue ahí. No pide fotogramas: si nada se mueve, no corre.
  void _watch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final field = _field;
      final clip = _clip;
      _measure();
      if (mounted && (field != _field || clip != _clip)) setState(() {});
      if (mounted) _watch();
    });
  }

  /// Cierra sin elegir: el campo ya no está o ya no se ve.
  void _dismiss() {
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) Navigator.of(context).pop();
  }

  /// Los rectángulos del campo y de su zona visible, en las coordenadas de la
  /// capa raíz de rutas (la de esta página, que la llena). Si el campo
  /// desaparece (la pantalla se reconstruyó con otro diseño) o el panel lo
  /// desplaza fuera de su vista, cierra el desplegable.
  void _measure() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final base = overlay?.context.findRenderObject();
    if (base is! RenderBox || !base.attached) return;
    final box = widget.anchorBox;
    if (!widget.anchor.mounted || !box.attached || !box.hasSize) {
      _dismiss();
      return;
    }
    Rect? rectOf(RenderBox? box) {
      if (box == null || !box.attached || !box.hasSize) return null;
      return MatrixUtils.transformRect(
        box.getTransformTo(base),
        Offset.zero & box.size,
      );
    }

    final field = rectOf(box);
    final clip = rectOf(
      widget.scrollable?.mounted ?? false
          ? widget.scrollable!.context.findRenderObject() as RenderBox?
          : null,
    );
    if (field != null && clip != null) {
      final inside = field.intersect(clip);
      if (inside.width <= 0 || inside.height <= 0) {
        _dismiss();
        return;
      }
    }
    _field = field ?? _field;
    _clip = clip;
  }

  @override
  Widget build(BuildContext context) => _AnchoredPopup(
    field: _field,
    clip: _clip,
    maxHeight: kAnchoredPickerMaxHeight,
    maxWidth: widget.maxWidth,
    alignEnd: widget.alignEnd,
    animation: widget.animation,
    reduce: widget.reduce,
    child: widget.child,
  );
}

/// Coloca a su hijo anclado al campo [anchor] y lo anima: la posición y el
/// tamaño salen de la maquetación (debajo o encima según quepa), así que el
/// origen de la escala también.
class _AnchoredPopup extends SingleChildRenderObjectWidget {
  const _AnchoredPopup({
    required this.field,
    required this.clip,
    required this.maxHeight,
    required this.maxWidth,
    required this.alignEnd,
    required this.animation,
    required this.reduce,
    required super.child,
  });

  final Rect? field;
  final Rect? clip;
  final double maxHeight;
  final double? maxWidth;
  final bool alignEnd;
  final Animation<double> animation;
  final bool reduce;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderAnchoredPopup(
    field: field,
    clip: clip,
    maxHeight: maxHeight,
    maxWidth: maxWidth,
    alignEnd: alignEnd,
    animation: animation,
    reduce: reduce,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAnchoredPopup renderObject,
  ) {
    renderObject
      ..field = field
      ..clip = clip
      ..maxHeight = maxHeight
      ..maxWidth = maxWidth
      ..alignEnd = alignEnd
      ..animation = animation
      ..reduce = reduce;
  }
}

class _RenderAnchoredPopup extends RenderShiftedBox {
  _RenderAnchoredPopup({
    required this._field,
    required this._clip,
    required this._maxHeight,
    required this._maxWidth,
    required this._alignEnd,
    required this._animation,
    required this._reduce,
  }) : super(null);

  Rect? _field;
  set field(Rect? value) {
    if (_field == value) return;
    _field = value;
    markNeedsLayout();
  }

  Rect? _clip;
  set clip(Rect? value) {
    if (_clip == value) return;
    _clip = value;
    markNeedsLayout();
  }

  double _maxHeight;
  set maxHeight(double value) {
    if (_maxHeight == value) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  double? _maxWidth;
  set maxWidth(double? value) {
    if (_maxWidth == value) return;
    _maxWidth = value;
    markNeedsLayout();
  }

  bool _alignEnd;
  set alignEnd(bool value) {
    if (_alignEnd == value) return;
    _alignEnd = value;
    markNeedsLayout();
  }

  Animation<double> _animation;
  set animation(Animation<double> value) {
    if (_animation == value) return;
    if (attached) _animation.removeListener(markNeedsPaint);
    _animation = value;
    if (attached) _animation.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  bool _reduce;
  set reduce(bool value) {
    if (_reduce == value) return;
    _reduce = value;
    markNeedsPaint();
  }

  /// Si el desplegable se abrió encima del campo.
  bool _above = false;

  /// El punto de la ventana desde el que crece: el borde del campo.
  Offset _origin = Offset.zero;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    final child = this.child;
    if (child == null) return;
    var bounds = (Offset.zero & size).deflate(_edge);
    final field =
        _field ?? Rect.fromLTWH(bounds.center.dx, bounds.center.dy, 0, 0);
    // El panel que desplaza al campo limita dónde cabe el desplegable: no se
    // abre sobre lo que queda fuera de él (los botones del pie del editor).
    final clip = _clip;
    var visible = field;
    if (clip != null) {
      final inside = field.intersect(clip);
      if (inside.width > 0 && inside.height > 0) visible = inside;
      // Se ajusta a ese sitio y la lista se desplaza. Solo si ni 3 filas
      // caben (un diálogo muy bajo, que mide lo que su contenido) se sale del
      // panel hacia el lado con más sitio, sin salir de la ventana.
      final inBounds = bounds.intersect(clip);
      // Con el hueco descontado, como al medir la altura más abajo: si no,
      // con 150 + 3 de sitio quedarían 149 útiles.
      final room = math.max(
        inBounds.bottom - visible.bottom - _gap,
        visible.top - inBounds.top - _gap,
      );
      if (inBounds.width > 0 &&
          inBounds.height > 0 &&
          room >= math.min(_maxHeight, _minClippedRoom)) {
        bounds = inBounds;
      }
    }
    var width = math.min(visible.width, bounds.width);
    final cap = _maxWidth;
    if (cap != null) width = math.min(width, cap);
    final left = (_alignEnd ? visible.right - width : visible.left)
        .clamp(bounds.left, math.max(bounds.left, bounds.right - width))
        .toDouble();
    final below = bounds.bottom - visible.bottom - _gap;
    final above = visible.top - bounds.top - _gap;
    final room = math.max(0.0, math.min(_maxHeight, math.max(below, above)));
    child.layout(
      BoxConstraints(minWidth: width, maxWidth: width, maxHeight: room),
      parentUsesSize: true,
    );
    final height = child.size.height;
    _above = height > below + 0.5;
    final top = _above ? visible.top - _gap - height : visible.bottom + _gap;
    (child.parentData! as BoxParentData).offset = Offset(left, top);
    _origin = Offset(left + width / 2, _above ? top + height : top);
  }

  double get _opacity {
    if (_animation.isCompleted) return 1;
    final v = _animation.value.clamp(0.0, 1.0);
    return _animation.status == AnimationStatus.reverse
        ? RegalosCurves.sheetExit.transform(v)
        : RegalosCurves.fold.transform(v);
  }

  double get _scale {
    if (_reduce ||
        _animation.isCompleted ||
        _animation.status == AnimationStatus.reverse) {
      return 1;
    }
    final v = _animation.value.clamp(0.0, 1.0);
    return _enterScale + (1 - _enterScale) * _enterCurve.transform(v);
  }

  /// La escala alrededor del borde del campo, en coordenadas de este objeto.
  Matrix4 get _scaleMatrix {
    final scale = _scale;
    return Matrix4.identity()
      ..translateByDouble(_origin.dx, _origin.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-_origin.dx, -_origin.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final alpha = (_opacity * 255).round().clamp(0, 255);
    if (alpha == 0) return;
    final shift = (child.parentData! as BoxParentData).offset;
    void paintScaled(PaintingContext context, Offset offset) {
      if (_scale == 1) {
        context.paintChild(child, offset + shift);
      } else {
        context.pushTransform(
          needsCompositing,
          offset,
          _scaleMatrix,
          (context, offset) => context.paintChild(child, offset + shift),
        );
      }
    }

    if (alpha == 255) {
      paintScaled(context, offset);
    } else {
      context.pushOpacity(offset, alpha, paintScaled);
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = (child.parentData! as BoxParentData).offset;
    transform
      ..multiply(_scaleMatrix)
      ..translateByDouble(shift.dx, shift.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    final shift = (child.parentData! as BoxParentData).offset;
    return result.addWithPaintTransform(
      transform: _scaleMatrix,
      position: position,
      hitTest: (result, position) => result.addWithPaintOffset(
        offset: shift,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      ),
    );
  }
}

/// Alto mínimo de una fila del desplegable.
const double _rowMinHeight = 40;

/// El radio de una fila dentro del desplegable (el del desplegable, 8, menos
/// su margen de 4 hacia dentro).
const BorderRadius _rowRadius = RegalosShape.menuRow;

/// El desplegable: superficie con borde y sombra, la frase fija si la hay y la
/// lista de opciones con su barra.
class _PickerPanel<T> extends StatefulWidget {
  const _PickerPanel({
    required this.label,
    required this.options,
    required this.selected,
    required this.description,
  });

  final String label;
  final List<PickerOption<T>> options;
  final T? selected;
  final String? description;

  @override
  State<_PickerPanel<T>> createState() => _PickerPanelState<T>();
}

class _PickerPanelState<T> extends State<_PickerPanel<T>> {
  late final List<FocusNode> _nodes = [
    for (var i = 0; i < widget.options.length; i++)
      FocusNode(
        debugLabel: 'AnchoredPicker.$i',
        canRequestFocus: widget.options[i].enabled,
      ),
  ];
  final ScrollController _scroll = ScrollController();

  /// Las cabeceras de grupo, por el índice de su primera opción.
  final Map<int, GlobalKey> _headerKeys = <int, GlobalKey>{};

  /// La opción que abre enfocada: la elegida, o la primera activa.
  int? _initial;

  /// La última opción enfocada (para saber hacia dónde se mueve el foco).
  int? _focused;

  /// Si la lista no cabe y se desplaza: deja sitio a la barra.
  bool _overflows = false;
  bool _done = false;

  /// Si lo último que tocó la lista fue un puntero (y no una tecla).
  bool _pointerLast = false;

  @override
  void initState() {
    super.initState();
    final options = widget.options;
    for (var i = 0; i < options.length; i++) {
      if (options[i].enabled && options[i].value == widget.selected) {
        _initial = i;
        break;
      }
    }
    _initial ??= _nextEnabled(-1, 1);
    // La elegida, centrada si hay que desplazar: cuando ya se ha maquetado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final i = _initial;
      if (!mounted || i == null) return;
      final context = _nodes[i].context;
      if (context != null) {
        Scrollable.ensureVisible(context, alignment: 0.5);
      }
    });
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  /// La opción activa más cercana a [from] en la dirección [step], o `null`.
  int? _nextEnabled(int from, int step) {
    for (var i = from + step; i >= 0 && i < widget.options.length; i += step) {
      if (widget.options[i].enabled) return i;
    }
    return null;
  }

  void _choose(T value) {
    if (_done) return;
    _done = true;
    final route = ModalRoute.of(context);
    if (route is _AnchoredPickerRoute<T>) {
      route.pickedByPointer = _pointerLast;
    }
    context.haptics.selection();
    Navigator.of(context).pop(value);
  }

  void _close() {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop();
  }

  void _focusAt(int? index) {
    if (index != null) _nodes[index].requestFocus();
  }

  /// Hace visible la opción [index] al llegarle el foco: con su cabecera si es
  /// la primera de un grupo y el foco sube.
  void _reveal(int index) {
    final up = _focused != null && index < _focused!;
    _focused = index;
    final header = _headerKeys[index]?.currentContext;
    final target = up && header != null ? header : _nodes[index].context;
    if (target == null) return;
    final box = target.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    Scrollable.ensureVisible(
      target,
      alignmentPolicy: up
          ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
          : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    _pointerLast = false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    final current = _nodes.indexWhere((n) => n.hasPrimaryFocus);
    if (key == LogicalKeyboardKey.tab) {
      final route = ModalRoute.of(context);
      if (route is _AnchoredPickerRoute<T>) {
        route.tabStep = HardwareKeyboard.instance.isShiftPressed ? -1 : 1;
      }
      final index = current >= 0 ? current : _initial;
      if (index != null && widget.options[index].enabled) {
        _choose(widget.options[index].value);
      } else {
        _close();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _focusAt(_nextEnabled(current, 1) ?? (current < 0 ? null : current));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _focusAt(current < 0 ? _initial : (_nextEnabled(current, -1) ?? current));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _focusAt(_nextEnabled(-1, 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _focusAt(_nextEnabled(widget.options.length, -1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    final overflows = n.metrics.maxScrollExtent > 0.5;
    if (overflows != _overflows) {
      setState(() => _overflows = overflows);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final options = widget.options;
    final rows = <Widget>[];
    String? lastGroup;
    for (var i = 0; i < options.length; i++) {
      final o = options[i];
      final group = o.group;
      if (group != null && group != lastGroup) {
        final count = options.where((x) => x.group == group).length;
        rows.add(
          SectionHeader(
            key: _headerKeys.putIfAbsent(i, GlobalKey.new),
            title: group,
            trailing: '$count',
            bordered: false,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          ),
        );
      }
      lastGroup = group;
      rows.add(
        _PickerRow<T>(
          option: o,
          focusNode: _nodes[i],
          selected: o.value == widget.selected,
          autofocus: i == _initial,
          onFocus: () => _reveal(i),
          onTap: () => _choose(o.value),
        ),
      );
    }
    final description = widget.description;
    final surface = Material(
      color: t.sheet,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: RegalosShape.card,
        // Filete de 1 px: en oscuro, el de los controles, que sí se ve.
        side: BorderSide(color: t.isDark ? t.outline : t.separator),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (description != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Text(description, style: t.styles.meta),
            ),
            Divider(height: 1, thickness: 1, color: t.separator),
          ],
          Flexible(
            // Material ya pone otra barra a las listas del escritorio: aquí
            // se pone la de la app y siempre, también con el ratón en una
            // tablet.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(scrollbars: false),
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: _onMetrics,
                child: Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      4,
                      4,
                      _overflows ? AppScrollbar.gutter : 4,
                      4,
                    ),
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (_) => _pointerLast = true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: rows,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      role: SemanticsRole.menu,
      label: widget.label,
      child: Focus(
        // Recoge las flechas, Esc y Tab de la opción enfocada.
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: DecoratedBox(
          key: kAnchoredPickerKey,
          decoration: BoxDecoration(
            borderRadius: RegalosShape.card,
            boxShadow: [
              BoxShadow(
                color: t.shadow,
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: surface,
        ),
      ),
    );
  }
}

class _PickerRow<T> extends StatelessWidget {
  const _PickerRow({
    required this.option,
    required this.focusNode,
    required this.selected,
    required this.autofocus,
    required this.onFocus,
    required this.onTap,
  });

  final PickerOption<T> option;
  final FocusNode focusNode;
  final bool selected;
  final bool autofocus;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final enabled = option.enabled;
    final hint = option.hint;
    return Semantics(
      container: true,
      role: SemanticsRole.menuItemRadio,
      enabled: enabled,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      selected: selected,
      label: hint == null ? option.label : '${option.label}. $hint',
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: PointerSurface(
        radius: _rowRadius,
        enabled: enabled,
        child: Material(
          color: selected ? t.selection : Colors.transparent,
          borderRadius: _rowRadius,
          child: InkWell(
            focusNode: focusNode,
            autofocus: autofocus,
            canRequestFocus: enabled,
            onFocusChange: (focused) {
              if (focused) onFocus();
            },
            borderRadius: _rowRadius,
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _rowMinHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    if (option.leading != null) ...[
                      SizedBox.square(
                        dimension: 28,
                        child: Center(
                          child: Opacity(
                            opacity: enabled ? 1 : 0.5,
                            child: option.leading,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            option.label,
                            style: t.styles.body.copyWith(
                              fontWeight: selected ? FontWeight.w700 : null,
                              color: !enabled
                                  ? t.textSecondary
                                  : (selected ? t.textOnSoft : null),
                            ),
                          ),
                          if (hint != null) Text(hint, style: t.styles.meta),
                        ],
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 10),
                      StrokeIcon(
                        AppIcons.check,
                        size: 20,
                        color: t.textOnSoft,
                        strokeWidth: 2,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
