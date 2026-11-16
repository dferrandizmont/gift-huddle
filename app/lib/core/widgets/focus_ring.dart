import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';

/// El foco visible del teclado (plan de escritorio, §2.3): un filete de 2 px de
/// la tinta del acento, radio 8, por fuera del control que tiene el foco.
///
/// Se pinta una sola vez para toda la app, encima de lo demás, siguiendo al
/// control con foco: así lo llevan todos los botones, filas y casillas sin
/// que cada uno tenga que saberlo. **Solo con teclado**: el sistema pasa a
/// modo «tradicional» al pulsar Tab o una flecha y vuelve a «táctil» al tocar
/// o hacer clic, y entonces el filete desaparece. Nunca en un campo de texto
/// (ya trae su borde de foco) ni en un ámbito.
///
/// Al pasar el foco de un control a otro el filete viaja de uno a otro en
/// [travelDuration] (120 ms, `easeOut`); con «Reducir movimiento» salta. Al
/// aparecer (el primer foco con teclado) no viaja de ninguna parte.
class FocusRingOverlay extends StatefulWidget {
  /// Pone el filete de foco encima de [child].
  const FocusRingOverlay({super.key, required this.child});

  final Widget child;

  /// Lo que tarda el filete en viajar de un control al siguiente.
  static const Duration travelDuration = Duration(milliseconds: 120);

  @override
  State<FocusRingOverlay> createState() => _FocusRingOverlayState();
}

/// Si en [node] se ve el filete (para las pruebas).
@visibleForTesting
bool focusRingable(FocusNode node) => _FocusRingOverlayState._ringable(node);

class _FocusRingOverlayState extends State<FocusRingOverlay>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<Rect?> _ring = ValueNotifier<Rect?>(null);
  bool _scheduled = false;

  // El viaje entre dos controles: de dónde sale el filete y con qué foco.
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: FocusRingOverlay.travelDuration,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  Rect? _from;
  FocusNode? _lastNode;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_measureSoon);
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_measureSoon);
    FocusManager.instance.removeHighlightModeListener(_onMode);
    _ring.dispose();
    _travel.dispose();
    super.dispose();
  }

  void _onMode(FocusHighlightMode mode) => _measureSoon();

  void _measureSoon() {
    if (_scheduled || !mounted) {
      return;
    }
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) {
        return;
      }
      _measure();
      // Mientras haya filete, vuelve a medir en cada fotograma (la lista puede
      // desplazarse con el control con foco dentro). No pide fotogramas: corre
      // cuando los hay.
      if (_ring.value != null) {
        _measureSoon();
      }
    });
  }

  /// Si en [node] se ve el filete: un control de verdad, no un ámbito, ni una
  /// zona que solo recoge el foco, ni un campo de texto.
  static bool _ringable(FocusNode node) {
    if (node is FocusScopeNode || node.skipTraversal || !node.canRequestFocus) {
      return false;
    }
    final context = node.context;
    if (context == null || !context.mounted) {
      return false;
    }
    final widget = context.widget;
    if (widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    // Una pantalla que ya no se ve (otra rama del shell, o tapada por otra
    // ruta) conserva su foco: no se le pinta el filete encima de la actual.
    if (!TickerMode.valuesOf(context).enabled ||
        ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    return true;
  }

  void _measure() {
    Rect? next;
    final node = FocusManager.instance.primaryFocus;
    if (FocusManager.instance.highlightMode == FocusHighlightMode.traditional &&
        node != null &&
        _ringable(node)) {
      final own = context.findRenderObject();
      final object = node.context?.findRenderObject();
      if (own is RenderBox &&
          own.attached &&
          object is RenderBox &&
          object.attached &&
          object.hasSize) {
        final topLeft = own.globalToLocal(object.localToGlobal(Offset.zero));
        next = topLeft & object.size;
      }
    }
    // Otro control con foco y filete ya a la vista: viaja desde donde está.
    final focused = next == null ? null : node;
    if (next != null &&
        focused != _lastNode &&
        _ring.value != null &&
        !RegalosMotion.of(context).reduce) {
      _from = _displayed(_ring.value!);
      _travel.forward(from: 0);
    }
    _lastNode = focused;
    if (next != _ring.value) {
      _ring.value = next;
    }
  }

  /// El rectángulo que se pinta ahora para el objetivo [target]: si el filete
  /// viaja, entre donde salió y [target].
  Rect _displayed(Rect target) {
    final from = _from;
    if (from == null || _travel.isCompleted) {
      return target;
    }
    return Rect.lerp(from, target, Curves.easeOut.transform(_travel.value))!;
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: Listenable.merge([_ring, _travel]),
              builder: (context, _) {
                final target = _ring.value;
                return CustomPaint(
                  painter: FocusRingPainter(
                    target == null ? null : _displayed(target),
                    t.ink,
                    t.bg,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// El filete del foco: dibuja un rectángulo de radio 8 y 2 px alrededor de
/// [rect] (en las coordenadas del [FocusRingOverlay]), si lo hay, a 2 px del
/// control, con ese hueco pintado de [gapColor].
class FocusRingPainter extends CustomPainter {
  /// Crea el pintor.
  const FocusRingPainter(this.rect, this.color, [this.gapColor]);

  /// El control con foco, o `null` si no hay filete.
  final Rect? rect;

  /// El color del filete.
  final Color color;

  /// El color del hueco entre el control y el filete (el del fondo); sin él,
  /// el hueco queda transparente.
  final Color? gapColor;

  /// El grosor del filete.
  static const double width = 2;

  /// Lo que se separa del control: el hueco entre su borde y el filete.
  static const double gap = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = this.rect;
    if (rect == null) {
      return;
    }
    const radius = Radius.circular(RegalosShape.cardRadius);
    // El hueco, por fuera del control, del color del fondo.
    final gapColor = this.gapColor;
    if (gapColor != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(gap / 2), radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = gap
          ..color = gapColor,
      );
    }
    // Y el filete, tras el hueco: su centro queda a gap + width / 2 del borde.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(gap + width / 2), radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(FocusRingPainter old) =>
      old.rect != rect || old.color != color || old.gapColor != gapColor;
}
