import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/unlock_cascade.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../recovery/application/recovery_hold.dart';
import '../../review/application/review_providers.dart';
import '../../sync/application/replace_join_hold.dart';
import '../application/lock_controller.dart';
import '../application/lock_gate_state.dart';
import '../data/biometrics.dart';
import 'lock_screen.dart';
import 'pin_setup_screen.dart';

/// Envuelve la app y la tapa mientras haya que desbloquear.
///
/// - Sin familia (primer arranque) no hay nada que proteger: no bloquea.
/// - Con familia y sin PIN pide crearlo (se puede dejar para más tarde).
/// - Con PIN, bloquea siempre en frío y al volver de más de 30 s en segundo
///   plano.
/// - En iOS tapa la app cuando queda inactiva, para el selector de apps.
///
/// La app queda montada debajo, así que al desbloquear sigue donde estaba.
class LockGate extends ConsumerStatefulWidget {
  /// Crea la puerta.
  const LockGate({super.key, required this.child});

  /// La app.
  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _covered = false;
  ReviewVisibility? _reviewVisibility;

  /// El fundido de salida del overlay (0 a 1). En reposo vale 1.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: RegalosSprings.snapDuration,
    value: 1,
    // El fundido de 150 ms de «Quitar animaciones» no debe acortarse a un corte.
    animationBehavior: AnimationBehavior.preserve,
  );
  _OverlayKind _lastKind = _OverlayKind.none;
  Widget? _lastOverlay;

  /// El overlay que se acaba de ir y sigue pintándose mientras se desvanece.
  Widget? _leaving;
  _OverlayKind _revealKind = _OverlayKind.none;
  bool _revealReduce = false;

  /// Entre que se va el overlay y arranca el fundido (un fotograma), la
  /// animación vale 0 aunque el controlador aún no haya empezado.
  bool _pending = false;

  /// Si el PIN correcto acaba de desbloquear: el candado espera 80 ms a que se
  /// vea el primer latido de los puntos antes de irse (§1+.4).
  bool _pinUnlocked = false;
  Timer? _revealTimer;

  /// Red de seguridad: si el fundido no termina en este tiempo, se fuerza el
  /// estado limpio (sin velo gris).
  Timer? _safetyTimer;

  /// Lo avisa la pantalla de bloqueo al acertar el PIN.
  void _onPinUnlocked() => _pinUnlocked = true;

  late final ValueNotifier<bool> _hold = ref.read(recoveryHoldProvider);

  /// «Sustituir y unirme» en marcha: sin familia un momento, pero bloqueada.
  late final ValueNotifier<bool> _replacing = ref.read(replaceJoinHoldProvider);

  /// La recuperación con el código retiene o suelta la entrada: se repinta.
  void _onDeferralChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hold.addListener(_onDeferralChanged);
    _replacing.addListener(_onDeferralChanged);
    if (isStoreReviewEnabled) {
      _reviewVisibility = ref.read(reviewVisibilityProvider);
    }
  }

  @override
  void dispose() {
    _reviewVisibility?.isLockGateClear = false;
    _hold.removeListener(_onDeferralChanged);
    _replacing.removeListener(_onDeferralChanged);
    WidgetsBinding.instance.removeObserver(this);
    _revealTimer?.cancel();
    _safetyTimer?.cancel();
    _reveal.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(lockControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        lock.appPaused();
        // Un aviso con el nombre de un regalo no debe sobrevivir a la salida
        // y pintarse luego encima de la pantalla de bloqueo.
        _clearSnackBars();
      case AppLifecycleState.resumed:
        lock.appResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
    // Se tapa al salir, no al volver: así el último fotograma que pinta el
    // sistema (selector de apps, o el primero al regresar) es la cubierta y
    // nunca la lista. Android e iOS; en la web y el escritorio, no.
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      // En Android, `inactive` también llega con la vista previa de una
      // captura, la persiana de notificaciones o un diálogo del sistema: no
      // se tapa por eso. El selector de apps ya no enseña miniatura
      // (`setRecentsScreenshotEnabled`/`FLAG_SECURE`, MainActivity). En iOS
      // `inactive` es justo el selector de apps: ahí sí.
      final covered = defaultTargetPlatform == TargetPlatform.android
          ? state == AppLifecycleState.paused ||
                state == AppLifecycleState.hidden ||
                state == AppLifecycleState.detached
          : state != AppLifecycleState.resumed;
      if (covered != _covered) {
        setState(() => _covered = covered);
      }
    }
  }

  /// Descarta los avisos en cola y quita el actual al momento, sin su
  /// animación de salida (que se vería sobre la pantalla de bloqueo).
  void _clearSnackBars() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..removeCurrentSnackBar();
  }

  @override
  Widget build(BuildContext context) {
    // Al pasar a bloqueado, fuera los avisos: se retiran antes de que el
    // `Scaffold` de la pantalla de bloqueo se registre y los pinte encima.
    ref.listen(lockControllerProvider, (previous, next) {
      if (next.value?.locked == true && previous?.value?.locked != true) {
        _clearSnackBars();
        // Cada bloqueo vuelve a mirar si hay Face ID o Touch ID (se pudo dar de
        // alta con la app abierta). La puerta sigue montada entre bloqueos; la
        // pantalla de bloqueo no.
        refreshBiometricKind(ref, () => mounted);
      }
    });
    final family = ref.watch(familyControllerProvider);
    final lockAsync = ref.watch(lockControllerProvider);
    final content = lockGateContent(
      family: family,
      lock: lockAsync,
      recoveryHeld: _hold.value,
      replacingFamily: _replacing.value,
    );
    Widget? overlay = switch (content) {
      LockGateContent.none => null,
      LockGateContent.loading => const _Cover(named: false),
      LockGateContent.error => _RetryCover(
        onRetry: () => ref.invalidate(lockControllerProvider),
      ),
      LockGateContent.setup => PinSetupScreen(
        onPinChosen: ref.read(lockControllerProvider.notifier).setPin,
        onSkip: ref.read(lockControllerProvider.notifier).skipSetup,
      ),
      LockGateContent.locked => LockScreen(onPinUnlocked: _onPinUnlocked),
    };
    var hideApp = content != LockGateContent.none;
    if (_covered) {
      overlay = const _Cover();
      hideApp = true;
    }
    // La cubierta de privacidad no se anima nunca al entrar (norma 7): el
    // selector de apps hace su captura enseguida. Lo único que se anima es
    // lo que se va.
    final kind = switch (overlay) {
      null => _OverlayKind.none,
      _Cover() || _RetryCover() => _OverlayKind.cover,
      _ => _OverlayKind.lock,
    };
    if (kind == _OverlayKind.none) {
      if (_lastKind != _OverlayKind.none && _leaving == null) {
        // Acaba de irse un overlay: lo seguimos pintando mientras se va.
        _leaving = _lastOverlay;
        _revealKind = _lastKind;
        _pending = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _startReveal());
        // Red de seguridad: si el fundido no termina en ~1 s, se fuerza el
        // estado limpio para no dejar un velo gris sobre la app.
        _safetyTimer?.cancel();
        _safetyTimer = Timer(const Duration(seconds: 1), _forceCleanReveal);
      }
    } else if (_leaving != null || !_reveal.isCompleted) {
      // Volvió a taparse a mitad del fundido: sin animación, al momento.
      _leaving = null;
      _pending = false;
      _pinUnlocked = false;
      _revealTimer?.cancel();
      _revealTimer = null;
      _safetyTimer?.cancel();
      _safetyTimer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resetReveal());
    }
    _lastKind = kind;
    _lastOverlay = overlay ?? _lastOverlay;

    final shown = overlay ?? _leaving;
    final reviewVisibility = _reviewVisibility;
    if (reviewVisibility != null) {
      // The overlay can still be on screen after the PIN state is unlocked.
      reviewVisibility.isLockGateClear = shown == null;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: hideApp,
          child: TickerMode(
            enabled: !hideApp,
            child: _RevealLayer(
              animation: _reveal,
              kind: _revealKind,
              reduce: _revealReduce,
              pending: _pending,
              role: _RevealRole.app,
              child: widget.child,
            ),
          ),
        ),
        if (shown != null)
          _RevealLayer(
            animation: _reveal,
            kind: _revealKind,
            reduce: _revealReduce,
            pending: _pending,
            role: overlay == null ? _RevealRole.leaving : _RevealRole.steady,
            child: shown,
          ),
      ],
    );
  }

  void _startReveal() {
    if (!mounted || _leaving == null) {
      // Si por algún camino se quedó `_pending` a true sin fundido, se limpia.
      if (_leaving == null) {
        _pending = false;
        _safetyTimer?.cancel();
        _safetyTimer = null;
      }
      return;
    }
    final reduce = RegalosMotion.of(context).reduce;
    _revealReduce = reduce;
    final afterPin =
        _pinUnlocked && !reduce && _revealKind == _OverlayKind.lock;
    _pinUnlocked = false;
    if (afterPin) {
      // El candado se va 80 ms después, para que se vea el primer latido de
      // los puntos; no espera al resto de la ola. Hasta entonces la app
      // sigue como si el fundido no hubiera empezado (`_pending`).
      _revealTimer?.cancel();
      _revealTimer = Timer(const Duration(milliseconds: 80), _runReveal);
      return;
    }
    _runReveal();
  }

  void _runReveal() {
    if (!mounted || _leaving == null) {
      _pending = false;
      _revealTimer?.cancel();
      _revealTimer = null;
      return;
    }
    final reduce = _revealReduce;
    // El bloqueo se funde y crece 375 ms; la cubierta, solo un fundido de 150.
    _reveal.duration = reduce || _revealKind == _OverlayKind.cover
        ? RegalosMotion.fade
        : RegalosSprings.snapDuration;
    _reveal.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted) {
        return;
      }
      if (_reveal.isCompleted) {
        setState(() => _leaving = null);
        _safetyTimer?.cancel();
        _safetyTimer = null;
      } else {
        // Cancelado (TickerFuture cancelado, p. ej. stop()): el `whenComplete`
        // normal no se llama. Se fuerza el estado limpio para no dejar velo.
        _reveal.stop();
        _reveal.value = 1;
        setState(() {
          _leaving = null;
          _pending = false;
        });
        _revealTimer?.cancel();
        _revealTimer = null;
        _safetyTimer?.cancel();
        _safetyTimer = null;
      }
    });
    setState(() => _pending = false);
    // Debajo, la app no aparece entera: los bloques de la pantalla que se ve
    // entran uno tras otro y la cuenta atrás rueda desde vacío. Solo al
    // desbloquear desde la pantalla de bloqueo (no al crear el PIN ni al
    // quitar la cubierta de privacidad) y sin «Reducir movimiento».
    if (!reduce && _leaving is LockScreen) {
      UnlockCascade.play();
    }
  }

  void _forceCleanReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    if (!mounted) {
      _leaving = null;
      _pending = false;
      _pinUnlocked = false;
      _safetyTimer = null;
      return;
    }
    // Si ya terminó limpio, no hace nada.
    if (_leaving == null && !_pending && _reveal.isCompleted) {
      _safetyTimer = null;
      return;
    }
    _reveal.stop();
    _reveal.value = 1;
    setState(() {
      _leaving = null;
      _pending = false;
      _pinUnlocked = false;
    });
    _safetyTimer = null;
  }

  void _resetReveal() {
    if (!mounted) {
      return;
    }
    _reveal
      ..stop()
      ..value = 1;
    _safetyTimer?.cancel();
    _safetyTimer = null;
  }
}

