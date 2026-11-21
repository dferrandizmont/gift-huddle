import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/value_switcher.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../application/lock_controller.dart';
import 'pin_pad.dart';
import '../data/biometrics.dart';
import 'biometric_labels.dart';

/// Crear el PIN: se escribe y se repite.
///
/// [onPinChosen] recibe el PIN cuando los dos coinciden. Con [onSkip] hay un
/// botón para dejarlo para más tarde.
class PinSetupScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const PinSetupScreen({super.key, required this.onPinChosen, this.onSkip});

  /// Se llama con el PIN confirmado.
  final Future<void> Function(String pin) onPinChosen;

  /// Si se da, enseña «Ahora no».
  final VoidCallback? onSkip;

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  final GlobalKey<PinDisplayState> _display = GlobalKey<PinDisplayState>();
  String _first = '';
  String _pin = '';
  bool _confirming = false;
  bool _mismatch = false;
  bool _busy = false;
  bool _offering = false;

  void _onDigit(String d) {
    if (_pin.length >= kPinMaxLength || _busy) {
      return;
    }
    setState(() {
      _pin += d;
      _mismatch = false;
    });
  }

  Future<void> _next() async {
    if (_pin.length < kPinMinLength || _busy) {
      return;
    }
    if (!_confirming) {
      setState(() {
        _first = _pin;
        _pin = '';
        _confirming = true;
      });
      return;
    }
    if (_pin != _first) {
      // Los dos PIN no coinciden: el mismo temblor que un PIN erróneo.
      _display.currentState?.fail(_pin.length);
      setState(() {
        _first = '';
        _pin = '';
        _confirming = false;
        _mismatch = true;
      });
      return;
    }
    setState(() => _busy = true);
    final lock = ref.read(lockControllerProvider.notifier);
    final already = ref.read(lockControllerProvider).value?.biometrics ?? false;
    final canOffer = !already && await lock.biometricsAvailable();
    if (!mounted) {
      return;
    }
    if (canOffer) {
      // Se pudo dar de alta Face ID o Touch ID con la app abierta.
      ref.invalidate(biometricKindProvider);
      // Un paso más dentro de esta misma pantalla (no es un diálogo: la
      // puerta del bloqueo vive encima del navegador y no puede abrir uno).
      setState(() {
        _busy = false;
        _offering = true;
      });
      return;
    }
    setState(() => _busy = false);
    await _finish(enableBiometrics: false);
  }

  /// Guarda el PIN y, si se aceptó, activa la huella o el rostro.
  Future<void> _finish({required bool enableBiometrics}) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    // Todo lo que hace falta después se toma antes: quien llama puede cerrar
    // esta pantalla en cuanto el PIN queda guardado.
    final lock = ref.read(lockControllerProvider.notifier);
    final reason = AppLocalizations.of(context).lockBiometricReason;
    try {
      await widget.onPinChosen(_pin);
      if (enableBiometrics) {
        // Con el PIN ya guardado: comprueba que la huella funciona y la activa.
        // Si falla o se cancela, el PIN queda igual y se puede activar luego
        // en Ajustes > Seguridad.
        await lock.setBiometrics(true, reason: reason);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _offer(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind =
        ref.watch(biometricKindProvider).value ?? BiometricKind.generic;
    final t = RegalosTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.appTitle, style: t.styles.sectionTitle),
        const SizedBox(height: 20),
        Text(
          kind.offerTitle(l10n),
          style: t.styles.screenTitle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          kind.notice(l10n),
          style: t.styles.meta,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : () => _finish(enableBiometrics: true),
          child: Text(l10n.pinBiometricOfferEnable),
        ),
        TextButton(
          onPressed: _busy ? null : () => _finish(enableBiometrics: false),
          child: Text(l10n.pinSkip),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    // Se pide ya para que el nombre esté listo cuando salga la oferta.
    ref.watch(biometricKindProvider);
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: PinBlock(
          // Elegir el PIN y la oferta de la huella son dos pasos: el segundo
          // entra con el mismo cambio de paso que las hojas.
          child: SheetSteps(
            step: _offering,
            distance: 24,
            child: _offering
                ? _offer(context)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.appTitle, style: t.styles.sectionTitle),
                      const SizedBox(height: 20),
                      // Al pasar de «crear» a «repetir» el título se cruza con un
                      // fundido corto, sin mover el teclado.
                      ValueSwitcher(
                        alignment: Alignment.center,
                        child: Text(
                          _confirming
                              ? l10n.pinConfirmTitle
                              : l10n.pinSetupTitle,
                          key: ValueKey<bool>(_confirming),
                          style: t.styles.screenTitle,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.pinSetupMessage,
                        style: t.styles.meta,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      PinDisplay(key: _display, count: _pin.length),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 24,
                        child: ValueSwitcher(
                          alignment: Alignment.topCenter,
                          child: _mismatch
                              ? Semantics(
                                  key: const ValueKey<bool>(true),
                                  liveRegion: true,
                                  child: Text(
                                    l10n.pinMismatch,
                                    style: t.styles.meta,
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey<bool>(false),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      PinPad(
                        enabled: !_busy,
                        onDigit: _onDigit,
                        onBackspace: () => setState(() {
                          if (_pin.isNotEmpty) {
                            _pin = _pin.substring(0, _pin.length - 1);
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      // Del ancho del teclado: al cambiar «Continuar» por
                      // «Guardar PIN» el botón no cambia de tamaño.
                      SizedBox(
                        width: PinPad.width,
                        child: FilledButton(
                          onPressed: _pin.length < kPinMinLength || _busy
                              ? null
                              : _next,
                          child: ValueSwitcher(
                            alignment: Alignment.center,
                            dy: 3,
                            child: Text(
                              _confirming ? l10n.pinSave : l10n.pinContinue,
                              key: ValueKey<bool>(_confirming),
                            ),
                          ),
                        ),
                      ),
                      if (widget.onSkip != null)
                        TextButton(
                          onPressed: _busy ? null : widget.onSkip,
                          child: Text(l10n.pinSkip),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
