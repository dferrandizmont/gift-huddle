import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'vault_store.dart';
import 'vault_transaction.dart';

Future<VaultStore> openVaultStore(String name) async {
  final factory = web.window.indexedDB;
  final request = factory.open(name, 1);
  final ready = Completer<VaultStore>();
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore('vault');
  }).toJS;
  request.onsuccess = ((web.Event _) {
    final db = request.result as web.IDBDatabase;
    db.onversionchange = ((web.Event _) => db.close()).toJS;
    if (ready.isCompleted) {
      db.close();
      return;
    }
    ready.complete(_IndexedVaultStore(db));
  }).toJS;
  void fail() {
    if (!ready.isCompleted) {
      ready.completeError(StateError('IndexedDB unavailable'));
    }
  }

  request.onerror = ((web.Event _) => fail()).toJS;
  request.onblocked = ((web.Event _) => fail()).toJS;
  return ready.future;
}

Future<bool> requestVaultPersistence() async =>
    (await web.window.navigator.storage.persist().toDart).toDart;

class _IndexedVaultStore extends VaultStore {
  _IndexedVaultStore(this.db);
  final web.IDBDatabase db;
  Future<VaultState> _run(VaultState Function(VaultState)? update) {
    final tx = db.transaction(
      'vault'.toJS,
      update == null ? 'readonly' : 'readwrite',
    );
    return runVaultTransaction(_BrowserTransaction(tx), update);
  }

  @override
  Future<VaultState> read() => _run(null);
  @override
  Future<void> transaction(VaultState Function(VaultState) update) async {
    await _run(update);
  }
}

class _BrowserTransaction implements VaultStorageTransaction {
  _BrowserTransaction(this.tx);
  final web.IDBTransaction tx;

  @override
  set onComplete(void Function() callback) {
    tx.oncomplete = ((web.Event _) => callback()).toJS;
  }

  @override
  set onFailure(void Function() callback) {
    tx.onabort = ((web.Event _) => callback()).toJS;
    tx.onerror = ((web.Event _) => callback()).toJS;
  }

  @override
  void read(void Function(String?) loaded) {
    final request = tx.objectStore('vault').get('state'.toJS);
    request.onsuccess = ((web.Event _) {
      final raw = request.result;
      loaded(
        raw == null || raw.isUndefinedOrNull ? null : (raw as JSString).toDart,
      );
    }).toJS;
  }

  @override
  void put(String value) =>
      tx.objectStore('vault').put(value.toJS, 'state'.toJS);

  @override
  void abort() => tx.abort();
}
