import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/motion/shared_axis_switcher.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/platform/secure_screen.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/verify_owner.dart';
import '../../sync/application/recovery_providers.dart';
import 'recovery_parts.dart';
import 'recovery_problem.dart';
import 'recovery_words_view.dart';

enum _Step { intro, words, check, done }

/// Crear (o cambiar) el código de recuperación, a pantalla completa:
/// explicación, autenticación local, las 24 palabras, una comprobación con
/// tres de ellas y, por fin, el estado real de la copia.
///
/// Las palabras se entregan una sola vez: viven solo en el estado de esta
/// pantalla y se descartan al salir. «Preparado» solo se dice cuando
/// `recoveryStatusProvider` lo confirma.
class RecoveryCreateScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla. [rotate] cambia el código que ya existe. [random] se da
  /// en las pruebas, para saber qué tres palabras se piden.
  const RecoveryCreateScreen({super.key, this.rotate = false, this.random});

  /// Si se cambia el código existente en vez de crear el primero.
  final bool rotate;

  /// De dónde salen las tres palabras de la comprobación.
  final math.Random? random;

  @override
  ConsumerState<RecoveryCreateScreen> createState() =>
      _RecoveryCreateScreenState();
}

class _RecoveryCreateScreenState extends ConsumerState<RecoveryCreateScreen> {
  final List<TextEditingController> _answers = [
    for (var i = 0; i < 3; i++) TextEditingController(),
  ];
  _Step _step = _Step.intro;
  RecoveryCodeDisplay? _display;
  List<int> _asked = const [];
  bool _busy = false;
  bool _showQr = false;
  bool _wrong = false;
  RecoveryProblem? _problem;

  /// Si la copia cifrada aún no está confirmada en el servidor: no hay
  /// palabras que enseñar todavía, solo un progreso y «Reintentar».
  bool _pending = false;

