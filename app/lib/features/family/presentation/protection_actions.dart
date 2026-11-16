import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/family_controller.dart';

/// Lo que la interfaz de los regalos en secreto le pide a la lógica (pedir,
/// confirmar y quitar la protección de una persona, y reintentar sus regalos
/// pendientes). Todo pasa por el controlador de la familia; este contrato solo
/// existe para que las hojas no dependan de él y las pruebas de pantalla
/// puedan apuntar las llamadas.
abstract class ProtectionActions {
  /// Pide la protección de [personId]: solo guarda la petición.
  Future<void> request(String personId);

  /// Confirma la petición desde un móvil con permiso.
  Future<void> activate(String personId);

  /// Quita la protección: publica todos los regalos disponibles.
  Future<void> deactivate(String personId);

  /// Vuelve a intentar guardar los regalos pendientes de [personId].
  Future<void> retryPending(String personId);
}

class _ControllerActions implements ProtectionActions {
  _ControllerActions(this._ref);

  final Ref _ref;

  FamilyController get _controller =>
      _ref.read(familyControllerProvider.notifier);

  @override
  Future<void> request(String personId) =>
      _controller.requestProtection(personId);

  @override
  Future<void> activate(String personId) =>
      _controller.activateProtection(personId);

  @override
  Future<void> deactivate(String personId) =>
      _controller.deactivateProtection(personId);

  @override
  Future<void> retryPending(String personId) =>
      _controller.retryPendingProtectedGifts(personId);
}

/// Las acciones de protección, sobre el controlador de la familia.
final protectionActionsProvider = Provider<ProtectionActions>(
  _ControllerActions.new,
);
