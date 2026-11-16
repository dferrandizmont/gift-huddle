import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// Desplaza a su hijo en horizontal con el muelle del temblor
/// ([RegalosShake]): el «no» del PIN erróneo.
///
/// Se dispara con `GlobalKey<ShakeXState>().currentState.shake()`. Con
/// «Reducir movimiento» no tiembla (el que llama tiñe algo en su lugar).
class ShakeX extends StatefulWidget {
  /// Crea el temblor.
  const ShakeX({super.key, required this.child});

  /// Lo que tiembla.
  final Widget child;

  @override
  State<ShakeX> createState() => ShakeXState();
}

/// El estado de [ShakeX]: `shake()` y `cancel()`.
class ShakeXState extends State<ShakeX> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
  );

  /// Lanza el temblor. Si ya había uno, lo reinicia.
  void shake() {
    if (!mounted || RegalosMotion.of(context).reduce) {
      return;
    }
    _controller
      ..stop()
      ..value = 0;
    _controller.animateWith(RegalosShake.simulation());
  }

  /// Corta el temblor y deja el hijo en su sitio.
  void cancel() {
    _controller
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final dx = _controller.value;
      return dx == 0
          ? child!
          : Transform.translate(offset: Offset(dx, 0), child: child);
    },
  );
}
