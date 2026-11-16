import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/value_switcher.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tabler_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../application/lock_controller.dart';
import '../data/pin_vault.dart';
import 'pin_pad.dart';

/// Pantalla de bloqueo: PIN y, si está activada, huella o rostro.
class LockScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const LockScreen({super.key, this.onPinUnlocked});

  /// Se llama cuando el PIN escrito era el correcto, antes de que la puerta
  /// retire esta pantalla: así la puerta sabe que tiene que esperar a la ola
  /// de los puntos (§1+.4 de la guía de movimiento).
  final VoidCallback? onPinUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

enum _Message { none, wrong, wrongNow }

class _LockScreenState extends ConsumerState<LockScreen> {
  final GlobalKey<PinDisplayState> _display = GlobalKey<PinDisplayState>();
  String _pin = '';
  bool _busy = false;
  _Message _message = _Message.none;
  int _attemptsLeft = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Con la huella activada, el diálogo del sistema salta solo, una vez por
    // bloqueo (la marca vive en `LockController`, no aquí: en iOS esta
    // pantalla se destruye y se vuelve a crear al cerrarse el diálogo). Con
    // una espera pendiente no (el teclado, huella incluida, está desactivado
    // hasta que pase). Si se cancela o falla, solo vuelve con su botón.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final lock = ref.read(lockControllerProvider).value;
      if (lock != null &&
          lock.biometrics &&
          lock.locked &&
          _remainingWait(lock) == null &&
          ref.read(lockControllerProvider.notifier).takeAutoBiometric()) {
        unawaited(_biometric());
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration? _remainingWait(AppLockState? lock) {
    final until = lock?.waitUntil;
    if (until == null) {
      return null;
    }
    final left = until.difference(clock.now());
    return left > Duration.zero ? left : null;
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (_remainingWait(ref.read(lockControllerProvider).value) == null) {
        _ticker?.cancel();
        _ticker = null;
      }
      setState(() {});
    });
  }

  Future<void> _submit() async {
    if (_busy || _pin.length < kPinMinLength) {
      return;
    }
    setState(() => _busy = true);
    final entered = _pin.length;
    final check = await ref.read(lockControllerProvider.notifier).unlock(_pin);
    if (!mounted) {
      return;
    }
    if (check is PinWrong) {
      // El PIN erróneo tiembla y vibra fuerte; los puntos siguen llenos hasta
      // que acaba el temblor. Antes de vaciar `_pin`, para que la fila no
      // empiece a vaciarse en este mismo fotograma.
      _display.currentState?.fail(entered);
    } else if (check is PinOk) {
      // El PIN correcto late de punto en punto mientras el candado se va. Los
      // puntos siguen llenos hasta que acaba la ola.
      widget.onPinUnlocked?.call();
      _display.currentState?.succeed(entered);
    }
    setState(() {
      _busy = false;
      _pin = '';
      switch (check) {
        case PinOk():
          _message = _Message.none;
        case PinWrong(:final attemptsLeft, :final waitUntil):
          _message = waitUntil == null ? _Message.wrong : _Message.wrongNow;
          _attemptsLeft = attemptsLeft;
        case PinLockedOut():
          _message = _Message.none;
      }
    });
    _startTicker();
  }

  Future<void> _biometric() async {
    final reason = AppLocalizations.of(context).lockBiometricReason;
    await ref
        .read(lockControllerProvider.notifier)
        .unlockWithBiometrics(reason);
  }

  /// Longitud con la que se comprueba el PIN sin botón: la guardada o, con
  /// un PIN antiguo que no la guardó, el máximo.
  int _length(AppLockState? lock) => lock?.pinLength ?? kPinMaxLength;

  void _onDigit(String d) {
    final length = _length(ref.read(lockControllerProvider).value);
    if (_pin.length >= length) {
      return;
    }
    setState(() {
      _pin += d;
      _message = _Message.none;
    });
    if (_pin.length == length) {
      unawaited(_submit());
    }
  }

  String _clockText(Duration d) {
    final seconds = d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final lock = ref.watch(lockControllerProvider).value;
    final wait = _remainingWait(lock);
    if (wait != null) {
      _startTicker();
    }
    final text = wait != null
        ? l10n.lockWait(_clockText(wait))
        : switch (_message) {
            _Message.wrong => l10n.lockWrongPin(_attemptsLeft),
            _Message.wrongNow => l10n.lockWrongPinNow,
            _Message.none => null,
          };
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        // En el móvil, arriba; desde 600 dp, centrado (`PinBlock`).
        child: PinBlock(
          compactAlignment: Alignment.topCenter,
          compactPadding: const EdgeInsets.fromLTRB(24, 50, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.appTitle,
                style: t.styles.rowTitleCompact.copyWith(
                  fontWeight: FontWeight.w600,
                  color: t.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.lockEnterPin,
                style: t.styles.screenTitle.copyWith(
                  fontSize: 26,
                  height: 32 / 26,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              PinDisplay(
                key: _display,
                count: _pin.length,
                total: _length(lock),
              ),
              ConstrainedBox(
                // Mínimo, no fijo: «PIN incorrecto. Quedan 4 intentos antes de
                // tener que esperar.» salta de línea y no debe recortarse.
                constraints: const BoxConstraints(minHeight: 32),
                // El mensaje de intentos entra con un fundido de 150 ms.
                child: ValueSwitcher(
                  alignment: Alignment.topCenter,
                  child: text == null
                      ? const SizedBox.shrink(key: ValueKey<Object>('none'))
                      : Padding(
                          // La clave es la clase de mensaje, no el texto: la
                          // cuenta atrás de la espera cambia cada segundo y
                          // no debe parpadear.
                          key: ValueKey<Object>(
                            wait != null ? 'wait' : _message,
                          ),
                          padding: const EdgeInsets.only(top: 10),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              text,
                              style: t.styles.meta,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              PinPad(
                enabled: !_busy && wait == null,
                onDigit: _onDigit,
                onBackspace: () => setState(() {
                  if (_pin.isNotEmpty) {
                    _pin = _pin.substring(0, _pin.length - 1);
                  }
                }),
                onBiometric: (lock?.biometrics ?? false) ? _biometric : null,
              ),
              if (lock?.biometrics ?? false) ...[
                const SizedBox(height: 12),
                ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StrokeIcon(
                        tablerFingerprint,
                        size: 16,
                        color: t.ink,
                        strokeWidth: 1.5,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          l10n.lockBiometricHint,
                          style: t.styles.meta,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Con la longitud guardada el PIN se comprueba al completarlo y no
              // hace falta botón; con un PIN antiguo, sí.
              if (lock?.pinLength == null) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed:
                      _busy || wait != null || _pin.length < kPinMinLength
                      ? null
                      : _submit,
                  child: Text(l10n.lockUnlock),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
