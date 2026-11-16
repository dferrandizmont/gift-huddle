import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../application/web_app_provider.dart';
import '../application/web_device_providers.dart';
import 'web_settings_section.dart';

/// Aviso, una sola vez por sesión abierta, de que hubo PIN fallidos desde la
/// última vez que se desbloqueó este ordenador.
///
/// Sale con `lastUnlockFailedAttempts` mayor que 0 y mientras no se cierre:
/// «Cambiar PIN» abre la hoja de cambio (y, si se cambia, lo cierra) y
/// «Entendido» lo cierra. Fuera de la web o con 0 no ocupa nada; al aparecer o
/// desaparecer se funde y estira el hueco con `fold`.
class FailedAttemptsNotice extends ConsumerWidget {
  /// Crea el aviso.
  const FailedAttemptsNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWeb = ref.watch(webAppProvider);
    final count = isWeb
        ? ref.watch(webDeviceStateProvider).lastUnlockFailedAttempts
        : 0;
    final dismissed = ref.watch(webFailedAttemptsDismissedProvider);
    final show = count > 0 && !dismissed;
    final motion = RegalosMotion.of(context);
    return AnimatedSize(
      duration: motion.duration(RegalosCurves.foldDuration),
      curve: motion.curve(RegalosCurves.fold),
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: RegalosMotion.fade,
        child: !show
            ? const SizedBox(key: ValueKey<bool>(false), width: double.infinity)
            : Padding(
                key: const ValueKey<bool>(true),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _Card(
                  count: count,
                  onChangePin: () async {
                    final changed = await showWebChangePin(
                      context,
                      ref.read(webGateActionsProvider),
                    );
                    if (changed) {
                      ref
                          .read(webFailedAttemptsDismissedProvider.notifier)
                          .dismiss();
                    }
                  },
                  onDismiss: () => ref
                      .read(webFailedAttemptsDismissedProvider.notifier)
                      .dismiss(),
                ),
              ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.count,
    required this.onChangePin,
    required this.onDismiss,
  });

  final int count;
  final VoidCallback onChangePin;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.soft,
          borderRadius: RegalosShape.card,
          border: Border.all(color: t.danger),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: StrokeIcon(
                  SettingsIcons.shield,
                  size: 18,
                  color: t.ink,
                  strokeWidth: 1.9,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.webFailedAttemptsNotice(count),
                      style: t.styles.meta.copyWith(color: t.textOnSoft),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: onChangePin,
                          child: Text(l10n.webSettingsChangePin),
                        ),
                        TextButton(
                          onPressed: onDismiss,
                          child: Text(l10n.actionUnderstood),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
