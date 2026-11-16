import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/shared_axis_switcher.dart';
import '../../../core/motion/unlock_cascade.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../sharing/presentation/pairing_qr_view.dart' show PairingQrFrame;
import '../../sync/presentation/code_card.dart';
import '../data/vault_crypto.dart';
import 'web_gate_model.dart';
import 'web_gate_parts.dart';

/// La puerta de la versión web: lo que se ve antes de la app.
///
/// Pinta el [view] que le da el motor y llama a [actions]; en
/// [WebGateOpen] enseña [child] (la app). Entre estados hay una transición
/// con muelle (un fundido con «Reducir movimiento»); solo la tapa
/// ([WebGateLocked]) entra de golpe, para que el contenido no se vea ni un
/// fotograma de más.
///
/// No abre diálogos ni rutas: puede vivir encima del `Navigator`. La
/// confirmación de borrar los datos va dentro de la misma tarjeta.
class WebGate extends StatelessWidget {
  /// Crea la puerta.
  const WebGate({
    super.key,
    required this.view,
    required this.actions,
    required this.child,
    this.onConfirmCode,
    this.onRejectCode,
  });

  /// Qué enseñar.
  final WebGateView view;

  /// Lo que la interfaz pide al motor.
  final WebGateActions actions;

  /// La app, que solo se construye con la sesión abierta.
  final Widget child;

  /// Batch 4 numeric comparison; omitted by presentation-only doubles.
  final Future<void> Function()? onConfirmCode, onRejectCode;

  static int _index(WebGateView view) => switch (view) {
    WebGateConnect() => 0,
    WebGateComparing() => 1,
    WebGateConnectFailed() => 2,
    WebGateChoosePin() => 3,
    WebGateUnlock() => 4,
    WebGateSuspended() => 5,
    WebGateDisconnected() => 6,
    WebGateOtherTab() => 7,
    WebGateOpen() => 8,
    WebGateLocked() => 9,
    WebGateDamaged() => 10,
  };

  Widget _pane(BuildContext context) => switch (view) {
    final WebGateConnect v => _ConnectPane(url: v.url),
    final WebGateComparing v => _ComparingPane(
      code: v.code,
      actions: actions,
      onConfirmCode: onConfirmCode,
      onRejectCode: onRejectCode,
    ),
    final WebGateConnectFailed v => _FailedPane(
      reason: v.reason,
      actions: actions,
    ),
    final WebGateChoosePin v => _ChoosePinPane(
      personName: v.personName,
      actions: actions,
    ),
    final WebGateUnlock v => _UnlockPane(view: v, actions: actions),
    WebGateSuspended() => _SuspendedPane(actions: actions),
    final WebGateDisconnected v => _DisconnectedPane(
      unsentChanges: v.unsentChanges,
      confirmErase: v.confirmErase,
      actions: actions,
    ),
    WebGateOtherTab() => _OtherTabPane(actions: actions),
    WebGateDamaged() => _DamagedPane(actions: actions),
    WebGateOpen() => child,
    WebGateLocked() => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final locked = view is WebGateLocked;
    return _CascadeOnUnlock(
      unlocking: view is WebGateUnlock,
      open: view is WebGateOpen,
      child: Material(
        color: t.bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Al bloquear, lo de debajo se quita ya: ni la app ni sus estados
            // siguen vivos detrás de la tapa.
            if (!locked)
              SharedAxisSwitcher(
                index: _index(view),
                child: SizedBox.expand(child: _pane(context)),
              ),
            _CoverLayer(show: locked),
          ],
        ),
      ),
    );
  }
}

/// El desbloqueo en cascada de la web (como el del móvil, §1+.4): al pasar de
/// pedir la contraseña a enseñar la app, la pantalla que aparece no sale
/// entera. Sus bloques entran uno tras otro y la cuenta atrás rueda desde
/// vacío (`UnlockCascade`). Solo al desbloquear (no al crear la contraseña, ni
/// al volver tras la tapa de privacidad) y sin «Reducir movimiento».
class _CascadeOnUnlock extends StatefulWidget {
  const _CascadeOnUnlock({
    required this.unlocking,
    required this.open,
    required this.child,
  });

  final bool unlocking;
  final bool open;
  final Widget child;

  @override
  State<_CascadeOnUnlock> createState() => _CascadeOnUnlockState();
}

