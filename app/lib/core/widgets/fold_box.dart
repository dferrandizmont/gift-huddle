import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// Un trozo de pantalla que se pliega hasta desaparecer (la tarjeta de
/// presupuesto y los filtros de la página de una persona al bajar) y vuelve
/// al subir.
///
/// [folded] va de 0 (a la vista) a 1 (plegado). Con él, el hijo se funde y la
/// caja pierde alto. Con «Reducir movimiento» no se desliza nada: el hijo se
/// funde en su sitio y el alto cambia de golpe cuando ya no se ve (al
/// plegarse) o antes de que empiece a verse (al volver).
///
/// Plegado del todo, el hijo no recibe toques, foco ni lector de pantalla.
class FoldBox extends StatelessWidget {
  /// Crea la caja.
  const FoldBox({super.key, required this.folded, required this.child});

  /// Cuánto está plegado: 0 a la vista, 1 plegado.
  final Animation<double> folded;

  /// Lo que se pliega.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = RegalosMotion.of(context).reduce;
    return AnimatedBuilder(
      animation: folded,
      child: child,
      builder: (context, child) {
        final v = folded.value.clamp(0.0, 1.0);
        if (v == 0) {
          return child!;
        }
        final gone = v >= 1;
        final factor = reduce ? (gone ? 0.0 : 1.0) : 1 - v;
        // El contenido se apaga antes de que la caja termine de cerrarse.
        final opacity = reduce ? 1 - v : (1 - v * 1.6).clamp(0.0, 1.0);
        return ExcludeFocus(
          excluding: gone,
          child: ExcludeSemantics(
            excluding: gone,
            child: IgnorePointer(
              ignoring: gone,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: factor,
                  child: Opacity(opacity: opacity, child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
