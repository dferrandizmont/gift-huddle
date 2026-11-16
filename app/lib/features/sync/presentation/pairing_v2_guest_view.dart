import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/motion/success_mark.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/sheet_parts.dart';
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
        body = const _Progress();
      case PairingV2GuestPhase.choosePerson:
        body = _ChoosePerson(
          people: state.people,
          selfId: state.selfId,
          onChoose: _controller.choosePerson,
        );
      case PairingV2GuestPhase.waitingCode:
        body = _Waiting(
          text: l10n.pairingV2GuestWaitingCode,
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
  const _Waiting({required this.text, required this.onCancel});

  final String text;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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

class _ChoosePerson extends StatelessWidget {
  const _ChoosePerson({
    required this.people,
    required this.onChoose,
    this.selfId,
  });

  final List<PairingV2Person> people;

  /// La persona que este móvil ya tenía en «Este móvil es de», si está en
  /// [people]: sale primera, marcada y con «Continuar».
  final String? selfId;
  final ValueChanged<String?> onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    var selfIndex = -1;
    if (selfId != null) {
      selfIndex = people.indexWhere((p) => p.id == selfId);
    }
    final preselected = selfIndex >= 0 ? people[selfIndex] : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.pairingV2ChooseTitle,
            style: t.styles.screenTitleSmall,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          people.isEmpty
              ? l10n.pairingV2ChooseNone
              : preselected != null
              ? l10n.pairingV2ChooseBodySelf(preselected.name)
              : l10n.pairingV2ChooseBody,
          style: t.styles.body,
        ),
        if (people.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (preselected != null)
            _PersonRow(
              index: selfIndex,
              person: preselected,
              selected: true,
              onTap: () => onChoose(preselected.id),
            ),
          for (var i = 0; i < people.length; i++)
            if (i != selfIndex)
              _PersonRow(
                index: i,
                person: people[i],
                onTap: () => onChoose(people[i].id),
              ),
        ],
        if (preselected != null) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => onChoose(preselected.id),
            child: Text(l10n.pairingV2ChooseContinue),
          ),
        ],
        const SizedBox(height: 20),
        // «Elegir después» es una decisión aparte, con su aviso delante: no
        // se confunde con una persona de la lista (N2).
        WarningBox(l10n.pairingV2ChooseLaterBody),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => onChoose(null),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(44, 48),
            foregroundColor: t.text,
            side: BorderSide(color: t.controlBorder),
            shape: const RoundedRectangleBorder(
              borderRadius: RegalosShape.button,
            ),
          ),
          child: Text(l10n.pairingV2ChooseLaterTitle),
        ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.index,
    required this.person,
    required this.onTap,
    this.selected = false,
  });

  final int index;
  final PairingV2Person person;
  final VoidCallback onTap;

  /// La fila premarcada: fondo pastel que se tiñe y visto que se dibuja.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final tint = RegalosMotion.of(context)
        .duration(const Duration(milliseconds: 240));
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: person.name,
      excludeSemantics: true,
      onTap: onTap,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          begin: Colors.transparent,
          end: selected ? t.soft : Colors.transparent,
        ),
        duration: tint,
        builder: (context, color, child) => Material(
          color: color,
          borderRadius: RegalosShape.button,
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: EdgeInsets.symmetric(
              vertical: 8,
              horizontal: selected ? 8 : 0,
            ),
            decoration: BoxDecoration(
              border: selected
                  ? null
                  : Border(top: BorderSide(color: t.separator)),
            ),
            child: Row(
              children: [
                PersonAvatar(name: person.name, colorIndex: index, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    person.name,
                    style: selected
                        ? t.styles.rowTitle.copyWith(
                            color: t.ink,
                            fontWeight: FontWeight.w600,
                          )
                        : t.styles.rowTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected)
                  DrawnCheck(
                    color: t.ink,
                    size: 22,
                    strokeWidth: 2.2,
                    duration: const Duration(milliseconds: 300),
                    delay: const Duration(milliseconds: 80),
                    curve: const Cubic(0.3, 0.7, 0.3, 1),
                  )
                else
                  StrokeIcon(
                    AppIcons.chevronRight,
                    color: t.textSecondary,
                    strokeWidth: 1.9,
                  ),
              ],
            ),
          ),
        ),
      ),
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
