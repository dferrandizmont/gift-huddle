import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/motion/unfold_section.dart';
import '../../../core/platform/secure_screen.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../sync/application/recovery_file_flow.dart';
import '../../sync/application/recovery_providers.dart';
import 'recovery_file_parts.dart';
import 'recovery_file_problem.dart';
import 'recovery_parts.dart';

/// «Guardar en un fichero» (ADR 0008): se abre desde la pantalla de las
/// palabras, con el código de esa entrega ([display]). Explica qué es el
/// fichero, deja protegerlo con una contraseña (opcional, desactivada por
/// defecto) y lo guarda con el selector del sistema o lo comparte.
///
/// Guardar con el selector y releer el destino comprueba el código: la pantalla
/// lo enseña y se puede guardar otra copia mientras siga abierta. Al cerrar
/// devuelve `true` si el código quedó comprobado. Nada de lo escrito sale de
/// esta pantalla y el fichero sellado se suelta al cerrarla.
class RecoveryFileSaveScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const RecoveryFileSaveScreen({super.key, required this.display});

  /// El código que enseñó la pantalla de las palabras.
  final RecoveryCodeDisplay display;

  @override
  ConsumerState<RecoveryFileSaveScreen> createState() =>
      _RecoveryFileSaveScreenState();
}

