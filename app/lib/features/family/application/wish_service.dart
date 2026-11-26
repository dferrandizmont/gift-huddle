import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/protected_doc.dart' show ProtectedPersonReason;
import '../../../core/sync/wish.dart';
import '../../../core/sync/wish_author.dart';
import '../../../core/sync/wish_plan.dart';
import '../../web_device/application/web_sync_engine.dart';
import '../../web_device/data/web_family_store.dart';
import '../data/family_store.dart' show familyStoreProvider;
import 'family_controller.dart';

/// Por qué una acción sobre un deseo o su plan no se hizo, en lo que la
/// pantalla necesita para decirlo (ADR 0010). Nunca lleva datos de nadie.
enum WishProblem {
  /// Ya hay 200 deseos vivos para esa persona.
  capReached,

  /// Lo escrito no cabe.
  tooLarge,

  /// Falta el título o un valor no vale.
  invalidField,

  /// Solo la persona del deseo lo cambia o lo quita.
  notOwner,

  /// El deseo ya no está en la lista (o el plan ya no existe).
  wishGone,

  /// Otra persona ya lo ha cogido.
  alreadyClaimed,

  /// Este móvil aún no está aprobado por la familia.
  waitingApproval,

  /// Este móvil no puede escribir deseos ahora (revocado, sin persona...).
  notAllowed,

  /// La persona no tiene móvil en la familia: no hay a quién enseñárselo.
  noDevice,

  /// No se puede abrir ahora el bloque de sorpresas de esa persona.
  blockUnavailable,

  /// No cabe más en el bloque de sorpresas.
  blockFull,

  /// Algún otro móvil con derecho al bloque aún no entiende los planes (no es
  /// la 1.0.7): no se escribe nada hasta que se actualice.
  devicesNeedUpdate,

  /// Otro fallo.
  failed,
}

/// El resultado de una acción: hecha o con su [problem].
final class WishResult {
  /// Hecha. [pending]: quedó guardada solo en este móvil.
  const WishResult.ok({this.wishId, this.planId, this.pending = false})
    : problem = null,
      reason = null,
      devicesNeedUpdate = false;

  /// No hecha.
  const WishResult.failed(
    this.problem, {
    this.reason,
    this.devicesNeedUpdate = false,
  }) : wishId = null,
       planId = null,
       pending = false;

  /// El id del deseo creado, editado o quitado.
  final String? wishId;

  /// El id del plan creado o cambiado.
  final String? planId;

  /// Si el cambio quedó guardado solo en este móvil.
  final bool pending;

  /// Qué falló, o null.
  final WishProblem? problem;

  /// Con [WishProblem.blockUnavailable], el motivo del bloque, si se sabe.
  final ProtectedPersonReason? reason;

  /// Si no se hizo porque algún otro móvil de la familia aún no entiende los
  /// planes de deseos. Va con [WishProblem.devicesNeedUpdate].
  final bool devicesNeedUpdate;

  /// Si se hizo.
  bool get ok => problem == null;
}

/// Lo que las pantallas hacen con los deseos: el móvil lo resuelve el
/// controlador de la familia; la web, su motor (ADR 0010, fase 5).
abstract interface class WishService {
  /// Si se puede sugerir un deseo visible a otra persona («Visible para»).
  bool get canSuggest;

  /// Si se puede convertir un plan en una sorpresa independiente o borrarlo.
  bool get canConvertPlan;

  /// Apunta un deseo para la persona de este dispositivo.
  Future<WishResult> createOwn(VisibleWishPatch patch);

  /// Sugiere un deseo visible para [recipientId].
  Future<WishResult> suggest(String recipientId, VisibleWishPatch patch);

  /// Cambia el contenido visible de un deseo (solo su persona).
  Future<WishResult> edit(String wishId, VisibleWishPatch patch);

  /// Quita un deseo de la lista (solo su persona).
  Future<WishResult> remove(String wishId);

  /// Coge el deseo [wishId].
  Future<WishResult> claim(String wishId, {String? giverId});

  /// Cambia lo privado del plan [planId] de [person].
  Future<WishResult> editPlan(
    String person,
    String planId,
    PrivatePlanPatch patch,
  );

  /// Suelta el plan [planId] de [person].
  Future<WishResult> releasePlan(String person, String planId);

  /// Borra el plan [planId] de [person].
  Future<WishResult> deletePlan(String person, String planId);

