import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/fresh_install.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/secure_wipe.dart';
import 'package:regalos/features/family/data/storage.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';

import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';

/// Ficheros que fallan al leer.
class _BrokenFiles implements FileStore {
  final List<String> written = [];

  @override
  Future<Uint8List?> read(String name) async => throw StateError('disco roto');

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async =>
      written.add(name);

  @override
  Future<void> delete(String name) async {}
}

/// Ficheros que se leen pero no se pueden escribir (disco lleno).
class _ReadOnlyFiles extends MemoryFileStore {
  bool readOnly = true;

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    if (readOnly) {
      throw StateError('disco lleno');
    }
    await super.writeAtomic(name, bytes);
  }
}

/// En iPhone el llavero sobrevive a desinstalar la app: en el primer arranque
/// tras instalar se vacía, antes de leer ninguna clave. La marca de «ya ha
/// arrancado» es un fichero que no entra en las copias de seguridad.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryFileStore files;
  late int wipes;
  Future<void> wipe() async => wipes++;

  bool marked(MemoryFileStore store) =>
      store.files.containsKey(kInstallMarkerFileName);

  setUp(() {
    files = MemoryFileStore();
    wipes = 0;
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('iPhone sin marca y sin documento: vacía el llavero y pone la marca, '
      'que es un fichero vacío y no una preferencia', () async {
    final prefs = await mockPrefs();
    final wiped = await clearKeychainOnFreshInstall(
      prefs: prefs,
      files: files,
      wipeSecureStorage: wipe,
      isIOS: true,
    );
    expect(wiped, isTrue);
    expect(wipes, 1);
    expect(files.files.keys, [kInstallMarkerFileName]);
    expect(files.files[kInstallMarkerFileName], isEmpty);
    expect(prefs.getKeys(), isEmpty, reason: 'nada que viaje en las copias');
  });

  test('iPhone con la marca: no toca nada, ni en este arranque ni en los '
      'siguientes', () async {
    final prefs = await mockPrefs();
    for (var i = 0; i < 3; i++) {
      await clearKeychainOnFreshInstall(
        prefs: prefs,
        files: files,
        wipeSecureStorage: wipe,
        isIOS: true,
      );
    }
    expect(wipes, 1, reason: 'solo el primer arranque');

    final already = MemoryFileStore();
    await already.writeAtomic(kInstallMarkerFileName, Uint8List(0));
    wipes = 0;
    final wiped = await clearKeychainOnFreshInstall(
      prefs: await mockPrefs(),
      files: already,
      wipeSecureStorage: wipe,
      isIOS: true,
    );
    expect(wiped, isFalse);
    expect(wipes, 0);
  });

  test('iPhone sin marca pero con documento guardado es una actualización: '
      'no borra las claves y pone la marca', () async {
    await files.writeAtomic(kFamilyDocFileName, Uint8List.fromList([1, 2, 3]));
    final prefs = await mockPrefs();
    final wiped = await clearKeychainOnFreshInstall(
      prefs: prefs,
      files: files,
      wipeSecureStorage: wipe,
      isIOS: true,
    );
    expect(wiped, isFalse);
    expect(wipes, 0);
    expect(marked(files), isTrue);
    expect(files.files[kFamilyDocFileName], [1, 2, 3]);
  });

  group('la marca antigua, en las preferencias', () {
    test('se migra al fichero sin borrar nada, y la preferencia se quita '
        'para que no viaje en las copias', () async {
      final prefs = await mockPrefs({kLegacyInstallMarkerKey: true});
      final wiped = await clearKeychainOnFreshInstall(
        prefs: prefs,
        files: files,
        wipeSecureStorage: wipe,
        isIOS: true,
      );
      expect(wiped, isFalse);
      expect(wipes, 0, reason: 'es una actualización, aunque no haya lista');
      expect(marked(files), isTrue);
      expect(prefs.containsKey(kLegacyInstallMarkerKey), isFalse);

      // Los siguientes arranques ya solo miran el fichero.
      expect(
        await clearKeychainOnFreshInstall(
          prefs: prefs,
          files: files,
          wipeSecureStorage: wipe,
          isIOS: true,
        ),
        isFalse,
      );
      expect(wipes, 0);
    });

    test('también con la lista ya creada, que no se toca', () async {
      await files.writeAtomic(kFamilyDocFileName, Uint8List.fromList([7]));
      final prefs = await mockPrefs({kLegacyInstallMarkerKey: true});
      await clearKeychainOnFreshInstall(
        prefs: prefs,
        files: files,
        wipeSecureStorage: wipe,
        isIOS: true,
      );
      expect(wipes, 0);
      expect(marked(files), isTrue);
      expect(files.files[kFamilyDocFileName], [7]);
      expect(prefs.containsKey(kLegacyInstallMarkerKey), isFalse);
    });

    test('si el fichero no se puede crear, la preferencia sigue y se '
        'reintenta en el siguiente arranque', () async {
      final stuck = _ReadOnlyFiles();
      final prefs = await mockPrefs({kLegacyInstallMarkerKey: true});
      expect(
        await clearKeychainOnFreshInstall(
          prefs: prefs,
          files: stuck,
          wipeSecureStorage: wipe,
          isIOS: true,
        ),
        isFalse,
      );
      expect(wipes, 0);
      expect(prefs.getBool(kLegacyInstallMarkerKey), isTrue);

      stuck.readOnly = false;
      await clearKeychainOnFreshInstall(
        prefs: prefs,
        files: stuck,
        wipeSecureStorage: wipe,
        isIOS: true,
      );
      expect(wipes, 0);
      expect(marked(stuck), isTrue);
      expect(prefs.containsKey(kLegacyInstallMarkerKey), isFalse);
    });

    test('con el fichero ya puesto, una preferencia que quedara de una '
        'migración a medias se quita', () async {
      await files.writeAtomic(kInstallMarkerFileName, Uint8List(0));
      final prefs = await mockPrefs({kLegacyInstallMarkerKey: true});
      await clearKeychainOnFreshInstall(
        prefs: prefs,
        files: files,
        wipeSecureStorage: wipe,
        isIOS: true,
      );
      expect(wipes, 0);
      expect(prefs.containsKey(kLegacyInstallMarkerKey), isFalse);
    });
  });

  test('en Android no se vacía nada: solo se pone la marca', () async {
    final prefs = await mockPrefs();
    final wiped = await clearKeychainOnFreshInstall(
      prefs: prefs,
      files: files,
      wipeSecureStorage: wipe,
      isIOS: false,
    );
    expect(wiped, isFalse);
    expect(wipes, 0);
    expect(marked(files), isTrue);
  });

  test('sin decirle la plataforma, usa la del móvil', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await clearKeychainOnFreshInstall(
      prefs: await mockPrefs(),
      files: MemoryFileStore(),
      wipeSecureStorage: wipe,
    );
    expect(wipes, 0);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await clearKeychainOnFreshInstall(
      prefs: await mockPrefs(),
      files: MemoryFileStore(),
      wipeSecureStorage: wipe,
    );
    expect(wipes, 1);
  });

  test('si el llavero falla no se pone la marca y se reintenta en el '
      'siguiente arranque, sin impedir que la app arranque', () async {
    final prefs = await mockPrefs();
    var fail = true;
    Future<void> flaky() async {
      if (fail) {
        throw StateError('llavero bloqueado');
      }
      wipes++;
    }

    expect(
      await clearKeychainOnFreshInstall(
        prefs: prefs,
        files: files,
        wipeSecureStorage: flaky,
        isIOS: true,
      ),
      isFalse,
    );
    expect(marked(files), isFalse);

    fail = false;
    expect(
      await clearKeychainOnFreshInstall(
        prefs: prefs,
        files: files,
        wipeSecureStorage: flaky,
        isIOS: true,
      ),
      isTrue,
    );
    expect(wipes, 1);
    expect(marked(files), isTrue);
  });

  test('si no se puede saber si hay marca o documento, no se borra '
      'nada', () async {
    final prefs = await mockPrefs();
    final broken = _BrokenFiles();
    final wiped = await clearKeychainOnFreshInstall(
      prefs: prefs,
      files: broken,
      wipeSecureStorage: wipe,
      isIOS: true,
    );
    expect(wiped, isFalse);
    expect(wipes, 0);
    expect(broken.written, isEmpty);
    expect(prefs.getKeys(), isEmpty);
  });

  group('con las claves de una instalación anterior en el llavero', () {
    /// Lo que deja en el llavero una instalación que se desinstala: las
    /// claves siguen, y el documento y las preferencias se borran.
    Future<MemorySecretStore> leftovers() async {
      final old = FakePhone(prefs: await mockPrefs());
      addTearDown(old.dispose);
      await old.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'Instalación anterior');
      await old.container.read(lockControllerProvider.future);
      await old.container.read(lockControllerProvider.notifier).setPin('1234');
      // El nombre del documento es el que mira el primer arranque.
      expect(old.files.files.keys, [kFamilyDocFileName]);
      expect(old.secrets.values, isNotEmpty);
      return old.secrets;
    }

    test('sin la limpieza, la app reinstalada arrancaría con la familia y el '
        'PIN de antes', () async {
      final secrets = await leftovers();
      final phone = FakePhone(prefs: await mockPrefs(), secrets: secrets);
      addTearDown(phone.dispose);
      final family = await phone.container.read(
        familyControllerProvider.future,
      );
      expect(family.hasFamily, isTrue);
      final lock = await phone.container.read(lockControllerProvider.future);
      expect(lock.pinSet, isTrue);
    });

    test('con la limpieza del primer arranque en iPhone, empieza de '
        'cero', () async {
      final secrets = await leftovers();
      final prefs = await mockPrefs();
      final phone = FakePhone(prefs: prefs, secrets: secrets);
      addTearDown(phone.dispose);
      // Como en main(): antes de leer ninguna clave.
      final wiped = await clearKeychainOnFreshInstall(
        prefs: prefs,
        files: phone.files,
        wipeSecureStorage: phone.container.read(secureStorageWipeProvider),
        isIOS: true,
      );
      expect(wiped, isTrue);
      expect(phone.secrets.values, isEmpty);
      final family = await phone.container.read(
        familyControllerProvider.future,
      );
      expect(family.hasFamily, isFalse);
      final lock = await phone.container.read(lockControllerProvider.future);
      expect(lock.pinSet, isFalse);

      // La lista que se cree ahora sobrevive a los siguientes arranques.
      await phone.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'Instalación nueva');
      final listId = (await phone.container.read(
        familyControllerProvider.future,
      )).listId;
      phone.restart();
      expect(
        await clearKeychainOnFreshInstall(
          prefs: prefs,
          files: phone.files,
          wipeSecureStorage: phone.container.read(secureStorageWipeProvider),
          isIOS: true,
        ),
        isFalse,
      );
      final again = await phone.container.read(familyControllerProvider.future);
      expect(again.listId, listId);
    });

    test('al restaurar una copia de seguridad en el mismo iPhone vuelven las '
        'preferencias, pero no la marca ni el documento: el llavero se vacía '
        'igual', () async {
      // Una instalación en uso: arrancó, puso su marca y tiene familia y PIN.
      final prefs = await mockPrefs({'una.preferencia': 'sage'});
      final used = FakePhone(prefs: prefs);
      addTearDown(used.dispose);
      await clearKeychainOnFreshInstall(
        prefs: prefs,
        files: used.files,
        wipeSecureStorage: used.container.read(secureStorageWipeProvider),
        isIOS: true,
      );
      await used.container
          .read(familyControllerProvider.notifier)
          .createFamily(deviceName: 'Antes de la copia');
      await used.container.read(lockControllerProvider.future);
      await used.container.read(lockControllerProvider.notifier).setPin('1234');
      expect(used.secureWipes, 1);

      // La copia se lleva las preferencias tal cual (aquí, el mismo objeto);
      // los ficheros de la app están excluidos y el llavero no sale del
      // iPhone, así que al restaurar sigue con lo de antes.
      expect(prefs.getKeys(), {'una.preferencia'});
      final restored = FakePhone(prefs: prefs, secrets: used.secrets);
      addTearDown(restored.dispose);
      expect(restored.files.files, isEmpty);
      final wiped = await clearKeychainOnFreshInstall(
        prefs: prefs,
        files: restored.files,
        wipeSecureStorage: restored.container.read(secureStorageWipeProvider),
        isIOS: true,
      );
      expect(wiped, isTrue, reason: 'con la marca en preferencias no pasaba');
      expect(restored.secrets.values, isEmpty);
      final family = await restored.container.read(
        familyControllerProvider.future,
      );
      expect(family.hasFamily, isFalse);
      final lock = await restored.container.read(lockControllerProvider.future);
      expect(lock.pinSet, isFalse);
    });
  });
}
