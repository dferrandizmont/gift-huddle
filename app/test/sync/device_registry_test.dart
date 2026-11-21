// Registro firmado de móviles (ADR 0004, fase 2a; requisitos 1 a 6 de
// la revisión de seguridad de la fase 1 (segunda pasada)).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';

import 'protected_harness.dart';

const _people = {'aritz', 'leo', 'nora'};

Future<DeviceRecord> _record(Phone p, {String? person, int seq = 1}) =>
    DeviceRecord.create(
      keys: p.keys,
      listId: kListId,
      deviceId: p.id,
      personId: person ?? p.self,
      seq: seq,
    );

/// [by] avala [record] desde su ficha [as] (por defecto, la primera).
Future<Vouch> _vouch(Phone by, DeviceRecord record, {DeviceRecord? as}) async =>
    Vouch.create(
      keys: by.keys,
      voucher: as ?? await _record(by),
      record: record,
    );

/// [by] revoca a [target] desde su ficha [as] (por defecto, la primera).
Future<Revocation> _revoke(Phone by, String target, {DeviceRecord? as}) async =>
    Revocation.create(
      keys: by.keys,
      by: as ?? await _record(by),
      deviceId: target,
    );

/// [registry] con los avales de [pairs] (quien avala, ficha avalada).
Future<DeviceRegistry> _vouched(
  DeviceRegistry registry,
  List<(Phone, DeviceRecord)> pairs,
) async {
  var out = registry;
  for (final (by, record) in pairs) {
    out = await out.withVouch(await _vouch(by, record));
  }
  return out;
}

Future<RegistryView> _view(
  DeviceRegistry registry,
  Phone me, {
  Set<String> people = _people,
}) => registry.viewFor(
  me: me.id,
  mySigningKey: me.keys.publicKeys.signing,
  livePeople: people,
);

