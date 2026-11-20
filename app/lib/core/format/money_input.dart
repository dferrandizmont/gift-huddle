import 'package:flutter/services.dart';

import 'money.dart';

/// El teclado de un campo de importe: números con decimales.
const TextInputType moneyKeyboard = TextInputType.numberWithOptions(
  decimal: true,
);

final RegExp _invalidMoneyCharacter = RegExp(r'[^0-9.,\s€-]');

/// Rechaza la edición entera si contiene algo distinto de cifras, separadores,
/// espacios, el euro o el signo menos (que `parseCents` rechaza con su aviso).
final List<TextInputFormatter> moneyInputFormatters = [
  TextInputFormatter.withFunction(
    (oldValue, newValue) =>
        _invalidMoneyCharacter.hasMatch(newValue.text) ? oldValue : newValue,
  ),
];

/// Un importe en céntimos escrito para un campo de importe: «12» si es
/// redondo y «12,50» (en `en`, «12.50») si no. Lo contrario de `parseCents`.
String centsInputText(int cents, String languageCode) {
  final euros = cents ~/ 100;
  final rest = cents % 100;
  if (rest == 0) {
    return '$euros';
  }
  final sep = languageCode == 'en' ? '.' : ',';
  return '$euros$sep${rest.toString().padLeft(2, '0')}';
}

/// Lee lo escrito en un campo de importe: `null` si está vacío o no vale.
/// [valid] dice si lo que hay vale (vacío vale).
({int? cents, bool valid}) readMoneyField(String text, String languageCode) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return (cents: null, valid: true);
  }
  final cents = parseCents(trimmed, locale: languageCode);
  return (cents: cents, valid: cents != null);
}
