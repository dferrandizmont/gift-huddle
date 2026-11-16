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
}

final documentExchangeProvider = Provider<DocumentExchange>(
  platform.createDocumentExchange,
);
