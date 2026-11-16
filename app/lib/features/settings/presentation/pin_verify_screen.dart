import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../core/motion/value_switcher.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../lock/data/pin_vault.dart';
import '../../lock/presentation/pin_pad.dart';

/// Pide el PIN actual antes de quitarlo o cambiarlo.
///
/// [onSubmit] comprueba el PIN. Con `PinOk` la pantalla se cierra con `true`;
/// si no, avisa de cuántos intentos quedan o de cuánto hay que esperar.
class PinVerifyScreen extends StatefulWidget {
  /// Crea la pantalla.
  const PinVerifyScreen({
    super.key,
    required this.title,
    required this.message,
    required this.onSubmit,
  });

  /// Título («Quitar el PIN»).
  final String title;

  /// Explicación bajo el título.
  final String message;

  /// Comprueba el PIN escrito.
  final Future<PinCheck> Function(String pin) onSubmit;

  @override
  State<PinVerifyScreen> createState() => _PinVerifyScreenState();
}

class _PinVerifyScreenState extends State<PinVerifyScreen> {
  final GlobalKey<PinDisplayState> _display = GlobalKey<PinDisplayState>();
  String _pin = '';
  bool _busy = false;
  String? _error;

  String _clockText(Duration d) {
    final seconds = d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _submit() async {
    if (_busy || _pin.length < kPinMinLength) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final entered = _pin.length;
    final check = await widget.onSubmit(_pin);
    if (!mounted) {
      return;
    }
    if (check is PinWrong) {
      // Un PIN erróneo tiembla y vibra, como en la pantalla de bloqueo.
      _display.currentState?.fail(entered);
    }
    switch (check) {
      case PinOk():
        Navigator.of(context).pop(true);
      case PinWrong(:final attemptsLeft, :final waitUntil):
        setState(() {
          _busy = false;
          _pin = '';
          _error = waitUntil == null
              ? l10n.lockWrongPin(attemptsLeft)
              : l10n.lockWrongPinNow;
        });
      case PinLockedOut(:final waitUntil):
        setState(() {
          _busy = false;
          _pin = '';
          _error = l10n.lockWait(_clockText(waitUntil.difference(clock.now())));
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop(false)),
      ),
      body: SafeArea(
        child: PinBlock(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  widget.title,
                  style: t.styles.screenTitle,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.message,
                style: t.styles.meta,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              PinDisplay(key: _display, count: _pin.length),
              const SizedBox(height: 14),
              ConstrainedBox(
                // Mínimo, no fijo: el mensaje puede saltar de línea.
                constraints: const BoxConstraints(minHeight: 40),
                // El mensaje entra con un fundido de 150 ms.
                child: ValueSwitcher(
                  alignment: Alignment.topCenter,
                  child: _error == null
                      ? const SizedBox.shrink(key: ValueKey<Object>('none'))
                      : Semantics(
                          key: const ValueKey<Object>('error'),
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: t.styles.meta,
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              PinPad(
                enabled: !_busy,
                onDigit: (d) {
                  if (_pin.length < kPinMaxLength) {
                    setState(() {
                      _pin += d;
                      _error = null;
                    });
                  }
                },
                onBackspace: () => setState(() {
                  if (_pin.isNotEmpty) {
                    _pin = _pin.substring(0, _pin.length - 1);
                  }
                }),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy || _pin.length < kPinMinLength
                    ? null
                    : () => unawaited(_submit()),
                child: Text(l10n.pinContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
