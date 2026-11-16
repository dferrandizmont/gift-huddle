import 'package:flutter/material.dart';

import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';

/// Aviso dentro de la app de que hay cambios **apartados**: son para una
/// persona protegida, no se suben y siguen cifrados en este ordenador.
///
/// Con [count] 0 no ocupa nada; al aparecer o desaparecer se funde y estira el
/// hueco con `fold`.
class SetAsideNotice extends StatelessWidget {
  /// Crea el aviso para [count] cambios apartados.
  const SetAsideNotice({super.key, required this.count});

  /// Cambios apartados.
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    return AnimatedSize(
      duration: motion.duration(RegalosCurves.foldDuration),
      curve: motion.curve(RegalosCurves.fold),
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: RegalosMotion.fade,
        child: count <= 0
            ? const SizedBox(key: ValueKey<bool>(false), width: double.infinity)
            : Padding(
                key: const ValueKey<bool>(true),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.soft,
                    borderRadius: RegalosShape.card,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: StrokeIcon(
                            SettingsIcons.lock,
                            size: 18,
                            color: t.ink,
                            strokeWidth: 1.9,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Semantics(
                            container: true,
                            child: Text(
                              l10n.webSetAsideNotice(count),
                              style: t.styles.meta.copyWith(
                                color: t.textOnSoft,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