class _CascadeOnUnlockState extends State<_CascadeOnUnlock> {
  @override
  void didUpdateWidget(_CascadeOnUnlock old) {
    super.didUpdateWidget(old);
    if (widget.open && old.unlocking && !RegalosMotion.of(context).reduce) {
      // Cuando la app ya está montada y su primera entrada, en marcha.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          UnlockCascade.play();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// La capa de la tapa: entra de golpe y se va con un fundido.
class _CoverLayer extends StatelessWidget {
  const _CoverLayer({required this.show});

  final bool show;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: Duration.zero,
    reverseDuration: RegalosMotion.fade,
    switchOutCurve: Curves.linear,
    transitionBuilder: (child, animation) =>
        FadeTransition(opacity: animation, child: child),
    child: show
        ? const _Cover(key: ValueKey<bool>(true))
        : const SizedBox.shrink(key: ValueKey<bool>(false)),
  );
}

/// La tapa: lo único que se ve con la web bloqueada u oculta.
class _Cover extends StatelessWidget {
  const _Cover({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      label: l10n.webGateLockedLabel,
      excludeSemantics: true,
      child: ColoredBox(
        color: t.surface,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StrokeIcon(
                SettingsIcons.lock,
                size: 28,
                color: t.textSecondary,
                strokeWidth: 1.9,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.appTitle,
                style: t.styles.sectionTitle.copyWith(color: t.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ButtonKind { filled, outlined, danger }

/// Un botón de ancho completo que se bloquea mientras su acción corre: así un
/// doble clic no la lanza dos veces.
class _AsyncButton extends StatefulWidget {
  const _AsyncButton({
    required this.label,
    required this.onPressed,
    this.kind = _ButtonKind.filled,
  });

  final String label;
  final Future<void> Function() onPressed;
  final _ButtonKind kind;

  @override
  State<_AsyncButton> createState() => _AsyncButtonState();
}

class _AsyncButtonState extends State<_AsyncButton> {
  bool _busy = false;

  Future<void> _press() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onPressed();
    } on Object {
      // El motor cuenta lo que pasó con el estado siguiente.
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final VoidCallback? onPressed = _busy ? null : _press;
    final label = Text(widget.label, textAlign: TextAlign.center);
    final Widget button = switch (widget.kind) {
      _ButtonKind.filled => FilledButton(onPressed: onPressed, child: label),
      _ButtonKind.outlined => OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.text,
          minimumSize: const Size(44, 48),
          side: BorderSide(color: t.controlBorder),
          shape: const RoundedRectangleBorder(
            borderRadius: RegalosShape.button,
          ),
        ),
        onPressed: onPressed,
        child: label,
      ),
      _ButtonKind.danger => OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.danger,
          minimumSize: const Size(44, 48),
          side: BorderSide(color: t.danger),
          shape: const RoundedRectangleBorder(
            borderRadius: RegalosShape.button,
          ),
        ),
        onPressed: onPressed,
        child: label,
      ),
    };
    return SizedBox(width: double.infinity, child: button);
  }
}

// --- Conectar ---------------------------------------------------------------

class _ConnectPane extends StatelessWidget {
  const _ConnectPane({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WebGatePane(
      children: [
        WebGateHeading(
          title: l10n.webGateConnectTitle,
          body: l10n.webGateConnectIntro,
        ),
        const SizedBox(height: 20),
        WebGateSteps(
          steps: [
            l10n.webGateStepOpenApp,
            l10n.webGateConnectStep2,
            l10n.webGateConnectStep3,
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) => Center(
            child: PairingQrFrame(
              // Cambiar la URL repinta el QR sin repetir la entrada.
              key: ValueKey<String>(url),
              data: url,
              side: math.min(280, box.maxWidth),
            ),
          ),
        ),
        const SizedBox(height: 16),
        WebGateWaiting(text: l10n.webGateConnectWaiting),
      ],
    );
  }
}

// --- Comparar el código -----------------------------------------------------

class _ComparingPane extends StatelessWidget {
  const _ComparingPane({
    required this.code,
    required this.actions,
    this.onConfirmCode,
    this.onRejectCode,
  });

  final String code;
  final WebGateActions actions;
  final Future<void> Function()? onConfirmCode, onRejectCode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WebGatePane(
      children: [
        WebGateHeading(
          title: l10n.webGateCompareTitle,
          body: l10n.webGateCompareBody,
        ),
        const SizedBox(height: 20),
        VerificationCodeCard(label: l10n.webGateCompareLabel, code: code),
        if (onConfirmCode != null) ...[
          const SizedBox(height: 16),
          _AsyncButton(label: l10n.pairingV2Match, onPressed: onConfirmCode!),
        ],
        if (onRejectCode != null)
          _AsyncButton(
            kind: _ButtonKind.outlined,
            label: l10n.pairingV2NoMatch,
            onPressed: onRejectCode!,
          ),
        const SizedBox(height: 16),
        WebGateWaiting(text: l10n.webGateCompareWaiting),
        const SizedBox(height: 16),
        _AsyncButton(
          kind: _ButtonKind.outlined,
          label: l10n.webGateStartAgain,
          onPressed: actions.restartPairing,
        ),
      ],
    );
  }
}

// --- Fallo al conectar ------------------------------------------------------

class _FailedPane extends StatelessWidget {
  const _FailedPane({required this.reason, required this.actions});

  final WebConnectFailure reason;
  final WebGateActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WebGatePane(
      children: [
        WebGateHeading(
          title: l10n.webGateFailedTitle,
          body: switch (reason) {
            WebConnectFailure.expired => l10n.webGateFailedExpired,
            WebConnectFailure.codeMismatch => l10n.webGateFailedMismatch,
            WebConnectFailure.rejected => l10n.webGateFailedRejected,
            WebConnectFailure.network => l10n.webGateFailedNetwork,
          },
        ),
        const SizedBox(height: 24),
        _AsyncButton(
          label: l10n.webGateStartAgain,
          onPressed: actions.restartPairing,
        ),
      ],
    );
  }
}

// --- Elegir el PIN ----------------------------------------------------------

class _ChoosePinPane extends StatefulWidget {
  const _ChoosePinPane({required this.personName, required this.actions});

  final String personName;
  final WebGateActions actions;

  @override
  State<_ChoosePinPane> createState() => _ChoosePinPaneState();
}

enum _PinProblem { none, invalid, mismatch }

class _ChoosePinPaneState extends State<_ChoosePinPane> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  final FocusNode _repeatFocus = FocusNode();
  _PinProblem _problem = _PinProblem.none;
  bool _busy = false;
  bool _confirmRestart = false;

  @override
  void dispose() {
    _pin.dispose();
    _repeat.dispose();
    _repeatFocus.dispose();
    super.dispose();
  }

  void _clearProblem() {
    if (_problem != _PinProblem.none) {
      setState(() => _problem = _PinProblem.none);
    }
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final pin = _pin.text;
    if (!VaultCrypto.validPin(pin)) {
      setState(() => _problem = _PinProblem.invalid);
      return;
    }
    if (pin != _repeat.text) {
      setState(() => _problem = _PinProblem.mismatch);
      return;
    }
    setState(() {
      _problem = _PinProblem.none;
      _busy = true;
    });
    try {
      await widget.actions.choosePin(pin);
    } on Object {
      // El motor cuenta lo que pasó con el estado siguiente.
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
    final invalid = _problem == _PinProblem.invalid;
    final motion = RegalosMotion.of(context);
    final Widget content = _confirmRestart
        ? Column(
            key: const ValueKey<bool>(true),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebGateHeading(
                title: l10n.webGateRestartTitle,
                body: l10n.webGateRestartBody,
              ),
              const SizedBox(height: 24),
              _AsyncButton(
                label: l10n.webGateRestartConfirm,
                onPressed: widget.actions.restartPairing,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _confirmRestart = false),
                child: Text(l10n.actionCancel),
              ),
            ],
          )
        : _form(context, l10n, t, invalid);
    return WebGatePane(
      children: [
        AnimatedSize(
          duration: motion.duration(RegalosSprings.snapDuration),
          curve: motion.curve(RegalosCurves.snap),
          alignment: Alignment.topCenter,
          child: ValueSwitcher(alignment: Alignment.topLeft, child: content),
        ),
      ],
    );
  }

