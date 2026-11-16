import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'document_exchange_native.dart'
    if (dart.library.js_interop) 'document_exchange_web.dart'
    as platform;
export 'document_exchange_native.dart'
    if (dart.library.js_interop) 'document_exchange_web.dart'
    show tempDirectoryProvider, kIncomingChannel;

abstract interface class DocumentExchange {
  Future<XFile> exportBytes(Uint8List bytes, String name);
  Future<ShareResult> shareBytes(
    Uint8List bytes,
    String name, {
    required String text,
    Rect? origin,
  });
  Future<Uint8List?> pickBytes();
  Future<void> startReceiving(Future<void> Function(Uint8List) receive);
  void stopReceiving();

  /// Borra los ficheros `.gifthuddle` que la app dejó en su carpeta temporal al
  /// exportar o compartir («Borrar todo») y, en iPhone, las copias que iOS
  /// guarda de los que se abrieron con la app (`Documents/Inbox`). Van
  /// cifrados, pero son datos de este móvil. No falla: lo que no se pueda
  /// borrar se queda.
  Future<void> clearExports();

  /// Guarda [bytes] con el selector de ficheros del sistema (Android
  /// `ACTION_CREATE_DOCUMENT`, iOS `UIDocumentPickerViewController
  /// (forExporting:)`), relee **el documento de destino** con lectura acotada
  /// a [maxReadBytes] y devuelve lo leído para comprobarlo. Null si la persona
  /// cancela. Lanza [DocumentPickerException].
  Future<Uint8List?> saveWithPicker(
    Uint8List bytes,
    String name, {
    required int maxReadBytes,
  });

  /// Elige un fichero con el selector del sistema (Android
  /// `ACTION_OPEN_DOCUMENT`, iOS document picker) y lo lee entero solo si
  /// mide como mucho [maxBytes]; uno mayor se rechaza sin leerlo
  /// ([DocumentPickerFailure.tooLarge]). Null si la persona cancela.
  Future<Uint8List?> openWithPicker({required int maxBytes});

  /// [text] en NFC, normalizado por la plataforma (Android
  /// `java.text.Normalizer`, iOS `precomposedStringWithCanonicalMapping`).
  /// Lanza [DocumentPickerException] con
  /// [DocumentPickerFailure.unavailable] si no hay canal nativo.
  Future<String> normalizeNfc(String text);

  /// Comparte un fichero de recuperación con la hoja de compartir desde su
  /// propia carpeta temporal, que borra [clearRecoveryShares].
  Future<ShareResult> shareRecoveryFile(
    Uint8List bytes,
    String name, {
    required String text,
    Rect? origin,
  });

  /// Borra los ficheros de recuperación temporales que dejó compartir (al
  /// volver tras un margen, al arrancar y en «Borrar todo»). No falla.
  Future<void> clearRecoveryShares();
}

/// Por qué falló el selector de ficheros del sistema.
enum DocumentPickerFailure {
  /// El fichero pasa del tope: no se leyó.
  tooLarge,

  /// No se pudo escribir o leer el documento.
  unreadable,

  /// Ya hay un selector abierto.
  busy,

  /// Sin selector en esta plataforma (web, pruebas, escritorio).
  unavailable,
}

/// Fallo del selector de ficheros. Cancelar no es un fallo: da null.
class DocumentPickerException implements Exception {
  /// Crea el error.
  const DocumentPickerException(this.failure);

  /// El motivo.
  final DocumentPickerFailure failure;

  @override
  String toString() => 'DocumentPickerException(${failure.name})';
}

final documentExchangeProvider = Provider<DocumentExchange>(
  platform.createDocumentExchange,
);
