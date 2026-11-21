import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/success_mark.dart';
import '../../../core/sync/model.dart' show Recipient;
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/settings_row.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../sharing/presentation/join_qr_screen.dart'
    show scannerBuilderProvider;
import '../../sharing/presentation/qr_camera_scanner.dart';
import '../../sharing/presentation/scan_viewfinder.dart';
import '../../sync/application/pairing_v2_controller.dart';
import '../../sync/application/pairing_v2_flow.dart';
import '../../sync/presentation/code_card.dart';

/// «Conectar la web» desde el móvil (ADR 0003, §5): escanea el QR que enseña el
/// navegador, pregunta «¿De quién es este ordenador?», empareja como un
/// dispositivo más y, después de comparar el código, da acceso.
///
/// Los pasos son tres, y cada uno entra con el mismo cambio de paso que las
/// hojas:
///
/// 1. **Escanear.** El QR solo vale si lo valida `WebPairingQr.parse`
///    (origen exacto, `/w` y dos campos canónicos); si no, avisa sin salir.
/// 2. **De quién es.** Una persona viva de la familia. Ninguna oferta se crea
///    hasta tener el QR y la persona.
/// 3. **Emparejar.** Reutiliza el anfitrión v2 (`pairingV2HostProvider`): el
///    QR ya lo enseña el navegador, así que aquí no hay otro; solo esperar,
///    comparar el código y dar acceso. La persona se confirma sola porque la ha
///    elegido este mismo móvil.
class ConnectWebScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const ConnectWebScreen({super.key});

  @override
  ConsumerState<ConnectWebScreen> createState() => _ConnectWebScreenState();
}

enum _Step { scan, whose, pairing }

class _ConnectWebScreenState extends ConsumerState<ConnectWebScreen> {
  late final PairingV2HostController _controller;
  final GlobalKey<ScanViewfinderState> _finder =
      GlobalKey<ScanViewfinderState>();

  _Step _step = _Step.scan;
  bool _back = false;

  // El QR leído y validado, y la persona elegida.
  String? _qr;
  String? _person;

  // El último QR leído no valía.
  bool _invalid = false;