void main() {
  late Phone aritz;
  late Phone leo;
  late Phone nora;
  late DeviceRecord rAritz;
  late DeviceRecord rLeo;
  late DeviceRecord rNora;

  /// Los tres móviles, avalados entre sí (emparejados y confirmados).
  Future<DeviceRegistry> family() async {
    var registry = DeviceRegistry.empty(kListId);
    for (final r in [rAritz, rLeo, rNora]) {
      registry = await registry.withRecord(r);
    }
    return _vouched(registry, [
      (aritz, rLeo),
      (aritz, rNora),
      (leo, rAritz),
      (leo, rNora),
      (nora, rAritz),
      (nora, rLeo),
    ]);
  }

  setUp(() async {
    aritz = await Phone.create('aritz-phone', 'aritz', 1);
    leo = await Phone.create('leo-phone', 'leo', 2);
    nora = await Phone.create('nora-phone', 'nora', 3);
    rAritz = await _record(aritz);
    rLeo = await _record(leo);
    rNora = await _record(nora);
  });

  group('fichas, avales y revocaciones', () {
    test('la ficha va firmada por el propio móvil; ida y vuelta', () async {
      final back = DeviceRecord.fromJson(
        jsonDecode(jsonEncode(rAritz.toJson())),
      );
      expect(await back.verify(), isTrue);
      expect(back.digest, rAritz.digest);
      expect(back.personId, 'aritz');
    });

    test('cambiar la persona, las claves o el seq de una ficha rompe la '
        'firma y el registro no la acepta', () async {
      for (final change in <String, Object?>{
        'p': 'leo',
        'n': 2,
        'x': rLeo.toJson()['x'],
        'd': 'leo-phone',
      }.entries) {
        final forged = DeviceRecord.fromJson({
          ...rAritz.toJson(),
          change.key: change.value,
        });
        expect(await forged.verify(), isFalse, reason: change.key);
        await expectLater(
          DeviceRegistry.empty(kListId).withRecord(forged),
          throwsA(isA<RegistryException>()),
        );
      }
    });

    test('nadie se avala ni se revoca a sí mismo', () async {
      await expectLater(
        _vouch(aritz, rAritz),
        throwsA(isA<RegistryException>()),
      );
      await expectLater(
        _revoke(aritz, aritz.id),
        throwsA(isA<RegistryException>()),
      );
      final own = (await _vouch(leo, rAritz)).toJson()..['by'] = aritz.id;
      expect(() => Vouch.fromJson(own), throwsA(isA<RegistryException>()));
    });

    test('formato roto o de otra lista: rechazado', () async {
      expect(
        () => DeviceRecord.fromJson({...rAritz.toJson(), 'v': 1}),
        throwsA(isA<RegistryException>()),
      );
      expect(
        () => DeviceRecord.fromJson({...rAritz.toJson(), 'p': 'no vale'}),
        throwsA(isA<RegistryException>()),
      );
      final other = await DeviceRecord.create(
        keys: aritz.keys,
        listId: 'otra-lista',
        deviceId: aritz.id,
        personId: 'aritz',
      );
      await expectLater(
        DeviceRegistry.empty(kListId).withRecord(other),
        throwsA(isA<RegistryException>()),
      );
    });
  });

  group('quién es de la familia', () {
    test('un móvil solo: no está emparejado y solo se ve a sí mismo', () async {
      final registry = await DeviceRegistry.empty(kListId).withRecord(rAritz);
      final view = await _view(registry, aritz);
      expect(view.paired, isFalse);
      expect(view.members, ['aritz-phone']);
      expect(view.epoch, 1);
      expect(view.myPerson, 'aritz');
    });

    test('un móvil que no tiene su ficha en el registro no puede leerlo', () {
      expect(
        _view(DeviceRegistry.empty(kListId), aritz),
        throwsA(isA<RegistryException>()),
      );
    });

    test(
      'tres móviles avalados entre sí: todos activos y emparejados',
      () async {
        final registry = await family();
        for (final me in [aritz, leo, nora]) {
          final view = await _view(registry, me);
          expect(view.paired, isTrue);
          expect(view.members, ['aritz-phone', 'leo-phone', 'nora-phone']);
          expect(view.pending, isEmpty);
          expect(view.member('leo-phone')!.personId, 'leo');
          expect(
            view.member('leo-phone')!.signingKey,
            leo.keys.publicKeys.signing,
          );
          expect(view.member('otro'), isNull);
        }
      },
    );

    test('una ficha sin aval de alguien de la familia no entra, y un aval '
        'con firma falsa o de un desconocido no cuenta', () async {
      final intruder = await Phone.create('intruso', 'leo', 9);
      final rIntruder = await _record(intruder);
      final accomplice = await Phone.create('complice', 'aritz', 8);
      var registry = await (await family()).withRecord(rIntruder);
      registry = await registry.withRecord(await _record(accomplice));
      // El cómplice (que nadie conoce) avala al intruso.
      registry = await registry.withVouch(await _vouch(accomplice, rIntruder));
      // Un aval «de Leo» con la firma de otro ni siquiera entra.
      await expectLater(
        registry.withVouch(
          Vouch.fromJson({
            ...(await _vouch(accomplice, rIntruder)).toJson(),
            'by': 'leo-phone',
          }),
        ),
        throwsA(isA<RegistryException>()),
      );
      final view = await _view(registry, aritz);
      expect(view.member('intruso'), isNull);
      expect(view.member('complice'), isNull);
      expect(view.entitled('intruso', 'nora'), isNull);
      expect(view.pending, isEmpty);
      expect(view.epoch, 1);
    });

    test('el emparejamiento en persona son dos avales: sin el mío, el otro '
        'no es de mi familia', () async {
      var registry = DeviceRegistry.empty(kListId);
      registry = await registry.withRecord(rAritz);
      registry = await registry.withRecord(rLeo);
      registry = await registry.withVouch(await _vouch(leo, rAritz));
      expect((await _view(registry, aritz)).paired, isFalse);
      expect((await _view(registry, leo)).paired, isTrue);
      registry = await registry.withVouch(await _vouch(aritz, rLeo));
      expect((await _view(registry, aritz)).paired, isTrue);
    });
  });

  group('derecho a las sorpresas (req. 2, 3 y 6)', () {
    test('Aritz y Leo, avalados entre sí, tienen derecho a las de Nora; '
        'Nora no', () async {
      final view = await _view(await family(), aritz);
      expect(view.entitledDevices('nora'), ['aritz-phone', 'leo-phone']);
      expect(view.selfEntitled('nora'), isTrue);
      expect(view.selfEntitled('aritz'), isFalse);
      expect(view.entitled('nora-phone', 'nora'), isNull);
      expect(view.entitled('nora-phone', 'leo'), isNotNull);
    });

    test('ataque: Nora registra un segundo móvil suyo como «leo» y lo avala. '
        'Es de la familia, pero no consigue derecho a sus sorpresas', () async {
      final fake = await Phone.create('nora-2', 'leo', 7);
      final rFake = await _record(fake);
      var registry = await (await family()).withRecord(rFake);
      registry = await registry.withVouch(await _vouch(nora, rFake));
      for (final me in [aritz, leo]) {
        final view = await _view(registry, me);
        expect(view.member('nora-2'), isNotNull);
        expect(view.entitled('nora-2', 'nora'), isNull);
        expect(view.entitledDevices('nora'), ['aritz-phone', 'leo-phone']);
      }
      // Hallazgo 1: que después Aritz revoque a cualquiera no le da derecho
      // (antes, revocar avalaba a todos los activos que veía).
      final change = await revokeDevice(
        registry: registry,
        view: await _view(registry, aritz),
        myKeys: aritz.keys,
        deviceId: 'leo-phone',
      );
      final after = await _view(change.registry, aritz);
      expect(after.entitled('nora-2', 'nora'), isNull);
      expect(after.entitledDevices('nora'), ['aritz-phone']);
      expect(change.orphans, isEmpty);
    });

    test(
      'ataque en cadena: el falso de Nora avala a otro falso: tampoco',
      () async {
        final fake1 = await Phone.create('nora-2', 'leo', 7);
        final fake2 = await Phone.create('nora-3', 'aritz', 6);
        final r1 = await _record(fake1);
        final r2 = await _record(fake2);
        var registry = await (await family()).withRecord(r1);
        registry = await registry.withRecord(r2);
        registry = await _vouched(registry, [
          (nora, r1),
          (fake1, r2),
          (fake2, r1),
        ]);
        final view = await _view(registry, aritz);
        expect(view.entitled('nora-2', 'nora'), isNull);
        expect(view.entitled('nora-3', 'nora'), isNull);
      },
    );

    test(
      'ataque: el propio móvil de Nora se declara «leo» (ficha nueva). '
      'Queda pendiente; aunque lo avale su otro móvil, sin derecho',
      () async {
        final asLeo = await _record(nora, person: 'leo', seq: 2);
        var registry = await (await family()).withRecord(asLeo);
        var view = await _view(registry, aritz);
        expect(view.member('nora-phone'), isNull);
        expect(view.pending.single.deviceId, 'nora-phone');
        expect(view.entitled('nora-phone', 'nora'), isNull);
        final second = await Phone.create('nora-2', 'nora', 7);
        final rSecond = await _record(second);
        registry = await _vouched(await registry.withRecord(rSecond), [
          (nora, rSecond),
          (second, asLeo),
        ]);
        view = await _view(registry, aritz);
        expect(view.entitled('nora-phone', 'nora'), isNull);
      },
    );

    test('sin aval de alguien con derecho no hay derecho: Leo, aprobado solo '
        'por Nora, no cuenta para Aritz hasta que Aritz lo confirma', () async {
      var registry = DeviceRegistry.empty(kListId);
      for (final r in [rAritz, rLeo, rNora]) {
        registry = await registry.withRecord(r);
      }
      // Nora creó la familia y emparejó a los dos.
      registry = await _vouched(registry, [
        (nora, rAritz),
        (aritz, rNora),
        (nora, rLeo),
        (leo, rNora),
      ]);
      var view = await _view(registry, aritz);
      expect(view.member('leo-phone'), isNotNull);
      expect(view.entitled('leo-phone', 'nora'), isNull);
      expect(view.entitledDevices('nora'), ['aritz-phone']);
      final change = await approveDevice(
        registry: registry,
        view: view,
        myKeys: aritz.keys,
        record: rLeo,
      );
      expect(change.rotates, isFalse);
      view = await _view(change.registry, aritz);
      expect(view.entitled('leo-phone', 'nora'), isNotNull);
    });

    test('la persona tiene que existir y ser un id válido; un móvil sin '
        'persona no tiene derecho a nada', () async {
      final registry = await family();
      final noLeo = await _view(registry, aritz, people: {'aritz', 'nora'});
      expect(noLeo.entitled('leo-phone', 'nora'), isNull);
      expect(noLeo.member('leo-phone'), isNotNull);
      final noNora = await _view(registry, aritz, people: {'aritz', 'leo'});
      expect(noNora.entitledDevices('nora'), isEmpty);
      final nobody = await Phone.create('sin-persona', null, 5);
      final rNobody = await _record(nobody);
      final withNobody = await _vouched(await registry.withRecord(rNobody), [
        (aritz, rNobody),
        (nobody, rAritz),
      ]);
      expect(
        (await _view(withNobody, aritz)).entitled('sin-persona', 'nora'),
        isNull,
      );
      expect((await _view(withNobody, nobody)).selfEntitled('nora'), isFalse);
    });

    test('ataque (hallazgo 5): el móvil de Nora avala a un falso «aritz», '
        'pasa a ser «de Leo» y lo aprueban: el aval que dio siendo de Nora no '
        'cuenta para sus sorpresas', () async {
      final fake = await Phone.create('nora-2', 'aritz', 7);
      final rFake = await _record(fake);
      var registry = await (await family()).withRecord(rFake);
      registry = await _vouched(registry, [(nora, rFake), (fake, rNora)]);
      final changed = await changePerson(
        registry: registry,
        view: await _view(registry, nora),
        myKeys: nora.keys,
        personId: 'leo',
      );
      final asLeo = changed.registry.recordByDigest(
        (await _view(changed.registry, nora)).self.recordDigest,
      )!;
      // Aritz lo aprueba (lo engañan, o de verdad ahora es de Leo).
      final approved = await approveDevice(
        registry: changed.registry,
        view: await _view(changed.registry, aritz),
        myKeys: aritz.keys,
        record: asLeo,
      );
      final view = await _view(approved.registry, aritz);
      expect(view.entitled('nora-phone', 'nora'), isNotNull);
      expect(view.member('nora-2'), isNotNull);
      expect(view.entitled('nora-2', 'nora'), isNull);
      // Lo que avale desde su ficha nueva sí cuenta: eso lo decidió quien
      // aprobó el cambio (límite que la interfaz tiene que explicar).
      final again = await approved.registry.withVouch(
        await _vouch(nora, rFake, as: asLeo),
      );
      expect((await _view(again, aritz)).entitled('nora-2', 'nora'), isNotNull);
    });

    test('el móvil de Nora, que solo reenvía, ve como escritores a los '
        'activos que no son de Nora', () async {
      final view = await _view(await family(), nora);
      expect(view.selfEntitled('nora'), isFalse);
      expect(view.entitledDevices('nora'), ['aritz-phone', 'leo-phone']);
      expect(view.entitled('nora-phone', 'nora'), isNull);
    });
  });

  group('confirmador posible para pedir protección', () {
    late Phone unassigned;
    late DeviceRegistry pair;

    setUp(() async {
      unassigned = await Phone.create('8t', null, 5);
      pair = await registryOf([unassigned, nora]);
    });

    Future<ProtectionRequestBlock?> blocked(
      DeviceRegistry registry,
      Phone requester, {
      Set<String> people = _people,
    }) async => protectionRequestBlock(
      registry: registry,
      localView: await _view(registry, requester, people: people),
      personId: 'nora',
    );

    test('8T sin persona y Nora necesitan un móvil de otra persona', () async {
      for (final requester in [unassigned, nora]) {
        expect(
          await blocked(pair, requester),
          ProtectionRequestBlock.noConfirmer,
        );
      }
      final registry = await registryOf([unassigned, nora, aritz]);
      final view = await _view(registry, unassigned);
      expect(view.entitledDevices('nora'), isEmpty);
      expect(await blocked(registry, unassigned), isNull);
      expect(await blocked(registry, nora), isNull);
    });

    test('el propio móvil con derecho basta', () async {
      final registry = await DeviceRegistry.empty(kListId).withRecord(rAritz);
      expect(await blocked(registry, aritz), isNull);
    });

    test('rechaza una vista de otra instantánea de la misma lista', () async {
      final registry = await registryOf([unassigned, nora, aritz]);
      final oldView = await _view(registry, nora);
      expect(pair.recordByDigest(oldView.self.recordDigest), isNotNull);
      expect(
        await protectionRequestBlock(
          registry: pair,
          localView: oldView,
          personId: 'nora',
        ),
        ProtectionRequestBlock.registryUnavailable,
      );
    });

    test(
      'reutiliza las vistas de candidatos y no cuenta las que fallan',
      () async {
        final registry = await registryOf([unassigned, nora, aritz]);
        final view = await _view(registry, unassigned);
        Future<ProtectionRequestBlock?> check(
          Map<String, Future<RegistryView>> memo,
        ) => protectionRequestBlock(
          registry: registry,
          localView: view,
          personId: 'nora',
          candidateViews: memo,
        );
        final views = <String, Future<RegistryView>>{};
        expect(await check(views), isNull);
        expect(views.keys, contains(aritz.id));
        final first = views[aritz.id];
        expect(await check(views), isNull);
        expect(views[aritz.id], same(first));

        // A candidate whose view cannot be built does not count.
        final broken = Future<RegistryView>.error(
          const RegistryException('vista rota'),
        )..ignore();
        expect(
          await check({aritz.id: broken}),
          ProtectionRequestBlock.noConfirmer,
        );
      },
    );

    test(
      'una ficha pendiente no cuenta aunque figure activa para otro móvil',
      () async {
        var registry = await pair.withRecord(rAritz);
        registry = await registry.withVouch(await _vouch(nora, rAritz));
        final changed = await _record(aritz, person: 'leo', seq: 2);
        registry = await registry.withRecord(changed);
        expect((await _view(registry, nora)).pending.single.deviceId, aritz.id);
        expect(
          await blocked(registry, nora),
          ProtectionRequestBlock.noConfirmer,
        );

        registry = await registry.withVouch(await _vouch(nora, changed));
        expect((await _view(registry, nora)).member(aritz.id), isNotNull);
        expect((await _view(registry, aritz)).selfApproved, isFalse);
        expect(
          await blocked(registry, nora),
          ProtectionRequestBlock.noConfirmer,
        );
        expect(
          await blocked(registry, aritz),
          ProtectionRequestBlock.requesterPending,
        );

        registry = await registry.withVouch(
          await _vouch(aritz, rNora, as: changed),
        );
        expect(await blocked(registry, nora), isNull);
      },
    );

    test(
      'la persona del candidato y la destinataria deben estar vivas',
      () async {
        final registry = await registryOf([unassigned, nora, aritz]);
        expect(
          await blocked(registry, unassigned, people: {'nora'}),
          ProtectionRequestBlock.noConfirmer,
        );
        expect(
          await blocked(registry, unassigned, people: {'aritz'}),
          ProtectionRequestBlock.recipientUnavailable,
        );
      },
    );

    test('un navegador activo con persona no cuenta', () async {
      final web = await DeviceRecord.create(
        keys: aritz.keys,
        listId: kListId,
        deviceId: aritz.id,
        personId: 'aritz',
        kind: DeviceKind.web,
      );
      final registry = await (await pair.withRecord(web))
          .withVouch(await _vouch(nora, web));
      expect(
        (await _view(registry, nora)).member(aritz.id)?.kind,
        DeviceKind.web,
      );
      expect(await blocked(registry, nora), ProtectionRequestBlock.noConfirmer);
      expect(await blocked(registry, aritz), ProtectionRequestBlock.notMobile);
    });

    test(
      'ni un revocado ni un ambiguo cuentan como candidato o solicitante',
      () async {
        final registry = await registryOf([unassigned, nora, aritz]);
        final revoked = await registry.withRevocation(
          await _revoke(nora, aritz.id),
        );
        expect(
          await blocked(revoked, unassigned),
          ProtectionRequestBlock.noConfirmer,
        );
        expect(
          await blocked(revoked, aritz),
          ProtectionRequestBlock.requesterRevoked,
        );

        final impostor = await Phone.create(aritz.id, 'aritz', 9);
        final record = await _record(impostor);
        final ambiguous = await (await registry.withRecord(record))
            .withVouch(await _vouch(nora, record));
        expect(
          await blocked(ambiguous, unassigned),
          ProtectionRequestBlock.noConfirmer,
        );
        expect(
          await blocked(ambiguous, aritz),
          ProtectionRequestBlock.requesterAmbiguous,
        );
      },
    );

    test('un móvil huérfano tras una revocación no cuenta', () async {
      var registry = await registryOf([unassigned, nora, leo]);
      registry = await _vouched(await registry.withRecord(rAritz), [
        (leo, rAritz),
        (aritz, rLeo),
      ]);
      expect(await blocked(registry, unassigned), isNull);
      registry = await registry.withRevocation(await _revoke(nora, leo.id));
      final view = await _view(registry, unassigned);
      expect(view.everMembers, contains(aritz.id));
      expect(view.member(aritz.id), isNull);
      expect(
        await blocked(registry, unassigned),
        ProtectionRequestBlock.noConfirmer,
      );
    });
  });

  group('cambiar de persona (req. 4)', () {
    test(
      'exige aprobación y abre una época; los avales viejos no valen',
      () async {
        final registry = await family();
        final before = await _view(registry, leo);
        final change = await changePerson(
          registry: registry,
          view: before,
          myKeys: leo.keys,
          personId: 'nora',
        );
        expect(change.rotates, isTrue);
        // Para los demás, Leo queda pendiente y sin derecho a nada.
        var view = await _view(change.registry, aritz);
        expect(view.epoch, before.epoch + 1);
        expect(view.member('leo-phone'), isNull);
        expect(view.entitled('leo-phone', 'nora'), isNull);
        expect(view.entitled('leo-phone', 'aritz'), isNull);
        expect(view.pending.single.personId, 'nora');
        // Aritz lo aprueba: ahora es de Nora, sin derecho a las de Nora.
        final approved = await approveDevice(
          registry: change.registry,
          view: view,
          myKeys: aritz.keys,
          record: change.registry.recordByDigest(
            view.pending.single.recordDigest,
          )!,
        );
        view = await _view(approved.registry, aritz);
        expect(view.member('leo-phone')!.personId, 'nora');
        expect(view.entitled('leo-phone', 'nora'), isNull);
        expect(view.entitled('leo-phone', 'leo'), isNotNull);
        // Y él mismo ya no se cuenta con derecho a las de Nora.
        expect(
          (await _view(approved.registry, leo)).selfEntitled('nora'),
          isFalse,
        );
      },
    );

    test('cambiar de persona en el propio móvil no le da derecho a nada, ni '
        'a sus propios ojos, hasta que otro lo aprueba', () async {
      final registry = await family();
      expect((await _view(registry, aritz)).selfApproved, isTrue);
      // Aritz se cambia a «leo»: él mismo deja de contarse con derecho.
      final changed = await changePerson(
        registry: registry,
        view: await _view(registry, aritz),
        myKeys: aritz.keys,
        personId: 'leo',
      );
      var mine = await _view(changed.registry, aritz);
      expect(mine.myPerson, 'leo');
      expect(mine.selfApproved, isFalse);
      expect(mine.selfEntitled('nora'), isFalse);
      expect(mine.selfEntitled('aritz'), isFalse);
      // Leo aprueba la ficha nueva.
      final approved = await approveDevice(
        registry: changed.registry,
        view: await _view(changed.registry, leo),
        myKeys: leo.keys,
        record: changed.registry.recordByDigest(mine.self.recordDigest)!,
      );
      mine = await _view(approved.registry, aritz);
      expect(mine.selfEntitled('nora'), isTrue);
      expect(mine.selfEntitled('aritz'), isTrue);
      expect(mine.selfEntitled('leo'), isFalse);
      // Segunda revisión, N7: la aprobación vale mientras quien la dio sea
      // activo. Si se revoca al único que aprobó la ficha nueva, este móvil
      // vuelve a esperar aprobación (la interfaz avisa antes de revocarlo);
      // con otro activo que lo haya aprobado, no.
      final alone = await revokeDevice(
        registry: approved.registry,
        view: mine,
        myKeys: aritz.keys,
        deviceId: 'leo-phone',
      );
      mine = await _view(alone.registry, aritz);
      expect(mine.selfApproved, isFalse);
      expect(mine.selfEntitled('nora'), isFalse);
      final both = await approveDevice(
        registry: approved.registry,
        view: await _view(approved.registry, nora),
        myKeys: nora.keys,
        record: approved.registry.recordByDigest(mine.self.recordDigest)!,
      );
      final stillOne = await revokeDevice(
        registry: both.registry,
        view: await _view(both.registry, aritz),
        myKeys: aritz.keys,
        deviceId: 'leo-phone',
      );
      mine = await _view(stillOne.registry, aritz);
      expect(mine.selfApproved, isTrue);
      expect(mine.selfEntitled('nora'), isTrue);
      expect(mine.selfEntitled('leo'), isFalse);
    });

    test('el único móvil de la familia cuenta para sí mismo', () async {
      final registry = await DeviceRegistry.empty(kListId).withRecord(rAritz);
      final view = await _view(registry, aritz);
      expect(view.selfApproved, isTrue);
      expect(view.selfEntitled('nora'), isTrue);
      expect(view.selfEntitled('aritz'), isFalse);
    });

    test('hallazgo 7: el seq tiene tope, así que nadie infla la época sin '
        'límite', () async {
      var registry = await family();
      for (var seq = 2; seq <= kMaxDeviceSeq; seq++) {
        registry = (await changePerson(
          registry: registry,
          view: await _view(registry, leo),
          myKeys: leo.keys,
          personId: seq.isEven ? 'aritz' : 'leo',
        )).registry;
      }
      await expectLater(
        changePerson(
          registry: registry,
          view: await _view(registry, leo),
          myKeys: leo.keys,
          personId: 'nora',
        ),
        throwsA(isA<RegistryException>()),
      );
      expect(
        () => DeviceRecord.fromJson({...rLeo.toJson(), 'n': kMaxDeviceSeq + 1}),
        throwsA(isA<RegistryException>()),
      );
      expect((await _view(registry, aritz)).epoch, kMaxDeviceSeq);
    });

    test('no cambiar nada no abre época', () async {
      final registry = await family();
      final change = await changePerson(
        registry: registry,
        view: await _view(registry, leo),
        myKeys: leo.keys,
        personId: 'leo',
      );
      expect(change.rotates, isFalse);
      expect(change.registry.sameAs(registry), isTrue);
    });
  });

  group('revocar (req. 5)', () {
    test('el revocado resuelve a null, sube la época y no vuelve', () async {
      final registry = await family();
      final change = await revokeDevice(
        registry: registry,
        view: await _view(registry, aritz),
        myKeys: aritz.keys,
        deviceId: 'leo-phone',
      );
      expect(change.rotates, isTrue);
      for (final me in [aritz, nora]) {
        final view = await _view(change.registry, me);
        expect(view.epoch, 2);
        expect(view.member('leo-phone'), isNull);
        expect(view.entitled('leo-phone', 'nora'), isNull);
        expect(view.revoked, {'leo-phone'});
        expect(view.pending, isEmpty);
      }
      // Volver a avalarlo, o que publique una ficha nueva, no lo devuelve.
      var again = await change.registry.withVouch(await _vouch(nora, rLeo));
      final rLeo2 = await _record(leo, seq: 2);
      again = await _vouched(await again.withRecord(rLeo2), [(nora, rLeo2)]);
      final view = await _view(again, aritz);
      expect(view.member('leo-phone'), isNull);
      expect(view.epoch, greaterThan(2));
    });

    test('el revocado no acepta su revocación para decidir en quién confía, '
        'pero la ve', () async {
      final registry = await family();
      final change = await revokeDevice(
        registry: registry,
        view: await _view(registry, aritz),
        myKeys: aritz.keys,
        deviceId: 'leo-phone',
      );
      final view = await _view(change.registry, leo);
      expect(view.revokedByOthers, isTrue);
      expect(view.selfEntitled('nora'), isFalse);
      expect(view.members, contains('aritz-phone'));
    });

    test('lo que avala un revocado no entra, ni antes ni después', () async {
      final registry = await family();
      final thief = await Phone.create('ladron', 'leo', 9);
      final rThief = await _record(thief);
      var stolen = await _vouched(await registry.withRecord(rThief), [
        (leo, rThief),
      ]);
      // Aritz revoca a Leo viendo también al ladrón (antes la prueba usaba
      // la vista sin él, y así no se veía el aval automático: hallazgo 1).
      final before = await _view(stolen, aritz);
      expect(before.member('ladron'), isNotNull);
      final change = await revokeDevice(
        registry: stolen,
        view: before,
        myKeys: aritz.keys,
        deviceId: 'leo-phone',
      );
      stolen = change.registry;
      final view = await _view(stolen, aritz);
      expect(view.member('ladron'), isNull);
      expect(view.entitled('ladron', 'nora'), isNull);
      // El ladrón queda como huérfano: la interfaz pide confirmarlo o
      // revocarlo; nunca se avala solo.
      expect([for (final d in change.orphans) d.deviceId], ['ladron']);
    });

    test('una revocación de un desconocido sin ficha, o con firma falsa, no '
        'entra; la de un desconocido con ficha entra pero no cuenta', () async {
      final stranger = await Phone.create('intruso', 'leo', 9);
      final fromStranger = await _revoke(stranger, 'leo-phone');
      var registry = await family();
      for (final bad in [
        fromStranger,
        Revocation.fromJson({...fromStranger.toJson(), 'by': 'nora-phone'}),
      ]) {
        await expectLater(
          registry.withRevocation(bad),
          throwsA(isA<RegistryException>()),
        );
      }
      registry = await (await registry.withRecord(await _record(stranger)))
          .withRevocation(fromStranger);
      expect(registry.revocations, hasLength(1));
      final view = await _view(registry, aritz);
      expect(view.member('leo-phone'), isNotNull);
      expect(view.epoch, 1);
    });

    test('revocar al móvil que emparejó a los demás no avala a nadie: los '
        'que solo unía él quedan huérfanos hasta que se confirman', () async {
      var registry = DeviceRegistry.empty(kListId);
      for (final r in [rAritz, rLeo, rNora]) {
        registry = await registry.withRecord(r);
      }
      registry = await _vouched(registry, [
        (nora, rAritz),
        (aritz, rNora),
        (nora, rLeo),
        (leo, rNora),
      ]);
      final change = await revokeDevice(
        registry: registry,
        view: await _view(registry, aritz),
        myKeys: aritz.keys,
        deviceId: 'nora-phone',
      );
      var mine = await _view(change.registry, aritz);
      expect(mine.members, ['aritz-phone']);
      // Lo que solo cuelga del revocado ya no es pendiente (segunda
      // revisión, N1): sale en los huérfanos de quien revoca.
      expect(mine.pending, isEmpty);
      expect([for (final d in change.orphans) d.deviceId], ['leo-phone']);
      // Una persona confirma en la pantalla de Aritz que es el de Leo.
      final confirmed = await approveDevice(
        registry: change.registry,
        view: mine,
        myKeys: aritz.keys,
        record: change.registry.recordByDigest(
          change.orphans.single.recordDigest,
        )!,
      );
      mine = await _view(confirmed.registry, aritz);
      expect(mine.members, ['aritz-phone', 'leo-phone']);
      // Leo todavía no ha confirmado a Aritz: no es de su familia hasta que
      // lo apruebe (no hereda la confianza del revocado). Como Aritz solo
      // cuelga del revocado, no es un pendiente; sale como «desligado» que
      // ha avalado la ficha de Leo.
      var his = await _view(confirmed.registry, leo);
      expect(his.member('aritz-phone'), isNull);
      expect(his.pending, isEmpty);
      expect(his.detached.single.deviceId, 'aritz-phone');
      final approved = await approveDevice(
        registry: confirmed.registry,
        view: his,
        myKeys: leo.keys,
        record: rAritz,
      );
      his = await _view(approved.registry, leo);
      expect(his.members, ['aritz-phone', 'leo-phone']);
      expect(his.detached, isEmpty);
    });

    test('un móvil robado que revoca a todos no deja a los demás sin su '
        'propia familia: cada uno sigue confiando en sí mismo', () async {
      var registry = await family();
      for (final target in ['aritz-phone', 'nora-phone']) {
        registry = await registry.withRevocation(await _revoke(leo, target));
      }
      final view = await _view(registry, aritz);
      expect(view.revokedByOthers, isTrue);
      expect(view.members, ['aritz-phone', 'leo-phone']);
      expect(view.member('nora-phone'), isNull);
    });
  });

  group('suplantar un id', () {
    test('ataque: Nora publica una ficha con el id de Leo y otras claves y '
        'la avala: el id deja de resolverse, nadie firma como Leo', () async {
      final impostor = await Phone.create('leo-phone', 'leo', 9);
      final rImpostor = await _record(impostor, seq: 5);
      var registry = await (await family()).withRecord(rImpostor);
      registry = await registry.withVouch(await _vouch(nora, rImpostor));
      final view = await _view(registry, aritz);
      expect(view.member('leo-phone'), isNull);
      expect(view.entitled('leo-phone', 'nora'), isNull);
      expect(view.revoked, contains('leo-phone'));
    });

    test('una ficha con mi id y otras claves no me cambia a mí', () async {
      final impostor = await Phone.create('aritz-phone', 'nora', 9);
      final rImpostor = await _record(impostor, seq: 5);
      var registry = await (await family()).withRecord(rImpostor);
      registry = await registry.withVouch(await _vouch(nora, rImpostor));
      final view = await _view(registry, aritz);
      expect(view.myPerson, 'aritz');
      expect(view.self.signingKey, aritz.keys.publicKeys.signing);
      // Hallazgo 8: pero se avisa, como si me hubieran revocado, y no
      // publico hasta que se aclare.
      expect(view.revokedByOthers, isTrue);
      expect(view.selfEntitled('nora'), isFalse);
      expect((await _view(await family(), aritz)).revokedByOthers, isFalse);
    });
  });

  group('basura en el registro (hallazgo 4)', () {
    const revoke = _revoke;

    test(
      'ataque: 64 revocaciones falsas y después una buena, que entra',
      () async {
        final stranger = await Phone.create('intruso', 'leo', 9);
        final json = (await family()).toJson();
        // Firmadas por un desconocido pero «de Nora», a 64 móviles inventados.
        json['revocations'] = [
          for (var i = 0; i < kMaxRegistryRevocations; i++)
            {...(await revoke(stranger, 'x$i')).toJson(), 'by': 'nora-phone'},
        ];
        final read = await DeviceRegistry.fromJsonVerified(
          jsonDecode(jsonEncode(json)),
        );
        expect(read.revocations, isEmpty);
        final change = await revokeDevice(
          registry: read,
          view: await _view(read, aritz),
          myKeys: aritz.keys,
          deviceId: 'leo-phone',
        );
        expect((await _view(change.registry, aritz)).revoked, {'leo-phone'});
      },
    );

    test('ataque: 64 revocaciones bien firmadas por fichas basura (sin '
        'enlace) llenan el tope, y una de la familia entra igual', () async {
      final junk = await Phone.create('basura', null, 9);
      var registry = await family();
      for (final id in ['basura-1', 'basura-2']) {
        registry = await registry.withRecord(
          await DeviceRecord.create(
            keys: junk.keys,
            listId: kListId,
            deviceId: id,
            personId: null,
          ),
        );
      }
      // Cada firmante, como mucho su cupo.
      for (var i = 0; i < kMaxRegistryRevocations; i++) {
        final by = Phone(i.isEven ? 'basura-1' : 'basura-2', null, junk.keys);
        registry = await registry.withRevocation(await revoke(by, 'x$i'));
      }
      expect(registry.revocations, hasLength(kMaxRegistryRevocations));
      await expectLater(
        registry.withRevocation(
          await revoke(Phone('basura-1', null, junk.keys), 'otro'),
        ),
        throwsA(isA<RegistryException>()),
      );
      // Sin ancla no hay sitio; con el ancla de Aritz se desaloja basura.
      final change = await revokeDevice(
        registry: registry,
        view: await _view(registry, aritz),
        myKeys: aritz.keys,
        deviceId: 'leo-phone',
      );
      expect(change.registry.revocations, hasLength(kMaxRegistryRevocations));
      expect((await _view(change.registry, aritz)).revoked, {'leo-phone'});
      expect((await _view(change.registry, nora)).revoked, {'leo-phone'});
    });

    test('ataque: el registro lleno de fichas basura no impide emparejar un '
        'móvil nuevo', () async {
      final junk = await Phone.create('basura', null, 9);
      var registry = await family();
      for (var i = 0; registry.records.length < kMaxRegistryRecords; i++) {
        registry = await registry.withRecord(
          await DeviceRecord.create(
            keys: junk.keys,
            listId: kListId,
            deviceId: 'basura-$i',
            personId: 'nora',
          ),
        );
      }
      final second = await Phone.create('leo-2', 'leo', 4);
      final rSecond = await _record(second);
      await expectLater(
        registry.withRecord(rSecond),
        throwsA(isA<RegistryException>()),
      );
      final change = await approveDevice(
        registry: registry,
        view: await _view(registry, aritz),
        myKeys: aritz.keys,
        record: rSecond,
      );
      expect(change.registry.records, hasLength(kMaxRegistryRecords));
      expect((await _view(change.registry, aritz)).member('leo-2'), isNotNull);
      // Y lo de la familia sigue entero.
      for (final r in [rAritz, rLeo, rNora]) {
        expect(change.registry.recordByDigest(r.digest), isNotNull);
      }
      // Al fusionar con un registro lleno de basura, tampoco se pierde nada
      // de la familia.
      final merged = await change.registry.merge(
        registry,
        anchor: (await _view(change.registry, aritz)).anchor,
      );
      expect(merged.recordByDigest(rSecond.digest), isNotNull);
      expect((await _view(merged, aritz)).members, [
        'aritz-phone',
        'leo-2',
        'leo-phone',
        'nora-phone',
      ]);
    });

    test('un aval sin la ficha avalada, o firmado por quien no tiene ficha, '
        'no entra', () async {
      final registry = await family();
      final outsider = await Phone.create('fuera', 'leo', 9);
      final rOutsider = await _record(outsider);
      await expectLater(
        registry.withVouch(await _vouch(aritz, rOutsider)),
        throwsA(isA<RegistryException>()),
      );
      await expectLater(
        registry.withVouch(await _vouch(outsider, rLeo)),
        throwsA(isA<RegistryException>()),
      );
      // Por JSON se descartan sin romper la lectura.
      final json = registry.toJson();
      json['vouches'] = [
        ...json['vouches']! as List,
        (await _vouch(outsider, rLeo)).toJson(),
      ];
      final back = await DeviceRegistry.fromJsonVerified(
        jsonDecode(jsonEncode(json)),
      );
      expect(back.sameAs(registry), isTrue);
    });
  });

  group('fusión', () {
    test('conmutativa, asociativa e idempotente', () async {
      final base = await family();
      final a = (await revokeDevice(
        registry: base,
        view: await _view(base, aritz),
        myKeys: aritz.keys,
        deviceId: 'nora-phone',
      )).registry;
      final b = (await changePerson(
        registry: base,
        view: await _view(base, leo),
        myKeys: leo.keys,
        personId: null,
      )).registry;
      final c = await DeviceRegistry.empty(kListId).withRecord(rAritz);
      final ab = await a.merge(b);
      expect(ab.sameAs(await b.merge(a)), isTrue);
      expect(
        (await ab.merge(c)).sameAs(await a.merge(await b.merge(c))),
        isTrue,
      );
      expect((await ab.merge(ab)).sameAs(ab), isTrue);
      // Dos móviles que cambian el registro a la vez acaban en la misma
      // época.
      expect((await _view(ab, aritz)).epoch, (await _view(ab, leo)).epoch);
      expect((await _view(ab, aritz)).epoch, 3);
    });

    test('hallazgo 10: una entrada rota se salta y no invalida el '
        'registro', () async {
      final registry = await family();
      final json = jsonDecode(jsonEncode(registry.toJson())) as Map;
      json['records'] = [
        ...json['records'] as List,
        {'v': kRegistryVersion, 'l': kListId, 'd': 'roto'},
        'ni siquiera es un mapa',
      ];
      json['vouches'] = [
        ...json['vouches'] as List,
        {'v': kRegistryVersion},
      ];
      json['revocations'] = [...json['revocations'] as List, 42];
      final back = await DeviceRegistry.fromJsonVerified(json);
      expect(back.sameAs(registry), isTrue);
      expect((await _view(back, aritz)).members, hasLength(3));
    });

    test(
      'ida y vuelta por JSON; una ficha falsa se descarta al leer',
      () async {
        final registry = await family();
        final json = jsonDecode(jsonEncode(registry.toJson())) as Map;
        final back = await DeviceRegistry.fromJsonVerified(json);
        expect(back.sameAs(registry), isTrue);
        (json['records'] as List).add({...rLeo.toJson(), 'p': 'nora', 'n': 2});
        final dropped = await DeviceRegistry.fromJsonVerified(json);
        expect(dropped.sameAs(registry), isTrue);
      },
    );

    test('un registro que no cabe se rechaza entero, antes de comprobar '
        'firmas', () async {
      final json = (await family()).toJson();
      json['vouches'] = List<Object?>.filled(kMaxRegistryVouches + 1, null);
      await expectLater(
        DeviceRegistry.fromJsonVerified(json),
        throwsA(isA<RegistryException>()),
      );
      await expectLater(
        (await family()).merge(DeviceRegistry.empty('otra')),
        throwsA(isA<RegistryException>()),
      );
    });
  });

  group('segunda revisión de la fase 2a', () {
    /// La familia y un ladrón que Aritz emparejó (avalados entre sí), ya
    /// revocado por Aritz.
    Future<(DeviceRegistry, Phone, DeviceRecord)> revokedThief() async {
      final thief = await Phone.create('ladron', 'leo', 20);
      final rThief = await _record(thief);
      var registry = await (await family()).withRecord(rThief);
      registry = await _vouched(registry, [(aritz, rThief), (thief, rAritz)]);
      registry = (await revokeDevice(
        registry: registry,
        view: await _view(registry, aritz),
        myKeys: aritz.keys,
        deviceId: 'ladron',
      )).registry;
      return (registry, thief, rThief);
    }

    test('4b: la 33.ª revocación de Aritz cabe: las que cuentan, y son la '
        'primera para su móvil, no gastan el cupo de quien revoca', () async {
      var registry = await family();
      final targets = <DeviceRecord>[];
      for (var i = 0; i <= kMaxRevocationsPerSigner; i++) {
        final r = await _record(await Phone.create('movil-$i', 'leo', 10 + i));
        registry = await registry.withRecord(r);
        // Aritz ya avala a Leo y a Nora: avala a 30 más, y Nora al resto.
        final by = i < kMaxVouchesPerSigner - 2 ? aritz : nora;
        registry = await registry.withVouch(await _vouch(by, r));
        targets.add(r);
      }
      for (final r in targets) {
        registry = (await revokeDevice(
          registry: registry,
          view: await _view(registry, aritz),
          myKeys: aritz.keys,
          deviceId: r.deviceId,
        )).registry;
      }
      expect(registry.revocations, hasLength(kMaxRevocationsPerSigner + 1));
      final view = await _view(registry, aritz);
      expect(view.revoked, hasLength(kMaxRevocationsPerSigner + 1));
      expect(view.members, ['aritz-phone', 'leo-phone', 'nora-phone']);
      // Lo mismo al leerlo de JSON con el ancla.
      final back = await DeviceRegistry.fromJsonVerified(
        jsonDecode(jsonEncode(registry.toJson())),
        anchor: view.anchor,
      );
      expect(back.sameAs(registry), isTrue);
    });

    test(
      'ataque (N1): lo que cuelga de un ladrón revocado no es pendiente, '
      'no sube la época, no vuelve ambiguo a nadie y no ocupa sitio',
      () async {
        var (registry, thief, rThief) = await revokedThief();
        final epoch = (await _view(registry, aritz)).epoch;
        expect(epoch, 2);
        // El ladrón conserva sus claves: avala fichas falsas (con el seq
        // alto), revoca una y avala una ficha con el id de Nora y otras
        // claves.
        final junk = await Phone.create('basura', 'aritz', 21);
        var prev = (thief, rThief);
        for (var i = 0; i < 8; i++) {
          final fake = Phone('falso-$i', 'aritz', junk.keys);
          final r = await fake.record(seq: 5);
          registry = await registry.withRecord(r);
          registry = await registry.withVouch(await _vouch(thief, r));
          prev = (fake, r);
        }
        registry = await registry.withRevocation(
          await _revoke(thief, 'falso-0'),
        );
        final fakeNora = await _record(Phone('nora-phone', 'nora', junk.keys));
        registry = await registry.withRecord(fakeNora);
        registry = await registry.withVouch(await _vouch(thief, fakeNora));
        for (final me in [aritz, leo, nora]) {
          final view = await _view(registry, me);
          expect(view.pending, isEmpty, reason: me.id);
          expect(view.epoch, epoch, reason: me.id);
          expect(view.revoked, {'ladron'}, reason: me.id);
          expect(view.members, ['aritz-phone', 'leo-phone', 'nora-phone']);
          expect(view.revokedByOthers, isFalse, reason: me.id);
        }
        // Llena el registro con una cadena de fichas que cuelga del ladrón.
        for (var i = 8; registry.records.length < kMaxRegistryRecords; i++) {
          final fake = Phone('falso-$i', 'aritz', junk.keys);
          final r = await fake.record();
          registry = await registry.withRecord(r);
          registry = await registry.withVouch(
            await _vouch(prev.$1, r, as: prev.$2),
          );
          prev = (fake, r);
        }
        // Un móvil nuevo que aprueba Aritz entra desalojando esa basura; el
        // ladrón sigue (su revocación tiene que seguir contando).
        final second = await Phone.create('leo-2', 'leo', 22);
        final rSecond = await _record(second);
        await expectLater(
          registry.withRecord(rSecond),
          throwsA(isA<RegistryException>()),
        );
        final change = await approveDevice(
          registry: registry,
          view: await _view(registry, aritz),
          myKeys: aritz.keys,
          record: rSecond,
        );
        expect(change.registry.records, hasLength(kMaxRegistryRecords));
        expect(change.registry.recordByDigest(rThief.digest), isNotNull);
        final view = await _view(change.registry, aritz);
        expect(view.member('leo-2'), isNotNull);
        expect(view.revoked, {'ladron'});
        // Al fusionar otra vez con el registro lleno, lo nuevo de la familia
        // no se pierde.
        final merged = await change.registry.merge(
          registry,
          anchor: view.anchor,
        );
        expect(merged.recordByDigest(rSecond.digest), isNotNull);
      },
    );

    test('N6: dos fichas distintas del mismo móvil con el mismo seq más '
        'alto: el móvil es ambiguo y no se resuelve', () async {
      var registry = await family();
      for (final person in ['aritz', 'nora']) {
        registry = await registry.withRecord(
          await _record(leo, person: person, seq: 2),
        );
      }
      final view = await _view(registry, aritz);
      expect(view.member('leo-phone'), isNull);
      expect(view.pending, isEmpty);
      expect(view.revoked, contains('leo-phone'));
      // El propio móvil se entera, como si lo hubieran revocado.
      expect((await _view(registry, leo)).revokedByOthers, isTrue);
    });

    test('ataque (N7): ni un revocado ni un pendiente aprueban la ficha nueva '
        'de un móvil a sus propios ojos; un activo, sí', () async {
      var (registry, thief, _) = await revokedThief();
      registry = (await changePerson(
        registry: registry,
        view: await _view(registry, leo),
        myKeys: leo.keys,
        personId: 'aritz',
      )).registry;
      final rNew = registry.recordByDigest(
        (await _view(registry, leo)).self.recordDigest,
      )!;
      // El ladrón revocado avala la ficha nueva de Leo.
      registry = await registry.withVouch(await _vouch(thief, rNew));
      expect((await _view(registry, leo)).selfApproved, isFalse);
      // Nora cambia también de persona (queda pendiente) y la avala desde su
      // ficha nueva.
      registry = (await changePerson(
        registry: registry,
        view: await _view(registry, nora),
        myKeys: nora.keys,
        personId: 'leo',
      )).registry;
      final rNora2 = registry.recordByDigest(
        (await _view(registry, nora)).self.recordDigest,
      )!;
      registry = await registry.withVouch(await _vouch(nora, rNew, as: rNora2));
      final view = await _view(registry, leo);
      expect(view.member('nora-phone'), isNull);
      expect(view.selfApproved, isFalse);
      // Aritz, que es activo, sí.
      registry = await registry.withVouch(await _vouch(aritz, rNew));
      expect((await _view(registry, leo)).selfApproved, isTrue);
    });

    test('N2: un móvil emparejado sin persona que después elige «Yo» ve como '
        'huérfanos a los que avaló sin persona, y volver a avalarlos lo '
        'arregla', () async {
      final rLeo0 = await DeviceRecord.create(
        keys: leo.keys,
        listId: kListId,
        deviceId: leo.id,
        personId: null,
      );
      var registry = DeviceRegistry.empty(kListId);
      for (final r in [rAritz, rLeo0, rNora]) {
        registry = await registry.withRecord(r);
      }
      registry = await _vouched(registry, [
        (aritz, rLeo0),
        (aritz, rNora),
        (nora, rAritz),
        (nora, rLeo0),
      ]);
      for (final r in [rAritz, rNora]) {
        registry = await registry.withVouch(await _vouch(leo, r, as: rLeo0));
      }
      final change = await changePerson(
        registry: registry,
        view: await _view(registry, leo),
        myKeys: leo.keys,
        personId: 'leo',
      );
      expect(
        [for (final d in change.orphans) d.deviceId],
        ['aritz-phone', 'nora-phone'],
      );
      var view = await _view(change.registry, leo);
      expect(view.entitled('aritz-phone', 'nora'), isNull);
      var fixed = change.registry;
      for (final orphan in change.orphans) {
        fixed = (await approveDevice(
          registry: fixed,
          view: await _view(fixed, leo),
          myKeys: leo.keys,
          record: fixed.recordByDigest(orphan.recordDigest)!,
        )).registry;
      }
      view = await _view(fixed, leo);
      expect(view.entitled('aritz-phone', 'nora'), isNotNull);
      expect(view.entitled('nora-phone', 'aritz'), isNotNull);
      // Si vuelve a cambiar (a Aritz), lo que avaló siendo «leo» no vale
      // para las sorpresas de Leo (hallazgo 5): los dos, otra vez.
      final again = await changePerson(
        registry: fixed,
        view: view,
        myKeys: leo.keys,
        personId: 'aritz',
      );
      expect(
        [for (final d in again.orphans) d.deviceId],
        ['aritz-phone', 'nora-phone'],
      );
    });
  });
}
