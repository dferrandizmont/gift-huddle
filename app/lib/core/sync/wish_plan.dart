/// Lo que hacen los demás con un deseo visible (ADR 0010, 1.0.7, fase 3):
/// cogerlo, comprarlo, soltarlo. Vive en `ScopeCollections.wishPlans`, dentro
/// del bloque secreto `surprise:P` de la persona que lo desea: sus móviles no
/// lo pueden abrir, así que nada de esto cambia lo que P recibe ni mide.
///
/// - El enlace con el deseo (`sourceWishId`) solo existe en el plan. El
///   registro del deseo en el común no sabe nada de él.
/// - Al coger un deseo se copian `title`, `size` y `url` (dentro de
///   [kMaxWishCopyBytes]): así el plan se sigue mostrando y editando aunque
///   P quite el deseo antes de que llegue la lápida a este móvil.
/// - Soltar o borrar un plan deja una lápida en el bloque; volver a cogerlo
///   crea otro `planId`. Dos reservas desconectadas se conservan las dos y se
///   enseñan como conflicto ([WishPlanState.conflictingClaims]): no hay un
///   booleano «cogido» que pierda una de las intenciones.
/// - Las marcas salen de un reloj propio del ámbito, nunca del público.
///
/// Dart puro, sin Flutter. Los permisos son los de las sorpresas: solo un
/// móvil con derecho efectivo a `surprise:P` ([RegistryView.selfEntitled])
/// escribe o lee planes.
library;

import 'dart:math';

import 'device_keys.dart' show kSyncIdPattern;
import 'device_registry.dart';
import 'family_doc.dart';
import 'hlc.dart';
import 'model.dart';
import 'protected_envelope.dart';
import 'wish.dart';

/// Un id nuevo y aleatorio de plan.
String newWishPlanId() => _randomId('p');

/// Un id nuevo y aleatorio para el regalo sorpresa que sale de un plan.
String newPlanGiftId() => _randomId('g');

final Random _random = Random.secure();
const String _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

String _randomId(String prefix) {
  final b = StringBuffer(prefix);
  for (var i = 0; i < 16; i++) {
    b.write(_alphabet[_random.nextInt(_alphabet.length)]);
  }
  return b.toString();
}

/// Estado de un deseo para quien puede abrir el bloque (nunca para P).
enum WishPlanState {
  /// Nadie lo ha cogido.
  available,

  /// Un plan vivo.
  claimed,

  /// Dos o más planes vivos para el mismo deseo (reservas desconectadas):
  /// los autorizados lo resuelven soltando o borrando uno.
  conflictingClaims,

  /// P lo quitó de su lista (lápida pública) y queda al menos un plan vivo:
  /// el único texto es la copia del plan.
  removedFromList,
}

/// Por qué una operación sobre un plan no se hizo. No escribe nada.
enum WishPlanError {
  /// Este móvil no tiene derecho al bloque de esa persona (también el de la
  /// propia persona).
  notEntitled,

  /// El plan pertenece a otra persona.
  notClaimant,

  /// No existe ese deseo (o está mal formado).
  wishNotFound,

  /// El deseo ya se quitó de la lista: no se coge.
  wishRemoved,

  /// Ya hay una reserva visible de otra persona: la segunda no es ordinaria.
  alreadyClaimed,

  /// No existe ese plan.
  planNotFound,

  /// Ese id de plan ya se usó (también por uno soltado: no se reutiliza), o
  /// es de otro deseo.
  planIdInUse,

  /// Ya hay [kMaxSurpriseGifts] registros vivos (regalos y planes) en el
  /// bloque.
  capacityReached,

  /// El bloque no cabe en el slot con este plan.
  slotFull,

  /// El plan pasaría de [kMaxSurpriseGiftBytes] o la copia del deseo de
  /// [kMaxWishCopyBytes].
  tooLarge,

  /// Un valor no vale.
  invalidField,

