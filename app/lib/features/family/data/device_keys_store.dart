import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/access_policy.dart';
import '../../../core/sync/device_keys.dart';
import 'generation_storage.dart';
import 'storage.dart';
import 'storage_providers.dart';

/// Claves propias del móvil (ADR 0004).
const kDeviceKeysSecret = 'device.keys';

/// Llavero de sorpresas del móvil, con el `listId` de su familia (ADR 0004).
const kSurpriseKeysSecret = 'device.surpriseKeys';

/// Lo guardado de las claves del móvil no se puede leer o usar.
class DeviceKeysStoreException implements Exception {
  /// Crea el error.
  const DeviceKeysStoreException(this.message);

  /// Qué pasó (sin claves).
  final String message;

  @override
  String toString() => 'DeviceKeysStoreException: $message';
}

/// Guarda en el almacén seguro del sistema las claves propias de este móvil
/// y su llavero de sorpresas (ADR 0004).
///
/// En la web no guarda nada: allí el almacén es de memoria y la web no
/// recibe ni claves de móvil ni `surpriseKey` (revisión de seguridad, B4).
///
/// Nada de la app lo usa todavía: lo conectan el transporte y la interfaz
/// de la fase 2b. Tiene que haber una sola instancia por almacén (N5).
class DeviceKeysStore {
  /// Crea el guardado sobre [secrets]. [enabled] es false en la web.
  DeviceKeysStore(SecretStore secrets, {bool? enabled})
    : _secrets = GenerationSecretStore.active(secrets),
      _enabled = enabled ?? !kIsWeb,
      _queue = GenerationStorageQueue.on(secrets, 'deviceKeys');

  final SecretStore _secrets;
  final bool _enabled;
  final GenerationStorageQueue _queue;

  /// Ejecuta [task] después de lo anterior de este guardado, para que dos
  /// llamadas a la vez no se pisen.
  Future<T> _inGeneration<T>(Future<T> Function() task) =>
      (_secrets as GenerationSecretStore).inGeneration(task);

  Future<T> _serial<T>(Future<T> Function() task) => _queue.run(
    () => _inGeneration(() async {
      if (await _secrets.read('family.transferred') == 'true') {
        throw StateError('transferred');
      }
      return task();
    }),
  );

  void _guard() {
    if (!_enabled) {
      throw const DeviceKeysStoreException(
        'las claves del móvil no se guardan en la web',
      );
    }
  }

  /// Las claves guardadas, o null si este móvil aún no las tiene. Lanza
  /// [DeviceKeysStoreException] si están dañadas.
  Future<DeviceKeys?> read() => _inGeneration(() async {
    _guard();
    final raw = await _secrets.read(kDeviceKeysSecret);
    if (raw == null) return null;
    try {
      return await DeviceKeys.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      throw const DeviceKeysStoreException('claves del móvil dañadas');
    }
  });

  /// Crea y guarda las claves de este móvil. Nunca las regenera en
  /// silencio: si ya hay unas, lanza [DeviceKeysStoreException] (perderlas
  /// es un caso que decide la fase 2, no algo que se tape).
  Future<DeviceKeys> create() => _serial(() async {
    _guard();
    if (await (_secrets as GenerationSecretStore).managed) {
      throw const DeviceKeysStoreException(
        'usa la preparación durable de generación',
      );
    }
    if (await _secrets.read(kDeviceKeysSecret) != null) {
      throw const DeviceKeysStoreException('este móvil ya tiene claves');
    }
    final fresh = await DeviceKeys.generate();
    await _secrets.write(kDeviceKeysSecret, jsonEncode(fresh.toJson()));
    return fresh;
  });

  /// Guarda [keys] en lugar de las que hubiera (al restaurar una copia de
  /// recuperación).
  Future<void> restore(DeviceKeys keys) => _serial(() async {
    _guard();
    final stored = await _secrets.read(kDeviceKeysSecret);
    if (stored != null &&
        await (_secrets as GenerationSecretStore).managed &&
        jsonEncode((await read())!.toJson()) != jsonEncode(keys.toJson())) {
      throw const DeviceKeysStoreException(
        'claves referenciadas por una generación',
      );
    }
    await _secrets.write(kDeviceKeysSecret, jsonEncode(keys.toJson()));
  });

