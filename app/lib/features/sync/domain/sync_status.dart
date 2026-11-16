import 'package:flutter/foundation.dart';

/// En qué punto está la sincronización de este móvil.
enum SyncPhase {
  /// No hay servidor configurado en esta versión (`SYNC_HOST` vacío).
  notConfigured,

  /// Todavía no hay familia.
  noFamily,

  /// La persona la ha apagado.
  disabled,

  /// Otro móvil retiró este de la familia. Solo se conserva la copia local.
  removed,

  /// Encendida, aún sin ninguna sincronización hecha.
  idle,

  /// Encendida, pero la familia todavía no tiene un segundo móvil emparejado:
  /// hasta entonces no se sube nada ni se abre el WebSocket.
  waitingForPeer,

  /// Hablando con el servidor.
  syncing,

  /// Al día.
  synced,

  /// No hay red: lo local está guardado y se enviará cuando vuelva.
  offline,

  /// Falla algo que no es la red; mira [SyncStatus.issue].
  error,
}

/// Por qué está en [SyncPhase.error].
enum SyncIssue {
  /// El servidor no acepta la clave de esta familia.
  auth,

  /// Otro móvil tiene el reloj más de un día adelantado.
  clockDrift,

  /// La lista pasa del tamaño máximo del servidor.
  tooLarge,

  /// La primera subida pasa del tamaño máximo de una primera subida (256 KiB).
  firstUploadTooLarge,

  /// El servidor falla (`5xx`) o contesta algo raro.
  server,

  /// Demasiadas peticiones (`429`).
  rateLimited,

  /// El sobre del servidor no se puede abrir con la clave de la familia.
  unreadable,

  /// Cualquier otra cosa.
  unknown,
}

/// Estado observable de la sincronización.
@immutable
class SyncStatus {
  /// Crea el estado.
  const SyncStatus(this.phase, {this.lastSyncAt, this.issue});

  /// Sin servidor.
  const SyncStatus.notConfigured() : this(SyncPhase.notConfigured);

  /// Fase actual.
  final SyncPhase phase;

  /// Hora de la última sincronización correcta (de este arranque o la
  /// anterior de esta sesión).
  final DateTime? lastSyncAt;

  /// Causa, solo con [SyncPhase.error].
  final SyncIssue? issue;

  /// Si la sincronización está encendida (aunque siga a la espera del segundo
  /// móvil y todavía no hable con el servidor).
  bool get active =>
      phase != SyncPhase.notConfigured &&
      phase != SyncPhase.noFamily &&
      phase != SyncPhase.disabled &&
      phase != SyncPhase.removed;

  /// Copia con otra fase (conserva la última hora salvo que se cambie).
  SyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastSyncAt,
    SyncIssue? issue,
  }) => SyncStatus(
    phase ?? this.phase,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    issue: phase != null && phase != SyncPhase.error
        ? null
        : (issue ?? this.issue),
  );

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.phase == phase &&
      other.lastSyncAt == lastSyncAt &&
      other.issue == issue;

  @override
  int get hashCode => Object.hash(phase, lastSyncAt, issue);

  @override
  String toString() => 'SyncStatus($phase, $lastSyncAt, $issue)';
}