class _RecoveryFileSaveScreenState
    extends ConsumerState<RecoveryFileSaveScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  final GlobalKey _shareKey = GlobalKey();

  /// El flujo, guardado aquí porque en `dispose` ya no vale `ref`.
  late final RecoveryFileController _flow = ref.read(
    recoveryFileProvider.notifier,
  );

  bool _protect = false;
  bool _working = false;
  bool _saved = false;
  RecoveryFileProblem? _problem;

  /// El motivo por el que la contraseña no vale (en vivo) y si ya vale.
  RecoveryPasswordProblem? _live;
  bool _ready = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    // Aquí se escribe la contraseña de un fichero que abre la lista: sin
    // capturas en Android, como las palabras.
    unawaited(enableSecureScreen());
  }

  @override
  void dispose() {
    unawaited(disableSecureScreen());
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  // ---- Contraseña

  void _onPasswordChanged() {
    final password = _password.text;
    final repeat = _repeat.text;
    final generation = ++_generation;
    setState(() {
      _ready = false;
      _problem = null;
      if (password.isEmpty) _live = null;
    });
    if (password.isEmpty) return;
    unawaited(() async {
      RecoveryPasswordProblem? problem;
      try {
        problem = await _flow.checkNewPassword(
          password,
          repeat: repeat.isEmpty ? null : repeat,
        );
      } on Object catch (e) {
        // Sin la normalización NFC de la plataforma no se puede validar.
        if (!mounted || generation != _generation) return;
        setState(() {
          _live = null;
          _ready = false;
          _problem = recoveryFileProblemOf(e);
        });
        return;
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _live = problem;
        _ready = problem == null && repeat.isNotEmpty;
      });
    }());
  }

  void _setProtect(bool value) {
    ref.read(hapticsProvider).selection();
    _generation++;
    setState(() {
      _protect = value;
      _problem = null;
      if (!value) {
        _password.clear();
        _repeat.clear();
        _live = null;
        _ready = false;
      }
    });
  }

  /// Dónde sale la hoja de compartir en un iPad.
  Rect? _shareOrigin() {
    final box = _shareKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  bool get _canSubmit => !_working && (!_protect || _ready);

  // ---- Acciones

  /// Un fichero sellado nuevo para cada guardado o envío (sal y nonce
  /// nuevos, ADR 0008): con contraseña repite la derivación, con su progreso.
  /// Solo vive lo que dura ese guardado o envío.
  Future<PreparedRecoveryFile> _prepare() => _flow.prepare(
    widget.display,
    password: _protect ? _password.text : null,
    repeat: _protect ? _repeat.text : null,
  );

  Future<void> _run(Future<void> Function() action) async {
    if (!_canSubmit) return;
    setState(() {
      _working = true;
      _problem = null;
    });
    try {
      await action();
    } on RecoveryPasswordException catch (e) {
      if (mounted) {
        setState(() {
          _live = e.problem;
          _ready = false;
        });
      }
    } on Object catch (e) {
      final problem = recoveryFileProblemOf(e);
      if (mounted && problem != null) {
        ref.read(hapticsProvider).error();
        setState(() => _problem = problem);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save() => _run(() async {
    final l10n = AppLocalizations.of(context);
    final file = await _prepare();
    final name = recoveryCodeFileName(l10n.recoveryFileStem, clock.now());
    final result = await _flow.save(file, fileName: name);
    if (!mounted) return;
    if (result == RecoveryFileSaveResult.confirmed) {
      ref.read(hapticsProvider).success();
      setState(() => _saved = true);
    }
  });

  Future<void> _share() => _run(() async {
    final l10n = AppLocalizations.of(context);
    final origin = _shareOrigin();
    final file = await _prepare();
    final name = recoveryCodeFileName(l10n.recoveryFileStem, clock.now());
    await _flow.share(
      file,
      fileName: name,
      text: l10n.recoveryFileShareText,
      origin: origin,
    );
  });

  void _close() {
    _flow.cancel();
    Navigator.of(context).pop(_saved);
  }

  // ---- Pantalla

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final deriving = ref.watch(
      recoveryFileProvider.select(
        (s) => s.activity == RecoveryFileActivity.deriving,
      ),
    );
    final mismatch = _live == RecoveryPasswordProblem.mismatch;
    final firstNote = _live == null || mismatch
        ? null
        : recoveryPasswordProblemText(l10n, _live!);
    final repeatNote = mismatch ? l10n.recoveryFilePwMismatch : null;

    final body = AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UnfoldSection(
            show: _saved,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RecoveryCard(
                    leading: const RecoverySuccessMark(size: 48),
                    title: l10n.recoveryFileSavedTitle,
                    body: l10n.recoveryFileSavedBody,
                  ),
                  const SizedBox(height: 8),
                  // Otras copias: en el cuerpo, que se desplaza, para que el pie
                  // quede en un solo botón con letra grande.
                  OutlinedButton(
                    onPressed: _canSubmit ? _save : null,
                    child: Text(l10n.recoveryFileSaveAgain),
                  ),
                  TextButton(
                    key: _shareKey,
                    onPressed: _canSubmit ? _share : null,
                    child: Text(l10n.recoveryFileShare),
                  ),
                ],
              ),
            ),
          ),
          RecoveryHeading(
            title: l10n.recoveryFileTitle,
            body: l10n.recoveryFileBody,
          ),
          const SizedBox(height: 16),
          WarningBox(l10n.recoveryFilePersonal),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _protect,
            onChanged: _working ? null : (v) => _setProtect(v ?? false),
            title: Text(l10n.recoveryFileProtect, style: t.styles.rowTitle),
            subtitle: RecoveryFade(
              stateKey: _protect,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _protect
                      ? l10n.recoveryFileProtectOnHint
                      : l10n.recoveryFileProtectOffHint,
                  style: t.styles.meta,
                ),
              ),
            ),
          ),
          UnfoldSection(
            show: _protect,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RecoveryPasswordField(
                    controller: _password,
                    label: l10n.recoveryFilePassword,
                    newPassword: true,
                    enabled: !_working,
                    error: firstNote != null,
                    textInputAction: TextInputAction.next,
                    onChanged: _onPasswordChanged,
                  ),
                  RecoveryFieldNote(text: firstNote),
                  const SizedBox(height: 12),
                  RecoveryPasswordField(
                    controller: _repeat,
                    label: l10n.recoveryFilePasswordRepeat,
                    newPassword: true,
                    enabled: !_working,
                    error: repeatNote != null,
                    onChanged: _onPasswordChanged,
                    onSubmitted: _canSubmit ? _save : null,
                  ),
                  RecoveryFieldNote(text: repeatNote),
                  const SizedBox(height: 8),
                  Text(
                    l10n.recoveryFilePasswordHelp(kRecoveryPasswordMinRunes),
                    style: t.styles.meta,
                  ),
                  const SizedBox(height: 12),
                  WarningBox(l10n.recoveryFilePasswordForgot),
                ],
              ),
            ),
          ),
          UnfoldSection(
            show: deriving,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: RecoveryDerivingCard(
                title: l10n.recoveryFileDerivingTitle,
                body: l10n.recoveryFileDerivingBody,
              ),
            ),
          ),
          RecoveryProblemNote(problem: _problem),
        ],
      ),
    );

    // Mientras deriva, «Cancelar» va en el pie, siempre a la vista.
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (deriving)
          OutlinedButton(
            onPressed: _flow.cancel,
            child: Text(l10n.actionCancel),
          )
        else if (_saved) ...[
          FilledButton(onPressed: _close, child: Text(l10n.recoveryContinue)),
        ] else ...[
          FilledButton(
            onPressed: _canSubmit ? _save : null,
            child: Text(l10n.recoveryFileSave),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: _shareKey,
            onPressed: _canSubmit ? _share : null,
            child: Text(l10n.recoveryFileShare),
          ),
        ],
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: RecoveryFlowScaffold(onBack: _close, footer: footer, child: body),
    );
  }
}