  // Falló antes de que el anfitrión llegara a empezar (persona o QR).
  bool _startFailed = false;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    // Guardado ya: en `dispose` no se puede leer con `ref`.
    _controller = ref.read(pairingV2HostProvider.notifier);
  }

  @override
  void dispose() {
    final controller = _controller;
    // Fuera del desmontaje del árbol; si el contenedor ya no existe no hay
    // nada que cancelar.
    scheduleMicrotask(() {
      try {
        controller.dismiss();
      } on Object {
        // Sin contenedor: nada que reposar.
      }
    });
    super.dispose();
  }

  void _go(_Step step, {bool back = false}) => setState(() {
    _step = step;
    _back = back;
  });

  void _onCode(String text) {
    if (_step != _Step.scan) return;
    try {
      WebPairingQr.parse(text);
    } on Object {
      // Cualquier otro QR (de una invitación de móvil, de otra web…) no vale.
      ref.read(hapticsProvider).warning();
      if (!_invalid) setState(() => _invalid = true);
      return;
    }
    ref.read(hapticsProvider).success();
    _finder.currentState?.lock(null);
    _qr = text;
    setState(() => _invalid = false);
    _go(_Step.whose);
  }

  Future<void> _start(String personId) async {
    final qr = _qr;
    if (qr == null) return;
    _person = personId;
    _startFailed = false;
    // Reposo antes de empezar: el estado puede ser el de un intento anterior.
    _controller.dismiss();
    _go(_Step.pairing);
    try {
      await _controller.startWeb(qr, guestPerson: personId);
    } on Object {
      if (mounted) setState(() => _startFailed = true);
    }
  }

  /// Vuelve a escanear: otro código del ordenador.
  void _scanAgain() {
    _controller.dismiss();
    _qr = null;
    _person = null;
    _startFailed = false;
    _finder.currentState?.reset();
    _go(_Step.scan, back: true);
  }

  /// Pasar a v2 no se puede deshacer: se pregunta antes. Si se cancela, no se
  /// ha tocado nada y se vuelve a escanear.
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
      _scanAgain();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<PairingV2HostState>(pairingV2HostProvider, (previous, next) {
      if (_step != _Step.pairing) return;
      if (next.phase == PairingV2HostPhase.confirmMigration &&
          previous?.phase != PairingV2HostPhase.confirmMigration) {
        unawaited(_askMigration());
      }
      // La persona la eligió este móvil: si el ordenador responde con otra, no
      // se da acceso. Si es la misma, se confirma sin preguntar otra vez.
      if (next.phase == PairingV2HostPhase.confirmPerson &&
          previous?.phase != PairingV2HostPhase.confirmPerson) {
        if (next.guestPersonId == _person) {
          unawaited(_controller.confirmPerson());
        } else {
          unawaited(_controller.cancel());
        }
      }
    });
    final Widget body = switch (_step) {
      _Step.scan => _ScanStep(
        finder: _finder,
        invalid: _invalid,
        onCode: _onCode,
      ),
      _Step.whose => _WhoseStep(onPick: _start),
      _Step.pairing => _PairingStep(
        startFailed: _startFailed,
        onScanAgain: _scanAgain,
        onClose: () => Navigator.of(context).maybePop(),
      ),
    };
    final compact = WindowClass.of(context) == WindowClass.compact;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: l10n.connectWebTitle,
              backLabel: l10n.actionBack,
              onBack: _step == _Step.whose
                  ? _scanAgain
                  : () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: ContentWidth(
                maxWidth: compact ? double.infinity : 560,
                child: SheetSteps(step: _step, back: _back, child: body),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- escanear

class _ScanStep extends ConsumerStatefulWidget {
  const _ScanStep({
    required this.finder,
    required this.invalid,
    required this.onCode,
  });

  final GlobalKey<ScanViewfinderState> finder;
  final bool invalid;
  final ValueChanged<String> onCode;

  @override
  ConsumerState<_ScanStep> createState() => _ScanStepState();
}

class _ScanStepState extends ConsumerState<_ScanStep> {
  /// El permiso de cámara está denegado: no hay nada que enmarcar.
  bool _denied = false;

  @override
  Widget build(BuildContext context) {
    final finder = widget.finder;
    final invalid = widget.invalid;
    final onCode = widget.onCode;
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final custom = ref.watch(scannerBuilderProvider);
    final scanner =
        custom?.call(context, onCode) ??
        QrCameraScanner(
          onCode: onCode,
          onDeniedChanged: (denied) {
            if (mounted) {
              setState(() => _denied = denied);
            }
          },
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            l10n.connectWebIntro,
            style: t.styles.body.copyWith(color: t.textSecondary),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 480,
                  maxHeight: 480,
                ),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      scanner,
                      if (!_denied)
                        IgnorePointer(child: ScanViewfinder(key: finder)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        _Message(show: invalid, text: l10n.connectWebScanInvalid, danger: true),
      ],
    );
  }
}

/// Una línea de aviso que entra y sale con un fundido y estirando el hueco.
class _Message extends StatelessWidget {
  const _Message({required this.show, required this.text, this.danger = false});

