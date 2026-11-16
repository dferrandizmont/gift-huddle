// Paquetes v4 de la clave común (ADR 0005, lote B1, con los arreglos de la
// revisión de seguridad): cada campo del AAD con su error concreto, también
// firmado de nuevo para llegar al GCM; kid, firma del creador, audiencia
// del registro, generación, ámbito, orden bajo de X25519, webs, pendientes,
// fichas viejas e inundaciones del llavero.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart' show encodeBase64Url;
import 'package:regalos/core/sync/family_candidate.dart';
import 'package:regalos/core/sync/family_key_bundle.dart';
import 'package:regalos/core/sync/key_bundle.dart';

import 'family_key_harness.dart';
import 'protected_harness.dart';

Matcher _fails(String message) => throwsA(
  isA<KeyBundleException>().having((e) => e.message, 'message', message),
);

void main() {
  // Orden bajo de Curve25519 (y sus formas no reducidas): el secreto X25519
  // sale todo ceros.
  final lowOrder = <String>[
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0100000000000000000000000000000000000000000000000000000000000000',
    'e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800',
    '5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157',
    'ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'cdeb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b880',
    '4c9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f11d7',
    'd9ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    'daffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    'dbffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  ].map(_hex).toList();

  late Family family;
  late FamilyCandidate candidate;
  setUp(() async {
    family = await Family.create();
    candidate = await candidateFor(family, family.view);
  });

  String digestOf(Phone phone) => family.view.member(phone.id)!.recordDigest;

  Future<FamilyKeyBundle> forLeo([FamilyCandidate? c]) => FamilyKeyBundle.seal(
    sender: family.aritz.keys,
    view: family.view,
    syncId: kSync,
    toDevice: family.leo.id,
    candidate: c ?? candidate,
  );

  Future<FamilyCandidate> openAs(
    FamilyKeyBundle bundle, {
    Phone? phone,
    RegistryView? view,
    DeviceRegistry? registry,
    String syncId = kSync,
  }) {
    final p = phone ?? family.leo;
    return bundle.open(
      mine: p.keys,
      view: view ?? family.viewOf(p),
      registry: registry ?? family.registry,
      syncId: syncId,
    );
  }

  Future<FamilyKeyBundle> forged(
    FamilyCandidate c, {
    Phone? signer,
    Phone? from,
    Phone? to,
    List<int>? secret,
  }) {
    final f = from ?? family.aritz;
    final t = to ?? family.leo;
    return FamilyKeyBundle.sealForTesting(
      sender: (signer ?? f).keys,
      candidate: c,
      fromDevice: f.id,
      senderRecord: digestOf(f),
      toDevice: t.id,
      recipientRecord: digestOf(t),
      recipientAgreementKey: t.keys.publicKeys.agreement,
      secretForTesting: secret,
    );
  }

  test('ida y vuelta, también por JSON', () async {
    final bundle = FamilyKeyBundle.fromJson((await forLeo()).toJson());
    final got = await openAs(bundle);
    expect(got.kid, candidate.kid);
    expect(got.secret, candidate.secret);
    expect(got.audience, candidate.audience);
    expect(got.creator, 'aritz-phone');
    expect(got.creatorSignature, candidate.creatorSignature);
    expect(bundle.toJson()['v'], 4);
  });

  test('sealForAudience reparte a todos los demás de la audiencia', () async {
    final bundles = await FamilyKeyBundle.sealForAudience(
      sender: family.aritz.keys,
      view: family.view,
      syncId: kSync,
      candidate: candidate,
    );
    expect(bundles.map((b) => b.toDevice), ['leo-phone', 'nora-phone']);
    expect((await openAs(bundles.last, phone: family.nora)).kid, candidate.kid);
  });

  test('cada campo del AAD: sin volver a firmar falla la firma (o la '
      'comprobación previa); firmado de nuevo, falla el GCM', () async {
    final bundle = await forLeo();
    final other = await candidateFor(family, family.view, seed: 9);
    final noNora = [
      for (final m in candidate.audience)
        if (m.deviceId != 'nora-phone') m,
    ];
    const sig = 'firma no válida';
    const gcm = 'el paquete no se puede abrir';
    final cases =
        <
          String,
          ({
            FamilyKeyBundle bundle,
            Phone opener,
            Phone sender,
            Phone? creator,
            String syncId,
            String plain,
            String resigned,
          })
        >{
          'época': (
            bundle: bundle.copyForTesting(epochNumber: 2),
            opener: family.leo,
            sender: family.aritz,
            creator: family.aritz,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
          'contexto': (
            bundle: bundle.copyForTesting(epochContext: 'a' * 64),
            opener: family.leo,
            sender: family.aritz,
            creator: family.aritz,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
          'kid': (
            bundle: bundle.copyForTesting(kid: other.kid),
            opener: family.leo,
            sender: family.aritz,
            creator: family.aritz,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
          'generación': (
            bundle: bundle.copyForTesting(syncId: kOtherSync),
            opener: family.leo,
            sender: family.aritz,
            creator: family.aritz,
            syncId: kOtherSync,
            plain: sig,
            resigned: gcm,
          ),
          'lista': (
            bundle: bundle.copyForTesting(listId: 'list-2'),
            opener: family.leo,
            sender: family.aritz,
            creator: family.aritz,
            syncId: kSync,
            plain: 'el paquete es de otra lista',
            resigned: 'el paquete es de otra lista',
          ),
          'creador': (
            bundle: bundle.copyForTesting(
              creator: 'leo-phone',
              creatorRecord: digestOf(family.leo),
            ),
            opener: family.leo,
            sender: family.aritz,
            creator: family.leo,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
          'firma del creador': (
            bundle: bundle.copyForTesting(
              creatorSignature: List<int>.filled(64, 7),
            ),
            opener: family.leo,
            sender: family.aritz,
            creator: null,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
          'emisor': (
            bundle: bundle.copyForTesting(
              fromDevice: 'nora-phone',
              senderRecord: digestOf(family.nora),
            ),
            opener: family.leo,
            sender: family.nora,
            creator: null,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
          'ficha del emisor': (
            bundle: bundle.copyForTesting(senderRecord: digestOf(family.nora)),
            opener: family.leo,
            sender: family.aritz,
            creator: null,
            syncId: kSync,
            plain: 'cabecera del paquete no válida',
            resigned: 'cabecera del paquete no válida',
          ),
          'destinatario': (
            bundle: bundle.copyForTesting(
              toDevice: 'nora-phone',
              recipientRecord: digestOf(family.nora),
            ),
            opener: family.nora,
            sender: family.aritz,
            creator: null,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
          'ficha del destinatario': (
            bundle: bundle.copyForTesting(
              recipientRecord: digestOf(family.nora),
            ),
            opener: family.leo,
            sender: family.aritz,
            creator: null,
            syncId: kSync,
            plain: 'cabecera del paquete no válida',
            resigned: 'cabecera del paquete no válida',
          ),
          'audiencia (quitar)': (
            bundle: bundle.copyForTesting(audience: noNora),
            opener: family.leo,
            sender: family.aritz,
            creator: family.aritz,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
          'audiencia (orden)': (
            bundle: bundle.copyForTesting(
              audience: candidate.audience.reversed.toList(),
            ),
            opener: family.leo,
            sender: family.aritz,
            creator: null,
            syncId: kSync,
            plain: 'cabecera del paquete no válida',
            resigned: 'cabecera del paquete no válida',
          ),
          'efímera': (
            bundle: bundle.copyForTesting(
              ephemeralPublicKey: family.nora.keys.publicKeys.agreement,
            ),
            opener: family.leo,
            sender: family.aritz,
            creator: null,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
          'nonce': (
            bundle: bundle.copyForTesting(nonce: List<int>.filled(12, 1)),
            opener: family.leo,
            sender: family.aritz,
            creator: null,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
          'texto cifrado': (
            bundle: bundle.copyForTesting(
              ciphertext: [
                bundle.ciphertext[0] ^ 1,
                ...bundle.ciphertext.sublist(1),
              ],
            ),
            opener: family.leo,
            sender: family.aritz,
            creator: null,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
          'etiqueta': (
            bundle: bundle.copyForTesting(
              ciphertext: [
                ...bundle.ciphertext.sublist(0, 47),
                bundle.ciphertext[47] ^ 1,
              ],
            ),
            opener: family.leo,
            sender: family.aritz,
            creator: null,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
          'firma': (
            bundle: bundle.copyForTesting(
              signature: [
                bundle.signature[0] ^ 1,
                ...bundle.signature.sublist(1),
              ],
            ),
            opener: family.leo,
            sender: family.aritz,
            creator: null,
            syncId: kSync,
            plain: sig,
            resigned: gcm,
          ),
        };
    for (final e in cases.entries) {
      final c = e.value;
      await expectLater(
        openAs(c.bundle, phone: c.opener, syncId: c.syncId),
        _fails(c.plain),
        reason: e.key,
      );
      if (e.key == 'firma') continue;
      final resigned = await c.bundle.resignForTesting(
        sender: c.sender.keys,
        recipientAgreementKey: c.opener.keys.publicKeys.agreement,
        creator: c.creator?.keys,
      );
      await expectLater(
        openAs(resigned, phone: c.opener, syncId: c.syncId),
        _fails(c.resigned),
        reason: '${e.key} (firmado de nuevo)',
      );
    }
    // El de verdad sigue abriendo, y firmarlo de nuevo sin cambios también.
    expect((await openAs(bundle)).kid, candidate.kid);
    final same = await bundle.resignForTesting(
      sender: family.aritz.keys,
      recipientAgreementKey: family.leo.keys.publicKeys.agreement,
    );
    expect((await openAs(same)).kid, candidate.kid);
  });

  test('firmado por el emisor con un secreto que no da el kid, o de '
      'ceros: rechazado', () async {
    await expectLater(
      openAs(await forged(candidate, secret: secretOf(100))),
      _fails('el kid no es el de la clave'),
    );
    await expectLater(
      openAs(await forged(candidate, secret: List<int>.filled(32, 0))),
      _fails('secreto no válido'),
    );
  });

  test('M3: firma del creador falsa, o candidata atribuida a otro', () async {
    final bogus = FamilyCandidate.signed(
      listId: kListId,
      syncId: kSync,
      epochNumber: candidate.epochNumber,
      epochContext: candidate.epochContext,
      creator: candidate.creator,
      creatorRecord: candidate.creatorRecord,
      audience: candidate.audience,
      secret: secretOf(50),
      creatorSignature: List<int>.filled(64, 3),
    );
    await expectLater(
      openAs(await forLeo(bogus)),
      _fails('firma del creador no válida'),
    );
    // Aritz acuña una candidata a nombre de Nora (firma él).
    final framed = await candidateFor(
      family,
      family.view,
      seed: 51,
      creator: 'nora-phone',
      signer: family.aritz,
    );
    await expectLater(
      openAs(await forLeo(framed)),
      _fails('firma del creador no válida'),
    );
    // La de verdad de Nora, repartida por Aritz, sí entra.
    final byNora = await candidateFor(family, family.viewOf(family.nora));
    expect((await openAs(await forLeo(byNora))).creator, 'nora-phone');
  });

  group('R1: el creador es el nodo enlazado desde mi ancla', () {
    test('Nora publica una ficha autofirmada con el id de Aritz: sus '
        'candidatas no entran y Leo conserva las de Aritz', () async {
      final leoView = family.viewOf(family.leo);
      bool sealableLeo(FamilyCandidate c) =>
          c.sealableIn(leoView, syncId: kSync);
      var ring = FamilyKeyring.empty;
      for (var i = 0; i < kMaxIdleCandidatesPerCreator; i++) {
        final c = await candidateFor(
          family,
          family.view,
          seed: 20 + i,
          context: sha256Hex([200 + i]),
        );
        final b = await forLeo(c);
        ring = ring.withReceivedCandidate(
          await openAs(b),
          from: b.fromDevice,
          fromRecord: b.senderRecord,
          sealable: sealableLeo,
        );
      }
      final fakeKeys = await DeviceKeys.fromSeedsForTesting(
        agreementSeed: List<int>.filled(32, 91),
        signingSeed: List<int>.filled(32, 92),
        serviceCredential: List<int>.filled(32, 93),
      );
      final fake = await DeviceRecord.create(
        keys: fakeKeys,
        listId: kListId,
        deviceId: 'aritz-phone',
        personId: 'aritz',
      );
      final poisoned = await family.registry.withRecord(fake);
      final leoPoisoned = await family.leo.viewOf(poisoned);
      final noraPoisoned = await family.nora.viewOf(poisoned);
      // La ficha falsa no tiene aval: Aritz sigue siendo el de siempre.
      expect(
        leoPoisoned.member('aritz-phone')!.recordDigest,
        digestOf(family.aritz),
      );
      expect(
        leoPoisoned.linkedSigningKey('aritz-phone'),
        family.aritz.keys.publicKeys.signing,
      );
      final impostor = await FamilyCandidate.create(
        listId: kListId,
        syncId: kSync,
        epochNumber: 1,
        epochContext: sha256Hex([1]),
        creator: 'aritz-phone',
        creatorRecord: fake.digest,
        audience: [
          AudienceMember('aritz-phone', fake.digest),
          AudienceMember('leo-phone', leoPoisoned.self.recordDigest),
          AudienceMember('nora-phone', noraPoisoned.self.recordDigest),
        ],
        secret: secretOf(1),
        creatorKeys: fakeKeys,
      );
      final b = await FamilyKeyBundle.seal(
        sender: family.nora.keys,
        view: noraPoisoned,
        syncId: kSync,
        toDevice: 'leo-phone',
        candidate: impostor,
      );
      await expectLater(
        openAs(b, view: leoPoisoned, registry: poisoned),
        _fails('el creador no es un móvil del registro'),
      );
      expect(ring.length, kMaxIdleCandidatesPerCreator);
    });

    test('creadores fantasma (fichas sin aval) no entran', () async {
      var registry = family.registry;
      for (var g = 0; g < 3; g++) {
        final keys = await DeviceKeys.fromSeedsForTesting(
          agreementSeed: List<int>.filled(32, 120 + g),
          signingSeed: List<int>.filled(32, 140 + g),
          serviceCredential: List<int>.filled(32, 160 + g),
        );
        final id = 'zz-ghost-$g';
        final record = await DeviceRecord.create(
          keys: keys,
          listId: kListId,
          deviceId: id,
          personId: null,
        );
        registry = await registry.withRecord(record);
        final leo = await family.leo.viewOf(registry);
        final nora = await family.nora.viewOf(registry);
        expect(leo.linkedSigningKey(id), isNull);
        final c = await FamilyCandidate.create(
          listId: kListId,
          syncId: kSync,
          epochNumber: 1,
          epochContext: sha256Hex([g, 7]),
          creator: id,
          creatorRecord: record.digest,
          audience: [
            AudienceMember('leo-phone', leo.self.recordDigest),
            AudienceMember('nora-phone', nora.self.recordDigest),
            AudienceMember(id, record.digest),
          ],
          secret: secretOf(1 + g),
          creatorKeys: keys,
        );
        final b = await FamilyKeyBundle.seal(
          sender: family.nora.keys,
          view: nora,
          syncId: kSync,
          toDevice: 'leo-phone',
          candidate: c,
        );
        await expectLater(
          openAs(b, view: leo, registry: registry),
          _fails('el creador no es un móvil del registro'),
        );
      }
    });

    test('una candidata de Nora de antes de su revocación, reenviada por '
        'Aritz, se abre y no se poda', () async {
      final noraKey = await FamilyCandidate.generate(
        family.viewOf(family.nora),
        keys: family.nora.keys,
        syncId: kSync,
      );
      final relay = await forLeo(noraKey);
      final registry = await withRevoked(family, family.nora);
      final leoRevoked = await family.leo.viewOf(registry);
      expect(leoRevoked.revoked, contains('nora-phone'));
      expect(
        leoRevoked.linkedSigningKey('nora-phone'),
        family.nora.keys.publicKeys.signing,
      );
      final got = await openAs(relay, view: leoRevoked, registry: registry);
      expect(got.kid, noraKey.kid);
      final ring = FamilyKeyring.empty.withReceivedCandidate(
        got,
        from: relay.fromDevice,
        fromRecord: relay.senderRecord,
        sealable: (c) => c.sealableIn(leoRevoked, syncId: kSync),
      );
      expect(ring.pruneRevoked(leoRevoked).entry(got.kid), isNotNull);
    });
  });

  test('M2: audiencia con fichas que el registro no conoce', () async {
    final ghost = AudienceMember(
      'zz-ghost',
      encodeBase64Url(List<int>.filled(32, 9)),
    );
    final withGhost = await candidateFor(
      family,
      family.view,
      seed: 60,
      epoch: 4000000000,
      context: 'f' * 64,
      audience: [...candidate.audience, ghost],
    );
    await expectLater(
      openAs(await forged(withGhost)),
      _fails('la audiencia tiene fichas que el registro no conoce'),
    );
    // Un id real con la ficha de otro.
    final swapped = await candidateFor(
      family,
      family.view,
      seed: 61,
      audience: [
        for (final m in candidate.audience)
          m.deviceId == 'nora-phone'
              ? AudienceMember('nora-phone', digestOf(family.leo))
              : m,
      ],
    );
    await expectLater(
      openAs(await forged(swapped)),
      _fails('la audiencia tiene fichas que el registro no conoce'),
    );
    // Una audiencia ampliada con alguien del registro abre, pero no sella.
    final w = await withWeb(family);
    final wider = await candidateFor(
      family,
      family.view,
      seed: 62,
      audience: [
        ...candidate.audience,
        AudienceMember('web-1', w.root.member('web-1')!.recordDigest),
      ],
    );
    final got = await openAs(await forged(wider), registry: w.registry);
    expect(got.sealableIn(family.viewOf(family.leo), syncId: kSync), isFalse);
  });

  test('una web no emite, ni crea; el paquete para la web se abre con la '
      'vista de su raíz', () async {
    final w = await withWeb(family);
    final c = await candidateFor(family, w.root);
    expect(c.audienceOf('web-1'), isNotNull);
    // Firmado por la web: Leo lo rechaza.
    final fromWeb = await FamilyKeyBundle.sealForTesting(
      sender: w.web.keys,
      candidate: c,
      fromDevice: 'web-1',
      senderRecord: w.root.member('web-1')!.recordDigest,
      toDevice: 'leo-phone',
      recipientRecord: w.root.member('leo-phone')!.recordDigest,
      recipientAgreementKey: family.leo.keys.publicKeys.agreement,
    );
    await expectLater(
      openAs(fromWeb, view: w.leo, registry: w.registry),
      _fails('el emisor no es de la familia'),
    );
    // La web no reparte con la vista de su raíz.
    await expectLater(
      FamilyKeyBundle.seal(
        sender: w.web.keys,
        view: w.root,
        syncId: kSync,
        toDevice: 'leo-phone',
        candidate: c,
      ),
      _fails('ese dispositivo no puede recibir esta clave común'),
    );
    // Un paquete creado por la web (creador web) no vale.
    final webCreated = await candidateFor(
      family,
      w.root,
      seed: 70,
      creator: 'web-1',
      signer: w.web,
    );
    await expectLater(
      openAs(
        await FamilyKeyBundle.seal(
          sender: family.aritz.keys,
          view: w.root,
          syncId: kSync,
          toDevice: 'leo-phone',
          candidate: webCreated,
        ),
        view: w.leo,
        registry: w.registry,
      ),
      _fails('el creador no es un móvil del registro'),
    );
    // Aritz reparte a la web; la web lo abre con la vista de su raíz.
    final toWeb = await FamilyKeyBundle.seal(
      sender: family.aritz.keys,
      view: w.root,
      syncId: kSync,
      toDevice: 'web-1',
      candidate: c,
    );
    final opened = await toWeb.open(
      mine: w.web.keys,
      view: w.root,
      registry: w.registry,
      syncId: kSync,
    );
    expect(opened.kid, c.kid);
    // Leo no lo abre: no tiene las claves de la web.
    await expectLater(
      openAs(toWeb, view: w.leo, registry: w.registry),
      _fails('las claves no son las de la ficha'),
    );
  });

  test('emisor pendiente; fichas viejas tras seq 2; selfApproved en '
      'false', () async {
    // Leo cambia de persona: pendiente hasta que alguien lo apruebe.
    final leo2 = await family.leo.record(person: 'aritz', seq: 2);
    var registry = await family.registry.withRecord(leo2);
    final aritzView = await family.aritz.viewOf(registry);
    final leoPending = await family.leo.viewOf(registry);
    expect(leoPending.selfApproved, isFalse);
    await expectLater(
      FamilyKeyBundle.seal(
        sender: family.leo.keys,
        view: leoPending,
        syncId: kSync,
        toDevice: 'aritz-phone',
        candidate: await candidateFor(family, family.viewOf(family.leo)),
      ),
      _fails('ese dispositivo no puede recibir esta clave común'),
    );
    final fromPending = await forged(
      await candidateFor(family, family.viewOf(family.leo)),
      from: family.leo,
      to: family.aritz,
    );
    await expectLater(
      openAs(
        fromPending,
        phone: family.aritz,
        view: aritzView,
        registry: registry,
      ),
      _fails('el emisor no es de la familia'),
    );
    // Aritz aprueba la ficha nueva: el paquete viejo para Leo (tr de seq 1)
    // ya no vale, y uno viejo de Leo (fr de seq 1) tampoco.
    registry = await registry.withVouch(
      await Vouch.create(
        keys: family.aritz.keys,
        voucher: await family.aritz.record(),
        record: leo2,
      ),
    );
    final leoApproved = await family.leo.viewOf(registry);
    expect(leoApproved.member('leo-phone')!.recordDigest, leo2.digest);
    await expectLater(
      openAs(await forLeo(), view: leoApproved, registry: registry),
      _fails('el paquete es de otro estado del registro'),
    );
    final oldFromLeo = await forged(
      await candidateFor(family, family.viewOf(family.leo)),
      from: family.leo,
      to: family.aritz,
    );
    await expectLater(
      openAs(
        oldFromLeo,
        phone: family.aritz,
        view: await family.aritz.viewOf(registry),
        registry: registry,
      ),
      _fails('el paquete es de otro estado del registro'),
    );
  });

  test('firmado por otro (aunque sea de la familia): rechazado', () async {
    await expectLater(
      openAs(await forged(candidate, signer: family.nora)),
      _fails('firma no válida'),
    );
  });

  test('generación y lista equivocadas', () async {
    await expectLater(
      openAs(await forLeo(), syncId: kOtherSync),
      _fails('el paquete es de otra lista'),
    );
    await expectLater(
      FamilyKeyBundle.seal(
        sender: family.aritz.keys,
        view: family.view,
        syncId: kSync,
        toDevice: family.leo.id,
        candidate: await candidateFor(family, family.view, syncId: kOtherSync),
      ),
      _fails('ese dispositivo no puede recibir esta clave común'),
    );
  });

  test('B5 y ámbito: claves exactas, v3 y v4 no se confunden, enteros y '
      'base64url estrictos', () async {
    final json = (await forLeo()).toJson();
    expect(
      () => FamilyKeyBundle.fromJson({...json, 's': 'surprise:nora'}),
      _fails('no es un paquete de la clave común'),
    );
    expect(
      () => FamilyKeyBundle.fromJson({...json, 'zz': 'no firmado'}),
      _fails('paquete con campos desconocidos'),
    );
    expect(
      () => FamilyKeyBundle.fromJson({...json}..remove('cs')),
      _fails('paquete con campos desconocidos'),
    );
    expect(
      () => FamilyKeyBundle.fromJson({...json, 'e': 1.0}),
      _fails('paquete no válido'),
    );
    final epk = json['epk']! as String;
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final alt =
        epk.substring(0, epk.length - 1) +
        alphabet[alphabet.indexOf(epk[epk.length - 1]) ^ 1];
    expect(
      () => FamilyKeyBundle.fromJson({...json, 'epk': alt}),
      _fails('paquete no válido'),
    );
    expect(() => KeyBundle.fromJson(json), _fails('versión no soportada'));
    final v3 = await KeyBundle.sealSurpriseKey(
      sender: family.aritz.keys,
      view: family.view,
      toDevice: family.leo.id,
      key: family.key,
    );
    expect(
      () => FamilyKeyBundle.fromJson(v3.toJson()),
      _fails('versión no soportada'),
    );
    expect(FamilyKeyBundle.isV4(json), isTrue);
    expect(FamilyKeyBundle.isV4(v3.toJson()), isFalse);
  });

  test('X25519 de orden bajo: no se sella para esa clave, y una efímera de '
      'orden bajo bien firmada no abre', () async {
    for (final bad in lowOrder.take(5)) {
      await expectLater(
        FamilyKeyBundle.sealForTesting(
          sender: family.aritz.keys,
          candidate: candidate,
          fromDevice: family.aritz.id,
          senderRecord: digestOf(family.aritz),
          toDevice: family.leo.id,
          recipientRecord: digestOf(family.leo),
          recipientAgreementKey: bad,
        ),
        _fails('clave pública del destinatario no válida'),
        reason: encodeBase64Url(bad),
      );
    }
    final bundle = await forLeo();
    for (final bad in lowOrder) {
      final signed = await bundle
          .copyForTesting(ephemeralPublicKey: bad)
          .resignForTesting(
            sender: family.aritz.keys,
            recipientAgreementKey: family.leo.keys.publicKeys.agreement,
          );
      // Las siete primeras (reducidas, o >= p sin el bit alto) dan secreto
      // de ceros. Las que tienen el bit alto no son de orden bajo según el
      // RFC 7748 (que lo enmascara): dan otro secreto y falla el GCM.
      await expectLater(
        openAs(signed),
        _fails(
          lowOrder.indexOf(bad) < 7
              ? 'clave efímera no válida'
              : 'el paquete no se puede abrir',
        ),
        reason: encodeBase64Url(bad),
      );
    }
  });

  test('quién reparte y a quién: solo dentro de la audiencia, con sus '
      'claves, y nunca a un revocado', () async {
    final withoutLeo = await candidateFor(
      family,
      family.view,
      audience: candidate.audience.where((m) => m.deviceId != 'leo-phone'),
    );
    await expectLater(
      forLeo(withoutLeo),
      _fails('ese dispositivo no puede recibir esta clave común'),
    );
    await expectLater(
      forged(withoutLeo),
      _fails('cabecera del paquete no válida'),
    );
    await expectLater(
      FamilyKeyBundle.seal(
        sender: family.nora.keys,
        view: family.view,
        syncId: kSync,
        toDevice: family.leo.id,
        candidate: candidate,
      ),
      _fails('ese dispositivo no puede recibir esta clave común'),
    );
    final registry = await withRevoked(family, family.nora);
    final leoAfter = await family.leo.viewOf(registry);
    final fromNora = await forged(
      await candidateFor(family, family.viewOf(family.nora)),
      from: family.nora,
    );
    await expectLater(
      openAs(fromNora, view: leoAfter, registry: registry),
      _fails('el emisor no es de la familia'),
    );
    await expectLater(
      FamilyKeyBundle.seal(
        sender: family.aritz.keys,
        view: await family.aritz.viewOf(registry),
        syncId: kSync,
        toDevice: family.nora.id,
        candidate: candidate,
      ),
      _fails('ese dispositivo no puede recibir esta clave común'),
    );
    // Abrir no decide si sirve para sellar.
    expect(
      (await openAs(await forLeo(), view: leoAfter, registry: registry)).kid,
      candidate.kid,
    );
  });

  group('M2: inundaciones del llavero de Leo', () {
    test('16 paquetes de un emisor en el contexto actual: la buena de '
        'otro emisor y la propia entran', () async {
      final noraView = family.viewOf(family.nora);
      final leoView = family.viewOf(family.leo);
      final pair = EpochDescriptor.ofView(
        noraView,
        syncId: kSync,
      ).members.where((m) => m.deviceId != 'aritz-phone').toList();
      bool sealable(FamilyCandidate c) => c.sealableIn(leoView, syncId: kSync);
      var ring = FamilyKeyring.empty;
      for (var i = 0; i < 16; i++) {
        final junk = await candidateFor(
          family,
          noraView,
          seed: 10 + i,
          audience: pair,
        );
        final b = await FamilyKeyBundle.seal(
          sender: family.nora.keys,
          view: noraView,
          syncId: kSync,
          toDevice: 'leo-phone',
          candidate: junk,
        );
        ring = ring.withReceivedCandidate(
          await openAs(b),
          from: b.fromDevice,
          fromRecord: b.senderRecord,
          sealable: sealable,
        );
      }
      expect(ring.length, kMaxIdleCandidatesPerCreator);
      expect(ring.forSealingIn(leoView, syncId: kSync), isNull);
      final good = await FamilyCandidate.generate(
        family.view,
        keys: family.aritz.keys,
        syncId: kSync,
      );
      final b = await forLeo(good);
      ring = ring.withReceivedCandidate(
        await openAs(b),
        from: b.fromDevice,
        fromRecord: b.senderRecord,
        sealable: sealable,
      );
      expect(ring.forSealingIn(leoView, syncId: kSync)!.kid, good.kid);
      final mine = await FamilyCandidate.generate(
        leoView,
        keys: family.leo.keys,
        syncId: kSync,
      );
      expect(ring.withOwnCandidate(mine).entry(mine.kid), isNotNull);
    });

    test('64 contextos inventados de un emisor: la buena de otro emisor '
        'entra y sella', () async {
      final leoView = family.viewOf(family.leo);
      bool sealable(FamilyCandidate c) => c.sealableIn(leoView, syncId: kSync);
      var ring = FamilyKeyring.empty;
      for (var i = 0; i < 64; i++) {
        final junk = await candidateFor(
          family,
          family.view,
          seed: 100 + i,
          epoch: 1 + i,
          context: sha256Hex([i]),
        );
        final b = await forLeo(junk);
        ring = ring.withReceivedCandidate(
          await openAs(b),
          from: b.fromDevice,
          fromRecord: b.senderRecord,
          sealable: sealable,
        );
      }
      expect(ring.length, kMaxIdleCandidatesPerCreator);
      final noraView = family.viewOf(family.nora);
      final good = await FamilyCandidate.generate(
        noraView,
        keys: family.nora.keys,
        syncId: kSync,
      );
      final b = await FamilyKeyBundle.seal(
        sender: family.nora.keys,
        view: noraView,
        syncId: kSync,
        toDevice: 'leo-phone',
        candidate: good,
      );
      ring = ring.withReceivedCandidate(
        await openAs(b),
        from: b.fromDevice,
        fromRecord: b.senderRecord,
        sealable: sealable,
      );
      expect(ring.forSealingIn(leoView, syncId: kSync)!.kid, good.kid);
    });
  });
}

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
