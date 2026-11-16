import 'package:flutter/widgets.dart';

/// Navegador raíz: lo que se abre por encima de la barra inferior (primer
/// uso, unirse con QR) y los avisos de los envíos que llegan de fuera.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);
