import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/motion/success_mark.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../sharing/presentation/pairing_qr_view.dart';
import '../application/pairing_v2_controller.dart';
import 'code_card.dart';

/// El emparejamiento v2 desde el móvil que invita: el QR («Está aquí») o el
/// enlace («Está lejos»), el número que hay que comparar y el resultado.
///
/// Al montarse empieza una invitación si no hay ninguna en marcha; al
/// desmontarse la cancela. No lleva ninguna clave: quien lee el QR o abre el
/// enlace solo puede pedir entrada, y entra cuando los dos móviles muestran el
/// mismo número y este pulsa «Coinciden» (y, si dice ser de alguien, «Sí, es
/// de…»). Si la familia sigue en v1 con otros móviles, antes de nada pregunta
/// si se pasa a la sincronización nueva, que no se puede deshacer.
class PairingV2HostView extends ConsumerStatefulWidget {
  /// Crea la vista. Con [far] enseña el enlace para compartir en lugar del
  /// QR.
  const PairingV2HostView({super.key, this.far = false});

  /// Si el otro móvil está lejos: se comparte el enlace en lugar de enseñar
  /// el QR.
  final bool far;

  @override
  ConsumerState<PairingV2HostView> createState() => _PairingV2HostViewState();
}

class _PairingV2HostViewState extends ConsumerState<PairingV2HostView> {
  late final PairingV2HostController _controller;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    // Guardado ya: en `dispose` no se puede leer con `ref`.
    _controller = ref.read(pairingV2HostProvider.notifier);
    // El estado no se toca mientras se construye el árbol.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          ref.read(pairingV2HostProvider).phase == PairingV2HostPhase.idle) {
        unawaited(_controller.start());
      }
    });
  }

  @override
  void dispose() {
    final controller = _controller;
    // Fuera del desmontaje del árbol; si el contenedor ya no existe (cierre
    // de la app o de una prueba) no hay nada que cancelar.
    scheduleMicrotask(() {
      try {
        controller.dismiss();
      } on Object {
        // Sin contenedor: nada que reposar.
      }
    });
    super.dispose();
  }

  /// Pasar a v2 no se puede deshacer: se pregunta antes (hallazgo 8). Si se
  /// cancela, la hoja se cierra sin haber tocado nada.
  Future<void> _askMigration() async {
    if (_asking) return;
    _asking = true;
    final l10n = AppLocalizations.of(context);
    final go = await showRegalosConfirm(
      context,
      title: l10n.pairingV2MigrateTitle,
      body: l10n.pairingV2MigrateBody,
      confirmLabel: l10n.pairingV2MigrateContinue,
      cancelLabel: l10n.actionCancel,
    );
    _asking = false;
    if (!mounted) return;
    if (go) {
      await _controller.confirmMigration();
    } else {
      _controller.dismiss();
      await Navigator.of(context).maybePop();
    }
  }

  Future<void> _share(BuildContext context, String link) async {
    final l10n = AppLocalizations.of(context);
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: l10n.inviteShareText(link),
          sharePositionOrigin: origin,
        ),
      );
    } on Object {
      // El botón sigue a mano para intentarlo otra vez.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<PairingV2HostState>(pairingV2HostProvider, (previous, next) {
      if (next.phase == PairingV2HostPhase.confirmMigration &&
          previous?.phase != PairingV2HostPhase.confirmMigration) {
        unawaited(_askMigration());
      }
    });
    final state = ref.watch(pairingV2HostProvider);
    final Widget body;
    switch (state.phase) {
      case PairingV2HostPhase.idle:
      case PairingV2HostPhase.confirmMigration:
      case PairingV2HostPhase.preparing:
        body = _Progress(text: l10n.pairingV2Preparing);
      case PairingV2HostPhase.waiting:
        body = _Waiting(
          link: state.link ?? '',
          far: widget.far,
          onShare: (box) => _share(box, state.link ?? ''),
          onCancel: _controller.cancel,
        );
      case PairingV2HostPhase.compare:
        body = _Compare(
          code: state.code ?? '',
          withoutPerson: state.guestWithoutPerson,
          busy: false,
          onMatch: _controller.confirm,
          onNoMatch: _controller.cancel,
        );
      case PairingV2HostPhase.confirmPerson:
        body = _ConfirmPerson(
          name: state.guestPersonName ?? '',
          busy: false,
          onYes: _controller.confirmPerson,
          onNo: _controller.cancel,
        );
      case PairingV2HostPhase.approving:
        // Se queda en el paso desde el que se aprobó, con el indicador.
        body = state.guestPersonId != null
            ? _ConfirmPerson(
                name: state.guestPersonName ?? '',
                busy: true,
                onYes: () {},
                onNo: () {},
              )
            : _Compare(
                code: state.code ?? '',
                withoutPerson: state.guestWithoutPerson,
                busy: true,
                onMatch: () {},
                onNoMatch: () {},
              );
      case PairingV2HostPhase.done:
        body = _Done(far: widget.far);
      case PairingV2HostPhase.cancelled:
        body = _Failure(
          text: l10n.pairingV2HostCancelled,
          onRestart: _controller.start,
        );
      case PairingV2HostPhase.failed:
        body = _Failure(
          text: state.notReady
              ? l10n.pairingV2NotReady
              : l10n.pairingV2HostFailed,
          onRestart: _controller.start,
        );
    }
    // Cada fase entra con el mismo cambio de paso que las hojas, y la altura
    // se ajusta con `snap`. Aprobar es el mismo paso que aquel desde el que
    // se aprueba; avisar de la migración, el mismo que preparar.
    final step = switch (state.phase) {
      PairingV2HostPhase.approving =>
        state.guestPersonId != null
            ? PairingV2HostPhase.confirmPerson
            : PairingV2HostPhase.compare,
      PairingV2HostPhase.idle ||
      PairingV2HostPhase.confirmMigration => PairingV2HostPhase.preparing,
      final phase => phase,
    };
    return SheetSteps(step: step, child: body);
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(text, style: t.styles.body, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({
    required this.link,
    required this.far,
    required this.onShare,
    required this.onCancel,
  });

  final String link;
  final bool far;
  final void Function(BuildContext) onShare;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final maxSide = PairingQrView.maxSideOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (far) ...[
          Semantics(
            header: true,
            child: Text(
              l10n.pairingV2FarTitle,
              style: t.styles.screenTitleSmall,
            ),
          ),
          const SizedBox(height: 8),
          Text(l10n.pairingV2FarBody, style: t.styles.body),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.soft,
              borderRadius: RegalosShape.card,
            ),
            child: SelectableText(
              link,
              style: t.styles.body.copyWith(color: t.textOnSoft),
            ),
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (box) => FilledButton(
              onPressed: () => onShare(box),
              child: Text(l10n.pairingV2Share),
            ),
          ),
        ] else
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) => PairingQrFrame(
                data: link,
                side: math.min(constraints.maxWidth, maxSide),
              ),
            ),
          ),
        const SizedBox(height: 16),
        WarningBox(l10n.pairingV2NoticeExpires),
        const SizedBox(height: 12),
        Text(
          l10n.pairingV2WaitingHere,
          style: t.styles.meta,
          textAlign: TextAlign.center,
        ),
        if (far) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onCancel, child: Text(l10n.inviteCancel)),
        ],
      ],
    );
  }
}

