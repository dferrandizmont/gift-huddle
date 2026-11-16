import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/pop_in.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/sheet_motion.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/motion/success_mark.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';

/// La hoja de «Móviles emparejados» (§3.2 y «momento L» de
/// la guía de movimiento), que sustituye al `AlertDialog`.
///
/// Sube como las demás hojas (`showRegalosSheet`, con `snap`) y por dentro:
///
/// - [SuccessMark] de 64: el cuadro rebota desde 0,8 a los 60 ms y su visto se
///   dibuja en 300 ms a los 180 ms;
/// - título, frase y botón entran con [StaggerItem] a 40 ms, desde los 140 ms;
/// - los avatares de la familia que acaba de llegar rebotan desde 0,8, con
///   50 ms entre uno y otro, desde los 260 ms.
///
/// La vibración de éxito llega con la hoja ya arriba y el visto dibujándose
/// ([kPairedHapticDelay]).
///
/// Con «Reducir movimiento»: todo con fundidos de 150 ms y el visto entero.
Future<void> showPairedSheet(
  BuildContext context, {
  required String title,
  required String body,
}) {
  context.haptics.success(
    after: RegalosMotion.of(context).reduce
        ? Duration.zero
        : kPairedHapticDelay,
  );
  return showRegalosSheet<void>(
    context,
    builder: (_) => _PairedSheet(title: title, body: body),
  );
}

/// Cuánto tarda la hoja de emparejado en llegar arriba y empezar a dibujar el
/// visto: la vibración de éxito sale en ese instante.
const Duration kPairedHapticDelay = Duration(milliseconds: 400);

class _PairedSheet extends ConsumerWidget {
  const _PairedSheet({required this.title, required this.body});

  final String title;
  final String body;

  /// Cuántos avatares caben en la fila.
  static const int _maxAvatars = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final people = ref.watch(recipientsProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: StaggerScope(
          step: const Duration(milliseconds: 40),
          delay: const Duration(milliseconds: 140),
          maxItems: 3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SuccessMark(size: 64)),
              const SizedBox(height: 14),
              StaggerItem(
                index: 0,
                dy: 8,
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: t.styles.screenTitleSmall,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              StaggerItem(
                index: 1,
                dy: 8,
                child: Text(
                  body,
                  textAlign: TextAlign.center,
                  style: t.styles.body,
                ),
              ),
              if (people.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < people.length && i < _maxAvatars; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: PopIn(
                          key: ValueKey(people[i].id),
                          from: 0.8,
                          delay: Duration(milliseconds: 260 + 50 * i),
                          child: PersonAvatar(
                            name: people[i].name,
                            colorIndex: people[i].colorIndex,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              StaggerItem(
                index: 2,
                dy: 8,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.actionDone),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
