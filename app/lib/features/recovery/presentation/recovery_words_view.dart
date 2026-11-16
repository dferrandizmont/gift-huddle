import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/stagger.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../sharing/presentation/pairing_qr_view.dart';
import 'recovery_parts.dart';

/// Las 24 palabras numeradas en una cuadrícula legible, o su QR para imprimir.
///
/// Se tapan solas en cuanto la app deja de estar en primer plano (el selector
/// de apps, una llamada, el cambio de app): las palabras no se quedan en
/// ninguna miniatura. No se copian al portapapeles en ningún momento.
class RecoveryWordsView extends StatefulWidget {
  /// Crea la vista.
  const RecoveryWordsView({
    super.key,
    required this.words,
    required this.qrText,
    required this.showQr,
  });

  /// Las 24 palabras, en orden.
  final List<String> words;

  /// El texto del QR imprimible.
  final String qrText;

  /// Si se enseña el QR en vez de las palabras.
  final bool showQr;

  @override
  State<RecoveryWordsView> createState() => _RecoveryWordsViewState();
}

class _RecoveryWordsViewState extends State<RecoveryWordsView>
    with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _covered = _isAway(WidgetsBinding.instance.lifecycleState);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static bool _isAway(AppLifecycleState? state) =>
      state != null && state != AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final away = _isAway(state);
    if (away != _covered) {
      setState(() => _covered = away);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    if (_covered) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RegalosShape.card,
        ),
        child: Column(
          children: [
            Text(
              l10n.recoveryHidden,
              style: t.styles.rowTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.recoveryHiddenBody,
              style: t.styles.body.copyWith(color: t.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (widget.showQr) {
      return Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Center(
              child: PairingQrFrame(
                data: widget.qrText,
                side: math.min(constraints.maxWidth, 280),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.recoveryQrBody,
            style: t.styles.body.copyWith(color: t.textSecondary),
          ),
        ],
      );
    }
    return StaggerScope(
      maxItems: 1,
      child: StaggerItem(index: 0, child: _WordGrid(words: widget.words)),
    );
  }
}

class _WordGrid extends StatelessWidget {
  const _WordGrid({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = recoveryGridColumns(context, constraints.maxWidth);
        const gap = 8.0;
        final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < words.length; i++)
              SizedBox(
                width: cell,
                child: Semantics(
                  label: l10n.recoveryWordItem(i + 1, words[i]),
                  excludeSemantics: true,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: RegalosShape.card,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${i + 1}',
                              style: t.styles.meta.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            words[i],
                            style: t.styles.rowTitle,
                            maxLines: 1,
                            overflow: TextOverflow.visible,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
