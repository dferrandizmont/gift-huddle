// Lote B5 del ADR 0005: con qué candidata puede sellar la web. Nunca la
// crea ni reparte, así que solo vuelve a sellar con la del común remoto, si
// sella desde su vista y su reparto está hecho (B6 de la revisión de seguridad).
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/family_envelope.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/family_candidate.dart';
import 'package:regalos/core/sync/family_key_bundle.dart';
import 'package:regalos/features/sync/application/common_v2.dart';
import 'package:regalos/features/sync/application/common_v2_cutover.dart';
import 'package:regalos/features/web_device/application/web_common.dart';

import '../sync/family_key_harness.dart';
import '../sync/protected_harness.dart';

void main() {
  group('instalar al emparejar', installTests);
  late Family family;
  late ({
    DeviceRegistry registry,
    Phone web,
    RegistryView root,
    RegistryView leo,
  })
  w;
  late FamilyCandidate candidate;
  late FamilyKeyring keyring;
  late Map<String, Map<String, Object?>> toOf;

  setUp(() async {
    family = await Family.create();
    w = await withWeb(family);
    candidate = await candidateFor(family, w.root);
    keyring = FamilyKeyring.empty.withReceivedCandidate(
      candidate,
      from: 'aritz-phone',
      fromRecord: w.root.self.recordDigest,
      sealable: (c) => c.sealableIn(w.root, syncId: kSync),
    );
    toOf = {
      for (final to in ['leo-phone', 'nora-phone', 'web-1'])
        to: (await FamilyKeyBundle.seal(
          sender: family.aritz.keys,
          view: w.root,
          syncId: kSync,
          toDevice: to,
          candidate: candidate,
        )).toJson(),
    };
  });

  Future<FamilyCandidate?> sealing({
    FamilyKeyring? ring,
    String? remoteKid,
    String writer = 'aritz-phone',
    RegistryView? view,
    List<Map<String, Object?>>? packages,
  }) => webSealingCandidate(
    keyring: ring ?? keyring,
    remoteKid: remoteKid ?? candidate.kid,
    writer: writer,
    view: view ?? w.root,
    registry: w.registry,
    syncId: kSync,
    me: 'web-1',
    packages: packages ?? toOf.values.toList(),
  );

  test('con el reparto hecho, sella con la del común remoto', () async {
    expect((await sealing())?.kid, candidate.kid);
    // El paquete de la propia web no hace falta.
    expect(
      (await sealing(packages: [toOf['leo-phone']!, toOf['nora-phone']!]))?.kid,
      candidate.kid,
    );
  });

  test('sin el paquete de un miembro no sella (B6); el escritor del '
      'común remoto ya la tiene', () async {
    expect(await sealing(packages: [toOf['leo-phone']!]), isNull);
    expect(
      (await sealing(
        packages: [toOf['leo-phone']!],
        writer: 'nora-phone',
      ))?.kid,
      candidate.kid,
    );
  });

  test(
    'un paquete manipulado o de otra ficha no cuenta como reparto',
    () async {
      final forged = {...toOf['nora-phone']!, 'sig': toOf['leo-phone']!['sig']};
      expect(await sealing(packages: [toOf['leo-phone']!, forged]), isNull);
      final otherRecord = {
        ...toOf['nora-phone']!,
        'tr': w.root.member('leo-phone')!.recordDigest,
      };
      expect(
        await sealing(packages: [toOf['leo-phone']!, otherRecord]),
        isNull,
      );
    },
  );

  test(
    'nunca crea: sin común remoto, con otro kid o sin la candidata, nada',
    () async {
      final other = await candidateFor(family, w.root, seed: 9);
      expect(
        await webSealingCandidate(
          keyring: keyring,
          remoteKid: null,
          writer: null,
          view: w.root,
          registry: w.registry,
          syncId: kSync,
          me: 'web-1',
          packages: toOf.values.toList(),
        ),
        isNull,
      );
      expect(await sealing(remoteKid: other.kid), isNull);
      expect(await sealing(ring: FamilyKeyring.empty), isNull);
    },
  );

  test(
    'ni histórica, ni comprometida, ni una que ya no sella desde su vista',
    () async {
      expect(
        await sealing(ring: keyring.markHistorical(candidate.kid)),
        isNull,
      );
      expect(
        await sealing(ring: keyring.markCompromised(candidate.kid)),
        isNull,
      );
      final withoutNora = await candidateFor(
        family,
        w.root,
        seed: 11,
        audience: candidate.audience.where((m) => m.deviceId != 'nora-phone'),
      );
      final ring = keyring.withReceivedCandidate(
        withoutNora,
        from: 'aritz-phone',
        fromRecord: w.root.self.recordDigest,
        sealable: (c) => c.sealableIn(w.root, syncId: kSync),
      );
      expect(await sealing(ring: ring, remoteKid: withoutNora.kid), isNull);
      // Tras revocar a Nora, la de antes ya no sella (audiencia con revocado).
      final revoked = await withRevoked(family, family.nora);
      final web = await DeviceRecord.create(
        keys: w.web.keys,
        listId: kListId,
        deviceId: 'web-1',
        personId: null,
        kind: DeviceKind.web,
      );
      final registry = await (await revoked.withRecord(web)).withVouch(
        await Vouch.create(
          keys: family.aritz.keys,
          voucher: await family.aritz.record(),
          record: web,
        ),
      );
      final after = await family.aritz.viewOf(registry);
      expect(await sealing(view: after), isNull);
    },
  );

  test('B1: el paquete de un no miembro con el kid cambiado no '
      'cuenta como reparto', () async {
    // Mallory: claves propias, ficha de móvil autofirmada, sin aval.
    final mallory = await Phone.create('mallory-phone', null, 9);
    final record = await mallory.record();
    final nora = w.root.member('nora-phone')!;
    final fake = await FamilyCandidate.create(
      listId: kListId,
      syncId: kSync,
      epochNumber: candidate.epochNumber,
      epochContext: candidate.epochContext,
      creator: 'mallory-phone',
      creatorRecord: record.digest,
      audience: [
        AudienceMember('mallory-phone', record.digest),
        AudienceMember('nora-phone', nora.recordDigest),
      ],
      secret: secretOf(42),
      creatorKeys: mallory.keys,
    );
    final sealed = await FamilyKeyBundle.sealForTesting(
      sender: mallory.keys,
      candidate: fake,
      fromDevice: 'mallory-phone',
      senderRecord: record.digest,
      toDevice: 'nora-phone',
      recipientRecord: nora.recordDigest,
      recipientAgreementKey: nora.agreementKey,
    );
    final forged =
        (await sealed
                .copyForTesting(kid: candidate.kid)
                .resignForTesting(
                  sender: mallory.keys,
                  recipientAgreementKey: nora.agreementKey,
                ))
            .toJson();
    final registry = await DeviceRegistry.fromJsonVerified(
      (await w.registry.withRecord(record)).toJson(),
      anchor: RegistryAnchor(
        deviceId: 'aritz-phone',
        signingKey: family.aritz.keys.publicKeys.signing,
      ),
    );
    final view = await family.aritz.viewOf(registry);
    expect(view.member('mallory-phone'), isNull);
    expect(
      await webSealingCandidate(
        keyring: keyring,
        remoteKid: candidate.kid,
        writer: 'aritz-phone',
        view: view,
        registry: registry,
        syncId: kSync,
        me: 'web-1',
        packages: [toOf['leo-phone']!, forged],
      ),
      isNull,
    );
  });

  test('B1: un miembro que firma un paquete con otra cabecera (otra '
      'audiencia) no lo reparte', () async {
    final other = await candidateFor(
      family,
      w.root,
      audience: candidate.audience.where((m) => m.deviceId != 'leo-phone'),
    );
    final sealed = await FamilyKeyBundle.seal(
      sender: family.aritz.keys,
      view: w.root,
      syncId: kSync,
      toDevice: 'nora-phone',
      candidate: other,
    );
    final mixed =
        (await sealed
                .copyForTesting(kid: candidate.kid)
                .resignForTesting(
                  sender: family.aritz.keys,
                  recipientAgreementKey: family.nora.keys.publicKeys.agreement,
                ))
            .toJson();
    expect(
      await webDeliveredPackage(
        mixed,
        candidate,
        candidate.audienceOf('nora-phone')!,
        w.root,
        w.registry,
      ),
      isFalse,
    );
    expect(
      await webDeliveredPackage(
        toOf['nora-phone']!,
        candidate,
        candidate.audienceOf('nora-phone')!,
        w.root,
        w.registry,
      ),
      isTrue,
    );
  });

  test('la marca de la caja: sin marca 1, una que no se entiende cuenta como '
      '2, y sin el estado con la marca no se empieza de cero', () {
    expect(webCommonFloor({}), 1);
    expect(webCommonFloor({kWebCommonFloorField: 2}), 2);
    expect(webCommonFloor({kWebCommonFloorField: 3}), 3);
    for (final bad in ['2', 0, -1, 1.5, true]) {
      expect(webCommonFloor({kWebCommonFloorField: bad}), kCommonFormatLatest);
    }
    expect(webCommonKeys({}).keyring.length, 0);
    expect(
      () => webCommonKeys({kWebCommonFloorField: 2}),
      throwsA(isA<CommonStateException>()),
    );
    expect(
      () => webCommonKeys({kWebCommonKeysField: 'basura'}),
      throwsA(isA<FamilyKeyException>()),
    );
  });
}

