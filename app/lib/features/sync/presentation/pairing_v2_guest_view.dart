import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../core/widgets/soft_note.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/verify_owner.dart';
import '../application/pairing_v2_controller.dart';
import 'code_card.dart';

/// El emparejamiento v2 desde el móvil que entra: abre la invitación
/// [inviteId], pregunta de quién es este móvil, enseña el número para
/// comparar y espera a que el otro móvil dé acceso.
///
/// [onDone] se llama una vez cuando este móvil ya está dentro de la familia;
/// [onExit] cuando la persona sale tras un fallo, una invitación caducada o
/// un «No coinciden».
class PairingV2GuestView extends ConsumerStatefulWidget {
  /// Crea la vista.
  const PairingV2GuestView({
    super.key,
    required this.inviteId,
    required this.onDone,
    required this.onExit,
    this.deviceName = '',
  });

  /// Id de la invitación (de un QR o de un enlace).
  final String inviteId;

  /// Nombre confirmado antes de abrir la invitación; vacío si no lo hubo.
  final String deviceName;

  /// Ya está dentro.
  final VoidCallback onDone;

  /// Salir sin haber entrado.
  final VoidCallback onExit;

  @override
  ConsumerState<PairingV2GuestView> createState() => _PairingV2GuestViewState();
}

class _PairingV2GuestViewState extends ConsumerState<PairingV2GuestView> {
  late final PairingV2GuestController _controller;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    // Guardado ya: en `dispose` no se puede leer con `ref`.
    _controller = ref.read(pairingV2GuestProvider.notifier);
    // El estado no se toca mientras se construye el árbol.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          _controller.begin(widget.inviteId, deviceName: widget.deviceName),
        );
      }
    });
  }

  @override
  void dispose() {
    final controller = _controller;
    scheduleMicrotask(() {
      try {
        controller.reset();
      } on Object {
        // Sin contenedor: nada que reposar.
      }
    });
    super.dispose();
  }

  Future<void> _askReplace() async {
    if (_dialogOpen) {
      return;
    }
    _dialogOpen = true;
    final l10n = AppLocalizations.of(context);
    final replace = await showRegalosConfirm(
      context,
      title: l10n.joinConflictTitle,
      body: l10n.joinConflictBody,
      confirmLabel: l10n.joinReplace,
      cancelLabel: l10n.actionCancel,
    );
    _dialogOpen = false;
    if (replace && mounted) {
      // Sustituir la lista no se puede deshacer: PIN o biometría antes
      // (hallazgo 5). Sin PIN configurado no se pide nada.
      var verified = false;
      try {
        verified = await verifyOwner(
          context,
          ref,
          title: l10n.joinReplace,
          message: l10n.joinReplacePinPrompt,
          biometricReason: l10n.joinReplaceBiometricReason,
        );
      } on Object {
        // El bloqueo no se pudo leer: no se sustituye nada.
      }
      if (verified && mounted) {
        await _controller.confirmReplace();
        return;
      }
    }
    _controller.reset();
    widget.onExit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<PairingV2GuestState>(pairingV2GuestProvider, (previous, next) {
      if (next.phase == PairingV2GuestPhase.confirmReplace &&
          previous?.phase != PairingV2GuestPhase.confirmReplace) {
        unawaited(_askReplace());
      } else if (next.phase == PairingV2GuestPhase.done &&
          previous?.phase != PairingV2GuestPhase.done) {
        widget.onDone();
      }
    });
    final state = ref.watch(pairingV2GuestProvider);
    final Widget body;
    switch (state.phase) {
      case PairingV2GuestPhase.idle:
      case PairingV2GuestPhase.opening:
      case PairingV2GuestPhase.confirmReplace:
      case PairingV2GuestPhase.done:
      // 1.0.6: este móvil ya no elige persona (la eligió quien invita); un
      // controlador que aún llegara a este paso solo espera.
      case PairingV2GuestPhase.choosePerson:
        body = const _Progress();
      case PairingV2GuestPhase.waitingCode:
        body = _Waiting(
          text: l10n.pairingV2GuestWaitingCode,
          // 1.0.6: quien invita ha elegido de quién es este móvil.
          assigned: state.hostAssigned ? l10n.pairingV2GuestAssigned : null,
          onCancel: _controller.cancel,
        );
      case PairingV2GuestPhase.compare:
        body = _Compare(
          code: state.code ?? '',
          onMatch: _controller.confirmCode,
          onNoMatch: _controller.cancel,
        );
      case PairingV2GuestPhase.waitingApproval:
        body = _Compare(
          code: state.code ?? '',
          waiting: true,
          onMatch: _controller.confirmCode,
          onNoMatch: _controller.cancel,
        );
      case PairingV2GuestPhase.cancelled:
        body = _Failure(
          text: l10n.pairingV2GuestCancelled,
          onExit: widget.onExit,
        );
      case PairingV2GuestPhase.gone:
        body = _Failure(text: l10n.joinInviteGone, onExit: widget.onExit);
      case PairingV2GuestPhase.failed:
        body = _Failure(
          text: state.failureCode == 'restore_pending'
              // Una recuperación a medias bloquea unirse: se dice cuál y qué
              // hacer, en vez de quedarse en el progreso.
              ? '${l10n.recoveryProblemPendingTitle}. '
                    '${l10n.recoveryProblemPendingBody}'
              : state.versionMismatch
              ? l10n.pairingV2VersionMismatch
              : state.notReady
              ? l10n.joinInviteNetwork
              : l10n.joinInviteUnknown,
          onExit: widget.onExit,
        );
    }
    return SheetSteps(
      step: switch (state.phase) {
        PairingV2GuestPhase.waitingApproval => PairingV2GuestPhase.compare,
        PairingV2GuestPhase.idle ||
        PairingV2GuestPhase.opening ||
        PairingV2GuestPhase.confirmReplace ||
        PairingV2GuestPhase.choosePerson ||
        PairingV2GuestPhase.done => PairingV2GuestPhase.opening,
        final other => other,
      },
      child: body,
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 32),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.text, required this.onCancel, this.assigned});

  final String text;

  /// «Quien te invita ha elegido de quién es este móvil»: una nota con el
  /// icono de personas, antes de la espera.
  final String? assigned;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (assigned != null) ...[
          SoftNote(icon: AppIcons.people, text: assigned!),
          const SizedBox(height: 12),
        ],
        Text(text, style: t.styles.body),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        ),
        TextButton(onPressed: onCancel, child: Text(l10n.actionCancel)),
      ],
    );
  }
}

