import 'package:flutter/material.dart';

import '../../../core/motion/sheet_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/settings_row.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';

/// Lo que se decide en la hoja «Más opciones» y hace la pantalla al cerrarla.
enum MoreChoice {
  /// Unir este móvil a otra familia leyendo su QR.
  scanQr,

  /// Unir este móvil a otra familia con un enlace de invitación.
  pasteLink,

  /// Dejar de sincronizar (ya confirmado).
  stopSync,
}

/// Abre la hoja «Más opciones» de «Móviles de la familia»: unir este móvil a
/// otra familia, dejar de sincronizar (solo con [canStopSync]) y cómo se
/// protege la lista ([showPrivacy], si la versión sincroniza).
///
/// Cada fila lleva a su paso dentro de la misma hoja: el paso entra por la
/// derecha y la hoja cambia de alto con `snap`. «Dejar de sincronizar» se
/// confirma aquí, no en un diálogo.
Future<MoreChoice?> showMoreOptionsSheet(
  BuildContext context, {
  required bool canStopSync,
  required bool showPrivacy,
}) => showRegalosSheet<MoreChoice>(
  context,
  flat: true,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) =>
      _MoreSheet(canStopSync: canStopSync, showPrivacy: showPrivacy),
);

enum _Step { menu, joinOther, stop, privacy }

class _MoreSheet extends StatefulWidget {
  const _MoreSheet({required this.canStopSync, required this.showPrivacy});

  final bool canStopSync;
  final bool showPrivacy;

  @override
  State<_MoreSheet> createState() => _MoreSheetState();
}

class _MoreSheetState extends State<_MoreSheet> {
  _Step _step = _Step.menu;
  bool _back = false;

  void _go(_Step step, {bool back = false}) => setState(() {
    _step = step;
    _back = back;
  });

  void _done(MoreChoice choice) => Navigator.of(context).pop(choice);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    void toMenu() => _go(_Step.menu, back: true);
    final backLabel = l10n.backTo(l10n.devicesMore);
    const buttonShape = RoundedRectangleBorder(
      borderRadius: RegalosShape.button,
    );
    Widget ghost(String label, VoidCallback onPressed) => OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.text,
        minimumSize: const Size(44, 48),
        side: BorderSide(color: t.controlBorder),
        shape: buttonShape,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
    Widget padded(List<Widget> children) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

    final List<Widget> children;
    switch (_step) {
      case _Step.menu:
        children = [
          SheetHeading(title: l10n.devicesMore),
          Divider(height: 1, thickness: 1, color: t.separator),
          SettingsRow(
            icon: SettingsIcons.leave,
            title: l10n.devicesJoinOther,
            hint: l10n.devicesJoinOtherHint,
            onTap: () => _go(_Step.joinOther),
          ),
          if (widget.canStopSync)
            SettingsRow(
              icon: SettingsIcons.cloudOff,
              title: l10n.syncStopTitle,
              hint: l10n.syncStopHint,
              danger: true,
              onTap: () => _go(_Step.stop),
            ),
          if (widget.showPrivacy)
            SettingsRow(
              icon: SettingsIcons.shield,
              title: l10n.devicesPrivacyTitle,
              onTap: () => _go(_Step.privacy),
            ),
        ];
      case _Step.joinOther:
        children = [
          SheetHeading(
            title: l10n.devicesJoinOther,
            backLabel: backLabel,
            onBack: toMenu,
          ),
          padded([
            WarningBox(l10n.devicesJoinOtherWarning),
            const SizedBox(height: 12),
          ]),
          SheetDoor(
            icon: SettingsIcons.qr,
            title: l10n.devicesScanTitle,
            hint: l10n.devicesScanHint,
            onTap: () => _done(MoreChoice.scanQr),
          ),
          SheetDoor(
            icon: SettingsIcons.link,
            title: l10n.devicesPasteLinkTitle,
            hint: l10n.devicesPasteLinkHint,
            onTap: () => _done(MoreChoice.pasteLink),
          ),
        ];
      case _Step.stop:
        children = [
          SheetHeading(
            title: l10n.syncStopConfirmTitle,
            backLabel: backLabel,
            onBack: toMenu,
          ),
          padded([
            Text(
              l10n.syncStopConfirmBody,
              style: t.styles.body.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: t.dangerSoft,
                foregroundColor: t.danger,
                shape: buttonShape,
              ),
              onPressed: () => _done(MoreChoice.stopSync),
              child: Text(l10n.syncStopTitle),
            ),
            const SizedBox(height: 8),
            ghost(l10n.actionCancel, () => Navigator.of(context).pop()),
          ]),
        ];
      case _Step.privacy:
        children = [
          SheetHeading(
            title: l10n.devicesPrivacyTitle,
            backLabel: backLabel,
            onBack: toMenu,
          ),
          padded([
            Text(
              l10n.syncPrivacyNote,
              style: t.styles.body.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: 16),
            ghost(l10n.actionUnderstood, () => Navigator.of(context).pop()),
          ]),
        ];
    }
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: SheetSteps(
          step: _step,
          back: _back,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