  /// Este móvil no puede abrir ahora el bloque de esa persona (falta la clave
  /// de la época, un slot sin leer, o aún sin registro v2). Lo explica
  /// `WishPlanOutcome.failure`.
  unavailable,

  /// Algún móvil con derecho a leer o recoger ese bloque aún no entiende los
  /// planes de deseos (sigue en la 1.0.6, o todavía no ha publicado su slot de
  /// la 1.0.7): escribir uno le haría rechazar el bloque entero, regalos
  /// incluidos. No se escribe nada hasta que todos estén actualizados («Actualiza
  /// los demás móviles»).
  devicesNeedUpdate,
}

/// Con qué límites se sella el slot de este móvil ahora: los mismos que usa
/// `publishScope`. Un plan que no cabría con ellos se rechaza
/// ([WishPlanError.slotFull]) en lugar de quedarse fuera del slot sin que los
/// demás lo vean.
final class SlotLimits {
  /// Crea los límites.
  const SlotLimits({
    this.maxLive = kMaxSlotGifts,
    this.seen = const <String, SlotVersion>{},
  });

  /// Registros vivos que admite el slot (`slotGiftLimitFor`: 232, o 64 con un
  /// escritor 1.0.5 o sin slot).
  final int maxLive;

  /// Lo que lleva fusionado este móvil de los demás escritores (`seen`).
  final Map<String, SlotVersion> seen;
}

/// Campos privados de un plan que se pueden vaciar.
enum WishPlanField {
  /// Quién regala.
  giverId,

  /// Precio previsto.
  plannedCents,

  /// Precio real.
  actualCents,

  /// Tienda.
  store,

  /// Enlace de compra.
  purchaseUrl,

  /// Nota de quien regala.
  giverNote,
}

/// Cambios a los campos privados de un plan. Tipo propio: no es un
/// `VisibleWishPatch` ni un `Gift`. El título, la talla y el enlace del deseo
/// copiados al coger no se editan aquí.
final class PrivatePlanPatch {
  /// Crea un parche. Un campo null no se toca; para vaciar uno, [clear].
  const PrivatePlanPatch({
    this.giverId,
    this.status,
    this.plannedCents,
    this.actualCents,
    this.store,
    this.purchaseUrl,
    this.giverNote,
    this.clear = const {},
  });

  /// Quién regala.
  final String? giverId;

  /// En qué punto está.
  final GiftStatus? status;

  /// Precio previsto, en céntimos.
  final int? plannedCents;

  /// Precio real, en céntimos.
  final int? actualCents;

  /// Tienda.
  final String? store;

  /// Enlace de compra (http o https).
  final String? purchaseUrl;

  /// Nota de quien regala.
  final String? giverNote;

  /// Campos que se vacían.
  final Set<WishPlanField> clear;
}

/// El resultado de una operación: el ámbito nuevo o un error tipado.
final class WishPlanWrite {
  const WishPlanWrite._(this.scope, this.error, this.planId, [this.giftId]);

  /// Una operación que no se hizo (la usa la capa de la aplicación cuando
  /// falla antes de llegar al ámbito).
  const WishPlanWrite.failed(FamilyDoc scope, WishPlanError error)
    : this._(scope, error, null);

  /// El documento del ámbito resultante (el mismo, sin cambios, si hay
  /// [error] o no había nada que escribir).
  final FamilyDoc scope;

  /// Qué falló, o null.
  final WishPlanError? error;

  /// El plan creado, editado o quitado.
  final String? planId;

  /// Con `convertPlanToSurprise`, el regalo sorpresa nuevo.
  final String? giftId;

  /// Si se hizo.
  bool get ok => error == null;
}

/// Un plan: lo que alguien hace con el deseo de otra persona.
class WishPlan {
  /// Crea un plan.
  const WishPlan({
    required this.planId,
    required this.recipientId,
    required this.sourceWishId,
    required this.claimantPersonId,
    required this.title,
    required this.status,
    this.size,
    this.url,
    this.giverId,
    this.plannedCents,
    this.actualCents,
    this.store,
    this.purchaseUrl,
    this.giverNote,
  });

