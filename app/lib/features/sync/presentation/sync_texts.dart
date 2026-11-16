import 'package:clock/clock.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/sync_status.dart';

/// La línea de estado: «Sincronizado hace 1 min», «Sin conexión, se enviará
/// luego»...
String syncStatusText(
  AppLocalizations l10n,
  SyncStatus status, {
  DateTime? now,
}) {
  switch (status.phase) {
    case SyncPhase.notConfigured:
      return l10n.syncStatusNotConfigured;
    case SyncPhase.noFamily:
      return l10n.syncStatusNoFamily;
    case SyncPhase.disabled:
      return l10n.syncStatusDisabled;
    case SyncPhase.removed:
      return l10n.healthRevokedTitle;
    case SyncPhase.idle:
      return l10n.syncStatusIdle;
    case SyncPhase.waitingForPeer:
      return l10n.syncStatusWaitingPeer;
    case SyncPhase.syncing:
      return l10n.syncStatusSyncing;
    case SyncPhase.synced:
      return _ago(l10n, status.lastSyncAt, now ?? clock.now());
    case SyncPhase.offline:
      return l10n.syncStatusOffline;
    case SyncPhase.error:
      return l10n.syncStatusError;
  }
}

String _ago(AppLocalizations l10n, DateTime? at, DateTime now) {
  if (at == null) {
    return l10n.syncStatusSyncedNow;
  }
  final elapsed = now.difference(at);
  if (elapsed.inMinutes < 1) {
    return l10n.syncStatusSyncedNow;
  }
  if (elapsed.inHours < 1) {
    return l10n.syncStatusSyncedMinutes(elapsed.inMinutes);
  }
  if (elapsed.inDays < 1) {
    return l10n.syncStatusSyncedHours(elapsed.inHours);
  }
  return l10n.syncStatusSyncedDays(elapsed.inDays);
}

/// El estado en una o dos palabras, para la fila «Móviles de la familia» de
/// Ajustes («2 · al día»); `null` si esta versión no sincroniza o si todavía
/// no hay un segundo móvil (la fila dice entonces «Solo este»).
String? syncShortText(AppLocalizations l10n, SyncStatus status) {
  switch (status.phase) {
    case SyncPhase.notConfigured:
    case SyncPhase.noFamily:
    case SyncPhase.waitingForPeer:
      return null;
    case SyncPhase.disabled:
      return l10n.syncShortOff;
    case SyncPhase.removed:
      return l10n.healthRevokedTitle;
    case SyncPhase.idle:
      return l10n.syncShortPending;
    case SyncPhase.syncing:
      return l10n.syncShortSyncing;
    case SyncPhase.synced:
      return l10n.syncShortUpToDate;
    case SyncPhase.offline:
      return l10n.syncShortOffline;
    case SyncPhase.error:
      return l10n.syncShortError;
  }
}

/// La explicación de un error de sincronización, o `null` si no hay.
String? syncIssueText(AppLocalizations l10n, SyncStatus status) {
  if (status.phase != SyncPhase.error) {
    return null;
  }
  switch (status.issue ?? SyncIssue.unknown) {
    case SyncIssue.auth:
      return l10n.syncIssueAuth;
    case SyncIssue.clockDrift:
      return l10n.syncIssueClockDrift;
    case SyncIssue.tooLarge:
      return l10n.syncIssueTooLarge;
    case SyncIssue.firstUploadTooLarge:
      return l10n.syncIssueFirstUpload;
    case SyncIssue.server:
      return l10n.syncIssueServer;
    case SyncIssue.rateLimited:
      return l10n.syncIssueRateLimited;
    case SyncIssue.unreadable:
      return l10n.syncIssueUnreadable;
    case SyncIssue.unknown:
      return l10n.syncIssueUnknown;
  }
}