  /// El plan [planId] de [person] pasa a ser una sorpresa independiente.
  Future<WishResult> convertPlan(
    String person,
    String planId, {
    required int year,
    String? occasionId,
  });
}

WishResult _fromWrite(WishWrite write) {
  final error = write.error;
  if (error == null) return WishResult.ok(wishId: write.wishId);
  return WishResult.failed(switch (error) {
    WishError.notWishOwner => WishProblem.notOwner,
    WishError.wishNotFound ||
    WishError.wishRemoved ||
    WishError.recipientUnavailable => WishProblem.wishGone,
    WishError.suggestionForSelf ||
    WishError.invalidField => WishProblem.invalidField,
    WishError.capReached => WishProblem.capReached,
    WishError.tooLarge => WishProblem.tooLarge,
    WishError.idInUse => WishProblem.failed,
    WishError.recipientHasNoDevice => WishProblem.noDevice,
    WishError.authorRefused => switch (write.authorError) {
      WishAuthorError.devicePending ||
      WishAuthorError.unknownDevice => WishProblem.waitingApproval,
      _ => WishProblem.notAllowed,
    },
  });
}

/// Qué problema de pantalla es un error de plan.
WishProblem wishProblemForPlanError(WishPlanError error) => switch (error) {
  WishPlanError.notEntitled ||
  WishPlanError.unavailable => WishProblem.blockUnavailable,
  WishPlanError.devicesNeedUpdate => WishProblem.devicesNeedUpdate,
  WishPlanError.wishNotFound ||
  WishPlanError.wishRemoved ||
  WishPlanError.planNotFound => WishProblem.wishGone,
  WishPlanError.alreadyClaimed => WishProblem.alreadyClaimed,
  WishPlanError.planIdInUse => WishProblem.failed,
  WishPlanError.capacityReached ||
  WishPlanError.slotFull => WishProblem.blockFull,
  WishPlanError.tooLarge => WishProblem.tooLarge,
  WishPlanError.invalidField => WishProblem.invalidField,
  // Solo quien cogió el deseo cambia o suelta su reserva.
  WishPlanError.notClaimant => WishProblem.notAllowed,
};

/// El resultado de pantalla de lo que escribió una operación sobre un plan.
WishResult wishResultFromPlanWrite(
  WishPlanWrite write, {
  ProtectedPersonReason? failure,
  ProtectedPersonReason? pending,
}) {
  final error = write.error;
  if (error == null) {
    return WishResult.ok(planId: write.planId, pending: pending != null);
  }
  return WishResult.failed(
    wishProblemForPlanError(error),
    reason: failure,
    devicesNeedUpdate: error == WishPlanError.devicesNeedUpdate,
  );
}

/// El móvil: el controlador de la familia.
final class MobileWishService implements WishService {
  /// Crea el servicio.
  const MobileWishService(this._controller);

  final FamilyController _controller;

  @override
  bool get canSuggest => true;

  @override
  bool get canConvertPlan => true;

  @override
  Future<WishResult> createOwn(VisibleWishPatch patch) async =>
      _fromWrite(await _controller.createOwnWish(patch));

  @override
  Future<WishResult> suggest(
    String recipientId,
    VisibleWishPatch patch,
  ) async =>
      _fromWrite(await _controller.suggestVisibleWish(recipientId, patch));

  @override
  Future<WishResult> edit(String wishId, VisibleWishPatch patch) async =>
      _fromWrite(await _controller.editVisibleWish(wishId, patch));

  @override
  Future<WishResult> remove(String wishId) async =>
      _fromWrite(await _controller.removeWish(wishId));

  WishResult _fromOutcome(WishPlanOutcome outcome) => wishResultFromPlanWrite(
    outcome.write,
    failure: outcome.failure,
    pending: outcome.pendingReason,
  );

  @override
  Future<WishResult> claim(String wishId, {String? giverId}) async =>
      _fromOutcome(await _controller.claimWish(wishId, giverId: giverId));

  @override
  Future<WishResult> editPlan(
    String person,
    String planId,
    PrivatePlanPatch patch,
  ) async =>
      _fromOutcome(await _controller.editWishPlan(person, planId, patch));

  @override
  Future<WishResult> releasePlan(String person, String planId) async =>
      _fromOutcome(await _controller.releaseWishPlan(person, planId));

