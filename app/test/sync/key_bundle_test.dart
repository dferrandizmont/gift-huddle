// Paquetes de claves ligados al registro de móviles (ADR 0004, fases 1 y 2a;
// A1, M6, B6, N6 y los requisitos 5 y 6 de la segunda pasada).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/key_bundle.dart';
import 'package:regalos/core/sync/model.dart';

import 'protected_harness.dart';

void main() {
  // Puntos de orden bajo de Curve25519: con cualquier clave privada el
  // secreto X25519 sale todo ceros.
  final lowOrder = <List<int>>[
    Uint8List(32),
    [1, ...List<int>.filled(31, 0)],
    _hex('e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800'),
    _hex('5f9c95bca3508c24b1d0b1559c83ef5b04445cc4581c8e86d8224eddd09f1157'),
    _hex('ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f'),
  ];

  late Family family;
  setUp(() async => family = await Family.create());

  String digestOf(Phone phone, [RegistryView? view]) =>
      (view ?? family.view).member(phone.id)!.recordDigest;

  Future<KeyBundle> bundleForLeo({SurpriseKey? key}) =>
      KeyBundle.sealSurpriseKey(
        sender: family.aritz.keys,
        view: family.view,
        toDevice: family.leo.id,
        key: key ?? family.key,
      );

  /// Un paquete hecho a mano, como lo haría un atacante con sus claves.
  Future<KeyBundle> forged({
    required Phone from,
    required Phone to,
    SurpriseKey? key,
    String? scope,
    List<int>? agreementKey,
    DeviceKeys? signer,
  }) => KeyBundle.sealForTesting(
    sender: signer ?? from.keys,
    fromDevice: from.id,
    toDevice: to.id,
    senderRecord: digestOf(from),
    recipientRecord: digestOf(to),
    recipientAgreementKey: agreementKey ?? to.keys.publicKeys.agreement,
    listId: kListId,
    scope: scope ?? KeyScope.surprise('nora'),
    epoch: (key ?? family.key).epoch,
    key: (key ?? family.key).bytes,
  );

  Future<SurpriseKey> openAsLeo(KeyBundle bundle, {RegistryView? view}) =>
      bundle.openSurpriseKey(
        mine: family.leo.keys,
        view: view ?? family.viewOf(family.leo),
      );

  final rejected = throwsA(isA<KeyBundleException>());

  test('ida y vuelta, también por JSON', () async {
    final bundle = KeyBundle.fromJson((await bundleForLeo()).toJson());
    final key = await openAsLeo(bundle);
    expect(key.bytes, family.key.bytes);
    expect(key.personId, 'nora');
    expect(key.epoch, 1);
    expect(key.kid, family.key.kid);
    expect(key.audience, ['aritz-phone', 'leo-phone']);
  });

  test('hallazgo 7: la audiencia va firmada; cambiarla rompe el paquete, y '
      'no se reparte una clave que conoce alguien sin derecho', () async {
    final bundle = await bundleForLeo();
    expect(bundle.audience, ['aritz-phone', 'leo-phone']);
    final json = bundle.toJson();
    for (final audience in [
      ['leo-phone'],
      ['aritz-phone', 'leo-phone', 'tia-phone'],
    ]) {
      final changed = <String, Object?>{...json, 'a': audience};
      if (audience.contains('aritz-phone')) {
        await expectLater(openAsLeo(KeyBundle.fromJson(changed)), rejected);
      } else {
        expect(() => KeyBundle.fromJson(changed), rejected);
      }
    }
    final known = family.key.withAudience(['nora-phone']);
    expect(() => bundleForLeo(key: known), rejected);
    final noAudience = SurpriseKey(
      personId: 'nora',
      epoch: 1,
      bytes: family.key.bytes,
    );
    expect(() => bundleForLeo(key: noAudience), rejected);
  });

  test(
    'la familyKey viaja igual, con su ámbito, entre móviles activos',
    () async {
      final familyKey = await FamilyKey.generate();
      final bundle = await KeyBundle.sealFamilyKey(
        sender: family.aritz.keys,
        view: family.view,
        toDevice: family.nora.id,
        epoch: 1,
        familyKey: familyKey,
      );
      expect(bundle.scope, KeyScope.family);
      final opened = await bundle.openFamilyKey(
        mine: family.nora.keys,
        view: family.viewOf(family.nora),
      );
      expect(opened, familyKey);
      // Ni para un desconocido ni de una época que el registro no ha abierto.
      for (final (to, epoch) in [('intruso', 1), (family.nora.id, 2)]) {
        expect(
          () => KeyBundle.sealFamilyKey(
            sender: family.aritz.keys,
            view: family.view,
            toDevice: to,
            epoch: epoch,
            familyKey: familyKey,
          ),
          rejected,
        );
      }
    },
  );

  test('un paquete de sorpresas no se abre como familyKey (B6)', () async {
    final bundle = await bundleForLeo();
    await expectLater(
      bundle.openFamilyKey(
        mine: family.leo.keys,
        view: family.viewOf(family.leo),
      ),
      rejected,
    );
  });

  test(
    'nunca se cifra la clave de Nora para el móvil de Nora, para uno sin '
    'persona, para uno de alguien que no existe ni para sí mismo (M6)',
    () async {
      final nobody = await Phone.create('sin-persona', null, 5);
      final registry = await registryOf([
        family.aritz,
        family.leo,
        family.nora,
        nobody,
      ]);
      final view = await family.aritz.viewOf(registry);
      for (final to in ['nora-phone', 'sin-persona', 'aritz-phone', 'otro']) {
        expect(
          () => KeyBundle.sealSurpriseKey(
            sender: family.aritz.keys,
            view: view,
            toDevice: to,
            key: family.key,
          ),
          rejected,
          reason: to,
        );
      }
      // Leo ya no existe como persona: su móvil tampoco la recibe.
      final withoutLeo = await family.aritz.viewOf(
        registry,
        people: {'aritz', 'nora'},
      );
      expect(
        () => KeyBundle.sealSurpriseKey(
          sender: family.aritz.keys,
          view: withoutLeo,
          toDevice: 'leo-phone',
          key: family.key,
        ),
        rejected,
      );
      // Y el móvil de Nora no puede sellar su propia clave para nadie.
      expect(
        () => KeyBundle.sealSurpriseKey(
          sender: family.nora.keys,
          view: family.viewOf(family.nora),
          toDevice: 'leo-phone',
          key: family.key,
        ),
        rejected,
      );
      expect(
        await KeyBundle.sealSurpriseKeyForAll(
          sender: family.aritz.keys,
          view: view,
          key: family.key,
        ),
        hasLength(1),
      );
    },
  );

  test('las personas borradas no existen', () {
    final clock = clockOf('aritz-phone', 100);
    final common = commonWithPeople(clock)
        .delete(clock, Collections.recipients, 'leo');
    expect(livePeopleOf(common), {'aritz', 'nora'});
  });

  test('el móvil de Nora no la abre aunque le llegue a su nombre', () async {
    final bundle = await forged(from: family.aritz, to: family.nora);
    await expectLater(
      bundle.openSurpriseKey(
        mine: family.nora.keys,
        view: family.viewOf(family.nora),
      ),
      rejected,
    );
  });

  test('ataque A1: Nora manda a Leo una clave suya de sus sorpresas', () async {
    // Nora fabrica una clave que conoce y la cifra para Leo, firmada por
    // ella, con las fichas correctas.
    final known32 = SurpriseKey(
      personId: 'nora',
      epoch: 1,
      bytes: List<int>.filled(32, 7),
    );
    final fromNora = await forged(
      from: family.nora,
      to: family.leo,
      key: known32,
    );
    await expectLater(openAsLeo(fromNora), rejected);
    // Y aunque llegara, el llavero no cambia la clave que ya tiene (la otra
    // queda como candidata, sin reemplazarla) ni admite una época que el
    // registro no ha abierto.
    final keyring = family.authorizedKeyring;
    expect(
      () => keyring.withKey(
        SurpriseKey(personId: 'nora', epoch: 2, bytes: List.filled(32, 7)),
        registryEpoch: 1,
      ),
      throwsA(isA<KeyringConflictException>()),
    );
    expect(
      identical(keyring.withKey(family.key, registryEpoch: 1), keyring),
      isTrue,
    );
    final both = keyring.withKey(known32, registryEpoch: 1);
    expect(both.keyFor('nora', 1, family.key.kid)!.bytes, family.key.bytes);
    expect(both.keys, hasLength(2));
  });

  test('ataque (req. 6): el segundo móvil de Nora, registrado como «leo» y '
      'avalado por ella, ni recibe la clave ni se le acepta una', () async {
    final fake = await Phone.create('nora-2', 'leo', 7);
    final rFake = await fake.record();
    var registry = await family.registry.withRecord(rFake);
    registry = await registry.withVouch(
      await Vouch.create(
        keys: family.nora.keys,
        voucher: registry.recordByDigest(digestOf(family.nora))!,
        record: rFake,
      ),
    );
    registry = await registry.withVouch(
      await Vouch.create(
        keys: fake.keys,
        voucher: rFake,
        record: registry.recordByDigest(digestOf(family.nora))!,
      ),
    );
    final view = await family.aritz.viewOf(registry);
    expect(view.member('nora-2'), isNotNull);
    expect(
      () => KeyBundle.sealSurpriseKey(
        sender: family.aritz.keys,
        view: view,
        toDevice: 'nora-2',
        key: family.key,
      ),
      rejected,
    );
    // El falso manda a Aritz una clave que Nora conoce.
    final evil = await KeyBundle.sealForTesting(
      sender: fake.keys,
      fromDevice: fake.id,
      toDevice: family.aritz.id,
      senderRecord: rFake.digest,
      recipientRecord: digestOf(family.aritz),
      recipientAgreementKey: family.aritz.keys.publicKeys.agreement,
      listId: kListId,
      scope: KeyScope.surprise('nora'),
      epoch: 1,
      key: List<int>.filled(32, 7),
    );
    await expectLater(
      evil.openSurpriseKey(mine: family.aritz.keys, view: view),
      rejected,
    );
    // (El falso se cree con derecho, pero nadie con derecho le cifra nada.)
    expect((await fake.viewOf(registry)).selfEntitled('nora'), isTrue);
  });

  group('ligado al estado del registro (req. 5)', () {
    test('un emisor revocado resuelve a null: su paquete no se abre', () async {
      final bundle = await bundleForLeo();
      final revoked = (await revokeDevice(
        registry: family.registry,
        view: family.viewOf(family.nora),
        myKeys: family.nora.keys,
        deviceId: family.aritz.id,
      )).registry;
      final view = await family.leo.viewOf(revoked);
      expect(view.member('aritz-phone'), isNull);
      await expectLater(openAsLeo(bundle, view: view), rejected);
    });

    test('si el destinatario o el emisor cambian de ficha, el paquete viejo '
        'ya no vale', () async {
      final bundle = await bundleForLeo();
      // Leo publica una ficha nueva (misma persona) y Aritz la aprueba.
      final leo2 = await family.leo.record(seq: 2);
      var registry = (await approveDevice(
        registry: family.registry,
        view: family.view,
        myKeys: family.aritz.keys,
        record: leo2,
      )).registry;
      var view = await family.leo.viewOf(registry);
      expect(view.selfEntitled('nora'), isTrue);
      await expectLater(openAsLeo(bundle, view: view), rejected);
      // Aritz cambia de ficha y Leo la aprueba: lo que selló antes no vale.
      final aritz2 = await family.aritz.record(seq: 2);
      registry = (await approveDevice(
        registry: family.registry,
        view: family.viewOf(family.leo),
        myKeys: family.leo.keys,
        record: aritz2,
      )).registry;
      view = await family.leo.viewOf(registry);
      expect(view.entitled('aritz-phone', 'nora'), isNotNull);
      await expectLater(openAsLeo(bundle, view: view), rejected);
    });

    test('una época que el registro no ha abierto no entra; una ya abierta, '
        'sí', () async {
      final future = SurpriseKey(
        personId: 'nora',
        epoch: 2,
        bytes: List<int>.filled(32, 8),
        audience: const ['aritz-phone', 'leo-phone'],
      );
      expect(() => bundleForLeo(key: future), rejected);
      final early = await forged(
        from: family.aritz,
        to: family.leo,
        key: future,
      );
      await expectLater(openAsLeo(early), rejected);
      // Tras revocar a Nora, la época es 2 y la clave nueva viaja.
      final registry = (await revokeDevice(
        registry: family.registry,
        view: family.view,
        myKeys: family.aritz.keys,
        deviceId: family.nora.id,
      )).registry;
      final mine = await family.aritz.viewOf(registry);
      expect(mine.epoch, 2);
      final bundle = await KeyBundle.sealSurpriseKey(
        sender: family.aritz.keys,
        view: mine,
        toDevice: family.leo.id,
        key: future,
      );
      final opened = await openAsLeo(
        bundle,
        view: await family.leo.viewOf(registry),
      );
      expect(opened.epoch, 2);
    });
  });

  test('manipular el ámbito, la época, el emisor, el destinatario, las '
      'fichas o el texto: rechazado', () async {
    final bundle = await bundleForLeo();
    final tampered = [
      bundle.copyForTesting(epoch: 2),
      bundle.copyForTesting(fromDevice: family.nora.id),
      bundle.copyForTesting(senderRecord: digestOf(family.nora)),
      bundle.copyForTesting(recipientRecord: digestOf(family.nora)),
      bundle.copyForTesting(scope: KeyScope.surprise('aritz')),
      bundle.copyForTesting(ciphertext: [...bundle.ciphertext]..[0] ^= 1),
      bundle.copyForTesting(signature: Uint8List(64)),
    ];
    for (final b in tampered) {
      await expectLater(openAsLeo(b), rejected);
    }
    await expectLater(
      bundle
          .copyForTesting(scope: KeyScope.family)
          .openFamilyKey(
            mine: family.leo.keys,
            view: family.viewOf(family.leo),
          ),
      rejected,
    );
    await expectLater(
      bundle
          .copyForTesting(toDevice: family.aritz.id)
          .openSurpriseKey(mine: family.aritz.keys, view: family.view),
      rejected,
    );
    await expectLater(
      bundle.openSurpriseKey(mine: family.aritz.keys, view: family.view),
      rejected,
    );
  });

  test('firma de otro móvil: rechazada', () async {
    final bundle = await forged(
      from: family.aritz,
      to: family.leo,
      signer: family.nora.keys,
    );
    await expectLater(openAsLeo(bundle), rejected);
  });

  test('clave X25519 de orden bajo: rechazada al cifrar y al abrir', () async {
    for (final point in lowOrder) {
      await expectLater(
        forged(from: family.aritz, to: family.leo, agreementKey: point),
        rejected,
      );
    }
    // Un emisor malicioso firma un paquete con una efímera de orden bajo:
    // la firma vale, pero el secreto de ceros se rechaza.
    final bundle = await bundleForLeo();
    for (final point in lowOrder) {
      final evil = bundle.copyForTesting(ephemeralPublicKey: point);
      final resigned = await _resign(evil, family);
      await expectLater(openAsLeo(resigned), rejected);
    }
    // El paquete bueno, vuelto a firmar igual, sí se abre: la prueba de
    // arriba falla por la efímera y no por la firma.
    expect((await openAsLeo(await _resign(bundle, family))).bytes, [
      ...family.key.bytes,
    ]);
  });

  test('vector fijo', () async {
    final bundle = await KeyBundle.sealForTesting(
      sender: family.aritz.keys,
      fromDevice: family.aritz.id,
      toDevice: family.leo.id,
      senderRecord: digestOf(family.aritz),
      recipientRecord: digestOf(family.leo),
      recipientAgreementKey: family.leo.keys.publicKeys.agreement,
      listId: kListId,
      scope: KeyScope.surprise('nora'),
      epoch: 1,
      key: family.key.bytes,
      ephemeralSeed: List<int>.filled(32, 9),
      nonce: List<int>.filled(12, 5),
    );
    expect(bundle.toJson()['c'], _bundleVector);
    expect((await openAsLeo(bundle)).bytes, family.key.bytes);
  });
}

