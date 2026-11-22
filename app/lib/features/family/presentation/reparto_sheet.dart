// ignore_for_file: prefer_initializing_formals
import '../../web_device/application/web_app_provider.dart';

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../../../core/layout/large_text.dart';
import '../../../core/layout/pane_scope.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/protected_doc.dart' show ProtectedPersonException;
import '../../../core/theme/occasion_theme.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/giver_dot.dart';
import '../../../core/widgets/gift_status_map.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/status_checkbox.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../gifts/presentation/gift_editor_screen.dart';
import '../application/family_controller.dart';
import '../application/family_providers.dart';
import 'family_texts.dart';
import 'giver_person_flow.dart';
import 'giver_picker.dart';
import 'reparto_grid.dart';
import 'reparto_person_sheet.dart';

/// Clave de la hoja de una celda (para las pruebas).
const Key kRepartoSheetKey = ValueKey<String>('repartoSheet');

/// Abre la hoja de una celda de Reparto: crece desde la celda ([from]) hasta
/// quedar abajo, con los regalos de esa persona y de quien regala.
///
/// [giver] nulo es la hoja de los regalos sin quién regala. [empty] es una
/// celda sin regalos: [giftIds] son entonces los de esa persona que aún no
/// tienen quién los regale. [onOpenList] lleva a la lista completa de la
/// persona.
///
/// En una ventana ancha la hoja mide 560 y se centra en el panel de
/// [context] (el área de contenido, sin el raíl); el velo cubre la ventana.
Future<void> showRepartoSheet(
  BuildContext context, {
  required Rect from,
  required Color fromColor,
  required Recipient recipient,
  required Giver? giver,
  required List<String> giftIds,
  required bool empty,
  required String? occasionId,
  required RepartoBumps bumps,
  required VoidCallback onOpenList,
}) {
  final anchor = PaneScope.anchorOf(context);
  return Navigator.of(context, rootNavigator: true).push<void>(
    _SheetRoute(
      builder: (_) => _RepartoSheet(
        anchor: anchor,
        from: from,
        fromColor: fromColor,
        recipient: recipient,
        giver: giver,
        giftIds: giftIds,
        empty: empty,
        occasionId: occasionId,
        bumps: bumps,
        onOpenList: onOpenList,
      ),
    ),
  );
}

/// Abre la ficha de una persona de Reparto: sube desde [from] (su nombre)
/// con la misma animación que la hoja de una celda. Lleva «Sale en el
/// reparto» y una casilla por ocasión; [onOpenList] lleva a su lista.
Future<void> showRepartoPersonSheet(
  BuildContext context, {
  required Rect from,
  required Recipient recipient,
  required VoidCallback onOpenList,
}) {
  final t = RegalosTokens.of(context);
  final l10n = AppLocalizations.of(context);
  final anchor = PaneScope.anchorOf(context);
  return Navigator.of(context, rootNavigator: true).push<void>(
    _SheetRoute(
      builder: (_) => _RepartoSheet.person(
        anchor: anchor,
        from: from,
        fromColor: t.bg,
        recipient: recipient,
        label: l10n.repartoPersonSheetLabel(recipient.name),
        contentBuilder: (onClose, onDrag, onDragEnd) => RepartoPersonSheet(
          recipient: recipient,
          onClose: onClose,
          onOpenList: onOpenList,
          onDrag: onDrag,
          onDragEnd: onDragEnd,
        ),
      ),
    ),
  );
}

/// La ruta de la hoja: sin transición propia (la hoja se anima a sí misma, con
/// muelles) y sin velo (lo pinta ella).
class _SheetRoute extends PopupRoute<void> {
  _SheetRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);
}

class _RepartoSheet extends StatefulWidget {
  const _RepartoSheet({
    required this.anchor,
    required this.from,
    required this.fromColor,
    required this.recipient,
    required this.giver,
    required this.giftIds,
    required this.empty,
    required this.occasionId,
    required this.bumps,
    required this.onOpenList,
  }) : label = null,
       contentBuilder = null;