  /// Si hay palabras guardadas de una creación cortada, sin enseñar todavía:
  /// solo se consumen después de pasar el PIN o la huella.
  bool _hasDisplay = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reclaim());
  }

  /// Si el bloqueo de capturas está puesto (solo mientras se ven las palabras
  /// o el QR).
  bool _secured = false;

  Future<void> _secure(bool on) async {
    if (_secured == on) {
      return;
    }
    _secured = on;
    await (on ? enableSecureScreen() : disableSecureScreen());
  }

  @override
  void dispose() {
    for (final controller in _answers) {
      controller.dispose();
    }
    _display = null;
    if (_secured) {
      _secured = false;
      unawaited(disableSecureScreen());
    }
    super.dispose();
  }

  /// Si una creación o un cambio anterior se cortó antes de enseñar las
  /// palabras, se avisa (sin consumirlas: eso va tras el PIN o la huella).
  Future<void> _reclaim() async {
    try {
      final notifier = ref.read(recoveryApplicationProvider.notifier);
      final has = await notifier.hasCodeDisplay();
      if (!mounted || _step != _Step.intro) {
        return;
      }
      if (has) {
        setState(() => _hasDisplay = true);
      } else if (ref.read(recoveryStatusProvider).readiness ==
          RecoveryReadiness.updatePending) {
        // Una creación anterior sigue a medias: no se deja la pantalla vacía.
        setState(() => _pending = true);
      }
    } on Object {
      // Sin nada que recuperar: se empieza por el principio.
    }
  }

  /// Enseña las palabras, con el bloqueo de capturas ya puesto: se espera al
  /// canal antes de pintar el primer fotograma con ellas.
  Future<void> _show(RecoveryCodeDisplay display) async {
    await _secure(true);
    if (!mounted) {
      return;
    }
    final random = widget.random ?? math.Random.secure();
    final numbers = <int>{};
    while (numbers.length < 3) {
      numbers.add(random.nextInt(display.words.length) + 1);
    }
    setState(() {
      _display = display;
      _asked = numbers.toList()..sort();
      _go(_Step.words);
    });
  }

  void _go(_Step step) => _step = step;

  /// Reintenta lo que quedó a medias y, si ya está confirmado, recupera las
  /// palabras que se guardaron para enseñarlas una vez.
  Future<void> _resumePending() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    final notifier = ref.read(recoveryApplicationProvider.notifier);
    try {
      await notifier.retry();
    } on RecoveryApplicationException catch (e) {
      if (mounted) {
        final problem = recoveryProblemOfException(e);
        setState(() {
          _busy = false;
          _problem = problem == RecoveryProblem.notReady ? null : problem;
        });
      }
      return;
    } on Object {
      // Se mira igualmente si ya hay palabras.
    }
    bool has;
    try {
      has = await notifier.hasCodeDisplay();
    } on Object {
      has = false;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (has) {
        // Ya hay palabras: se enseñarán tras el PIN o la huella.
        _hasDisplay = true;
        _pending = false;
      }
    });
  }

  Future<void> _start() async {
    if (_busy) {
      return;
    }
    if (_pending) {
      await _resumePending();
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final allowed = await verifyOwner(
        context,
        ref,
        title: l10n.recoveryAuthTitle,
        message: l10n.recoveryAuthMessage,
        biometricReason: l10n.recoveryAuthBiometric,
      );
      if (!allowed || !mounted) {
        if (mounted) {
          setState(() => _busy = false);
        }
        return;
      }
      final notifier = ref.read(recoveryApplicationProvider.notifier);
      RecoveryCodeDisplay? display;
      if (_hasDisplay) {
        display = await notifier.takeCreatedCode();
        _hasDisplay = display != null;
      }
      display ??= widget.rotate
          ? await notifier.rotateCode()
          : await notifier.createCode();
      if (!mounted) {
        return;
      }
      await _show(display);
      if (mounted) {
        setState(() => _busy = false);
      }
    } on RecoveryApplicationException catch (e) {
      if (mounted) {
        final problem = recoveryProblemOfException(e);
        setState(() {
          _busy = false;
          // La copia aún no está lista: se enseña el progreso, no las palabras.
          _pending = problem == RecoveryProblem.notReady;
          _problem = _pending ? null : problem;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = RecoveryProblem.other;
        });
      }
    }
  }

  Future<void> _check() async {
    if (_busy) return;
    final display = _display;
    if (display == null) {
      return;
    }
    var ok = true;
    for (var i = 0; i < _asked.length; i++) {
      final typed = _answers[i].text.trim().toLowerCase();
      if (typed != display.words[_asked[i] - 1]) {
        ok = false;
      }
    }
    if (!ok) {
      ref.read(hapticsProvider).error();
      setState(() => _wrong = true);
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await ref
          .read(recoveryApplicationProvider.notifier)
          .confirmCreatedCode(display);
    } on RecoveryApplicationException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = recoveryProblemOfException(e);
        });
      }
      return;
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = RecoveryProblem.other;
        });
      }
      return;
    }
    if (!mounted) return;
    ref.read(hapticsProvider).success();
    setState(() {
      _busy = false;
      _wrong = false;
      _showQr = false;
      _go(_Step.done);
      // Las palabras ya no hacen falta: se sueltan.
      _display = null;
    });
  }

  Future<void> _leave() async {
    final l10n = AppLocalizations.of(context);
    final leave = await showRegalosConfirm(
      context,
      title: l10n.recoveryLeaveTitle,
      body: l10n.recoveryLeaveBody,
      confirmLabel: l10n.recoveryLeaveConfirm,
      cancelLabel: l10n.recoveryLeaveStay,
    );
    if (leave && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _backToWords() async {
    await _secure(true);
    if (mounted) {
      setState(() => _go(_Step.words));
    }
  }

  void _back() {
    switch (_step) {
      case _Step.intro || _Step.done:
        Navigator.of(context).pop();
      case _Step.words:
        unawaited(_leave());
      case _Step.check:
        unawaited(_backToWords());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    ref.listen<RecoveryStatus>(recoveryStatusProvider, (previous, next) {
      if (_pending &&
          _step == _Step.intro &&
          (next.readiness == RecoveryReadiness.prepared ||
              next.readiness == RecoveryReadiness.confirmationPending)) {
        unawaited(_resumePending());
      }
    });
    final status = ref.watch(recoveryStatusProvider);
    final isDone = _step == _Step.done;
    final prepared = status.readiness == RecoveryReadiness.prepared;
    final attention = status.readiness == RecoveryReadiness.needsAttention;

    final Widget body;
    final Widget footer;
    switch (_step) {
      case _Step.intro:
        body = _Intro(
          rotate: widget.rotate,
          problem: _problem,
          pending: _pending,
        );
        footer = FilledButton(
          onPressed: _busy ? null : _start,
          child: Text(
            _busy
                ? l10n.recoveryMaking
                : _pending
                ? l10n.recoveryRetry
                : l10n.recoveryContinue,
          ),
        );
      case _Step.words:
        final display = _display;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RecoveryHeading(
              title: l10n.recoveryWordsTitle,
              body: l10n.recoveryWordsBody,
            ),
            const SizedBox(height: 16),
            if (display != null)
              RecoveryFade(
                stateKey: _showQr,
                child: RecoveryWordsView(
                  words: display.words,
                  qrText: display.qrText,
                  showQr: _showQr,
                ),
              ),
            const SizedBox(height: 16),
            WarningBox(
              // Android bloquea las capturas mientras se ven; iPhone no puede,
              // y entonces el aviso lo dice.
              defaultTargetPlatform == TargetPlatform.android
                  ? l10n.recoveryWordsWarn
                  : '${l10n.recoveryWordsWarn} ${l10n.recoveryWordsWarnNoBlock}',
            ),
          ],
        );
        footer = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: () => setState(() {
                for (final c in _answers) {
                  c.clear();
                }
                _wrong = false;
                _go(_Step.check);
                unawaited(_secure(false));
              }),
              child: Text(l10n.recoveryWordsSaved),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => setState(() => _showQr = !_showQr),
              child: Text(
                _showQr ? l10n.recoveryShowWords : l10n.recoveryShowQr,
              ),
            ),
          ],
        );
      case _Step.check:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RecoveryHeading(
              title: l10n.recoveryCheckTitle,
              body: l10n.recoveryCheckBody(_asked[0], _asked[1], _asked[2]),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < 3; i++) ...[
              TextField(
                controller: _answers[i],
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: i == 2
                    ? TextInputAction.done
                    : TextInputAction.next,
                onChanged: (_) {
                  if (_wrong) {
                    setState(() => _wrong = false);
                  }
                },
                onSubmitted: (_) => i == 2 ? _check() : null,
                decoration: InputDecoration(
                  labelText: l10n.recoveryCheckField(_asked[i]),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_wrong)
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.recoveryCheckWrong,
                  style: t.styles.meta.copyWith(color: t.danger),
                ),
              ),
            if (_problem != null)
              Text(
                recoveryProblemTitle(l10n, _problem!),
                style: t.styles.meta.copyWith(color: t.danger),
              ),
          ],
        );
        footer = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _busy ? null : _check,
              child: Text(l10n.recoveryCheckButton),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => unawaited(_backToWords()),
              child: Text(l10n.recoveryCheckBack),
            ),
          ],
        );
      case _Step.done:
        body = _Done(status: status);
        footer = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (attention)
              FilledButton(
                onPressed: () => unawaited(
                  ref
                      .read(recoveryApplicationProvider.notifier)
                      .retry()
                      .catchError((Object _) {}),
                ),
                child: Text(l10n.recoveryRetry),
              )
            else if (prepared)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.recoveryDoneButton),
              )
            else
              const SizedBox.shrink(),
            if (!prepared)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.recoveryCloseLater),
              ),
          ],
        );
    }

    return PopScope(
      canPop: _step == _Step.intro || isDone,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _back();
        }
      },
      child: RecoveryFlowScaffold(
        onBack: _back,
        step: _step.index + 1,
        steps: _Step.values.length,
        footer: footer,
        child: SharedAxisSwitcher(index: _step.index, child: body),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({
    required this.rotate,
    required this.problem,
    required this.pending,
  });

  final bool rotate;
  final RecoveryProblem? problem;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StaggerScope(
      maxItems: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StaggerItem(
            index: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: RecoveryBadge(icon: SettingsIcons.key),
            ),
          ),
          const SizedBox(height: 16),
          StaggerItem(
            index: 1,
            child: RecoveryHeading(
              title: rotate
                  ? l10n.recoveryRotateTitle
                  : l10n.recoveryIntroTitle,
              body: rotate ? l10n.recoveryRotateBody : l10n.recoveryIntroBody,
            ),
          ),
          const SizedBox(height: 8),
          StaggerItem(
            index: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RecoveryPoint(l10n.recoveryPoint1),
                RecoveryPoint(l10n.recoveryPoint2),
                RecoveryPoint(l10n.recoveryPoint3),
              ],
            ),
          ),
          if (pending) ...[
            const SizedBox(height: 20),
            Semantics(
              liveRegion: true,
              child: RecoveryCard(
                leading: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(child: RecoverySpinner(size: 24)),
                ),
                title: l10n.recoveryPendingTitle,
                body: l10n.recoveryPendingBody,
              ),
            ),
          ],
          if (problem != null) ...[
            const SizedBox(height: 20),
            Semantics(
              liveRegion: true,
              child: RecoveryCard(
                title: recoveryProblemTitle(l10n, problem!),
                body: recoveryProblemBody(l10n, problem!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.status});

  final RecoveryStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prepared = status.readiness == RecoveryReadiness.prepared;
    final attention = status.readiness == RecoveryReadiness.needsAttention;
    final Widget lead = prepared
        ? const RecoverySuccessMark(size: 56)
        : attention
        ? RecoveryBadge(icon: SettingsIcons.refresh, size: 56)
        : const SizedBox(
            width: 56,
            height: 56,
            child: Center(child: RecoverySpinner(size: 28)),
          );
    final problem = attention ? recoveryProblemOf(status.cause) : null;
    final title = prepared
        ? l10n.recoveryDonePreparedTitle
        : attention
        ? l10n.recoveryAttentionTitle
        : l10n.recoveryPendingTitle;
    final body = prepared
        ? l10n.recoveryDonePreparedBody
        : attention
        ? '${recoveryProblemTitle(l10n, problem!)}. ${recoveryProblemBody(l10n, problem)}'
        : l10n.recoveryDonePendingBody;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(alignment: Alignment.centerLeft, child: lead),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: RecoveryFade(
            stateKey: status.readiness,
            child: RecoveryHeading(title: title, body: body),
          ),
        ),
      ],
    );
  }
}
