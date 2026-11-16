import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/web_device/data/vault_store.dart';
import 'package:regalos/features/web_device/data/vault_transaction.dart';

class _Transaction implements VaultStorageTransaction {
  @override
  late void Function() onComplete;
  @override
  late void Function() onFailure;
  late void Function(String?) loaded;
  String? pending;
  String durable = jsonEncode(VaultState().toJson());
  bool putSucceeded = false;
  @override
  void read(void Function(String?) callback) => loaded = callback;
  @override
  void put(String value) {
    pending = value;
    putSucceeded = true;
  }

  @override
  void abort() => onFailure();
  void complete() {
    durable = pending ?? durable;
    onComplete();
  }
}

void main() {
  for (final abort in [false, true]) {
    test(
      'successful put waits for transaction ${abort ? 'abort' : 'oncomplete'}',
      () async {
        final tx = _Transaction();
        var saved = false;
        final future =
            runVaultTransaction(
              tx,
              (_) => VaultState(
                pending: VaultSet(
                  header: {'format': 1},
                  box: {'ciphertext': 'opaque'},
                ),
              ),
            ).then((value) {
              saved = true;
              return value;
            });
        final rejected = abort ? expectLater(future, throwsStateError) : null;
        tx.loaded(tx.durable);
        await Future<void>.delayed(Duration.zero);
        expect(tx.putSucceeded, isTrue);
        expect(saved, isFalse);
        expect(
          VaultState.fromJson(jsonDecode(tx.durable) as Map).pending,
          isNull,
        );
        if (abort) {
          tx.abort();
          await rejected;
          expect(saved, isFalse);
          expect(
            VaultState.fromJson(jsonDecode(tx.durable) as Map).pending,
            isNull,
          );
        } else {
          tx.complete();
          expect((await future).pending, isNotNull);
          expect(saved, isTrue);
          expect(
            VaultState.fromJson(jsonDecode(tx.durable) as Map).pending,
            isNotNull,
          );
        }
      },
    );
  }
}