  /// La hoja de una persona: el mismo marco, otro contenido.
  _RepartoSheet.person({
    required this.anchor,
    required this.from,
    required this.fromColor,
    required this.recipient,
    required String this.label,
    required this.contentBuilder,
  }) : giver = null,
       giftIds = const <String>[],
       empty = false,
       occasionId = null,
       bumps = RepartoBumps(),
       onOpenList = _noop;

  static void _noop() {}

  /// El panel desde el que se abrió la hoja, para centrarla en él en una
  /// ventana ancha; `null` si no había panel (se centra en la ventana).
  final ValueListenable<Rect>? anchor;

  final Rect from;
  final Color fromColor;
  final Recipient recipient;
  final Giver? giver;
  final List<String> giftIds;
  final bool empty;
  final String? occasionId;
  final RepartoBumps bumps;
  final VoidCallback onOpenList;

  /// El nombre de la hoja para el lector de pantalla; `null`: el de la hoja
  /// de una celda.
  final String? label;

  /// El contenido propio de la hoja, en lugar de los regalos de una celda.
  final Widget Function(
    Future<void> Function({bool pop}) onClose,
    ValueChanged<double> onDrag,
    ValueChanged<double> onDragEnd,
  )?
  contentBuilder;

  @override
  State<_RepartoSheet> createState() => _RepartoSheetState();
}

