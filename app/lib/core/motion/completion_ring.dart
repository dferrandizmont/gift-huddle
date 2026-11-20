import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/regalos_motion.dart';
import '../theme/regalos_tokens.dart';
import 'success_mark.dart';

/// El camino de un cuadrado de esquinas de radio [r] que arranca a las 12 y
/// va en el sentido de las agujas del reloj.
Path _squarePath(Rect rect, double r) => Path()
  ..moveTo(rect.center.dx, rect.top)
  ..lineTo(rect.right - r, rect.top)
  ..arcToPoint(Offset(rect.right, rect.top + r), radius: Radius.circular(r))
  ..lineTo(rect.right, rect.bottom - r)
  ..arcToPoint(Offset(rect.right - r, rect.bottom), radius: Radius.circular(r))
  ..lineTo(rect.left + r, rect.bottom)
  ..arcToPoint(Offset(rect.left, rect.bottom - r), radius: Radius.circular(r))
  ..lineTo(rect.left, rect.top + r)
  ..arcToPoint(Offset(rect.left + r, rect.top), radius: Radius.circular(r))
  ..close();

/// El avatar de una persona con su anillo de progreso (§2.11 de
/// la guía de movimiento, «Persona completa»).
///
/// El anillo rodea al avatar (un cuadrado de esquinas de 8, como todo en la
/// app): una pista en `track` y un arco en tinta de [fraction], desde las 12
/// y con extremos rectos. Cada cambio de [fraction] mueve el arco con `snap`
/// (con `soft` si [quiet], es decir, si llegó por sincronización).
///
/// Cuando cambia [celebration] (solo lo hace una acción del usuario) el arco
/// se cierra y empieza la celebración, que dura unos 1,3 s y no bloquea
/// nada:
/// - a los 190 ms (la mitad de `snap`), una onda del anillo sale y se apaga
///   (radio de +0 a +15 %, opacidad de 0,55 a 0, trazo de 3 a 0,5, en 900 ms);
/// - a la vez, el avatar late una vez de 1 a 1,08 (la ficha «A + Actual»:
///   190 ms de subida con rebote y 290 de vuelta, [_beat]);
/// - a los 250 ms aparece el sello (un cuadrado de radio 6 con borde y, a los
///   350 ms, su visto dibujándose en 220 ms).
///
/// Si [complete] cambia sin [celebration] (sincronización), el sello aparece
/// con un fundido `soft` y nada más. Al dejar de estar completa, el sello se
/// va en 150 ms con `fold`. Con «Reducir movimiento» el arco cambia con un
/// fundido de 150 ms, el sello aparece y desaparece con un fundido y no hay
/// onda ni rebote; la háptica la pone quien llama.
class CompletionAvatar extends StatefulWidget {
  /// Crea el avatar con anillo.
  const CompletionAvatar({
    super.key,
    required this.child,
    required this.avatarSize,
    required this.fraction,
    required this.complete,
    this.celebration = 0,
    this.quiet = false,
    this.showRing = true,
  });

  /// El avatar.
  final Widget child;

  /// Lado del avatar; el anillo mide 1,25 veces más.
  final double avatarSize;

  /// Lo comprado, de 0 a 1.
  final double fraction;

  /// Si la persona está completa.
  final bool complete;

  /// Cambia cuando hay que celebrar.
  final int celebration;

  /// Si el último cambio llegó por sincronización.
  final bool quiet;

  /// Si se pinta el anillo: sin regalos que contar no hay nada que medir.
  final bool showRing;

  /// El lado del cuadro del anillo para un avatar de [avatarSize].
  static double boxFor(double avatarSize) => avatarSize * 1.25;

  @override
  State<CompletionAvatar> createState() => _CompletionAvatarState();
}

