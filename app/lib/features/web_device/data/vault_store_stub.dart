import 'vault_store.dart';

Future<VaultStore> openVaultStore(String name) async =>
    throw UnsupportedError('IndexedDB requires a browser');
Future<bool> requestVaultPersistence() async => false;