// Texto cifrado y etiqueta del paquete del vector fijo (efímera 09..09,
// nonce 05..05, clave de sorpresas 2a..2a, claves y fichas de la familia de
// prueba; formato v3, con la audiencia en el AAD).
const _bundleVector =
    '4_X945-PUw4oWclYyumTtjySJTPXl9j3BNUOg7_oReOI6SBeCoeIILbcM5AOAA1J';

/// Vuelve a firmar con la clave de Aritz lo que lleve [bundle], como haría un
/// emisor malicioso.
Future<KeyBundle> _resign(KeyBundle bundle, Family family) async {
  final json = bundle.toJson();
  final aad = <int>[
    ...'gift-huddle-key-bundle-v3'.codeUnits,
    0,
    ...canonicalHeaderBytes(<String, Object?>{
      'a': bundle.audience,
      'e': bundle.epoch,
      'fr': bundle.senderRecord,
      'from': bundle.fromDevice,
      'l': bundle.listId,
      's': bundle.scope,
      'to': bundle.toDevice,
      'tr': bundle.recipientRecord,
      'v': 3,
    }),
    ...bundle.ephemeralPublicKey,
    ...family.leo.keys.publicKeys.agreement,
  ];
  final signature = await family.aritz.keys.sign([
    ...aad,
    ...bundle.nonce,
    ...bundle.ciphertext,
  ]);
  return KeyBundle.fromJson({...json, 'sig': encodeBase64Url(signature)});
}

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);