  Widget _form(
    BuildContext context,
    AppLocalizations l10n,
    RegalosTokens t,
    bool invalid,
  ) {
    return Column(
      key: const ValueKey<bool>(false),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebGateHeading(
          title: l10n.webGateChoosePinTitle(widget.personName),
          body: l10n.webGateChoosePinBody,
        ),
        const SizedBox(height: 12),
        Text(l10n.webGateChoosePinCheck, style: t.styles.meta),
        const SizedBox(height: 20),
        WebPinField(
          controller: _pin,
          label: l10n.webGatePinLabel,
          autofocus: true,
          enabled: !_busy,
          error: invalid,
          textInputAction: TextInputAction.next,
          onChanged: _clearProblem,
          onSubmitted: _repeatFocus.requestFocus,
        ),
        const SizedBox(height: 8),
        AnimatedDefaultTextStyle(
          duration: RegalosMotion.of(context).duration(RegalosMotion.fade),
          style: t.styles.meta.copyWith(
            color: invalid ? t.danger : t.textSecondary,
          ),
          child: Text(l10n.webGatePinRule),
        ),
        const SizedBox(height: 16),
        WebPinField(
          controller: _repeat,
          focusNode: _repeatFocus,
          label: l10n.webGatePinRepeatLabel,
          enabled: !_busy,
          error: _problem == _PinProblem.mismatch,
          onChanged: _clearProblem,
          onSubmitted: _submit,
        ),
        WebGateMessage(
          text: _problem == _PinProblem.mismatch
              ? l10n.webGatePinMismatch
              : null,
          danger: true,
          topGap: 8,
        ),
        const SizedBox(height: 12),
        Text(l10n.webGatePinSameHint, style: t.styles.meta),
        const SizedBox(height: 4),
        Text(l10n.webGatePinNoRecover, style: t.styles.meta),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? l10n.webGateSaving : l10n.webGateContinue),
        ),
        const SizedBox(height: 8),
        // Reiniciar pide confirmar: la puerta no abre diálogos, así que el
        // paso de más va en la propia tarjeta.
        _AsyncButton(
          kind: _ButtonKind.outlined,
          label: l10n.webGateStartAgain,
          onPressed: () async => setState(() => _confirmRestart = true),
        ),
      ],
    );
  }
}

