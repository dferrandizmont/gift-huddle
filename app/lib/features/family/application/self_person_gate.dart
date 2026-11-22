import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/device_name.dart'
    show isLegacyDeviceName, suggestedDeviceNameProvider;
import '../../../core/sync/access_policy.dart' show livePeopleOf;
import '../../../core/sync/model.dart';
import 'family_controller.dart';

/// «¿Quién eres?» (1.0.6): antes de invitar a otro dispositivo (móvil o
/// web), este móvil tiene que ser de una persona. Tres respuestas: una
/// persona de la lista, «No estoy en la lista» (se da de alta con el nombre
/// de la bienvenida, que se puede cambiar) y «Nadie» (quien regala y no
/// recibe: también una persona, marcada [Recipient.noGifts], para que el
/// móvil conserve todos sus derechos).
///
/// Se pregunta antes de crear la familia v2: la primera ficha nace ya con
/// persona y vale sin aprobación. En un móvil v2 solo cuya ficha no ha
/// salido de él, el cambio tampoco necesita aprobación
/// ([FamilyController.changeSelfPerson]).
class SelfPersonGate {
  /// Crea el estado.
  const SelfPersonGate({
    this.selfId,
    this.people = const [],
    this.suggestedName = '',
  });

  /// De quién es este móvil, si es de una persona que existe.
  final String? selfId;

  /// Las personas que se pueden elegir (sin archivadas), por nombre.
  final List<Recipient> people;

  /// El nombre que se escribió en la bienvenida («Nombre de este móvil»),
  /// para proponerlo en «No estoy en la lista» y «Nadie». Vacío si es uno de
  /// los nombres que ponía la app o el modelo del móvil sin cambiar (1.0.6, QA
  /// m6): el modelo no es el nombre de nadie.
  final String suggestedName;

  /// Si ya se puede invitar sin preguntar.
  bool get answered => selfId != null;
}

/// El estado de «¿Quién eres?» de este móvil.
final selfPersonGateProvider = FutureProvider<SelfPersonGate>((ref) async {
  final family = await ref.watch(familyControllerProvider.future);
  final identity = family.identity;
  if (identity == null) return const SelfPersonGate();
  final self = identity.selfRecipientId;
  final hasSelf = self != null && livePeopleOf(family.doc).contains(self);
  final name = identity.deviceName.trim();
  // El campo de la bienvenida viene relleno con el modelo del móvil: si se
  // dejó así, no es un nombre que proponer.
  // (Sin esperar al modelo: si aún no se ha leído, no se compara.)
  final model = ref.watch(suggestedDeviceNameProvider).value?.trim() ?? '';
  final isModel = model.isNotEmpty && model.toLowerCase() == name.toLowerCase();
  return SelfPersonGate(
    selfId: hasSelf ? self : null,
    people: family.view.recipients,
    suggestedName: isLegacyDeviceName(name) || isModel ? '' : name,
  );
});

/// Las respuestas de «¿Quién eres?». La pantalla las llama y después abre
/// la invitación.
class SelfPersonGateActions {
  /// Crea las acciones.
  const SelfPersonGateActions(this._ref);

  final Ref _ref;

  FamilyController get _family => _ref.read(familyControllerProvider.notifier);

  /// Este móvil es de [personId].
  Future<ChangeSelfPersonResult> choose(String personId) =>
      _family.answerWhoAreYou(personId);

  /// «No estoy en la lista»: da de alta a [name] y este móvil pasa a ser
  /// suyo. Devuelve el id de la persona nueva.
  Future<String> notOnList(String name) async =>
      (await _family.answerWhoAreYouNew(name)).$1;

  /// «Nadie»: da de alta a [name] como alguien que solo regala y este móvil
  /// pasa a ser suyo. Devuelve el id de la persona nueva.
  Future<String> nobody(String name) async =>
      (await _family.answerWhoAreYouNew(name, noGifts: true)).$1;
}

/// Las acciones de «¿Quién eres?».
final selfPersonGateActionsProvider = Provider<SelfPersonGateActions>(
  SelfPersonGateActions.new,
);
