import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../family/application/self_person_gate.dart';
import '../application/pairing_v2_controller.dart' show PairingV2Person;
import 'person_picker.dart';

/// «¿Quién eres?» (1.0.6): antes de conectar otro móvil o la web, este móvil
/// tiene que ser de una persona. Las tres respuestas de
/// [SelfPersonGateActions]: alguien de la lista, «No estoy en la lista» (con el
/// nombre de la bienvenida, que se puede cambiar) o «Nadie» (quien regala y no
/// recibe regalos).
///
/// [onAnswered] se llama ya con la respuesta guardada. Sin [people], la lista
/// sale de [selfPersonGateProvider].
class WhoAreYouStep extends ConsumerWidget {
  /// Crea la pregunta.
  const WhoAreYouStep({super.key, required this.onAnswered, this.people});

  /// Las personas que se ofrecen; `null` las toma del modelo.
  final List<PairingV2Person>? people;

  /// Ya se ha respondido.
  final VoidCallback onAnswered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final gate = ref.watch(selfPersonGateProvider).value;
    final options =
        people ??
        [
          for (final r in gate?.people ?? const [])
            PairingV2Person(r.id, r.name),
        ];
    Future<void> answer(
      Future<Object?> Function(SelfPersonGateActions) run,
    ) async {
      await run(ref.read(selfPersonGateActionsProvider));
      onAnswered();
    }

    return PersonPicker(
      title: l10n.whoAreYouTitle,
      body: l10n.whoAreYouBody,
      people: options,
      notOnListLabel: l10n.whoAreYouNotOnList,
      nobodyLabel: l10n.whoAreYouNobody,
      nameLabel: l10n.whoAreYouNameLabel,
      suggestedName: gate?.suggestedName ?? '',
      thisPhonePersonId: gate?.selfId,
      // Escribir un nombre que ya está en la lista pregunta «¿Eres tú?» antes
      // de crear a otra persona igual (QA 1.0.7, m8).
      sameNameAsk: SameNameAsk(
        title: l10n.personSameNameTitle,
        body: l10n.whoAreYouSameNameBody,
        yes: l10n.whoAreYouSameNameYes,
        no: l10n.personSameNameOther,
      ),
      onPerson: (id) => answer((a) => a.choose(id)),
      onNew: (name, {required noGifts}) =>
          answer((a) => noGifts ? a.nobody(name) : a.notOnList(name)),
    );
  }
}