class _Compare extends StatelessWidget {
  const _Compare({
    required this.code,
    required this.withoutPerson,
    required this.busy,
    required this.onMatch,
    required this.onNoMatch,
  });

  final String code;
  final bool withoutPerson;
  final bool busy;
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
        Text(l10n.pairingV2HostCompareBody, style: t.styles.body),
        const SizedBox(height: 16),
        VerificationCodeCard(
          label: l10n.inviteCodeLabel,
          code: code,
          confirmed: busy,
        ),
        if (withoutPerson) ...[
          const SizedBox(height: 12),
          WarningBox(l10n.pairingV2NoPersonWarning),
        ],
        const SizedBox(height: 20),
        if (busy) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 8),
          Text(
            l10n.pairingV2Approving,
            style: t.styles.meta,
            textAlign: TextAlign.center,
          ),
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

/// «Este móvil dice ser de…»: se confirma aparte de los códigos
/// (hallazgo 3). «No es suyo» cancela la invitación.
class _ConfirmPerson extends StatelessWidget {
  const _ConfirmPerson({
    required this.name,
    required this.busy,
    required this.onYes,
    required this.onNo,
  });

  final String name;
  final bool busy;
  final VoidCallback onYes;
  final VoidCallback onNo;

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
            l10n.pairingV2ClaimTitle(name),
            style: t.styles.screenTitleSmall,
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.pairingV2ClaimBody, style: t.styles.body),
        const SizedBox(height: 20),
        if (busy) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 8),
          Text(
            l10n.pairingV2Approving,
            style: t.styles.meta,
            textAlign: TextAlign.center,
          ),
        ] else ...[
          FilledButton(
            onPressed: onYes,
            child: Text(l10n.pairingV2ClaimYes(name)),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onNo,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 48),
              foregroundColor: t.text,
              side: BorderSide(color: t.controlBorder),
              shape: const RoundedRectangleBorder(
                borderRadius: RegalosShape.button,
              ),
            ),
            child: Text(l10n.pairingV2ClaimNo),
          ),
        ],
      ],
    );
  }
}

class _Done extends StatefulWidget {
  const _Done({required this.far});

  final bool far;

  @override
  State<_Done> createState() => _DoneState();
}

class _DoneState extends State<_Done> {
  @override
  void initState() {
    super.initState();
    // La vibración de éxito llega con el sello (250 ms), cuando el visto se
    // dibuja; con «Reducir movimiento», al momento. Este aviso no es el de
    // «Se ha conectado otro móvil» del QR v1, que sale cuando el otro móvil
    // ya ha entrado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.haptics.success(after: context.hapticSeal);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final far = widget.far;
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    // El mismo sello que la hoja de «Emparejados»: el cuadro rebota, el visto
    // se dibuja y el texto y el botón entran detrás, a 40 ms.
    return StaggerScope(
      step: const Duration(milliseconds: 40),
      delay: const Duration(milliseconds: 140),
      maxItems: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: SuccessMark(size: 64)),
            const SizedBox(height: 14),
            StaggerItem(
              index: 0,
              dy: 8,
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l10n.pairingV2HostDone,
                  style: t.styles.screenTitleSmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (far) ...[
              const SizedBox(height: 20),
              StaggerItem(
                index: 1,
                dy: 8,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(l10n.actionDone),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.text, required this.onRestart});

  final String text;
  final VoidCallback onRestart;

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
        FilledButton(onPressed: onRestart, child: Text(l10n.joinInviteRestart)),
      ],
    );
  }
}
