import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/renewal_protocol.dart';

import 'protected_harness.dart';

String _b(int n, [int length = 32]) => encodeBase64Url(List.filled(length, n));
final _source = _b(1, 16);
final _operation = _b(2, 16);
final _bad = throwsA(isA<RenewalProtocolException>());
Map<String, Object?> _copy(Map<String, Object?> m) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(m)) as Map);

class _CountingEd25519 extends DartEd25519 {
  var verifications = 0;
  @override
  Future<bool> verify(List<int> message, {required Signature signature}) {
    verifications++;
    return super.verify(message, signature: signature);
  }
}

class _CountingCryptography extends DartCryptography {
  final algorithm = _CountingEd25519();
  @override
  Ed25519 ed25519() => algorithm;
}

class _Log {
  _Log(this.aritz, this.nora, this.registry);
  final Phone aritz;
  final Phone nora;
  DeviceRegistry registry;
  Phone? observer;
  final List<RenewalCommand> commands = [];
  Map<String, Object?>? state;
  final Set<String> revoked = {};
  var replayIndex = RenewalReplayIndex();
  var operation = _operation;
  var version = 1;
  var revision = 1;
  var target = _b(3, 16);
  var identity = 0;
  RenewalBinding get binding => RenewalBinding(
    listId: kListId,
    operationId: operation,
    sourceSyncId: _source,
    targetSyncId: target,
    revision: revision,
  );
  RenewalLogAnchor get anchor => RenewalLogAnchor(
    sourceSyncId: _source,
    operationId: operation,
    head: commands.last.hash,
    height: commands.length,
  );
  List<String> get participants => [aritz.id, nora.id];
  static Future<_Log> create() async {
    final aritz = await Phone.create('aritz-phone', 'aritz', 1);
    final nora = await Phone.create('nora-phone', 'nora', 2);
    return _Log(aritz, nora, await registryOf([aritz, nora]));
  }

  Map<String, Object?> reservationFields() => {
    'participants': participants,
    'newDeviceId': 'destination-${++identity}',
    'newSigningKey': _b(20 + identity),
    'targetCommitment': _b(4),
    'inventoryCommitment': _b(5),
  };
  Future<RenewalCommand> add(
    RenewalAction action,
    Map<String, Object?> fields, {
    Phone? by,
  }) async {
    final actor = by ?? aritz;
    final c = await RenewalCommand.sign(
      action: action,
      binding: binding,
      sourceVersion: version,
      signerDeviceId: actor.id,
      keys: actor.keys,
      sourceView: await actor.viewOf(registry),
      prev: commands.lastOrNull?.hash,
      fields: fields,
    );
    state = replayRenewalCommand(state, c, revoked, index: replayIndex);
    replayIndex.add(c);
    commands.add(c);
    version++;
    if (action == RenewalAction.revoke) {
      registry = await registry.withRevocation(
        await Revocation.create(
          keys: actor.keys,
          by: await actor.record(),
          deviceId: fields['participantDeviceId'] as String,
        ),
      );
    }
    return c;
  }

  Future<void> reserve() async {
    await add(RenewalAction.reserve, reservationFields());
  }

  RenewalCommand get reservation =>
      commands.firstWhere((c) => c.hash == state!['reservation']);
  Future<void> ready({Phone? by}) async {
    await add(RenewalAction.ready, {'destinationVersion': 1}, by: by);
  }

  Future<void> ack(Phone by, {Phone? destination}) async {
    await add(RenewalAction.ack, {
      'newDeviceId':
          destination?.id ??
          (by.id == reservation.signerDeviceId
              ? reservation.newDeviceId
              : 'mapped-${++identity}'),
      'newSigningKey': destination != null
          ? encodeBase64Url(destination.keys.publicKeys.signing)
          : (by.id == reservation.signerDeviceId
                ? reservation.newSigningKey
                : _b(20 + identity)),
      'destinationVersion': 2,
      'receipt': _b(6),
    }, by: by);
  }

  Future<void> exclude(Phone lost, {Phone? by}) async {
    await add(RenewalAction.exclude, {
      'participantDeviceId': lost.id,
      'loss': true,
      'receipt': _b(7),
    }, by: by);
  }

  Future<void> prepare({Phone? by}) async {
    await add(RenewalAction.prepare, {
      'pendingResources': 0,
      'coverageCommitment': _b(8),
    }, by: by);
  }

  Future<void> confirm({Phone? by}) async {
    await add(RenewalAction.confirm, {
      'snapshotVersion': state!['barrierVersion'],
      'pendingResources': 0,
      'coverageCommitment': _b(9),
    }, by: by);
  }

  Future<void> revoke(Phone target, Phone by) async {
    await add(RenewalAction.revoke, {'participantDeviceId': target.id}, by: by);
  }

  Future<void> replace({Phone? by, bool recover = false}) async {
    final old = target;
    target = _b(40 + revision, 16);
    revision++;
    await add(recover ? RenewalAction.recover : RenewalAction.replace, {
      ...reservationFields(),
      'previousTargetSyncId': old,
    }, by: by);
  }

  List<RenewalLogPage> pages({
    List<RenewalCommand>? served,
    Map<String, Object?>? projection,
    int after = 0,
    int size = 32,
  }) {
    final items = served ?? commands;
    final p = projection ?? state!;
    final result = <RenewalLogPage>[];
    for (var at = after; at < items.length;) {
      var end = at + size < items.length ? at + size : items.length;
      while (utf8
              .encode(
                jsonEncode(
                  items.sublist(at, end).map((c) => c.toJson()).toList(),
                ),
              )
              .length >
          kRenewalLogPageBytes) {
        end--;
      }
      result.add(
        RenewalLogPage.fromJson({
          'sourceSyncId': _source,
          'operationId': operation,
          'head': p['head'],
          'height': p['height'],
          'after': at,
          'next': end == p['height'] ? null : end,
          'commands': items.sublist(at, end).map((c) => c.toJson()).toList(),
        }),
      );
      at = end;
    }
    return result;
  }

