import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../sync/exchange_file_names.dart';
import '../sync/recovery_file.dart' show isRecoveryFile, kRecoveryFileMaxBytes;
import 'document_exchange.dart';

const kIncomingChannel = MethodChannel('com.dferrandizmont.regalos/incoming');

final tempDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => getTemporaryDirectory,
);

class NativeDocumentExchange implements DocumentExchange {
  NativeDocumentExchange(
    this.directory, {
    this.recoveryShareRetention = const Duration(minutes: 5),
  });
  final Future<Directory> Function() directory;

  /// Margen tras volver de la hoja de compartir antes de borrar el fichero de
  /// recuperación temporal (la otra app puede seguir leyéndolo un momento).
  final Duration recoveryShareRetention;
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
    // En iPhone, `clearInbox` vacía también `tmp/recovery-export`.
    await _clearRecoveryFiles();
    await _clearInbox();
  }

  /// Carpeta propia de los ficheros de recuperación temporales (compartir y,
  /// en iPhone, la copia que el selector exporta), dentro de la temporal.
  static const recoveryFolder = 'recovery';

  @override
  Future<Uint8List?> saveWithPicker(
    Uint8List bytes,
    String name, {
    required int maxReadBytes,
  }) => _picker<Uint8List>('saveDocument', {
    'bytes': bytes,
    'name': _checkName(name),
    'mime': kExchangeMimeType,
    'maxReadBytes': maxReadBytes,
  });

  @override
  Future<Uint8List?> openWithPicker({required int maxBytes}) =>
      _picker<Uint8List>('openDocument', {'maxBytes': maxBytes});

  @override
  Future<String> normalizeNfc(String text) async {
    final normalized = await _picker<String>('normalizeNfc', text);
    if (normalized == null) {
      throw const DocumentPickerException(DocumentPickerFailure.unavailable);
    }
    return normalized;
  }

  Future<T?> _picker<T>(String method, Object arguments) async {
    try {
      return await kIncomingChannel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const DocumentPickerException(DocumentPickerFailure.unavailable);
    } on PlatformException catch (e) {
      throw DocumentPickerException(switch (e.code) {
        'too_large' => DocumentPickerFailure.tooLarge,
        'busy' => DocumentPickerFailure.busy,
        'unavailable' => DocumentPickerFailure.unavailable,
        _ => DocumentPickerFailure.unreadable,
      });
    }
  }

  static String _checkName(String name) {
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.startsWith('.')) {
      throw ArgumentError.value(name, 'name', 'nombre de fichero no válido');
    }
    return name;
  }

  @override
  Future<ShareResult> shareRecoveryFile(
    Uint8List bytes,
    String name, {
    required String text,
    Rect? origin,
  }) async {
    final checked = _checkName(name);
    final dir = await directory();
    final root = Directory(
      '${dir.path}${Platform.pathSeparator}$recoveryFolder',
    );
    if (!await root.exists()) await root.create(recursive: true);
    // Una carpeta propia por operación: dos envíos con el mismo nombre (la
    // hora va en minutos) nunca comparten fichero ni limpieza.
    final folder = await root.createTemp('share-');
    final file = File('${folder.path}${Platform.pathSeparator}$checked');
    _activeShares[checked] = (_activeShares[checked] ?? 0) + 1;
    try {
      await file.writeAsBytes(bytes, flush: true);
      return await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: [XFile(file.path, mimeType: kExchangeMimeType)],
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      Timer(
        recoveryShareRetention,
        () => unawaited(_deleteShared(folder, checked)),
      );
    }
  }

  /// Envíos de recuperación aún dentro de su margen, por nombre: la copia que
  /// `share_plus` deja con ese nombre solo se borra cuando acaba el último.
  final _activeShares = <String, int>{};

  /// Borra la carpeta de un envío y, si ya no queda otro con su nombre, la
  /// copia que `share_plus` dejara. No falla.
  Future<void> _deleteShared(Directory folder, String name) async {
    final left = (_activeShares[name] ?? 1) - 1;
    if (left <= 0) {
      _activeShares.remove(name);
    } else {
      _activeShares[name] = left;
    }
    try {
      if (await folder.exists()) await folder.delete(recursive: true);
      if (left > 0) return;
      final dir = await directory();
      final copy = File(
        '${dir.path}${Platform.pathSeparator}share_plus'
        '${Platform.pathSeparator}$name',
      );
      if (await copy.exists() && await _isRecoveryCopy(copy)) {
        await copy.delete();
      }
    } on Object {
      // Se queda hasta el próximo arranque o «Borrar todo».
    }
  }

  @override
  Future<void> clearRecoveryShares() async {
    await _clearRecoveryFiles();
    // iPhone: la copia que exporta el selector al guardar vive en
    // `tmp/recovery-export`, fuera de la carpeta temporal de Dart
    // (`Library/Caches`): la borra el código nativo (también al arrancar).
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await kIncomingChannel.invokeMethod<void>('clearRecoveryExport');
    } on MissingPluginException {
      // Sin código nativo (pruebas, escritorio).
    } on PlatformException {
      // Se queda hasta el próximo arranque.
    }
  }

  Future<void> _clearRecoveryFiles() async {
    try {
      final dir = await directory();
      // La carpeta de compartir, por si un cierre abrupto la dejó con E.
      final own = Directory(
        '${dir.path}${Platform.pathSeparator}$recoveryFolder',
      );
      if (await own.exists()) {
        try {
          await own.delete(recursive: true);
        } on FileSystemException {
          // Lo que no se pueda borrar se queda hasta la próxima vez.
        }
      }
      // La copia que `share_plus` deja al compartir: solo las que son
      // ficheros de recuperación (por su magia), no los sobres.
      final shared = Directory(
        '${dir.path}${Platform.pathSeparator}share_plus',
      );
      if (!await shared.exists()) return;
      final entries = shared.list(followLinks: false);
      await for (final entry in entries.handleError((Object _) {})) {
        if (entry is File && await _isRecoveryCopy(entry)) {
          try {
            await entry.delete();
          } on FileSystemException {
            // Se queda hasta la próxima vez.
          }
        }
      }
    } on Object {
      // Sin carpeta temporal (pruebas, escritorio) no hay nada que borrar.
    }
  }

  static Future<bool> _isRecoveryCopy(File file) async {
    try {
      if (await file.length() > kRecoveryFileMaxBytes) return false;
      final head = await file
          .openRead(0, 3)
          .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      return isRecoveryFile(head);
    } on FileSystemException {
      return false;
    }
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
