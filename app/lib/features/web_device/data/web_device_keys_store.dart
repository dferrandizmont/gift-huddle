import '../../../core/sync/device_keys.dart';
import '../../family/data/device_keys_store.dart';
import '../../family/data/storage.dart';
import '../application/vault_service.dart';

/// Override deviceKeysStoreProvider in the web session's ProviderContainer.
/// Seeds are read only from the opened vault; no surprise operation is allowed.
class WebDeviceKeysStore extends DeviceKeysStore {
  WebDeviceKeysStore(this.vault) : super(_NoSecrets(), enabled: false);
  final VaultService vault;
  @override
  Future<DeviceKeys?> read() async => DeviceKeys.fromJson(
    Map<String, Object?>.from(vault.opened.data['deviceKeys'] as Map),
  );
  @override
  Future<void> purgePerson(String? personId) async =>
      throw const DeviceKeysStoreException(
        'Surprise keys are unavailable on web',
      );
}

class _NoSecrets implements SecretStore {
  Never _deny() =>
      throw const DeviceKeysStoreException('Use the vault service on web');
  @override
  Future<String?> read(String key) async => _deny();
  @override
  Future<void> write(String key, String value) async => _deny();
  @override
  Future<void> delete(String key) async => _deny();
}