class _CompletionAvatarState extends State<CompletionAvatar>
    with TickerProviderStateMixin {
  static const int _total = 1300;
  static const int _d = 190;

  late final AnimationController _arc = AnimationController.unbounded(
    vsync: this,
    value: widget.fraction,
  );
  late final AnimationController _celebrate = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _total),
    value: widget.complete ? 1 : 0,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final AnimationController _seal = AnimationController(
    vsync: this,
    value: widget.complete ? 1 : 0,
    animationBehavior: AnimationBehavior.preserve,
  );
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = RegalosMotion.of(context).reduce;
  }

  @override
  void didUpdateWidget(CompletionAvatar old) {
    super.didUpdateWidget(old);
    if (widget.fraction != old.fraction) {
      _moveArc(widget.fraction);
    }
    if (widget.celebration != old.celebration && widget.complete) {
      _startCelebration();
    } else if (widget.complete != old.complete) {
      if (widget.complete) {
        _showSealQuietly();
      } else {
        _hideSeal();
      }
    }
  }

  void _moveArc(double to) {
    _arc.stop();
    if (_reduce) {
      _arc.animateTo(to, duration: RegalosMotion.fade, curve: Curves.linear);
      return;
    }
    _arc.animateWith(
      SpringSimulation(
        widget.quiet ? RegalosSprings.soft : RegalosSprings.snap,
        _arc.value,
        to,
        0,
        snapToEnd: true,
      ),
    );
  }

  void _startCelebration() {
    _seal.value = 1;
    if (_reduce) {
      _celebrate.value = 1;
      _seal
        ..value = 0
        ..animateTo(1, duration: RegalosMotion.fade, curve: Curves.linear);
      return;
    }
    _celebrate.forward(from: 0);
  }

  void _showSealQuietly() {
    _celebrate.value = 1;
    _seal
      ..value = 0
      ..animateTo(
        1,
        duration: _reduce ? RegalosMotion.fade : RegalosSprings.softDuration,
        curve: _reduce ? Curves.linear : RegalosCurves.soft,
      );
  }

  void _hideSeal() {
    _celebrate.stop();
    _seal.animateBack(
      0,
      duration: _reduce ? RegalosMotion.fade : RegalosCurves.foldDuration,
      curve: _reduce ? Curves.linear : RegalosCurves.fold,
    );
  }

  @override
  void dispose() {
    _arc.dispose();
    _celebrate.dispose();
    _seal.dispose();
    super.dispose();
  }

  /// Los milisegundos de la celebración, o -1 si no está en marcha.
  double get _ms => _celebrate.isAnimating ? _celebrate.value * _total : -1;

  double _bounce(double from, double startMs) {
    final t = (_ms - startMs) / 1000;
    if (_ms < 0 || t <= 0) {
      return _ms < 0 ? 1 : from;
    }
    return SpringSimulation(RegalosSprings.bounce, from, 1, 0).x(t);
  }

  /// El latido del avatar: sube a 1,08 en 190 ms con la curva de rebote de la
  /// ficha (`cubic-bezier(.3, 1.6, .5, 1)`) y vuelve a 1 en 290 ms.
  double _beat(double startMs) =>
      _ms < 0 ? 1 : CompletionBeat.scaleAt(_ms - startMs);

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final box = CompletionAvatar.boxFor(widget.avatarSize);
    final sealSize = box * 0.26;
    return SizedBox.square(
      dimension: box,
      child: AnimatedBuilder(
        animation: Listenable.merge([_arc, _celebrate, _seal]),
        builder: (context, _) {
          final ms = _ms;
          final celebrating = ms >= 0;
          final ripple = celebrating && !_reduce
              ? Interval(
                  _d / _total,
                  (_d + 900) / _total,
                  curve: const Cubic(0.2, 0.7, 0.2, 1),
                ).transform(_celebrate.value)
              : -1.0;
          final avatarScale = celebrating && !_reduce
              ? _beat(_d.toDouble())
              : 1.0;
          double sealScale = 1;
          double sealOpacity = _seal.value.clamp(0.0, 1.0);
          if (celebrating && !_reduce) {
            sealScale = _bounce(0.6, _d + 60);
            sealOpacity = ((ms - (_d + 60)) / 90).clamp(0.0, 1.0);
          } else if (!celebrating && !_reduce && sealOpacity < 1) {
            sealScale = 0.9 + 0.1 * sealOpacity;
          }
          final checkProgress = celebrating && !_reduce
              ? Curves.easeOut.transform(
                  ((ms - (_d + 160)) / 220).clamp(0.0, 1.0),
                )
              : 1.0;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _RingPainter(
                    track: t.track,
                    ink: t.ink,
                    fraction: _arc.value.clamp(0.0, 1.0),
                    showTrack: widget.showRing,
                    ripple: ripple,
                    avatarSize: widget.avatarSize,
                  ),
                ),
              ),
              Transform.scale(scale: avatarScale, child: widget.child),
              if (sealOpacity > 0)
                Positioned(
                  right: (box - widget.avatarSize) / 2 - sealSize * 0.35,
                  bottom: (box - widget.avatarSize) / 2 - sealSize * 0.35,
                  child: Opacity(
                    key: const ValueKey('completion-seal'),
                    opacity: sealOpacity,
                    child: Transform.scale(
                      scale: sealScale,
                      child: _Seal(
                        size: sealSize,
                        radius: 6 * sealSize / 26,
                        border: 3 * sealSize / 26,
                        checkProgress: checkProgress,
                      ),
                    ),
                  ),
                ),
              if (ripple >= 0 && ripple < 1)
                const SizedBox.shrink(key: ValueKey('completion-ripple')),
            ],
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.track,
    required this.ink,
    required this.fraction,
    required this.showTrack,
    required this.ripple,
    required this.avatarSize,
  });

  final Color track;
  final Color ink;
  final double fraction;
  final bool showTrack;
  final double ripple;
  final double avatarSize;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 100;
    final stroke = 3 * unit;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width - stroke - 6 * unit,
      height: size.height - stroke - 6 * unit,
    );
    final path = _squarePath(rect, 8);
    if (showTrack) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = track
          ..strokeWidth = stroke,
      );
    }
    if (fraction > 0) {
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * fraction),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = ink
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
    }
    if (ripple >= 0 && ripple < 1) {
      // De radio 47 a 62 (sobre 100), opacidad de 0,55 a 0, trazo de 3 a 0,5.
      final grow = 15 * unit * ripple;
      canvas.drawPath(
        _squarePath(rect.inflate(grow), 8),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = ink.withValues(alpha: 0.55 * (1 - ripple))
          ..strokeWidth = (3 - 2.5 * ripple) * unit,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.showTrack != showTrack ||
      old.ripple != ripple ||
      old.track != track ||
      old.ink != ink;
}

/// El sello de «persona completa»: un cuadrado en tinta con borde y un visto.
class _Seal extends StatelessWidget {
  const _Seal({
    required this.size,
    required this.radius,
    required this.border,
    required this.checkProgress,
  });

  final double size;
  final double radius;
  final double border;
  final double checkProgress;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.ink,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: t.bg, width: border),
      ),
      child: DrawnCheck(
        color: t.bg,
        size: size * 0.62,
        strokeWidth: 2.8,
        progress: AlwaysStoppedAnimation<double>(checkProgress),
      ),
    );
  }
}