  /// The read-only recovery workspace is never registered/activated. Its
  /// credential changes after claim, while installed generation keys stay fixed.
  Future<void> restoreReadWorkspace(DeviceKeys keys) => _serial(() async {
    _guard();
    final scoped = _secrets as GenerationSecretStore;
    if (!scoped.recoveryStaging ||
        !(await scoped.prefix()).startsWith('recovery.read.')) {
      throw StateError('not a recovery read workspace');
    }
    await _secrets.write(kDeviceKeysSecret, jsonEncode(keys.toJson()));
  });

  /// El llavero de sorpresas de la lista [listId] (vacío si no hay, o si lo
  /// guardado es de otra lista). Lanza [DeviceKeysStoreException] si está
  /// dañado.
  Future<SurpriseKeyring> readKeyring(String listId) => _inGeneration(() async {
    _guard();
    final stored = await _readStoredKeyring();
    if (stored == null || stored.listId != listId) {
      return SurpriseKeyring.empty;
    }
    return stored.keyring;
  });

  /// Cambia el llavero de la lista [listId] dentro de la cola: [update]
  /// recibe el que hay guardado en ese momento (vacío si es de otra lista) y
  /// devuelve el nuevo, que se guarda y se devuelve. Es la forma de añadir o
  /// quitar claves: dos cambios a la vez no se pisan, y nunca vuelven las
  /// claves de la persona de «Yo» ([purgePerson]), aunque [update] las traiga
  /// de un llavero leído antes (hallazgo 11).
  Future<SurpriseKeyring> updateKeyring(
    String listId,
    SurpriseKeyring Function(SurpriseKeyring current) update,
  ) => _serial(() async {
    _guard();
    final stored = await _readStoredKeyring();
    final current = stored == null || stored.listId != listId
        ? SurpriseKeyring.empty
        : stored.keyring;
    final excluded = stored?.excluded;
    var next = update(current);
    if (excluded != null) next = next.without(excluded);
    await _writeKeyring(listId, next, excluded);
    return next;
  });

  /// Guarda [keyring] entero como el llavero de la lista [listId]. Sirve para
  /// restaurar; para añadir o quitar claves, [updateKeyring], que no pierde
  /// lo que llegue a la vez. Tampoco aquí vuelven las claves de la persona de
  /// «Yo».
  Future<void> saveKeyring(String listId, SurpriseKeyring keyring) =>
      updateKeyring(listId, (_) => keyring);

  /// Este móvil es de [personId] («Yo»), o de nadie con null: quita del
  /// llavero sus claves y, desde ahora, no deja guardar ninguna suya (M7 y
  /// hallazgo 11). Con otra persona o con null, la anterior vuelve a poder
  /// tener claves (las que le den, de la época que toque).
  Future<void> purgePerson(String? personId) => _serial(() async {
    if (!_enabled) return;
    final stored = await _readStoredKeyring();
    final keyring = stored?.keyring ?? SurpriseKeyring.empty;
    await _writeKeyring(
      stored?.listId,
      personId == null ? keyring : keyring.without(personId),
      personId,
    );
  });

  /// Borra las claves del móvil y el llavero (en la misma cola que las
  /// demás escrituras).
  Future<void> clear() => _serial(() async {
    if (await (_secrets as GenerationSecretStore).managed) {
      throw const DeviceKeysStoreException(
        'generación conservada para recuperación',
      );
    }
    await _secrets.delete(kSurpriseKeysSecret);
    await _secrets.delete(kDeviceKeysSecret);
  });

  Future<({String? listId, SurpriseKeyring keyring, String? excluded})?>
  _readStoredKeyring() async {
    final raw = await _secrets.read(kSurpriseKeysSecret);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map;
      return (
        listId: json['l'] as String?,
        keyring: SurpriseKeyring.fromJson(json['k']),
        excluded: json['x'] as String?,
      );
    } catch (_) {
      throw const DeviceKeysStoreException('llavero de sorpresas dañado');
    }
  }

  Future<void> _writeKeyring(
    String? listId,
    SurpriseKeyring keyring,
    String? excluded,
  ) => _secrets.write(
    kSurpriseKeysSecret,
    jsonEncode(<String, Object?>{
      'l': listId,
      'k': keyring.toJson(),
      'x': ?excluded,
    }),
  );
}

/// El guardado de las claves del móvil.
final deviceKeysStoreProvider = Provider<DeviceKeysStore>(
  (ref) => DeviceKeysStore(ref.watch(secretStoreProvider)),
);
