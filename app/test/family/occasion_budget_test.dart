import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/sharing/application/pairing_service.dart';
import 'package:regalos/features/sharing/application/share_service.dart';

import '../helpers/memory_stores.dart';

const _christmas = Occasion(
  id: 'navidad',
  kind: OccasionKind.santa,
  rawKind: 'santa',
  name: 'Navidad',
  month: 12,
  day: 25,
  recurring: true,
  archived: false,
);

void main() {
  late FakePhone phone;
  late FamilyController controller;

  Future<FamilyDoc> doc([FakePhone? other]) async =>
      (await (other ?? phone).container.read(familyControllerProvider.future))
          .doc;

  Future<SyncRecord> record([FakePhone? other]) async =>
      (await doc(other)).record(Collections.occasions, _christmas.id)!;

  Future<SyncRecord> mergeRemoteFields(Map<String, Object?> fields) async {
    final local = await doc();
    final remoteClock = HlcClock(node: 'remote', last: local.maxStamp);
    final remote = local.set(
      remoteClock,
      Collections.occasions,
      _christmas.id,
      fields,
    );
    await controller.mergeRemote(remote, fromNode: remoteClock.node);
    final merged = await record();
    expect(
      merged.fields,
      remote.record(Collections.occasions, _christmas.id)!.fields,
    );
    return merged;
  }

  setUp(() async {
    phone = FakePhone();
    controller = phone.container.read(familyControllerProvider.notifier);
    await controller.createFamily(deviceName: 'Móvil');
    await controller.upsertOccasion(_christmas);
  });
  tearDown(() => phone.dispose());

  test('el presupuesto y el editor conservan los sellos del otro', () async {
    final before = await record();
    await controller.setOccasionBudget(_christmas.id, 50000);
    final after = await record();
    final budget = after.field('budgetCents')!;
    expect(budget.value, 50000);
    expect(after.fields, {...before.fields, 'budgetCents': budget});

    await controller.upsertOccasion(
      const Occasion(
        id: 'navidad',
        kind: OccasionKind.santa,
        rawKind: 'santa',
        name: 'Fiesta de Navidad',
        month: 12,
        day: 25,
        recurring: true,
        archived: false,
      ),
    );
    final edited = await record();
    expect(edited['name'], 'Fiesta de Navidad');
    expect(edited.field('budgetCents'), budget);

    await controller.setOccasionBudget(_christmas.id, null);
    final cleared = await record();
    final clearedBudget = cleared.field('budgetCents')!;
    expect(clearedBudget.value, isNull);
    expect(clearedBudget.stamp > budget.stamp, isTrue);
    expect(cleared.fields, {...edited.fields, 'budgetCents': clearedBudget});
  });

  test('quitar un presupuesto ausente escribe null con sello', () async {
    expect((await record()).field('budgetCents'), isNull);
    await controller.setOccasionBudget(_christmas.id, null);
    final budget = (await record()).field('budgetCents');
    expect(budget, isNotNull);
    expect(budget!.value, isNull);
  });

  test(
    'cambiar solo el presupuesto conserva la fecha remota y su sello',
    () async {
      final original = Occasion.fromRecord(await record())!;
      final remote = await mergeRemoteFields({'month': 11, 'day': 24});

      await controller.upsertOccasion(
        original.copyWith(budgetCents: 15000),
        original: original,
      );

      final saved = await record();
      expect(saved[Occasion.budgetField], 15000);
      expect(saved.fields, {
        ...remote.fields,
        Occasion.budgetField: saved.field(Occasion.budgetField),
      });
    },
  );

  test(
    'cambiar solo el nombre conserva el presupuesto remoto y su sello',
    () async {
      final original = Occasion.fromRecord(await record())!;
      final remote = await mergeRemoteFields({Occasion.budgetField: 15000});
      final renamed = Occasion(
        id: original.id,
        kind: original.kind,
        rawKind: original.rawKind,
        name: 'Fiesta de Navidad',
        month: original.month,
        day: original.day,
        recurring: original.recurring,
        archived: original.archived,
      );

      await controller.upsertOccasion(renamed, original: original);

      final saved = await record();
      expect(saved['name'], 'Fiesta de Navidad');
      expect(saved.fields, {...remote.fields, 'name': saved.field('name')});
    },
  );

  test('valida el importe y solo escribe en ocasiones existentes', () async {
    final before = await doc();
    for (final invalid in [-1, kMaxCents + 1]) {
      await expectLater(
        controller.setOccasionBudget(_christmas.id, invalid),
        throwsRangeError,
      );
    }
    await controller.setOccasionBudget('missing', 50000);
    expect((await doc()).canonicalJson(), before.canonicalJson());

    await controller.deleteOccasion(_christmas.id);
    final deleted = await doc();
    await controller.setOccasionBudget(_christmas.id, 50000);
    expect((await doc()).canonicalJson(), deleted.canonicalJson());
  });

  test(
    'rechaza presupuestos fuera de rango al dar de alta una ocasión',
    () async {
      final before = await doc();
      for (final invalid in [-1, kMaxCents + 1]) {
        final occasion = Occasion(
          id: 'reyes',
          kind: OccasionKind.kings,
          rawKind: 'kings',
          name: 'Reyes',
          month: 1,
          day: 6,
          recurring: true,
          archived: false,
          budgetCents: invalid,
        );
        await expectLater(
          controller.upsertOccasion(occasion),
          throwsRangeError,
        );
        expect((await doc()).canonicalJson(), before.canonicalJson());
      }
    },
  );

  test('rechaza presupuestos fuera de rango durante el primer uso', () async {
    final other = FakePhone();
    addTearDown(other.dispose);
    final onboarding = other.container.read(familyControllerProvider.notifier);
    for (final invalid in [-1, kMaxCents + 1]) {
      await expectLater(
        onboarding.createFamilyWith(
          deviceName: 'Nora',
          occasions: [_christmas.copyWith(budgetCents: invalid)],
          region: 'ES',
        ),
        throwsRangeError,
      );
      final state = await other.container.read(familyControllerProvider.future);
      expect(state.hasFamily, isFalse);
    }
  });

  test('el editor guarda, cambia y quita el presupuesto de una ocasión '
      'que ya existe, solo si lo cambió', () async {
    // Un alta lleva su presupuesto.
    final fresh = _christmas.copyWith(budgetCents: 20000);
    await controller.upsertOccasion(
      const Occasion(
        id: 'reyes',
        kind: OccasionKind.kings,
        rawKind: 'kings',
        name: 'Reyes',
        month: 1,
        day: 6,
        recurring: true,
        archived: false,
        budgetCents: 20000,
      ),
    );
    expect(
      (await doc()).record(Collections.occasions, 'reyes')!['budgetCents'],
      20000,
    );

    // Se cambia desde el editor, con la ocasión que se abrió como original.
    await controller.upsertOccasion(fresh, original: _christmas);
    expect((await record())['budgetCents'], 20000);

    // Se abre con 200 y se guarda sin tocarlo mientras otro móvil lo cambió a
    // 300: no se pisa.
    await controller.setOccasionBudget(_christmas.id, 30000);
    final remoteBudget = (await record()).field('budgetCents')!;
    await controller.upsertOccasion(
      fresh.copyWith(budgetCents: 20000),
      original: fresh,
    );
    expect((await record()).field('budgetCents'), remoteBudget);

    // Se vacía el campo: se quita con su propio sello.
    await controller.upsertOccasion(
      _christmas,
      original: fresh.copyWith(budgetCents: 30000),
    );
    final cleared = (await record()).field('budgetCents')!;
    expect(cleared.value, isNull);
    expect(cleared.stamp, greaterThan(remoteBudget.stamp));
  });

  test('la copia de seguridad conserva el presupuesto y su sello', () async {
    final share = phone.container.read(shareServiceProvider);
    Future<SyncRecord> readBackup() async {
      final bytes = await share.buildEnvelope();
      final opened = await open(
        bytes,
        key: controller.familyKey!,
        expectedListId: (await doc()).listId,
      );
      return FamilyDoc.fromJson(opened.doc)
          .record(Collections.occasions, _christmas.id)!;
    }

    expect(Occasion.fromRecord(await readBackup()), _christmas);
    await controller.setOccasionBudget(_christmas.id, 50000);
    final backup = await readBackup();
    expect(backup.field('budgetCents'), (await record()).field('budgetCents'));
    expect(Occasion.fromRecord(backup)?.budgetCents, 50000);
  });

  test(
    'restaurar una copia conserva el null y su sello más reciente',
    () async {
      final other = FakePhone();
      addTearDown(other.dispose);
      final qr = await phone.container
          .read(pairingServiceProvider)
          .qrTextForPairing();
      await other.container.read(pairingServiceProvider).joinFromQr(qr);
      final source = phone.container.read(shareServiceProvider);
      final target = other.container.read(shareServiceProvider);

      await controller.setOccasionBudget(_christmas.id, 50000);
      final old = (await record()).field(Occasion.budgetField)!;
      final oldBackup = await source.buildEnvelope();
      await target.importEnvelopeBytes(oldBackup);
      expect((await record(other)).field(Occasion.budgetField), old);

      await controller.setOccasionBudget(_christmas.id, null);
      final cleared = (await record()).field(Occasion.budgetField)!;
      expect(cleared.value, isNull);
      expect(cleared.stamp, greaterThan(old.stamp));
      await target.importEnvelopeBytes(await source.buildEnvelope());
      expect((await record(other)).field(Occasion.budgetField), cleared);

      await target.importEnvelopeBytes(oldBackup);
      other.restart();
      final restored = await record(other);
      expect(restored.field(Occasion.budgetField), cleared);
      expect(Occasion.fromRecord(restored)?.budgetCents, isNull);
    },
  );
}
