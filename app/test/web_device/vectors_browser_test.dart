// ADR 0005, B5 (B4 de la revisión de seguridad de B1): los vectores de la clave
// común abiertos por el Dart compilado para la web (dart2js, en Chrome), no
// por la VM. Se pasa con:
//   flutter test --platform chrome test/web_device/vectors_browser_test.dart
// WebCrypto por su cuenta: server/test/webcrypto-vectors.test.ts.
@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/family_candidate.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/family_envelope.dart';
import 'package:regalos/core/sync/family_key_bundle.dart';

import '../sync/family_key_harness.dart';
import '../sync/protected_harness.dart';
import 'vectors_data.dart';

List<int> _hex(String s) => [
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];

String _hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final v = jsonDecode(kCommonKeyVectors) as Map<String, Object?>;
  final devices = v['devices']! as Map<String, Object?>;
  Future<DeviceKeys> keysOf(String id) {
    final d = devices[id]! as Map<String, Object?>;
    return DeviceKeys.fromSeedsForTesting(
      agreementSeed: decodeBase64Url(d['agreementSeed']! as String),
      signingSeed: decodeBase64Url(d['signingSeed']! as String),
      serviceCredential: List<int>.filled(32, 0),
    );
  }

  test(
    'las claves, el contexto, el paquete v4 y el sobre común en dart2js',
    () async {
      for (final id in devices.keys) {
        final d = devices[id]! as Map<String, Object?>;
        final keys = await keysOf(id);
        expect(
          encodeBase64Url(keys.publicKeys.agreement),
          d['agreementPublic'],
        );
        expect(encodeBase64Url(keys.publicKeys.signing), d['signingPublic']);
      }
      final family = await Family.create();
      final leoView = family.viewOf(family.leo);
      final epoch = v['epoch']! as Map<String, Object?>;
      expect(epochContextOf(leoView, syncId: kSync), epoch['context']);
      final candidate = FamilyCandidate.fromJson(
        (v['candidate']! as Map<String, Object?>)['json'],
      );
      final bundle = FamilyKeyBundle.fromJson(
        (v['keyBundleV4']! as Map<String, Object?>)['json']!
            as Map<String, Object?>,
      );
      final opened = await bundle.open(
        mine: await keysOf('leo-phone'),
        view: leoView,
        registry: family.registry,
        syncId: kSync,
      );
      expect(opened.kid, candidate.kid);
      expect(opened.secret, candidate.secret);
      final common = v['commonEnvelope']! as Map<String, Object?>;
      final aritz = devices['aritz-phone']! as Map<String, Object?>;
      final result = await openFamilyEnvelope(
        decodeBase64Url(common['envelope']! as String),
        expectedListId: kListId,
        expectedSyncId: kSync,
        resolveWriter: (w, r) =>
            w == 'aritz-phone' && r == aritz['recordDigest']
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
      // B4 de la revisión de seguridad: dart2js también sella byte a byte lo mismo con el
      // nonce del vector.
      final resealed = await sealFamilyEnvelopeForTesting(
        doc: FamilyDoc.fromJson(
          jsonDecode(common['documentJson']! as String) as Map<String, Object?>,
        ),
        candidate: opened,
        writer: 'aritz-phone',
        writerRecord: aritz['recordDigest']! as String,
        revision: 7,
        signer: await keysOf('aritz-phone'),
        nonce: decodeBase64Url(common['nonce']! as String),
      );
      expect(encodeBase64Url(resealed), common['envelope']);
    },
  );

  test(
    'X25519 de orden bajo en dart2js: los mismos rechazos y secretos',
    () async {
      final x = jsonDecode(kX25519Vectors) as Map<String, Object?>;
      final mine = await DeviceKeys.fromSeedsForTesting(
        agreementSeed: _hex(x['agreementSeed']! as String),
        signingSeed: List<int>.filled(32, 102),
        serviceCredential: List<int>.filled(32, 0),
      );
      expect(_hexOf(mine.publicKeys.agreement), x['agreementPublic']);
      for (final p in [x['control'], ...x['points']! as List]) {
        final point = p! as Map<String, Object?>;
        String? got;
        try {
          got = _hexOf(
            await (await mine.agree(_hex(point['public']! as String)))
                .extractBytes(),
          );
        } on DeviceKeyException {
          got = null;
        }
        expect(got, point['secret'], reason: point['public'] as String);
      }
    },
  );
}
