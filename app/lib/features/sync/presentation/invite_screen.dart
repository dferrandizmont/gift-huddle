import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/device/device_name.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../settings/presentation/settings_column.dart';
import '../application/sync_controller.dart';
import '../domain/sync_status.dart';
import '../invites/invite_host.dart';
import '../application/pairing_v2_controller.dart';
import 'invite_approval_view.dart';
import 'pairing_v2_host_view.dart';

/// Ajustes › Móviles de la familia › Conectar otro móvil › Está lejos: crea
/// el enlace, lo comparte y espera la petición para aprobarla.
class InviteScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const InviteScreen({super.key});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _share(BuildContext context, String link) async {
    final l10n = AppLocalizations.of(context);
    final text = l10n.inviteShareText(link);
    // Dos intentos: el primero tras crear el enlace puede perderse si la
    // pantalla todavía está cambiando; el botón «Compartir de nuevo» queda
    // siempre a mano.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final box = context.findRenderObject();
        final origin = box is RenderBox && box.hasSize
            ? box.localToGlobal(Offset.zero) & box.size
            : null;
        await SharePlus.instance.share(
          ShareParams(text: text, sharePositionOrigin: origin),
        );
        return;
      } on Object {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if (!context.mounted) {
            return;
          }
        }
      }
    }
  }

  Future<void> _create(BuildContext context) async {
    final controller = ref.read(inviteHostProvider.notifier);
    // El nombre que verá el otro móvil: el que haya escrito aquí.
    await ref
        .read(familyControllerProvider.notifier)
        .setDeviceName(deviceNameToSend(ref, _name.text));
    await controller.create();
    // La pantalla pasa de «Crear» a «Esperando»: la hoja de compartir se abre
    // cuando ya está dibujada, no a mitad del cambio.
    await WidgetsBinding.instance.endOfFrame;
    final state = ref.read(inviteHostProvider);
    if (context.mounted &&
        state.phase == InvitePhase.waiting &&
        state.link != null) {
      await _share(context, state.link!);
    }
  }

  String? _hostError(AppLocalizations l10n, InviteHostIssue? issue) =>
      switch (issue) {
        null => null,
        InviteHostIssue.notReady => l10n.inviteNeedSync,
        InviteHostIssue.network => l10n.inviteErrorNetwork,
        InviteHostIssue.unknown => l10n.inviteErrorUnknown,
      };

  @override
  Widget build(BuildContext context) {
    // Con la sincronización v2 el enlace se crea al entrar y quien lo abre
    // entra comparando un número (ADR 0004).
    if (ref.watch(pairingV2AvailableProvider)) {
      return _frame(context, const PairingV2HostView(far: true), 'v2');
    }
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final myName =
        ref.watch(familyControllerProvider).value?.identity?.deviceName ?? '';
    final invite = ref.watch(inviteHostProvider);
    final sync = ref.watch(syncControllerProvider);
    final controller = ref.read(inviteHostProvider.notifier);

    final Widget body;
    switch (invite.phase) {
      case InvitePhase.request:
      case InvitePhase.approving:
        body = InviteApprovalView(
          guestName: invite.guestName ?? '',
          code: invite.code ?? '',
          busy: invite.phase == InvitePhase.approving,
          errorText: _hostError(l10n, invite.issue),
          onAccept: controller.approve,
          onReject: controller.reject,
        );
      case InvitePhase.waiting:
        final expires = invite.expiresAt?.toLocal();
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.inviteWaitingTitle,
                style: t.styles.screenTitleSmall,
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.inviteWaitingBody, style: t.styles.body),
            if (expires != null) ...[
              const SizedBox(height: 8),
              Text(l10n.inviteExpires(expires, expires), style: t.styles.meta),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: invite.link == null
                  ? null
                  : () => _share(context, invite.link!),
              child: Text(l10n.inviteShareAgain),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: controller.reject,
              child: Text(l10n.inviteCancel),
            ),
          ],
        );
      case InvitePhase.approved:
        body = _result(
          context,
          title: l10n.inviteApprovedTitle,
          text: l10n.inviteApprovedBody(
            invite.guestName?.isNotEmpty == true
                ? invite.guestName!
                : l10n.deviceNameDefault,
          ),
          onNew: controller.dismiss,
        );
      case InvitePhase.rejected:
        body = _result(
          context,
          title: l10n.inviteRowTitle,
          text: l10n.inviteRejectedBody,
          onNew: controller.dismiss,
        );
      case InvitePhase.expired:
        body = _result(
          context,
          title: l10n.inviteRowTitle,
          text: l10n.inviteExpiredBody,
          onNew: controller.dismiss,
        );
      case InvitePhase.idle:
      case InvitePhase.creating:
      case InvitePhase.failed:
        final ready = sync.active;
        final error = _hostError(l10n, invite.issue);
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.inviteIntro, style: t.styles.body),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.soft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.inviteHowItWorks,
                style: t.styles.body.copyWith(color: t.textOnSoft),
              ),
            ),
            if (!ready) ...[
              const SizedBox(height: 12),
              Text(
                sync.phase == SyncPhase.notConfigured
                    ? l10n.joinInviteUnavailable
                    : l10n.inviteNeedSync,
                style: t.styles.body,
              ),
            ] else if (error != null) ...[
              const SizedBox(height: 12),
              Text(error, style: t.styles.body),
            ],
            if (ready) ...[
              const SizedBox(height: 16),
              DeviceNameField(controller: _name, initial: myName),
            ],
            const SizedBox(height: 20),
            if (ready)
              FilledButton(
                onPressed: invite.phase == InvitePhase.creating
                    ? null
                    : () => _create(context),
                child: invite.phase == InvitePhase.creating
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.inviteCreate),
              )
            else if (sync.phase == SyncPhase.disabled)
              // Ya no hay pantalla de Sincronización ni interruptor: se
              // enciende desde aquí.
              FilledButton(
                onPressed: () =>
                    ref.read(syncControllerProvider.notifier).setEnabled(true),
                child: Text(l10n.inviteGoToSync),
              ),
          ],
        );
    }

    // Cada fase del enlace entra con el mismo cambio de paso que las hojas.
    final step = switch (invite.phase) {
      InvitePhase.request || InvitePhase.approving => 'request',
      InvitePhase.waiting => 'waiting',
      InvitePhase.approved => 'approved',
      InvitePhase.rejected => 'rejected',
      InvitePhase.expired => 'expired',
      InvitePhase.idle || InvitePhase.creating || InvitePhase.failed => 'idle',
    };
    return _frame(context, body, step);
  }

  Widget _frame(BuildContext context, Widget body, Object step) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // La cabecera y el contenido, en la columna de Ajustes (560),
            // centrada: la cabecera con `ContentWidth` y lo que se desplaza
            // con el margen en su `padding`.
            ContentWidth(
              maxWidth: RegalosLayout.formColumn,
              child: ScreenHeader(
                eyebrow: l10n.settingsShare,
                title: l10n.inviteRowTitle,
                backLabel: l10n.backTo(l10n.settingsShare),
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: settingsColumnPadding(context, inset: 20, top: 16),
                child: SheetSteps(step: step, child: body),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _result(
    BuildContext context, {
    required String title,
    required String text,
    required VoidCallback onNew,
  }) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: t.styles.screenTitleSmall),
        ),
        const SizedBox(height: 8),
        Text(text, style: t.styles.body),
        const SizedBox(height: 20),
        FilledButton(onPressed: onNew, child: Text(l10n.inviteNew)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(l10n.actionDone),
        ),
      ],
    );
  }
}
