import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Las medidas del tablero de la web de escritorio, todas en puntos lógicos
/// (ya sin la escala de interfaz) y a partir del ancho de la ventana W
/// (la guía de diseño de escritorio, «Reglas»).
///
/// Puro Dart: se prueba sin montar nada.
abstract final class BoardMetrics {
  /// La barra lateral desplegada, desde [wideFrom].
  static const double sidebarWide = 264;

  /// La barra lateral desplegada en una ventana de menos de [wideFrom].
  static const double sidebarNarrow = 232;

  /// La barra lateral plegada: un raíl de iconos y avatares.
  static const double sidebarRail = 64;

  /// Desde este ancho el margen y la barra son los grandes.
  static const double wideFrom = 1600;

  /// Hasta este ancho el margen es de [marginMid].
  static const double midUntil = 2400;

  /// Margen de los lados por debajo de [wideFrom].
  static const double marginNarrow = 24;

  /// Margen de los lados hasta [midUntil].
  static const double marginMid = 32;

  /// Margen de los lados por encima.
  static const double marginWide = 40;

  /// El editor no baja de esto…
  static const double editorMin = 400;

  /// …ni pasa de esto.
  static const double editorMax = 480;

  /// El editor empuja el contenido solo si quedan unos 1100 para los
  /// carriles (4·248 más los huecos y «Listo» plegado); si no, se superpone.
  static const double lanesRoom = 1100;

  /// Por encima de este ancho lógico la composición se centra y lo que sobra
  /// queda en el color de fondo. No se llega con una pantalla de 34″.
  static const double maxComposition = 3840;

  /// El ancho de la barra desplegada para una ventana de [window].
  static double sidebarFor(double window) =>
      window < wideFrom ? sidebarNarrow : sidebarWide;

  /// El margen de los lados para una ventana de [window].
  static double marginFor(double window) => window < wideFrom
      ? marginNarrow
      : (window <= midUntil ? marginMid : marginWide);

  /// El ancho del editor abierto: `clamp(0,17·W, 400, 480)`.
  static double editorWidthFor(double window) =>
      math.min(editorMax, math.max(editorMin, 0.17 * window));

  /// Si el editor abierto empuja el contenido (hay sitio para los carriles) o
  /// se superpone con sombra.
  static bool editorPushes(double window, {required double sidebar}) {
    final room =
        window - sidebar - editorWidthFor(window) - 2 * marginFor(window);
    return room >= lanesRoom;
  }
}

/// Si la barra lateral está plegada a un raíl de [BoardMetrics.sidebarRail].
/// Se recuerda mientras dura la sesión.
class BoardSidebarCollapsed extends Notifier<bool> {
  @override
  bool build() => false;

  /// Pliega o despliega la barra.
  void toggle() => state = !state;
}

/// Si la barra lateral está plegada.
final boardSidebarCollapsedProvider =
    NotifierProvider<BoardSidebarCollapsed, bool>(BoardSidebarCollapsed.new);

/// El regalo marcado con el teclado (↑ y ↓ recorren los regalos de la
/// pantalla). Cada pantalla le cuenta en qué orden salen sus regalos; solo
/// notifica cuando cambia la marca, no al contar el orden.
class BoardGiftCursor extends ChangeNotifier {
  List<String> _order = const <String>[];
  String? _current;

  /// El regalo marcado, o `null`.
  String? get current => _current;

  /// Anota los regalos que se ven, por orden. Se llama al construir: no
  /// notifica. Si el marcado ya no está, la marca se quita.
  void register(List<String> ids) {
    _order = ids;
    if (_current != null && !ids.contains(_current)) {
      _current = null;
    }
  }

  /// Quita la marca.
  void clear() {
    if (_current == null) {
      return;
    }
    _current = null;
    notifyListeners();
  }

  /// Marca [id] (un clic o la apertura del editor).
  void set(String? id) {
    if (_current == id) {
      return;
    }
    _current = id;
    notifyListeners();
  }

  /// Mueve la marca [delta] regalos (con la primera vez en el primero o el
  /// último) y devuelve el nuevo, o `null` si no hay regalos.
  String? step(int delta) {
    if (_order.isEmpty) {
      return null;
    }
    final at = _current == null ? -1 : _order.indexOf(_current!);
    final int next;
    if (at < 0) {
      next = delta > 0 ? 0 : _order.length - 1;
    } else {
      next = (at + delta).clamp(0, _order.length - 1);
    }
    _current = _order[next];
    notifyListeners();
    return _current;
  }
}

/// La marca del teclado de la sesión.
final boardGiftCursorProvider = Provider<BoardGiftCursor>((ref) {
  final cursor = BoardGiftCursor();
  ref.onDispose(cursor.dispose);
  return cursor;
});
