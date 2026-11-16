import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';

import '../helpers/memory_stores.dart';
import '../helpers/other_phone.dart';

const _nora = Recipient(
  id: 'nora',
  name: 'Nora',
  colorIndex: 4,
  archived: false,
);
const _leo = Recipient(id: 'leo', name: 'Leo', colorIndex: 3, archived: false);

FamilyController _ctl(ProviderContainer c) =>
    c.read(familyControllerProvider.notifier);

Future<FamilyState> _ready(ProviderContainer c) =>
    c.read(familyControllerProvider.future);

/// Deja acabar las microtareas y los guardados en memoria pendientes.
Future<void> _drain() => Future<void>.delayed(const Duration(milliseconds: 20));

/// «Yo»: el provider que dice de quién es este móvil (ADR 0004).
void main() {
  late FakePhone phone;

  setUp(() => phone = FakePhone());
  tearDown(() => phone.dispose());

  /// Una familia con Nora y Leo, y el provider escuchado (como en Ajustes).
  Future<void> family() async {
    await _ctl(phone.container).createFamily(deviceName: 'Pixel');
    await _ctl(phone.container).upsertRecipient(_nora);
    await _ctl(phone.container).upsertRecipient(_leo);
    phone.container.listen(selfRecipientIdProvider, (_, _) {});
  }

  String? self() => phone.container.read(selfRecipientIdProvider);

  Future<String?> stored() =>
      phone.container.read(familyStoreProvider).readSelfRecipient();

  SelfRecipient notifier() =>
      phone.container.read(selfRecipientIdProvider.notifier);

  test('sin familia no hay «Yo» y elegir no hace nada', () async {
    await _ready(phone.container);
    expect(self(), isNull);
    await notifier().choose('nora');
    expect(self(), isNull);
    expect(await stored(), isNull);
  });

  test('sin elegir vale null; elegir, cambiar y quitar', () async {
    await family();
    expect(self(), isNull);
    expect(phone.container.read(selfRecipientProvider), isNull);

    await notifier().choose('nora');
    expect(self(), 'nora');
    expect(phone.container.read(selfRecipientProvider)?.name, 'Nora');
    expect(await stored(), 'nora');

    await notifier().choose('leo');
    expect(self(), 'leo');
    expect(phone.container.read(selfRecipientProvider)?.name, 'Leo');
    expect(await stored(), 'leo');

    await notifier().choose(null);
    expect(self(), isNull);
    expect(phone.container.read(selfRecipientProvider), isNull);
    expect(await stored(), isNull);
  });

  test('es local: no toca el documento y solo guarda el id', () async {
    await family();
    final before = (await _ready(phone.container)).doc.canonicalJson();
    await notifier().choose('nora');
    final state = await _ready(phone.container);
    expect(state.doc.canonicalJson(), before);
    final identity =
        jsonDecode(phone.secrets.values['family.identity']!) as Map;
    expect(identity['selfRecipientId'], 'nora');
    expect(jsonEncode(identity), isNot(contains('Nora')));
  });

  test('se conserva al reabrir la app y al renombrar el móvil', () async {
    await family();
    await notifier().choose('leo');
    await _ctl(phone.container).setDeviceName('Pixel de casa');
    expect(self(), 'leo');

    phone.restart();
    await _ready(phone.container);
    expect(self(), 'leo');
    expect(
      (await _ready(phone.container)).identity!.deviceName,
      'Pixel de casa',
    );
  });

  test('un id que no es de una persona de la familia no cambia nada', () async {
    await family();
    await notifier().choose('leo');
    await notifier().choose('desconocida');
    expect(self(), 'leo');
    expect(await stored(), 'leo');
  });

  test(
    'si otro móvil elimina a la persona elegida, la elección se limpia sola',
    () async {
      await family();
      await notifier().choose('nora');
      // Aquí no se puede eliminar a «Yo»: llega de otro móvil.
      await deletedElsewhere(phone, 'nora');
      // Enseguida vale null...
      expect(self(), isNull);
      expect(phone.container.read(selfRecipientProvider), isNull);
      // ...y lo guardado se quita solo.
      await _drain();
      expect(await stored(), isNull);
      expect((await _ready(phone.container)).identity!.selfRecipientId, isNull);
      // Ya no se puede volver a elegir.
      await notifier().choose('nora');
      expect(self(), isNull);
      expect(await stored(), isNull);
    },
  );

  test('una elección guardada de alguien que ya no existe se limpia al '
      'abrir', () async {
    await family();
    await notifier().choose('nora');
    await deletedElsewhere(phone, 'nora');
    await _drain();
    // Como si la limpieza no hubiera llegado a guardarse.
    await phone.container.read(familyStoreProvider).saveSelfRecipient('nora');
    expect(await stored(), 'nora');
    phone.restart();
    await _ready(phone.container);
    phone.container.listen(selfRecipientIdProvider, (_, _) {});
    expect(self(), isNull);
    await _drain();
    expect(await stored(), isNull);
  });

  test('una persona que otro móvil archiva sigue siendo «Yo»', () async {
    await family();
    await notifier().choose('nora');
    await archivedElsewhere(phone, 'nora');
    expect(self(), 'nora');
    expect(phone.container.read(selfRecipientProvider)?.archived, isTrue);
    await _drain();
    expect(await stored(), 'nora');
  });

  test('M7: elegir «Yo» quita del llavero las claves de sorpresa de esa '
      'persona', () async {
    await family();
    final listId = (await _ready(phone.container)).listId!;
    final keys = DeviceKeysStore(phone.secrets, enabled: true);
    await keys.saveKeyring(
      listId,
      SurpriseKeyring([
        SurpriseKey.generate('nora', 1),
        SurpriseKey.generate('leo', 1),
      ]),
    );
    await notifier().choose('nora');
    expect((await keys.readKeyring(listId)).people, {'leo'});
    // Quitar la elección no devuelve nada al llavero.
    await notifier().choose(null);
    expect((await keys.readKeyring(listId)).people, {'leo'});
  });

  test('si el llavero está dañado, no se guarda la elección', () async {
    await family();
    await phone.secrets.write(kSurpriseKeysSecret, 'no es json');
    await expectLater(
      notifier().choose('nora'),
      throwsA(isA<DeviceKeysStoreException>()),
    );
    expect(self(), isNull);
    expect(await stored(), isNull);
    // Las escrituras siguientes no se quedan atascadas.
    await _ctl(phone.container).setDeviceName('Otro');
    expect((await _ready(phone.container)).identity!.deviceName, 'Otro');
  });
}
