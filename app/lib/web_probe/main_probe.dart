// Development-only browser entrypoint. Never imported by the product app.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart'
    show DartAesGcm, DartEd25519, DartHkdf, DartPbkdf2, DartX25519;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../core/theme/app_typography.dart' show kAppFontFamily;
import '../core/sync/envelope.dart' show encodeBase64Url;
import '../features/web_device/data/vault_crypto.dart';

void main() {
  final probe = BrowserProbe();
  // Install before mounting Flutter so that early lifecycle events are visible.
  probe.watchLifecycle();
  runApp(ProbeApp(probe: probe));
  unawaited(probe.run());
}

JSObject _options(Map<String, Object?> value) => value.jsify() as JSObject;
Uint8List _bytes(List<int> value) => Uint8List.fromList(value);
bool _same(List<int> a, List<int> b) => listEquals(a, b);
// runtimeType names are minified in release builds; these type checks survive.
String _backend(Object algorithm) => switch (algorithm) {
  DartPbkdf2() ||
  DartAesGcm() ||
  DartHkdf() ||
  DartX25519() ||
  DartEd25519() => 'pure Dart',
  _ => 'WebCrypto (cryptography browser backend)',
};
void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// All generated keys and payloads are disposable test data. Only status,
/// sizes, equality and timings are logged, never key material.
class BrowserProbe extends ChangeNotifier {
  final lines = <String>[];
  final tab = DateTime.now().microsecondsSinceEpoch.toString();
  final _lockLifetime = Completer<JSAny?>();
  web.BroadcastChannel? _channel;
  bool _hasLock = false;

  void log(bool ok, String message) {
    final line =
        '${ok ? 'OK' : 'FAIL'} ${DateTime.now().toIso8601String()} $message';
    lines.add(line);
    web.console.log('PROBE $line'.toJS);
    notifyListeners();
  }

