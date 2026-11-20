import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/sheet_motion.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/anchored_picker.dart';
import '../../../core/widgets/picker_option.dart';
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
class LanguageRow extends ConsumerStatefulWidget {
  const LanguageRow({super.key});

  @override
  ConsumerState<LanguageRow> createState() => _LanguageRowState();
}

class _LanguageRowState extends ConsumerState<LanguageRow> {
  // El foco de la fila: el desplegable lo devuelve aquí al cerrarse, también
  // si se abrió con el ratón estando otra fila enfocada.
  final FocusNode _focus = FocusNode(debugLabel: 'LanguageRow');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(localeProvider)?.languageCode;
    return SettingsRow(
      icon: SettingsIcons.language,
      title: l10n.settingsLanguage,
      value: _languageName(l10n, current),
      focusNode: _focus,
      onTap: () async {
        final picked = await _pickLanguage(context, l10n, current, _focus);
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

/// Los idiomas que se pueden elegir, con «Sistema» primero.
const List<String> _languageCodes = [_systemCode, 'es', 'ca', 'en'];

/// El idioma que usa la app cuando sigue al del móvil.
String _systemLanguage(AppLocalizations l10n) {
  final resolved = basicLocaleListResolution(
    WidgetsBinding.instance.platformDispatcher.locales,
    AppLocalizations.supportedLocales,
  );
  return _languageName(l10n, resolved.languageCode);
}

/// Elige el idioma: en una ventana de escritorio con ratón, un desplegable
/// anclado a la fila (pegado a su lado derecho, donde se lee el valor); en el
/// móvil y con el dedo, la hoja ([showLanguageSheet]).
Future<String?> _pickLanguage(
  BuildContext context,
  AppLocalizations l10n,
  String? current,
  FocusNode returnFocusTo,
) {
  if (!usesAnchoredPicker(context)) {
    return showLanguageSheet(context, current: current);
  }
  return showAnchoredPicker<String>(
    context,
    label: l10n.settingsLanguage,
    selected: current ?? _systemCode,
    options: [
      for (final code in _languageCodes)
        PickerOption<String>(
          value: code,
          label: _languageName(l10n, code),
          hint: code == _systemCode
              ? l10n.settingsLanguageSystemNow(_systemLanguage(l10n))
              : null,
        ),
    ],
    maxWidth: 320,
    alignEnd: true,
    returnFocusTo: returnFocusTo,
  );
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
                  for (final code in _languageCodes)
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
