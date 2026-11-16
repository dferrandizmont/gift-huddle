import 'dart:typed_data';

import 'storage.dart';

/// Ephemeral secrets, scoped to the owning provider container.
class MemorySecretStore implements ErasableSecretStore {
  final _values = <String, String>{};
  @override
  Future<void> eraseAllSecrets() async => _values.clear();
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// Copies on both sides prevent callers from mutating stored bytes.
class MemoryFileStore implements ListableFileStore {
  final _values = <String, Uint8List>{};
  @override
  Future<List<String>> listNames() async => _values.keys.toList();
  @override
  Future<Uint8List?> read(String name) async {
    final bytes = _values[name];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    _values[name] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String name) async {
    _values.remove(name);
  }
}

SecretStore createSecretStore() => MemorySecretStore();
FileStore createFileStore() => MemoryFileStore();