  final bool show;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    return AnimatedSize(
      duration: motion.duration(RegalosCurves.foldDuration),
      curve: motion.curve(RegalosCurves.fold),
      alignment: Alignment.topCenter,
      child: show
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  text,
                  style: t.styles.meta.copyWith(
                    color: danger ? t.danger : t.text,
                  ),
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

// ---------------------------------------------------------------- de quién

class _WhoseStep extends ConsumerWidget {
  const _WhoseStep({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final family = ref.watch(familyControllerProvider).value;
    final people = [
      for (final r in family?.fullView.recipients ?? const <Recipient>[])
        if (!r.archived && r.name.trim().isNotEmpty) r,
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Semantics(
            header: true,
            child: Text(
              l10n.connectWebWhoseTitle,
              style: t.styles.screenTitleSmall,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            l10n.connectWebWhoseBody,
            style: t.styles.body.copyWith(color: t.textSecondary),
          ),
        ),
        if (people.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(l10n.connectWebNoPeople, style: t.styles.meta),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.separator)),
            ),
            child: Column(
              children: [
                for (final person in people)
                  SettingsRow(
                    icon: SettingsIcons.people,
                    title: person.name.trim(),
                    onTap: () => onPick(person.id),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- emparejar

class _PairingStep extends ConsumerWidget {
  const _PairingStep({
    required this.startFailed,
    required this.onScanAgain,
    required this.onClose,
  });

  final bool startFailed;
  final VoidCallback onScanAgain;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(pairingV2HostProvider);
    final controller = ref.read(pairingV2HostProvider.notifier);
    final Widget body;
    final Object step;
    if (startFailed) {
      step = 'failed';
      body = _Failure(text: l10n.connectWebFailed, onScanAgain: onScanAgain);
    } else {
      switch (state.phase) {
        case PairingV2HostPhase.idle:
        case PairingV2HostPhase.confirmMigration:
        case PairingV2HostPhase.preparing:
          step = 'preparing';
          body = _Progress(text: l10n.pairingV2Preparing);
        case PairingV2HostPhase.waiting:
          step = 'waiting';
          body = _Progress(
            text: l10n.connectWebWaiting,
            onCancel: controller.cancel,
          );
        case PairingV2HostPhase.compare:
          step = 'compare';
          body = _Compare(
            code: state.code ?? '',
            onMatch: controller.confirm,
            onNoMatch: controller.cancel,
          );
        case PairingV2HostPhase.confirmPerson:
        case PairingV2HostPhase.approving:
          step = 'approving';
          body = _Progress(text: l10n.connectWebApproving);
        case PairingV2HostPhase.done:
          step = 'done';
          body = _Done(onClose: onClose);
        case PairingV2HostPhase.cancelled:
          step = 'cancelled';
          body = _Failure(
            text: l10n.connectWebCancelled,
            onScanAgain: onScanAgain,
          );
        case PairingV2HostPhase.failed:
          step = 'failed';
          body = _Failure(
            text: state.needsNewWebQr
                ? l10n.connectWebNewQr
                : (state.notReady
                      ? l10n.pairingV2NotReady
                      : l10n.connectWebFailed),
            onScanAgain: onScanAgain,
          );
      }
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: SheetSteps(step: step, child: body),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.text, this.onCancel});

  final String text;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 1.9),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              text,
              style: t.styles.body,
              textAlign: TextAlign.center,
            ),
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onCancel, child: Text(l10n.connectWebCancel)),
          ],
        ],
      ),
    );
  }
}

class _Compare extends StatelessWidget {
  const _Compare({
    required this.code,
    required this.onMatch,
    required this.onNoMatch,
  });

  final String code;
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
        Text(l10n.connectWebCompareBody, style: t.styles.body),
        const SizedBox(height: 16),
        VerificationCodeCard(label: l10n.inviteCodeLabel, code: code),
        const SizedBox(height: 20),
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
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: DrawnCheck(color: t.ink, size: 40)),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.connectWebDoneTitle,
              style: t.styles.screenTitleSmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.connectWebDoneBody,
            style: t.styles.body.copyWith(color: t.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onClose, child: Text(l10n.actionDone)),
        ],
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.text, required this.onScanAgain});

  final String text;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: StrokeIcon(
                SettingsIcons.computer,
                size: 20,
                color: t.textSecondary,
                strokeWidth: 1.9,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(text, style: t.styles.body),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: onScanAgain,
          child: Text(l10n.connectWebScanAgain),
        ),
      ],
    );
  }
}
