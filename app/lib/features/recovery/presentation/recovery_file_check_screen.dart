import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/motion/shake.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/platform/secure_screen.dart';
import '../../../l10n/app_localizations.dart';
import '../../sync/application/recovery_file_flow.dart';
import 'recovery_file_parts.dart';
import 'recovery_file_problem.dart';
import 'recovery_parts.dart';

enum _Stage { pick, password, working, done }

/// «Comprobar un fichero» (ADR 0008): se elige el fichero de recuperación que
/// se guardó, se escribe su contraseña si la lleva y, si abre el código
/// vigente de este móvil, el código queda comprobado. No exporta ni guarda
/// nada.
class RecoveryFileCheckScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const RecoveryFileCheckScreen({super.key});

  @override
  ConsumerState<RecoveryFileCheckScreen> createState() =>
      _RecoveryFileCheckScreenState();
}

class _RecoveryFileCheckScreenState
    extends ConsumerState<RecoveryFileCheckScreen> {
  final TextEditingController _password = TextEditingController();
  final GlobalKey<ShakeXState> _shake = GlobalKey<ShakeXState>();

  late final RecoveryFileController _flow;

  _Stage _stage = _Stage.pick;
  RecoveryFileCheck? _check;
  RecoveryFileProblem? _problem;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    unawaited(enableSecureScreen());
    // Se guarda ya: en dispose, ref ya no vale.
    _flow = ref.read(recoveryFileProvider.notifier);
  }

  @override
  void dispose() {
    unawaited(disableSecureScreen());
    // Fuera del fotograma en que se desmonta: el estado del flujo se repinta.
    final flow = _flow;
    scheduleMicrotask(() {
      try {
        flow.cancel();
      } on Object {
        // El contenedor ya se cerró con la app.
      }
    });
    _check = null;
    _password.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _problem = null;
    });
    try {
      final check = await _flow.pickForCheck();
      if (!mounted || check == null) return;
      _check = check;
      if (check.needsPassword) {
        _password.clear();
        setState(() => _stage = _Stage.password);
      } else {
        await _confirm();
      }
    } on Object catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _confirm() async {
    final check = _check;
    if (check == null) return;
    final withPassword = check.needsPassword;
    setState(() {
      _stage = _Stage.working;
      _problem = null;
    });
    try {
      await _flow.confirmCheck(
        check,
        password: withPassword ? _password.text : null,
      );
      if (!mounted) return;
      ref.read(hapticsProvider).success();
      _password.clear();
      _check = null;
      setState(() => _stage = _Stage.done);
    } on Object catch (e) {
      if (!mounted) return;
      final problem = recoveryFileProblemOf(e);
      if (problem == null) {
        // Cancelada: se vuelve a la contraseña sin decir nada.
        setState(() => _stage = _Stage.password);
        return;
      }
      _fail(e, backToPassword: problem.isWrongPassword);
    }
  }

  void _fail(Object error, {bool backToPassword = false}) {
    final problem = recoveryFileProblemOf(error);
    if (!mounted || problem == null) return;
    ref.read(hapticsProvider).error();
    setState(() {
      _problem = problem;
      _stage = backToPassword ? _Stage.password : _Stage.pick;
    });
    if (backToPassword) _shake.currentState?.shake();
  }

  void _otherFile() {
    _password.clear();
    _check = null;
    setState(() {
      _stage = _Stage.pick;
      _problem = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final deriving = ref.watch(
      recoveryFileProvider.select(
        (s) => s.activity == RecoveryFileActivity.deriving,
      ),
    );

    final Widget body;
    Widget? footer;
    switch (_stage) {
      case _Stage.pick:
        body = StaggerScope(
          maxItems: 2,
          child: StaggerItem(
            index: 0,
            child: RecoveryFileStepBody(
              title: l10n.recoveryCheckFileTitle,
              body: l10n.recoveryCheckFileBody,
              problem: _problem,
            ),
          ),
        );
        footer = FilledButton(
          onPressed: _picking ? null : _pick,
          child: Text(l10n.recoveryFilePick),
        );
      case _Stage.password:
        body = AutofillGroup(
          child: RecoveryFileStepBody(
            title: l10n.recoveryFilePasswordTitle,
            body: l10n.recoveryFilePasswordOpenBody,
            problem: _problem,
            field: ShakeX(
              key: _shake,
              child: RecoveryPasswordField(
                controller: _password,
                label: l10n.recoveryFilePassword,
                newPassword: false,
                autofocus: true,
                error: _problem?.isWrongPassword ?? false,
                onChanged: () {
                  if (_problem != null) setState(() => _problem = null);
                  setState(() {});
                },
                onSubmitted: _password.text.isEmpty ? null : _confirm,
              ),
            ),
          ),
        );
        footer = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _password.text.isEmpty ? null : _confirm,
              child: Text(l10n.recoveryFileOpen),
            ),
            TextButton(
              onPressed: _otherFile,
              child: Text(l10n.recoverFileOther),
            ),
          ],
        );
      case _Stage.working:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RecoveryHeading(title: l10n.recoveryCheckFileTitle),
            const SizedBox(height: 16),
            RecoveryFade(
              stateKey: deriving,
              child: deriving
                  ? RecoveryDerivingCard(
                      title: l10n.recoveryFileDerivingTitle,
                      body: l10n.recoveryFileDerivingBody,
                      onCancel: _flow.cancel,
                    )
                  : RecoveryWorkingCard(
                      title: l10n.recoveryFileCheckingTitle,
                      body: l10n.recoveryFileCheckingBody,
                    ),
            ),
          ],
        );
      case _Stage.done:
        body = StaggerScope(
          maxItems: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const StaggerItem(
                index: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: RecoverySuccessMark(size: 56),
                ),
              ),
              const SizedBox(height: 16),
              StaggerItem(
                index: 1,
                child: Semantics(
                  liveRegion: true,
                  child: RecoveryHeading(
                    title: l10n.recoveryCheckFileOkTitle,
                    body: l10n.recoveryCheckFileOkBody,
                  ),
                ),
              ),
            ],
          ),
        );
        footer = FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.recoveryDoneButton),
        );
    }

    return RecoveryFlowScaffold(
      onBack: _stage == _Stage.working && !deriving
          ? null
          : () => Navigator.of(context).pop(_stage == _Stage.done),
      footer: footer,
      child: RecoveryFade(stateKey: _stage, child: body),
    );
  }
}
