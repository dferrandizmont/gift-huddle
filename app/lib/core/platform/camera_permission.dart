import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'camera_permission_gate.dart';

export 'camera_permission_gate.dart'
    show CameraPermissionOutcome, CameraPermissionStatusRequest;

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

/// Como [requestCameraPermission], pero distingue «denegado para siempre» e
/// «interrumpido». Si la app nativa es anterior (sin el método nuevo), cae al
/// sí o no de siempre.
Future<CameraPermissionOutcome> requestCameraPermissionStatus() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return CameraPermissionOutcome.granted;
  }
  try {
    final raw = await _channel.invokeMethod<String>(
      'requestCameraPermissionStatus',
    );
    return parseCameraPermissionOutcome(raw);
  } on MissingPluginException {
    return await requestCameraPermission()
        ? CameraPermissionOutcome.granted
        : CameraPermissionOutcome.denied;
  } on PlatformException {
    return CameraPermissionOutcome.cancelled;
  }
}

/// Lee lo que devuelve el canal nativo (`granted`, `denied`,
/// `permanentlyDenied`, `cancelled`); cualquier otra cosa es `cancelled`.
@visibleForTesting
CameraPermissionOutcome parseCameraPermissionOutcome(String? raw) =>
    switch (raw) {
      'granted' => CameraPermissionOutcome.granted,
      'denied' => CameraPermissionOutcome.denied,
      'permanentlyDenied' => CameraPermissionOutcome.permanentlyDenied,
      _ => CameraPermissionOutcome.cancelled,
    };

/// Abre la página de la app en los ajustes del sistema (para dar el permiso
/// a mano). Devuelve si se pudo abrir.
Future<bool> openCameraSettings() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }
  try {
    return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
  } on Object {
    return false;
  }
}
