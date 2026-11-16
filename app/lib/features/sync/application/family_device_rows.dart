// La lista de móviles de la familia v2 para Ajustes › Móviles de la familia.
// Aparte de `family_devices.dart` (Dart puro) porque necesita Riverpod y los
// controladores de sincronización y emparejamiento.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../family/application/family_controller.dart';
import 'family_devices.dart';
import 'sync_controller.dart';
import 'v2_health_provider.dart';

/// Los móviles activos del registro firmado de la familia (este primero), o
/// null si la familia sigue en v1 o no hay familia v2 local.
///
/// Deriva de [localRegistryViewProvider] (la misma lectura verificada que usa
/// `devicePersonIdsProvider`): se recalcula cuando esa vista cambia, que ya
/// cubre terminar una vuelta de sincronización, un emparejamiento, quitar un
/// móvil o salir, y observa el documento común para actualizar también los
/// nombres cifrados que llegan en una vuelta posterior.
/// Si retiraron este móvil, conserva solo su fila junto a la copia local.
final familyDeviceRowsProvider = FutureProvider<List<FamilyDeviceRow>?>((
  ref,
) async {
  final family = await ref.watch(familyControllerProvider.future);
  final view = await ref.watch(localRegistryViewProvider.future);
  if (view == null) return null;
  final health = await ref.watch(v2HealthProvider.future);
  if (health.revokedByOthers) {
    return [
      FamilyDeviceRow(
        deviceId: view.me,
        isSelf: true,
        personId: family.identity?.selfRecipientId,
        deviceName: family.identity?.deviceName,
      ),
    ];
  }
  return familyDeviceRows(
    view,
    selfName: family.identity?.deviceName,
    common: family.doc,
  );
});