  /// Id aleatorio del plan.
  final String planId;

  /// La persona a la que le gustaría (la dueña del bloque).
  final String recipientId;

  /// El deseo de origen. Solo se conoce dentro del bloque.
  final String sourceWishId;

  /// Quién lo cogió, aunque el regalador elegido sea «Nosotros».
  final String claimantPersonId;

  /// Copia del título del deseo al cogerlo.
  final String title;

  /// Copia de la talla.
  final String? size;

  /// Copia del enlace del deseo.
  final String? url;

  /// Quién regala.
  final String? giverId;

  /// En qué punto está.
  final GiftStatus status;

  /// Precio previsto.
  final int? plannedCents;

  /// Precio real.
  final int? actualCents;

  /// Tienda.
  final String? store;

  /// Enlace de compra.
  final String? purchaseUrl;

  /// Nota de quien regala.
  final String? giverNote;

  /// Los nombres de campo que forman un plan: la lista positiva.
  static const List<String> fieldNames = [
    'recipientId',
    'sourceWishId',
    'claimantPersonId',
    'title',
    'size',
    'url',
    'giverId',
    'status',
    'plannedCents',
    'actualCents',
    'store',
    'purchaseUrl',
    'giverNote',
  ];

  /// El plan de [record], o null si es una lápida o le falta algo. Con el
  /// [common] de la vista se ignora la asignación a un regalador eliminado,
  /// sin escribir en el ámbito ni pisar una reasignación concurrente.
  static WishPlan? fromRecord(SyncRecord record, {FamilyDoc? common}) {
    if (record.isDeleted) return null;
    final recipientId = _str(record['recipientId']);
    final source = _str(record['sourceWishId']);
    final claimant = _str(record['claimantPersonId']);
    final title = _str(record['title']);
    final rawStatus = _str(record['status']);
    if (recipientId == null ||
        source == null ||
        claimant == null ||
        title == null ||
        rawStatus == null) {
      return null;
    }
    final giverId = _str(record['giverId']);
    final giverDeleted =
        giverId != null &&
        common?.record(Collections.givers, giverId)?.isDeleted == true;
    return WishPlan(
      planId: record.id,
      recipientId: recipientId,
      sourceWishId: source,
      claimantPersonId: claimant,
      title: title,
      status: GiftStatus.fromName(rawStatus),
      size: _str(record['size']),
      url: _str(record['url']),
      giverId: giverDeleted ? null : giverId,
      plannedCents: _cents(record['plannedCents']),
      actualCents: _cents(record['actualCents']),
      store: _str(record['store']),
      purchaseUrl: _str(record['purchaseUrl']),
      giverNote: _str(record['giverNote']),
    );
  }

  /// El plan como regalo, solo para quien puede abrir el bloque. [year] y
  /// [occasionId] los pone quien llama (el plan no los copia). Nunca se
  /// publica.
  Gift toGiftForAuthorizedView({required int year, String? occasionId}) => Gift(
    id: planId,
    recipientId: recipientId,
    title: title,
    giverId: giverId,
    occasionId: occasionId,
    status: status,
    rawStatus: status.name,
    plannedCents: plannedCents,
    actualCents: actualCents,
    store: store,
    url: purchaseUrl ?? url,
    note: giverNote,
    size: size,
    surprise: true,
    year: year,
  );

  /// Los campos del regalo sorpresa en que se convierte este plan.
  Map<String, Object?> _giftFields({required int year, String? occasionId}) =>
      toGiftForAuthorizedView(year: year, occasionId: occasionId).toFields();
}

String? _str(Object? v) => v is String ? v : null;

int? _cents(Object? v) => v is int && v >= 0 && v <= kMaxCents ? v : null;