class _Compare extends StatelessWidget {
  const _Compare({
    required this.code,
    required this.onMatch,
    required this.onNoMatch,
    this.waiting = false,
  });

  final String code;
  final bool waiting;
  final VoidCallback onMatch;
  final VoidCallback onNoMatch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.pairingV2CompareTitle,
            style: t.styles.screenTitleSmall,
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.pairingV2GuestCompareBody, style: t.styles.body),
        const SizedBox(height: 16),
        VerificationCodeCard(
          label: l10n.inviteCodeLabel,
          code: code,
          confirmed: waiting,
        ),
        const SizedBox(height: 20),
        if (waiting) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 8),
          Text(
            l10n.pairingV2GuestWaitingApproval,
            style: t.styles.meta,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onNoMatch, child: Text(l10n.actionCancel)),
        ] else ...[
          FilledButton(onPressed: onMatch, child: Text(l10n.pairingV2Match)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onNoMatch,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 48),
              foregroundColor: t.text,
              side: BorderSide(color: t.controlBorder),
              shape: const RoundedRectangleBorder(
                borderRadius: RegalosShape.button,
              ),
            ),
            child: Text(l10n.pairingV2NoMatch),
          ),
        ],
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.text, required this.onExit});

  final String text;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, style: t.styles.body),
        const SizedBox(height: 16),
        FilledButton(onPressed: onExit, child: Text(l10n.joinInviteRestart)),
      ],
    );
  }
}
