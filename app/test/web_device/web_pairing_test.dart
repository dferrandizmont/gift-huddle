import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/sync_v2_engine.dart';
import 'package:regalos/features/sync/application/v2_family_lock.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/core/sync/family_envelope.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/web_device/application/web_common.dart';
import 'package:regalos/features/web_device/application/web_pairing_guest.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart';

import '../sync/v2_harness.dart';
import 'web_engine_support.dart';

SyncResponse change(
  SyncResponse response,
  void Function(Map<String, Object?>) edit,
) {
  final json = response.json();
  edit(json);
  return SyncResponse(
    response.status,
    response.headers,
    Uint8List.fromList(utf8.encode(jsonEncode(json))),
  );
}

void main() {
  late WebHarness h;
  setUp(() {
    h = WebHarness();
  });

  test('approval winning withdrawal preserves the result until the web revokes itself', () async {
    await h.setup(approve: false);
    await h.host.confirm(confirmedPersonId: 'leo');
    expect(
      await h.client.withdrawInvite(
        h.guest.qr.inviteId,
        credential: h.guest.keys.serviceCredential,
      ),
      V2InviteWithdrawal.alreadyApproved,
    );
    expect(
      await h.client.pollInviteResult(
        h.guest.qr.inviteId,
        credential: h.guest.keys.serviceCredential,
      ),
      isA<V2InviteApproved>(),
    );
    final snapshot = (await h.client.getList(h.phone.auth) as V2GetOk).snapshot;
    final webId = snapshot.devices.singleWhere((d) => d.role == 'web').deviceId;
    final revoked = Completer<void>();
    h.worker.tamper = (method, uri, response) {
      if (method == 'POST' && uri.path.endsWith('/revoke')) {
        expect(response.status, 200);
        revoked.complete();
      }
      return response;
    };
    h.guest.cancel();
    await revoked.future.timeout(const Duration(seconds: 5));
    expect(h.guest.approved, isTrue);
    expect(h.worker.devicesOf(kV2Sync)[webId], isTrue);
    expect(h.worker.devicesOf(kV2Sync)[h.phone.identity.deviceId], isFalse);
  });

  test(
    'complete web pairing, enrollment, role and authenticated version floor',
    () async {
      await h.setup();
      addTearDown(h.close);
      expect(h.engine.status, WebSyncStatus.confirmed);
      expect(h.guest.joined!.minVersion, greaterThanOrEqualTo(3));
      final snapshot =
          (await h.client.getList(h.phone.auth) as V2GetOk).snapshot;
      expect(
        snapshot.devices
            .firstWhere((d) => d.deviceId == h.guest.joined!.identity.deviceId)
            .role,
        'web',
      );
      expect(h.vault.opened.data['roots'], isNotEmpty);
      expect(h.guest.personName, 'Leo');
      await expectLater(
        h.client.putList(
          h.engine.auth,
          version: snapshot.version,
          body: V2SnapshotUpload(
            common: snapshot.common,
            registry: h.phone.reg.toJson(),
            keyPackages: const [],
          ),
        ),
        throwsA(
          isA<V2ForbiddenException>().having(
            (e) => e.code,
            'role',
            'forbidden_role',
          ),
        ),
      );
    },
  );

  test(
    'no offer yet differs from expired and respects the 10 minute budget',
    () async {
      var time = DateTime.utc(2026);
      final guest = await WebPairingGuest.create(
        transport: h.client,
        now: () => time,
      );
      await guest.poll();
      expect(guest.code, isNull);
      await expectLater(
        h.client.getOffer(guest.qr.inviteId),
        throwsA(isA<InviteGoneException>()),
      );
      await expectLater(
        h.client.getOffer(guest.qr.inviteId, allowNotYet: true),
        throwsA(isA<V2OfferNotYetException>()),
      );
      for (var i = 0; i < 20; i++) {
        // 1-2 s while the pairing screen is open (before any request counts).
        expect(guest.pollDelay.inMilliseconds, inInclusiveRange(1000, 2000));
      }
      time = time.add(const Duration(minutes: 10));
      await expectLater(guest.poll(), throwsA(isA<InviteGoneException>()));
    },
  );

  test(
    'QR parser refuses wrong origin, route, query, size, noncanonical bytes',
    () {
      const id = 'AAAAAAAAAAAAAAAAAAAAAA';
      final good = 'https://web.gifthuddle.app/w#$id.$id';
      expect(WebPairingQr.parse(good).inviteId, id);
      expect(const WebPairingQr(id, id).url(), good);
      expect(
        () => WebPairingQr.parse(good, origin: 'https://custom.example'),
        throwsA(isA<PairingException>()),
      );
      for (final bad in [
        good.replaceFirst('/w#', '/i#'),
        good.replaceFirst('https', 'http'),
        good.replaceFirst('web.gifthuddle.app', 'other.example'),
        for (final host in [
          'web.gifthuddle.app.example.com',
          'xweb.gifthuddle.app',
          'gifthuddle.app',
          'gifthuddle.app.example.com',
          'xgifthuddle.app',
          'web.gifthuddle.app:443',
          'web.gifthuddle.app:8443',
          'usuario@web.gifthuddle.app',
          'gifthuddle-app.retired.example',
          'gifthuddle-app.retired.example:443',
          'gifthuddle-app.retired.example:8443',
          'usuario@gifthuddle-app.retired.example',
        ])
          good.replaceFirst('web.gifthuddle.app', host),
        good.replaceFirst('/w#', '/w?x=1#'),
        '$good.',
        good.replaceFirst('#$id', '#AAAAAAAAAAAAAAAAAAAAAB'),
      ]) {
        expect(() => WebPairingQr.parse(bad), throwsA(isA<PairingException>()));
      }
    },
  );

  test('invite_exists reserves the QR globally and idempotent requests preserve the offer', () async {
    await h.setup(approve: false);
    final offer = await h.client.getOffer(h.guest.qr.inviteId);
    final ticket = await h.client.createInvite(
      h.phone.auth,
      Map<String, Object?>.from(offer.offer as Map),
      inviteId: h.guest.qr.inviteId,
      guestPerson: 'leo',
    );
    expect(ticket.inviteId, h.guest.qr.inviteId);
    await expectLater(
      PairingV2Host.start(
        transport: h.client,
        local: h.phone,
        lock: V2FamilyLock(),
        web: h.guest.qr,
        guestPerson: 'leo',
      ),
      throwsA(
        isA<V2InviteConflictException>().having(
          (e) => e.code,
          'code',
          'invite_exists',
        ),
      ),
    );
  });

  for (final attack in ['fingerprint', 'person', 'mobile']) {
    test(
      'mobile rejects a substituted signed $attack before revealing',
      () async {
        // Create a new unconsumed web invitation on the real host.
        await h.setup(approve: false);
        final web = await WebPairingGuest.create(transport: h.client);
        final host = await PairingV2Host.start(
          transport: h.client,
          local: h.phone,
          lock: V2FamilyLock(),
          web: web.qr,
          guestPerson: 'leo',
        );
        final offer = await PairingOffer.fromJson(
          (await h.client.getOffer(host.inviteId)).offer,
        );
        final response = await joinPairing(
          offer: offer,
          keys: attack == 'fingerprint'
              ? await DeviceKeys.generate()
              : web.keys,
          deviceId: 'web-attacker',
          personId: attack == 'person' ? 'nora' : 'leo',
          kind: attack == 'mobile' ? DeviceKind.mobile : DeviceKind.web,
        );
        // Valid request first; substitute a newly signed response in GET I.
        await web.poll();
        h.worker.tamper = (method, uri, r) =>
            method == 'GET' && uri.path.endsWith('/${host.inviteId}')
            ? change(r, (j) => j['answer'] = response.answer.toJson())
            : r;
        final reveals = h.worker.calls['POST reveal'] ?? 0;
        await expectLater(host.poll(), throwsA(isA<PairingException>()));
        expect(h.worker.calls['POST reveal'] ?? 0, reveals);
      },
    );
  }

  test('normal mobile invitation refuses a signed web answer', () async {
    await h.setup(approve: false);
    final host = await PairingV2Host.start(
      transport: h.client,
      local: h.phone,
      lock: V2FamilyLock(),
    );
    final offer = await PairingOffer.fromJson(
      (await h.client.getOffer(host.inviteId)).offer,
    );
    final keys = await DeviceKeys.generate();
    final guest = PairingV2Guest.forWeb(
      transport: h.client,
      inviteId: host.inviteId,
      offer: offer,
      keys: keys,
      deviceId: 'unexpected-web',
    );
    await guest.answer(personId: 'leo');
    await expectLater(host.poll(), throwsA(isA<PairingException>()));
  });

  for (final attack in ['reveal', 'signature', 'minVersion', 'version']) {
    test('web refuses tampered approval $attack and never enrolls', () async {
      await h.setup(approve: false);
      h.guest.confirmCode();
      await h.host.confirm(confirmedPersonId: 'leo');
      h.worker.tamper = (method, uri, r) {
        if (!uri.path.endsWith('/result') || r.status != 200) return r;
        return change(r, (j) {
          final p = Map<String, Object?>.from(j['package'] as Map);
          switch (attack) {
            case 'reveal':
              j['reveal'] = {'v': 2, 'n': encodeBase64Url(List.filled(32, 0))};
            case 'signature':
              p.remove('sig');
            case 'minVersion':
              p['minVersion'] = 1;
            case 'version':
              p['v'] = 2;
          }
          j['package'] = p;
        });
      };
      await expectLater(h.guest.poll(), throwsA(isA<PairingException>()));
      expect(h.guest.joined, isNull);
      expect((await h.store.read()).current, isNull);
    });
  }

  test(
    'web also enforces signed minVersion when outer version is lowered',
    () async {
      await h.setup(approve: false);
      final old = (await h.client.getList(h.phone.auth) as V2GetOk).snapshot;
      h.guest.confirmCode();
      await h.host.confirm(confirmedPersonId: 'leo');
      h.worker.tamper = (method, uri, r) {
        if (uri.path.endsWith('/result') && r.status == 200) {
          return change(r, (j) => j['minVersion'] = 1);
        }
        if (uri.path == '/v2/lists/$kV2Sync' && method == 'GET') {
          return SyncResponse(
            200,
            {'etag': '"${old.version}"'},
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  ...r.json(),
                  'version': old.version,
                  'common': encodeBase64Url(old.common),
                  'registry': old.registry,
                }),
              ),
            ),
          );
        }
        return r;
      };
      // B7 (M1): la web parte del checkpoint con el suelo firmado, no del
      // `minVersion` del servidor, y su primera vuelta rechaza lo viejo.
      await h.guest.poll();
      expect(h.guest.joined!.minVersion, greaterThan(old.version));
      expect(h.guest.joined!.snapshot.version, h.guest.joined!.minVersion);
      await h.guest.enroll(h.vault, '123456');
      await expectLater(h.engine.sync(), throwsA(isA<V2RollbackException>()));
    },
  );

  test(
    'B7+B5: tras el corte la web se empareja, nace con el llavero del '
    'checkpoint y la marca, y su primera vuelta abre el común en formato 2',
    () async {
      expect(kWebPairingCommonV2, isTrue);
      await h.setup(cut: true);
      addTearDown(h.close);
      final joined = h.guest.joined!;
      expect(joined.commonFormat, 2);
      final data = h.vault.opened.data;
      expect(data[kWebCommonFloorField], 2);
      expect(data[kWebCommonKeysField], isNotNull);
      final server = (await h.client.getList(h.phone.auth) as V2GetOk).snapshot;
      expect(isFamilyEnvelope(server.common), isTrue);
      expect(h.engine.status, WebSyncStatus.confirmed);
      expect(h.engine.candidate!.record(Collections.gifts, 'gift'), isNotNull);
      expect(
        h.worker.devicesOf(kV2Sync)[joined.identity.deviceId],
        isFalse,
        reason: 'credencial web viva',
      );
    },
  );

  test('B7+B5: antes del corte la caja es la de siempre (sin llavero ni '
      'marca)', () async {
    await h.setup();
    addTearDown(h.close);
    expect(h.guest.joined!.commonFormat, 1);
    final data = h.vault.opened.data;
    expect(data.containsKey(kWebCommonFloorField), isFalse);
    expect(data.containsKey(kWebCommonKeysField), isFalse);
    expect(h.engine.status, WebSyncStatus.confirmed);
  });
}