/// El sello pequeño de la fila de Personas (16, radio 4), que aparece con un
/// fundido `soft` cuando la persona está completa y se va en 150 ms.
class MiniSeal extends StatelessWidget {
  /// Crea el sello.
  const MiniSeal({super.key, required this.visible, this.size = 16});

  /// Si la persona está completa.
  final bool visible;

  /// Lado del sello.
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: motion.reduce
          ? RegalosMotion.fade
          : (visible
                ? RegalosSprings.softDuration
                : RegalosCurves.foldDuration),
      curve: motion.reduce
          ? Curves.linear
          : (visible ? RegalosCurves.soft : RegalosCurves.fold),
      child: Container(
        key: const ValueKey('mini-seal'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.ink,
          borderRadius: BorderRadius.circular(size * 0.25),
          border: Border.all(color: t.bg, width: 1.5),
        ),
        child: DrawnCheck(
          color: t.bg,
          size: size * 0.62,
          strokeWidth: 3,
          progress: const AlwaysStoppedAnimation<double>(1),
        ),
      ),
    );
  }
}

/// El aviso para [LightWave]: las filas (por id y en orden) por las que pasa
/// la ola de luz. [seq] distingue dos celebraciones seguidas.
@immutable
class LightWaveCue {
  /// Crea el aviso.
  const LightWaveCue(this.ids, this.seq);

  /// Las filas, de arriba abajo.
  final List<String> ids;

  /// Número de orden del aviso.
  final int seq;

  @override
  bool operator ==(Object other) =>
      other is LightWaveCue && other.seq == seq && listEquals(other.ids, ids);

  @override
  int get hashCode => Object.hash(seq, Object.hashAll(ids));
}

/// El canal por el que la cabecera avisa a las filas de la ola de luz.
class LightWaveSignal extends ValueNotifier<LightWaveCue?> {
  /// Crea el canal vacío.
  LightWaveSignal() : super(null);

  int _seq = 0;

  /// Lanza la ola por las filas [ids].
  void wave(List<String> ids) => value = LightWaveCue(ids, ++_seq);
}

