import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// El contenedor de las pestañas (§2.7 de la guía de movimiento):
/// como el `indexedStack` de go_router (todas las ramas montadas, solo la
/// activa a la vista y con animaciones), pero el contenido que llega se
/// funde en [duration] (100 ms) para que no parpadee. Nada se mueve: iOS tampoco
/// anima el cambio de pestaña, y en escritorio cambiar de pestaña tiene que
/// notarse inmediato.
///
/// Lo que ya estaba montado no repite su entrada (su `StaggerScope` o la
/// entrada de sus paneles ya acabaron): solo se funde la pestaña entera. La
/// primera pestaña aparece sin nada. Con «Reducir movimiento» el fundido es de
/// 150 ms. Cambiar el tamaño de la ventana no lo dispara.
class FadingBranchContainer extends StatefulWidget {
  /// Crea el contenedor.
  const FadingBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  /// La rama activa.
  final int currentIndex;

  /// Las ramas, en orden.
  final List<Widget> children;

  /// Lo que dura el fundido de la pestaña que llega.
  static const Duration duration = Duration(milliseconds: 100);

  @override
  State<FadingBranchContainer> createState() => _FadingBranchContainerState();
}

class _FadingBranchContainerState extends State<FadingBranchContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: FadingBranchContainer.duration,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didUpdateWidget(FadingBranchContainer old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _fade
        ..duration = RegalosMotion.of(context).reduce
            ? RegalosMotion.fade
            : FadingBranchContainer.duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != widget.currentIndex,
            child: TickerMode(
              enabled: i == widget.currentIndex,
              // Todas llevan el mismo envoltorio, para no perder su estado.
              child: _BranchEntrance(
                animation: i == widget.currentIndex
                    ? _fade
                    : kAlwaysCompleteAnimation,
                child: widget.children[i],
              ),
            ),
          ),
      ],
    );
  }
}

/// El fundido de una pestaña que llega.
class _BranchEntrance extends StatelessWidget {
  const _BranchEntrance({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: animation, child: child);
}
