import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/gift_status.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'gift_status_l10n.dart';
import 'status_checkbox.dart';

/// Píldora con la forma del estado y su nombre.
///
/// Sirve de filtro o de selector. Sin [onTap] solo informa; con [onTap] la
/// zona táctil mide 44 px de alto aunque la píldora mida 32. Seleccionada se
/// rellena con el acento y pasa a negrita (no depende solo del color).
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.selected = false,
    this.onTap,
  });

  final GiftStatus status;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final name = status.label(l10n);

    final textStyle = selected
        ? t.styles.metaStrong.copyWith(
            fontWeight: FontWeight.w600,
            color: t.ink,
          )
        : t.styles.metaStrong;

    final pill = Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? t.selection : null,
        border: Border.all(color: selected ? t.selectionBorder : t.chipBorder),
        borderRadius: RegalosShape.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusGlyph(
            status: status,
            size: 16,
            stroke: selected ? t.ink : null,
          ),
          const SizedBox(width: 6),
          Flexible(child: Text(name, style: textStyle)),
        ],
      ),
    );

    final Widget body = onTap == null
        ? pill
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Center(
              widthFactor: 1,
              child: InkWell(
                onTap: onTap,
                borderRadius: RegalosShape.chip,
                child: pill,
              ),
            ),
          );

    return Semantics(
      container: true,
      button: onTap != null,
      selected: selected,
      label: name,
      onTap: onTap,
      excludeSemantics: true,
      child: body,
    );
  }
}