/// Una fila de la vista autorizada: un deseo (o el plan que sobrevive a su
/// retirada) con su estado.
final class WishPlanRow {
  /// Crea la fila.
  const WishPlanRow({
    required this.recipientId,
    required this.sourceWishId,
    required this.state,
    required this.plans,
    this.wish,
  });

  /// La persona dueña del deseo.
  final String recipientId;

  /// El deseo.
  final String sourceWishId;

  /// Estado derivado.
  final WishPlanState state;

  /// Planes vivos de este deseo, por id (ninguno si está disponible).
  final List<WishPlan> plans;

  /// El deseo visible vivo, o null si ya no está (quitado, o aún no llegó a
  /// este móvil): entonces manda la copia del plan.
  final Wish? wish;
}

/// Lo que ve quien puede abrir el bloque de [recipientId]: sus deseos
/// visibles con el estado que les dan los planes del [scope]. Solo se llama
/// con el ámbito de un móvil con derecho; los móviles de P no tienen ámbito.
///
/// `removedFromList` sale de la lápida pública verificada del deseo
/// (`record(wishes, id).isDeleted`) y de un plan vivo. Que el deseo no
/// aparezca en [common] (descarga incompleta, o aún no llegó) no basta.
List<WishPlanRow> deriveWishPlanRows({
  required FamilyDoc common,
  required FamilyDoc scope,
  required String recipientId,
}) {
  final plansByWish = <String, List<WishPlan>>{};
  for (final plan in scope.readLivePlans(common: common)) {
    if (plan.recipientId != recipientId) continue;
    plansByWish.putIfAbsent(plan.sourceWishId, () => []).add(plan);
  }
  final wishes = <String, Wish>{};
  for (final record
      in common.collections[Collections.wishes]?.values ??
          const <SyncRecord>[]) {
    final wish = Wish.fromRecord(record);
    if (wish != null && wish.recipientId == recipientId) {
      wishes[wish.id] = wish;
    }
  }
  final ids = <String>{...wishes.keys, ...plansByWish.keys}.toList()..sort();
  return [
    for (final id in ids)
      _row(
        recipientId,
        id,
        wishes[id],
        common.record(Collections.wishes, id)?.isDeleted == true,
        plansByWish[id] ?? const [],
      ),
  ];
}

WishPlanRow _row(
  String recipientId,
  String id,
  Wish? wish,
  bool removed,
  List<WishPlan> plans,
) => WishPlanRow(
  recipientId: recipientId,
  sourceWishId: id,
  wish: wish,
  plans: List.unmodifiable(plans),
  state: plans.isEmpty
      ? WishPlanState.available
      : removed
      ? WishPlanState.removedFromList
      : plans.length == 1
      ? WishPlanState.claimed
      : WishPlanState.conflictingClaims,
);

/// Operaciones sobre el ámbito secreto de una persona: el receptor es el
/// documento del ámbito (`surprise:P`, lo abierto más las ediciones locales).
extension WishPlanScope on FamilyDoc {
  /// Los planes vivos de este ámbito, por id.
  List<WishPlan> get livePlans => readLivePlans();

  /// Los planes vivos, por id, con las asignaciones que permite ver [common].
  List<WishPlan> readLivePlans({FamilyDoc? common}) => [
    for (final record
        in collections[ScopeCollections.wishPlans]?.values ??
            const <SyncRecord>[])
      ?WishPlan.fromRecord(record, common: common),
  ]..sort((a, b) => a.planId.compareTo(b.planId));

  /// Los planes vivos de `(recipientId, sourceWishId)`.
  List<WishPlan> plansFor(String recipientId, String sourceWishId) => [
    for (final plan in livePlans)
      if (plan.recipientId == recipientId && plan.sourceWishId == sourceWishId)
        plan,
  ];

