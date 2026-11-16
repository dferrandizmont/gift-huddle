// ignore_for_file: avoid_print

// Sonda del emparejamiento de la web compilada a wasm con el optimizador de
// producción (-O4, el de `flutter build web --wasm`).
//
// `flutter test --platform chrome --wasm` no carga en Windows (el servidor de
// pruebas de flutter_tools compara `canvaskit\...` con `canvaskit/` y devuelve
// 404 a skwasm). Esta sonda no usa Flutter, así que se compila y se ejecuta
// en V8 (Node 24, con WebCrypto y fetch reales):
//
//   dart compile wasm -O4 --no-strip-wasm test/wasm/web_pairing_probe.dart //     -o build/wasm_probe/probe.wasm
//   node test/wasm/run_probe.mjs build/wasm_probe
//
// Escribe `PROBE <escenario> OK` o `PROBE <escenario> FAIL <error>` y, al
// final, `PROBE DONE ok=N fail=M`.
// Recorre el emparejamiento completo de la web (oferta, respuesta, código,
// confirmación, aprobación, `finish()`, la caja y la primera vuelta) con
// familias reales: varias personas y regalos, un segundo móvil, el corte al
// formato 2 del común y una web quitada antes de emparejar otra.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:cryptography/cryptography.dart' show Hmac, Pbkdf2, SecretKey;
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/features/sync/application/v2_family_lock.dart';
import 'package:regalos/features/sync/data/sync_endpoint.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';
import 'package:regalos/features/sync/data/web_sync_transport.dart';
import 'package:regalos/features/web_device/application/pending_queue.dart';
import 'package:regalos/features/web_device/application/vault_service.dart';
import 'package:regalos/features/web_device/application/web_pairing_guest.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart';
import 'package:regalos/features/web_device/data/guard_client.dart';
import 'package:regalos/features/web_device/data/vault_crypto.dart';
import 'package:regalos/features/web_device/data/vault_store.dart';

import '../helpers/fake_worker_v2.dart';
import '../sync/v2_harness.dart';
import '../web_device/test_support.dart';

void _log(String line) => print('PROBE $line');

@JS('PROBE_ECHO')
external JSString? get _echoUrl;

/// With `globalThis.PROBE_ECHO` set (Node runner), every response of the fake
/// Worker travels through the real [WebSyncTransport] (fetch, streams, JS
/// typed arrays) via an echo server that sends it back in small chunks.
SyncV2Transport _clientOf(FakeWorkerV2 worker) {
  final echo = _echoUrl?.toDart;
  if (echo == null) return worker.client();
  final web = WebSyncTransport(SyncEndpoint.parse(echo)!);
  return SyncV2Client(
    base: Uri.parse('https://sync.test'),
    sendRequest: (method, uri, {body, headers = const {}}) async {
      final r = await worker.send(method, uri, body: body, headers: headers);
      return web.send(
        'POST',
        Uri.parse('$echo/echo'),
        body: {'s': r.status, 'h': r.headers, 'b': base64Encode(r.body)},
      );
    },
  );
}

Future<MemoryV2Phone> _family({bool cut = false, int people = 3}) async {
  final phone = await MemoryV2Phone.create(
    'aritz-phone',
    'aritz',
    1,
    familyKey: await FamilyKey.generate(),
    migrated: true,
  );
  phone
    ..addPerson('aritz', 'Aritz')
    ..addPerson('nora', 'Nora')
    ..addPerson('leo', 'Leo');
  for (var i = 0; i < people; i++) {
    phone.addPerson('p$i', 'Persona $i');
    for (var g = 0; g < 6; g++) {
      phone.addGift('g$i-$g', 'p$i', 'Regalo $g de $i con acentos áéí ñ');
    }
  }
  phone.addGift('gift', 'nora', 'Bufanda');
  if (cut) phone.enableCommonV2();
  return phone;
}

/// One full web pairing against [worker], approving from [phone].
Future<WebPairingGuest> _pairWeb(
  FakeWorkerV2 worker,
  MemoryV2Phone phone, {
  String person = 'leo',
  bool enroll = true,
  bool realPin = false,
}) async {
  final client = _clientOf(worker);
  final guest = await WebPairingGuest.create(transport: client);
  await guest.poll(); // No offer yet.
  final host = await PairingV2Host.start(
    transport: client,
    local: phone,
    lock: V2FamilyLock(),
    web: guest.qr,
    guestPerson: person,
  );
  await guest.poll(); // Offer + answer.
  final answered = (await host.poll())!;
  await guest.poll(); // Code.
  if (guest.code != answered.code) throw StateError('codes differ');
  guest.confirmCode();
  await guest.poll(); // Pending approval: finish() returns null.
  if (guest.joined != null) throw StateError('joined before approval');
  await host.confirm(confirmedPersonId: person);
  await guest.poll(); // finish() with the real approval.
  if (guest.joined == null) throw StateError('not joined after approval');
  if (enroll) {
    final vault = VaultService(
      store: MemoryVaultStore(),
      guard: GuardClient(
        base: Uri.parse('https://sync.test'),
        send: worker.send,
      ),
      // The real PBKDF2 (600,000 rounds, WebCrypto) when [realPin].
      crypto: realPin ? VaultCrypto() : FastTestCrypto(),
      persist: () async => false,
    );
    final enrollWatch = Stopwatch()..start();
    await guest.enroll(vault, '123456');
    if (realPin) _log('timing enroll ${enrollWatch.elapsedMilliseconds} ms');
    final engine = WebSyncEngine(
      transport: client,
      vault: vault,
      queue: PendingQueue(vault),
    );
    await engine.sync(); // first sync after pairing
    if (engine.status != WebSyncStatus.confirmed) {
      throw StateError('first sync: ${engine.status}');
    }
    engine.stop();
    vault.lock();
    if (realPin) {
      final unlockWatch = Stopwatch()..start();
      await vault.unlock('123456');
      _log('timing unlock ${unlockWatch.elapsedMilliseconds} ms');
      vault.lock();
      var opened = false;
      try {
        await vault.unlock('654321');
        opened = true;
      } catch (_) {
        // Refused, as it must be.
      }
      if (opened) throw StateError('a wrong PIN opened the vault');
    }
  }
  return guest;
}