class _RepartoSheetState extends State<_RepartoSheet>
    with TickerProviderStateMixin {
  /// 0 → 1: la hoja crece desde la celda (muelle `snap`). Sin límites, porque
  /// el muelle se pasa un 0,4 %.
  late final AnimationController _grow = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  /// 0 → 1: la hoja se desliza hacia abajo para irse.
  late final AnimationController _slide = AnimationController(vsync: this);

  final GlobalKey<_SheetContentState> _content = GlobalKey();
  bool _closing = false;
  bool _started = false;

  /// Sin panel: un rectángulo vacío, que cuenta como la ventana entera.
  static const ValueListenable<Rect> _noPane = AlwaysStoppedAnimation<Rect>(
    Rect.zero,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    if (RegalosMotion.of(context).reduce) {
      _grow.animateTo(1, duration: RegalosMotion.fade, curve: Curves.linear);
    } else {
      _grow.animateWith(SpringSimulation(RegalosSprings.snap, 0, 1, 0));
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    _slide.dispose();
    widget.bumps.clear();
    super.dispose();
  }

  Future<void> _close({bool pop = true}) async {
    if (_closing) {
      return;
    }
    _closing = true;
    _content.currentState?.flush();
    final reduce = RegalosMotion.of(context).reduce;
    final navigator = Navigator.of(context);
    if (reduce) {
      await _grow.animateTo(
        0,
        duration: RegalosMotion.fade,
        curve: Curves.linear,
      );
    } else {
      final left = 1 - _slide.value;
      await _slide.animateTo(
        1,
        duration: RegalosCurves.sheetExitDuration * left,
        curve: RegalosCurves.sheetExit,
      );
    }
    if (mounted && pop) {
      navigator.pop();
    }
  }

  void _drag(double dy) {
    if (_closing || RegalosMotion.of(context).reduce) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final height = (box?.size.height ?? 600) * 0.6;
    _slide.value = (_slide.value + dy / height).clamp(0.0, 1.0);
  }

  void _dragEnd(double velocity) {
    if (_closing || RegalosMotion.of(context).reduce) {
      return;
    }
    if (velocity > 700 || _slide.value > 0.35) {
      // La vibración llega cuando la hoja toca fondo.
      context.haptics.light(after: RegalosCurves.sheetExitDuration);
      _close();
    } else {
      // Soltarla a medias: vuelve con un clic cuando el muelle se asienta.
      final box = context.findRenderObject() as RenderBox?;
      final dragged = _slide.value * (box?.size.height ?? 600) * 0.6;
      if (dragged > kHapticMinDrag) {
        context.haptics.selection(after: kHapticSpringArrival);
      }
      _slide.animateWith(
        SpringSimulation(RegalosSprings.snap, _slide.value, 0, 0),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final giverName = giverNameFor(l10n, widget.giver);
    // En el móvil la hoja va de lado a lado, como siempre. Desde 600 dp mide
    // 560 y se centra en el panel desde el que se abrió.
    final window = MediaQuery.sizeOf(context);
    final wide = WindowClass.fromSize(window).usesRail;
    final sheet = Material(
      key: kRepartoSheetKey,
      type: MaterialType.transparency,
      child: widget.contentBuilder != null
          ? widget.contentBuilder!(_close, _drag, _dragEnd)
          : _SheetContent(
              key: _content,
              recipient: widget.recipient,
              giver: widget.giver,
              giftIds: widget.giftIds,
              empty: widget.empty,
              occasionId: widget.occasionId,
              bumps: widget.bumps,
              onClose: _close,
              onOpenList: () {
                widget.onOpenList();
              },
              onDrag: _drag,
              onDragEnd: _dragEnd,
            ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _close();
        }
      },
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label:
            widget.label ??
            l10n.repartoSheetLabel(giverName, widget.recipient.name),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // El velo se funde con `soft`.
            AnimatedBuilder(
              animation: Listenable.merge([_grow, _slide]),
              builder: (context, _) {
                final grow = motion.reduce
                    ? _grow.value.clamp(0.0, 1.0)
                    : RegalosCurves.soft.transform(_grow.value.clamp(0.0, 1.0));
                final slide = motion.reduce ? 0.0 : _slide.value;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _close,
                  child: Semantics(
                    button: true,
                    label: l10n.actionClose,
                    onTap: _close,
                    child: ColoredBox(
                      color: t.scrim.withValues(
                        alpha: t.scrim.a * grow * (1 - slide),
                      ),
                    ),
                  ),
                );
              },
            ),
            // El mismo árbol a cualquier ancho: girar con la hoja abierta no
            // pierde nada. Fuera de la hoja (a sus lados) el toque llega al
            // velo y la cierra.
            ValueListenableBuilder<Rect>(
              valueListenable: widget.anchor ?? _noPane,
              builder: (context, pane, child) => Padding(
                padding: wide
                    ? PaneAligned.insetsFor(
                        pane: pane,
                        windowWidth: window.width,
                        maxWidth: RegalosLayout.sheetWidth,
                      )
                    : EdgeInsets.zero,
                child: child,
              ),
              child: _Reveal(
                grow: _grow,
                // Con «Reducir movimiento» se funde toda la hoja; si no, solo
                // el contenido (la hoja ya crece).
                wholeSheet: motion.reduce,
                builder: (content) => _GrowingSheet(
                  from: widget.from,
                  fromColor: widget.fromColor,
                  color: t.sheet,
                  edge: t.sheetEdge,
                  shadow: t.shadow,
                  morph: !motion.reduce,
                  grow: _grow,
                  slide: _slide,
                  child: content,
                ),
                child: sheet,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El contenido de la hoja entra a partir del 30 % del crecimiento; con
/// «Reducir movimiento» ([wholeSheet]) es un fundido de toda la hoja.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.grow,
    required this.wholeSheet,
    required this.builder,
    required this.child,
  });

  final AnimationController grow;
  final bool wholeSheet;
  final Widget Function(Widget content) builder;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: grow,
    child: child,
    builder: (context, child) {
      final g = grow.value.clamp(0.0, 1.0);
      final opacity = wholeSheet ? g : ((g - 0.3) / 0.7).clamp(0.0, 1.0);
      final faded = !wholeSheet && opacity < 1
          ? Opacity(opacity: opacity, child: child)
          : child!;
      final sheet = builder(faded);
      return wholeSheet && opacity < 1
          ? Opacity(opacity: opacity, child: sheet)
          : sheet;
    },
  );
}

/// La hoja que crece: pinta un rectángulo redondeado que va de la celda a su
/// sitio final (abajo, a todo lo ancho del sitio que le dan), con la forma
/// de una hoja (esquinas de 8 por arriba, rectas por abajo), y el contenido
/// recortado por él.
class _GrowingSheet extends SingleChildRenderObjectWidget {
  const _GrowingSheet({
    required this.from,
    required this.fromColor,
    required this.color,
    required this.edge,
    required this.shadow,
    required this.morph,
    required this.grow,
    required this.slide,
    super.child,
  });

  final Rect from;
  final Color fromColor;
  final Color color;
  final Color edge;
  final Color shadow;
  final bool morph;
  final ValueListenable<double> grow;
  final ValueListenable<double> slide;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGrowingSheet(
    from: from,
    fromColor: fromColor,
    color: color,
    edge: edge,
    shadow: shadow,
    morph: morph,
    grow: grow,
    slide: slide,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGrowingSheet renderObject,
  ) {
    renderObject
      ..from = from
      ..fromColor = fromColor
      ..color = color
      ..edge = edge
      ..shadow = shadow
      ..morph = morph
      ..grow = grow
      ..slide = slide;
  }
}

class _RenderGrowingSheet extends RenderShiftedBox {
  _RenderGrowingSheet({
    required Rect from,
    required Color fromColor,
    required Color color,
    required Color edge,
    required Color shadow,
    required bool morph,
    required ValueListenable<double> grow,
    required ValueListenable<double> slide,
  }) : _from = from,
       _fromColor = fromColor,
       _color = color,
       _edge = edge,
       _shadow = shadow,
       _morph = morph,
       _grow = grow,
       _slide = slide,
       super(null);

  static const double _maxHeightFraction = 0.82;

  Rect _from;
  set from(Rect v) {
    if (_from != v) {
      _from = v;
      markNeedsPaint();
    }
  }

  Color _fromColor;
  set fromColor(Color v) {
    if (_fromColor != v) {
      _fromColor = v;
      markNeedsPaint();
    }
  }

  Color _color;
  set color(Color v) {
    if (_color != v) {
      _color = v;
      markNeedsPaint();
    }
  }

  Color _edge;
  set edge(Color v) {
    if (_edge != v) {
      _edge = v;
      markNeedsPaint();
    }
  }

  Color _shadow;
  set shadow(Color v) {
    if (_shadow != v) {
      _shadow = v;
      markNeedsPaint();
    }
  }

  bool _morph;
  set morph(bool v) {
    if (_morph != v) {
      _morph = v;
      markNeedsPaint();
    }
  }

  ValueListenable<double> _grow;
  set grow(ValueListenable<double> v) {
    if (_grow != v) {
      if (attached) {
        _grow.removeListener(markNeedsPaint);
        v.addListener(markNeedsPaint);
      }
      _grow = v;
      markNeedsPaint();
    }
  }

  ValueListenable<double> _slide;
  set slide(ValueListenable<double> v) {
    if (_slide != v) {
      if (attached) {
        _slide.removeListener(markNeedsPaint);
        v.addListener(markNeedsPaint);
      }
      _slide = v;
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _grow.addListener(markNeedsPaint);
    _slide.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _grow.removeListener(markNeedsPaint);
    _slide.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final child = this.child;
    if (child == null) {
      return;
    }
    child.layout(
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height * _maxHeightFraction,
      ),
      parentUsesSize: true,
    );
    (child.parentData! as BoxParentData).offset = Offset(
      0,
      size.height - child.size.height,
    );
  }

  /// Dónde está la hoja ahora, en coordenadas de esta caja.
  Rect _currentRect() {
    final h = child!.size.height;
    final end = Rect.fromLTWH(0, size.height - h, size.width, h);
    var r = end;
    if (_morph) {
      // Decisión de producto (2026-11-11): todas las hojas suben desde
      // abajo, como una tarjeta; crecer desde cada celda quedaba raro.
      // `_from` ya no se usa para la posición.
      r = end.shift(Offset(0, (1 - _grow.value) * (size.height - end.top)));
    }
    final dy = _slide.value * (size.height - end.top);
    return r.shift(Offset(0, dy));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      return;
    }
    final r = _currentRect();
    const g = 1.0; // la forma ya es la final mientras sube
    final top = Radius.circular(
      lerpDouble(RegalosShape.cardRadius, RegalosShape.sheetRadius, g)!,
    );
    final bottom = Radius.circular(
      math.max(0, lerpDouble(RegalosShape.cardRadius, 0, g)!),
    );
    final rrect = RRect.fromRectAndCorners(
      r,
      topLeft: top,
      topRight: top,
      bottomLeft: bottom,
      bottomRight: bottom,
    );
    final shifted = rrect.shift(offset);
    context.canvas
      ..drawShadow(
        Path()..addRRect(shifted),
        _shadow.withValues(alpha: 0.5),
        8 * g,
        true,
      )
      ..drawRRect(shifted, Paint()..color = Color.lerp(_fromColor, _color, g)!)
      // Filo de 1 px más claro arriba (solo en oscuro; en claro es invisible).
      ..drawRRect(
        shifted.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _edge,
      );
    context.pushClipRRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      rrect,
      (inner, innerOffset) => inner.paintChild(child, innerOffset + r.topLeft),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) {
      return false;
    }
    final r = _currentRect();
    return result.addWithPaintOffset(
      offset: r.topLeft,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final r = _currentRect();
    transform.translateByDouble(r.left, r.top, 0, 1);
  }
}

/// Lo que lleva la hoja: título, regalos con su chip de quién regala y los
/// botones.
class _SheetContent extends ConsumerStatefulWidget {
  const _SheetContent({
    super.key,
    required this.recipient,
    required this.giver,
    required this.giftIds,
    required this.empty,
    required this.occasionId,
    required this.bumps,
    required this.onClose,
    required this.onOpenList,
    required this.onDrag,
    required this.onDragEnd,
  });

  final Recipient recipient;
  final Giver? giver;
  final List<String> giftIds;
  final bool empty;
  final String? occasionId;
  final RepartoBumps bumps;
  final Future<void> Function({bool pop}) onClose;
  final VoidCallback onOpenList;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;

  @override
  ConsumerState<_SheetContent> createState() => _SheetContentState();
}

class _SheetContentState extends ConsumerState<_SheetContent> {
  /// El regalo con la fila de chips desplegada.
  String? _openId;

  /// La elección hecha y aún sin guardar (el chip ya cambió de forma).
  ({String giftId, String? giverId})? _pending;
  Timer? _foldTimer;
  Timer? _applyTimer;

  @override
  void dispose() {
    _foldTimer?.cancel();
    _applyTimer?.cancel();
    super.dispose();
  }

  void _toggle(String giftId) {
    flush();
    setState(() => _openId = _openId == giftId ? null : giftId);
  }

  void _pick(Gift gift, String? giverId) {
    final view = ref.read(familyViewProvider);
    if (giverId == view.resolveGiver(gift.giverId)?.id &&
        view.giversByOriginalId[gift.giverId]?.archived != true) {
      setState(() => _openId = null);
      return;
    }
    flush();
    final motion = RegalosMotion.of(context);
    setState(() => _pending = (giftId: gift.id, giverId: giverId));
    // El chip cambia de forma (375 ms); luego la fila se pliega (180 ms) y
    // entonces se guarda: las celdas de detrás rebotan con el número nuevo.
    _foldTimer = Timer(
      motion.reduce ? Duration.zero : RegalosSprings.snapDuration,
      () {
        if (!mounted) {
          return;
        }
        setState(() => _openId = null);
        _applyTimer = Timer(
          motion.reduce ? Duration.zero : RegalosCurves.foldDuration,
          _apply,
        );
      },
    );
  }

  /// Asigna una persona de la familia como quién regala, al momento. En un
  /// regalo secreto pasa antes por el paso explícito.
  Future<void> _pickPerson(Gift gift, GiverPersonCandidate candidate) async {
    flush();
    final previous = ref.read(familyViewProvider).repartoGiverId(gift);
    final result = await assignGiftToPerson(
      context,
      ref,
      gift: gift,
      candidate: candidate,
    );
    if (!mounted || result == null) {
      return;
    }
    final saved = result == GiftWriteResult.saved;
    setState(() => _openId = null);
    if (saved) {
      final now = ref
          .read(familyViewProvider)
          .giverForPerson(candidate.person.id)
          ?.id;
      widget.bumps.mark([
        if (previous != null) repartoCellKey(gift.recipientId, previous),
        if (now != null) repartoCellKey(gift.recipientId, now),
      ]);
    } else {
      showRegalosSnackBar(
        context,
        SnackBar(
          content: Text(
            giftWriteResultText(
              AppLocalizations.of(context),
              result,
              web: ref.read(webAppProvider),
            ),
          ),
        ),
      );
    }
  }

  /// Termina ya lo que esté a medias (un segundo toque, cerrar la hoja).
  void flush() {
    if (_pending == null) {
      return;
    }
    _foldTimer?.cancel();
    _applyTimer?.cancel();
    if (_openId != null && mounted) {
      setState(() => _openId = null);
    }
    _apply();
  }

  Future<void> _apply() async {
    final pending = _pending;
    if (pending == null) {
      return;
    }
    _pending = null;
    final view = ref.read(familyViewProvider);
    final gift = view.gifts.where((g) => g.id == pending.giftId).firstOrNull;
    if (gift == null) {
      return;
    }
    final bumps = widget.bumps;
    final result = await ref
        .read(familyControllerProvider.notifier)
        .setGiftGiver(gift.id, pending.giverId)
        .onError<ProtectedPersonException>(
          (error, _) => error.savedLocally
              ? GiftWriteResult.saved
              : GiftWriteResult.giftUnavailable,
        );
    final saved = result == GiftWriteResult.saved;
    if (saved) {
      final previous = view.repartoGiverId(gift);
      bumps.mark([
        if (previous != null) repartoCellKey(gift.recipientId, previous),
        repartoCellKey(gift.recipientId, pending.giverId),
      ]);
    }
    if (mounted) {
      setState(() {});
      if (!saved) {
        showRegalosSnackBar(
          context,
          SnackBar(
            content: Text(
              giftWriteResultText(
                AppLocalizations.of(context),
                result,
                web: ref.read(webAppProvider),
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final view = ref.watch(familyViewProvider);
    final byId = {for (final g in view.gifts) g.id: g};
    final gifts = [
      for (final id in widget.giftIds)
        if (byId[id] != null) byId[id]!,
    ];
    final person = widget.recipient;
    final giver = widget.giver;
    final giverName = giverNameFor(l10n, giver);
    final unassigned = widget.empty && gifts.isNotEmpty;

    var planned = 0;
    var spent = 0;
    for (final g in gifts) {
      planned += g.plannedCents ?? 0;
      spent += g.spentCents;
    }
    final cents = spent > 0 ? spent : planned;
    final price = cents > 0
        ? formatCents(cents, l10n.localeName)
        : l10n.familyNoPrice;

    final Widget title;
    final String sub;
    if (widget.empty) {
      title = Text(
        l10n.repartoSheetNobodyYet(giverName, person.name),
        style: t.styles.screenTitleSmall.copyWith(fontSize: 18, height: 1.3),
      );
      sub = unassigned
          ? l10n.repartoSheetUnassignedHint(person.name)
          : l10n.repartoSheetStartHint;
    } else {
      final titleStyle = t.styles.rowTitle.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
      );
      // Con letra grande quién regala y a quién van en dos líneas: juntos no
      // caben y uno de los dos acababa en «…».
      final stacked = isLargeText(context);
      final giverPart = <Widget>[
        if (giver != null) ...[
          GiverDot(colorIndex: giver.colorIndex, size: 10),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            giver == null ? l10n.repartoSheetNoGiver : giverName,
            maxLines: stacked ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
      ];
      final personPart = <Widget>[
        if (!stacked) ...[
          const SizedBox(width: 6),
          StrokeIcon(AppIcons.chevronRight, size: 16, color: t.ideaStroke),
          const SizedBox(width: 6),
        ],
        RepartoAvatar(
          name: person.name,
          colorIndex: person.colorIndex,
          size: 24,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
      ];
      title = stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: giverPart),
                const SizedBox(height: 4),
                Row(children: personPart),
              ],
            )
          : Row(children: [...giverPart, ...personPart]);
      sub = l10n.repartoSheetSummary(l10n.giftCount(gifts.length), price);
    }

    final newGiftLabel = widget.empty
        ? l10n.repartoSheetNewGiftFrom(giverName)
        : l10n.repartoSheetAddGift;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final large = isLargeText(context);
    final actions = <Widget>[
      const SizedBox(height: 12),
      _SheetButton(
        label: newGiftLabel,
        onTap: () => openGiftEditor(
          context,
          recipientId: person.id,
          giverId: giver?.id,
          occasionId: widget.occasionId,
        ),
      ),
      Align(
        alignment: Alignment.center,
        child: TextButton(
          style: TextButton.styleFrom(
            shape: const RoundedRectangleBorder(
              borderRadius: RegalosShape.button,
            ),
          ),
          onPressed: () async {
            await widget.onClose(pop: false);
            if (context.mounted) {
              Navigator.of(context).pop();
            }
            widget.onOpenList();
          },
          child: Text(
            l10n.repartoSheetOpenList(person.name),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Se arrastra por el asa y el título.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) => widget.onDrag(d.delta.dy),
            onVerticalDragEnd: (d) =>
                widget.onDragEnd(d.velocity.pixelsPerSecond.dy),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.chipBorder,
                      borderRadius: const BorderRadius.all(Radius.circular(2)),
                    ),
                    child: const SizedBox(width: 36, height: 4),
                  ),
                ),
                const SizedBox(height: 14),
                Semantics(header: true, child: title),
                const SizedBox(height: 3),
                Text(sub, style: t.styles.meta),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < gifts.length; i++)
                    _GiftEntry(
                      key: ValueKey<String>(gifts[i].id),
                      gift: gifts[i],
                      first: i == 0,
                      view: view,
                      open: _openId == gifts[i].id,
                      pickedGiverId:
                          _pending != null && _pending!.giftId == gifts[i].id
                          ? (_pending!.giverId, true)
                          : null,
                      onToggle: () => _toggle(gifts[i].id),
                      onPick: (id) => _pick(gifts[i], id),
                      onPickPerson: (c) => _pickPerson(gifts[i], c),
                      onOpenGift: () => openGiftEditor(context, gift: gifts[i]),
                    ),
                  // Con letra grande los botones no caben fijos debajo sin
                  // dejar la lista sin sitio: se desplazan con ella.
                  if (large) ...actions,
                ],
              ),
            ),
          ),
          if (!large) ...actions,
        ],
      ),
    );
  }
}

