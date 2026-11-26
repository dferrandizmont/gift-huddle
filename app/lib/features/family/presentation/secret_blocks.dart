import '../../web_device/application/web_app_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/sync/model.dart';
import '../../../core/widgets/secret_block.dart';
import '../../../l10n/app_localizations.dart';
import '../application/family_providers.dart';

/// Las personas cuyos regalos este móvil no puede ver (un bloque secreto
/// cada una). Sale de [secretBlocksProvider]: solo ids, ninguna cifra.
final lockedPeopleProvider = Provider<Set<String>>(
  (ref) => {for (final b in ref.watch(secretBlocksProvider)) b.personId},
);

/// Las personas activas con bloque secreto, en el orden de la lista de
/// personas.
final lockedRecipientsProvider = Provider<List<Recipient>>((ref) {
  final locked = ref.watch(lockedPeopleProvider);
  if (locked.isEmpty) return const <Recipient>[];
  return [
    for (final r in ref.watch(recipientsProvider))
      if (locked.contains(r.id)) r,
  ];
});

/// Quién lleva el bloque secreto en [occasion]: de [people], las que tienen
/// regalos en secreto que este móvil no ve ([locked]) y a las que la ocasión
/// concierne. Un cumpleaños (ocasión con `recipientId`) solo concierne a su
/// persona; las demás ocasiones, a todas.
///
/// Depende solo de la configuración de la ocasión y de la lista de personas,
/// nunca de si hay regalos en secreto (eso lo contaría): el bloque de una
/// persona protegida sale igual haya detrás cero regalos o cien.
List<Recipient> lockedPeopleFor(
  Occasion occasion,
  Iterable<Recipient> people,
  Set<String> locked,
) {
  final only = occasion.recipientId;
  return [
    for (final p in people)
      if (locked.contains(p.id) && (only == null || only == p.id)) p,
  ];
}

/// Los bloques secretos de [people], uno bajo otro, con el margen de 16 de los
/// lados. Cada uno entra y sale plegándose como una fila (con fundido suave:
/// llegan por sincronización). [onOpen] abre la ficha de la persona.
class SecretBlockList extends ConsumerWidget {
  /// Crea la lista.
  const SecretBlockList({super.key, required this.people, this.onOpen});

  /// Las personas protegidas.
  final List<Recipient> people;

  /// Se llama al tocar el bloque de una persona.
  final ValueChanged<Recipient>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final web = ref.watch(webAppProvider);
    // El bloque fijo de la propia persona se llama «Sorpresas» (ADR 0010).
    final own = ref.watch(ownHiddenPeopleProvider);
    final l10n = AppLocalizations.of(context);
    var order = 0;
    return AnimatedRows(
      key: const ValueKey<String>('secret-blocks'),
      quiet: true,
      rows: [
        for (final p in people)
          AnimatedRowItem(
            id: 'secret-${p.id}',
            child: StaggerItem(
              index: order++,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: SecretBlockCard(
                  key: ValueKey<String>('secret-block:${p.id}'),
                  name: p.name,
                  colorIndex: p.colorIndex,
                  web: web,
                  title: own.contains(p.id) ? l10n.surprisesTitle : null,
                  onTap: onOpen == null ? null : () => onOpen!(p),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
