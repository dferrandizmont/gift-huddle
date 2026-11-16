import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';

/// El visor del lector de códigos (§3.2 y «momento L» de
/// la guía de movimiento): cuatro «L» de 30 px, trazo de 3 y
/// radio 4, sobre un cuadro de 200 centrado.
///
/// Al leer un código, [ScanViewfinderState.lock] las lleva con `snap` hasta el
/// rectángulo del código (ampliado 5 px) y las pasa de blanco al pastel de la
/// familia, con `mediumImpact`. Si el rectángulo no es de fiar en algún móvil,
/// las esquinas solo se cierran un 8 % hacia el centro. Con «Reducir
/// movimiento» no viajan: solo cambian de color en 150 ms.
class ScanViewfinder extends StatefulWidget {
  /// Crea el visor.
  const ScanViewfinder({super.key, this.autoStart = true});

  /// Si la entrada arranca sola al montarse. El lector real lo pone a `false`
  /// y llama a [ScanViewfinderState.begin] cuando la cámara ya da imagen: las
  /// esquinas no llegan sobre un cuadro negro.
  final bool autoStart;

  /// Lado del cuadro en reposo.
  static const double box = 200;

  /// Largo de cada brazo de una esquina.
  static const double arm = 30;

  /// Grosor del trazo.
  static const double stroke = 3;

  /// Radio de la esquina de cada «L».
  static const double radius = 4;

  /// Cuánto se amplía el rectángulo del código al cerrarse sobre él.
  static const double margin = 5;

  /// Cuánto se cierra hacia el centro si no hay rectángulo de fiar.
  static const double fallbackClose = 0.08;

  /// Cuánto tarda, desde que se lee el código, en subir la hoja de éxito: el
  /// 70 % del muelle de las esquinas (~262 ms) o, con «Reducir movimiento», lo
  /// que dura su fundido. Va por tiempo y no por el reloj de la animación:
  /// una animación parada (la app tapada por el PIN) no debe retener la hoja.
  static Duration followUp({required bool reduce}) =>
      reduce ? RegalosMotion.fade : RegalosSprings.snapDuration * 0.7;

  /// Si [code] (en coordenadas del visor de tamaño [size]) es un rectángulo de
  /// fiar: dentro del visor (con un 10 % de margen), ni diminuto ni más grande
  /// que él.
  static bool plausible(Rect code, Size size) {
    if (code.isEmpty || !code.isFinite) {
      return false;
    }
    final bounds = (Offset.zero & size).inflate(size.shortestSide * 0.1);
    return bounds.contains(code.topLeft) &&
        bounds.contains(code.bottomRight) &&
        code.shortestSide >= 24 &&
        code.longestSide <= size.longestSide;
  }

  /// El rectángulo de un código cuyas esquinas ([corners]) vienen en las
  /// coordenadas de la imagen de la cámara de tamaño [image], pintada con
  /// `BoxFit.cover` en un visor de tamaño [view]; o `null` si no sirve.
  static Rect? codeRect({
    required List<Offset> corners,
    required Size image,
    required Size view,
  }) {
    if (corners.length < 4 || image.isEmpty || view.isEmpty) {
      return null;
    }
    final scale = math.max(
      view.width / image.width,
      view.height / image.height,
    );
    final dx = (view.width - image.width * scale) / 2;
    final dy = (view.height - image.height * scale) / 2;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in corners) {
      final x = p.dx * scale + dx;
      final y = p.dy * scale + dy;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    final rect = Rect.fromLTRB(minX, minY, maxX, maxY);
    return plausible(rect, view) ? rect : null;
  }

  @override
  State<ScanViewfinder> createState() => ScanViewfinderState();
}

