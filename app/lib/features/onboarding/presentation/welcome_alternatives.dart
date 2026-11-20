import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/device/device_name.dart';
import '../../../core/motion/sheet_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../sync/application/recovery_providers.dart';

/// Lo que se puede elegir en las hojas de la bienvenida.
enum _WelcomeChoice { joinQr, joinLink, recoverCode, recoverFile }

/// Los dos botones de debajo de «Empezar» en la bienvenida: «Unirme a una
/// familia» (QR o enlace) y «Restaurar una copia» (código o fichero).
///
/// Van lado a lado, de medio ancho cada uno. Si no caben (pantalla estrecha o
/// letra muy grande) se apilan, uno encima del otro, a todo el ancho. Cada uno
/// abre una hoja con sus dos opciones; la opción elegida cierra la hoja y abre
/// su pantalla. «Unirme» se desactiva con una recuperación a medias, igual que
/// antes lo hacían las dos opciones sueltas.
class WelcomeAlternatives extends ConsumerWidget {
  /// Crea los botones.
  const WelcomeAlternatives({
    super.key,
    required this.nameController,
    required this.pending,
  });

  /// El nombre de este móvil: viaja con la petición de unirse.
  final TextEditingController nameController;

  /// Si hay una recuperación a medias: sin unirse a otra familia.
  final bool pending;

  Future<void> _joinSheet(BuildContext context, WidgetRef ref) async {
    final choice = await _showSheet(context, join: true);
    if (choice == null || !context.mounted) {
      return;
    }
    // La recuperación pendiente puede aparecer con la hoja abierta.
    if (ref.read(recoveryStatusProvider).hasPendingRestore) {
      return;
    }
    final name = deviceNameToSend(ref, nameController.text);
    if (choice == _WelcomeChoice.joinQr) {
      context.push(AppRoutes.join, extra: name);
    } else if (choice == _WelcomeChoice.joinLink) {
      context.push(AppRoutes.joinLink, extra: name);
    }
  }

  Future<void> _restoreSheet(BuildContext context) async {
    final choice = await _showSheet(context, join: false);
    if (choice == null || !context.mounted) {
      return;
    }
    if (choice == _WelcomeChoice.recoverCode) {
      context.push(AppRoutes.recover);
    } else if (choice == _WelcomeChoice.recoverFile) {
      context.push(AppRoutes.recoverFile);
    }
  }

  Future<_WelcomeChoice?> _showSheet(
    BuildContext context, {
    required bool join,
  }) => showRegalosSheet<_WelcomeChoice>(
    context,
    flat: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _WelcomeSheet(join: join),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final style = OutlinedButton.styleFrom(
      foregroundColor: t.text,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      side: BorderSide(color: t.controlBorder),
      shape: const RoundedRectangleBorder(borderRadius: RegalosShape.button),
    );
    final join = OutlinedButton(
      style: style,
      onPressed: pending ? null : () => _joinSheet(context, ref),
      child: Text(l10n.obJoinFamily, textAlign: TextAlign.center),
    );
    final restore = OutlinedButton(
      style: style,
      onPressed: () => _restoreSheet(context),
      child: Text(l10n.obRestoreBackup, textAlign: TextAlign.center),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Con letra grande o poco ancho, uno encima del otro: así ningún
        // texto se parte en tres líneas ni desborda.
        final stacked =
            MediaQuery.textScalerOf(context).scale(16) > 21 ||
            constraints.maxWidth < 300;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [join, const SizedBox(height: 8), restore],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: join),
              const SizedBox(width: 8),
              Expanded(child: restore),
            ],
          ),
        );
      },
    );
  }
}

class _WelcomeSheet extends StatelessWidget {
  const _WelcomeSheet({required this.join});

  final bool join;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    void pick(_WelcomeChoice choice) => Navigator.of(context).pop(choice);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: join
              ? [
                  SheetHeading(
                    title: l10n.obJoinFamily,
                    subtitle: l10n.obJoinFamilyHint,
                  ),
                  SheetDoor(
                    icon: SettingsIcons.qr,
                    title: l10n.shareJoinTitle,
                    hint: l10n.obJoinQrHint,
                    onTap: () => pick(_WelcomeChoice.joinQr),
                  ),
                  SheetDoor(
                    icon: SettingsIcons.link,
                    title: l10n.joinInviteRowTitle,
                    hint: l10n.obJoinLinkHint,
                    onTap: () => pick(_WelcomeChoice.joinLink),
                  ),
                ]
              : [
                  SheetHeading(
                    title: l10n.obRestoreBackup,
                    subtitle: l10n.obRestoreBackupHint,
                  ),
                  SheetDoor(
                    icon: SettingsIcons.key,
                    title: l10n.obHaveRecoveryCode,
                    hint: l10n.obRestoreCodeHint,
                    onTap: () => pick(_WelcomeChoice.recoverCode),
                  ),
                  SheetDoor(
                    icon: SettingsIcons.upload,
                    title: l10n.obRecoverWithFile,
                    hint: l10n.obRestoreFileHint,
                    onTap: () => pick(_WelcomeChoice.recoverFile),
                  ),
                ],
        ),
      ),
    );
  }
}
