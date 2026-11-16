// ADR 0003 W1–W4: every attack below uses newly signed records/declarations.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/device_keys.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/key_bundle.dart';
import 'package:regalos/core/sync/pairing_v2.dart';

import 'protected_harness.dart';

Future<DeviceRecord> record(
  Phone phone, {
  DeviceKind kind = DeviceKind.mobile,
  int seq = 1,
  String? person,
}) => DeviceRecord.create(
  keys: phone.keys,
  listId: kListId,
  deviceId: phone.id,
  personId: person ?? phone.self,
  seq: seq,
  kind: kind,
);

Future<Vouch> vouch(Phone signer, DeviceRecord from, DeviceRecord to) =>
    Vouch.create(keys: signer.keys, voucher: from, record: to);

void main() {
  late Phone a, b, w, intruder;
  late DeviceRecord ra, rb, rw, ri;
  late DeviceRegistry base;
  late RegistryAnchor anchor;

  setUp(() async {
    a = await Phone.create('aritz-phone', 'aritz', 1);
    b = await Phone.create('leo-phone', 'leo', 2);
    w = await Phone.create('nora-web', 'nora', 3);
    intruder = await Phone.create('intruder', 'aritz', 4);
    ra = await record(a);
    rb = await record(b);
    rw = await record(w, kind: DeviceKind.web);
    ri = await record(intruder, seq: 16);
    anchor = RegistryAnchor(
      deviceId: a.id,
      signingKey: a.keys.publicKeys.signing,
    );
    base = await DeviceRegistry.empty(kListId).withDeclarations(
      records: [ra, rb, rw],
      vouches: [
        await vouch(a, ra, rb),
        await vouch(b, rb, ra),
        await vouch(a, ra, rw),
      ],
      anchor: anchor,
    );
  });

  test('fixed pre-k mobile message, signature and digest; signed web vector and QR', () async {
    final vector = jsonDecode(
      File('../docs/adr/0003-vector-ficha.json').readAsStringSync(),
    ) as Map;
    final keys = await DeviceKeys.fromSeedsForTesting(
      signingSeed: decodeBase64Url(vector['signingSeed'] as String),
      agreementSeed: decodeBase64Url(vector['agreementSeed'] as String),
      serviceCredential: List.filled(32, 0),
    );
    for (final kind in DeviceKind.values) {
      final expected = vector[kind.name] as Map;
      final fixed = await DeviceRecord.create(
        keys: keys,
        listId: 'vector-list',
        deviceId: 'vector-device',
        personId: 'aritz',
        kind: kind,
      );
      expect(fixed.toJson(), expected['record']);
      expect(fixed.digest, expected['digest']);
      final fields = Map<String, Object?>.from(fixed.toJson())..remove('sig');
      expect(
        encodeBase64Url([
          ...utf8.encode('gift-huddle-device-v2'),
          0,
          ...canonicalHeaderBytes(fields),
        ]),
        expected['messageBase64Url'],
      );
      expect(await DeviceRecord.fromJson(expected['record']).verify(), isTrue);
    }
    final qr = vector['pairing'] as Map;
    expect(
      webPairingFingerprint(
        qr['inviteId'] as String,
        keys.publicKeys.signing,
        keys.publicKeys.agreement,
      ),
      qr['fingerprint'],
    );
  });

  test('k is signed; only absence or literal web is accepted', () async {
    expect(ra.toJson().containsKey('k'), isFalse);
    expect(rw.toJson()['k'], 'web');
    for (final bad in [null, 'mobile', 'desktop', 1, true]) {
      expect(
        () => DeviceRecord.fromJson({...rw.toJson(), 'k': bad}),
        throwsA(isA<RegistryException>()),
      );
    }
    final stripped = rw.toJson()..remove('k');
    expect(await DeviceRecord.fromJson(stripped).verify(), isFalse);
  });

  for (final seq in [1, 2, 16]) {
    test(
      'new valid mobile record without k at seq $seq makes web id ambiguous',
      () async {
        final downgraded = await record(w, seq: seq);
        expect(await downgraded.verify(), isTrue);
        final attackVouch = await vouch(w, downgraded, ri);
        final attackRevoke = await Revocation.create(
          keys: w.keys,
          by: downgraded,
          deviceId: b.id,
        );
        // Valid mobile authority in isolation must disappear when its web history arrives.
        final remote = await DeviceRegistry.empty(kListId).withDeclarations(
          records: [downgraded, ri],
          vouches: [attackVouch],
          revocations: [attackRevoke],
        );
        for (final registry in [
          await base.merge(remote, anchor: anchor),
          await remote.merge(base, anchor: anchor),
          await base.withRecord(downgraded, anchor: anchor),
        ]) {
          final view = await a.viewOf(registry);
          expect(view.device(w.id), isNull);
          expect(view.revoked, contains(w.id));
          expect(view.epoch, 2 + seq - 1);
          expect(view.member(b.id), isNotNull);
          expect(view.device(intruder.id), isNull);
          expect(view.pending.map((d) => d.deviceId), isNot(contains(w.id)));
          expect(view.detached.map((d) => d.deviceId), isNot(contains(w.id)));
          expect(view.entitled(w.id, 'leo'), isNull);
          await expectLater(
            w.viewOf(registry),
            throwsA(isA<RegistryException>()),
          );
          await expectLater(
            registry.withVouch(attackVouch),
            throwsA(isA<RegistryException>()),
          );
          await expectLater(
            registry.withRevocation(attackRevoke),
            throwsA(isA<RegistryException>()),
          );
          final restored = await DeviceRegistry.fromJsonVerified(
            registry.toJson(),
            anchor: anchor,
          );
          expect((await a.viewOf(restored)).revoked, contains(w.id));
          expect((await a.viewOf(restored)).device(intruder.id), isNull);
        }
      },
    );
  }

  test(
    'a historical mobile record conflicts with a newer valid web record',
    () async {
      final historical = await record(w);
      final newer = await record(
        w,
        kind: DeviceKind.web,
        seq: 2,
        person: 'leo',
      );
      final registry = await base.withDeclarations(
        records: [historical, newer],
      );
      final view = await a.viewOf(registry);
      expect(view.revoked, contains(w.id));
      expect(view.device(w.id), isNull);
      expect(webStatusIn(view, w.id), WebDeviceStatus.revoked);
    },
  );

  for (final victimIsRoot in [false, true]) {
    for (final revokedSponsor in [false, true]) {
      test(
        'foreign web keys do not invalidate ${victimIsRoot ? 'root' : 'member'} '
        'with ${revokedSponsor ? 'revoked-only' : 'no'} vouch (N1)',
        () async {
          final victim = victimIsRoot ? a : b;
          final fake = await DeviceRecord.create(
            keys: intruder.keys,
            listId: kListId,
            deviceId: victim.id,
            personId: victim.self,
            kind: DeviceKind.web,
          );
          expect(await fake.verify(), isTrue);
          final revoked = await base.withDeclarations(
            records: [ri],
            vouches: [await vouch(a, ra, ri)],
            revocations: [
              await Revocation.create(
                keys: a.keys,
                by: ra,
                deviceId: intruder.id,
              ),
            ],
            anchor: anchor,
          );
          final remote = await DeviceRegistry.empty(kListId).withDeclarations(
            records: [ri, fake],
            vouches: [if (revokedSponsor) await vouch(intruder, ri, fake)],
          );
          for (final merged in [
            await revoked.merge(remote, anchor: anchor),
            await remote.merge(revoked, anchor: anchor),
          ]) {
            final restored = await DeviceRegistry.fromJsonVerified(
              jsonDecode(jsonEncode(merged.toJson())),
              anchor: anchor,
            );
            for (final registry in [merged, restored]) {
              expect(
                registry.revocations.map((r) => r.toJson()),
                revoked.revocations.map((r) => r.toJson()),
              );
              expect(
                registry.vouches.map((v) => v.toJson()),
                containsAll(revoked.vouches.map((v) => v.toJson())),
              );
              for (final root in [a, b]) {
                final before = await root.viewOf(revoked);
                final after = await root.viewOf(registry);
                expect(after.members, before.members);
                expect(after.revoked, before.revoked);
                expect(after.epoch, before.epoch);
                expect(after.revokedByOthers, isFalse);
                expect(after.pending, isEmpty);
                expect(after.detached, isEmpty);
                expect(after.member(victim.id)!.kind, DeviceKind.mobile);
                expect(after.entitled(victim.id, 'nora'), isNotNull);
              }
            }
          }
        },
      );
    }
  }

  test('foreign web keys vouched by an active mobile follow identity ambiguity', () async {
    for (final victim in [a, b]) {
      final fake = await DeviceRecord.create(
        keys: intruder.keys,
        listId: kListId,
        deviceId: victim.id,
        personId: victim.self,
        kind: DeviceKind.web,
      );
      final registry = await base.withDeclarations(
        records: [fake],
        vouches: [
          await vouch(victim == a ? b : a, victim == a ? rb : ra, fake),
        ],
        anchor: anchor,
      );
      final rootView = await a.viewOf(registry);
      if (victim == a) {
        expect(rootView.revokedByOthers, isTrue);
        expect(rootView.self.recordDigest, ra.digest);
      } else {
        expect(rootView.revoked, contains(b.id));
        expect(rootView.device(b.id), isNull);
        expect(rootView.epoch, 2);
      }
      // A foreign identity must not erase the legitimate mobile's declarations.
      expect(
        registry.vouches.map((v) => v.toJson()),
        containsAll(base.vouches.map((v) => v.toJson())),
      );
    }
  });

  test('approved mobile cannot become web with the same keys', () async {
    final changed = await record(b, kind: DeviceKind.web, seq: 2);
    expect(await changed.verify(), isTrue);
    final registry = await base.withRecord(changed, anchor: anchor);
    final restored = await DeviceRegistry.fromJsonVerified(
      jsonDecode(jsonEncode(registry.toJson())),
      anchor: anchor,
    );
    for (final candidate in [registry, restored]) {
      final view = await a.viewOf(candidate);
      expect(view.device(b.id), isNull);
      expect(view.revoked, contains(b.id));
      expect(view.epoch, 3);
      expect(view.entitled(b.id, 'nora'), isNull);
      expect(candidate.vouches.where((v) => v.by == b.id), isEmpty);
      await expectLater(b.viewOf(candidate), throwsA(isA<RegistryException>()));
    }
  });

  for (final crowdedKind in DeviceKind.values) {
    test(
      '16 ${crowdedKind.name} records preserve opposite-kind witness in both merge orders',
      () async {
        final crowdedRecords = [
          for (var seq = 1; seq <= 16; seq++)
            await record(w, seq: seq, kind: crowdedKind),
        ];
        final opposite = await record(
          w,
          kind: crowdedKind == DeviceKind.mobile
              ? DeviceKind.web
              : DeviceKind.mobile,
        );
        final crowded = await DeviceRegistry.empty(kListId).withDeclarations(
          records: [ra, ...crowdedRecords],
          vouches: [await vouch(a, ra, crowdedRecords.first)],
          anchor: anchor,
        );
        final other = await DeviceRegistry.empty(kListId).withDeclarations(
          records: [ra, opposite],
          vouches: [await vouch(a, ra, opposite)],
          anchor: anchor,
        );
        for (var registry in [
          await crowded.merge(other, anchor: anchor),
          await other.merge(crowded, anchor: anchor),
        ]) {
          // Apply further pressure to the global cap, too: neither witness can go.
          final junk = await DeviceRegistry.empty(kListId).withDeclarations(
            records: [
              for (var i = 0; i < 64; i++)
                await DeviceRecord.create(
                  keys: intruder.keys,
                  listId: kListId,
                  deviceId: 'quota-junk-$i',
                  personId: 'aritz',
                ),
            ],
          );
          registry = await junk.merge(registry, anchor: anchor);
          registry = await DeviceRegistry.fromJsonVerified(
            jsonDecode(jsonEncode(registry.toJson())),
            anchor: anchor,
          );
          final witnesses = registry.records.where((r) => r.deviceId == w.id);
          expect(witnesses.length, lessThanOrEqualTo(kMaxRecordsPerDevice + 2));
          expect(
            witnesses.map((r) => r.kind).toSet(),
            DeviceKind.values.toSet(),
          );
          expect((await a.viewOf(registry)).device(w.id), isNull);
          await expectLater(
            w.viewOf(registry),
            throwsA(isA<RegistryException>()),
          );
          // Reintroducing a clean-looking history cannot rehabilitate the id.
          registry = await registry.merge(crowded, anchor: anchor);
          await expectLater(
            w.viewOf(registry),
            throwsA(isA<RegistryException>()),
          );
        }
      },
    );
  }

  test(
    'a conflicting anchor retains both witnesses beyond its ordinary quota',
    () async {
      final mobileHistory = [
        for (var seq = 1; seq <= 16; seq++) await record(a, seq: seq),
      ];
      var registry = await base.withDeclarations(
        records: mobileHistory,
        anchor: anchor,
      );
      final web = await record(a, kind: DeviceKind.web);
      registry = await registry.withRecord(web, anchor: anchor);
      expect(registry.recordByDigest(mobileHistory.last.digest), isNotNull);
      expect(registry.recordByDigest(web.digest), isNotNull);
      expect(registry.records.where((r) => r.deviceId == a.id), hasLength(17));
      registry = await DeviceRegistry.fromLocalStoreJson(
        jsonDecode(jsonEncode(registry.toLocalStoreJson())),
        anchor: anchor,
      );
      final clean = await DeviceRegistry.empty(kListId)
          .withRecord(mobileHistory.last);
      registry = await registry.merge(clean, anchor: anchor);
      await expectLater(a.viewOf(registry), throwsA(isA<RegistryException>()));
      expect(registry.recordByDigest(web.digest), isNotNull);
    },
  );

  Future<List<List<DeviceRecord>>> junkPairs(String id, int count) async => [
    for (var i = 0; i < count; i++)
      [
        await record(await Phone.create(id, 'nora', 10 + i)),
        await record(
          await Phone.create(id, 'nora', 10 + i),
          kind: DeviceKind.web,
        ),
      ],
  ];

  test(
    'nine self-signed pairs merge without throwing or splitting a pair',
    () async {
      final pairs = await junkPairs(w.id, 9);
      final first = await DeviceRegistry.empty(kListId)
          .withDeclarations(records: pairs.take(8).expand((pair) => pair));
      final last = await DeviceRegistry.empty(kListId)
          .withDeclarations(records: pairs.last);
      for (final (left, right) in [(first, last), (last, first)]) {
        final merged = await left.merge(right);
        expect(merged.records.length, 16);
        for (final pair in pairs) {
          expect(
            merged.recordByDigest(pair.first.digest) != null,
            merged.recordByDigest(pair.last.digest) != null,
          );
        }
      }
    },
  );

  test('eight foreign pairs using anchor id cannot evict authentic root or revocation evidence', () async {
    final pairs = await junkPairs(a.id, 8);
    final attack = await DeviceRegistry.empty(kListId)
        .withDeclarations(records: pairs.expand((pair) => pair));
    final revoked = await base.withRevocation(
      await Revocation.create(keys: a.keys, by: ra, deviceId: b.id),
      anchor: anchor,
    );
    for (final merged in [
      await revoked.merge(attack, anchor: anchor),
      await attack.merge(revoked, anchor: anchor),
    ]) {
      for (final registry in [
        merged,
        await DeviceRegistry.fromJsonVerified(
          jsonDecode(jsonEncode(merged.toJson())),
          anchor: anchor,
        ),
        await DeviceRegistry.fromLocalStoreJson(
          jsonDecode(jsonEncode(merged.toLocalStoreJson())),
          anchor: anchor,
        ),
      ]) {
        expect(registry.recordByDigest(ra.digest), isNotNull);
        final view = await a.viewOf(registry);
        expect(view.self.recordDigest, ra.digest);
        expect(view.revokedByOthers, isFalse);
        expect(view.revoked, contains(b.id));
        expect(registry.revocations, hasLength(1));
        for (final pair in pairs) {
          expect(
            registry.recordByDigest(pair.first.digest) != null,
            registry.recordByDigest(pair.last.digest) != null,
          );
        }
      }
    }
  });

  test('nine junk pairs cannot prevent merging a legitimate change', () async {
    final pairs = await junkPairs(a.id, 9);
    final first = await DeviceRegistry.empty(kListId)
        .withDeclarations(records: pairs.take(8).expand((pair) => pair));
    final newer = await record(b, seq: 2, person: 'nora');
    final legitimate = await base.withDeclarations(
      records: [newer, ...pairs.last],
      vouches: [await vouch(a, ra, newer)],
      anchor: anchor,
    );
    for (final merged in [
      await first.merge(legitimate, anchor: anchor),
      await legitimate.merge(first, anchor: anchor),
    ]) {
      expect((await a.viewOf(merged)).member(b.id)!.recordDigest, newer.digest);
      expect(merged.recordByDigest(ra.digest), isNotNull);
    }
  });

  test('revoking sponsor frees reservations of its nine conflicting identities (N1)', () async {
    final pairs = await junkPairs(w.id, 9);
    var registry = await base.withDeclarations(
      records: [ri, ...pairs.expand((pair) => pair)],
      vouches: [
        await vouch(a, ra, ri),
        for (final pair in pairs) await vouch(intruder, ri, pair.first),
      ],
      anchor: anchor,
    );
    expect(
      pairs.every(
        (p) => p.every((r) => registry.recordByDigest(r.digest) != null),
      ),
      isTrue,
    );
    final filler = await DeviceRegistry.empty(kListId).withDeclarations(
      records: [
        for (var i = 0; i < 64; i++)
          await DeviceRecord.create(
            keys: intruder.keys,
            listId: kListId,
            deviceId: 'fill-$i',
            personId: 'aritz',
          ),
      ],
    );
    registry = await registry.merge(filler, anchor: anchor);
    registry = await registry.withRevocation(
      await Revocation.create(keys: a.keys, by: ra, deviceId: intruder.id),
      anchor: anchor,
    );
    expect(
      pairs.any((p) => registry.recordByDigest(p.first.digest) == null),
      isTrue,
    );
    for (final pair in pairs) {
      expect(
        registry.recordByDigest(pair.first.digest) != null,
        registry.recordByDigest(pair.last.digest) != null,
      );
    }
    expect((await a.viewOf(registry)).revoked, contains(intruder.id));
    final newer = await record(b, seq: 2, person: 'nora');
    registry = await registry.withDeclarations(
      records: [newer],
      vouches: [await vouch(a, ra, newer)],
      anchor: anchor,
    );
    expect((await a.viewOf(registry)).member(b.id)!.recordDigest, newer.digest);
    expect(registry.revocations, hasLength(1));
  });

  test('same Ed25519 with another X25519 cannot turn an approved web into mobile authority', () async {
    final changedKeys = await DeviceKeys.fromSeedsForTesting(
      signingSeed: List.filled(32, 103),
      agreementSeed: List.filled(32, 44),
      serviceCredential: List.filled(32, 0),
    );
    final fakePhone = Phone(w.id, w.self, changedKeys);
    final mobile = await record(fakePhone, seq: 16);
    expect(await mobile.verify(), isTrue);
    expect(mobile.keys.signing, rw.keys.signing);
    expect(mobile.keys.agreement, isNot(rw.keys.agreement));
    final revoke = await Revocation.create(
      keys: changedKeys,
      by: mobile,
      deviceId: b.id,
    );
    final fakeVouch = await vouch(fakePhone, mobile, ri);
    final remote = await DeviceRegistry.empty(kListId).withDeclarations(
      records: [mobile, ri],
      vouches: [fakeVouch],
      revocations: [revoke],
    );
    for (var merged in [
      await base.merge(remote, anchor: anchor),
      await remote.merge(base, anchor: anchor),
    ]) {
      merged = await DeviceRegistry.fromLocalStoreJson(
        jsonDecode(jsonEncode(merged.toLocalStoreJson())),
        anchor: anchor,
      );
      final view = await a.viewOf(merged);
      expect(view.revoked, contains(w.id));
      expect(view.device(w.id), isNull);
      expect(view.member(b.id), isNotNull);
      expect(view.device(intruder.id), isNull);
      expect(merged.revocations, isEmpty);
      expect(merged.vouches.where((v) => v.by == w.id), isEmpty);
      await expectLater(
        fakePhone.viewOf(merged),
        throwsA(isA<RegistryException>()),
      );
      await expectLater(
        merged.withRevocation(revoke),
        throwsA(isA<RegistryException>()),
      );
    }
  });

  test(
    'global pressure preserves local conflict memory after losing witnesses',
    () async {
      final pairs = <List<DeviceRecord>>[];
      for (var i = 0; i < 34; i++) {
        final phone = await Phone.create('conflict-$i', 'nora', 20 + i);
        pairs.add([
          await record(phone),
          await record(phone, kind: DeviceKind.web),
        ]);
      }
      final first = await base.withDeclarations(
        records: pairs.take(30).expand((p) => p),
        vouches: [
          for (final pair in pairs.take(30)) await vouch(a, ra, pair.first),
        ],
        anchor: anchor,
      );
      final last = await DeviceRegistry.empty(kListId).withDeclarations(
        records: [ra, rb, ...pairs.skip(30).expand((p) => p)],
        vouches: [
          await vouch(a, ra, rb),
          for (final pair in pairs.skip(30)) await vouch(b, rb, pair.first),
        ],
        anchor: anchor,
      );
      var merged = await first.merge(last, anchor: anchor);
      expect(merged.records.length, lessThanOrEqualTo(kMaxRegistryRecords));
      expect(merged.recordByDigest(ra.digest), isNotNull);
      final lost = pairs.firstWhere(
        (p) => merged.recordByDigest(p.last.digest) == null,
      );
      final localJson = jsonDecode(jsonEncode(merged.toLocalStoreJson()));
      merged = await DeviceRegistry.fromLocalStoreJson(
        localJson,
        anchor: anchor,
      );
      merged = await merged.withRevocation(
        await Revocation.create(keys: a.keys, by: ra, deviceId: b.id),
        anchor: anchor,
      );
      final clean = await DeviceRegistry.empty(kListId).withDeclarations(
        records: [ra, lost.first],
        vouches: [await vouch(a, ra, lost.first)],
        anchor: anchor,
      );
      merged = await merged.merge(clean, anchor: anchor);
      expect(merged.recordByDigest(lost.first.digest), isNotNull);
      expect(merged.recordByDigest(lost.last.digest), isNull);
      await expectLater(
        merged.viewFor(
          me: lost.first.deviceId,
          mySigningKey: lost.first.keys.signing,
          livePeople: kPeople,
        ),
        throwsA(isA<RegistryException>()),
      );
      expect((await a.viewOf(merged)).device(lost.first.deviceId), isNull);
      expect(merged.toJson().containsKey('localTypeConflicts'), isFalse);

      // An unsigned mark delivered in shared JSON must have no effect.
      final injected = base.toJson()
        ..['localTypeConflicts'] = [
          '${a.id}\u0000${encodeBase64Url(ra.keys.signing)}',
        ];
      final shared = await DeviceRegistry.fromJsonVerified(
        injected,
        anchor: anchor,
      );
      expect((await a.viewOf(shared)).self.recordDigest, ra.digest);
    },
  );

  test(
    'web vouches and revocations are ignored with every external mobile root',
    () async {
      final fake = await vouch(w, rw, ri);
      final tail = await DeviceRecord.create(
        keys: intruder.keys,
        listId: kListId,
        deviceId: 'chain-tail',
        personId: 'aritz',
        seq: 16,
      );
      final secondHop = await vouch(intruder, ri, tail);
      final revokeB = await Revocation.create(
        keys: w.keys,
        by: rw,
        deviceId: b.id,
      );
      final revokeA = await Revocation.create(
        keys: w.keys,
        by: rw,
        deviceId: a.id,
      );
      final json = base.toJson();
      json['records'] = [
        ...base.records.map((r) => r.toJson()),
        ri.toJson(),
        tail.toJson(),
      ];
      json['vouches'] = [
        ...base.vouches.map((v) => v.toJson()),
        fake.toJson(),
        secondHop.toJson(),
      ];
      json['revocations'] = [revokeA.toJson(), revokeB.toJson()];
      final registry = await DeviceRegistry.fromJsonVerified(
        json,
        anchor: anchor,
      );
      expect(registry.vouches.length, base.vouches.length + 1);
      expect(registry.revocations, isEmpty);
      for (final root in [a, b]) {
        final view = await root.viewOf(registry);
        expect(view.device(intruder.id), isNull);
        expect(view.device(tail.deviceId), isNull);
        expect(view.pending, isEmpty);
        expect(view.detached, isEmpty);
        expect(view.revoked, isEmpty);
        expect(view.revokedByOthers, isFalse);
        expect(view.epoch, 1);
        expect(view.everMembers, isNot(contains(intruder.id)));
        expect(webStatusIn(view, w.id), WebDeviceStatus.confirmed);
        expect(view.entitled(w.id, 'aritz'), isNull);
        expect(view.relayable(w.id, 'aritz'), isNull);
      }
      await expectLater(
        base.withDeclarations(records: [ri], vouches: [fake]),
        throwsA(isA<RegistryException>()),
      );
      await expectLater(
        base.withRevocation(revokeA),
        throwsA(isA<RegistryException>()),
      );
      final webView = await w.viewOf(registry);
      expect(webView.members, [w.id]);
      expect(webView.selfEntitled('aritz'), isFalse);
      expect(webView.entitled(w.id, 'aritz'), isNull);
      expect(webView.relayable(w.id, 'aritz'), isNull);
      expect(
        () => webStatusIn(webView, w.id),
        throwsA(isA<RegistryException>()),
      );
    },
  );

  test('web cannot approve a changed local record (N7) or create detached confirmation', () async {
    final newer = await record(a, seq: 2, person: 'leo');
    final fake = await vouch(w, rw, newer);
    final json = base.toJson()
      ..['records'] = [...base.records.map((r) => r.toJson()), newer.toJson()]
      ..['vouches'] = [...base.vouches.map((v) => v.toJson()), fake.toJson()];
    final restored = await DeviceRegistry.fromJsonVerified(
      json,
      anchor: anchor,
    );
    final view = await a.viewOf(restored);
    expect(view.selfApproved, isFalse);
    expect(view.selfEntitled('nora'), isFalse);
    expect(view.detached, isEmpty);
  });

  test(
    'web is excluded from lax surprise relay and policy authority too',
    () async {
      for (final person in ['nora', null]) {
        final phone = await Phone.create('other-phone', person, 5);
        final rp = await record(phone);
        final registry = await base.withDeclarations(
          records: [rp],
          vouches: [
            await vouch(a, ra, rp),
            await vouch(phone, rp, ra),
            await vouch(phone, rp, rw),
          ],
        );
        final view = await phone.viewOf(registry);
        expect(view.member(w.id), isNotNull);
        expect(view.entitled(w.id, 'nora'), isNull);
        expect(view.relayable(w.id, 'nora'), isNull);
        expect(view.entitledDevices('nora'), isNot(contains(w.id)));
      }
    },
  );

  test(
    'external root reports active, pending, orphan, revoked and unknown web',
    () async {
      final changed = await changePerson(
        registry: base,
        view: await w.viewOf(base),
        myKeys: w.keys,
        personId: 'leo',
      );
      final currentWeb = changed.registry.records.singleWhere(
        (r) => r.deviceId == w.id && r.seq == 2,
      );
      expect(currentWeb.kind, DeviceKind.web);
      expect(currentWeb.toJson()['k'], 'web');
      expect(await currentWeb.verify(), isTrue);
      expect(
        webStatusIn(await a.viewOf(changed.registry), w.id),
        WebDeviceStatus.pending,
      );
      expect(
        webStatusIn(await a.viewOf(base), 'unknown-web'),
        WebDeviceStatus.unknown,
      );
      final revoked = await revokeDevice(
        registry: base,
        view: await a.viewOf(base),
        myKeys: a.keys,
        deviceId: w.id,
      );
      expect(
        webStatusIn(await a.viewOf(revoked.registry), w.id),
        WebDeviceStatus.revoked,
      );
    },
  );

  for (final chain in [false, true]) {
    test(
      '${chain ? 'chain' : 'star'}: revoked web host, orphan and individual confirmation',
      () async {
        var registry = await DeviceRegistry.empty(kListId).withDeclarations(
          records: [ra, rb, rw],
          vouches: [
            await vouch(a, ra, rb),
            await vouch(b, rb, ra),
            await vouch(b, rb, rw),
            if (!chain) await vouch(a, ra, rw),
          ],
        );
        final change = await revokeDevice(
          registry: registry,
          view: await a.viewOf(registry),
          myKeys: a.keys,
          deviceId: b.id,
        );
        registry = change.registry;
        final root = await a.viewOf(registry);
        expect(
          webStatusIn(root, w.id),
          chain ? WebDeviceStatus.pending : WebDeviceStatus.confirmed,
        );
        expect(change.orphans.map((d) => d.deviceId), chain ? [w.id] : isEmpty);
        expect(root.pending, isEmpty); // Orphans are not pending members (N1).
        expect(root.detached, isEmpty);
        expect((await b.viewOf(registry)).revokedByOthers, isTrue);
        expect(root.epoch, 2);
        final approved = await approveDevice(
          registry: registry,
          view: root,
          myKeys: a.keys,
          record: rw,
        );
        final after = await a.viewOf(approved.registry);
        expect(webStatusIn(after, w.id), WebDeviceStatus.confirmed);
        expect(after.entitled(w.id, 'leo'), isNull);
      },
    );
  }

  test(
    'changing a mobile person never asks to vouch a web for surprises',
    () async {
      final changed = await changePerson(
        registry: base,
        view: await a.viewOf(base),
        myKeys: a.keys,
        personId: 'leo',
      );
      expect(changed.orphans.map((d) => d.deviceId), isNot(contains(w.id)));
      expect(
        (await a.viewOf(changed.registry)).member(w.id)!.kind,
        DeviceKind.web,
      );
    },
  );

  test('full registry: web declarations protect no junk from eviction; restore stays ambiguous', () async {
    final junk = <DeviceRecord>[];
    final fakeVouches = <Vouch>[];
    final fakeRevokes = <Revocation>[];
    for (var i = 0; i < 61; i++) {
      final r = await DeviceRecord.create(
        keys: intruder.keys,
        listId: kListId,
        deviceId: 'junk-$i',
        personId: 'aritz',
        seq: 16,
      );
      junk.add(r);
      if (i < 32) {
        fakeVouches.add(await vouch(w, rw, r));
        fakeRevokes.add(
          await Revocation.create(keys: w.keys, by: rw, deviceId: r.deviceId),
        );
      }
    }
    final fullJson = base.toJson()
      ..['records'] = [
        ...base.records.map((r) => r.toJson()),
        ...junk.map((r) => r.toJson()),
      ]
      ..['vouches'] = [
        ...base.vouches.map((v) => v.toJson()),
        ...fakeVouches.map((v) => v.toJson()),
      ]
      ..['revocations'] = fakeRevokes.map((r) => r.toJson()).toList();
    var full = await DeviceRegistry.fromJsonVerified(fullJson, anchor: anchor);
    expect(full.records.length, 64);
    expect((await a.viewOf(full)).epoch, 1);
    final clean = await base.withDeclarations(
      records: [ri],
      vouches: [await vouch(a, ra, ri)],
    );
    full = await full.merge(clean, anchor: anchor);
    expect(full.records.length, 64);
    expect((await a.viewOf(full)).member(intruder.id), isNotNull);
    expect(
      full.records.where((r) => r.deviceId.startsWith('junk-')).length,
      60,
    );
    expect(full.revocations, isEmpty);
    final downgrade = await record(w, seq: 2);
    full = await full.withRecord(downgrade, anchor: anchor);
    full = await DeviceRegistry.fromJsonVerified(full.toJson(), anchor: anchor);
    final restored = await a.viewOf(full);
    expect(restored.revoked, contains(w.id));
    expect(restored.device(w.id), isNull);
    await expectLater(w.viewOf(full), throwsA(isA<RegistryException>()));
  });

  test(
    'web cannot host, seal family keys, or emit family/surprise packages',
    () async {
      final webView = await w.viewOf(base);
      expect(
        () => PairingHost.start(base, webView),
        throwsA(isA<PairingException>()),
      );
      expect(
        () => KeyBundle.sealFamilyKey(
          sender: w.keys,
          view: webView,
          toDevice: a.id,
          epoch: 1,
          familyKey: FamilyKey(List.filled(32, 9)),
        ),
        throwsA(isA<KeyBundleException>()),
      );
      for (final scope in [KeyScope.family, KeyScope.surprise('nora')]) {
        final bundle = await KeyBundle.sealForTesting(
          sender: w.keys,
          fromDevice: w.id,
          toDevice: a.id,
          senderRecord: rw.digest,
          recipientRecord: ra.digest,
          recipientAgreementKey: ra.keys.agreement,
          listId: kListId,
          scope: scope,
          epoch: 1,
          key: List.filled(32, 9),
        );
        final view = await a.viewOf(base);
        if (scope == KeyScope.family) {
          await expectLater(
            bundle.openFamilyKey(mine: a.keys, view: view),
            throwsA(isA<KeyBundleException>()),
          );
        } else {
          await expectLater(
            bundle.openSurpriseKey(mine: a.keys, view: view),
            throwsA(isA<KeyBundleException>()),
          );
        }
      }
    },
  );

  test(
    'mobile family package addressed to web opens with its external root view',
    () async {
      final view = await a.viewOf(base);
      final key = FamilyKey(List.filled(32, 9));
      final bundle = await KeyBundle.sealFamilyKey(
        sender: a.keys,
        view: view,
        toDevice: w.id,
        epoch: 1,
        familyKey: key,
      );
      expect(
        (await bundle.openFamilyKey(mine: w.keys, view: view)).bytes,
        key.bytes,
      );
      await expectLater(
        bundle.openFamilyKey(mine: b.keys, view: view),
        throwsA(isA<KeyBundleException>()),
      );
      final forMobile = await KeyBundle.sealFamilyKey(
        sender: a.keys,
        view: view,
        toDevice: b.id,
        epoch: 1,
        familyKey: key,
      );
      // External views are a web facility; mobile opening still requires its own view.
      await expectLater(
        forMobile.openFamilyKey(mine: b.keys, view: view),
        throwsA(isA<KeyBundleException>()),
      );
      expect(
        (await forMobile.openFamilyKey(
          mine: b.keys,
          view: await b.viewOf(base),
        )).bytes,
        key.bytes,
      );
      final revoked = await revokeDevice(
        registry: base,
        view: view,
        myKeys: a.keys,
        deviceId: w.id,
      );
      await expectLater(
        bundle.openFamilyKey(
          mine: w.keys,
          view: await a.viewOf(revoked.registry),
        ),
        throwsA(isA<KeyBundleException>()),
      );
    },
  );

  test(
    'web rejects fresh family packages through a revoked external root',
    () async {
      final revoked = await base.withRevocation(
        await Revocation.create(keys: b.keys, by: rb, deviceId: a.id),
        anchor: anchor,
      );
      final view = await a.viewOf(revoked);
      expect(view.revokedByOthers, isTrue);
      expect(view.member(a.id), isNotNull);
      expect(webStatusIn(view, w.id), WebDeviceStatus.confirmed);
      final bundle = await KeyBundle.sealForTesting(
        sender: a.keys,
        fromDevice: a.id,
        toDevice: w.id,
        senderRecord: ra.digest,
        recipientRecord: rw.digest,
        recipientAgreementKey: rw.keys.agreement,
        listId: kListId,
        scope: KeyScope.family,
        epoch: 1,
        key: List.filled(32, 9),
        audience: view.members,
      );
      // Prove the new package is valid; only the revocation makes it inadmissible.
      expect(
        (await bundle.openFamilyKey(
          mine: w.keys,
          view: await a.viewOf(base),
        )).bytes,
        List.filled(32, 9),
      );
      await expectLater(
        bundle.openFamilyKey(mine: w.keys, view: view),
        throwsA(isA<KeyBundleException>()),
      );
    },
  );

  group('web pairing checks precede nonce disclosure', () {
    final invite = encodeBase64Url(List.generate(16, (i) => i));
    Future<PairingHost> host() async => PairingHost.start(
      base,
      await a.viewOf(base),
      expectWeb: true,
      inviteId: invite,
      guestPerson: 'nora',
      expectedFingerprint: webPairingFingerprint(
        invite,
        w.keys.publicKeys.signing,
        w.keys.publicKeys.agreement,
      ),
    );

    test(
      'valid web answer retains proof but only mobile vouch enters registry',
      () async {
        final session = await host();
        final join = await joinPairing(
          offer: session.offer,
          keys: w.keys,
          deviceId: 'new-web',
          personId: 'nora',
          kind: DeviceKind.web,
        );
        expect(join.registry.vouches, isEmpty);
        final answer = PairingAnswer.fromJson(join.answer.toJson());
        final reveal = await session.receive(answer);
        expect(join.codeFor(reveal), session.code);
        final accepted = await acceptPairing(
          registry: base,
          view: await a.viewOf(base),
          myKeys: a.keys,
          session: session,
          confirmedPersonId: 'nora',
        );
        final view = await a.viewOf(accepted.registry);
        expect(view.member('new-web')!.kind, DeviceKind.web);
        expect(
          accepted.registry.vouches.where((v) => v.by == 'new-web'),
          isEmpty,
        );
        expect(webStatusIn(view, 'new-web'), WebDeviceStatus.confirmed);
      },
    );

    test('changed signing key, agreement key, person or kind are rejected without spending response', () async {
      final changedSigning = await DeviceKeys.fromSeedsForTesting(
        agreementSeed: List.filled(32, 3),
        signingSeed: List.filled(32, 104),
        serviceCredential: List.filled(32, 0),
      );
      final changedAgreement = await DeviceKeys.fromSeedsForTesting(
        agreementSeed: List.filled(32, 4),
        signingSeed: List.filled(32, 103),
        serviceCredential: List.filled(32, 0),
      );
      for (final (keys, person, kind) in [
        (changedSigning, 'nora', DeviceKind.web),
        (changedAgreement, 'nora', DeviceKind.web),
        (w.keys, 'leo', DeviceKind.web),
        (w.keys, 'nora', DeviceKind.mobile),
      ]) {
        final session = await host();
        final bad = await joinPairing(
          offer: session.offer,
          keys: keys,
          deviceId: 'new-web',
          personId: person,
          kind: kind,
        );
        expect(await bad.answer.guest.verify(), isTrue);
        await expectLater(
          session.receive(bad.answer),
          throwsA(isA<PairingException>()),
        );
        expect(session.answer, isNull);
        expect(() => session.code, throwsStateError);
        final good = await joinPairing(
          offer: session.offer,
          keys: w.keys,
          deviceId: 'new-web',
          personId: 'nora',
          kind: DeviceKind.web,
        );
        expect(good.codeFor(await session.receive(good.answer)), session.code);
      }
    });

    test('normal flow rejects a valid web answer', () async {
      final session = PairingHost.start(base, await a.viewOf(base));
      final join = await joinPairing(
        offer: session.offer,
        keys: w.keys,
        deviceId: 'new-web',
        personId: 'nora',
        kind: DeviceKind.web,
      );
      await expectLater(
        session.receive(join.answer),
        throwsA(isA<PairingException>()),
      );
      expect(session.answer, isNull);
    });

    test(
      'web flow requires QR fingerprint, invite and chosen live person',
      () async {
        final view = await a.viewOf(base);
        expect(
          () => PairingHost.start(base, view, expectWeb: true),
          throwsA(isA<PairingException>()),
        );
        expect(
          () => PairingHost.start(
            base,
            view,
            expectWeb: true,
            inviteId: invite,
            guestPerson: 'missing',
            expectedFingerprint: encodeBase64Url(List.filled(16, 0)),
          ),
          throwsA(isA<PairingException>()),
        );
        expect(
          () => webPairingFingerprint(
            'short',
            rw.keys.signing,
            rw.keys.agreement,
          ),
          throwsA(isA<PairingException>()),
        );
        expect(
          () => webPairingFingerprint(invite, [1], rw.keys.agreement),
          throwsA(isA<PairingException>()),
        );
      },
    );
  });

  group('reservations and local marks follow N1', () {
    // Distinct keys for many devices (Phone.create only has ~55 seeds).
    Future<Phone> manyPhone(String id, int n) async => Phone(
      id,
      'nora',
      await DeviceKeys.fromSeedsForTesting(
        agreementSeed: [n % 256, n ~/ 256, ...List.filled(30, 0xa1)],
        signingSeed: [n % 256, n ~/ 256, ...List.filled(30, 0xb2)],
        serviceCredential: [n % 256, n ~/ 256, ...List.filled(30, 0xc3)],
      ),
    );

    Future<Map<String, Object?>> summary(
      Phone phone,
      DeviceRegistry registry,
    ) async {
      final view = await phone.viewOf(registry);
      return {
        'self': view.self.recordDigest,
        'members': view.members,
        'revoked': view.revoked.toList()..sort(),
        'byOthers': view.revokedByOthers,
        'epoch': view.epoch,
        'pending': [for (final d in view.pending) d.recordDigest],
        'detached': [for (final d in view.detached) d.recordDigest],
      };
    }

    Future<List<DeviceRegistry>> roundTrips(DeviceRegistry registry) async => [
      registry,
      await DeviceRegistry.fromJsonVerified(
        jsonDecode(jsonEncode(registry.toJson())),
        anchor: anchor,
      ),
      await DeviceRegistry.fromLocalStoreJson(
        jsonDecode(jsonEncode(registry.toLocalStoreJson())),
        anchor: anchor,
      ),
    ];

    // A anchor; thief T revoked by A; chain T->X1->...->X62 and T revokes
    // X62. The 64 records A/T/X fill the registry on their own.
    late DeviceRecord rt;
    late DeviceRegistry revokedThief;
    late DeviceRegistry attack;
    setUp(() async {
      rt = await record(intruder);
      revokedThief = await base.withDeclarations(
        records: [rt],
        vouches: [await vouch(a, ra, rt)],
        revocations: [
          await Revocation.create(keys: a.keys, by: ra, deviceId: intruder.id),
        ],
        anchor: anchor,
      );
      final phones = [
        for (var i = 1; i <= 62; i++) await manyPhone('chain-$i', 1000 + i),
      ];
      final xs = [for (final p in phones) await record(p)];
      attack = await DeviceRegistry.empty(kListId).withDeclarations(
        records: [ra, rt, ...xs],
        vouches: [
          await vouch(a, ra, rt),
          await vouch(intruder, rt, xs.first),
          for (var i = 0; i < 61; i++) await vouch(phones[i], xs[i], xs[i + 1]),
        ],
        revocations: [
          await Revocation.create(
            keys: intruder.keys,
            by: rt,
            deviceId: xs.last.deviceId,
          ),
        ],
      );
      expect(attack.records, hasLength(kMaxRegistryRecords));
    });

    test(
      'attack (N1): a revocation inside a branch hanging from a revoked thief '
      'reserves nothing and cannot evict a family phone',
      () async {
        final before = await summary(b, revokedThief);
        for (final merged in [
          await revokedThief.merge(attack, anchor: anchor),
          await attack.merge(revokedThief, anchor: anchor),
        ]) {
          for (final registry in await roundTrips(merged)) {
            expect(registry.records.length, kMaxRegistryRecords);
            expect(registry.recordByDigest(rb.digest), isNotNull);
            expect(registry.recordByDigest(rw.digest), isNotNull);
            expect(await summary(b, registry), before);
            final view = await a.viewOf(registry);
            expect(view.member(b.id)!.recordDigest, rb.digest);
            expect(view.revoked, {intruder.id});
            expect(webStatusIn(view, w.id), WebDeviceStatus.confirmed);
          }
        }
      },
    );

    test(
      'a legitimate family revocation is still kept with the registry full',
      () async {
        final legit = await revokedThief.withRevocation(
          await Revocation.create(keys: b.keys, by: rb, deviceId: w.id),
          anchor: anchor,
        );
        final before = await summary(b, legit);
        for (final merged in [
          await legit.merge(attack, anchor: anchor),
          await attack.merge(legit, anchor: anchor),
        ]) {
          for (final registry in await roundTrips(merged)) {
            expect(registry.records.length, kMaxRegistryRecords);
            expect(registry.recordByDigest(rw.digest), isNotNull);
            expect(
              registry.revocations.where(
                (r) => r.by == b.id && r.deviceId == w.id,
              ),
              hasLength(1),
            );
            expect(
              registry.revocations.where(
                (r) => r.by == a.id && r.deviceId == intruder.id,
              ),
              hasLength(1),
            );
            expect((await a.viewOf(registry)).revoked, {intruder.id, w.id});
            expect(await summary(b, registry), before);
          }
        }
      },
    );

    test('batches of incompatible vouched identities never keep more than 64 marks', () async {
      var registry = base;
      var n = 2000;
      var created = 0;
      for (var round = 0; round < 6; round++) {
        final sponsor = await manyPhone('sponsor-$round', n++);
        final rs = await record(sponsor);
        final pairs = <List<DeviceRecord>>[];
        for (var i = 0; i < 20; i++) {
          final phone = await manyPhone('mixed-$round-$i', n++);
          pairs.add([
            await record(phone),
            await record(phone, kind: DeviceKind.web),
          ]);
        }
        created += pairs.length;
        final remote = await DeviceRegistry.empty(kListId).withDeclarations(
          records: [ra, rs, ...pairs.expand((p) => p)],
          vouches: [
            await vouch(a, ra, rs),
            for (final p in pairs) await vouch(sponsor, rs, p.first),
          ],
        );
        registry = await registry.merge(remote, anchor: anchor);
        final view = await a.viewOf(registry);
        for (final p in pairs) {
          expect(view.device(p.first.deviceId), isNull);
        }
        registry = await registry.withRevocation(
          await Revocation.create(keys: a.keys, by: ra, deviceId: sponsor.id),
          anchor: anchor,
        );
        for (final r in await roundTrips(registry)) {
          final marks = r.toLocalStoreJson()['localTypeConflicts'] as List;
          expect(marks.length, lessThanOrEqualTo(kMaxRegistryRecords));
        }
        registry = (await roundTrips(registry)).last;
      }
      expect(created, greaterThan(kMaxRegistryRecords));
      expect((await a.viewOf(registry)).members, [a.id, b.id, w.id]..sort());
    });

    test(
      'every linked identity in conflict stays ambiguous after save, restore '
      'and merges without its witness, even when pressure evicts witnesses',
      () async {
        final pairs = <List<DeviceRecord>>[];
        for (var i = 0; i < 34; i++) {
          final phone = await manyPhone('conflict-$i', 3000 + i);
          pairs.add([
            await record(phone),
            await record(phone, kind: DeviceKind.web),
          ]);
        }
        final first = await base.withDeclarations(
          records: pairs.take(30).expand((p) => p),
          vouches: [
            for (final pair in pairs.take(30)) await vouch(a, ra, pair.first),
          ],
          anchor: anchor,
        );
        final last = await DeviceRegistry.empty(kListId).withDeclarations(
          records: [ra, rb, ...pairs.skip(30).expand((p) => p)],
          vouches: [
            await vouch(a, ra, rb),
            for (final pair in pairs.skip(30)) await vouch(b, rb, pair.first),
          ],
          anchor: anchor,
        );
        final merged = await first.merge(last, anchor: anchor);
        expect(merged.records.length, kMaxRegistryRecords);
        bool kept(DeviceRecord r) => merged.recordByDigest(r.digest) != null;
        expect(pairs.any((p) => !kept(p.first) || !kept(p.last)), isTrue);
        // Each conflicting identity keeps at least one record, so its mark
        // is never pruned.
        expect(pairs.every((p) => kept(p.first) || kept(p.last)), isTrue);
        expect(
          (merged.toLocalStoreJson()['localTypeConflicts'] as List).length,
          pairs.length,
        );
        for (final pair in pairs) {
          var restored = await DeviceRegistry.fromLocalStoreJson(
            jsonDecode(jsonEncode(merged.toLocalStoreJson())),
            anchor: anchor,
          );
          final clean = await DeviceRegistry.empty(kListId).withDeclarations(
            records: [ra, pair.first],
            vouches: [await vouch(a, ra, pair.first)],
            anchor: anchor,
          );
          for (final other in [clean, base, clean]) {
            restored = await restored.merge(other, anchor: anchor);
            restored = await DeviceRegistry.fromLocalStoreJson(
              jsonDecode(jsonEncode(restored.toLocalStoreJson())),
              anchor: anchor,
            );
          }
          expect(
            restored.toLocalStoreJson()['localTypeConflicts'],
            contains(
              '${pair.first.deviceId}\u0000'
              '${encodeBase64Url(pair.first.keys.signing)}',
            ),
          );
          await expectLater(
            restored.viewFor(
              me: pair.first.deviceId,
              mySigningKey: pair.first.keys.signing,
              livePeople: kPeople,
            ),
            throwsA(isA<RegistryException>()),
          );
          expect(
            (await a.viewOf(restored)).device(pair.first.deviceId),
            isNull,
          );
        }
      },
    );
  });
}