// --- Desbloquear ------------------------------------------------------------

class _UnlockPane extends StatefulWidget {
  const _UnlockPane({required this.view, required this.actions});

  final WebGateUnlock view;
  final WebGateActions actions;

  @override
  State<_UnlockPane> createState() => _UnlockPaneState();
}

class _UnlockPaneState extends State<_UnlockPane> {
  final TextEditingController _pin = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _timer;
  int _remaining = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void didUpdateWidget(_UnlockPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.view, widget.view)) {
      // Una respuesta nueva del motor: el intento terminó.
      _busy = false;
      if (widget.view.wrongPin) {
        _pin.clear();
        _focus.requestFocus();
      }
      _startCountdown();
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    final wait = widget.view.retryAfter;
    _remaining = wait == null || wait <= Duration.zero
        ? 0
        : (wait.inMilliseconds / 1000).ceil();
    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _remaining -= 1);
        if (_remaining <= 0) {
          timer.cancel();
          _focus.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pin.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pin.text;
    if (_busy || _remaining > 0 || pin.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.actions.submitPin(pin);
    } on Object {
      // El motor cuenta lo que pasó con el estado siguiente.
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = widget.view;
    final left = view.attemptsLeft;
    final String? status = switch ((view.wrongPin, left)) {
      (true, final int n) =>
        '${l10n.webGateWrongPin} '
            '${l10n.webGateAttemptsLeft(n)}',
      (true, null) => l10n.webGateWrongPin,
      (false, final int n) => l10n.webGateAttemptsLeft(n),
      _ => null,
    };
    return WebGatePane(
      children: [
        WebGateHeading(
          title: l10n.webGateUnlockTitle,
          body: l10n.webGateUnlockBody,
        ),
        const SizedBox(height: 20),
        WebShakeOnChange(
          shakeToken: view.wrongPin ? view : null,
          child: WebPinField(
            controller: _pin,
            focusNode: _focus,
            label: l10n.webGatePinLabel,
            autofocus: true,
            enabled: !_busy,
            error: view.wrongPin,
            onSubmitted: _submit,
          ),
        ),
        WebGateMessage(text: status, danger: view.wrongPin, topGap: 8),
        WebGateMessage(
          text: _remaining > 0 ? l10n.webGateWait(_remaining) : null,
          valueKey: 'wait',
          topGap: 4,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy || _remaining > 0 ? null : _submit,
          child: Text(_busy ? l10n.webGateUnlocking : l10n.webGateUnlock),
        ),
      ],
    );
  }
}

// --- Suspendida -------------------------------------------------------------

class _SuspendedPane extends StatelessWidget {
  const _SuspendedPane({required this.actions});

  final WebGateActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WebGatePane(
      children: [
        WebGateHeading(
          title: l10n.webGateSuspendedTitle,
          body: l10n.webGateSuspendedBody,
        ),
        const SizedBox(height: 20),
        WebGateSteps(
          steps: [
            l10n.webGateStepOpenApp,
            l10n.webGateSuspendedStep2,
            l10n.webGateSuspendedStep3,
          ],
        ),
        const SizedBox(height: 24),
        _AsyncButton(label: l10n.webGateRetry, onPressed: actions.retry),
      ],
    );
  }
}

// --- Desconectado -----------------------------------------------------------

class _DisconnectedPane extends StatefulWidget {
  const _DisconnectedPane({
    required this.unsentChanges,
    required this.actions,
    this.confirmErase = false,
  });

  final int unsentChanges;
  final bool confirmErase;
  final WebGateActions actions;