/// Una fila por la que pasa la ola de luz de «persona completa»: el fondo
/// va al pastel claro [color] y vuelve, con el pico al 25 % de 1000 ms
/// (`easeOut`), empezando a los 140 ms de la onda (D + 140, con D = 190 ms) y
/// con 60 ms de desfase entre filas. Con «Reducir movimiento» no hay ola.
class LightWave extends StatefulWidget {
  /// Crea la fila.
  const LightWave({
    super.key,
    required this.id,
    required this.signal,
    required this.color,
    required this.child,
  });

  /// El id de la fila.
  final String id;

  /// Por dónde llega el aviso.
  final LightWaveSignal signal;

  /// El pastel claro de la persona.
  final Color color;

  /// La fila.
  final Widget child;

  @override
  State<LightWave> createState() => _LightWaveState();
}

class _LightWaveState extends State<LightWave>
    with SingleTickerProviderStateMixin {
  static const int _start = 190 + 140;
  static const int _length = 1000;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );
  int _delay = 0;

  @override
  void initState() {
    super.initState();
    widget.signal.addListener(_onCue);
  }

  @override
  void didUpdateWidget(LightWave old) {
    super.didUpdateWidget(old);
    if (old.signal != widget.signal) {
      old.signal.removeListener(_onCue);
      widget.signal.addListener(_onCue);
    }
  }

  @override
  void dispose() {
    widget.signal.removeListener(_onCue);
    _controller.dispose();
    super.dispose();
  }

  void _onCue() {
    final ids = widget.signal.value?.ids;
    final index = ids?.indexOf(widget.id) ?? -1;
    if (index < 0 || RegalosMotion.of(context).reduce) {
      return;
    }
    _delay = _start + 60 * index;
    _controller
      ..duration = Duration(milliseconds: _delay + _length)
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      var strength = 0.0;
      if (_controller.isAnimating) {
        final ms = _controller.value * (_delay + _length) - _delay;
        if (ms > 0) {
          final p = ms / _length;
          // Sube hasta el 25 % y baja con `easeOut`.
          strength = p < 0.25
              ? Curves.easeOut.transform(p / 0.25)
              : 1 - Curves.easeOut.transform((p - 0.25) / 0.75);
        }
      }
      return ColoredBox(
        color: widget.color.withValues(
          alpha: widget.color.a * strength.clamp(0.0, 1.0),
        ),
        child: child,
      );
    },
  );
}

/// El latido de «Persona completa» en la fila de Personas (la ficha): cuando
/// [complete] pasa a `true` con la fila ya en pantalla, el cuadrado de la
/// inicial late una vez de 1 a 1,08 (190 ms de subida con rebote y 290 de
/// vuelta) mientras aparece el sello. Al montarse ya completa no late. Con
/// «Reducir movimiento», nada se escala.
class CompletionBeat extends StatefulWidget {
  /// Crea el latido.
  const CompletionBeat({
    super.key,
    required this.complete,
    required this.child,
  });

  /// Si la persona está completa.
  final bool complete;

  /// El cuadrado de la inicial.
  final Widget child;

  /// Lo que dura el latido.
  static const Duration duration = Duration(milliseconds: 480);

  /// La escala a los [ms] milisegundos del latido.
  static double scaleAt(double ms) {
    if (ms <= 0 || ms >= 480) return 1;
    if (ms < 190) return 1 + 0.08 * _up.transform(ms / 190);
    return 1 + 0.08 * (1 - Curves.easeInOut.transform((ms - 190) / 290));
  }

  static const Cubic _up = Cubic(0.3, 1.6, 0.5, 1);

  @override
  State<CompletionBeat> createState() => _CompletionBeatState();
}

class _CompletionBeatState extends State<CompletionBeat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CompletionBeat.duration,
  );

  @override
  void didUpdateWidget(CompletionBeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.complete &&
        !oldWidget.complete &&
        !RegalosMotion.of(context).reduce) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // «Reducir movimiento» activado a mitad del latido: se para ahí mismo y la
    // escala vuelve a 1.
    if (RegalosMotion.of(context).reduce && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = RegalosMotion.of(context).reduce;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => Transform.scale(
        scale: !reduce && _controller.isAnimating
            ? CompletionBeat.scaleAt(_controller.value * 480)
            : 1,
        child: child,
      ),
    );
  }
}
