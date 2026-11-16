import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/envelope.dart';
import '../../family/application/family_controller.dart';
import '../../family/domain/family_errors.dart';
import '../../sync/application/sync_controller.dart';

/// Emparejar dos móviles con un QR en persona.
///
/// El QR lleva la clave de la familia: se enseña en persona y nunca se envía.
class PairingService {
  /// Crea el servicio.
  PairingService(this._ref);

  final Ref _ref;

  FamilyController get _controller =>
      _ref.read(familyControllerProvider.notifier);

  /// El texto del QR que enseña el móvil que ya tiene la familia.
  ///
  /// Enseñarlo es la única señal de que puede llegar un segundo móvil (el QR
  /// no avisa de que lo han leído): desde aquí la sincronización mira, sin
  /// subir nada, si el otro ya ha entrado ([SyncController.expectPeer]).
  ///
  /// Lanza [NoFamilyException] si todavía no hay familia.
  Future<String> qrTextForPairing() async {
    final state = await _ref.read(familyControllerProvider.future);
    final identity = state.identity;
    final key = _controller.familyKey;
    if (identity == null || key == null) {
      throw const NoFamilyException();
    }
    final text = PairingPayload(
      listId: identity.listId,
      key: key,
      deviceName: identity.deviceName,
    ).toQrText();
    await _ref.read(syncControllerProvider.notifier).expectPeer();
    return text;
  }

  /// Une este móvil a la familia del QR leído.
  ///
  /// Lanza [PairingFormatException] si el texto no es un QR de Gift Huddle.
  /// Si este móvil ya tiene otra familia con datos, lanza
  /// [FamilyConflictException]: la interfaz pide confirmación y repite con
  /// `replace: true`. [deviceName] es el nombre de este móvil.
  Future<JoinResult> joinFromQr(
    String text, {
    bool replace = false,
    String deviceName = '',
  }) async => _controller.joinFamily(
    payload: PairingPayload.parse(text),
    deviceName: deviceName,
    replace: replace,
  );
}

/// El servicio de emparejamiento.
final pairingServiceProvider = Provider<PairingService>(PairingService.new);
