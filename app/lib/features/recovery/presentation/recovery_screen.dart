import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/pane_scope.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/settings_row.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_column.dart';
import '../../settings/presentation/verify_owner.dart';
import '../../sync/application/recovery_providers.dart';
import 'recovery_create_screen.dart';
import 'recovery_file_check_screen.dart';
import 'recovery_parts.dart';
import 'recovery_problem.dart';

/// Lo que dice la fila «Código de recuperación» de Ajustes a su derecha.
String recoveryRowValue(AppLocalizations l10n, RecoveryStatus status) =>
    switch (status.readiness) {
      RecoveryReadiness.absent => l10n.recoveryValueNone,
      RecoveryReadiness.prepared => l10n.recoveryValuePrepared,
      RecoveryReadiness.confirmationPending => l10n.recoveryValueUnconfirmed,
      RecoveryReadiness.updatePending => l10n.recoveryValuePending,
      RecoveryReadiness.needsAttention => l10n.recoveryValueAttention,
      RecoveryReadiness.transferred => l10n.recoveryValueTransferred,
    };

/// Ajustes › Código de recuperación: el estado real de la copia y lo que se
/// puede hacer con ella (crearla, cambiarla, quitarla o reintentar).
class RecoveryScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const RecoveryScreen({super.key});

  @override
  ConsumerState<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends ConsumerState<RecoveryScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Se mira otra vez al entrar: el estado de la última vez puede estar viejo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(recoveryApplicationProvider.notifier).refresh());
      }
    });
  }

  Future<void> _open({required bool rotate}) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RecoveryCreateScreen(rotate: rotate),
      ),
    );
    if (mounted) {
      unawaited(ref.read(recoveryApplicationProvider.notifier).refresh());
    }
  }

  /// «Comprobar un fichero»: si abre el código vigente, queda comprobado.
  Future<void> _checkFile() async {
    await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const RecoveryFileCheckScreen()),
    );
    if (mounted) {
      unawaited(ref.read(recoveryApplicationProvider.notifier).refresh());
    }
  }

  void _say(String text) {
    showRegalosSnackBar(context, SnackBar(content: Text(text)));
  }

  Future<void> _retry() async {
    if (_busy) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(recoveryApplicationProvider.notifier).retry();
    } on RecoveryApplicationException catch (e) {
      if (mounted) {
        _say(recoveryProblemTitle(l10n, recoveryProblemOfException(e)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Cancela lo que está a medias: una recuperación en este móvil (con su
  /// texto según la reclamación) o la preparación del código.
  Future<void> _cancelPending(RecoveryStatus status) async {
    final l10n = AppLocalizations.of(context);
    final restore = status.hasPendingRestore;
    final ok = restore
        ? await confirmAbandonRecovery(context, claimSent: status.claimSent)
        : await showRegalosConfirm(
            context,
            title: l10n.recoveryMaintCancelTitle,
            body: l10n.recoveryMaintCancelBody,
            confirmLabel: l10n.recoveryMaintCancelConfirm,
            cancelLabel: l10n.recoverAbandonKeep,
          );
    if (!ok || !mounted) {
      return;
    }
    setState(() => _busy = true);
    var showWords = false;
    try {
      final notifier = ref.read(recoveryApplicationProvider.notifier);
      if (restore) {
        await notifier.abandon();
      } else {
        await notifier.cancelMaintenance();
        // Si un cambio ya se había confirmado en el servidor, sus palabras
        // nuevas esperan a que se vean: se pasa por el PIN o la huella antes
        // de consumirlas (lo hace la pantalla de crear al abrirse).
        showWords = await notifier.hasCodeDisplay();
      }
    } on Object {
      if (mounted) {
        _say(l10n.recoverAbandonFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    if (showWords && mounted) {
      await _open(
        rotate:
            ref.read(recoveryStatusProvider).readiness ==
            RecoveryReadiness.prepared,
      );
    }
  }

  /// «Entendido»: descarta un fallo ya cerrado y la pantalla vuelve a «Crear
  /// código» o al código preparado.
  Future<void> _dismiss() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(recoveryApplicationProvider.notifier).dismissFailure();
    } on Object {
      if (mounted) {
        _say(l10n.recoverAbandonFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    // Si no queda otro móvil ni la web, quitar el código también retira la
    // lista del servidor: se avisa antes. Es orientativo (la operación lo
    // vuelve a comprobar); sin respuesta, el aviso no sale.
    setState(() => _busy = true);
    var stopsRemote = false;
    try {
      stopsRemote = await ref
          .read(recoveryApplicationProvider.notifier)
          .removalStopsRemoteSync();
    } on Object {
      stopsRemote = false;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    final ok = await showRegalosConfirm(
      context,
      title: l10n.recoveryRemoveTitle,
      body: stopsRemote
          ? '${l10n.recoveryRemoveBody}\n\n${l10n.recoveryRemoveSoloNote}'
          : l10n.recoveryRemoveBody,
      confirmLabel: l10n.recoveryRemoveConfirm,
      cancelLabel: l10n.actionCancel,
    );
    if (!ok || !mounted) {
      return;
    }
    try {
      final allowed = await verifyOwner(
        context,
        ref,
        title: l10n.recoveryAuthTitle,
        message: l10n.recoveryRemoveAuthMessage,
        biometricReason: l10n.recoveryRemoveBiometric,
      );
      if (!allowed || !mounted) {
        return;
      }
    } on Object {
      if (mounted) {
        _say(l10n.recoverAbandonFailed);
      }
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(recoveryApplicationProvider.notifier).retireCode();
      if (mounted) {
        _say(l10n.recoveryRemoved);
      }
    } on RecoveryApplicationException catch (e) {
      if (mounted) {
        _say(recoveryProblemTitle(l10n, recoveryProblemOfException(e)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final status = ref.watch(recoveryStatusProvider);
    final readiness = status.readiness;

    var order = 0;
    Widget block(Widget child) => StaggerItem(index: order++, child: child);
    const edge = EdgeInsets.fromLTRB(16, 12, 16, 0);

    final Widget card;
    final List<Widget> actions = [];
    switch (readiness) {
      case RecoveryReadiness.absent:
        card = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RecoveryCard(
              leading: RecoveryBadge(icon: SettingsIcons.key),
              title: l10n.recoveryAbsentTitle,
              body: l10n.recoveryAbsentBody,
            ),
            const SizedBox(height: 12),
            WarningBox(l10n.recoveryAbsentWarn),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : () => _open(rotate: false),
              child: Text(l10n.recoveryCreate),
            ),
          ],
        );
      case RecoveryReadiness.prepared:
        card = RecoveryCard(
          leading: RecoveryBadge(icon: SettingsIcons.shield),
          title: l10n.recoveryPreparedTitle,
          body: l10n.recoveryPreparedBody,
        );
        actions.addAll([
          SettingsRow(
            icon: SettingsIcons.refresh,
            title: l10n.recoveryChange,
            hint: l10n.recoveryChangeHint,
            onTap: _busy ? null : () => _open(rotate: true),
          ),
          SettingsRow(
            icon: SettingsIcons.trash,
            title: l10n.recoveryRemove,
            hint: l10n.recoveryRemoveHint,
            danger: true,
            chevron: false,
            onTap: _busy ? null : _remove,
          ),
        ]);
      case RecoveryReadiness.confirmationPending:
        card = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RecoveryCard(
              leading: RecoveryBadge(icon: SettingsIcons.key),
              title: l10n.recoveryUnconfirmedTitle,
              body: l10n.recoveryUnconfirmedBody,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : () => _open(rotate: true),
              child: Text(l10n.recoveryContinue),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _checkFile,
              child: Text(l10n.recoveryCheckFileAction),
            ),
          ],
        );
        actions.add(
          SettingsRow(
            icon: SettingsIcons.trash,
            title: l10n.recoveryRemove,
            hint: l10n.recoveryRemoveHint,
            danger: true,
            chevron: false,
            onTap: _busy ? null : _remove,
          ),
        );
      case RecoveryReadiness.updatePending:
        card = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RecoveryCard(
              leading: const SizedBox(
                width: 48,
                height: 48,
                child: Center(child: RecoverySpinner(size: 24)),
              ),
              title: l10n.recoveryPendingTitle,
              body: l10n.recoveryPendingBody,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => _cancelPending(status),
              child: Text(
                status.hasPendingRestore
                    ? l10n.recoverAbandon
                    : l10n.recoveryMaintCancel,
              ),
            ),
          ],
        );
      case RecoveryReadiness.needsAttention:
        final problem = recoveryProblemOf(status.cause);
        card = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RecoveryCard(
              leading: RecoveryBadge(icon: SettingsIcons.refresh),
              title: l10n.recoveryAttentionTitle,
              body:
                  '${recoveryProblemTitle(l10n, problem)}. '
                  '${recoveryProblemBody(l10n, problem)}',
            ),
            const SizedBox(height: 16),
            if (status.canDismissFailure)
              // Un fallo ya cerrado: no hay nada que reintentar ni cancelar.
              FilledButton(
                onPressed: _busy ? null : _dismiss,
                child: Text(l10n.actionUnderstood),
              )
            else ...[
              FilledButton(
                onPressed: _busy ? null : _retry,
                child: Text(l10n.recoveryRetry),
              ),
              // Lo que está a medias también se puede cancelar.
              TextButton(
                onPressed: _busy ? null : () => _cancelPending(status),
                child: Text(
                  status.hasPendingRestore
                      ? l10n.recoverAbandon
                      : l10n.recoveryMaintCancel,
                ),
              ),
            ],
          ],
        );
      case RecoveryReadiness.transferred:
        card = RecoveryCard(
          leading: RecoveryBadge(icon: SettingsIcons.devices),
          title: l10n.transferredTitle,
          body: l10n.transferredBody,
        );
    }

    return Scaffold(
      body: StaggerScope(
        animate: PaneScope.roleOf(context) != PaneRole.detail,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: settingsColumnPadding(context),
            children: [
              ScreenHeader(
                eyebrow: l10n.navSettings,
                title: l10n.settingsRecovery,
                subtitle: l10n.recoverySubtitle,
                backLabel: l10n.backTo(l10n.navSettings),
                onBack: () =>
                    context.canPop() ? context.pop() : context.go('/settings'),
              ),
              block(
                Padding(
                  padding: edge,
                  child: RecoveryFade(stateKey: readiness, child: card),
                ),
              ),
              if (actions.isNotEmpty)
                block(
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: t.separator)),
                    ),
                    child: Column(children: actions),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