/// Qué tapaba la app.
enum _OverlayKind { none, cover, lock }

/// Qué papel juega una capa en el desbloqueo.
enum _RevealRole { app, steady, leaving }

/// Envuelve la app o lo que la tapa para animar el desbloqueo (guía de
/// movimiento, §1.4). El árbol de debajo es el mismo
/// cuando no hay animación, así que el estado no se pierde.
///
/// - Tapa de bloqueo que se va: se funde (`Interval(0, 0.6)`) y crece de 1 a
///   1,06 con `snap`.
/// - La app: de opacidad 0,4 a 1 con `snap`, sin escalar (nada retrocede).
/// - Cubierta de privacidad que se va, o «Reducir movimiento»: solo fundido.
class _RevealLayer extends StatelessWidget {
  const _RevealLayer({
    required this.animation,
    required this.kind,
    required this.reduce,
    required this.pending,
    required this.role,
    required this.child,
  });

  final Animation<double> animation;
  final _OverlayKind kind;
  final bool reduce;

  /// El fundido aún no ha arrancado: vale como si estuviera en 0.
  final bool pending;
  final _RevealRole role;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final v = pending ? 0.0 : animation.value.clamp(0.0, 1.0);
      var scale = 1.0;
      var opacity = 1.0;
      final plain = reduce || kind != _OverlayKind.lock;
      switch (role) {
        case _RevealRole.steady:
          break;
        case _RevealRole.leaving:
          if (plain) {
            opacity = 1 - v;
          } else {
            scale = 1 + 0.06 * RegalosCurves.snap.transform(v);
            opacity = 1 - const Interval(0, 0.6).transform(v);
          }
        case _RevealRole.app:
          if (kind == _OverlayKind.lock) {
            if (reduce) {
              opacity = v;
            } else {
              // La app no se encoge ni retrocede: solo se aclara.
              opacity = (0.4 + 0.6 * RegalosCurves.snap.transform(v)).clamp(
                0.0,
                1.0,
              );
            }
          }
      }
      return IgnorePointer(
        ignoring: role == _RevealRole.leaving,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        ),
      );
    },
  );
}

