import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/domain/family_errors.dart';

import '../helpers/memory_stores.dart';
import '../helpers/other_phone.dart';

const _nora = Recipient(
  id: 'nora',
  name: 'Nora',
  colorIndex: 4,
  birthMonth: 6,
  birthDay: 12,
  archived: false,
);
const _leo = Recipient(id: 'leo', name: 'Leo', colorIndex: 3, archived: false);

Gift _gift(String id, String recipient) => Gift(
  id: id,
  recipientId: recipient,
  title: 'Regalo $id',
  status: GiftStatus.idea,
  rawStatus: 'idea',
  surprise: false,
  year: 2026,
);

Matcher _refused(String id, DevicePersonOwner owner) => throwsA(
  isA<DevicePersonException>()
      .having((e) => e.recipientId, 'recipientId', id)
      .having((e) => e.owner, 'owner', owner),
);

/// A la persona de un móvil de la familia no se la puede archivar ni eliminar
/// (defensa del controlador; la pantalla ya desactiva los botones).
void main() {
  late FakePhone phone;
  late FamilyController controller;

  Future<FamilyState> state() =>
      phone.container.read(familyControllerProvider.future);

  Future<String> json() async => (await state()).doc.canonicalJson();

  setUp(() async {
    phone = FakePhone();
    controller = phone.container.read(familyControllerProvider.notifier);
    await controller.createFamily(deviceName: 'Pixel');
    await controller.upsertRecipient(_nora);
    await controller.upsertRecipient(_leo);
    await controller.ensureBirthdayOccasions();
    await controller.upsertGift(_gift('g1', 'nora'));
    await controller.upsertGift(_gift('g2', 'leo'));
  });
  tearDown(() => phone.dispose());

  test('sin «Yo» nadie es la persona de un móvil', () async {
    final s = await state();
    expect(s.isDevicePerson('nora'), isFalse);
    expect(s.devicePersonOwner('nora'), isNull);
    expect(s.isDevicePerson('nadie'), isFalse);
    // Una lista v1 no tiene registro firmado de otros móviles.
    expect(s.otherDevicePeople, isEmpty);
  });

  test('«Yo» es la persona de este móvil; los demás, de ninguno', () async {
    await controller.setSelfRecipient('nora');
    final s = await state();
    expect(s.isDevicePerson('nora'), isTrue);
    expect(s.devicePersonOwner('nora'), DevicePersonOwner.thisDevice);
    expect(s.isDevicePerson('leo'), isFalse);
  });

  test('archivar a «Yo» lanza y no escribe nada', () async {
    await controller.setSelfRecipient('nora');
    final before = await json();
    await expectLater(
      controller.archiveRecipient('nora'),
      _refused('nora', DevicePersonOwner.thisDevice),
    );
    expect(await json(), before);
    expect(
      (await state()).fullView.recipients
          .singleWhere((r) => r.id == 'nora')
          .archived,
      isFalse,
    );
  });

  test(
    'eliminar a «Yo» lanza: siguen ella, sus regalos y su cumpleaños',
    () async {
      await controller.setSelfRecipient('nora');
      final before = await json();
      await expectLater(
        controller.deleteRecipient('nora'),
        _refused('nora', DevicePersonOwner.thisDevice),
      );
      expect(await json(), before);
      final s = await state();
      expect(s.view.recipients.map((r) => r.id), contains('nora'));
      expect(s.view.gifts.map((g) => g.id), contains('g1'));
      expect(
        s.view.occasions.where(
          (o) => o.kind == OccasionKind.birthday && o.recipientId == 'nora',
        ),
        hasLength(1),
      );
      expect((await state()).identity!.selfRecipientId, 'nora');
    },
  );

  test(
    'guardar a «Yo» como archivada lanza; cambiarle el nombre, no',
    () async {
      await controller.setSelfRecipient('nora');
      final before = await json();
      await expectLater(
        controller.upsertRecipient(
          const Recipient(
            id: 'nora',
            name: 'Nora',
            colorIndex: 4,
            birthMonth: 6,
            birthDay: 12,
            archived: true,
          ),
        ),
        _refused('nora', DevicePersonOwner.thisDevice),
      );
      expect(await json(), before);

      await controller.upsertRecipient(
        const Recipient(
          id: 'nora',
          name: 'Nora Martí',
          colorIndex: 4,
          birthMonth: 6,
          birthDay: 12,
          archived: false,
        ),
      );
      expect(
        (await state()).view.recipients.singleWhere((r) => r.id == 'nora').name,
        'Nora Martí',
      );
    },
  );

  test('tras un intento rechazado el controlador sigue escribiendo, y a los '
      'demás se les puede archivar y eliminar', () async {
    await controller.setSelfRecipient('nora');
    await expectLater(
      controller.deleteRecipient('nora'),
      throwsA(isA<DevicePersonException>()),
    );
    await controller.archiveRecipient('leo');
    expect(
      (await state()).fullView.recipients
          .singleWhere((r) => r.id == 'leo')
          .archived,
      isTrue,
    );
    await controller.deleteRecipient('leo');
    expect((await state()).fullView.recipients.map((r) => r.id), ['nora']);
  });

  test('en cuanto deja de ser «Yo» se la puede archivar y eliminar', () async {
    await controller.setSelfRecipient('nora');
    await controller.setSelfRecipient('leo');
    await controller.archiveRecipient('nora');
    await controller.deleteRecipient('nora');
    expect((await state()).fullView.recipients.map((r) => r.id), ['leo']);
    await expectLater(
      controller.archiveRecipient('leo'),
      _refused('leo', DevicePersonOwner.thisDevice),
    );
    await controller.setSelfRecipient(null);
    await controller.archiveRecipient('leo');
    await controller.deleteRecipient('leo');
    expect((await state()).fullView.recipients, isEmpty);
  });

  test('la protección sigue al volver a abrir la app', () async {
    await controller.setSelfRecipient('nora');
    phone.restart();
    controller = phone.container.read(familyControllerProvider.notifier);
    await state();
    await expectLater(
      controller.archiveRecipient('nora'),
      _refused('nora', DevicePersonOwner.thisDevice),
    );
    await expectLater(
      controller.deleteRecipient('nora'),
      _refused('nora', DevicePersonOwner.thisDevice),
    );
  });

  test('si otro móvil la archivó, a «Yo» se la puede recuperar y guardar, '
      'pero no eliminar ni volver a archivar', () async {
    await controller.setSelfRecipient('nora');
    await archivedElsewhere(phone, 'nora');
    bool archived() => phone.container
        .read(familyControllerProvider)
        .requireValue
        .fullView
        .recipients
        .singleWhere((r) => r.id == 'nora')
        .archived;
    expect(archived(), isTrue);

    // Ya está archivada: guardarla tal cual (el editor conserva el dato) o
    // pedir archivarla otra vez no lanza ni cambia nada.
    await controller.upsertRecipient(
      const Recipient(
        id: 'nora',
        name: 'Nora M.',
        colorIndex: 4,
        birthMonth: 6,
        birthDay: 12,
        archived: true,
      ),
    );
    await controller.archiveRecipient('nora');
    expect(archived(), isTrue);

    await expectLater(
      controller.deleteRecipient('nora'),
      _refused('nora', DevicePersonOwner.thisDevice),
    );

    await controller.archiveRecipient('nora', archived: false);
    expect(archived(), isFalse);
    await expectLater(
      controller.archiveRecipient('nora'),
      _refused('nora', DevicePersonOwner.thisDevice),
    );
  });

  test('eliminar a alguien que no existe o ya está eliminado sigue sin hacer '
      'nada, aunque «Yo» apunte ahí', () async {
    await controller.setSelfRecipient('nora');
    await deletedElsewhere(phone, 'nora');
    final before = await json();
    await controller.deleteRecipient('nora');
    await controller.archiveRecipient('nora');
    await controller.deleteRecipient('nadie');
    expect(await json(), before);
  });
}
