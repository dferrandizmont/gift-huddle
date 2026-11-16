// Vectores fijos del lote B1 del ADR 0005: contexto de época, kid, paquete
// v4 de la clave común y sobre común firmado. La web compila este mismo Dart
// (`flutter build web`), así que los vectores atan las dos plataformas; el
// JSON de docs/adr/0005-vector-clave-comun.json sirve además a quien quiera
// reimplementarlo con WebCrypto.
//
// Regenerar (solo si cambia el formato o la versión de 'archive'):
//   REGALOS_WRITE_VECTORS=1 flutter test test/sync/family_vector_test.dart
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_candidate.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/family_envelope.dart';
import 'package:regalos/core/sync/family_key_bundle.dart';
import 'package:regalos/core/sync/model.dart';

import 'family_key_harness.dart';
import 'protected_harness.dart';

const _path = '../docs/adr/0005-vector-clave-comun.json';

Future<Map<String, Object?>> _compute() async {
  final family = await Family.create();
  final view = family.view;
  final descriptor = EpochDescriptor.ofView(view, syncId: kSync);
  final candidate = await candidateFor(family, view, seed: 7);
  final ephemeralSeed = List<int>.filled(32, 0x11);
  final bundleNonce = List<int>.filled(12, 0x22);
  final bundle = await FamilyKeyBundle.sealForTesting(
    sender: family.aritz.keys,
    candidate: candidate,
    fromDevice: family.aritz.id,
    senderRecord: view.self.recordDigest,
    toDevice: family.leo.id,
    recipientRecord: view.member(family.leo.id)!.recordDigest,
    recipientAgreementKey: family.leo.keys.publicKeys.agreement,
    ephemeralSeed: ephemeralSeed,
    nonce: bundleNonce,
  );
  final clock = clockOf('aritz-phone', 1);
  final doc = FamilyDoc.empty(kListId)
      .set(clock, Collections.recipients, 'leo', {
        'name': 'Leo',
        'colorIndex': 1,
        'archived': false,
      })
      .set(clock, Collections.gifts, 'g1', giftFields('leo', 'Cometa'))
      .delete(clock, Collections.gifts, 'g1');
  final envelopeNonce = List<int>.filled(12, 0x33);
  final envelope = await sealFamilyEnvelopeForTesting(
    doc: doc,
    candidate: candidate,
    writer: family.aritz.id,
    writerRecord: view.self.recordDigest,
    revision: 7,
    signer: family.aritz.keys,
    nonce: envelopeNonce,
  );
  final hLen = (envelope[3] << 8) | envelope[4];
  return <String, Object?>{
    'about':
        'ADR 0005, lote B1. Binarios en base64url sin relleno; kid y '
        'contexto en hexadecimal. Semillas de las claves de dispositivo: '
        'X25519 y Ed25519 (como DeviceKeys.fromSeedsForTesting).',
    'listId': kListId,
    'syncId': kSync,
    'devices': {
      for (final p in [family.aritz, family.leo, family.nora])
        p.id: {
          'agreementSeed': encodeBase64Url(List<int>.filled(32, _seed(p.id))),
          'signingSeed': encodeBase64Url(
            List<int>.filled(32, _seed(p.id) + 100),
          ),
          'agreementPublic': encodeBase64Url(p.keys.publicKeys.agreement),
          'signingPublic': encodeBase64Url(p.keys.publicKeys.signing),
          'recordDigest': view.member(p.id)!.recordDigest,
        },
    },
    'epoch': {
      'domain': 'gift-huddle-epoch-context-v2',
      'descriptor': descriptor.toJson(),
      'canonical': utf8.decode(canonicalHeaderBytes(descriptor.toJson())),
      'context': descriptor.context,
    },
    'candidate': {
      'kidDomain': 'gift-huddle-family-kid-v1',
      'creatorDomain': 'gift-huddle-family-candidate-v1',
      'json': candidate.toJson(),
    },
    'keyBundleV4': {
      'domain': 'gift-huddle-key-bundle-v4',
      'ephemeralSeed': encodeBase64Url(ephemeralSeed),
      'json': bundle.toJson(),
    },
    'commonEnvelope': {
      'signatureDomain': 'gift-huddle-common-v2',
      'contentKey': 'HKDF-SHA256(secreto, sal vacía, info = signatureDomain ‖ 0x00 ‖ kid)',
      'documentJson': jsonEncode(doc.toJson()),
      'header': utf8.decode(envelope.sublist(5, 5 + hLen)),
      'nonce': encodeBase64Url(envelopeNonce),
      'envelope': encodeBase64Url(envelope),
    },
  };
}