  /// Este móvil coge el deseo [wishId] del documento [common].
  ///
  /// Copia título, talla y enlace visibles ahora. Con [planId] (el que el
  /// llamador guardó antes de la primera escritura) o, sin él, con un plan
  /// vivo de la misma persona para ese deseo, un reintento reutiliza el id y
  /// no escribe nada. Otra reserva visible de otra persona impide la
  /// ordinaria ([WishPlanError.alreadyClaimed]); las dos reservas
  /// desconectadas se juntan al fusionar, no aquí.
  WishPlanWrite claimWish(
    HlcClock scopeClock,
    RegistryView view,
    FamilyDoc common,
    String wishId, {
    String? planId,
    String? giverId,
    SlotLimits limits = const SlotLimits(),
  }) {
    final wishRecord = common.record(Collections.wishes, wishId);
    if (wishRecord == null) {
      return WishPlanWrite._(this, WishPlanError.wishNotFound, null);
    }
    if (wishRecord.isDeleted) {
      return WishPlanWrite._(this, WishPlanError.wishRemoved, null);
    }
    final wish = Wish.fromRecord(wishRecord);
    if (wish == null) {
      return WishPlanWrite._(this, WishPlanError.wishNotFound, null);
    }
    final denied = _denied(view, wish.recipientId);
    if (denied != null) return WishPlanWrite._(this, denied, null);
    if (planId != null && !kSyncIdPattern.hasMatch(planId)) {
      return WishPlanWrite._(this, WishPlanError.invalidField, null);
    }
    if (giverId != null && !kSyncIdPattern.hasMatch(giverId)) {
      return WishPlanWrite._(this, WishPlanError.invalidField, null);
    }
    final claimant = view.myPerson!;
    final live = plansFor(wish.recipientId, wishId);
    if (planId != null) {
      final existing = record(ScopeCollections.wishPlans, planId);
      if (existing != null) {
        final same =
            !existing.isDeleted &&
            existing['sourceWishId'] == wishId &&
            existing['recipientId'] == wish.recipientId &&
            existing['claimantPersonId'] == claimant;
        return same
            ? WishPlanWrite._(this, null, planId)
            : WishPlanWrite._(this, WishPlanError.planIdInUse, planId);
      }
    }
    // Un reintento (o el mismo móvil en otro intento) reutiliza su plan.
    for (final plan in live) {
      if (plan.claimantPersonId == claimant) {
        return WishPlanWrite._(this, null, plan.planId);
      }
    }
    if (live.isNotEmpty) {
      return WishPlanWrite._(this, WishPlanError.alreadyClaimed, null);
    }
    if (wishCopyBytes(title: wish.title, size: wish.size, url: wish.url) >
        kMaxWishCopyBytes) {
      return WishPlanWrite._(this, WishPlanError.tooLarge, null);
    }
    var id = planId ?? newWishPlanId();
    while (planId == null && record(ScopeCollections.wishPlans, id) != null) {
      id = newWishPlanId();
    }
    final next = set(scopeClock, ScopeCollections.wishPlans, id, {
      'recipientId': wish.recipientId,
      'sourceWishId': wishId,
      'claimantPersonId': claimant,
      'title': wish.title,
      'size': ?wish.size,
      'url': ?wish.url,
      'giverId': ?giverId,
      'status': GiftStatus.decided.name,
    });
    return _checked(next, id, wish.recipientId, limits, countsOne: true);
  }

  /// Este móvil cambia campos privados del plan [planId].
  WishPlanWrite editPlan(
    HlcClock scopeClock,
    RegistryView view,
    String planId,
    PrivatePlanPatch patch, {
    SlotLimits limits = const SlotLimits(),
  }) {
    final record = this.record(ScopeCollections.wishPlans, planId);
    final plan = record == null ? null : WishPlan.fromRecord(record);
    if (plan == null) {
      return WishPlanWrite._(this, WishPlanError.planNotFound, planId);
    }
    final denied = _changeDenied(view, record!);
    if (denied != null) return WishPlanWrite._(this, denied, planId);
    final changes = _changesOf(patch);
    if (changes == null) {
      return WishPlanWrite._(this, WishPlanError.invalidField, planId);
    }
    final next = setChanged(
      scopeClock,
      ScopeCollections.wishPlans,
      planId,
      changes,
    );
    if (identical(next, this)) return WishPlanWrite._(this, null, planId);
    return _checked(next, planId, plan.recipientId, limits);
  }