/// El estado de [ScanViewfinder]: [lock] y [reset].
class ScanViewfinderState extends State<ScanViewfinder>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: RegalosSprings.snapDuration,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// La entrada: las esquinas llegan un poco más abiertas y se asientan con
  /// `snap`, y una línea de luz recorre el cuadro una vez (también al volver
  /// a empezar tras un fallo). Sin bucles: no hay nada que siga animándose.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: _introDuration,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// El destello pastel dentro del cuadro al cerrarse sobre un código.
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: _flashDuration,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// Las esquinas se asientan con `snap` y, detrás, la línea de luz cruza con
  /// `soft`: la entrada dura lo que los dos muelles, uno tras otro.
  static final Duration _introDuration =
      RegalosSprings.snapDuration + RegalosSprings.softDuration;

  /// El destello pastel se apaga con `soft`.
  static final Duration _flashDuration = RegalosSprings.softDuration;

  /// Hasta dónde llega la entrada de las esquinas (`snap`) y desde dónde
  /// empieza a correr la línea de luz.
  static final double _cornersEnd =
      RegalosSprings.snapDuration.inMicroseconds /
      _introDuration.inMicroseconds;
  static final double _sweepStart = _cornersEnd;

  Size _size = Size.zero;
  bool _locked = false;
  bool _begun = false;

  /// El rectángulo del código sobre el que se cerraron, si el lector lo dio.
  Rect? _code;
  bool _reduce = false;

  /// El cuadro de reposo, centrado en el visor.
  Rect get _rest => Rect.fromCenter(
    center: _size.center(Offset.zero),
    width: math.min(ScanViewfinder.box, _size.shortestSide),
    height: math.min(ScanViewfinder.box, _size.shortestSide),
  );

  /// Adónde van las esquinas al cerrarse: el código ampliado o, sin él, un
  /// 8 % hacia el centro de [rest]. Sale del cuadro de reposo de ahora y no
  /// del que había al leer: si el visor cambia de tamaño con las esquinas
  /// cerradas (la tablet gira), siguen centradas.
  Rect _targetFor(Rect rest) {
    final code = _code;
    return code == null
        ? Rect.lerp(
            rest,
            Rect.fromCenter(center: rest.center, width: 0, height: 0),
            ScanViewfinder.fallbackClose,
          )!
        : code.inflate(ScanViewfinder.margin);
  }

  /// Si las esquinas están cerradas sobre un código.
  bool get locked => _locked;

  /// Cierra las esquinas sobre [code] (el rectángulo del código en las
  /// coordenadas del visor) o, si es `null`, un 8 % hacia el centro. Vibra
  /// medio. Quien llama sigue, tras [ScanViewfinder.followUp], con lo
  /// siguiente (la hoja de éxito).
  void lock(Rect? code) {
    if (!mounted || _size.isEmpty) {
      return;
    }
    if (!_begun) {
      // Las esquinas aún no habían entrado: se ven ya en su sitio.
      _begun = true;
      _intro.value = 1;
    }
    context.haptics.medium();
    _reduce = RegalosMotion.of(context).reduce;
    setState(() {
      _locked = true;
      _code = code;
    });
    unawaited(_controller.forward(from: 0));
    if (!_reduce) {
      unawaited(_flash.forward(from: 0));
    }
  }

  /// Vuelve las esquinas a su sitio y a blanco (la lectura falló).
  void reset() {
    if (!mounted) {
      return;
    }
    _controller
      ..stop()
      ..value = 0;
    _flash
      ..stop()
      ..value = 1;
    setState(() {
      _locked = false;
      _code = null;
    });
    if (!_begun) {
      begin();
      return;
    }
    // Vuelve a buscar: la línea de luz recorre el cuadro otra vez.
    if (!RegalosMotion.of(context).reduce) {
      unawaited(_intro.forward(from: _sweepStart));
    }
  }

  /// Lanza la entrada: las esquinas llegan y la línea de luz cruza el cuadro.
  /// Solo la primera vez; una segunda llamada no hace nada. Con «Reducir
  /// movimiento» las esquinas aparecen ya en su sitio y no hay línea.
  void begin() {
    if (!mounted || _begun) {
      return;
    }
    _begun = true;
    if (RegalosMotion.of(context).reduce) {
      _intro.value = 1;
    } else {
      unawaited(_intro.forward(from: 0));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.autoStart) {
      begin();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _intro.dispose();
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return AnimatedBuilder(
          animation: Listenable.merge([_controller, _intro, _flash]),
          builder: (context, _) {
            final raw = _controller.value;
            // El recorrido sigue `snap`; el color, el mismo avance.
            final travel = _reduce ? 0.0 : RegalosCurves.snap.transform(raw);
            final tint = _reduce ? raw : travel.clamp(0.0, 1.0);
            final rest = _rest;
            final rect = !_locked || _size.isEmpty
                ? rest
                : Rect.lerp(rest, _targetFor(rest), travel)!;
            // La entrada: las esquinas llegan un 10 % más abiertas y fundiendo,
            // y después la línea de luz baja por el cuadro.
            final intro = _intro.value;
            final arrive = RegalosCurves.snap.transform(
              (intro / _cornersEnd).clamp(0.0, 1.0),
            );
            final sweepRaw = ((intro - _sweepStart) / (1 - _sweepStart)).clamp(
              0.0,
              1.0,
            );
            final sweeping = !_locked && sweepRaw > 0 && sweepRaw < 1;
            return CustomPaint(
              size: Size.infinite,
              painter: _CornersPainter(
                rect: rect,
                color: Color.lerp(Colors.white, t.fill, tint)!,
                arrive: arrive,
                sweep: sweeping ? RegalosCurves.soft.transform(sweepRaw) : null,
                flash: _locked && _flash.isAnimating
                    ? 1 - RegalosCurves.soft.transform(_flash.value)
                    : 0,
                flashColor: t.fill,
              ),
            );
          },
        );
      },
    );
  }
}