  @override
  Future<WishResult> deletePlan(String person, String planId) async =>
      _fromOutcome(await _controller.deleteWishPlan(person, planId));

  @override
  Future<WishResult> convertPlan(
    String person,
    String planId, {
    required int year,
    String? occasionId,
  }) async => _fromOutcome(
    await _controller.convertWishPlanToSurprise(
      person,
      planId,
      year: year,
      occasionId: occasionId,
    ),
  );
}

/// La web: su motor. No sugiere deseos a otras personas ni convierte o borra
/// planes (el motor de la web no lo hace): las pantallas no ofrecen esas
/// acciones.
final class WebWishService implements WishService {
  /// Crea el servicio.
  const WebWishService(this._engine);

  final WebSyncEngine _engine;

  @override
  bool get canSuggest => false;

  @override
  bool get canConvertPlan => false;

  Future<WishResult> _guard(Future<WishResult> Function() action) async {
    try {
      return await action();
    } on WebOperationException catch (e) {
      return WishResult.failed(switch (e.operation) {
        'wishAuthor' => WishProblem.waitingApproval,
        'wishUnavailable' => WishProblem.blockUnavailable,
        _ => WishProblem.failed,
      });
    }
  }

  @override
  Future<WishResult> createOwn(VisibleWishPatch patch) =>
      _guard(() async => _fromWrite(await _engine.createOwnWish(patch)));

  @override
  Future<WishResult> suggest(
    String recipientId,
    VisibleWishPatch patch,
  ) async => const WishResult.failed(WishProblem.notAllowed);

  @override
  Future<WishResult> edit(String wishId, VisibleWishPatch patch) =>
      _guard(() async => _fromWrite(await _engine.editOwnWish(wishId, patch)));

  @override
  Future<WishResult> remove(String wishId) =>
      _guard(() async => _fromWrite(await _engine.removeOwnWish(wishId)));

  @override
  Future<WishResult> claim(String wishId, {String? giverId}) => _guard(
    () async => wishResultFromPlanWrite(
      await _engine.claimWish(wishId, giverId: giverId),
    ),
  );

  @override
  Future<WishResult> editPlan(
    String person,
    String planId,
    PrivatePlanPatch patch,
  ) => _guard(
    () async =>
        wishResultFromPlanWrite(await _engine.editPlan(person, planId, patch)),
  );

  @override
  Future<WishResult> releasePlan(String person, String planId) => _guard(
    () async =>
        wishResultFromPlanWrite(await _engine.releasePlan(person, planId)),
  );

  @override
  Future<WishResult> deletePlan(String person, String planId) async =>
      const WishResult.failed(WishProblem.notAllowed);

  @override
  Future<WishResult> convertPlan(
    String person,
    String planId, {
    required int year,
    String? occasionId,
  }) async => const WishResult.failed(WishProblem.notAllowed);
}

/// El servicio de deseos de este dispositivo: el del motor en la web, el del
/// controlador en el móvil. Las pruebas lo sustituyen.
final wishServiceProvider = Provider<WishService>((ref) {
  final store = ref.watch(familyStoreProvider);
  if (store is WebFamilyStore) return WebWishService(store.engine);
  return MobileWishService(ref.watch(familyControllerProvider.notifier));
});

/// Cambia quién regala el regalo [giftId] (la rejilla de Reparto). Si es un
/// deseo que alguien ha cogido ([plan]), el regalo es solo la forma en que se
/// ve su plan: quién regala se cambia en el plan, no con `setGiftGiver`
/// (ADR 0010). [giverId] nulo lo deja sin asignar.
Future<GiftWriteResult> assignGiftGiver({
  required FamilyController controller,
  required WishService service,
  required String giftId,
  required String? giverId,
  WishPlan? plan,
  void Function(WishResult)? onPlanFailure,
}) async {
  if (plan == null) return controller.setGiftGiver(giftId, giverId);
  final result = await service.editPlan(
    plan.recipientId,
    plan.planId,
    giverId == null
        ? const PrivatePlanPatch(clear: {WishPlanField.giverId})
        : PrivatePlanPatch(giverId: giverId),
  );
  if (result.ok) return GiftWriteResult.saved;
  // Quien llama dice el motivo con el texto de los deseos (por ejemplo, que
  // los demás móviles necesitan la última versión).
  onPlanFailure?.call(result);
  return GiftWriteResult.giftUnavailable;
}
