import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// Un bloque de un formulario o de una hoja que se despliega al aparecer y se
/// pliega al irse, en vez de saltar (por ejemplo, los campos que salen al
/// activar «Me lo pidió alguien», o el color y el icono de una ocasión
/// «Otra»).
///
/// - Al aparecer: la altura crece con el muelle `snap`, el contenido se funde
///   y baja 6 px hasta su sitio.
/// - Al irse: se pliega en 180 ms con `fold`, sin rebote, y deja de existir
///   (sus campos ya no reciben foco ni lectores de pantalla).
/// - Si se invierte a medias, parte de lo que se ve y conserva la velocidad:
///   no hay saltos.
/// - La primera vez se pinta ya en su estado, sin animar.
/// - Con «Reducir movimiento» no cambia de altura: aparece y desaparece con un
///   fundido de 150 ms.
class UnfoldSection extends StatefulWidget {
  /// Crea el bloque.
  const UnfoldSection({super.key, required this.show, required this.child});

  /// Si el contenido está a la vista.
  final bool show;

  /// El contenido.
  final Widget child;

  @override
  State<UnfoldSection> createState() => _UnfoldSectionState();
}

class _UnfoldSectionState extends State<UnfoldSection>
    with SingleTickerProviderStateMixin {
  // Lo que se ve del bloque: 1 es entero y 0 está plegado. Es la altura
  // misma, así que invertir a medias parte de aquí.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.show ? 1 : 0,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didUpdateWidget(UnfoldSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show == oldWidget.show) {
      return;
    }
    final reduce = RegalosMotion.of(context).reduce;
    final velocity = _controller.isAnimating ? _controller.velocity : 0.0;
    if (reduce) {
      final fade = widget.show
          ? _controller.animateTo
          : _controller.animateBack;
      fade(
        widget.show ? 1 : 0,
        duration: RegalosMotion.fade,
        curve: Curves.linear,
      );
    } else if (widget.show) {
      _controller.animateWith(
        SpringSimulation(
          RegalosSprings.snap,
          _controller.value,
          1,
          velocity,
          snapToEnd: true,
        ),
      );
    } else {
      _controller.animateBack(
        0,
        duration: RegalosCurves.foldDuration,
        curve: RegalosCurves.fold,
      );
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
      builder: (context, child) {
        if (_controller.isDismissed) {
          return const SizedBox(width: double.infinity);
        }
        final v = _controller.value.clamp(0.0, 1.0);
        final complete = v >= 1;
        // Con «Reducir movimiento» la altura salta; solo el fundido anima.
        return ClipRect(
          clipBehavior: complete || reduce ? Clip.none : Clip.hardEdge,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: reduce || complete ? null : v,
            child: Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(0, reduce ? 0 : -6 * (1 - v)),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
