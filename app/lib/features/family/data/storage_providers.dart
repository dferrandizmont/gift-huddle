import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'storage.dart';
import 'storage_memory.dart'
    if (dart.library.io) 'storage_native.dart'
    if (dart.library.js_interop) 'storage_memory.dart'
    as platform;

final secretStoreProvider = Provider<SecretStore>(
  (ref) => platform.createSecretStore(),
);
final fileStoreProvider = Provider<FileStore>(
  (ref) => platform.createFileStore(),
);
