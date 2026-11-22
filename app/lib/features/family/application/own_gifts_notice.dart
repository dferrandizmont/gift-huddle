import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'family_controller.dart';
import 'protection_providers.dart';

/// Preferencia local: el aviso de «en este móvil ya no se ven los regalos para
/// ti» ya se enseñó (una vez, al actualizar o al quedar acompañado).
const String kOwnGiftsHiddenSeenKey = 'ownGiftsHiddenNoticeSeen';

/// Preferencia local: la última vez que se miró, los regalos de la persona de
/// este móvil estaban ocultos. Con ella se sabe que el móvil ha quedado solo.
const String kOwnGiftsWasHiddenKey = 'ownGiftsWasHidden';

/// Qué avisa [OwnGiftsNotice].
enum OwnGiftsNoticeKind {
  /// Los regalos para la persona de este móvil dejan de verse en él (se
  /// avisa una sola vez, tras actualizar o al conectar otro móvil).
  hidden,

  /// Este móvil se ha quedado solo: los regalos que estaban en secreto no
  /// están en él.
  alone,
}

/// Un aviso para quien usa este móvil.
class OwnGiftsNotice {
  /// Crea el aviso.
  const OwnGiftsNotice(this.kind, this.personName);

  /// Qué avisa.
  final OwnGiftsNoticeKind kind;

  /// El nombre de la persona de este móvil.
  final String personName;
}

/// Lo que se sabe ahora de los regalos de la persona de este móvil.
class OwnGiftsSituation {
  /// Crea la situación.
  const OwnGiftsSituation({
    required this.hidden,
    required this.settled,
    required this.name,
  });

  /// Si este móvil no pinta los regalos de su persona (acompañado).
  final bool hidden;

  /// Si ya se ha leído el registro: solo entonces «no oculto» es seguro
  /// (antes, ante la duda, se oculta).
  final bool settled;

  /// El nombre de la persona de este móvil.
  final String name;
}

/// La situación de ahora, o `null` si este móvil no es de nadie o su persona
/// solo regala (no recibe regalos: no hay nada que ocultar).
final ownGiftsSituationProvider = Provider<OwnGiftsSituation?>((ref) {
  final family = ref.watch(familyControllerProvider).value;
  final self = family?.identity?.selfRecipientId;
  if (family == null || self == null) return null;
  final person = family.view.recipients.where((r) => r.id == self).firstOrNull;
  if (person == null || person.noGifts) return null;
  final registry = ref.watch(screenRegistryViewProvider);
  return OwnGiftsSituation(
    hidden: ref.watch(ownHiddenPeopleProvider).contains(self),
    settled: !registry.isLoading && !registry.hasError,
    name: person.name.trim(),
  );
});

/// El aviso que toca ahora, si toca, y apunta en [prefs] lo que ya se vio
/// (sin esperar a que se guarde).
///
/// - Regalos ocultos y sin avisar nunca: [OwnGiftsNoticeKind.hidden].
/// - Ocultos otras veces: nada (solo se apunta que lo estaban).
/// - Ya no ocultos, con el registro leído, y lo estaban:
///   [OwnGiftsNoticeKind.alone].
OwnGiftsNotice? nextOwnGiftsNotice(
  SharedPreferences prefs,
  OwnGiftsSituation? situation,
) {
  if (situation == null || situation.name.isEmpty) return null;
  final seen = prefs.getBool(kOwnGiftsHiddenSeenKey) ?? false;
  final wasHidden = prefs.getBool(kOwnGiftsWasHiddenKey) ?? false;
  if (situation.hidden) {
    if (!wasHidden) prefs.setBool(kOwnGiftsWasHiddenKey, true);
    if (seen) return null;
    prefs.setBool(kOwnGiftsHiddenSeenKey, true);
    return OwnGiftsNotice(OwnGiftsNoticeKind.hidden, situation.name);
  }
  if (situation.settled && wasHidden) {
    prefs.setBool(kOwnGiftsWasHiddenKey, false);
    return OwnGiftsNotice(OwnGiftsNoticeKind.alone, situation.name);
  }
  return null;
}

/// El móvil que acaba de entrar a una familia ya sabe, por su hoja final, que
/// no verá los regalos de su persona: el aviso de una vez no se repite.
void markOwnGiftsHiddenSeen(SharedPreferences prefs) {
  prefs.setBool(kOwnGiftsHiddenSeenKey, true);
  prefs.setBool(kOwnGiftsWasHiddenKey, true);
}
