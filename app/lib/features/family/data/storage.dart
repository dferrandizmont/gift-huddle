import 'dart:typed_data';

/// Almacenamiento seguro de claves y textos pequeños (Keystore en Android,
/// Keychain en iOS). Se abstrae para poder probar sin plugins.
abstract interface class SecretStore {
  /// Lee un valor, o `null` si no existe.
  Future<String?> read(String key);

  /// Guarda un valor.
  Future<void> write(String key, String value);

  /// Borra un valor (no falla si no existe).
  Future<void> delete(String key);
}

/// Ficheros privados de la app, por nombre.
abstract interface class FileStore {
  /// Lee un fichero, o `null` si no existe.
  Future<Uint8List?> read(String name);

  /// Escribe un fichero de forma atómica: nunca queda a medias.
  Future<void> writeAtomic(String name, Uint8List bytes);

  /// Borra un fichero (no falla si no existe).
  Future<void> delete(String name);
}

/// Confirmed cryptographic erasure, including secrets unknown to this version.
abstract interface class ErasableSecretStore implements SecretStore {
  Future<void> eraseAllSecrets();
}

/// Flat directory inventory independent of encrypted indexes.
abstract interface class ListableFileStore implements FileStore {
  Future<List<String>> listNames();
}
