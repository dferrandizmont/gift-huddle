import 'dart:async';

import 'package:regalos/core/sync/recovery.dart';
import 'package:regalos/features/family/data/recovery_wordlist_loader.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';

/// El código de recuperación de las pruebas: 32 bytes fijos, con sus 24
/// palabras y su QR reales.
Future<RecoveryCodeDisplay> sampleRecoveryDisplay() async {
  final wordlist = await loadRecoveryWordlist();
  final code = RecoveryCode([for (var i = 0; i < 32; i++) (i * 37 + 11) % 256]);
  return RecoveryCodeDisplay(code.toWords(wordlist), code.toQrText());
}

/// La capa de aplicación del código de recuperación sin red ni almacenes: lo
/// que se le pide queda apuntado en [calls] y lo que contesta lo decide la
/// prueba.
class FakeRecovery extends RecoveryApplication {
  /// Crea la capa con el estado de [initial].
  FakeRecovery({
    this.initial = const RecoveryStatus(RecoveryReadiness.absent),
    this.display,
  });

  /// El estado de partida.
  final RecoveryStatus initial;

  /// Lo que entregan crear y cambiar.
  RecoveryCodeDisplay? display;

  /// Lo que devuelve `takeCreatedCode` (una creación cortada).
  RecoveryCodeDisplay? reclaim;

  /// Todo lo pedido, en orden.
  final List<String> calls = [];

  /// El estado en que quedan crear, cambiar y reintentar.
  RecoveryStatus afterCreate = const RecoveryStatus(RecoveryReadiness.prepared);

  /// Si crear o cambiar fallan con esto.
  Object? createError;

  /// Mientras no se complete, crear no termina.
  Completer<void>? holdCreate;

  /// Si restaurar falla con esto.
  Object? restoreError;

  /// El estado en que acaba una restauración, si no falla.
  RecoveryStatus? restoreFinal;

  /// Mientras no se complete, restaurar no termina.
  Completer<void>? holdRestore;

  /// Qué pasa al restaurar (por ejemplo, dar de alta la familia de muestra).
  Future<void> Function()? onRestored;

  @override
  RecoveryStatus build() => initial;

  /// Cambia el estado desde la prueba.
  void push(RecoveryStatus status) => state = status;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> confirmCreatedCode(RecoveryCodeDisplay display) async {
    calls.add('confirm');
    state = afterCreate;
  }

  @override
  Future<RecoveryCodeDisplay> createCode() => _create('create');

  @override
  Future<RecoveryCodeDisplay> rotateCode() => _create('rotate');

  Future<RecoveryCodeDisplay> _create(String name) async {
    calls.add(name);
    await holdCreate?.future;
    final error = createError;
    if (error != null) {
      throw error;
    }
    state = afterCreate.readiness == RecoveryReadiness.prepared
        ? const RecoveryStatus(RecoveryReadiness.confirmationPending)
        : afterCreate;
    return display ?? await sampleRecoveryDisplay();
  }

  @override
  Future<void> dismissFailure() async {
    calls.add('dismiss');
    state = const RecoveryStatus(RecoveryReadiness.absent);
  }

  @override
  Future<bool> hasCodeDisplay() async {
    calls.add('has');
    return reclaim != null;
  }

  @override
  Future<void> cancelMaintenance() async {
    calls.add('cancelMaintenance');
    state = const RecoveryStatus(RecoveryReadiness.prepared);
  }

  @override
  Future<RecoveryCodeDisplay?> takeCreatedCode() async {
    calls.add('take');
    final next = reclaim;
    reclaim = null;
    return next;
  }

  /// Lo que contesta `removalStopsRemoteSync`: si quitar el código deja la
  /// lista solo en este móvil.
  bool removalStops = false;

  @override
  Future<bool> removalStopsRemoteSync() async {
    calls.add('removalCheck');
    return removalStops;
  }

  @override
  Future<void> retireCode() async {
    calls.add('retire');
    state = const RecoveryStatus(RecoveryReadiness.absent);
  }

  @override
  Future<void> retry() async {
    calls.add('retry');
    await _restore();
  }

  /// Si cancelar falla con esto.
  Object? abandonError;

  @override
  Future<void> abandon() async {
    calls.add('abandon');
    final error = abandonError;
    if (error != null) {
      throw error;
    }
    final transferred = state.installationTransferred;
    state = RecoveryStatus(
      transferred ? RecoveryReadiness.transferred : RecoveryReadiness.absent,
      installationTransferred: transferred,
    );
  }

  @override
  Future<void> restoreWords(
    String words, {
    bool replaceExisting = false,
  }) async {
    calls.add(replaceExisting ? 'words+replace' : 'words');
    lastWords = words;
    await _restore();
  }

  @override
  Future<void> restoreQr(String text, {bool replaceExisting = false}) async {
    calls.add(replaceExisting ? 'qr+replace' : 'qr');
    lastQr = text;
    await _restore();
  }

  /// Las palabras o el QR con que se pidió restaurar por última vez.
  String? lastWords;
  String? lastQr;

  Future<void> _restore() async {
    reportPhase(RecoveryPhase.locating);
    await holdRestore?.future;
    final error = restoreError;
    if (error != null) {
      restoreError = null;
      throw error;
    }
    await onRestored?.call();
    state = restoreFinal ?? const RecoveryStatus(RecoveryReadiness.prepared);
  }
}