  @override
  State<_DisconnectedPane> createState() => _DisconnectedPaneState();
}

class _DisconnectedPaneState extends State<_DisconnectedPane> {
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _confirming = widget.confirmErase;
  }

  @override
  void didUpdateWidget(covariant _DisconnectedPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.confirmErase) _confirming = true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final unsent = widget.unsentChanges;
    final motion = RegalosMotion.of(context);
    final Widget content = _confirming
        ? Column(
            key: const ValueKey<bool>(true),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebGateHeading(
                title: l10n.webGateEraseTitle,
                body: unsent > 0
                    ? l10n.webGateEraseBodyUnsent
                    : l10n.webGateEraseBody,
              ),
              const SizedBox(height: 24),
              _AsyncButton(
                kind: _ButtonKind.danger,
                label: l10n.actionDelete,
                onPressed: widget.actions.eraseComputer,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _confirming = false),
                child: Text(l10n.actionCancel),
              ),
            ],
          )
        : Column(
            key: const ValueKey<bool>(false),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebGateHeading(
                title: l10n.webGateDisconnectedTitle,
                body: l10n.webGateDisconnectedBody,
              ),
              if (unsent > 0) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.soft,
                    borderRadius: RegalosShape.card,
                  ),
                  child: Text(
                    l10n.webGateDisconnectedUnsent(unsent),
                    style: t.styles.meta.copyWith(color: t.textOnSoft),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _AsyncButton(
                label: l10n.webGateReconnect,
                onPressed: widget.actions.reconnect,
              ),
              const SizedBox(height: 8),
              // Borrar pide confirmar: primero un paso más, en la tarjeta.
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.danger,
                  minimumSize: const Size(44, 48),
                  side: BorderSide(color: t.danger),
                  shape: const RoundedRectangleBorder(
                    borderRadius: RegalosShape.button,
                  ),
                ),
                onPressed: () => setState(() => _confirming = true),
                child: Text(l10n.webGateErase, textAlign: TextAlign.center),
              ),
            ],
          );
    return WebGatePane(
      children: [
        AnimatedSize(
          duration: motion.duration(RegalosSprings.snapDuration),
          curve: motion.curve(RegalosCurves.snap),
          alignment: Alignment.topCenter,
          child: ValueSwitcher(alignment: Alignment.topLeft, child: content),
        ),
      ],
    );
  }
}

// --- Datos dañados ----------------------------------------------------------

class _DamagedPane extends StatefulWidget {
  const _DamagedPane({required this.actions});

  final WebGateActions actions;

  @override
  State<_DamagedPane> createState() => _DamagedPaneState();
}

class _DamagedPaneState extends State<_DamagedPane> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final Widget content = _confirming
        ? Column(
            key: const ValueKey<bool>(true),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebGateHeading(
                title: l10n.webGateEraseTitle,
                body: l10n.webGateEraseBodyUnsent,
              ),
              const SizedBox(height: 24),
              _AsyncButton(
                kind: _ButtonKind.danger,
                label: l10n.actionDelete,
                onPressed: widget.actions.eraseComputer,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _confirming = false),
                child: Text(l10n.actionCancel),
              ),
            ],
          )
        : Column(
            key: const ValueKey<bool>(false),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WebGateHeading(
                title: l10n.webGateDamagedTitle,
                body: l10n.webGateDamagedBody,
              ),
              const SizedBox(height: 12),
              Text(l10n.webGateDamagedPhoneHint, style: t.styles.meta),
              const SizedBox(height: 24),
              // Borrar pide confirmar: un paso más, dentro de la tarjeta.
              _AsyncButton(
                kind: _ButtonKind.danger,
                label: l10n.webGateErase,
                onPressed: () async => setState(() => _confirming = true),
              ),
            ],
          );
    return WebGatePane(
      children: [
        AnimatedSize(
          duration: motion.duration(RegalosSprings.snapDuration),
          curve: motion.curve(RegalosCurves.snap),
          alignment: Alignment.topCenter,
          child: ValueSwitcher(alignment: Alignment.topLeft, child: content),
        ),
      ],
    );
  }
}

// --- Otra pestaña -----------------------------------------------------------

class _OtherTabPane extends StatelessWidget {
  const _OtherTabPane({required this.actions});

  final WebGateActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WebGatePane(
      children: [
        WebGateHeading(
          title: l10n.webGateOtherTabTitle,
          body: l10n.webGateOtherTabBody,
        ),
        const SizedBox(height: 24),
        _AsyncButton(label: l10n.webGateUseHere, onPressed: actions.useHere),
      ],
    );
  }
}
