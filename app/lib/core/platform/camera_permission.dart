import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('com.dferrandizmont.regalos/incoming');

/// Pide el permiso de cámara (una sola vez) y dice si se tiene.
///
/// En Android lo pide la propia app, antes de crear el lector de QR: el lector
/// lo volvía a pedir al volver del diálogo y, si se denegaba, salía dos veces.
/// En el resto (iPhone, pruebas) devuelve `true` y lo gestiona el lector.
typedef CameraPermissionRequest = Future<bool> Function();

/// Si el permiso ya está concedido, sin preguntar nada.
Future<bool> hasCameraPermission() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return true;
  }
  try {
    return await _channel.invokeMethod<bool>('cameraPermission') ?? false;
  } on Object {
    return true;
  }
}

/// Muestra el diálogo del sistema si hace falta y devuelve el resultado.
Future<bool> requestCameraPermission() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return true;
  }
  try {
    return await _channel.invokeMethod<bool>('requestCameraPermission') ??
        false;
  } on Object {
    // Sin canal (pruebas): que decida el lector.
    return true;
  }
}