class _CornersPainter extends CustomPainter {
  const _CornersPainter({
    required this.rect,
    required this.color,
    this.arrive = 1,
    this.sweep,
    this.flash = 0,
    this.flashColor = Colors.white,
  });

  /// El cuadro al que se cierran las esquinas (en reposo, el de 200).
  final Rect rect;
  final Color color;

  /// La entrada de las esquinas, de 0 (abiertas y transparentes) a 1.
  final double arrive;

  /// Por dónde va la línea de luz (0 arriba, 1 abajo), o `null` si no hay.
  final double? sweep;

  /// Cuánto queda del destello al cerrarse sobre un código (1 a 0).
  final double flash;
  final Color flashColor;

  @override
  void paint(Canvas canvas, Size size) {
    const arm = ScanViewfinder.arm;
    const r = ScanViewfinder.radius;
    if (flash > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(r)),
        Paint()..color = flashColor.withValues(alpha: 0.32 * flash),
      );
    }
    final line = sweep;
    if (line != null) {
      // Una línea recta con los extremos que se funden; sube su brillo hacia
      // la mitad del recorrido.
      final y = rect.top + rect.height * line;
      final bell = math.sin(line * math.pi);
      final a = Rect.fromLTRB(rect.left + 8, y - 1, rect.right - 8, y + 1);
      canvas.drawRect(
        a,
        Paint()
          ..shader = LinearGradient(
            colors: [
              const Color(0x00FFFFFF),
              Colors.white.withValues(alpha: 0.75 * bell),
              const Color(0x00FFFFFF),
            ],
          ).createShader(a),
      );
    }
    final scale = 1 + 0.1 * (1 - arrive);
    final shown = scale == 1
        ? rect
        : Rect.fromCenter(
            center: rect.center,
            width: rect.width * scale,
            height: rect.height * scale,
          );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ScanViewfinder.stroke
      ..color = color.withValues(alpha: color.a * arrive.clamp(0.0, 1.0))
      ..strokeJoin = StrokeJoin.round;
    final l = shown.left, tp = shown.top, rt = shown.right, b = shown.bottom;
    final path = Path()
      // Arriba a la izquierda.
      ..moveTo(l, tp + arm)
      ..lineTo(l, tp + r)
      ..arcTo(Rect.fromLTWH(l, tp, 2 * r, 2 * r), math.pi, math.pi / 2, false)
      ..lineTo(l + arm, tp)
      // Arriba a la derecha.
      ..moveTo(rt - arm, tp)
      ..lineTo(rt - r, tp)
      ..arcTo(
        Rect.fromLTWH(rt - 2 * r, tp, 2 * r, 2 * r),
        -math.pi / 2,
        math.pi / 2,
        false,
      )
      ..lineTo(rt, tp + arm)
      // Abajo a la izquierda.
      ..moveTo(l, b - arm)
      ..lineTo(l, b - r)
      ..arcTo(
        Rect.fromLTWH(l, b - 2 * r, 2 * r, 2 * r),
        math.pi,
        -math.pi / 2,
        false,
      )
      ..lineTo(l + arm, b)
      // Abajo a la derecha.
      ..moveTo(rt - arm, b)
      ..lineTo(rt - r, b)
      ..arcTo(
        Rect.fromLTWH(rt - 2 * r, b - 2 * r, 2 * r, 2 * r),
        math.pi / 2,
        -math.pi / 2,
        false,
      )
      ..lineTo(rt, b - arm);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornersPainter old) =>
      old.rect != rect ||
      old.color != color ||
      old.arrive != arrive ||
      old.sweep != sweep ||
      old.flash != flash ||
      old.flashColor != flashColor;
}
