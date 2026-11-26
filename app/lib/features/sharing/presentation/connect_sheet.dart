import 'package:flutter/material.dart';

import '../../../core/motion/sheet_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import 'pairing_qr_view.dart';

/// Lo que se elige en la hoja «Conectar otro móvil» y necesita otra pantalla.
enum ConnectChoice {
  /// «Está lejos»: invitar con un enlace.
  far,
}

/// Abre la hoja «Conectar otro móvil» (la maqueta de ajustes, Compartir A):
/// pregunta dónde está el otro móvil.
///
/// - «Está aquí» enseña el QR dentro de la misma hoja: el paso entra por la
///   derecha y la hoja cambia de alto con `snap`.
/// - «Está lejos» cierra la hoja y devuelve [ConnectChoice.far]: la
///   invitación con enlace sigue en su pantalla.
Future<ConnectChoice?> showConnectSheet(BuildContext context) =>
    showRegalosSheet<ConnectChoice>(
      context,
      flat: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ConnectSheet(),
    );

enum _Step { choose, here }

class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet();

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  _Step _step = _Step.choose;
  bool _back = false;

  void _go(_Step step, {bool back = false}) => setState(() {
    _step = step;
    _back = back;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final Widget body;
    switch (_step) {
      case _Step.choose:
        body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeading(
              title: l10n.devicesConnect,
              subtitle: l10n.devicesConnectQuestion,
            ),
            SheetDoor(
              icon: SettingsIcons.qr,
              title: l10n.devicesHereTitle,
              hint: l10n.devicesHereHint,
              onTap: () => _go(_Step.here),
            ),
            SheetDoor(
              icon: SettingsIcons.link,
              title: l10n.devicesFarTitle,
              hint: l10n.devicesFarHint,
              onTap: () => Navigator.of(context).pop(ConnectChoice.far),
            ),
          ],
        );
      case _Step.here:
        body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeading(
              title: l10n.devicesHereTitle,
              subtitle: l10n.showQrIntro,
              backLabel: l10n.backTo(l10n.devicesConnect),
              onBack: () => _go(_Step.choose, back: true),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PairingQrView(),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.text,
                      minimumSize: const Size(44, 48),
                      side: BorderSide(color: t.controlBorder),
                      shape: const RoundedRectangleBorder(
                        borderRadius: RegalosShape.button,
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.actionClose),
                  ),
                ],
              ),
            ),
          ],
        );
    }
    // Con el teclado abierto («¿Quién eres?» pide un nombre) la hoja deja su
    // sitio al teclado: lo de dentro se desplaza y el campo y «Continuar»
    // quedan por encima (QA 1.0.7, M1).
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: SheetSteps(step: _step, back: _back, child: body),
        ),
      ),
    );
  }
}
