import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'storage.dart';

/// Opciones del almacén seguro.
///
/// - iOS: el Keychain solo se abre tras el primer desbloqueo y **no sale del
///   móvil** (`first_unlock_this_device`): ni copias de seguridad ni
///   migración a otro iPhone, así que la clave no viaja con ellas.
/// - Android: `resetOnError: false`. Con `true` (el valor por defecto) un
///   fallo pasajero del Keystore borraba en silencio la clave de la familia;
///   así el error sale y se puede reintentar.
const FlutterSecureStorage kSecureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  aOptions: AndroidOptions(resetOnError: false),
);

/// [SecretStore] sobre `flutter_secure_storage`.
class FlutterSecretStore implements ErasableSecretStore {
  /// Crea el almacén con [storage] (por defecto, [kSecureStorage]).
  FlutterSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? kSecureStorage;

  final FlutterSecureStorage _storage;
  @override
  Future<void> eraseAllSecrets() => _storage.deleteAll();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Canal nativo (el mismo que recibe los ficheros `.regalos`). En iOS tiene
/// `excludeFromBackup`; en Android no hace falta (`allowBackup=false`).
const MethodChannel _nativeChannel = MethodChannel(
  'com.dferrandizmont.regalos/incoming',
);

/// Marca un fichero como excluido de las copias de seguridad de iOS
/// (`NSURLIsExcludedFromBackupKey`). En otras plataformas no hace nada.
Future<void> excludeFromBackup(String path) async {
  if (!Platform.isIOS) {
    return;
  }
  await _nativeChannel.invokeMethod<void>('excludeFromBackup', path);
}

/// [FileStore] en un directorio: escribe en un temporal y después renombra.
///
/// En iOS excluye de las copias de seguridad tanto el temporal como el
/// fichero final, tras cada escritura.
class DirectoryFileStore implements ListableFileStore {
  /// Crea el almacén en el directorio que devuelva [directory].
  ///
  /// [excludeFromBackupHook] sustituye al aviso nativo (para pruebas).
  DirectoryFileStore(
    this.directory, {
    Future<void> Function(String path) excludeFromBackupHook =
        excludeFromBackup,
  }) : _exclude = excludeFromBackupHook;

  /// Directorio de soporte de la app.
  factory DirectoryFileStore.appSupport() =>
      DirectoryFileStore(getApplicationSupportDirectory);

  /// Quién da el directorio.
  final Future<Directory> Function() directory;

  final Future<void> Function(String path) _exclude;
  @override
  Future<List<String>> listNames() async {
    final dir = await directory();
    if (!await dir.exists()) return [];
    return [
      await for (final entry in dir.list(followLinks: false))
        if (entry is File) entry.uri.pathSegments.last,
    ];
  }

  // El anfitrión y la sincronización de fondo comparten este almacén. Dos
  // escrituras del mismo nombre no pueden compartir el temporal: una puede
  // renombrarlo mientras la otra aún lo escribe. También las lecturas y los
  // borrados esperan, para no abrir/borrar el destino durante el rename.
  final Map<String, Future<void>> _pending = {};

  Future<T> _serial<T>(String name, Future<T> Function() task) {
    final result = (_pending[name] ?? Future<void>.value()).then((_) => task());
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _pending[name] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_pending[name], tail)) _pending.remove(name);
      }),
    );
    return result;
  }

  Future<File> _file(String name, {bool temp = false}) async {
    final dir = await directory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(
      '${dir.path}${Platform.pathSeparator}$name${temp ? '.tmp' : ''}',
    );
  }

  @override
  Future<Uint8List?> read(String name) => _serial(name, () async {
    final file = await _file(name);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  });

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) =>
      _serial(name, () async {
        final temp = await _file(name, temp: true);
        await temp.writeAsBytes(bytes, flush: true);
        await _exclude(temp.path);
        final target = await temp.rename((await _file(name)).path);
        await _exclude(target.path);
      });

  @override
  Future<void> delete(String name) => _serial(name, () async {
    for (final file in [await _file(name), await _file(name, temp: true)]) {
      if (await file.exists()) {
        await file.delete();
      }
    }
  });
}

SecretStore createSecretStore() => FlutterSecretStore();
FileStore createFileStore() => DirectoryFileStore.appSupport();
