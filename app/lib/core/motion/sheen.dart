import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// Una banda de luz blanca (80 %, inclinada 10°) que cruza una vez la
/// superficie del hijo (la guía de movimiento, «Brillo»):
/// 800 ms con `Cubic(0.3, 0, 0.2, 1)`.
///
/// Se lanza a mano con `GlobalKey<SheenState>().currentState!.play()`. Con
/// «Reducir movimiento» no hace nada: ahí solo queda el destello de color.
class Sheen extends StatefulWidget {
  /// Crea la superficie con brillo.
  const Sheen({super.key, required this.child, this.borderRadius});

  /// La superficie.
  final Widget child;

  /// Esquinas del recorte, si la superficie las tiene.
  final BorderRadius? borderRadius;

  /// Lo que dura la banda cruzando.
  static const Duration duration = Duration(milliseconds: 800);

  /// La curva de la banda.
  static const Cubic curve = Cubic(0.3, 0, 0.2, 1);

  @override
  State<Sheen> createState() => SheenState();
}

/// El estado de [Sheen]: [play] lanza el brillo.
class SheenState extends State<Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );
  Duration _delay = Duration.zero;

  /// Si la banda está cruzando ahora mismo (para las pruebas).
  bool get playing => _controller.isAnimating;

  /// Lanza el brillo tras [delay]. No hace nada con «Reducir movimiento».
  void play({Duration delay = Duration.zero}) {
    if (!mounted || RegalosMotion.of(context).reduce) {
      return;
    }
    _delay = delay;
    _controller
      ..duration = delay + Sheen.duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final band = Positioned.fill(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (!_controller.isAnimating) {
            return const SizedBox.shrink();
          }
          final total = _controller.duration!.inMicroseconds;
          final raw =
              ((_controller.value * total - _delay.inMicroseconds) /
                      Sheen.duration.inMicroseconds)
                  .clamp(0.0, 1.0);
          if (raw <= 0) {
            return const SizedBox.shrink();
          }
          return IgnorePointer(
            child: CustomPaint(
              key: const ValueKey('sheen-band'),
              painter: _SheenPainter(Sheen.curve.transform(raw)),
            ),
          );
        },
      ),
    );
    final stack = Stack(
      fit: StackFit.passthrough,
      children: [widget.child, band],
    );
    return widget.borderRadius == null
        ? ClipRect(child: stack)
        : ClipRRect(borderRadius: widget.borderRadius!, child: stack);
  }
}

class _SheenPainter extends CustomPainter {
  const _SheenPainter(this.t);

  /// 0 es la banda fuera por la izquierda y 1 fuera por la derecha.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final band = math.max(64.0, size.width * 0.34);
    final lean = math.tan(10 * math.pi / 180) * size.height;
    final x = -band - lean + t * (size.width + 2 * (band + lean));
    final path = Path()
      ..moveTo(x + lean, 0)
      ..lineTo(x + lean + band, 0)
      ..lineTo(x + band, size.height)
      ..lineTo(x, size.height)
      ..close();
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x00FFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
      ).createShader(Rect.fromLTWH(x, 0, band + lean, size.height));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SheenPainter old) => old.t != t;
}
