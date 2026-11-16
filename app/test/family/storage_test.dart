import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/data/storage_native.dart';

void main() {
  test('dos escritores, una lectura y un borrado del mismo fichero '
      'conservan el orden y no comparten el temporal', () async {
    final dir = await Directory.systemTemp.createTemp('regalos_storage_race');
    addTearDown(() => dir.delete(recursive: true));
    final entered = Completer<void>();
    final resume = Completer<void>();
    var writes = 0;
    final store = DirectoryFileStore(
      () async => dir,
      excludeFromBackupHook: (path) async {
        if (path.endsWith('.tmp') && ++writes == 1) {
          entered.complete();
          await resume.future;
        }
      },
    );
    final first = store.writeAtomic('family.registry', Uint8List.fromList([1]));
    await entered.future;
    final second = store.writeAtomic(
      'family.registry',
      Uint8List.fromList([2]),
    );
    final reading = store.read('family.registry');
    final deleting = store.delete('family.registry');
    resume.complete();
    await Future.wait([first, second, deleting]);
    expect(await reading, [2]);
    expect(await store.read('family.registry'), isNull);
    expect(await dir.list().toList(), isEmpty);
  });

  test('un fallo al escribir no bloquea la siguiente escritura', () async {
    final dir = await Directory.systemTemp.createTemp('regalos_storage_retry');
    addTearDown(() => dir.delete(recursive: true));
    var fail = true;
    final store = DirectoryFileStore(
      () async => dir,
      excludeFromBackupHook: (path) async {
        if (path.endsWith('.tmp') && fail) {
          fail = false;
          throw const FileSystemException('interrumpido');
        }
      },
    );
    await expectLater(
      store.writeAtomic('family.registry', Uint8List.fromList([1])),
      throwsA(isA<FileSystemException>()),
    );
    await store.writeAtomic('family.registry', Uint8List.fromList([2]));
    expect(await store.read('family.registry'), [2]);
  });

  test('cada escritura marca el temporal y el fichero final', () async {
    final dir = await Directory.systemTemp.createTemp('regalos_storage');
    addTearDown(() => dir.delete(recursive: true));
    final marked = <String>[];
    final store = DirectoryFileStore(
      () async => dir,
      excludeFromBackupHook: (path) async =>
          marked.add(path.split(Platform.pathSeparator).last),
    );
    await store.writeAtomic('family.doc', Uint8List.fromList([1, 2, 3]));
    expect(marked, ['family.doc.tmp', 'family.doc']);
    expect(await store.read('family.doc'), [1, 2, 3]);
    expect(
      File('${dir.path}${Platform.pathSeparator}family.doc.tmp').existsSync(),
      isFalse,
    );

    await store.writeAtomic('family.doc', Uint8List.fromList([4]));
    expect(marked, hasLength(4));
  });

  test('fuera de iOS excluir de la copia no hace nada ni falla', () async {
    if (Platform.isIOS) {
      return;
    }
    await excludeFromBackup('no-importa');
  });

  test('el almacén seguro usa Keychain solo de este móvil', () {
    expect(
      kSecureStorage.iOptions.toMap()['accessibility'],
      'first_unlock_this_device',
    );
  });
}
