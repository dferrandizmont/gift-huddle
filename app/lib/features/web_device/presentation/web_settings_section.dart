import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/settings_row.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../../l10n/app_localizations.dart';
import '../data/vault_crypto.dart';
import 'web_gate_model.dart';
import 'web_gate_parts.dart';

/// La sección «Este ordenador» de los Ajustes de la web: cambiar el PIN,
/// bloquear ahora y olvidar este ordenador (con confirmación).
///
/// Con [persistenceDenied] enseña, además, que el navegador podría borrar los
/// datos si le falta espacio (`navigator.storage.persist()` dijo que no).
class WebSettingsSection extends StatelessWidget {
  /// Crea la sección.
  const WebSettingsSection({
    super.key,
    required this.actions,
    this.persistenceDenied = false,
    this.leading = const <Widget>[],
    this.showHeader = true,
  });

  /// Lo que la interfaz pide al motor.
  final WebGateActions actions;

  /// Si el navegador no garantiza guardar los datos.
  final bool persistenceDenied;

  /// Filas que van antes de las de este ordenador, bajo la misma cabecera
  /// (en Ajustes: idioma y apariencia).
  final List<Widget> leading;

  /// Si la sección lleva su cabecera «Este ordenador». Ajustes la pone fuera
  /// (con el mismo margen que las demás) y la deja en `false`.
  final bool showHeader;

  Future<void> _forget(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showRegalosConfirm(
      context,
      title: l10n.webSettingsForgetTitle,
      body: l10n.webSettingsForgetBody,
      confirmLabel: l10n.webSettingsForgetConfirm,
      cancelLabel: l10n.actionCancel,
    );
    if (confirmed) {
      await actions.forgetComputer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) SectionHeader(title: l10n.webSettingsTitle),
        _PersistenceNotice(show: persistenceDenied),
        ...leading,
        SettingsRow(
          icon: SettingsIcons.lock,
          title: l10n.webSettingsChangePin,
          hint: l10n.webSettingsChangePinHint,
          onTap: () => unawaited(showWebChangePin(context, actions)),
        ),
        SettingsRow(
          icon: SettingsIcons.shield,
          title: l10n.webSettingsLockNow,
          chevron: false,
          onTap: () => unawaited(actions.lock()),
        ),
        SettingsRow(
          icon: SettingsIcons.trash,
          title: l10n.webSettingsForget,
          hint: l10n.webSettingsForgetHint,
          danger: true,
          chevron: false,
          bordered: false,
          onTap: () => unawaited(_forget(context)),
        ),
      ],
    );
  }
}

/// El aviso discreto de que el navegador podría borrar los datos. Entra y sale
/// con un fundido y estirando la sección.
class _PersistenceNotice extends StatelessWidget {
  const _PersistenceNotice({required this.show});

  final bool show;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    return AnimatedSize(
      duration: motion.duration(RegalosCurves.foldDuration),
      curve: motion.curve(RegalosCurves.fold),
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: RegalosMotion.fade,
        child: show
            ? Padding(
                key: const ValueKey<bool>(true),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: RegalosShape.card,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Semantics(
                      container: true,
                      child: Text(
                        l10n.webSettingsPersistenceDenied,
                        style: t.styles.meta,
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox(
                key: ValueKey<bool>(false),
                width: double.infinity,
              ),
      ),
    );
  }
}

/// Abre la hoja de cambio de PIN y, si se cambió, lo dice con un aviso breve.
/// Devuelve si se cambió. Lo usan Ajustes y el aviso de intentos fallidos.
Future<bool> showWebChangePin(
  BuildContext context,
  WebGateActions actions,
) async {
  final l10n = AppLocalizations.of(context);
  final changed = await showEditSheet<bool>(
    context,
    (_) => WebChangePinSheet(actions: actions),
  );
  if (changed == true && context.mounted) {
    showRegalosSnackBar(
      context,
      SnackBar(content: Text(l10n.webSettingsPinChanged)),
    );
  }
  return changed == true;
}

/// La hoja de «Cambiar PIN»: el actual y el nuevo (dos veces).
class WebChangePinSheet extends StatefulWidget {
  /// Crea la hoja.
  const WebChangePinSheet({super.key, required this.actions});

  /// Lo que la interfaz pide al motor.
  final WebGateActions actions;

  @override
  State<WebChangePinSheet> createState() => _WebChangePinSheetState();
}

enum _SheetProblem {
  none,
  currentEmpty,
  invalid,
  mismatch,
  wrongCurrent,
  failed,
}

class _WebChangePinSheetState extends State<WebChangePinSheet> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  _SheetProblem _problem = _SheetProblem.none;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _clearProblem() {
    if (_problem != _SheetProblem.none) {
      setState(() => _problem = _SheetProblem.none);
    }
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    if (_current.text.isEmpty) {
      setState(() => _problem = _SheetProblem.currentEmpty);
      return;
    }
    if (!VaultCrypto.validPin(_next.text)) {
      setState(() => _problem = _SheetProblem.invalid);
      return;
    }
    if (_next.text != _repeat.text) {
      setState(() => _problem = _SheetProblem.mismatch);
      return;
    }
    setState(() {
      _problem = _SheetProblem.none;
      _busy = true;
    });
    var result = WebPinChangeResult.failed;
    try {
      result = await widget.actions.changePin(_current.text, _next.text);
    } on Object {
      result = WebPinChangeResult.failed;
    }
    if (!mounted) {
      return;
    }
    switch (result) {
      case WebPinChangeResult.changed:
        Navigator.of(context).pop(true);
      case WebPinChangeResult.wrongCurrent:
        setState(() {
          _busy = false;
          _problem = _SheetProblem.wrongCurrent;
        });
      case WebPinChangeResult.failed:
        setState(() {
          _busy = false;
          _problem = _SheetProblem.failed;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final message = switch (_problem) {
      _SheetProblem.none => null,
      _SheetProblem.currentEmpty ||
      _SheetProblem.wrongCurrent => l10n.webSettingsCurrentWrong,
      _SheetProblem.invalid => l10n.webGatePinRule,
      _SheetProblem.mismatch => l10n.webGatePinMismatch,
      _SheetProblem.failed => l10n.webSettingsChangeFailed,
    };
    return SheetFrame(
      title: l10n.webSettingsChangePinTitle,
      saveLabel: l10n.actionSave,
      onSave: _busy ? null : _submit,
      children: [
        WebPinField(
          controller: _current,
          label: l10n.webSettingsCurrentPin,
          autofocus: true,
          enabled: !_busy,
          error:
              _problem == _SheetProblem.currentEmpty ||
              _problem == _SheetProblem.wrongCurrent,
          textInputAction: TextInputAction.next,
          onChanged: _clearProblem,
        ),
        const SizedBox(height: 16),
        WebPinField(
          controller: _next,
          label: l10n.webSettingsNewPin,
          enabled: !_busy,
          error: _problem == _SheetProblem.invalid,
          textInputAction: TextInputAction.next,
          onChanged: _clearProblem,
        ),
        const SizedBox(height: 8),
        Text(l10n.webGatePinRule, style: t.styles.meta),
        const SizedBox(height: 16),
        WebPinField(
          controller: _repeat,
          label: l10n.webSettingsNewPinRepeat,
          enabled: !_busy,
          error: _problem == _SheetProblem.mismatch,
          onChanged: _clearProblem,
          onSubmitted: _submit,
        ),
        WebGateMessage(text: message, danger: true, topGap: 8),
      ],
    );
  }
}
