import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'secure_screen.dart';

/// Si las pantallas que enseñan regalos bloquean capturas y grabaciones: solo
/// en la versión de tienda ([kStoreBuild]) y solo en Android (`FLAG_SECURE`).
/// Las prereleases dejan hacer capturas para probar y opinar; iOS no permite
/// bloquearlas.
bool get giftScreensSecure =>
    (debugGiftScreensSecure ?? kStoreBuild) &&
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android;

/// Las pruebas fuerzan la versión de tienda (`kStoreBuild` es una constante de
/// compilación). `null` usa el valor real.
@visibleForTesting
bool? debugGiftScreensSecure;

/// Bloquea capturas y grabaciones mientras [child], una pantalla que enseña
/// regalos, está a la vista: pide [enableSecureScreen] al aparecer y
/// [disableSecureScreen] al irse, siempre emparejados (el contador de
/// `secure_screen.dart` deja el flag puesto mientras quede alguna pantalla
/// sensible, también las palabras de recuperación).
///
/// «A la vista» no es solo «montada»: una pantalla tapada por otra de página
/// completa, o la de una rama inactiva de la barra de navegación, sigue
/// montada pero sus animaciones están apagadas (`TickerMode`); entonces suelta
/// el bloqueo, para que Ajustes o Ocasiones se puedan capturar. Una hoja o un
/// diálogo encima no la tapan. En tablet, con dos paneles, cada pantalla de
/// regalos de cada panel pide el suyo.
///
/// Con [enabled] en `false` (por ejemplo, una persona cuyos regalos este móvil
/// no enseña) no pide nada. Fuera de la versión de tienda en Android no hace
/// nada.
class GiftsSecureScope extends StatefulWidget {
  /// Crea el bloqueo alrededor de [child].
  const GiftsSecureScope({super.key, this.enabled = true, required this.child});

  /// Si la pantalla enseña regalos ahora.
  final bool enabled;

  /// La pantalla.
  final Widget child;

  @override
  State<GiftsSecureScope> createState() => _GiftsSecureScopeState();
}

class _GiftsSecureScopeState extends State<GiftsSecureScope> {
  // Si esta pantalla tiene puesta ahora su petición de bloqueo.
  bool _held = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(GiftsSecureScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final want = widget.enabled && giftScreensSecure && TickerMode.valuesOf(context).enabled;
    if (want == _held) return;
    _held = want;
    unawaited(want ? enableSecureScreen() : disableSecureScreen());
  }

  @override
  void dispose() {
    if (_held) {
      _held = false;
      unawaited(disableSecureScreen());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
