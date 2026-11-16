import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../sync/exchange_file_names.dart';
import 'document_exchange.dart';

const kIncomingChannel = MethodChannel('com.dferrandizmont.regalos/incoming');

final tempDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => getTemporaryDirectory,
);

class NativeDocumentExchange implements DocumentExchange {
  NativeDocumentExchange(this.directory);
  final Future<Directory> Function() directory;
  @override
  Future<XFile> exportBytes(Uint8List bytes, String name) async {
    final dir = await directory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return XFile(file.path, mimeType: kExchangeMimeType);
  }

  @override
  Future<ShareResult> shareBytes(
    Uint8List bytes,
    String name, {
    required String text,
    Rect? origin,
  }) async {
    final file = await exportBytes(bytes, name);
    return SharePlus.instance.share(
      ShareParams(text: text, files: [file], sharePositionOrigin: origin),
    );
  }

  @override
  Future<void> startReceiving(Future<void> Function(Uint8List) receive) async {
    kIncomingChannel.setMethodCallHandler((call) async {
      if (call.method == 'onFile' && call.arguments is Uint8List) {
        await receive(call.arguments as Uint8List);
      }
      return null;
    });
    try {
      final initial = await kIncomingChannel.invokeMethod<Uint8List>(
        'takeInitialFile',
      );
      if (initial != null) await receive(initial);
    } on MissingPluginException {
      // No native channel in VM tests or on desktop.
    } on PlatformException {
      // The native side could not read the file.
    }
  }

  @override
  Future<void> clearExports() async {
    try {
      final dir = await directory();
      // La carpeta temporal y, dentro, la copia que `share_plus` deja al
      // compartir. Sin recorrer más: la carpeta es del sistema.
      final folders = [
        dir,
        Directory('${dir.path}${Platform.pathSeparator}share_plus'),
      ];
      for (final folder in folders) {
        if (!await folder.exists()) {
          continue;
        }
        final entries = folder.list(followLinks: false);
        await for (final entry in entries.handleError((Object _) {})) {
          if (entry is File &&
              kExchangeFileExtensions.any(entry.path.toLowerCase().endsWith)) {
            try {
              await entry.delete();
            } on FileSystemException {
              // Se queda: va cifrado y el sistema limpia esta carpeta.
            }
          }
        }
      }
    } on Object {
      // Sin carpeta temporal (pruebas, escritorio) no hay nada que borrar.
    }
    await _clearInbox();
  }

  /// iPhone: borra las copias que iOS deja en `Documents/Inbox` (o en
  /// `tmp/<bundle>-Inbox`) de cada `.gifthuddle` o `.regalos` abierto. El
  /// código nativo ya borra cada una al leerla; esto barre las que quedaran
  /// (de versiones anteriores, o si la lectura falló). En Android no hay
  /// copia: el fichero se lee de donde está.
  Future<void> _clearInbox() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      await kIncomingChannel.invokeMethod<void>('clearInbox');
    } on MissingPluginException {
      // Sin código nativo (pruebas, escritorio).
    } on PlatformException {
      // Lo que no se pueda borrar se queda: va cifrado.
    }
  }

  @override
  void stopReceiving() => kIncomingChannel.setMethodCallHandler(null);
  @override
  Future<Uint8List?> pickBytes() => Future.error(
    UnsupportedError('Native files arrive through the incoming channel'),
  );
}

DocumentExchange createDocumentExchange(Ref ref) =>
    NativeDocumentExchange(ref.watch(tempDirectoryProvider));
