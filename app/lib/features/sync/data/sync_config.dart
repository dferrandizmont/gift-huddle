import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_endpoint.dart';
import 'sync_transport_factory.dart';
import 'sync_transport.dart';
import 'sync_transport_common.dart';
import 'sync_transport_v2.dart';

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

/// Tiempos de la sincronización. Las pruebas los acortan.
class SyncTiming {
  /// Crea los tiempos.
  const SyncTiming({
    this.debounce = const Duration(seconds: 2),
    this.backoff = const [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 45),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ],
    this.watchBackoff = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
    ],
    this.invitePoll = const Duration(seconds: 4),
    this.inviteHostPoll = const Duration(seconds: 10),
    this.inviteTimeout = const Duration(minutes: 10),
    this.maxConflicts = 3,
    this.peerPoll = const Duration(seconds: 12),
    this.peerPollFor = const Duration(minutes: 10),
    this.peerWait = const Duration(days: 3),
  });

  /// Espera tras un cambio local para agrupar varios en una sola subida.
  final Duration debounce;

  /// Esperas crecientes entre reintentos cuando falla la red; la última se
  /// repite.
  final List<Duration> backoff;

  /// Esperas entre intentos de reabrir el WebSocket si se corta. Más cortas
  /// que [backoff]: es la vía por la que llegan los cambios del otro móvil y
  /// reconectar no cuesta nada. Se reinician en cuanto una conexión se abre.
  final List<Duration> watchBackoff;

  /// Cada cuánto pregunta por la aprobación quien entra con una invitación.
  /// El servidor admite 30 peticiones por minuto e IP en estas rutas: 4 s o
  /// más.
  final Duration invitePoll;

  /// Cada cuánto comprueba peticiones quien invita (el WebSocket avisa antes;
  /// esto es la red de seguridad, más lenta para no pasar del límite de
  /// peticiones por IP a las rutas de invitación).
  final Duration inviteHostPoll;

  /// Cuánto espera quien entra a que lo aprueben.
  final Duration inviteTimeout;

  /// Reintentos seguidos tras un `409` antes de dejarlo para luego.
  final int maxConflicts;

  /// Cada cuánto mira, tras enseñar el QR de emparejar, si el otro móvil ya
  /// ha subido su primera copia (el QR no avisa de que lo han leído).
  final Duration peerPoll;

  /// Cuánto dura ese sondeo desde que se enseñó el QR. Después solo mira al
  /// arrancar, al volver a la app y tras un cambio local.
  final Duration peerPollFor;

  /// Cuánto sigue mirando desde que se enseñó el QR. Pasado ese plazo sin
  /// que nadie entre, vuelve a no hablar con el servidor.
  final Duration peerWait;

  /// La espera antes de reabrir el WebSocket tras [failures] cortes seguidos
  /// (empezando en 1).
  Duration watchBackoffFor(int failures) {
    if (watchBackoff.isEmpty) {
      return Duration.zero;
    }
    final i = (failures - 1).clamp(0, watchBackoff.length - 1);
    return watchBackoff[i];
  }

  /// La espera del intento [failures] (empezando en 1).
  Duration backoffFor(int failures) {
    if (backoff.isEmpty) {
      return Duration.zero;
    }
    final i = (failures - 1).clamp(0, backoff.length - 1);
    return backoff[i];
  }
}

/// Servidor configurado (cadena vacía si no hay). Las pruebas lo sustituyen.
final syncHostProvider = Provider<String>((ref) => kSyncHost);

/// A dónde apunta la sincronización, o `null` si no está configurada o el
/// valor no vale.
final invitationOriginProvider = Provider<String>((ref) => kInvitationOrigin);

final syncEndpointProvider = Provider<SyncEndpoint?>(
  (ref) => SyncEndpoint.parse(
    ref.watch(syncHostProvider),
    invitationOrigin: ref.watch(invitationOriginProvider),
  ),
);

/// Cliente del servidor, o `null` sin servidor configurado. Las pruebas lo
/// sustituyen por el servidor falso.
final syncTransportProvider = Provider<SyncTransport?>((ref) {
  final endpoint = ref.watch(syncEndpointProvider);
  if (endpoint == null) {
    return null;
  }
  final transport = createSyncTransport(endpoint);
  ref.onDispose(transport.close);
  return transport;
});

/// Cliente de la API v2 (ADR 0004), o `null` sin servidor. Va sobre el mismo
/// transporte que v1; las pruebas lo sustituyen por el Worker falso.
final syncV2TransportProvider = Provider<SyncV2Transport?>((ref) {
  final transport = ref.watch(syncTransportProvider);
  return transport is BaseSyncTransport ? transport.v2 : null;
});

/// Tiempos de la sincronización.
final syncTimingProvider = Provider<SyncTiming>((ref) => const SyncTiming());