/// El botón principal de la hoja: relleno del acento, esquinas de 8.
class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Material(
      color: t.fill,
      shape: const RoundedRectangleBorder(borderRadius: RegalosShape.button),
      child: InkWell(
        onTap: onTap,
        customBorder: const RoundedRectangleBorder(
          borderRadius: RegalosShape.button,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StrokeIcon(AppIcons.plus, size: 18, color: t.onFill),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    // Con letra grande «Regalo nuevo de …» pasa a dos líneas
                    // en vez de acabar en «…».
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: t.styles.label.copyWith(
                      color: t.onFill,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un regalo de la hoja: su casilla, su título, el chip de quién lo regala y,
/// desplegada debajo, la fila para cambiarlo.
class _GiftEntry extends ConsumerWidget {
  const _GiftEntry({
    super.key,
    required this.gift,
    required this.first,
    required this.view,
    required this.open,
    required this.pickedGiverId,
    required this.onToggle,
    required this.onPick,
    required this.onPickPerson,
    required this.onOpenGift,
  });

  final Gift gift;
  final bool first;
  final FamilyView view;
  final bool open;

  /// La elección pendiente de este regalo (`(giverId, true)`), o `null`.
  final (String?, bool)? pickedGiverId;
  final VoidCallback onToggle;
  final ValueChanged<String?> onPick;
  final ValueChanged<GiverPersonCandidate> onPickPerson;
  final VoidCallback onOpenGift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final occasion = gift.occasionId == null
        ? null
        : view.occasionsById[gift.occasionId];
    final price = giftPriceText(l10n, gift) ?? l10n.familyNoPrice;
    final giver = view.resolveGiver(
      pickedGiverId == null ? gift.giverId : pickedGiverId!.$1,
    );
    final selectedId = giver?.id;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: t.separator)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: GiftRowLayout(
              large: isLargeText(context),
              indent: 34,
              info: Semantics(
                button: true,
                label: gift.title,
                excludeSemantics: true,
                onTap: onOpenGift,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onOpenGift,
                  child: Row(
                    children: [
                      StatusHoverTip(
                        status: gift.status.visualStatus,
                        child: StatusGlyph(
                          status: gift.status.visualStatus,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              gift.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.styles.rowTitleCompact.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _GiftMeta(
                              occasion: occasion,
                              price: price,
                              recipientName: view
                                  .recipientsById[occasion?.recipientId]
                                  ?.name,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              chip: GiverChip(giver: giver, onTap: onToggle),
            ),
          ),
          // La fila de chips se despliega en línea con un muelle y se pliega
          // sin rebotar.
          AnimatedSize(
            // Con «Reducir movimiento» la fila aparece sin desplegarse (solo
            // se funden los chips): en un fotograma y no con `Duration.zero`,
            // que hace a `AnimatedSize` marcarse para maquetar dentro de su
            // propia maquetación cuando su hijo cambia de tamaño (al girar
            // con la hoja abierta, por ejemplo).
            duration: motion.reduce
                ? const Duration(milliseconds: 1)
                : (open
                      ? RegalosSprings.snapDuration
                      : RegalosCurves.foldDuration),
            curve: open ? RegalosCurves.snap : RegalosCurves.fold,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.only(
                      left: 34,
                      top: 2,
                      bottom: 12,
                    ),
                    child: GiverPicker(
                      givers: view.selectableGiversFor(gift.recipientId),
                      selectedId: selectedId,
                      onPick: onPick,
                      people: personSectionOf(
                        ref.watch(giftGiverPersonCandidatesProvider(gift.id)),
                      ),
                      onPickPerson: onPickPerson,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _GiftMeta extends StatelessWidget {
  const _GiftMeta({
    required this.occasion,
    required this.price,
    required this.recipientName,
  });

  final Occasion? occasion;
  final String price;
  final String? recipientName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final o = occasion;
    // Un solo texto que se parte en líneas: con letra grande no desborda.
    return Text.rich(
      TextSpan(
        children: [
          if (o != null) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: OccasionTheme.forOccasion(o).mark(dark: t.isDark),
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 7),
                  ),
                ),
              ),
            ),
            TextSpan(
              text: '${occasionTitle(l10n, o, personName: recipientName)} · ',
            ),
          ],
          TextSpan(text: price),
        ],
      ),
      maxLines: isLargeText(context) ? 4 : 2,
      overflow: TextOverflow.ellipsis,
      style: t.styles.caption,
    );
  }
}