/// Pantalla en blanco, con el nombre de la app o sin él: no enseña nada de la
/// lista.
///
/// Con [named] (la cubierta de privacidad, que ve el selector de apps) lleva
/// el nombre; sin él (mientras carga el estado al arrancar) es solo el fondo.
class _Cover extends StatelessWidget {
  const _Cover({this.named = true});

  /// Si pinta el nombre de la app.
  final bool named;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    // `Material` y no `ColoredBox`: la cubierta vive encima del navegador, sin
    // ningún `DefaultTextStyle` por encima, y el texto salía con el subrayado
    // doble amarillo de Flutter mientras se fundía (primer arranque).
    return Material(
      type: MaterialType.canvas,
      color: t.bg,
      child: named
          ? Center(
              child: Text(
                AppLocalizations.of(context).appTitle,
                style: t.styles.screenTitle,
                textDirection: Directionality.of(context),
              ),
            )
          : null,
    );
  }
}

/// Tapa la app cuando no se puede leer el estado del bloqueo, con un botón
/// para repetir la lectura.
class _RetryCover extends StatelessWidget {
  const _RetryCover({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Material(
      color: t.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.appTitle, style: t.styles.screenTitle),
              const SizedBox(height: 12),
              Text(
                l10n.lockLoadError,
                style: t.styles.meta,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: Text(l10n.lockRetry)),
            ],
          ),
        ),
      ),
    );
  }
}