  Future<void> check(String name, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      log(false, '$name: $error');
    }
  }

  void watchLifecycle() {
    for (final name in ['pagehide', 'pageshow']) {
      web.window.addEventListener(
        name,
        ((web.Event event) {
          final transition = event as web.PageTransitionEvent;
          log(true, '$name persisted=${transition.persisted} lock=$_hasLock');
        }).toJS,
      );
    }
    web.document.addEventListener(
      'visibilitychange',
      ((web.Event event) {
        log(true, 'visibilitychange state=${web.document.visibilityState}');
      }).toJS,
    );
    log(
      true,
      'lifecycle listeners installed; visibility=${web.document.visibilityState}',
    );
  }

  Future<void> run() async {
    log(
      true,
      'browser=${web.window.navigator.userAgent} secureContext=${web.window.isSecureContext} '
      'dart2wasm=${const bool.fromEnvironment('dart.tool.dart2wasm')} tab=$tab',
    );
    await check('Web Locks', _lock);
    await check('BroadcastChannel', _broadcast);
    await check('IndexedDB', _indexedDb);
    await check('storage.persist', () async {
      final granted =
          (await web.window.navigator.storage.persist().toDart).toDart;
      log(
        granted,
        'storage.persist granted=$granted (denial is a browser policy outcome)',
      );
    });
    await check('storage.estimate', () async {
      final estimate = await web.window.navigator.storage.estimate().toDart;
      log(
        true,
        'storage.estimate usage=${estimate.usage} quota=${estimate.quota} bytes',
      );
    });
    for (final iterations in [300000, 600000, 1000000]) {
      await check('PBKDF2 $iterations', () => _pbkdf2(iterations));
      // Give rendering and lifecycle callbacks a turn between measurements.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await check('AES-256-GCM', _aes);
    await check('Vault NFC vector', checkVaultNfcVector);
    await check('HKDF-SHA256', _hkdf);
    await check('X25519', _x25519);
    await check('Ed25519', _ed25519);
    log(
      true,
      'automatic checks finished; inspect FAIL lines above. '
      'Open another tab, send a message, edit accented text, hide/show and navigate back.',
    );
  }

  Future<void> _lock() async {
    final granted = Completer<void>();
    unawaited(
      web.window.navigator.locks
          .request(
            'gift-huddle-session',
            web.LockOptions(ifAvailable: true),
            ((web.Lock? lock) {
              _hasLock = lock != null;
              log(
                true,
                'Web Locks ifAvailable=true acquired=$_hasLock; held for page lifetime',
              );
              granted.complete();
              return lock == null
                  ? Future<JSAny?>.value(null).toJS
                  : _lockLifetime.future.toJS;
            }).toJS,
          )
          .toDart
          .then<void>(
            (_) {},
            onError: (Object error) {
              if (!granted.isCompleted) {
                granted.completeError(error);
              } else {
                log(false, 'Web Locks lifetime: $error');
              }
            },
          ),
    );
    await granted.future.timeout(const Duration(seconds: 10));
  }

  Future<void> _broadcast() async {
    final channel = web.BroadcastChannel('gift-huddle');
    _channel = channel;
    channel.onmessage = ((web.MessageEvent event) {
      final value = event.data.dartify();
      log(true, 'BroadcastChannel received=$value');
      // A hello/ack handshake proves both directions, without echo loops.
      if (value is Map && value['type'] == 'hello') {
        channel.postMessage(
          {'type': 'ack', 'from': tab, 'to': value['from']}.jsify(),
        );
        log(true, 'BroadcastChannel sent ack from=$tab');
      }
    }).toJS;
    channel.onmessageerror = ((web.Event event) {
      log(false, 'BroadcastChannel messageerror');
    }).toJS;
    sendMessage();
    log(true, 'BroadcastChannel ready; receive check pending a second tab');
  }

  void sendMessage() {
    if (_channel == null) {
      log(false, 'BroadcastChannel is not ready');
      return;
    }
    _channel!.postMessage(
      {
        'type': 'hello',
        'from': tab,
        'at': DateTime.now().toIso8601String(),
      }.jsify(),
    );
    log(true, 'BroadcastChannel sent hello from=$tab');
  }

  Future<JSAny?> _request(web.IDBRequest request) {
    final result = Completer<JSAny?>();
    request.onsuccess = ((web.Event event) {
      if (!result.isCompleted) result.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event event) {
      if (!result.isCompleted) {
        result.completeError(StateError('IndexedDB ${request.error?.name}'));
      }
    }).toJS;
    return result.future.timeout(const Duration(seconds: 15));
  }

  Future<void> _transaction(web.IDBTransaction transaction) {
    final done = Completer<void>();
    transaction.oncomplete = ((web.Event event) {
      if (!done.isCompleted) done.complete();
    }).toJS;
    transaction.onabort = ((web.Event event) {
      if (!done.isCompleted) {
        done.completeError(
          StateError(
            'IndexedDB transaction aborted: ${transaction.error?.name}',
          ),
        );
      }
    }).toJS;
    return done.future.timeout(const Duration(seconds: 15));
  }

  Future<void> _indexedDb() async {
    final name = 'gift-huddle-probe-$tab';
    final factory = web.window.indexedDB;
    final open = factory.open(name, 1);
    open.onupgradeneeded = ((web.Event event) {
      (open.result as web.IDBDatabase).createObjectStore('bytes');
    }).toJS;
    final db = (await _request(open)) as web.IDBDatabase;
    try {
      final payload = Uint8List.fromList(
        List<int>.generate(64 * 1024, (i) => i % 251),
      );
      final write = db.transaction('bytes'.toJS, 'readwrite');
      final committed = _transaction(write);
      write.objectStore('bytes').put(payload.toJS, 'payload'.toJS);
      await committed; // Request success alone does not mean the write committed.
      log(true, 'IndexedDB write 65536 bytes transaction oncomplete');
      final read = db.transaction('bytes'.toJS, 'readonly');
      final completed = _transaction(read);
      final loaded = _request(read.objectStore('bytes').get('payload'.toJS));
      // Attach both error handlers immediately, even if one operation fails.
      final results = await Future.wait<Object?>([loaded, completed]);
      final bytes = (results.first as JSUint8Array).toDart;
      _require(_same(bytes, payload), 'IndexedDB payload differs');
      log(true, 'IndexedDB read 65536 bytes equal=true transaction oncomplete');
    } finally {
      db.close();
      final deletion = factory.deleteDatabase(name);
      deletion.onblocked = ((web.Event event) {
        log(false, 'IndexedDB delete blocked');
      }).toJS;
      await _request(deletion);
      log(true, 'IndexedDB disposable database deleted');
    }
  }

  Uint8List _random(int length) {
    final bytes = Uint8List(length).toJS;
    web.window.crypto.getRandomValues(bytes);
    return bytes.toDart;
  }

  Future<web.CryptoKey> _import(
    List<int> bytes,
    String algorithm,
    List<String> uses,
  ) => web.window.crypto.subtle
      .importKey(
        'raw',
        _bytes(bytes).toJS,
        algorithm.toJS,
        false,
        uses.map((s) => s.toJS).toList().toJS,
      )
      .toDart;

  Future<Uint8List> _derive(
    web.CryptoKey key,
    Map<String, Object?> params,
  ) async =>
      (await web.window.crypto.subtle
              .deriveBits(_options(params), key, 256)
              .toDart)
          .toDart
          .asUint8List();

  Future<T> _timed<T>(String name, Future<T> Function() action) async {
    final clock = Stopwatch()..start();
    final value = await action();
    clock.stop();
    log(
      true,
      '$name ms=${(clock.elapsedMicroseconds / 1000).toStringAsFixed(2)}',
    );
    return value;
  }

  Future<void> _pbkdf2(int iterations) async {
    // Diagnostic PIN only; never a real vault or credential.
    final password = _bytes(utf8.encode('probe-PIN-é-123456'));
    final salt = _random(16);
    final key = await _import(password, 'PBKDF2', ['deriveBits']);
    final native = await _timed(
      'WebCrypto PBKDF2-SHA256 iterations=$iterations salt=16 output=32',
      () => _derive(key, {
        'name': 'PBKDF2',
        'hash': 'SHA-256',
        'salt': salt.toJS,
        'iterations': iterations,
      }),
    );
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final dart = await _timed(
      'cryptography PBKDF2 iterations=$iterations backend=${_backend(algorithm)}',
      () async => (await algorithm.deriveKey(
        secretKey: SecretKey(password),
        nonce: salt,
      )).extractBytes(),
    );
    _require(_same(native, dart), 'PBKDF2 outputs differ');
    log(
      true,
      'PBKDF2 iterations=$iterations WebCrypto/cryptography equal=true',
    );
  }

  /// Matches `nfc` in docs/adr/0003-vector-caja.json. Never logs the key.
  Future<void> checkVaultNfcVector() async {
    final header = VaultHeader(
      syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
      deviceId: 'bbbbbbbbbb',
      salt: List.generate(16, (i) => i),
      guardToken: List.generate(32, (i) => i + 64),
      guardVersion: 1,
    );
    final bigA = await VaultCrypto().deriveA('Cafe\u0301 Nora', header);
    _require(
      encodeBase64Url(await bigA.extractBytes()) ==
          'iq75xwY1ldf3WmnGQ6TfSXxu3_GTwFtiY9esyB_fOEY',
      'Vault NFC vector A differs',
    );
    log(true, 'Vault decomposed-accent NFC/PBKDF2 matches vector A');
  }

  Future<void> _aes() async {
    final keyBytes = _random(32);
    final nativeKey = await _import(keyBytes, 'AES-GCM', [
      'encrypt',
      'decrypt',
    ]);
    final dartKey = SecretKey(keyBytes);
    final payload = _random(64 * 1024);
    final nonce = _random(12);
    final aad = _bytes(utf8.encode('gift-huddle probe cross-vector v1'));
    final params = _options({
      'name': 'AES-GCM',
      'iv': nonce.toJS,
      'additionalData': aad.toJS,
      'tagLength': 128,
    });
    final native = await _timed(
      'WebCrypto AES-256-GCM encrypt 65536 bytes',
      () async =>
          ((await web.window.crypto.subtle
                      .encrypt(params, nativeKey, payload.toJS)
                      .toDart)
                  as JSArrayBuffer)
              .toDart
              .asUint8List(),
    );
    final algorithm = AesGcm.with256bits();
    final decrypted = await _timed(
      'cryptography AES-GCM decrypt WebCrypto backend=${_backend(algorithm)}',
      () => algorithm.decrypt(
        SecretBox(
          native.sublist(0, native.length - 16),
          nonce: nonce,
          mac: Mac(native.sublist(native.length - 16)),
        ),
        secretKey: dartKey,
        aad: aad,
      ),
    );
    _require(
      _same(decrypted, payload),
      'cryptography could not decrypt WebCrypto',
    );
    // A fresh nonce for the reverse direction, as with every real encryption.
    final dartNonce = _random(12);
    final dartBox = await _timed(
      'cryptography AES-256-GCM encrypt 65536 bytes',
      () => algorithm.encrypt(
        payload,
        secretKey: dartKey,
        nonce: dartNonce,
        aad: aad,
      ),
    );
    final reverse = await _timed(
      'WebCrypto AES-GCM decrypt cryptography',
      () async =>
          ((await web.window.crypto.subtle
                      .decrypt(
                        _options({
                          'name': 'AES-GCM',
                          'iv': dartNonce.toJS,
                          'additionalData': aad.toJS,
                          'tagLength': 128,
                        }),
                        nativeKey,
                        _bytes([...dartBox.cipherText, ...dartBox.mac.bytes])
                            .toJS,
                      )
                      .toDart)
                  as JSArrayBuffer)
              .toDart
              .asUint8List(),
    );
    _require(
      _same(reverse, payload),
      'WebCrypto could not decrypt cryptography',
    );
    log(
      true,
      'AES-256-GCM cross-vector both directions equal=true nonce=12 tag=16 AAD=true',
    );
  }

  Future<void> _hkdf() async {
    final input = _random(32);
    final salt = _random(16);
    final info = utf8.encode('gift-huddle web vault-a v1');
    final key = await _import(input, 'HKDF', ['deriveBits']);
    // Exercise both an explicit salt and the empty salt used by the ADR.
    for (final nonce in [salt, Uint8List(0)]) {
      final native = await _timed(
        'WebCrypto HKDF-SHA256 salt=${nonce.length}',
        () => _derive(key, {
          'name': 'HKDF',
          'hash': 'SHA-256',
          'salt': nonce.toJS,
          'info': _bytes(info).toJS,
        }),
      );
      final algorithm = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
      final dart = await _timed(
        'cryptography HKDF-SHA256 backend=${_backend(algorithm)}',
        () async => (await algorithm.deriveKey(
          secretKey: SecretKey(input),
          nonce: nonce,
          info: info,
        )).extractBytes(),
      );
      _require(_same(native, dart), 'HKDF outputs differ');
      log(true, 'HKDF-SHA256 salt=${nonce.length} output=32 equal=true');
    }
  }

  Future<void> _x25519() async {
    final algorithm = X25519();
    // Seed-based generation and extraction mirror DeviceKeys, without importing
    // the shared sync implementation into this independent entrypoint.
    final a = await _timed(
      'cryptography X25519 generate/extract A backend=${_backend(algorithm)}',
      () async => (await algorithm.newKeyPairFromSeed(_random(32))).extract(),
    );
    final b = await _timed(
      'cryptography X25519 generate/extract B',
      () async => (await algorithm.newKeyPairFromSeed(_random(32))).extract(),
    );
    final ab = await _timed(
      'cryptography X25519 agree A/B',
      () async => (await algorithm.sharedSecretKey(
        keyPair: a,
        remotePublicKey: b.publicKey,
      )).extractBytes(),
    );
    final ba = await _timed(
      'cryptography X25519 agree B/A',
      () async => (await algorithm.sharedSecretKey(
        keyPair: b,
        remotePublicKey: a.publicKey,
      )).extractBytes(),
    );
    _require(
      ab.length == 32 && _same(ab, ba) && ab.any((v) => v != 0),
      'X25519 agreement differs or is zero',
    );
    log(true, 'X25519 shared secret 32 bytes equal=true nonzero=true');
  }

  Future<void> _ed25519() async {
    final algorithm = Ed25519();
    final pair = await _timed(
      'cryptography Ed25519 generate/extract backend=${_backend(algorithm)}',
      () async => (await algorithm.newKeyPairFromSeed(_random(32))).extract(),
    );
    final message = utf8.encode('Gift Huddle probe: Aritz, Nora, Leo');
    final signature = await _timed(
      'cryptography Ed25519 sign',
      () => algorithm.sign(message, keyPair: pair),
    );
    final valid = await _timed(
      'cryptography Ed25519 verify',
      () => algorithm.verify(message, signature: signature),
    );
    final altered = await algorithm.verify([
      ...message,
      0,
    ], signature: signature);
    _require(valid && !altered, 'Ed25519 verification failed');
    log(
      true,
      'Ed25519 signature=${signature.bytes.length} valid=true tampered=false',
    );
  }
}

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key, required this.probe});
  final BrowserProbe probe;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Gift Huddle browser probe',
    theme: ThemeData(
      fontFamily: kAppFontFamily,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
    ),
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Gift Huddle browser probe (development only)'),
              const Text(
                'Font: Inter bundled locally. Open two tabs for Locks/BroadcastChannel. '
                'Use Back/Forward for pageshow persisted; a held Web Lock can affect BFCache eligibility.',
              ),
              TextFormField(
                initialValue:
                    'Aritz, Nora, Leo: café, àvia, il·lusió, pingüí, mañana',
                decoration: const InputDecoration(
                  labelText: 'Edit accented text (local Inter font)',
                ),
              ),
              TextButton(
                onPressed: probe.sendMessage,
                child: const Text('Send BroadcastChannel hello'),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: probe,
                  builder: (context, child) => SingleChildScrollView(
                    child: SelectableText(probe.lines.join('\n')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
