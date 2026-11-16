import 'package:flutter/material.dart';

import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tabler_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../application/reparto_view_provider.dart';

/// Clave del conmutador (para las pruebas).
const Key kRepartoViewToggleKey = ValueKey<String>('repartoViewToggle');

/// El conmutador de las dos vistas de Reparto: iconos de rejilla y de lista,
/// en un contenedor de radio 8 con un indicador de radio 6 que se desliza con
/// el muelle `snap`. Con «Reducir movimiento» el indicador no se desliza: se
/// funde en 150 ms.
class RepartoViewToggle extends StatelessWidget {
  /// Crea el conmutador.
  const RepartoViewToggle({
    super.key,
    required this.view,
    required this.onChanged,
  });

  /// La vista activa.
  final RepartoView view;

  /// Se llama al tocar la otra vista.
  final ValueChanged<RepartoView> onChanged;

  /// Medidas de un botón: 44 de ancho y 38 de alto, más 3 de margen.
  static const double buttonWidth = 44;
  static const double buttonHeight = 38;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    Widget button(RepartoView v, StrokeIconBuilder icon, String label) {
      final selected = v == view;
      return Semantics(
        container: true,
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        onTap: () => onChanged(v),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(v),
          child: AnimatedContainer(
            duration: motion.reduce ? RegalosMotion.fade : Duration.zero,
            width: buttonWidth,
            height: buttonHeight,
            decoration: BoxDecoration(
              color: motion.reduce && selected
                  ? t.fill
                  : t.fill.withValues(alpha: 0),
              borderRadius: const BorderRadius.all(Radius.circular(6)),
            ),
            alignment: Alignment.center,
            child: StrokeIcon(
              icon,
              size: 20,
              color: selected ? t.ink : t.textSecondary,
              strokeWidth: 1.75,
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.repartoViewLabel,
      child: DecoratedBox(
        key: kRepartoViewToggleKey,
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Stack(
            children: [
              if (!motion.reduce)
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: RegalosSprings.snapDuration,
                    curve: RegalosCurves.snap,
                    alignment: view == RepartoView.grid
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: DecoratedBox(
                      key: const ValueKey<String>('repartoViewIndicator'),
                      decoration: BoxDecoration(
                        color: t.fill,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(6),
                        ),
                      ),
                      child: const SizedBox(
                        width: buttonWidth,
                        height: buttonHeight,
                      ),
                    ),
                  ),
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  button(
                    RepartoView.grid,
                    tablerLayoutGrid,
                    l10n.repartoViewGrid,
                  ),
                  button(
                    RepartoView.occasion,
                    tablerList,
                    l10n.repartoViewOccasion,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
