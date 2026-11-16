import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/pane_scope.dart';
import '../../../core/motion/sheet_motion.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/settings_row.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/settings_column.dart';
import '../application/share_service.dart';
import 'share_dialogs.dart';
import 'share_error_text.dart';

/// Ajustes › Copia de seguridad: guardar la lista en un fichero `.gifthuddle`
/// cifrado y recuperarla (lo que antes eran «Enviar cambios» y «Pegar
/// cambios» de Compartir).
///
/// La copia va cifrada y no lleva ninguna clave en claro: solo se abre en un
/// móvil que ya esté conectado, y la pantalla lo dice. Sin la marca del
/// formato 2 es el sobre de siempre (con la clave de la familia); con ella,
/// el fichero de intercambio firmado con sus paquetes (ADR 0005, B6). Lo
/// decide `ShareService`. No es la copia de recuperación (fase 3, lote 5).
class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  void _say(BuildContext context, String text) {
    showRegalosSnackBar(context, SnackBar(content: Text(text)));
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(shareServiceProvider).shareEnvelope(context);
    } on Object catch (error) {
      if (context.mounted) {
        _say(context, shareSendErrorMessage(l10n, error));
      }
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final paste = await showRegalosSheet<bool>(
      context,
      flat: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _RestoreSheet(),
    );
    if (paste == true && context.mounted) {
      await _paste(context, ref);
    }
  }

  Future<void> _paste(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!context.mounted) {
      return;
    }
    if (text.isEmpty) {
      _say(context, l10n.sharePasteEmpty);
      return;
    }
    try {
      final summary = await ref.read(shareServiceProvider).importFromText(text);
      if (context.mounted) {
        await showImportSummaryDialog(context, summary);
      }
    } on Object catch (error) {
      if (context.mounted) {
        await showImportErrorDialog(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Scaffold(
      body: StaggerScope(
        // En dos paneles el detalle ya cambia con su propio eje: no repite
        // la entrada escalonada.
        animate: PaneScope.roleOf(context) != PaneRole.detail,
        step: const Duration(milliseconds: 40),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: settingsColumnPadding(context),
            children: [
              ScreenHeader(
                eyebrow: l10n.navSettings,
                title: l10n.settingsBackup,
                subtitle: l10n.backupSubtitle,
                backLabel: l10n.backTo(l10n.navSettings),
                onBack: () =>
                    context.canPop() ? context.pop() : context.go('/settings'),
              ),
              StaggerItem(
                index: 0,
                dy: 10,
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.separator)),
                  ),
                  child: Column(
                    children: [
                      Builder(
                        builder: (rowContext) => SettingsRow(
                          icon: SettingsIcons.download,
                          title: l10n.backupSaveTitle,
                          hint: l10n.backupSaveHint,
                          onTap: () => _save(rowContext, ref),
                        ),
                      ),
                      SettingsRow(
                        icon: SettingsIcons.upload,
                        title: l10n.backupRestoreTitle,
                        hint: l10n.backupRestoreHint,
                        onTap: () => _restore(context, ref),
                      ),
                    ],
                  ),
                ),
              ),
              // ADR 0004 (R-b y R-c): aquí irá el grupo «Para un móvil
              // nuevo» con la fila «Código de recuperación» y su hoja.
              // Oculto hasta que funcione.
              StaggerItem(
                index: 1,
                dy: 10,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(l10n.backupNote, style: t.styles.meta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La hoja «Recuperar una copia»: pegar desde el portapapeles y cómo se abre
/// un fichero. Devuelve `true` si se elige pegar.
class _RestoreSheet extends StatelessWidget {
  const _RestoreSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeading(
              title: l10n.backupRestoreTitle,
              subtitle: l10n.backupRestoreSubtitle,
            ),
            SheetDoor(
              icon: SettingsIcons.clipboard,
              title: l10n.backupPasteTitle,
              hint: l10n.backupPasteHint,
              onTap: () => Navigator.of(context).pop(true),
            ),
            Divider(height: 1, thickness: 1, color: t.separator),
            // Elegir el fichero desde la app pide un selector de ficheros que
            // la app aún no tiene: se abre desde fuera.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(l10n.backupFileNote, style: t.styles.meta),
            ),
          ],
        ),
      ),
    );
  }
}
