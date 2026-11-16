import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secure_wipe_stub.dart'
    if (dart.library.io) 'secure_wipe_native.dart'
    as platform;

/// Vacía entero el almacén seguro de la app (Keychain en iOS, el almacén
/// cifrado con el Keystore en Android): todas sus claves, también las que
/// esta versión no conozca.
///
/// Lo usan el primer arranque tras instalar en iPhone (el llavero sobrevive
/// a desinstalar la app) y «Borrar todo» de Ajustes. En la web no hay nada
/// que vaciar: el almacén es de memoria.
typedef SecureStorageWipe = Future<void> Function();

/// El vaciado del almacén seguro. Las pruebas lo sustituyen.
final secureStorageWipeProvider = Provider<SecureStorageWipe>(
  (ref) => platform.wipeSecureStorage,
);