  Future<RenewalControl> verify({
    RenewalControl? previous,
    List<RenewalLogPage>? servedPages,
    Map<String, Object?>? projection,
    RenewalLogAnchor? trusted,
    int size = 32,
  }) async => RenewalControl.fromLog(
    listId: kListId,
    sourceSyncId: _source,
    version: version,
    projection: projection ?? state,
    sourceRegistry: registry,
    sourceView: await (observer ?? nora).viewOf(registry),
    anchor: trusted ?? anchor,
    pages: servedPages ?? pages(after: previous?.height ?? 0, size: size),
    previous: previous,
  );
}

void main() {
  late _Log log;
  setUp(() async {
    log = await _Log.create();
  });

  test(
    'canonical Ed25519/hash interoperates with independent Node vector',
    () async {
      await log.reserve();
      expect(
        log.commands.single.toJson()['signature'],
        'T6VkENaIBE0JSqV-VDe-_5kad3RpiMiNZ8sAI0pkeAVT42de9G4Ma5Fdc_60xgu-WkwjXzTDSkpMNm4gRnBKAA',
      );
      expect(
        log.commands.single.hash,
        'JARBEPfhMR4dg2vmD8oyaQixMms_uj5i7bm7sG6WWZw',
      );
      await log.verify();
    },
  );

  test('all signed numeric fields reject doubles, including capability commonFormat', () async {
    await log.reserve();
    final reserve = log.commands.single;
    await log.add(RenewalAction.capability, {'commonFormat': 2});
    final capability = log.commands.last;
    for (final field in ['v', 'revision', 'sourceVersion', 'commonFormat']) {
      final raw = {
        ...capability.toJson(),
        field: (capability.toJson()[field] as int).toDouble(),
      };
      expect(() => RenewalCommand.fromJson(raw), _bad, reason: field);
    }
    await log.ready();
    await log.ack(log.aritz);
    await log.ack(log.nora);
    await log.prepare();
    await log.confirm();
    for (final c in log.commands) {
      for (final field in [
        'destinationVersion',
        'snapshotVersion',
        'pendingResources',
      ]) {
        if (!c.toJson().containsKey(field)) continue;
        expect(
          () => RenewalCommand.fromJson({
            ...c.toJson(),
            field: (c.toJson()[field] as int).toDouble(),
          }),
          _bad,
          reason: field,
        );
      }
    }
    // Exact Dart -> JSON -> Worker persisted JSON -> Dart interoperability vector.
    expect(reserve.hash, 'JARBEPfhMR4dg2vmD8oyaQixMms_uj5i7bm7sG6WWZw');
    const workerSignature =
        'pXSqudZTFRbfF4RSEPq8GsgHx7eJWm-UuguGEhrmWSt06cREtUqkQ1wqZ2UMQDhd1ABN9uZSS6OkfaeQ6mFCAw';
    expect(capability.toJson()['signature'], workerSignature);
    final returned = RenewalCommand.fromJson(
      jsonDecode(jsonEncode(capability.toJson())),
    );
    expect(returned.toJson()['commonFormat'], isA<int>());
    expect(returned.toJson()['signature'], workerSignature);
    await returned.verify(
      binding: log.binding,
      sourceView: await log.nora.viewOf(log.registry),
    );
  });

  test('Nora starts another operation after persisting Aritz abort and revoking him', () async {
    await log.reserve();
    await log.add(RenewalAction.abort, {});
    final accepted = await log.verify();
    log.registry = await log.registry.withRevocation(
      await Revocation.create(
        keys: log.nora.keys,
        by: await log.nora.record(),
        deviceId: log.aritz.id,
      ),
    );
    log.operation = _b(200, 16);
    log.commands.clear();
    log.state = null;
    log.revision = 1;
    log.replayIndex = RenewalReplayIndex();
    await log.add(RenewalAction.reserve, log.reservationFields(), by: log.nora);
    final next = await log.verify(previous: accepted, servedPages: log.pages());
    expect(next.binding.operationId, log.operation);
    expect(next.reservation.signerDeviceId, log.nora.id);
  });

  test('canonical signed prev is mandatory, null only at genesis; strict public format', () async {
    await log.reserve();
    final genesis = log.commands.single;
    await log.ready();
    expect(log.commands.last.prev, genesis.hash);
    expect(genesis.hash, renewalCommandHash(genesis.toJson()));
    await log.verify();
    for (final raw in [
      {...genesis.toJson()}..remove('prev'),
      {...genesis.toJson(), 'prev': 'AAAA'},
      {...genesis.toJson(), 'historyHead': null},
      {...genesis.toJson(), 'privateManifest': {}},
      {...genesis.toJson(), 'sourceVersion': 1.0},
      {...genesis.toJson(), 'signature': 'AAAA'},
      {...genesis.toJson(), 'participants': List.filled(65, 'aritz')},
      {
        ...genesis.toJson(),
        'participants': ['aritz', 'aritz'],
      },
    ]) {
      expect(() => RenewalCommand.fromJson(raw), _bad);
    }
    for (final entry in {
      'prev': _b(30),
      'sourceVersion': 2,
      'newDeviceId': 'substituted',
      'newSigningKey': _b(31),
      'inventoryCommitment': _b(32),
    }.entries) {
      final changed = RenewalCommand.fromJson({
        ...genesis.toJson(),
        entry.key: entry.value,
      });
      await expectLater(
        changed.verify(
          binding: log.binding,
          sourceView: await log.nora.viewOf(log.registry),
        ),
        _bad,
      );
    }
  });

  test('omission, tail truncation, reordering and signed fork fail with and without previous', () async {
    await log.reserve();
    final observed = await log.verify();
    await log.ready();
    await log.ack(log.aritz);
    await log.exclude(log.nora);
    await log.prepare();
    await log.confirm();
    final intact = [...log.commands];
    final fork = await RenewalCommand.sign(
      action: RenewalAction.ready,
      binding: log.binding,
      sourceVersion: intact[1].sourceVersion,
      signerDeviceId: log.aritz.id,
      keys: log.aritz.keys,
      sourceView: await log.aritz.viewOf(log.registry),
      prev: intact[0].hash,
      fields: {'destinationVersion': 2},
    );
    for (final previous in [null, observed]) {
      for (final served in [
        [...intact]..removeAt(2),
        [...intact]..removeLast(),
        [intact[0], intact[2], intact[1], ...intact.skip(3)],
        [intact[0], fork, ...intact.skip(2)],
      ]) {
        // A malicious page may claim a valid next cursor for a missing item.
        // Construct pages with matching shape, then replay catches the gap.
        final p = {...log.state!, 'height': served.length};
        await expectLater(
          log.verify(
            previous: previous,
            trusted: observed.anchor,
            projection: p,
            servedPages: log.pages(
              served: served,
              projection: p,
              after: previous?.height ?? 0,
            ),
          ),
          _bad,
        );
      }
    }
    final firstOnly = replayRenewalCommand(
      null,
      intact.first,
      {},
      index: RenewalReplayIndex(),
    );
    await expectLater(
      log.verify(
        projection: firstOnly,
        servedPages: log.pages(served: [intact.first], projection: firstOnly),
      ),
      _bad,
    );
    // Even a self-consistent old prefix/fork cannot replace a mobile's anchor.
    final forkState = replayRenewalCommand(
      firstOnly,
      fork,
      {},
      index: RenewalReplayIndex()..add(intact.first),
    );
    await expectLater(
      log.verify(
        projection: forkState,
        servedPages: log.pages(
          served: [intact.first, fork],
          projection: forkState,
        ),
      ),
      _bad,
    );
  });

  test('projection is an assertion: hidden mappings, branches, revocations or barrier fail', () async {
    await log.reserve();
    await log.ready();
    await log.ack(log.aritz);
    await log.ack(log.nora);
    await log.prepare();
    await log.replace();
    for (final key in [
      'branches',
      'barrier',
      'barrierVersion',
      'reservation',
      'transfers',
      'participants',
      'needsRevalidation',
    ]) {
      final p = _copy(log.state!);
      p[key] = switch (key) {
        'branches' => <String>[],
        'transfers' => <String, Object?>{log.aritz.id: log.commands.first.hash},
        'participants' => [log.aritz.id],
        'needsRevalidation' => true,
        _ => null,
      };
      await expectLater(log.verify(projection: p), _bad, reason: key);
    }
  });

  test(
    'P1/P2: CAS order, local version floor and complete participant coverage',
    () async {
      await log.reserve();
      final previous = await log.verify();
      await log.ready();
      final good = await log.verify(previous: previous);
      expect(good.version, log.version);
      final savedVersion = log.version;
      log.version = previous.version - 1;
      await expectLater(log.verify(previous: previous), _bad);
      log.version = savedVersion;
      final wrong = RenewalCommand.fromJson({
        ...log.commands.last.toJson(),
        'sourceVersion': 1,
      });
      await expectLater(
        log.verify(servedPages: log.pages(served: [log.commands.first, wrong])),
        _bad,
      );
      final leo = await Phone.create('leo-phone', 'leo', 3);
      log.registry = await registryOf([log.aritz, log.nora, leo]);
      await expectLater(log.verify(), _bad);
    },
  );

  test(
    'pagination and persisted anchor reproduce the same complete projection',
    () async {
      await log.reserve();
      for (var i = 0; i < 70; i++) {
        await log.replace();
      }
      final single = await log.verify(size: 32);
      final paged = await log.verify(size: 7);
      expect(paged.toJson(), single.toJson());
      expect(paged.toJson(), log.state);
      expect(paged.identities.length, 71);
      final persisted = RenewalLogAnchor.fromJson(
        jsonDecode(jsonEncode(single.anchor.toJson())),
      );
      final previous = await log.verify(trusted: persisted);
      await log.ready();
      await log.ack(log.aritz);
      final suffix = await log.verify(previous: previous, trusted: persisted);
      final full = await log.verify(trusted: persisted);
      expect(suffix.toJson(), full.toJson());
      expect(suffix.commands.length, 73);
    },
  );

  test(
    'verified previous checks Ed25519 only on the downloaded suffix',
    () async {
      await log.reserve();
      await log.ready();
      await log.ack(log.aritz);
      final view = await log.nora.viewOf(log.registry);
      final provider = Cryptography.instance;
      final counting = _CountingCryptography();
      Future<RenewalControl> check(RenewalControl? previous) =>
          RenewalControl.fromLog(
            listId: kListId,
            sourceSyncId: _source,
            version: log.version,
            projection: log.state,
            sourceRegistry: log.registry,
            sourceView: view,
            pages: log.pages(after: previous?.height ?? 0),
            anchor: log.anchor,
            previous: previous,
          );
      try {
        Cryptography.instance = counting;
        final previous = await check(null);
        expect(counting.algorithm.verifications, 3);
        Cryptography.instance = provider;
        await log.ack(log.nora);
        counting.algorithm.verifications = 0;
        Cryptography.instance = counting;
        final current = await check(previous);
        expect(counting.algorithm.verifications, 1);
        expect(current.replayedCommandCount, 1);
        counting.algorithm.verifications = 0;
        final unchanged = await check(current);
        expect(counting.algorithm.verifications, 0);
        expect(unchanged.replayedCommandCount, 0);
      } finally {
        Cryptography.instance = provider;
      }
    },
  );

  test('N successive verified extensions replay N transitions, preserve prefixes and recheck changed trust', () async {
    await log.reserve();
    await log.ready();
    await log.ack(log.aritz);
    await log.ack(log.nora);
    await log.prepare();
    final view = await log.nora.viewOf(log.registry);
    Future<RenewalControl> check(RenewalControl? previous) =>
        RenewalControl.fromLog(
          listId: kListId,
          sourceSyncId: _source,
          version: log.version,
          projection: log.state,
          sourceRegistry: log.registry,
          sourceView: view,
          pages: log.pages(after: previous?.height ?? 0),
          anchor: log.anchor,
          previous: previous,
        );
    var current = await check(null);
    final first = current;
    var transitions = current.replayedCommandCount;
    const extensions = 160;
    for (var i = 0; i < extensions; i++) {
      await log.confirm();
      current = await check(current);
      transitions += current.replayedCommandCount;
      expect(current.replayedCommandCount, 1);
    }
    expect(transitions, 5 + extensions);
    expect(first.commands.length, 5);
    expect(first.height, 5);
    expect(() => first.commands.clear(), throwsUnsupportedError);
    // Reusing an older prefix as a fork safely reconstructs its consumed cache.
    final fork = await check(first);
    expect(fork.replayedCommandCount, log.commands.length);
    expect(fork.toJson(), current.toJson());
    // A newly seen unlinked record changes identity-collision inputs even though
    // no signature key changed. Recheck all transitions under the new registry.
    final leo = await Phone.create('unlinked-leo', 'leo', 7);
    log.registry = await log.registry.withRecord(await leo.record());
    final rechecked = await check(current);
    expect(rechecked.replayedCommandCount, log.commands.length);
    expect(rechecked.toJson(), current.toJson());
  });

  test('review: twice-excluded survivor uses effective revoke after its only resume', () async {
    await log.reserve();
    await log.ready();
    await log.ack(log.aritz);
    await log.exclude(log.nora);
    await log.add(RenewalAction.resume, {}, by: log.nora);
    log.revision++;
    await log.add(RenewalAction.revise, {
      'participants': log.participants,
      'inventoryCommitment': _b(5),
    });
    await log.ready();
    await log.ack(log.aritz);
    await log.exclude(log.nora);
    await log.prepare();
    final previous = await log.verify();
    await expectLater(log.add(RenewalAction.resume, {}, by: log.nora), _bad);
    await log.revoke(log.aritz, log.nora);
    expect((log.state!['exclusions'] as Map).containsKey(log.nora.id), isFalse);
    expect((log.state!['transfers'] as Map).containsKey(log.nora.id), isFalse);
    expect(
      (log.state!['acknowledgements'] as Map).containsKey(log.nora.id),
      isFalse,
    );
    expect(log.state!['barrier'], previous.barrier!.hash);
    await log.replace(by: log.nora, recover: true);
    await log.ready(by: log.nora);
    await log.ack(log.nora);
    await log.exclude(log.aritz, by: log.nora);
    await log.prepare(by: log.nora);
    await log.confirm(by: log.nora);
    final incremental = await log.verify(previous: previous);
    final full = await log.verify();
    expect(incremental.toJson(), full.toJson());
    expect(incremental.confirmation, isNotNull);
    expect(incremental.exclusions.keys, [log.aritz.id]);
  });

  test('N4/A1: recover, active-epoch Nora mapping, replace, late revocation veto by id and key', () async {
    final leo = await Phone.create('leo-phone', 'leo', 3);
    log.observer = leo;
    log.registry = await registryOf([log.aritz, log.nora, leo]);
    final participants = [...log.participants, leo.id];
    await log.add(RenewalAction.reserve, {
      ...log.reservationFields(),
      'participants': participants,
    });
    await log.ready();
    await log.ack(log.aritz);
    await log.revoke(log.aritz, leo);
    final old = log.target;
    log.target = _b(51, 16);
    log.revision++;
    await log.add(RenewalAction.recover, {
      ...log.reservationFields(),
      'participants': participants,
      'previousTargetSyncId': old,
    }, by: leo);
    await log.ready(by: leo);
    await log.ack(leo);
    final destinationNora = await Phone.create('nora-mapped', 'nora', 4);
    await log.ack(log.nora, destination: destinationNora);
    final mapping = log.commands.last;
    final previous = await log.verify();
    final prior = log.target;
    log.target = _b(52, 16);
    log.revision++;
    final creator = await Phone.create('leo-fresh', 'leo', 5);
    await log.add(RenewalAction.replace, {
      ...log.reservationFields(),
      'participants': participants,
      'previousTargetSyncId': prior,
      'newDeviceId': creator.id,
      'newSigningKey': encodeBase64Url(creator.keys.publicKeys.signing),
    }, by: leo);
    await log.revoke(log.nora, leo);
    for (final priorObservation in [null, previous]) {
      final verified = await log.verify(previous: priorObservation);
      expect(verified.identities.any((c) => c.hash == mapping.hash), isTrue);
      expect(
        verified.revokedIdentities.values.any((c) => c.hash == mapping.hash),
        isTrue,
      );
      final clean = await registryOf([creator]);
      expect(
        verified.destinationRevocationsSatisfied(
          await creator.viewOf(clean),
          destinationRegistry: clean,
        ),
        isTrue,
      );
      for (final id in [destinationNora.id, 'alias']) {
        final alias = await DeviceRecord.create(
          keys: destinationNora.keys,
          listId: kListId,
          deviceId: id,
          personId: 'nora',
          seq: 1,
        );
        final poisoned = await clean.withRecord(alias);
        expect(
          verified.destinationRevocationsSatisfied(
            await creator.viewOf(poisoned),
            destinationRegistry: poisoned,
          ),
          isFalse,
        );
      }
      final served = [...log.commands]
        ..removeWhere((c) => c.hash == mapping.hash);
      final hidden = {...log.state!, 'height': served.length};
      await expectLater(
        log.verify(
          previous: priorObservation,
          projection: hidden,
          servedPages: log.pages(
            served: served,
            projection: hidden,
            after: priorObservation?.height ?? 0,
          ),
        ),
        _bad,
      );
    }
  });

  test('review: extinguished barrier never resurrects after a later valid ack, with/without previous', () async {
    await log.reserve();
    await log.ready();
    await log.ack(log.aritz);
    await log.exclude(log.nora);
    await log.prepare();
    final barrier = log.state!['barrier'];
    await log.add(RenewalAction.resume, {}, by: log.nora);
    await log.revoke(log.aritz, log.nora);
    await log.replace(by: log.nora, recover: true);
    expect(log.state!['barrier'], isNull);
    final previous = await log.verify();
    await log.ready(by: log.nora);
    await log.ack(log.nora);
    await log.replace(by: log.nora);
    for (final p in [null, previous]) {
      final result = await log.verify(previous: p);
      expect(result.barrierVersion, isNull);
      expect(result.barrier, isNull);
      final forged = {...log.state!, 'barrier': barrier, 'barrierVersion': 6};
      await expectLater(log.verify(previous: p, projection: forged), _bad);
    }
  });

  test(
    'N5/B5: a live old transfer retains its barrier across recover and replace',
    () async {
      await log.reserve();
      await log.ready();
      await log.ack(log.aritz);
      await log.ack(log.nora);
      await log.prepare();
      final barrier = log.state!['barrier'];
      await log.revoke(log.aritz, log.nora);
      await log.replace(by: log.nora, recover: true);
      final previous = await log.verify();
      await log.replace(by: log.nora);
      for (final p in [null, previous]) {
        expect((await log.verify(previous: p)).barrier!.hash, barrier);
      }
    },
  );

  test(
    'recover to revise/replace and repeated recoveries retain all identities',
    () async {
      final leo = await Phone.create('leo-phone', 'leo', 3);
      log.registry = await registryOf([log.aritz, log.nora, leo]);
      final participants = [...log.participants, leo.id];
      await log.add(RenewalAction.reserve, {
        ...log.reservationFields(),
        'participants': participants,
      });
      await log.ready();
      await log.ack(log.aritz);
      await log.revoke(log.aritz, log.nora);
      for (final actor in [log.nora, leo]) {
        final old = log.target;
        log.target = _b(60 + log.revision, 16);
        log.revision++;
        await log.add(RenewalAction.recover, {
          ...log.reservationFields(),
          'participants': participants,
          'previousTargetSyncId': old,
        }, by: actor);
        log.revision++;
        await log.add(RenewalAction.revise, {
          'participants': participants,
          'inventoryCommitment': _b(5),
        }, by: actor);
        if (actor == log.nora) {
          await log.revoke(log.nora, leo);
          log.observer = leo;
        }
      }
      final result = await log.verify();
      expect(
        result.commands.where((c) => c.action == RenewalAction.recover).length,
        2,
      );
      expect(result.identities.length, 4);
      expect(result.revokedIdentities.length, 3);
    },
  );

  test('N2: narrow signed abort rejects cancellation after transfer', () async {
    await log.reserve();
    await log.add(RenewalAction.abort, {});
    final tombstone = await log.verify();
    expect(tombstone.abortion, isNotNull);
    expect(
      tombstone.authorizedIn(await log.nora.viewOf(log.registry)),
      isFalse,
    );
    log = await _Log.create();
    await log.reserve();
    await log.ready();
    await log.ack(log.aritz);
    await expectLater(log.add(RenewalAction.abort, {}), _bad);
  });

  test(
    'signed revoke is sufficient while the source registry is frozen',
    () async {
      await log.reserve();
      await log.ready();
      await log.ack(log.aritz);
      await log.ack(log.nora);
      await log.prepare();
      final frozenRegistry = log.registry;
      await log.revoke(log.nora, log.aritz);
      log.registry = frozenRegistry;
      log.observer = log.aritz;
      final result = await log.verify();
      expect(result.revokedIdentities, isNotEmpty);
      expect(
        result.authorizedIn(await log.aritz.viewOf(frozenRegistry)),
        isFalse,
      );
      expect(result.needsRevalidation, isTrue);
    },
  );

  test(
    'a valid web signature cannot authorize a plan or a new tombstone',
    () async {
      final web = await Phone.create('nora-web', 'nora', 7);
      final record = await DeviceRecord.create(
        keys: web.keys,
        listId: kListId,
        deviceId: web.id,
        personId: 'nora',
        kind: DeviceKind.web,
      );
      log.registry = await log.registry.withRecord(record);
      log.registry = await log.registry.withVouch(
        await Vouch.create(
          keys: log.aritz.keys,
          voucher: await log.aritz.record(),
          record: record,
        ),
      );
      final fields = {
        ...log.reservationFields(),
        'participants': [...log.participants, web.id],
      };
      await expectLater(
        RenewalCommand.sign(
          action: RenewalAction.reserve,
          binding: log.binding,
          sourceVersion: 1,
          signerDeviceId: web.id,
          keys: web.keys,
          sourceView: await web.viewOf(log.registry),
          prev: null,
          fields: fields,
        ),
        _bad,
      );
      final provisional = RenewalCommand.fromJson({
        'v': 1,
        'action': 'reserve',
        'operationId': _operation,
        'sourceSyncId': _source,
        'targetSyncId': log.target,
        'revision': 1,
        'sourceVersion': 1,
        'signerDeviceId': web.id,
        'prev': null,
        ...fields,
        'signature': _b(0, 64),
      });
      final command = RenewalCommand.fromJson({
        ...provisional.toJson(),
        'signature': encodeBase64Url(
          await web.keys.sign(provisional.signingBytes),
        ),
      });
      log.state = replayRenewalCommand(
        null,
        command,
        {},
        index: RenewalReplayIndex(),
      );
      log.commands.add(command);
      log.version++;
      await expectLater(log.verify(), _bad);
    },
  );

  test('N2: new abort needs current authority, persisted historical abort remains evidence', () async {
    await log.reserve();
    await log.add(RenewalAction.abort, {});
    final previous = await log.verify();
    log.registry = await log.registry.withRevocation(
      await Revocation.create(
        keys: log.nora.keys,
        by: await log.nora.record(),
        deviceId: log.aritz.id,
      ),
    );
    await expectLater(log.verify(), _bad);
    expect(
      (await log.verify(previous: previous)).abortion!.hash,
      previous.abortion!.hash,
    );
  });

  test(
    'normal close needs fresh receipts, resolved participants and latest CAS',
    () async {
      await log.reserve();
      await log.ready();
      await log.ack(log.aritz);
      await expectLater(log.prepare(), _bad);
      await log.ack(log.nora);
      await log.prepare();
      await log.confirm();
      final closed = await log.verify();
      final view = await log.nora.viewOf(log.registry);
      expect(closed.canDeleteSource(view, log.nora.id), isTrue);
      log.version++;
      final stale = await log.verify(previous: closed);
      expect(stale.canDeleteSource(view, log.nora.id), isFalse);
    },
  );

  test('P1: a newly served signed CAS cannot precede an unrelated persisted observation', () async {
    await log.reserve();
    log.version += 5;
    final previous = await log.verify();
    final c = await RenewalCommand.sign(
      action: RenewalAction.ready,
      binding: log.binding,
      sourceVersion: 2,
      signerDeviceId: log.aritz.id,
      keys: log.aritz.keys,
      sourceView: await log.aritz.viewOf(log.registry),
      prev: log.commands.last.hash,
      fields: {'destinationVersion': 1},
    );
    final p = replayRenewalCommand(log.state, c, {}, index: log.replayIndex);
    await expectLater(
      log.verify(
        previous: previous,
        projection: p,
        servedPages: log.pages(
          served: [...log.commands, c],
          projection: p,
          after: previous.height,
        ),
      ),
      _bad,
    );
  });

  test('same-target identities need explicit signed revocation; aliases remain vetoed', () async {
    final creator = await Phone.create('aritz-fresh', 'aritz', 4);
    final mapped = await Phone.create('nora-mapped', 'nora', 5);
    await log.add(RenewalAction.reserve, {
      ...log.reservationFields(),
      'newDeviceId': creator.id,
      'newSigningKey': encodeBase64Url(creator.keys.publicKeys.signing),
    });
    await log.ready();
    await log.ack(log.aritz);
    await log.ack(log.nora, destination: mapped);
    await log.revoke(log.nora, log.aritz);
    log.observer = log.aritz;
    final verified = await log.verify();
    var target = await registryOf([creator, mapped]);
    expect(
      verified.destinationRevocationsSatisfied(
        await creator.viewOf(target),
        destinationRegistry: target,
      ),
      isFalse,
    );
    target = await target.withRevocation(
      await Revocation.create(
        keys: creator.keys,
        by: await creator.record(),
        deviceId: mapped.id,
      ),
    );
    expect(
      verified.destinationRevocationsSatisfied(
        await creator.viewOf(target),
        destinationRegistry: target,
      ),
      isTrue,
    );
    target = await target.withRecord(
      await DeviceRecord.create(
        keys: mapped.keys,
        listId: kListId,
        deviceId: 'alias',
        personId: 'nora',
      ),
    );
    expect(
      verified.destinationRevocationsSatisfied(
        await creator.viewOf(target),
        destinationRegistry: target,
      ),
      isFalse,
    );
  });

  test('review: M1 bytes: large log survives revocation and a mobile completes close', () async {
    final participants = [
      log.aritz.id,
      log.nora.id,
      ...List.generate(30, (i) => 'local-$i-${'x' * 118}'),
    ];
    await log.add(RenewalAction.reserve, {
      ...log.reservationFields(),
      'participants': participants,
    });
    var full = false;
    for (var i = 0; i < 180; i++) {
      final old = log.target;
      log.target = _b(40 + log.revision, 16);
      log.revision++;
      try {
        await log.add(RenewalAction.replace, {
          ...log.reservationFields(),
          'participants': participants,
          'previousTargetSyncId': old,
        });
      } on RenewalProtocolException catch (e) {
        expect(e.code, 'log_full');
        full = true;
        break;
      }
    }
    expect(full, isTrue);
    expect(log.state!['logBytes'] as int, greaterThan(256 * 1024));
    expect(log.commands.length, lessThan(1024));
    log.target = log.state!['targetSyncId'] as String;
    log.revision = log.state!['revision'] as int;
    final previous = await log.verify();
    await log.revoke(log.aritz, log.nora);
    final old = log.state!['targetSyncId'];
    log.target = _b(250, 16);
    log.revision = (log.state!['revision'] as int) + 1;
    final creator = await Phone.create('nora-final', 'nora', 6);
    await log.add(RenewalAction.recover, {
      ...log.reservationFields(),
      'participants': participants,
      'previousTargetSyncId': old,
      'newDeviceId': creator.id,
      'newSigningKey': encodeBase64Url(creator.keys.publicKeys.signing),
    }, by: log.nora);
    await log.ready(by: log.nora);
    await log.ack(log.nora);
    for (final id in participants.where((id) => id != log.nora.id)) {
      await log.add(RenewalAction.exclude, {
        'participantDeviceId': id,
        'loss': true,
        'receipt': _b(7),
      }, by: log.nora);
    }
    await log.prepare(by: log.nora);
    await log.confirm(by: log.nora);
    final destination = await registryOf([creator]);
    for (final observed in [null, previous]) {
      final result = await log.verify(previous: observed);
      expect(
        utf8.encode(jsonEncode(result.toJson())).length,
        lessThan(256 * 1024),
      );
      expect(result.revokedIdentities.length, greaterThan(100));
      expect(
        result.canDeleteSource(
          await log.nora.viewOf(log.registry),
          log.nora.id,
          destinationView: await creator.viewOf(destination),
          destinationRegistry: destination,
        ),
        isTrue,
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    '32 longest participant ids: the 37-command solo exit fits the refill',
    () {
      final participants = List.generate(
        32,
        (i) => 'participant-$i-'.padRight(128, 'x'),
      );
      final aritz = participants[0],
          nora = participants[1],
          leo = participants[2];
      final index = RenewalReplayIndex();
      final revoked = <String>{};
      Map<String, Object?>? state;
      var revision = 1;
      var target = _b(3, 16);
      void append(
        RenewalAction action,
        String signer,
        Map<String, Object?> fields,
      ) {
        final c = RenewalCommand.fromJson({
          'v': 1,
          'action': action.name,
          'operationId': _operation,
          'sourceSyncId': _source,
          'targetSyncId': target,
          'revision': revision,
          'sourceVersion': index.height + 1,
          'signerDeviceId': signer,
          'prev': state?['head'],
          'signature': _b(0, 64),
          ...fields,
        });
        state = replayRenewalCommand(state, c, revoked, index: index);
        index.add(c);
      }

      Map<String, Object?> identity(String id) => {
        'newDeviceId': 'new-$id'.substring(0, 128),
        'newSigningKey': _b(id == aritz ? 40 : 41),
      };
      append(RenewalAction.reserve, aritz, {
        'participants': participants,
        ...identity(aritz),
        'targetCommitment': _b(4),
        'inventoryCommitment': _b(5),
      });
      append(RenewalAction.ready, aritz, {'destinationVersion': 1});
      append(RenewalAction.ack, aritz, {
        ...identity(aritz),
        'destinationVersion': 1,
        'receipt': _b(6),
      });
      append(RenewalAction.exclude, aritz, {
        'participantDeviceId': nora,
        'loss': true,
        'receipt': _b(7),
      });
      append(RenewalAction.revoke, leo, {'participantDeviceId': aritz});
      final beforeHeight = index.height, beforeBytes = index.bytes;
      // A previous effective revocation grants the excluded survivor a refill.
      // Resume is still available once, then recover and the entire solo close.
      append(RenewalAction.resume, nora, {});
      final oldTarget = target;
      target = _b(4, 16);
      revision++;
      append(RenewalAction.recover, nora, {
        'participants': participants,
        ...identity(nora),
        'previousTargetSyncId': oldTarget,
        'targetCommitment': _b(4),
        'inventoryCommitment': _b(5),
      });
      append(RenewalAction.ready, nora, {'destinationVersion': 1});
      append(RenewalAction.ack, nora, {
        ...identity(nora),
        'destinationVersion': 1,
        'receipt': _b(6),
      });
      for (final id in participants.where((id) => id != nora)) {
        append(RenewalAction.exclude, nora, {
          'participantDeviceId': id,
          'loss': true,
          'receipt': _b(7),
        });
      }
      append(RenewalAction.prepare, nora, {
        'pendingResources': 0,
        'coverageCommitment': _b(8),
      });
      append(RenewalAction.confirm, nora, {
        'snapshotVersion': state!['barrierVersion'],
        'pendingResources': 0,
        'coverageCommitment': _b(9),
      });
      expect(index.height - beforeHeight, 37);
      expect(index.bytes - beforeBytes, lessThanOrEqualTo(kRenewalRefillBytes));
      expect(
        index.height - beforeHeight,
        lessThanOrEqualTo(kRenewalRefillCommands),
      );
      expect(state!['confirmation'], isNotNull);
      const exempt = 2 * kRenewalParticipants + 1;
      const epochs = kRenewalParticipants * (kRenewalParticipants - 1) ~/ 2;
      expect(
        kRenewalOrdinaryCommands +
            kRenewalParticipants * kRenewalRescueCommands +
            epochs * kRenewalRefillCommands +
            exempt,
        22465,
      );
      expect(
        kRenewalOrdinaryBytes +
            kRenewalParticipants * kRenewalRescueBytes +
            epochs * kRenewalRefillBytes +
            exempt * kRenewalCommandBytes,
        lessThan(kRenewalLogMaxBytes),
      );
    },
  );

  test('maximum service log: linear replay and complete exits after every revocation', () {
    final participants = [
      'nora',
      'aritz',
      ...List.generate(30, (i) => 'local-$i'),
    ];
    final index = RenewalReplayIndex();
    final history = <RenewalCommand>[];
    final revoked = <String>{};
    Map<String, Object?>? state;
    var revision = 1;
    var target = _b(3, 16);
    // This measures deterministic replay, not Ed25519. Signature checking is
    // covered by fromLog tests; these fixed-size signatures isolate replay cost.
    void append(
      RenewalAction action,
      String signer,
      Map<String, Object?> fields,
    ) {
      final c = RenewalCommand.fromJson({
        'v': 1,
        'action': action.name,
        'operationId': _operation,
        'sourceSyncId': _source,
        'targetSyncId': target,
        'revision': revision,
        'sourceVersion': history.length + 1,
        'signerDeviceId': signer,
        'prev': state?['head'],
        'signature': _b(0, 64),
        ...fields,
      });
      state = replayRenewalCommand(state, c, revoked, index: index);
      index.add(c);
      history.add(c);
    }

    Map<String, Object?> identity(String id) => {
      'newDeviceId': 'new-$revision-$id',
      'newSigningKey': encodeBase64Url([
        revision,
        participants.indexOf(id),
        ...List.filled(30, 0),
      ]),
    };
    void readyAndResolve() {
      append(
        RenewalAction.ready,
        index.byHash[state!['reservation']]!.signerDeviceId,
        {'destinationVersion': 1},
      );
      for (final id in participants) {
        if (!revoked.contains(id)) {
          append(RenewalAction.ack, id, {
            ...identity(id),
            'destinationVersion': 2,
            'receipt': _b(6),
          });
        } else {
          append(RenewalAction.exclude, 'nora', {
            'participantDeviceId': id,
            'loss': true,
            'receipt': _b(7),
          });
        }
      }
      append(RenewalAction.prepare, 'nora', {
        'pendingResources': 0,
        'coverageCommitment': _b(8),
      });
    }

    void confirm(String id) => append(RenewalAction.confirm, id, {
      'snapshotVersion': state!['barrierVersion'],
      'pendingResources': 0,
      'coverageCommitment': _b(9),
    });
    append(RenewalAction.reserve, participants.last, {
      'participants': participants,
      ...identity(participants.last),
      'targetCommitment': _b(4),
      'inventoryCommitment': _b(5),
    });
    readyAndResolve();
    while (index.height < kRenewalOrdinaryCommands) {
      confirm('nora');
    }
    for (final id in participants) {
      while ((index.rescueCount[id] ?? 0) < kRenewalRescueCommands) {
        confirm(id);
      }
    }
    // Exercise all 31 revocation epochs, spending every remaining allowance.
    for (final lost in participants.reversed.where((id) => id != 'nora')) {
      append(RenewalAction.revoke, 'nora', {'participantDeviceId': lost});
      final oldTarget = target;
      revision++;
      target = _b(3 + revision, 16);
      final creator = participants.lastWhere((id) => !revoked.contains(id));
      append(RenewalAction.recover, creator, {
        'participants': participants,
        ...identity(creator),
        'previousTargetSyncId': oldTarget,
        'targetCommitment': _b(4),
        'inventoryCommitment': _b(5),
      });
      readyAndResolve();
      for (final id in participants.where((id) => !revoked.contains(id))) {
        while ((index.rescueCount[id] ?? 0) < kRenewalRefillCommands) {
          confirm(id);
        }
      }
    }
    expect(history.length, 22462);
    expect(history.length, lessThan(kRenewalLogMaxCommands));
    final expected = state;
    final timer = Stopwatch()..start();
    final replay = RenewalReplayIndex();
    final replayed = <RenewalCommand>[];
    final replayRevoked = <String>{};
    Map<String, Object?>? actual;
    for (final c in history) {
      actual = replayRenewalCommand(actual, c, replayRevoked, index: replay);
      replay.add(c);
      replayed.add(c);
    }
    timer.stop();
    expect(actual, expected);
    expect(actual!['confirmation'], isNotNull);
    // A generous regression bound catches the former quadratic prefix walks.
    expect(timer.elapsed, lessThan(const Duration(seconds: 60)));
    // Keep the measured duration in the test runner's saved report.
    // ignore: avoid_print
    print(
      'RENEWAL_MAX_REPLAY commands=${history.length} bytes=${index.bytes} elapsed_ms=${timer.elapsedMilliseconds} (desktop VM; replay only)',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('private commitments bind scope, kind, revision and random salt', () {
    String commitment({
      RenewalCommitmentKind kind = RenewalCommitmentKind.receipt,
      int salt = 1,
    }) => renewalCommitment(
      binding: log.binding,
      kind: kind,
      salt: List.filled(32, salt),
      manifest: {'pending': 0},
    );
    expect(commitment(), commitment());
    expect(commitment(salt: 2), isNot(commitment()));
    expect(
      commitment(kind: RenewalCommitmentKind.coverage),
      isNot(commitment()),
    );
    expect(
      () => renewalCommitment(
        binding: log.binding,
        kind: RenewalCommitmentKind.receipt,
        salt: [],
        manifest: {},
      ),
      _bad,
    );
  });
}
