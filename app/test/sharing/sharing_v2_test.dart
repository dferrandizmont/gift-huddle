// Lote B6 del ADR 0005 en la app: con la marca del formato 2, `ShareService`
// (la pantalla de copia y los ficheros que llegan de fuera) guarda y abre el
// fichero de intercambio nuevo, y cierra el de siempre con errores claros.
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/exchange_file.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/sharing/application/share_service.dart';
import 'package:regalos/features/sharing/presentation/share_error_text.dart';
import 'package:regalos/features/sync/application/app_sync_v2_local.dart';
import 'package:regalos/features/sync/application/common_v2_cutover.dart';
import 'package:regalos/features/sync/application/exchange_v2.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/fake_worker_v2.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart' show mockPrefs;
import '../sync/v2_harness.dart';

final _local = FutureProvider((ref) => AppSyncV2Local.load(ref));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeWorkerV2 worker;
  late SyncV2Client client;
  late FamilyKey key;
  late MemoryV2Phone a;
  late MemoryV2Phone b;
  late MemoryV2Phone c;
  late FakePhone phone;

  FamilyController family() =>
      phone.container.read(familyControllerProvider.notifier);
  FamilyStore store() => phone.container.read(familyStoreProvider);
  ShareService share() => phone.container.read(shareServiceProvider);
  Future<AppSyncV2Local> local() async =>
      (await phone.container.read<Future<AppSyncV2Local?>>(_local.future))!;
  Future<FamilyDoc> doc() async =>
      (await phone.container.read(familyControllerProvider.future)).doc;
  Set<String> titles(FamilyDoc d) => {
    for (final r in d.collections['gifts']?.values ?? const <SyncRecord>[])
      if (!r.isDeleted) r['title'] as String,
  };
  Future<void> syncApp() async => SyncV2Engine(
    transport: client,
    local: await local(),
    commonV2Ready: true,
  ).sync();

  setUp(() async {
    worker = FakeWorkerV2();
    client = worker.client();
    key = await FamilyKey.generate();
    a = await MemoryV2Phone.create(
      'aritz-phone',
      'aritz',
      1,
      familyKey: key,
      migrated: true,
    );
    b = await MemoryV2Phone.create('leo-phone', 'leo', 2, familyKey: key);
    c = await MemoryV2Phone.create('nora-phone', 'nora', 3, familyKey: key);
    a
      ..addPerson('aritz', 'Aritz')
      ..addPerson('leo', 'Leo')
      ..addPerson('nora', 'Nora')
      // 1.0.6: los regalos de quien tiene móvil se ponen en secreto solos;
      // estos son para alguien sin móvil.
      ..addPerson('leo-guest', 'Leo')
      ..addGift('g-1', 'leo-guest', 'Libro');
    await vouchAll([a, b, c]);
    await a.engine(client).ensureCreated();
    for (final p in [b, c]) {
      worker.addCredentialForTesting(
        kV2Sync,
        p.identity.deviceId,
        p.keys.serviceCredential,
      );
    }
    phone = FakePhone(
      prefs: await mockPrefs(),
      extraOverrides: [
        syncTransportProvider.overrideWithValue(FakeSyncServer().connect()),
        syncV2TransportProvider.overrideWithValue(client),
      ],
    );
    addTearDown(phone.dispose);
    await phone.container.read(familyControllerProvider.future);
    await family().installV2(
      listId: kV2List,
      node: a.node,
      key: key,
      doc: a.doc,
      paired: true,
    );
    await phone.container.read(deviceKeysStoreProvider).restore(a.keys);
    await family().setSelfRecipient('aritz');
    await store().saveRegistry(a.reg);
    await store().saveSyncV2(a.identity);
  });

  /// La familia (el móvil de la app, Leo y Nora) corta al formato 2.
  Future<void> cut() async {
    await b.engine(client).sync();
    await c.engine(client).sync();
    await syncApp();
    for (final p in [a, b, c]) {
      p.commonV2Ready = true;
      await client.announceCommonFormat(p.auth, kCommonFormatLatest);
    }
    await syncApp();
    await b.engine(client).sync();
    await c.engine(client).sync();
    await syncApp();
    expect(await store().readCommonFormatFloor(), 2);
    expect(b.formatFloor, 2);
    expect(c.formatFloor, 2);
  }

  test('B6: sin la marca la copia es el sobre de siempre y un fichero nuevo '
      'pide sincronizar', () async {
    expect(isLegacyEnvelope(await share().buildEnvelope()), isTrue);
    final file = ExchangeFile(
      listId: kV2List,
      syncId: kV2Sync,
      records: const [],
      packages: const [],
      common: Uint8List.fromList([0x52, 0x47, 2, 0, 0]),
    ).encode();
    await expectLater(
      share().importEnvelopeBytes(file),
      throwsA(isA<ExchangeNotReadyException>()),
    );
    expect(await store().readCommonFormatFloor(), 1);
  });

  test('B6: con la marca la copia va en el fichero nuevo, en los dos '
      'sentidos, y el de siempre no entra', () async {
    // Un fichero de siempre de antes del corte.
    final legacy = await share().buildEnvelope();
    await cut();
    // Guardar.
    await family().upsertGift(
      const Gift(
        id: 'g-app',
        recipientId: 'leo-guest',
        title: 'Puzle',
        status: GiftStatus.idea,
        rawStatus: 'idea',
        surprise: false,
        year: 2026,
      ),
    );
    final out = await share().buildEnvelope();
    expect(isExchangeFile(out), isTrue);
    final opened = await ExchangeV2(b).receive(out, nowMillis: 1);
    await b.mergeCommon(opened.doc, fromNode: opened.fromNode);
    expect(b.giftTitles, containsAll({'Libro', 'Puzle'}));
    // Abrir.
    b.addGift('g-leo', 'leo-guest', 'Cometa');
    final summary = await share().importEnvelopeBytes(
      await ExchangeV2(b).export(),
    );
    expect(summary.docChanged, isTrue);
    expect(titles(await doc()), containsAll({'Libro', 'Puzle', 'Cometa'}));
    // El de siempre: error propio, nada cambia y la marca sigue.
    final before = (await doc()).canonicalJson();
    await expectLater(
      share().importEnvelopeBytes(legacy),
      throwsA(isA<ExchangeLegacyFileException>()),
    );
    expect((await doc()).canonicalJson(), before);
    expect(await store().readCommonFormatFloor(), 2);
    // También pegado como texto.
    await expectLater(
      share().importFromText(envelopeToLink(legacy)),
      throwsA(isA<ExchangeLegacyFileException>()),
    );
  });

  test('B6: falta la clave: el fichero se guarda, el error lo dice y entra '
      'al sincronizar', () async {
    await cut();
    // Leo revoca a Nora en local y no sincroniza: su fichero va con una
    // candidata nueva; sin sus paquetes, este móvil no la tiene.
    b.reg = await b.reg.withRevocation(
      await Revocation.create(
        keys: b.keys,
        by: b.record,
        deviceId: 'nora-phone',
      ),
    );
    final docBefore = b.doc;
    b.addGift('g-file', 'leo-guest', 'Solo en el fichero');
    final file = ExchangeFile.parse(await ExchangeV2(b).export());
    b.doc = docBefore;
    final stripped = ExchangeFile(
      listId: file.listId,
      syncId: file.syncId,
      records: file.records,
      packages: const [],
      common: file.common,
    ).encode();
    final before = (await doc()).canonicalJson();
    Object? error;
    try {
      await share().importEnvelopeBytes(stripped);
    } on Object catch (e) {
      error = e;
    }
    expect(error, isA<ExchangeMissingKeyException>());
    final l10n = lookupAppLocalizations(const Locale('es'));
    expect(shareErrorMessage(l10n, error!), l10n.shareErrorMissingKey);
    expect((await doc()).canonicalJson(), before);
    final retained = await (await local()).readRetainedCommons();
    expect(retained.single.fromFile, isTrue);
    // Leo sincroniza y reparte; la vuelta siguiente de este móvil lo abre.
    await b.engine(client).sync();
    await syncApp();
    expect(titles(await doc()), contains('Solo en el fichero'));
    expect(await (await local()).readRetainedCommons(), isEmpty);
  });

  test('B6: los errores del fichero nuevo tienen su texto', () async {
    final l10n = lookupAppLocalizations(const Locale('es'));
    final texts = {
      for (final e in <Object>[
        const ExchangeLegacyFileException('x'),
        const ExchangeNotReadyException('x'),
        const ExchangeGenerationException('x'),
        const ExchangeRevokedWriterException('x'),
        const ExchangeMissingKeyException('x'),
        const ExchangeNotAllowedException('x'),
      ])
        shareErrorMessage(l10n, e),
    };
    expect(texts, hasLength(6));
    expect(texts.contains(l10n.shareErrorNotEnvelope), isFalse);
    expect(
      shareSendErrorMessage(l10n, const ExchangeNotAllowedException('x')),
      l10n.shareErrorNotAllowed,
    );
    expect(shareSendErrorMessage(l10n, StateError('x')), l10n.shareSendError);
    expect(
      shareSendErrorMessage(l10n, const EnvelopeTooLargeException('x')),
      l10n.shareErrorTooLarge,
    );
    for (final lang in ['ca', 'en']) {
      final other = lookupAppLocalizations(Locale(lang));
      expect(other.shareErrorMissingKey, isNot(l10n.shareErrorMissingKey));
    }
  });
}
