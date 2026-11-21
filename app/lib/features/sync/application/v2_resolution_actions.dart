import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/device_registry.dart';
import '../../family/application/family_controller.dart';
import '../data/sync_config.dart';
import '../data/sync_transport.dart';
import 'app_sync_v2_local.dart';
import 'family_device_review.dart';
import 'family_device_actions.dart' as device_actions;
import 'family_devices.dart';
import 'sync_controller.dart';
import 'sync_v2_engine.dart';

/// Resoluciones individuales de los avisos v2, serializadas con el motor.
final v2ResolutionActionsProvider = Provider<V2ResolutionActions>(
  V2ResolutionActions.new,
);

class V2ResolutionActions {
  V2ResolutionActions(this._ref);
  final Ref _ref;

  /// Corta una credencial sin respaldo y dice qué ha pasado de verdad. El id
  /// es el deviceId de la fila del servicio, no la credencial secreta. Guarda
  /// la intención antes de la red; si falla, propaga el error y la próxima
  /// vuelta reintenta automáticamente. El resultado lo decide el motor dentro
  /// de la operación, con el registro verificado: solo [UnbackedRevocation.revoked]
  /// significa que el acceso se ha cortado.
  Future<UnbackedRevocation> revokeUnbackedCredential(String credentialId) =>
      _ref
          .read(familyControllerProvider.notifier)
          .withRecoveredSelfPersonChange(() async {
            final local = await AppSyncV2Local.load(_ref);
            final transport = _ref.read(syncV2TransportProvider);
            if (local == null || transport == null) {
              throw SyncNotReadyException(_ref.read(syncControllerProvider));
            }
            final state = await local.readState();
            if (credentialId == local.identity.deviceId) {
              return UnbackedRevocation.keptBecauseBacked;
            }
            if (!(state.health?.unbackedCredentials.contains(credentialId) ??
                    false) &&
                !state.pendingUnbackedRevocations.contains(credentialId)) {
              return UnbackedRevocation.alreadyResolved;
            }
            await local.saveState(
              state.copyWith(
                pendingUnbackedRevocations: {
                  ...state.pendingUnbackedRevocations,
                  credentialId,
                },
              ),
            );
            final engine = SyncV2Engine(transport: transport, local: local);
            try {
              await engine.sync();
            } finally {
              _ref.invalidate(localRegistryReadProvider);
            }
            final outcome = engine.unbackedOutcomes[credentialId];
            if (outcome != null) return outcome;
            // La lista no se estuvo quieta (412 seguidos): la vuelta siguió y
            // la intención queda para la siguiente. No se ha cortado nada.
            if ((await local.readState()).pendingUnbackedRevocations.contains(
              credentialId,
            )) {
              throw const SyncTransportException(
                SyncFailure.server,
                'la lista cambia demasiado deprisa',
              );
            }
            // La vuelta quitó la intención sin decidir nada: ya estaba
            // resuelta.
            return UnbackedRevocation.alreadyResolved;
          });

  /// Mismas consecuencias y aviso N7 que la eliminación de un móvil.
  Future<device_actions.RemovalPreview> previewDeparture(String deviceId) =>
      _ref
          .read(familyControllerProvider.notifier)
          .withRecoveredSelfPersonChange(() async {
            final local = await AppSyncV2Local.load(_ref);
            if (local == null) {
              throw SyncNotReadyException(_ref.read(syncControllerProvider));
            }
            return device_actions.previewRemoval(
              local: local,
              deviceId: deviceId,
            );
          });

  /// Completa la baja firmada de un miembro cuya credencial ya está
  /// revocada. Reutiliza removeDevice (intención recuperable, huérfanos y
  /// rotación). Repetir no crea otra declaración ni otra época y devuelve null.
  /// Sin aceptar N7, lanza DeviceRemovalChangedException antes de persistir.
  Future<RegistryChange?> completeDeparture(
    String deviceId, {
    bool selfWaitAccepted = false,
  }) => _ref
      .read(familyControllerProvider.notifier)
      .withRecoveredSelfPersonChange(() async {
        final local = await AppSyncV2Local.load(_ref);
        final transport = _ref.read(syncV2TransportProvider);
        if (local == null || transport == null) return null;
        final state = await local.readState();
        final view = await localView(local);
        try {
          if (view.revoked.contains(deviceId)) {
            if (state.revocationOperations.containsKey(deviceId) ||
                state.pendingRevocations.contains(deviceId)) {
              await SyncV2Engine(transport: transport, local: local).sync();
            }
            return null;
          }
          if (!(state.health?.departedDevices.contains(deviceId) ?? false)) {
            return null;
          }
          if (!selfWaitAccepted &&
              (await device_actions.previewRemoval(
                local: local,
                deviceId: deviceId,
              )).selfWouldWait) {
            throw const device_actions.DeviceRemovalChangedException();
          }
          return await removeDevice(
            transport: transport,
            local: local,
            deviceId: deviceId,
            rememberOrphans: (orphans) async {
              final registry = await local.registry();
              await _ref.read(rememberedOrphansProvider.notifier).remember([
                for (final d in orphans)
                  DeviceReviewItem(
                    deviceId: d.deviceId,
                    personId: d.personId,
                    reason: DeviceReviewReason.orphan,
                    recordDigest: d.recordDigest,
                    recordChanged:
                        (registry.recordByDigest(d.recordDigest)?.seq ?? 1) > 1,
                    becauseOf: deviceId,
                  ),
              ]);
            },
          );
        } finally {
          _ref.invalidate(localRegistryReadProvider);
        }
      });
}
