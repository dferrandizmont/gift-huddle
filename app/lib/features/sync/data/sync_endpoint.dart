/// Servidor de sincronización por defecto (Worker v2 en el dominio propio).
const String kDefaultSyncHost = 'https://sync.gifthuddle.app';

/// Origen por defecto de los enlaces de invitación (`/i#<id>`), que abre la
/// app por App Links y Universal Links.
const String kDefaultInvitationOrigin = 'https://gifthuddle.app';

/// API origin: `--dart-define=SYNC_API_ORIGIN=https://sync.example`, o el
/// antiguo `SYNC_HOST`. Sin ninguno de los dos, [kDefaultSyncHost]. Una
/// cadena vacía a propósito (`--dart-define=SYNC_HOST=`) no la apaga: para
/// probar sin servidor se sustituye `syncHostProvider`.
const String kSyncHost = String.fromEnvironment(
  'SYNC_API_ORIGIN',
  defaultValue: String.fromEnvironment(
    'SYNC_HOST',
    defaultValue: kDefaultSyncHost,
  ),
);

/// Origen de las invitaciones: `--dart-define=SYNC_INVITATION_ORIGIN=...`, o
/// [kDefaultInvitationOrigin].
const String kInvitationOrigin = String.fromEnvironment(
  'SYNC_INVITATION_ORIGIN',
  defaultValue: kDefaultInvitationOrigin,
);

/// A dónde apunta la sincronización.
class SyncEndpoint {
  const SyncEndpoint._(this.base, this.invitationOrigin);

  /// Dirección base (`https://host` o, en desarrollo, `http://localhost:8787`).
  final Uri base;

  final Uri invitationOrigin;

  String get invitationHost => invitationOrigin.hasPort
      ? '${invitationOrigin.host}:${invitationOrigin.port}'
      : invitationOrigin.host;

  /// API host, kept for callers of the original endpoint contract.
  String get host => base.hasPort ? '${base.host}:${base.port}' : base.host;

  /// Interpreta `SYNC_HOST`: un host (`sync.example.workers.dev`) o una URL
  /// completa. Solo se admite `http` hacia el propio equipo o el emulador de
  /// Android (`localhost`, `127.0.0.1`, `10.0.2.2`); lo demás es `https`.
  /// Devuelve `null` si está vacío o no vale.
  static SyncEndpoint? parse(String raw, {String invitationOrigin = ''}) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    final withScheme = text.contains('://') ? text : 'https://$text';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final local = const {
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
    }.contains(uri.host);
    if (uri.scheme == 'http' && !local) {
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }
    final base = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
    final invitations = invitationOrigin.trim().isEmpty
        ? base
        : parse(invitationOrigin)?.base;
    if (invitations == null) return null;
    return SyncEndpoint._(base, invitations);
  }
}
