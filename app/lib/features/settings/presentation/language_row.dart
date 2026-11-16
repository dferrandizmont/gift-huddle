import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/sheet_motion.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/settings_row.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../application/locale_provider.dart';

/// El valor que devuelve la hoja para «Sistema» (el proveedor lo guarda como
/// `null`).
const String _systemCode = 'system';

/// El nombre de cada idioma en su propia lengua; solo «Sistema» se traduce.
String _languageName(AppLocalizations l10n, String? code) => switch (code) {
  'es' => l10n.settingsLanguageSpanish,
  'ca' => l10n.settingsLanguageCatalan,
  'en' => l10n.settingsLanguageEnglish,
  _ => l10n.settingsLanguageSystem,
};

/// Fila «Idioma» de Ajustes: enseña el idioma elegido a la derecha y abre la
/// hoja para cambiarlo. Al volver, el valor nuevo entra desde abajo.
class LanguageRow extends ConsumerWidget {
  const LanguageRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(localeProvider)?.languageCode;
    return SettingsRow(
      icon: SettingsIcons.language,
      title: l10n.settingsLanguage,
      value: _languageName(l10n, current),
      onTap: () async {
        final picked = await showLanguageSheet(context, current: current);
        if (picked == null) {
          return;
        }
        ref
            .read(localeProvider.notifier)
            .setLocale(picked == _systemCode ? null : Locale(picked));
      },
    );
  }
}

/// Abre la hoja de idioma: Sistema, Español, Català y English, con un visto
/// en el elegido. Devuelve el código tocado (`system`, `es`, `ca`, `en`) o
/// `null` si se cierra sin elegir.
Future<String?> showLanguageSheet(BuildContext context, {String? current}) =>
    showRegalosSheet<String>(
      context,
      flat: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LanguageSheet(current: current ?? _systemCode),
    );

class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({required this.current});

  final String current;

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  /// Lo que tarda la hoja en bajar sola tras elegir: deja ver el visto.
  static const Duration _closeDelay = Duration(milliseconds: 340);

  String? _picked;
  Timer? _close;

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  void _pick(String code) {
    if (_picked != null) {
      return;
    }
    setState(() => _picked = code);
    final reduce = RegalosMotion.of(context).reduce;
    _close = Timer(reduce ? RegalosMotion.fade : _closeDelay, () {
      if (mounted) {
        Navigator.of(context).pop(code);
      }
    });
  }

  /// El idioma que usa la app cuando sigue al del móvil.
  String _systemLanguage(AppLocalizations l10n) {
    final resolved = basicLocaleListResolution(
      WidgetsBinding.instance.platformDispatcher.locales,
      AppLocalizations.supportedLocales,
    );
    return _languageName(l10n, resolved.languageCode);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = _picked ?? widget.current;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeading(title: l10n.settingsLanguage),
            Semantics(
              container: true,
              explicitChildNodes: true,
              label: l10n.settingsLanguage,
              child: Column(
                children: [
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: RegalosTokens.of(context).separator,
                  ),
                  for (final code in const [_systemCode, 'es', 'ca', 'en'])
                    CheckOptionRow(
                      title: _languageName(l10n, code),
                      hint: code == _systemCode
                          ? l10n.settingsLanguageSystemNow(
                              _systemLanguage(l10n),
                            )
                          : null,
                      selected: code == selected,
                      drawCheck: code == _picked,
                      onTap: () => _pick(code),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