  /// Este móvil suelta el plan [planId]: lápida en el bloque. Volver a coger
  /// el deseo crea otro id. Soltar uno ya soltado no hace nada.
  WishPlanWrite releasePlan(
    HlcClock scopeClock,
    RegistryView view,
    String planId,
  ) => _remove(scopeClock, view, planId);

  /// Este móvil borra el plan [planId]. Mismo efecto que [releasePlan] (una
  /// lápida): la diferencia es de intención y de texto en la interfaz.
  WishPlanWrite deletePlan(
    HlcClock scopeClock,
    RegistryView view,
    String planId,
  ) => _remove(scopeClock, view, planId);

  WishPlanWrite _remove(HlcClock clock, RegistryView view, String planId) {
    final record = this.record(ScopeCollections.wishPlans, planId);
    if (record == null) {
      return WishPlanWrite._(this, WishPlanError.planNotFound, planId);
    }
    if (record.isDeleted) return WishPlanWrite._(this, null, planId);
    final denied = _changeDenied(view, record);
    if (denied != null) return WishPlanWrite._(this, denied, planId);
    return WishPlanWrite._(
      delete(clock, ScopeCollections.wishPlans, planId),
      null,
      planId,
    );
  }

  /// El plan [planId] pasa a ser un regalo sorpresa independiente (el
  /// plan se borra, el deseo de P no se toca). [common] permite descartar un
  /// regalador eliminado. [year] y [occasionId] los pone quien llama.
  /// Con [giftId] guardado antes de la primera escritura, un reintento no
  /// duplica el regalo.
  WishPlanWrite convertPlanToSurprise(
    HlcClock scopeClock,
    RegistryView view,
    String planId, {
    required FamilyDoc common,
    required int year,
    String? occasionId,
    String? giftId,
    SlotLimits limits = const SlotLimits(),
  }) {
    final record = this.record(ScopeCollections.wishPlans, planId);
    if (record == null) {
      return WishPlanWrite._(this, WishPlanError.planNotFound, planId);
    }
    if (record.isDeleted) {
      // Reintento tras una conversión que ya se escribió.
      final done = giftId == null
          ? null
          : this.record(Collections.gifts, giftId);
      return done != null && !done.isDeleted
          ? WishPlanWrite._(this, null, planId, giftId)
          : WishPlanWrite._(this, WishPlanError.planNotFound, planId);
    }
    final plan = WishPlan.fromRecord(record, common: common);
    if (plan == null) {
      return WishPlanWrite._(this, WishPlanError.planNotFound, planId);
    }
    final denied = _changeDenied(view, record);
    if (denied != null) return WishPlanWrite._(this, denied, planId);
    if (giftId != null && !kSyncIdPattern.hasMatch(giftId)) {
      return WishPlanWrite._(this, WishPlanError.invalidField, planId);
    }
    final id = giftId ?? newPlanGiftId();
    if (this.record(Collections.gifts, id) != null) {
      return WishPlanWrite._(this, WishPlanError.planIdInUse, planId);
    }
    // Primero la lápida del plan: el regalo ocupa su sitio en la capacidad.
    final without = delete(scopeClock, ScopeCollections.wishPlans, planId);
    final FamilyDoc next;
    try {
      next = addSurpriseGift(
        without,
        scopeClock,
        id,
        plan._giftFields(year: year, occasionId: occasionId),
      );
    } on SurpriseCapacityException {
      return WishPlanWrite._(this, WishPlanError.capacityReached, planId);
    } on SurpriseGiftTooLargeException {
      return WishPlanWrite._(this, WishPlanError.tooLarge, planId);
    }
    // El mismo criterio que las ediciones de regalos secretos.
    if (liveSurpriseGifts(next) > kMaxSurpriseGifts) {
      return WishPlanWrite._(this, WishPlanError.capacityReached, planId);
    }
    if (!scopeFitsInSlot(
      next,
      plan.recipientId,
      seen: limits.seen,
      maxLive: limits.maxLive,
    )) {
      return WishPlanWrite._(this, WishPlanError.slotFull, planId);
    }
    return WishPlanWrite._(next, null, planId, id);
  }

