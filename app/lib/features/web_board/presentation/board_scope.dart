import 'package:flutter/widgets.dart';

import '../application/board_metrics.dart';

/// Lo que el marco del tablero cuenta a las pantallas de dentro: el margen de
/// los lados y, con el editor superpuesto, cuánto tapa del lado derecho.
///
/// Es un valor animado: con el editor abriéndose o cerrándose, [overlayInset]
/// crece o baja con él.
class BoardScope extends InheritedWidget {
  /// Crea el ámbito.
  const BoardScope({
    super.key,
    required this.margin,
    required this.overlayInset,
    required super.child,
  });

  /// El margen de los lados (24, 32 o 40 según el ancho de la ventana).
  final double margin;

  /// Lo que tapa el editor cuando se superpone (0 si empuja o está cerrado).
  /// Las pantallas que no pueden quedar debajo (la tabla de Persona) lo
  /// reservan como margen derecho; los carriles se desplazan por debajo.
  final double overlayInset;

  /// El ámbito más cercano, o `null` fuera del tablero.
  static BoardScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BoardScope>();

  /// El margen de los lados de [context].
  static double marginOf(BuildContext context) =>
      maybeOf(context)?.margin ??
      BoardMetrics.marginFor(MediaQuery.sizeOf(context).width);

  /// Lo que tapa el editor superpuesto en [context].
  static double overlayInsetOf(BuildContext context) =>
      maybeOf(context)?.overlayInset ?? 0;

  @override
  bool updateShouldNotify(BoardScope old) =>
      margin != old.margin || overlayInset != old.overlayInset;
}
