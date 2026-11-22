import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Versión de tienda: se compila con `--dart-define=STORE_BUILD=true`. Las
/// prereleases dejan hacer capturas para probar y opinar.
const bool kStoreBuild = bool.fromEnvironment('STORE_BUILD');

const _channel = MethodChannel('com.dferrandizmont.regalos/incoming');

/// Cuántas pantallas sensibles hay a la vista ahora mismo (se pueden solapar:
/// las palabras y, encima, un diálogo; o la lista de regalos de un panel y, en
/// el otro, el editor).
int _sensitiveDepth = 0;

/// Empieza a bloquear capturas y grabaciones de pantalla mientras se ve algo
/// muy sensible: las 24 palabras, el QR o lo que se escribe al recuperar
/// (también en las prereleases) y, solo en la versión de tienda, las pantallas
/// que enseñan regalos (`GiftsSecureScope`). Android pone `FLAG_SECURE`; en iOS no se puede
/// bloquear: allí solo queda tapar lo sensible al perder el primer plano y el
/// aviso. Se espera a que el canal conteste: llámala antes de enseñar nada,
/// para que el primer fotograma ya vaya protegido. Cada llamada se empareja con
/// una a [disableSecureScreen]. No falla nunca.
Future<void> enableSecureScreen() async {
  _sensitiveDepth++;
  await _setSecure(true);
}

/// Deja de bloquear lo que pidió [enableSecureScreen]; el flag se quita
/// cuando ya no queda ninguna pantalla sensible a la vista.
Future<void> disableSecureScreen() async {
  if (_sensitiveDepth > 0) {
    _sensitiveDepth--;
  }
  if (_sensitiveDepth == 0) {
    await _setSecure(false);
  }
}

Future<void> _setSecure(bool on) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  try {
    await _channel.invokeMethod<void>('setSecure', on);
  } on Object {
    // Sin canal (pruebas) o actividad sin ventana: nada que hacer.
  }
}