Future<void> _scenario(String name, Future<void> Function() body) async {
  try {
    await body();
    _ok++;
    _log('$name OK');
  } catch (e, s) {
    _fail++;
    _log('$name FAIL $e\n$s');
  }
}

var _ok = 0, _fail = 0;

Future<void> main() async {
  _log('START');
  // Like the app (web vault, PIN): with Pbkdf2 in the program, the
  // `cryptography` Hkdf call with `info` became `unreachable` (hkdf.dart).
  await _scenario('pbkdf2-in-program', () async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 2,
      bits: 256,
    ).deriveKey(secretKey: SecretKey([1, 2, 3]), nonce: [4, 5]);
    if ((await key.extractBytes()).length != 32) throw StateError('pbkdf2');
  });
  // docs/adr/0003-vector-caja.json: the same bytes as Node's PBKDF2, so the
  // vaults already in browsers still open with their PIN.
  await _scenario('vault-vector', () async {
    final header = VaultHeader(
      syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
      deviceId: 'bbbbbbbbbb',
      salt: decodeBase64Url('AAECAwQFBgcICQoLDA0ODw'),
      guardToken: decodeBase64Url(
        'QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8',
      ),
      guardVersion: 1,
    );
    final watch = Stopwatch()..start();
    final a = await VaultCrypto().deriveA('Cafe Nora', header);
    _log('timing PBKDF2 600000 ${watch.elapsedMilliseconds} ms');
    if (encodeBase64Url(await a.extractBytes()) !=
        'lZwb1CGCqdOv5kub7yG0GLkddaNwNi1G3fExCJhDYDM') {
      throw StateError('vault vector A differs');
    }
    // Precomposed (U+00E9) and decomposed (e + U+0301) give the same key:
    // the PIN is NFC-normalised before PBKDF2.
    const composed = 'Café Nora';
    const decomposed = 'Café Nora';
    if (composed == decomposed) throw StateError('inputs must differ');
    for (final pin in [composed, decomposed]) {
      final nfc = await VaultCrypto().deriveA(pin, header);
      if (encodeBase64Url(await nfc.extractBytes()) !=
          'iq75xwY1ldf3WmnGQ6TfSXxu3_GTwFtiY9esyB_fOEY') {
        throw StateError('vault vector NFC differs for ${pin.runes.toList()}');
      }
    }
  });
  await _scenario('real-pin-enroll-unlock-sync', () async {
    await _pairWeb(FakeWorkerV2(), await _family(), realPin: true);
  });
  await _scenario('basic', () async {
    await _pairWeb(FakeWorkerV2(), await _family());
  });
  await _scenario('many-people', () async {
    await _pairWeb(FakeWorkerV2(), await _family(people: 30));
  });
  await _scenario('cut-format-2', () async {
    await _pairWeb(FakeWorkerV2(), await _family(cut: true));
  });
  await _scenario('second-phone', () async {
    final a = await _family();
    final b = await MemoryV2Phone.create(
      'nora-phone',
      'nora',
      2,
      familyKey: a.familyKey,
      doc: a.doc,
    );
    await vouchAll([a, b]);
    await _pairWeb(FakeWorkerV2(), a);
  });
  await _scenario('removed-web-then-new-web', () async {
    final worker = FakeWorkerV2();
    final a = await _family();
    final first = await _pairWeb(worker, a, person: 'nora');
    final webId = first.joined!.identity.deviceId;
    // The phone adopts the registry the web pairing left on the server.
    final snap = (await _clientOf(worker).getList(a.auth) as V2GetOk).snapshot;
    a.reg = await a.reg.merge(
      await DeviceRegistry.fromJsonVerified(
        snap.registry,
        anchor: RegistryAnchor(
          deviceId: a.identity.deviceId,
          signingKey: a.keys.publicKeys.signing,
        ),
      ),
    );
    a.reg = await a.reg.withRevocation(
      await Revocation.create(keys: a.keys, by: a.record, deviceId: webId),
    );
    await _pairWeb(worker, a, person: 'leo');
  });
  _log('DONE ok=$_ok fail=$_fail');
}
