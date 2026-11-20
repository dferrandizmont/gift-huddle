import 'package:intl/intl.dart';

import '../sync/model.dart';

/// Un importe en céntimos escrito para el idioma: «72,94 €», «31 €».
///
/// Los importes redondos van sin decimales, como en las maquetas.
String formatCents(int cents, String locale) {
  final whole = cents % 100 == 0;
  return NumberFormat.currency(
    locale: locale,
    symbol: '€',
    decimalDigits: whole ? 0 : 2,
  ).format(cents / 100);
}

final RegExp _plain = RegExp(r'^\d+$');
final RegExp _decimal = RegExp(r'^(\d*)[.,](\d{1,2})$');
final RegExp _dotThousands = RegExp(r'^(\d{1,3}(?:\.\d{3})+)(?:,(\d{1,2}))?$');
final RegExp _commaThousands = RegExp(
  r'^(\d{1,3}(?:,\d{3})+)(?:\.(\d{1,2}))?$',
);
final RegExp _spaceThousands = RegExp(
  r'^(\d{1,3}(?:[ \u00a0\u202f]\d{3})+)(?:[.,](\d{0,2}))?$',
);

final RegExp _trailingSeparator = RegExp(
  r'^(\d+|\d{1,3}(?:\.\d{3})+|\d{1,3}(?:,\d{3})+)([.,])$',
);

/// El separador decimal de [locale] («,» en es y ca, «.» en en).
String decimalSeparatorOf(String locale) =>
    // Sin `try`: dart2wasm deja un `unreachable` suelto en los que vuelven en
    // todas sus ramas y la guarda de `tool/check_wasm_unreachable.sh` lo cuenta.
    NumberFormat.localeExists(locale)
    ? NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP
    : ',';

/// Lee un importe escrito a mano y lo devuelve en céntimos.
///
/// Acepta «12», «12,5», «12.50», «1.234,56», «1,234.56» y «1 234,56», con o
/// sin el euro al principio o al final, y con el separador al final («12,»).
/// Los espacios de millares (normal o de no separación) separan grupos de tres
/// cifras. La coma y el punto sirven como separador decimal.
///
/// Un solo separador con tres cifras detrás («1.234») es un millar; si se da
/// [locale], solo cuando ese separador es el de millares de ese idioma («1.234»
/// en es, «1,234» en en): el decimal de su idioma con tres cifras no es un
/// importe. Devuelve `null` si no es un importe válido, es negativo o se pasa
/// del máximo.
int? parseCents(String input, {String? locale}) {
  var text = input.trim();
  if (text.startsWith('€')) {
    text = text.substring(1).trimLeft();
  } else if (text.endsWith('€')) {
    text = text.substring(0, text.length - 1).trimRight();
  }
  String whole;
  String decimals = '';
  RegExpMatch? match;
  if (_plain.hasMatch(text)) {
    whole = text;
  } else if ((match = _trailingSeparator.firstMatch(text)) != null) {
    final group = match!.group(1)!;
    if (group.contains(match.group(2)!)) return null;
    whole = group.replaceAll(RegExp(r'[.,]'), '');
  } else if ((match = _dotThousands.firstMatch(text)) != null ||
      (match = _commaThousands.firstMatch(text)) != null) {
    final group = match!.group(1)!;
    // Un solo separador sin decimales detrás: con el idioma delante, vale
    // como millar solo si es el de millares.
    if (locale != null &&
        match.group(2) == null &&
        RegExp(r'[.,]').allMatches(group).length == 1 &&
        group.contains(decimalSeparatorOf(locale))) {
      return null;
    }
    whole = group.replaceAll(RegExp(r'[.,]'), '');
    decimals = match.group(2) ?? '';
  } else if ((match = _decimal.firstMatch(text)) != null) {
    whole = match!.group(1)!.isEmpty ? '0' : match.group(1)!;
    decimals = match.group(2)!;
  } else if ((match = _spaceThousands.firstMatch(text)) != null) {
    whole = match!.group(1)!.replaceAll(RegExp(r'\s'), '');
    decimals = match.group(2) ?? '';
  } else {
    return null;
  }
  final euros = int.tryParse(whole);
  if (euros == null || euros > kMaxCents ~/ 100) {
    return null;
  }
  final cents =
      euros * 100 +
      (decimals.isEmpty ? 0 : int.parse(decimals.padRight(2, '0')));
  return cents > kMaxCents ? null : cents;
}
