import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/pane_scope.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/regalos_switch.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/settings_row.dart';
import '../../../l10n/app_localizations.dart';
import '../../lock/application/lock_controller.dart';
import '../../lock/presentation/pin_setup_screen.dart';
import '../../review/application/review_providers.dart';
import 'pin_verify_screen.dart';
import 'settings_column.dart';
import '../../../core/widgets/regalos_snack_bar.dart';

/// Si el móvil puede usar huella o rostro.
final biometricsAvailableProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.read(lockControllerProvider.notifier).biometricsAvailable(),
);

/// Ajustes › Bloqueo: activar o quitar el PIN, cambiarlo y la huella o el
/// rostro.
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  Future<bool?> _push(
    BuildContext context,
    WidgetRef ref,
    WidgetBuilder builder,
  ) {
    final route = MaterialPageRoute<bool>(builder: builder);
    final result = Navigator.of(context, rootNavigator: true).push(route);
    if (isStoreReviewEnabled) {
      ref.read(reviewVisibilityProvider).trackPinRoute(route);
    }
    return result;
  }

  void _say(BuildContext context, String text) {
    showRegalosSnackBar(context, SnackBar(content: Text(text)));
  }

  /// Crea un PIN nuevo (al activar el bloqueo o al cambiarlo).
  Future<bool> _createPin(
    BuildContext context,
    WidgetRef ref,
    LockController lock,
  ) async {
    final chosen = await _push(
      context,
      ref,
      (pinContext) => PinSetupScreen(
        onPinChosen: (pin) async {
          await lock.setPin(pin);
          if (pinContext.mounted) {
            Navigator.of(pinContext).pop(true);
          }
        },
        onSkip: () => Navigator.of(pinContext).pop(false),
      ),
    );
    return chosen ?? false;
  }

  Future<void> _togglePin(
    BuildContext context,
    WidgetRef ref, {
    required bool on,
  }) async {
    final l10n = AppLocalizations.of(context);
    final lock = ref.read(lockControllerProvider.notifier);
    if (on) {
      if (await _createPin(context, ref, lock) && context.mounted) {
        _say(context, l10n.securityPinEnabled);
      }
      return;
    }
    final removed = await _push(
      context,
      ref,
      (_) => PinVerifyScreen(
        title: l10n.securityDisableTitle,
        message: l10n.securityDisablePrompt,
        onSubmit: lock.disable,
        pinLength: ref.read(lockControllerProvider).value?.pinLength,
      ),
    );
    if ((removed ?? false) && context.mounted) {
      _say(context, l10n.securityPinDisabled);
    }
  }

  Future<void> _changePin(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final lock = ref.read(lockControllerProvider.notifier);
    final verified = await _push(
      context,
      ref,
      (_) => PinVerifyScreen(
        title: l10n.securityChangePin,
        message: l10n.securityChangeCurrentPrompt,
        onSubmit: lock.unlock,
        pinLength: ref.read(lockControllerProvider).value?.pinLength,
      ),
    );
    if (verified != true || !context.mounted) {
      return;
    }
    if (await _createPin(context, ref, lock) && context.mounted) {
      _say(context, l10n.securityPinChanged);
    }
  }

  Future<void> _toggleBiometrics(
    BuildContext context,
    WidgetRef ref, {
    required bool on,
  }) async {
    final l10n = AppLocalizations.of(context);
    final ok = await ref
        .read(lockControllerProvider.notifier)
        .setBiometrics(on, reason: l10n.lockBiometricReason);
    if (!ok && on && context.mounted) {
      _say(context, l10n.securityBiometricsFailed);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final lock = ref.watch(lockControllerProvider).value;
    final available = ref.watch(biometricsAvailableProvider).value ?? false;
    final pinOn = (lock?.enabled ?? false) && (lock?.pinSet ?? false);
    final bioOn = lock?.biometrics ?? false;

    var order = 0;
    return Scaffold(
      body: StaggerScope(
        // En dos paneles el detalle ya cambia con su propio eje: no repite
        // la entrada escalonada.
        animate: PaneScope.roleOf(context) != PaneRole.detail,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: settingsColumnPadding(context),
            children: [
              ScreenHeader(
                eyebrow: l10n.navSettings,
                title: l10n.settingsSecurity,
                backLabel: l10n.backTo(l10n.navSettings),
                onBack: () =>
                    context.canPop() ? context.pop() : context.go('/settings'),
              ),
              const SizedBox(height: 12),
              StaggerItem(
                index: order++,
                child: SettingsRow(
                  title: l10n.securityPinTitle,
                  hint: l10n.securityPinHint,
                  trailing: RegalosSwitch(
                    value: pinOn,
                    semanticLabel: l10n.securityPinTitle,
                    onChanged: lock == null
                        ? null
                        : (v) => _togglePin(context, ref, on: v),
                  ),
                ),
              ),
              StaggerItem(
                index: order++,
                child: SettingsRow(
                  title: l10n.securityChangePin,
                  onTap: pinOn ? () => _changePin(context, ref) : null,
                ),
              ),
              StaggerItem(
                index: order++,
                child: SettingsRow(
                  title: l10n.securityBiometrics,
                  hint: available
                      ? l10n.securityBiometricsHint
                      : l10n.securityBiometricsUnavailable,
                  trailing: RegalosSwitch(
                    value: bioOn,
                    semanticLabel: l10n.securityBiometrics,
                    onChanged: pinOn && available
                        ? (v) => _toggleBiometrics(context, ref, on: v)
                        : null,
                  ),
                ),
              ),
              StaggerItem(
                index: order++,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(l10n.securityNote, style: t.styles.meta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
