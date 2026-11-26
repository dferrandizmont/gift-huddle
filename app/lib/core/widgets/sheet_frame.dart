import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../motion/sheet_motion.dart';
import '../theme/regalos_tokens.dart';
import 'regalos_switch.dart';

/// Marco de las hojas inferiores de edición: título, contenido que se
/// desplaza con el teclado y los botones Cancelar y Guardar.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.saveLabel,
  });

  final String title;
  final List<Widget> children;

  /// Se llama al pulsar Guardar; `null` lo desactiva.
  final VoidCallback? onSave;
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: t.styles.screenTitleSmall),
              ),
              const SizedBox(height: 16),
              ...children,
              const SizedBox(height: 16),
              // Con letra grande en una pantalla estrecha los botones pasan a
              // dos líneas en vez de desbordar.
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.actionCancel),
                  ),
                  FilledButton(
                    onPressed: onSave,
                    child: Text(saveLabel ?? l10n.actionSave),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Abre una hoja inferior de edición por encima de la barra de navegación.
Future<T?> showEditSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showRegalosSheet<T>(
      context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: builder,
    );

/// Fila con un interruptor y su explicación, para las hojas y formularios.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String title;
  final String? hint;
  final bool value;

  /// `null` deja el interruptor fijo: sin toque y atenuado.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Text(title, style: t.styles.rowTitleCompact),
                  ),
                  if (hint != null)
                    ExcludeSemantics(child: Text(hint!, style: t.styles.meta)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            RegalosSwitch(
              value: value,
              semanticLabel: title,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
