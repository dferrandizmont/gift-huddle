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

/// Lee un importe escrito a mano y lo devuelve en céntimos.
///
/// Acepta «12», «12,5», «12.50», «1.234,56» y «1,234.56», con o sin el
/// símbolo del euro. Un solo separador con tres cifras detrás («1.234») es un
/// millar. Devuelve `null` si no es un importe válido, es negativo o se pasa
/// del máximo.
int? parseCents(String input) {
  final text = input.replaceAll('€', '').replaceAll(RegExp(r'\s'), '');
  String whole;
  String decimals = '';
  RegExpMatch? match;
  if (_plain.hasMatch(text)) {
    whole = text;
  } else if ((match = _dotThousands.firstMatch(text)) != null ||
      (match = _commaThousands.firstMatch(text)) != null) {
    whole = match!.group(1)!.replaceAll(RegExp(r'[.,]'), '');
    decimals = match.group(2) ?? '';
  } else if ((match = _decimal.firstMatch(text)) != null) {
    whole = match!.group(1)!.isEmpty ? '0' : match.group(1)!;
    decimals = match.group(2)!;
  } else {
    return null;
  }
  final euros = int.tryParse(whole);
  if (euros == null) {
    return null;
  }
  final cents =
      euros * 100 +
      (decimals.isEmpty ? 0 : int.parse(decimals.padRight(2, '0')));
  return cents > kMaxCents ? null : cents;
}
