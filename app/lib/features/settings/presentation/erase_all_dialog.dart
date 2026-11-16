import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../application/erase_all.dart';
import 'verify_owner.dart';

/// Clave del campo donde se escribe la palabra que confirma «Borrar todo»
/// (para las pruebas).
const Key kEraseAllFieldKey = ValueKey<String>('eraseAllField');

/// Clave del botón final de «Borrar todo» (para las pruebas).
const Key kEraseAllConfirmKey = ValueKey<String>('eraseAllConfirm');

/// «Borrar todo» de Ajustes, con doble confirmación.
///
/// 1. Un diálogo explica qué se borra, que no se puede deshacer y que los
///    demás móviles conservan su copia.
/// 2. Si hay PIN, se pide (o la huella o el rostro, si están activados, como
///    al desbloquear): sin él no se llega al último paso. Sin PIN configurado
///    no se pide nada.
/// 3. En el último paso hay que escribir una palabra («BORRAR») para que el
///    botón rojo se active. Si hay sincronización, primero se borra la copia
///    del servidor; si el servidor no responde, se puede reintentar, borrar
///    solo este móvil o dejarlo.
///
/// Al acabar no hay familia y la app vuelve sola al primer uso.
Future<void> runEraseAll(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final eraser = ref.read(eraseAllProvider);
  // El servicio se toma ya: la pantalla desaparece al borrar.
  final haptics = ref.read(hapticsProvider);
  // La pantalla de Ajustes desaparece al borrar: el aviso de un fallo sale
  // por el `ScaffoldMessenger` de la app.
  final messenger = ScaffoldMessenger.of(context);
  final snackStyle = regalosSnackBarStyle(context);
  void sayFailed() => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(l10n.eraseAllFailed)),
      snackBarAnimationStyle: snackStyle,
    );

  final go = await showRegalosConfirm(
    context,
    title: l10n.eraseAllConfirmTitle,
    body: eraser.hasServerCopy
        ? '${l10n.eraseAllConfirmBody} ${l10n.eraseAllConfirmServer}'
        : l10n.eraseAllConfirmBody,
    confirmLabel: l10n.eraseAllContinue,
    cancelLabel: l10n.actionCancel,
  );
  if (!go || !context.mounted) {
    return;
  }
  final bool verified;
  try {
    verified = await _verifyOwner(context, ref);
  } on Object {
    // No se sabe si hay PIN (el bloqueo no se pudo leer): no se borra.
    sayFailed();
    return;
  }
  if (!verified || !context.mounted) {
    return;
  }
  final confirmed = await showRegalosDialog<bool>(
    context,
    builder: (_) => EraseAllDialog(eraser: eraser),
  );
  if (confirmed != true) {
    return;
  }
  haptics.warning();
  try {
    await eraser.eraseLocal();
  } on Object {
    sayFailed();
  }
}

/// El paso del PIN de «Borrar todo» ([verifyOwner]).
Future<bool> _verifyOwner(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  return verifyOwner(
    context,
    ref,
    title: l10n.eraseAllTitle,
    message: l10n.eraseAllPinPrompt,
    biometricReason: l10n.eraseAllBiometricReason,
  );
}

enum _Phase { typing, working, failed }

/// El último paso de «Borrar todo»: escribir la palabra y, si hay
/// sincronización, borrar la copia del servidor.
///
/// Se cierra con `true` cuando ya se puede borrar lo de este móvil (el
/// servidor ya no tiene la copia, no había, o se eligió borrar solo este
/// móvil) y con `null` o `false` si se cancela. No borra nada local.
class EraseAllDialog extends StatefulWidget {
  /// Crea el diálogo sobre [eraser].
  const EraseAllDialog({super.key, required this.eraser});

  /// El borrado.
  final EraseAll eraser;

  @override
  State<EraseAllDialog> createState() => _EraseAllDialogState();
}

class _EraseAllDialogState extends State<EraseAllDialog> {
  final TextEditingController _text = TextEditingController();
  _Phase _phase = _Phase.typing;
  bool _matches = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// La palabra vale sin distinguir mayúsculas ni espacios de más.
  void _onChanged(String value, String word) {
    final matches = value.trim().toUpperCase() == word.toUpperCase();
    if (matches != _matches) {
      setState(() => _matches = matches);
    }
  }

  Future<void> _erase() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!widget.eraser.hasServerCopy) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _phase = _Phase.working);
    try {
      await widget.eraser.eraseServerCopy();
    } on Object {
      // Sin red, o el servidor no lo admite: se pregunta qué hacer.
      if (mounted) {
        setState(() => _phase = _Phase.failed);
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = RegalosMotion.of(context);
    final duration = motion.duration(const Duration(milliseconds: 200));
    final curve = motion.curve(RegalosCurves.fold);
    return PopScope(
      // Mientras se borra la copia del servidor no se puede salir.
      canPop: _phase != _Phase.working,
      child: RegalosDialogSurface(
        scrollable: true,
        // Los tres estados se funden y el diálogo cambia de alto sin saltos.
        child: AnimatedSize(
          duration: duration,
          curve: curve,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: curve,
            switchOutCurve: curve,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            child: KeyedSubtree(
              key: ValueKey<_Phase>(_phase),
              child: switch (_phase) {
                _Phase.typing => _typing(context),
                _Phase.working => _working(context),
                _Phase.failed => _failed(context),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _typing(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final word = l10n.eraseAllWord;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.eraseAllTypeTitle, style: t.styles.screenTitleSmall),
        ),
        const SizedBox(height: 8),
        Text(l10n.eraseAllTypeBody(word), style: t.styles.body),
        const SizedBox(height: 14),
        TextField(
          key: kEraseAllFieldKey,
          controller: _text,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          onChanged: (value) => _onChanged(value, word),
          onSubmitted: (_) {
            if (_matches) {
              unawaited(_erase());
            }
          },
          decoration: InputDecoration(
            labelText: l10n.eraseAllFieldLabel,
            hintText: word,
          ),
        ),
        const SizedBox(height: 20),
        DialogButtonRow(
          cancelLabel: l10n.actionCancel,
          confirmLabel: l10n.eraseAllTitle,
          cancel: OutlinedButton(
            style: regalosDialogCancelStyle(t),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          confirm: FilledButton(
            key: kEraseAllConfirmKey,
            style: regalosDialogDangerStyle(t),
            onPressed: _matches ? _erase : null,
            child: Text(l10n.eraseAllTitle, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }

  Widget _working(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.danger),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(l10n.eraseAllWorking, style: t.styles.body)),
          ],
        ),
      ),
    );
  }

  Widget _failed(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            l10n.eraseAllServerFailedTitle,
            style: t.styles.screenTitleSmall,
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.eraseAllServerFailedBody, style: t.styles.body),
        const SizedBox(height: 20),
        FilledButton(
          style: regalosDialogPrimaryStyle(t),
          onPressed: _erase,
          child: Text(l10n.eraseAllRetry),
        ),
        const SizedBox(height: 8),
        FilledButton(
          style: regalosDialogDangerStyle(
            t,
          ).copyWith(minimumSize: const WidgetStatePropertyAll(Size(44, 48))),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.eraseAllLocalOnly),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: regalosDialogCancelStyle(t),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
      ],
    );
  }
}
