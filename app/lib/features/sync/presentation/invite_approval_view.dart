import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../../l10n/app_localizations.dart';
import 'code_card.dart';

/// «Marta quiere unirse»: el código de 6 cifras y los botones Aceptar y
/// Rechazar.
///
/// [guestName] lo escribe el otro móvil: se enseña como texto, nunca como
/// instrucción.
class InviteApprovalView extends StatelessWidget {
  /// Crea la vista.
  const InviteApprovalView({
    super.key,
    required this.guestName,
    required this.code,
    required this.onAccept,
    required this.onReject,
    this.busy = false,
    this.errorText,
  });

  /// Nombre del móvil que pide entrar.
  final String guestName;

  /// Código de verificación, 6 cifras sin formato.
  final String code;

  /// Pulsó Aceptar.
  final VoidCallback onAccept;

  /// Pulsó Rechazar.
  final VoidCallback onReject;

  /// Subiendo la aprobación: los botones no responden.
  final bool busy;

  /// Error de un intento anterior.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final name = guestName.isEmpty ? l10n.deviceNameDefault : guestName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.inviteRequestTitle(name),
            style: t.styles.screenTitleSmall,
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.inviteRequestBody, style: t.styles.body),
        const SizedBox(height: 16),
        VerificationCodeCard(label: l10n.inviteCodeLabel, code: code),
        const SizedBox(height: 8),
        Text(
          l10n.inviteCompareNotice,
          style: t.styles.metaStrong,
          textAlign: TextAlign.center,
        ),
        if (errorText != null) ...[
          const SizedBox(height: 12),
          Text(errorText!, style: t.styles.body),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : onAccept,
          child: Text(l10n.inviteAccept),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: busy ? null : onReject,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(44, 48),
            foregroundColor: t.text,
            side: BorderSide(color: t.controlBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(l10n.inviteReject),
        ),
      ],
    );
  }
}