  WishPlanWrite _checked(
    FamilyDoc next,
    String planId,
    String recipientId,
    SlotLimits limits, {
    bool countsOne = false,
  }) {
    final record = next.record(ScopeCollections.wishPlans, planId)!;
    if (surpriseRecordBytes(record) > kMaxSurpriseGiftBytes) {
      return WishPlanWrite._(this, WishPlanError.tooLarge, planId);
    }
    // Un plan nuevo gasta una plaza con el mismo criterio que las ediciones
    // de regalos secretos: regalos y planes, también los movidos.
    if (countsOne && liveSurpriseGifts(next) > kMaxSurpriseGifts) {
      return WishPlanWrite._(this, WishPlanError.capacityReached, planId);
    }
    if (!scopeFitsInSlot(
      next,
      recipientId,
      seen: limits.seen,
      maxLive: limits.maxLive,
    )) {
      return WishPlanWrite._(this, WishPlanError.slotFull, planId);
    }
    return WishPlanWrite._(next, null, planId);
  }
}

WishPlanError? _denied(RegistryView view, String recipientId) =>
    recipientId.isEmpty ||
        view.myPerson == null ||
        view.myPerson == recipientId ||
        !view.selfEntitled(recipientId)
    ? WishPlanError.notEntitled
    : null;

WishPlanError? _changeDenied(RegistryView view, SyncRecord record) {
  final denied = _denied(view, record['recipientId'] as String? ?? '');
  if (denied != null) return denied;
  return record['claimantPersonId'] == view.myPerson
      ? null
      : WishPlanError.notClaimant;
}

String? _text(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}

/// Si [text] vale como enlace de compra de un plan (`http` o `https` con
/// sitio): lo mismo que comprueba la escritura. Para avisar en el campo antes
/// de guardar.
bool isPlanPurchaseUrl(String text) => _httpUrl(text.trim());

bool _httpUrl(String s) {
  final uri = Uri.tryParse(s);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// Los cambios que escribe [patch], o null si algún valor no vale.
Map<String, Object?>? _changesOf(PrivatePlanPatch patch) {
  final out = <String, Object?>{};
  final clear = patch.clear;
  void text(String name, WishPlanField field, String? value) {
    if (clear.contains(field)) {
      out[name] = null;
    } else if (value != null) {
      out[name] = _text(value) ?? '';
    }
  }

  text('giverId', WishPlanField.giverId, patch.giverId);
  text('store', WishPlanField.store, patch.store);
  text('purchaseUrl', WishPlanField.purchaseUrl, patch.purchaseUrl);
  text('giverNote', WishPlanField.giverNote, patch.giverNote);
  if (out.values.any((v) => v == '')) return null;
  final giver = out['giverId'];
  if (giver is String && !kSyncIdPattern.hasMatch(giver)) return null;
  final link = out['purchaseUrl'];
  if (link is String && !_httpUrl(link)) return null;
  void cents(String name, WishPlanField field, int? value) {
    if (clear.contains(field)) {
      out[name] = null;
    } else if (value != null) {
      out[name] = value;
    }
  }

  cents('plannedCents', WishPlanField.plannedCents, patch.plannedCents);
  cents('actualCents', WishPlanField.actualCents, patch.actualCents);
  for (final name in const ['plannedCents', 'actualCents']) {
    final v = out[name];
    if (v is int && (v < 0 || v > kMaxCents)) return null;
  }
  if (patch.status != null) out['status'] = patch.status!.name;
  return out;
}
