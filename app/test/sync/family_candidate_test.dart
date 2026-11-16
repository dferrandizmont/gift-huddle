// Candidatas de la clave común, contexto de época y llavero común (ADR 0005,
// lote B1, con los arreglos de la revisión de seguridad).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart' show encodeBase64Url;
import 'package:regalos/core/sync/family_candidate.dart';

import 'family_key_harness.dart';
import 'protected_harness.dart';

Matcher _fails(String message) => throwsA(
  isA<FamilyKeyException>().having((e) => e.message, 'message', message),
);

void main() {
  late Family family;
  setUp(() async => family = await Family.create());

  bool Function(FamilyCandidate) sealable(RegistryView view) =>
      (FamilyCandidate c) => c.sealableIn(view, syncId: kSync);

  group('contexto de época', () {
    test('es estable, va por la vista, no lleva el número de época y liga '
        'generación, fichas y revocados', () async {
      final a = EpochDescriptor.ofView(family.view, syncId: kSync);
      expect(a.context, epochContextOf(family.view, syncId: kSync));
      expect(a.context, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(a.toJson().keys, unorderedEquals(['l', 'm', 'r', 'sid', 'v']));
      expect(a.members.map((m) => m.deviceId), [
        'aritz-phone',
        'leo-phone',
        'nora-phone',
      ]);
      expect(
        epochContextOf(family.viewOf(family.leo), syncId: kSync),
        a.context,
      );
      expect(epochContextOf(family.view, syncId: kOtherSync), isNot(a.context));
      final back = EpochDescriptor.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Object,
      );
      expect(back.context, a.context);
    });

    test('el mismo número de época con registros distintos da contextos '
        'distintos', () async {
      final viewAb = await family.aritz.viewOf(
        await registryOf([family.aritz, family.leo]),
      );
      final viewAn = await family.aritz.viewOf(
        await registryOf([family.aritz, family.nora]),
      );
      expect(viewAb.epoch, viewAn.epoch);
      expect(
        epochContextOf(viewAb, syncId: kSync),
        isNot(epochContextOf(viewAn, syncId: kSync)),
      );
      final revoked = await family.aritz.viewOf(
        await withRevoked(family, family.nora),
      );
      expect(
        epochContextOf(revoked, syncId: kSync),
        isNot(epochContextOf(family.view, syncId: kSync)),
      );
    });

    test('M1: el revocado publica fichas con seq mayor: sube el número, el '
        'contexto no cambia y la candidata sigue sellable', () async {
      var registry = await withRevoked(family, family.nora);
      final before = await family.aritz.viewOf(registry);
      final c = await FamilyCandidate.generate(
        before,
        keys: family.aritz.keys,
        syncId: kSync,
      );
      for (var seq = 2; seq <= 3; seq++) {
        registry = await registry.withRecord(
          await family.nora.record(person: 'leo', seq: seq),
        );
        final after = await family.aritz.viewOf(registry);
        expect(after.epoch, greaterThan(before.epoch), reason: 'seq $seq');
        expect(
          epochContextOf(after, syncId: kSync),
          epochContextOf(before, syncId: kSync),
        );
        expect(c.sealableIn(after, syncId: kSync), isTrue);
        expect(
          FamilyKeyring.empty
              .withOwnCandidate(c)
              .forSealingIn(after, syncId: kSync)!
              .kid,
          c.kid,
        );
      }
    });

    test('M1: el pendiente cambia de persona dos veces: la candidata hecha '
        'tras el primer cambio sigue sellable', () async {
      var registry = await family.registry.withRecord(
        await family.leo.record(person: 'aritz', seq: 2),
      );
      final first = await family.aritz.viewOf(registry);
      expect(first.members, isNot(contains('leo-phone')));
      final c = await FamilyCandidate.generate(
        first,
        keys: family.aritz.keys,
        syncId: kSync,
      );
      registry = await registry.withRecord(
        await family.leo.record(person: 'nora', seq: 3),
      );
      final second = await family.aritz.viewOf(registry);
      expect(second.epoch, greaterThan(first.epoch));
      expect(c.sealableIn(second, syncId: kSync), isTrue);
      // Leo, pendiente, no puede crear (selfApproved en false).
      final leo = await family.leo.viewOf(registry);
      expect(leo.selfApproved, isFalse);
      await expectLater(
        FamilyCandidate.generate(leo, keys: family.leo.keys, syncId: kSync),
        _fails('este dispositivo no puede crear la clave común'),
      );
    });

    test('bajada de época: el número no decide nada', () async {
      // Una candidata del contexto actual con un número mayor (como si la
      // época hubiera bajado después de crearla) sigue sellando.
      final high = await candidateFor(
        family,
        family.view,
        seed: 1,
        epoch: family.view.epoch + 5,
      );
      expect(high.sealableIn(family.view, syncId: kSync), isTrue);
      expect(
        FamilyKeyring.empty
            .withOwnCandidate(high)
            .forSealingIn(family.view, syncId: kSync)!
            .kid,
        high.kid,
      );
    });

    test('un descriptor manipulado o no canónico no se lee', () {
      final json = EpochDescriptor.ofView(family.view, syncId: kSync).toJson();
      for (final bad in <Map<String, Object?>>[
        {...json, 'v': 1},
        {...json, 'e': 1},
        {...json, 'sid': 'corto'},
        {...json, 'm': (json['m']! as List).reversed.toList()},
        {...json, 'm': <Object?>[]},
        {
          ...json,
          'r': ['b', 'a'],
        },
      ]) {
        expect(
          () => EpochDescriptor.fromJson(bad),
          throwsA(isA<FamilyKeyException>()),
        );
      }
    });
  });

  group('candidata', () {
    test('generate: aleatoria, firmada por el creador y sellable', () async {
      final a = await FamilyCandidate.generate(
        family.view,
        keys: family.aritz.keys,
        syncId: kSync,
      );
      final b = await FamilyCandidate.generate(
        family.view,
        keys: family.aritz.keys,
        syncId: kSync,
      );
      expect(a.secret, isNot(b.secret));
      expect(a.kid, isNot(b.kid));
      expect(a.kid, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(a.creator, 'aritz-phone');
      expect(a.audienceOf('aritz-phone')!.recordDigest, a.creatorRecord);
      expect(await a.verifyCreator(family.aritz.keys.publicKeys.signing), true);
      expect(await a.verifyCreator(family.leo.keys.publicKeys.signing), false);
      expect(a.sealableIn(family.view, syncId: kSync), isTrue);
      expect(a.sealableIn(family.view, syncId: kOtherSync), isFalse);
      expect(a.toString(), isNot(contains(encodeBase64Url(a.secret))));
    });

    test('B1: solo crea un móvil activo con sus propias claves; ni una web '
        'con la vista de su raíz, ni un revocado', () async {
      await expectLater(
        FamilyCandidate.generate(
          family.view,
          keys: family.nora.keys,
          syncId: kSync,
        ),
        _fails('este dispositivo no puede crear la clave común'),
      );
      final w = await withWeb(family);
      await expectLater(
        FamilyCandidate.generate(w.root, keys: w.web.keys, syncId: kSync),
        _fails('este dispositivo no puede crear la clave común'),
      );
      final noraView = await family.nora.viewOf(
        await withRevoked(family, family.nora),
      );
      expect(noraView.revokedByOthers, isTrue);
      await expectLater(
        FamilyCandidate.generate(
          noraView,
          keys: family.nora.keys,
          syncId: kSync,
        ),
        _fails('este dispositivo no puede crear la clave común'),
      );
    });

    test('el kid liga el secreto con todos los campos', () async {
      final base = await candidateFor(family, family.view);
      final variants = [
        await candidateFor(family, family.view, seed: 8),
        await candidateFor(family, family.view, syncId: kOtherSync),
        await candidateFor(family, family.view, epoch: 2),
        await candidateFor(family, family.view, context: 'a' * 64),
        await candidateFor(
          family,
          family.view,
          audience: base.audience.where((m) => m.deviceId != 'nora-phone'),
        ),
        await candidateFor(family, family.viewOf(family.leo)),
      ];
      for (final other in variants) {
        expect(other.kid, isNot(base.kid));
      }
      expect((await candidateFor(family, family.view)).kid, base.kid);
    });

    test('no vale: secreto de ceros, creador fuera de la audiencia, '
        'audiencia repetida o vacía, contexto en mayúsculas', () async {
      final base = await candidateFor(family, family.view);
      Future<FamilyCandidate> make({
        List<int>? secret,
        String? creatorRecord,
        Iterable<AudienceMember>? audience,
        String? context,
      }) async => FamilyCandidate.create(
        listId: base.listId,
        syncId: base.syncId,
        epochNumber: base.epochNumber,
        epochContext: context ?? base.epochContext,
        creator: base.creator,
        creatorRecord: creatorRecord ?? base.creatorRecord,
        audience: audience ?? base.audience,
        secret: secret ?? base.secret,
        creatorKeys: family.aritz.keys,
      );
      final bad = throwsA(isA<FamilyKeyException>());
      await expectLater(make(secret: List<int>.filled(32, 0)), bad);
      await expectLater(make(secret: List<int>.filled(31, 1)), bad);
      await expectLater(
        make(creatorRecord: base.audience[1].recordDigest),
        bad,
      );
      await expectLater(
        make(audience: base.audience.where((m) => m.deviceId != 'aritz-phone')),
        bad,
      );
      await expectLater(
        make(audience: [...base.audience, base.audience[1]]),
        bad,
      );
      await expectLater(make(audience: const []), bad);
      await expectLater(make(context: 'A' * 64), bad);
    });

    test('un resumen en base64url no canónico no vale', () {
      final d = family.view.member('nora-phone')!.recordDigest;
      const alphabet =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
      final last = alphabet.indexOf(d[d.length - 1]);
      final alt = d.substring(0, d.length - 1) + alphabet[last ^ 1];
      expect(isRecordDigest(d), isTrue);
      expect(isRecordDigest(alt), isFalse);
      expect(
        () => AudienceMember('nora-phone', alt),
        _fails('miembro de la audiencia no válido'),
      );
    });

    test(
      'audienceMatches: falta uno, sobra uno, otro id u otra ficha',
      () async {
        final view = family.view;
        final all = EpochDescriptor.ofView(view, syncId: kSync).members;
        final ghost = AudienceMember(
          'zz-ghost',
          encodeBase64Url(List<int>.filled(32, 9)),
        );
        final leoDigest = view.member('leo-phone')!.recordDigest;
        final cases = <String, List<AudienceMember>>{
          'falta Nora': all.where((m) => m.deviceId != 'nora-phone').toList(),
          'sobra uno': [...all, ghost],
          'otro id': [
            for (final m in all) m.deviceId == 'nora-phone' ? ghost : m,
          ],
          'otra ficha': [
            for (final m in all)
              m.deviceId == 'nora-phone'
                  ? AudienceMember('nora-phone', leoDigest)
                  : m,
          ],
        };
        for (final e in cases.entries) {
          final c = await candidateFor(family, view, audience: e.value);
          expect(c.audienceMatches(view), isFalse, reason: e.key);
          expect(c.sealableIn(view, syncId: kSync), isFalse, reason: e.key);
        }
        expect((await candidateFor(family, view)).audienceMatches(view), true);
      },
    );

    test('ida y vuelta por JSON; kid, claves o enteros que no cuadran no '
        'se leen', () async {
      final c = await candidateFor(family, family.view);
      final back = FamilyCandidate.fromJson(
        jsonDecode(jsonEncode(c.toJson())) as Object,
      );
      expect(back.kid, c.kid);
      expect(back.secret, c.secret);
      expect(back.audience, c.audience);
      expect(
        await back.verifyCreator(family.aritz.keys.publicKeys.signing),
        true,
      );
      final json = c.toJson();
      for (final bad in <Map<String, Object?>>[
        {...json, 'kid': 'b' * 64},
        {...json, 'e': 9},
        {...json, 'e': 1.0},
        {...json, 's': 'surprise:nora'},
        {...json, 'zz': 1},
        {...json}..remove('cs'),
      ]) {
        expect(
          () => FamilyCandidate.fromJson(bad),
          throwsA(isA<FamilyKeyException>()),
        );
      }
      // Firma del creador cambiada: se lee (no hay registro) pero no vale.
      final forged = FamilyCandidate.fromJson({
        ...json,
        'cs': encodeBase64Url(List<int>.filled(64, 1)),
      });
      expect(
        await forged.verifyCreator(family.aritz.keys.publicKeys.signing),
        false,
      );
    });
  });

  group('llavero común', () {
    test('dos candidatas de la misma época y distinto kid: sella con la '
        'menor válida y abre con cualquiera', () async {
      final a = await candidateFor(family, family.view, seed: 1);
      final b = await candidateFor(family, family.view, seed: 2);
      final low = a.kid.compareTo(b.kid) < 0 ? a : b;
      final high = identical(low, a) ? b : a;
      for (final ring in [
        FamilyKeyring.empty.withOwnCandidate(high).withOwnCandidate(low),
        FamilyKeyring.empty.withOwnCandidate(low).withOwnCandidate(high),
      ]) {
        expect(ring.forSealingIn(family.view, syncId: kSync)!.kid, low.kid);
        expect(
          ring
              .forSealingIn(
                family.view,
                syncId: kSync,
                extra: (c) => c.kid != low.kid,
              )!
              .kid,
          high.kid,
        );
        for (final c in [a, b]) {
          expect(
            ring
                .forOpening(
                  listId: c.listId,
                  syncId: c.syncId,
                  epochNumber: c.epochNumber,
                  epochContext: c.epochContext,
                  kid: c.kid,
                )!
                .secret,
            c.secret,
          );
        }
        expect(identical(ring.withOwnCandidate(a), ring), isTrue);
      }
    });

    test('una candidata cuya audiencia incluye a un revocado no sella pero '
        'abre', () async {
      final revokedView = await family.aritz.viewOf(
        await withRevoked(family, family.nora),
      );
      final nora = (await candidateFor(
        family,
        family.view,
      )).audienceOf('nora-phone')!;
      final leaky = await candidateFor(
        family,
        revokedView,
        seed: 1,
        audience: [
          ...EpochDescriptor.ofView(revokedView, syncId: kSync).members,
          nora,
        ],
      );
      final ring = FamilyKeyring.empty.withOwnCandidate(leaky);
      expect(ring.forSealingIn(revokedView, syncId: kSync), isNull);
      expect(
        ring.forOpening(
          listId: kListId,
          syncId: kSync,
          epochNumber: leaky.epochNumber,
          epochContext: leaky.epochContext,
          kid: leaky.kid,
        ),
        isNotNull,
      );
      final safe = await candidateFor(family, revokedView, seed: 99);
      expect(
        ring
            .withOwnCandidate(safe)
            .forSealingIn(revokedView, syncId: kSync)!
            .kid,
        safe.kid,
      );
      final before = await candidateFor(family, family.view, seed: 3);
      expect(
        FamilyKeyring.empty
            .withOwnCandidate(before)
            .forSealingIn(revokedView, syncId: kSync),
        isNull,
      );
    });

    test('contextos distintos no se mezclan', () async {
      final ctxA = await candidateFor(
        family,
        family.view,
        seed: 1,
        context: 'a' * 64,
      );
      final ctxB = await candidateFor(
        family,
        family.view,
        seed: 2,
        context: 'b' * 64,
      );
      final ring = FamilyKeyring.empty
          .withOwnCandidate(ctxA)
          .withOwnCandidate(ctxB);
      expect(ring.candidatesOf('a' * 64).map((c) => c.kid), [ctxA.kid]);
      for (final (ctx, want) in [('a' * 64, ctxA), ('b' * 64, ctxB)]) {
        expect(
          ring.forSealing(epochContext: ctx, valid: (_) => true)!.kid,
          want.kid,
        );
      }
      expect(
        ring.forOpening(
          listId: kListId,
          syncId: kSync,
          epochNumber: 1,
          epochContext: 'a' * 64,
          kid: ctxB.kid,
        ),
        isNull,
      );
      expect(
        ring.forOpening(
          listId: kListId,
          syncId: kOtherSync,
          epochNumber: 1,
          epochContext: 'a' * 64,
          kid: ctxA.kid,
        ),
        isNull,
      );
      expect(ring.forSealingIn(family.view, syncId: kSync), isNull);
    });

    test('histórica y comprometida abren y no sellan', () async {
      final legacy = await candidateFor(family, family.view, seed: 1);
      final bad = await candidateFor(family, family.view, seed: 2);
      var ring = FamilyKeyring.empty
          .withOwnCandidate(legacy, historical: true)
          .withOwnCandidate(bad)
          .markCompromised(bad.kid);
      expect(ring.forSealingIn(family.view, syncId: kSync), isNull);
      for (final c in [legacy, bad]) {
        expect(
          ring.forOpening(
            listId: kListId,
            syncId: kSync,
            epochNumber: c.epochNumber,
            epochContext: c.epochContext,
            kid: c.kid,
          ),
          isNotNull,
        );
      }
      ring = ring.withOwnCandidate(legacy);
      expect(ring.entry(legacy.kid)!.historical, isTrue);
      final fresh = await candidateFor(family, family.view, seed: 3);
      ring = ring.withOwnCandidate(fresh);
      expect(ring.forSealingIn(family.view, syncId: kSync)!.kid, fresh.kid);
      ring = ring.markHistorical(fresh.kid);
      expect(ring.forSealingIn(family.view, syncId: kSync), isNull);
    });

    test('una referenciada no se desaloja; tope de referencias', () async {
      final c = await candidateFor(family, family.view, seed: 1);
      final other = await candidateFor(family, family.view, seed: 2);
      var ring = FamilyKeyring.empty
          .withOwnCandidate(c)
          .withOwnCandidate(other)
          .withReference(c.kid, 'common:pending')
          .withReference(c.kid, 'outbox:leo-phone');
      expect(
        () => ring.without(c.kid),
        throwsA(isA<FamilyKeyReferencedException>()),
      );
      expect(ring.prune((_) => false).candidates.map((x) => x.kid), [c.kid]);
      ring = ring
          .withoutReference(c.kid, 'common:pending')
          .withoutReference(c.kid, 'outbox:leo-phone');
      expect(ring.without(c.kid).candidates.map((x) => x.kid), [other.kid]);
      expect(
        () => ring.withReference('f' * 64, 'x'),
        _fails('esa clave común no está en el llavero'),
      );
      expect(
        () => ring.withReference(c.kid, 'con espacio'),
        _fails('referencia no válida'),
      );
      var full = ring;
      for (var i = 0; i < kMaxCandidateReferences; i++) {
        full = full.withReference(c.kid, 'r$i');
      }
      expect(
        () => full.withReference(c.kid, 'una-mas'),
        _fails('demasiadas referencias'),
      );
      // Una repetida no cuenta.
      expect(identical(full.withReference(c.kid, 'r0'), full), isTrue);
    });

    test('M2: cupo por creador para las recibidas que no sellan; la buena '
        'de otro creador y las propias entran', () async {
      final noraView = family.viewOf(family.nora);
      final leoView = family.viewOf(family.leo);
      final pair = EpochDescriptor.ofView(
        noraView,
        syncId: kSync,
      ).members.where((m) => m.deviceId != 'aritz-phone').toList();
      var ring = FamilyKeyring.empty;
      for (var i = 0; i < 16; i++) {
        ring = ring.withReceivedCandidate(
          await candidateFor(family, noraView, seed: 10 + i, audience: pair),
          from: 'nora-phone',
          fromRecord: noraView.self.recordDigest,
          sealable: sealable(leoView),
        );
      }
      expect(ring.length, kMaxIdleCandidatesPerCreator);
      final good = await candidateFor(family, family.view, seed: 200);
      ring = ring.withReceivedCandidate(
        good,
        from: 'aritz-phone',
        fromRecord: family.view.self.recordDigest,
        sealable: sealable(leoView),
      );
      expect(ring.forSealingIn(leoView, syncId: kSync)!.kid, good.kid);
      final mine = await FamilyCandidate.generate(
        leoView,
        keys: family.leo.keys,
        syncId: kSync,
      );
      ring = ring.withOwnCandidate(mine);
      expect(ring.entry(mine.kid)!.own, isTrue);
      expect(ring.entry(good.kid)!.senders.single.deviceId, 'aritz-phone');
      // Recibirla de otro emisor suma la procedencia.
      ring = ring.withReceivedCandidate(
        good,
        from: 'nora-phone',
        fromRecord: noraView.self.recordDigest,
        sealable: sealable(leoView),
      );
      expect(ring.entry(good.kid)!.senders.map((s) => s.deviceId), [
        'aritz-phone',
        'nora-phone',
      ]);
    });

    test('M2: tope total de las que no sellan; el creador que más tiene '
        'cede', () async {
      var ring = FamilyKeyring.empty;
      final leoView = family.viewOf(family.leo);
      for (var k = 0; k < 10; k++) {
        final id = 'creador-$k';
        final digest = encodeBase64Url(List<int>.filled(32, k + 1));
        for (var i = 0; i < kMaxIdleCandidatesPerCreator; i++) {
          final c = await FamilyCandidate.create(
            listId: kListId,
            syncId: kSync,
            epochNumber: 1,
            epochContext: sha256Hex([k, i]),
            creator: id,
            creatorRecord: digest,
            audience: [AudienceMember(id, digest)],
            secret: secretOf(k * 10 + i + 1),
            creatorKeys: family.nora.keys,
          );
          ring = ring.withReceivedCandidate(
            c,
            from: 'nora-phone',
            fromRecord: family.view.member('nora-phone')!.recordDigest,
            sealable: sealable(leoView),
          );
        }
      }
      expect(ring.length, kMaxIdleFamilyCandidates);
    });

    test('tope duro con propias: contrapresión, sin desalojar', () async {
      var ring = FamilyKeyring.empty;
      for (var i = 0; i < kMaxFamilyCandidates; i++) {
        ring = ring.withOwnCandidate(
          await candidateFor(family, family.view, seed: i + 1, epoch: i + 1),
        );
      }
      final extra = await candidateFor(
        family,
        family.view,
        seed: 1,
        epoch: 999,
      );
      expect(
        () => ring.withOwnCandidate(extra),
        throwsA(isA<FamilyKeyringFullException>()),
      );
      expect(ring.length, kMaxFamilyCandidates);
    });

    test('R2: poda solo si el creador y todos los emisores están revocados, '
        'sin referencias y sin buscarla', () async {
      final revokedView = await family.leo.viewOf(
        await withRevoked(family, family.nora),
      );
      final noraView = family.viewOf(family.nora);
      final noraRecord = noraView.self.recordDigest;
      final aritzRecord = family.view.self.recordDigest;
      // De Nora, reenviada por Aritz (honrado): se queda.
      final relayedByAritz = await candidateFor(family, noraView, seed: 1);
      // De Aritz, reenviada por Nora: el creador no está revocado, se queda.
      final byAritz = await candidateFor(family, family.view, seed: 2);
      // De Nora y solo por Nora: fuera.
      final onlyNora = await candidateFor(family, noraView, seed: 3);
      // Igual, pero con referencia o buscada: se quedan.
      final referenced = await candidateFor(family, noraView, seed: 4);
      final wanted = await candidateFor(family, noraView, seed: 5);
      final own = await candidateFor(
        family,
        family.viewOf(family.leo),
        seed: 6,
      );
      bool never(FamilyCandidate _) => false;
      FamilyKeyring add(
        FamilyKeyring r,
        FamilyCandidate c,
        String from,
        String rec,
      ) => r.withReceivedCandidate(
        c,
        from: from,
        fromRecord: rec,
        sealable: never,
      );
      var ring = FamilyKeyring.empty;
      ring = add(ring, relayedByAritz, 'aritz-phone', aritzRecord);
      ring = add(ring, byAritz, 'nora-phone', noraRecord);
      ring = add(ring, onlyNora, 'nora-phone', noraRecord);
      ring = add(ring, referenced, 'nora-phone', noraRecord);
      ring = add(ring, wanted, 'nora-phone', noraRecord);
      ring = ring
          .withReference(referenced.kid, 'common:pending')
          .withOwnCandidate(own);
      final pruned = ring.pruneRevoked(revokedView, wanted: {wanted.kid});
      expect(pruned.candidates.map((c) => c.kid).toSet(), {
        relayedByAritz.kid,
        byAritz.kid,
        referenced.kid,
        wanted.kid,
        own.kid,
      });
      // Sin buscarla, la buscada también sale.
      expect(ring.pruneRevoked(revokedView).entry(wanted.kid), isNull);
    });

    test('R3: una buscada de kid alto entra aunque su creador tenga el '
        'cupo lleno', () async {
      final leoView = family.viewOf(family.leo);
      bool sealableLeo(FamilyCandidate c) =>
          c.sealableIn(leoView, syncId: kSync);
      var ring = FamilyKeyring.empty;
      final kids = <String>[];
      for (var i = 0; i < kMaxIdleCandidatesPerCreator; i++) {
        final c = await candidateFor(
          family,
          family.view,
          seed: 20 + i,
          context: sha256Hex([200 + i]),
        );
        ring = ring.withReceivedCandidate(
          c,
          from: 'aritz-phone',
          fromRecord: family.view.self.recordDigest,
          sealable: sealableLeo,
        );
        kids.add(c.kid);
      }
      kids.sort();
      FamilyCandidate? high;
      for (var seed = 100; high == null; seed++) {
        final c = await candidateFor(
          family,
          family.view,
          seed: seed,
          context: sha256Hex([77]),
        );
        if (c.kid.compareTo(kids.last) > 0) high = c;
      }
      FamilyKeyring arrive(Set<String> wanted) => ring.withReceivedCandidate(
        high!,
        from: 'aritz-phone',
        fromRecord: family.view.self.recordDigest,
        sealable: sealableLeo,
        wanted: wanted,
      );
      // Sin decir que se busca, se desaloja al llegar.
      expect(arrive(const {}).entry(high.kid), isNull);
      final got = arrive({high.kid});
      expect(got.entry(high.kid), isNotNull);
      expect(got.length, kMaxIdleCandidatesPerCreator + 1);
      // Y sigue ahí al llegar más del mismo creador mientras se busque.
      final more = await candidateFor(
        family,
        family.view,
        seed: 300,
        context: sha256Hex([78]),
      );
      expect(
        got
            .withReceivedCandidate(
              more,
              from: 'aritz-phone',
              fromRecord: family.view.self.recordDigest,
              sealable: sealableLeo,
              wanted: {high.kid},
            )
            .entry(high.kid),
        isNotNull,
      );
    });

    test('R4: 256 sellables de un solo creador no llenan el llavero: entran '
        'la buena de otro y la propia', () async {
      final leoView = family.viewOf(family.leo);
      final noraView = family.viewOf(family.nora);
      bool sealableLeo(FamilyCandidate c) =>
          c.sealableIn(leoView, syncId: kSync);
      var ring = FamilyKeyring.empty;
      for (var i = 0; i < kMaxFamilyCandidates; i++) {
        final c = await candidateFor(family, noraView, seed: i + 1);
        expect(sealableLeo(c), isTrue);
        ring = ring.withReceivedCandidate(
          c,
          from: 'nora-phone',
          fromRecord: noraView.self.recordDigest,
          sealable: sealableLeo,
        );
      }
      expect(ring.length, kMaxIdleCandidatesPerCreator);
      // Se quedan las de kid menor (las que se usan para sellar).
      final kept = ring.candidates.map((c) => c.kid).toList();
      expect(ring.forSealingIn(leoView, syncId: kSync)!.kid, kept.first);
      final good = await FamilyCandidate.generate(
        family.view,
        keys: family.aritz.keys,
        syncId: kSync,
      );
      ring = ring.withReceivedCandidate(
        good,
        from: 'aritz-phone',
        fromRecord: family.view.self.recordDigest,
        sealable: sealableLeo,
      );
      expect(ring.entry(good.kid), isNotNull);
      final mine = await FamilyCandidate.generate(
        leoView,
        keys: family.leo.keys,
        syncId: kSync,
      );
      expect(ring.withOwnCandidate(mine).entry(mine.kid), isNotNull);
    });

    test('ida y vuelta JSON estable con procedencia; lo manipulado no se '
        'lee', () async {
      final a = await candidateFor(family, family.view, seed: 1);
      final b = await candidateFor(family, family.view, seed: 2);
      FamilyKeyring build(bool reversed) {
        var ring = FamilyKeyring.empty;
        final steps = <FamilyKeyring Function(FamilyKeyring)>[
          (r) => r.withReceivedCandidate(
            b,
            from: 'leo-phone',
            fromRecord: family.view.member('leo-phone')!.recordDigest,
            sealable: sealable(family.view),
          ),
          (r) => r.withOwnCandidate(a, historical: true),
        ];
        for (final step in reversed ? steps.reversed : steps) {
          ring = step(ring);
        }
        return ring.withReference(b.kid, 'common:pending');
      }

      final ring = build(false);
      final text = jsonEncode(ring.toJson());
      final back = FamilyKeyring.fromJson(jsonDecode(text) as Object);
      expect(jsonEncode(back.toJson()), text);
      expect(jsonEncode(build(true).toJson()), text);
      expect(back.entry(a.kid)!.historical, isTrue);
      expect(back.entry(a.kid)!.own, isTrue);
      expect(back.entry(b.kid)!.own, isFalse);
      expect(back.entry(b.kid)!.senders.single.deviceId, 'leo-phone');
      expect(back.entry(b.kid)!.references, {'common:pending'});
      expect(back.forSealingIn(family.view, syncId: kSync)!.secret, b.secret);

      final json = jsonDecode(text) as Map<String, Object?>;
      final keys = json['keys']! as List;
      final bad = throwsA(isA<FamilyKeyException>());
      Map<String, Object?> entryWith(Map<String, Object?> change) => {
        ...json,
        'keys': [
          {...(keys.first as Map<String, Object?>), ...change},
        ],
      };
      expect(() => FamilyKeyring.fromJson({...json, 'v': 2}), bad);
      expect(() => FamilyKeyring.fromJson({...json, 'zz': 1}), bad);
      expect(
        () => FamilyKeyring.fromJson({
          ...json,
          'keys': [...keys, keys.first],
        }),
        bad,
      );
      expect(() => FamilyKeyring.fromJson(entryWith({'h': 'sí'})), bad);
      expect(() => FamilyKeyring.fromJson(entryWith({'zz': true})), bad);
      final noOrigin = Map<String, Object?>.from(
        keys.firstWhere((e) => (e as Map)['o'] != true) as Map,
      )..remove('f');
      expect(
        () => FamilyKeyring.fromJson({
          ...json,
          'keys': [noOrigin],
        }),
        bad,
      );
      final tampered = Map<String, Object?>.from(keys.first as Map);
      tampered['c'] = {
        ...(tampered['c']! as Map<String, Object?>),
        'kid': '0' * 64,
      };
      expect(
        () => FamilyKeyring.fromJson({
          ...json,
          'keys': [tampered],
        }),
        bad,
      );
    });
  });
}
