import 'dart:async';
import 'dart:convert';

import 'vault_store.dart';

/// Minimal IndexedDB boundary. Request success only supplies data; durability
/// is reported exclusively by the transaction's complete event.
abstract interface class VaultStorageTransaction {
  set onComplete(void Function() callback);
  set onFailure(void Function() callback);
  void read(void Function(String? value) loaded);
  void put(String value);
  void abort();
}

Future<VaultState> runVaultTransaction(
  VaultStorageTransaction tx,
  VaultState Function(VaultState)? update,
) {
  final done = Completer<VaultState>();
  VaultState? result;
  Object? failure;
  tx.onComplete = () {
    if (!done.isCompleted) done.complete(result!);
  };
  tx.onFailure = () {
    if (!done.isCompleted) {
      done.completeError(failure ?? StateError('Vault transaction failed'));
    }
  };
  tx.read((raw) {
    try {
      final state = raw == null
          ? VaultState()
          : VaultState.fromJson(jsonDecode(raw) as Map);
      result = update == null ? state : update(state);
      if (update != null) tx.put(jsonEncode(result!.toJson()));
    } catch (e) {
      failure = e;
      tx.abort();
    }
  });
  return done.future;
}