int _seed(String id) => switch (id) {
  'aritz-phone' => 1,
  'leo-phone' => 2,
  _ => 3,
};

void main() {
  test('los vectores del JSON salen igual desde el Dart', () async {
    final computed = await _compute();
    final text = '${const JsonEncoder.withIndent('  ').convert(computed)}\n';
    final file = io.File(_path);
    if (io.Platform.environment['REGALOS_WRITE_VECTORS'] == '1') {
      file.writeAsStringSync(text);
    }
    expect(
      jsonDecode(file.readAsStringSync()),
      jsonDecode(text),
      reason: 'regenerar con REGALOS_WRITE_VECTORS=1 si cambió el formato',
    );
  });

  test('los vectores del JSON se abren desde sus semillas', () async {
    final v =
        jsonDecode(io.File(_path).readAsStringSync()) as Map<String, Object?>;
    final devices = v['devices']! as Map<String, Object?>;
    Future<DeviceKeys> keysOf(String id) {
      final d = devices[id]! as Map<String, Object?>;
      return DeviceKeys.fromSeedsForTesting(
        agreementSeed: decodeBase64Url(d['agreementSeed']! as String),
        signingSeed: decodeBase64Url(d['signingSeed']! as String),
        serviceCredential: List<int>.filled(32, 0),
      );
    }

    final family = await Family.create();
    final leoView = family.viewOf(family.leo);
    // Contexto desde el descriptor.
    final epoch = v['epoch']! as Map<String, Object?>;
    final descriptor = EpochDescriptor.fromJson(epoch['descriptor']);
    expect(descriptor.context, epoch['context']);
    expect(
      sha256Hex([
        ...utf8.encode(epoch['domain']! as String),
        0,
        ...utf8.encode(epoch['canonical']! as String),
      ]),
      epoch['context'],
    );
    expect(epochContextOf(leoView, syncId: kSync), epoch['context']);
    // La candidata y su kid.
    final candidateJson = (v['candidate']! as Map<String, Object?>)['json'];
    final candidate = FamilyCandidate.fromJson(candidateJson);
    expect(candidate.epochContext, epoch['context']);
    // El paquete abre como Leo y da la candidata.
    final bundleJson =
        (v['keyBundleV4']! as Map<String, Object?>)['json']!
            as Map<String, Object?>;
    final opened = await FamilyKeyBundle.fromJson(bundleJson).open(
      mine: await keysOf('leo-phone'),
      view: leoView,
      registry: family.registry,
      syncId: kSync,
    );
    expect(opened.kid, candidate.kid);
    expect(opened.secret, candidate.secret);
    // El sobre común abre con esa candidata y la firma de Aritz.
    final common = v['commonEnvelope']! as Map<String, Object?>;
    final aritz = devices['aritz-phone']! as Map<String, Object?>;
    final result = await openFamilyEnvelope(
      decodeBase64Url(common['envelope']! as String),
      expectedListId: kListId,
      expectedSyncId: kSync,
      resolveWriter: (w, r) => w == 'aritz-phone' && r == aritz['recordDigest']
          ? decodeBase64Url(aritz['signingPublic']! as String)
          : null,
      keyring: FamilyKeyring.empty.withOwnCandidate(opened),
    );
    expect(
      result.doc.canonicalJson(),
      FamilyDoc.fromJson(
        jsonDecode(common['documentJson']! as String) as Map<String, Object?>,
      ).canonicalJson(),
    );
    expect(result.header.revision, 7);
  });
}
