import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lock/application/lock_controller.dart';
import 'pin_verify_screen.dart';

/// Pide a quien tiene el móvil que demuestre que es su dueño antes de algo
/// que no se puede deshacer («Borrar todo», sustituir la lista al unirse a
/// otra familia): `true` si no hay PIN configurado o si lo demuestra.
///
/// Con huella o rostro activados se piden primero ([biometricReason]), como
/// al desbloquear; si se cancelan o fallan, queda el PIN, con [title] y
/// [message]. La pantalla del PIN avisa de los intentos que quedan y de la
/// espera, igual que al quitar el bloqueo, y salir de ella sin acertar
/// devuelve `false`. Lanza si el bloqueo no se puede leer.
Future<bool> verifyOwner(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String message,
  required String biometricReason,
}) async {
  final lock = ref.read(lockControllerProvider.notifier);
  final state = await ref.read(lockControllerProvider.future);
  if (!state.pinSet) {
    return true;
  }
  if (await lock.confirmWithBiometrics(biometricReason)) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  final verified = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => PinVerifyScreen(
        title: title,
        message: message,
        onSubmit: lock.unlock,
      ),
    ),
  );
  return verified ?? false;
}
