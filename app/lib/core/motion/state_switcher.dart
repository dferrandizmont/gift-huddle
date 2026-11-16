import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// Cambia el contenido de un hueco (lista, estado vacío, «sin resultados»)
/// con un fundido de 200 ms y la curva `fold`, sin movimiento (§1.6 de
/// la guía de movimiento).
///
/// [stateKey] identifica cada contenido: solo cuando cambia hay transición.
/// Con «Reducir movimiento» el fundido dura 150 ms lineales. El primer
/// contenido aparece sin animar. Rellena todo el hueco.
class StateSwitcher extends StatelessWidget {
  /// Crea el cambiador.
  const StateSwitcher({super.key, required this.stateKey, required this.child});

  /// Qué contenido es.
  final Object stateKey;

  /// El contenido.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = RegalosMotion.of(context);
    return AnimatedSwitcher(
      duration: motion.duration(const Duration(milliseconds: 200)),
      switchInCurve: motion.curve(RegalosCurves.fold),
      switchOutCurve: motion.curve(RegalosCurves.fold),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}
