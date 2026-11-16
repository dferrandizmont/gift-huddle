import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Si la app corre como versión web (el navegador de un ordenador). Las
/// pantallas comunes lo miran para ocultar lo que la web no hace (ADR 0003,
/// §8) y enseñar lo suyo. Las pruebas lo sustituyen.
final webAppProvider = Provider<bool>((ref) => kIsWeb);
