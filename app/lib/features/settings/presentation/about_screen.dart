import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_info.dart';
import '../../../core/layout/pane_scope.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/platform/external_link.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/settings_row.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tabler_icons.dart';
import '../../../l10n/app_localizations.dart';
import 'settings_column.dart';

/// Ajustes › Acerca de: nombre, versión, lo que la app guarda y el enlace a
/// la política de privacidad y el correo de soporte.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key, this.embedded = false});

  /// Si va apilado en la columna de Ajustes del tablero de la web.
  final bool embedded;

  /// Abre la política en el navegador del sistema, en el idioma de la app.
  /// Si no hay navegador, copia el enlace y lo dice.
  Future<void> _openPolicy(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final url = privacyPolicyUrl(l10n.localeName);
    final opened = await ref
        .read(externalLinkOpenerProvider)
        .open(url.toString());
    if (opened) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: url.toString()));
    if (context.mounted) {
      showRegalosSnackBar(
        context,
        SnackBar(content: Text(l10n.aboutPrivacyPolicyCopied)),
      );
    }
  }

  /// Abre la app de correo con el soporte. Si no hay ninguna, copia la
  /// dirección y lo dice.
  Future<void> _openSupport(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final opened = await ref
        .read(externalLinkOpenerProvider)
        .open(kSupportMailto.toString());
    if (opened) {
      return;
    }
    await Clipboard.setData(const ClipboardData(text: kSupportEmail));
    if (context.mounted) {
      showRegalosSnackBar(
        context,
        SnackBar(content: Text(l10n.aboutSupportCopied(kSupportEmail))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final body = <Widget>[
      StaggerItem(
        index: 0,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.appTitle, style: t.styles.screenTitle),
              Text(l10n.aboutVersion(kAppVersion), style: t.styles.meta),
              const SizedBox(height: 16),
              Text(l10n.aboutPrivacy, style: t.styles.body),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      StaggerItem(
        index: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.separator)),
          ),
          child: SettingsRow(
            icon: SettingsIcons.shield,
            title: l10n.aboutPrivacyPolicy,
            hint: l10n.aboutPrivacyPolicyHint,
            // Sale de la app: una flecha hacia fuera, no la de «entrar».
            trailing: StrokeIcon(
              tablerExternalLink,
              color: t.textSecondary,
              strokeWidth: 1.9,
            ),
            onTap: () => _openPolicy(context, ref),
          ),
        ),
      ),
      StaggerItem(
        index: 2,
        child: SettingsRow(
          icon: SettingsIcons.mail,
          title: l10n.aboutSupport,
          hint: l10n.aboutSupportHint,
          // Sale de la app, hacia el correo.
          trailing: StrokeIcon(
            tablerExternalLink,
            color: t.textSecondary,
            strokeWidth: 1.9,
          ),
          onTap: () => _openSupport(context, ref),
        ),
      ),
    ];
    if (embedded) {
      return StaggerScope(
        animate: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EmbeddedSectionHeader(title: l10n.settingsAbout),
            ...body,
          ],
        ),
      );
    }
    return Scaffold(
      body: StaggerScope(
        // En dos paneles el detalle ya cambia con su propio eje: no repite
        // la entrada escalonada.
        animate: PaneScope.roleOf(context) != PaneRole.detail,
        child: SafeArea(
          bottom: false,
          child: ListView(
            // Abajo, el margen seguro que la lista ponía sola al no llevar
            // `padding`.
            padding: settingsColumnPadding(
              context,
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              ScreenHeader(
                eyebrow: l10n.navSettings,
                title: l10n.settingsAbout,
                backLabel: l10n.backTo(l10n.navSettings),
                onBack: () =>
                    context.canPop() ? context.pop() : context.go('/settings'),
              ),
              ...body,
            ],
          ),
        ),
      ),
    );
  }
}
