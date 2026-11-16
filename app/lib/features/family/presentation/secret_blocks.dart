import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/sync/model.dart';
import '../../../core/widgets/secret_block.dart';
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

/// Los bloques secretos de [people], uno bajo otro, con el margen de 16 de los
/// lados. Cada uno entra y sale plegándose como una fila (con fundido suave:
/// llegan por sincronización). [onOpen] abre la ficha de la persona.
class SecretBlockList extends StatelessWidget {
  /// Crea la lista.
  const SecretBlockList({super.key, required this.people, this.onOpen});

  /// Las personas protegidas.
  final List<Recipient> people;

  /// Se llama al tocar el bloque de una persona.
  final ValueChanged<Recipient>? onOpen;

  @override
  Widget build(BuildContext context) {
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
                  onTap: onOpen == null ? null : () => onOpen!(p),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
