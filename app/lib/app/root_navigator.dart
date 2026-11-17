import 'package:flutter/widgets.dart';

/// Navegador raíz: lo que se abre por encima de la barra inferior (primer
/// uso, unirse con QR) y los avisos de los envíos que llegan de fuera.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// Señala el montaje del navegador (primera ruta) y los cambios de su pila.
/// Los receptores externos reintentan tras ese fotograma, sin sondear ni
/// mantener fotogramas en marcha mientras el navegador no está montado.
final rootNavigatorObserver = RootNavigatorObserver();

class RootNavigatorObserver extends NavigatorObserver with ChangeNotifier {
  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    notifyListeners();
  }
}