void installTests() {
  late Family family;
  late ({
    DeviceRegistry registry,
    Phone web,
    RegistryView root,
    RegistryView leo,
  })
  w;
  late FamilyCandidate candidate;
  late CommonKeyState keys;
  final common = FamilyDoc.empty(kListId).set(
    HlcClock(node: 'aritz-phone'),
    Collections.gifts,
    'g1',
    {'recipientId': 'leo', 'title': 'Cometa'},
  );
  final saved = <String, Object?>{
    'listId': kListId,
    'familyKey': 'local',
    'snapshot': {'version': 7, 'common': 'AAAA', 'slots': <Object?>[]},
  };

  setUp(() async {
    family = await Family.create();
    w = await withWeb(family);
    candidate = await candidateFor(family, w.root);
    keys = CommonKeyState(
      keyring: FamilyKeyring.empty.withReceivedCandidate(
        candidate,
        from: 'aritz-phone',
        fromRecord: w.root.self.recordDigest,
        sealable: (c) => c.sealableIn(w.root, syncId: kSync),
      ),
      lastKid: candidate.kid,
    );
  });

  Future<Map<String, Object?>> install({
    int format = 2,
    CommonKeyState? state,
    bool noKeys = false,
    String syncId = kSync,
  }) => webCommonInstall(
    saved,
    commonFormat: format,
    commonKeys: noKeys ? null : state ?? keys,
    common: common,
    keys: w.web.keys,
    deviceId: 'web-1',
    registry: w.registry,
    root: RegistryAnchor(
      deviceId: 'aritz-phone',
      signingKey: family.aritz.keys.publicKeys.signing,
    ),
    syncId: syncId,
  );

  test('B7: la web nace con la marca, el llavero y una base que reabre sin '
      'red', () async {
    final data = await install();
    expect(webCommonFloor(data), 2);
    final ks = webCommonKeys(data);
    expect(ks.lastKid, candidate.kid);
    expect(ks.keyring.entry(candidate.kid)!.references, contains(kCommonRef));
    final snap = data['snapshot']! as Map;
    expect(snap['version'], 7);
    final bytes = decodeBase64Url(snap['common']! as String);
    expect(peekFamilyEnvelope(bytes).writer, 'web-1');
    final opened = await openSavedCommon(data, listId: kListId, syncId: kSync);
    expect(opened.canonicalJson(), common.canonicalJson());
    // Lo demás de la caja, igual.
    expect(data['familyKey'], 'local');
  });

  test('B7: formato 1 deja la caja como siempre; sin la candidata del '
      'checkpoint o con un formato posterior, no se instala', () async {
    expect(await install(format: 1, noKeys: true), same(saved));
    await expectLater(
      install(noKeys: true),
      throwsA(isA<CommonStateException>()),
    );
    await expectLater(
      install(state: CommonKeyState(keyring: keys.keyring)),
      throwsA(isA<CommonStateException>()),
    );
    await expectLater(
      install(format: 3),
      throwsA(isA<EnvelopeFormatException>()),
    );
    // B5 de la revisión de seguridad: lo sellado se reabre con los datos de la caja.
    await expectLater(
      install(syncId: kOtherSync),
      throwsA(isA<CommonStateException>()),
    );
  });
}
