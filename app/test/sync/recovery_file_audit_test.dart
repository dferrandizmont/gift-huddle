import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/platform/document_exchange.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/recovery_store.dart';
import 'package:regalos/features/sync/application/recovery_file_flow.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import 'recovery_engine_test.dart' show RecoveryWorker;
import 'recovery_file_flow_test.dart' show FakeExchange;
import 'sync_harness.dart' show kFastTiming;

import 'dart:convert';
import 'dart:typed_data';

/// ADR 0008 con los almacenes y el servicio simulados de verdad: guardar con
/// el selector comprueba el código, «Comprobar un fichero» solo vale con el
/// código vigente y restaurar desde un fichero es el flujo de las palabras.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecoveryWorker w;
  late Directory temp;
  setUp(() {
    w = RecoveryWorker();
    temp = Directory.systemTemp.createTempSync('recovery-file-audit');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<(FakePhone, FakeExchange)> phone() async {
    final exchange = FakeExchange();
    final p = FakePhone(
      temp: temp,
      prefs: await mockPrefs(),
      syncHost: null,
      extraOverrides: [
        syncHostProvider.overrideWithValue('sync.test'),
        syncTransportProvider.overrideWithValue(FakeSyncServer().connect()),
        syncV2TransportProvider.overrideWithValue(w.client),
        recoveryTransportProvider.overrideWith((ref) => w),
        syncTimingProvider.overrideWithValue(kFastTiming),
        documentExchangeProvider.overrideWithValue(exchange),
      ],
    );
    addTearDown(p.dispose);
    p.container.read(syncControllerProvider);
    await p.container.read(familyControllerProvider.future);
    return (p, exchange);
  }

  Future<void> create(FakePhone p) => p.container
      .read(familyControllerProvider.notifier)
      .createFamily(deviceName: 'Aritz');

  test('saving with the picker confirms the delivered code', () async {
    final (p, _) = await phone();
    await create(p);
    final display = await p.container
        .read(recoveryApplicationProvider.notifier)
        .createCode();
    expect(
      p.container.read(recoveryStatusProvider).readiness,
      RecoveryReadiness.confirmationPending,
    );
    final flow = p.container.read(recoveryFileProvider.notifier);
    final prepared = await flow.prepare(display);
    expect(
      await flow.save(prepared, fileName: 'a.gifthuddle'),
      RecoveryFileSaveResult.confirmed,
    );
    expect(
      p.container.read(recoveryStatusProvider).readiness,
      RecoveryReadiness.prepared,
    );
  });

  test('checking a file confirms only the current code', () async {
    final (p, exchange) = await phone();
    await create(p);
    final app = p.container.read(recoveryApplicationProvider.notifier);
    final old = await app.createCode();
    final flow = p.container.read(recoveryFileProvider.notifier);
    // Shared (not confirmed), then the code changes.
    final oldFile = await flow.prepare(old);
    await flow.share(oldFile, fileName: 'a.gifthuddle', text: 'x');
    final next = await app.rotateCode();
    exchange.picked = exchange.shared.single;
    final staleCheck = await flow.pickForCheck();
    await expectLater(
      flow.confirmCheck(staleCheck!),
      throwsA(
        isA<RecoveryApplicationException>().having(
          (e) => e.code,
          'code',
          'not_current_code',
        ),
      ),
    );
    expect(
      p.container.read(recoveryStatusProvider).readiness,
      RecoveryReadiness.confirmationPending,
    );
    final current = await flow.prepare(next);
    await flow.share(current, fileName: 'b.gifthuddle', text: 'x');
    exchange.picked = exchange.shared.last;
    await flow.confirmCheck((await flow.pickForCheck())!);
    expect(
      p.container.read(recoveryStatusProvider).readiness,
      RecoveryReadiness.prepared,
    );
  });

  test('a received file restores an empty phone like the words', () async {
    final (owner, ownerExchange) = await phone();
    await create(owner);
    final display = await owner.container
        .read(recoveryApplicationProvider.notifier)
        .createCode();
    final ownerFlow = owner.container.read(recoveryFileProvider.notifier);
    await ownerFlow.share(
      await ownerFlow.prepare(display),
      fileName: 'a.gifthuddle',
      text: 'x',
    );
    final (p, _) = await phone();
    final flow = p.container.read(recoveryFileProvider.notifier);
    await flow.receive(ownerExchange.shared.single);
    expect(p.container.read(recoveryFileProvider).selection!.hasFamily, false);
    await flow.open();
    await flow.restore();
    final journal = await p.container.read(recoveryStoreProvider).readRestore();
    expect(journal!.phase, RecoveryPhase.active);
    expect(
      (await p.container.read(familyControllerProvider.future)).identity,
      isNotNull,
    );
    expect(p.container.read(recoveryFileProvider).selection, isNull);
  });
  Matcher appFails(String code) => throwsA(
    isA<RecoveryApplicationException>().having((e) => e.code, 'code', code),
  );

  test('a person change keeps sid and E but no longer confirms', () async {
    final (p, exchange) = await phone();
    await create(p);
    final display = await p.container
        .read(recoveryApplicationProvider.notifier)
        .createCode();
    // Offline «Yo» change: same list, same sid, same E (no sync round
    // retires the code meanwhile).
    await p.container
        .read(syncControllerProvider.notifier)
        .suspendForRecovery();
    w.offline = true;
    await p.container.read(familyStoreProvider).saveSelfRecipient('p1');
    final flow = p.container.read(recoveryFileProvider.notifier);
    final prepared = await flow.prepare(display);
    await expectLater(
      flow.save(prepared, fileName: 'a.gifthuddle'),
      appFails('person_changed'),
    );
    exchange.picked = exchange.saved.single;
    await expectLater(
      flow.confirmCheck((await flow.pickForCheck())!),
      appFails('person_changed'),
    );
    await expectLater(
      p.container
          .read(recoveryApplicationProvider.notifier)
          .confirmCreatedCode(display),
      appFails('person_changed'),
    );
    expect(
      (await p.container
          .read(recoveryStoreProvider)
          .readMaterial(
            (await p.container.read(familyStoreProvider).readSyncV2())!.syncId,
          ))!['wordsConfirmed'],
      isNot(true),
    );
  });

  test('receiving a file only reads local state: the family controller '
      '(which may resume a restore) is never built', () async {
    final (owner, _) = await phone();
    await create(owner);
    final open = Uint8List.fromList(
      utf8.encode('GHK'),
    ); // not even valid: still no side effects
    for (final family in [true, false]) {
      final p = FakePhone(
        temp: temp,
        secrets: family ? owner.secrets : null,
        files: family ? owner.files : null,
        prefs: await mockPrefs(),
        syncHost: null,
        extraOverrides: [
          syncHostProvider.overrideWithValue('sync.test'),
          syncV2TransportProvider.overrideWithValue(w.client),
          recoveryTransportProvider.overrideWith((ref) => w),
          documentExchangeProvider.overrideWithValue(FakeExchange()),
        ],
      );
      addTearDown(p.dispose);
      await p.container.read(recoveryFileProvider.notifier).receive(open);
      final selection = p.container.read(recoveryFileProvider).selection!;
      expect(selection.hasFamily, family);
      expect(selection.failure, RecoveryFileFailure.notRecoveryFile);
      expect(p.container.read(familyControllerProvider.exists), isFalse);
    }
  });
}
