import 'package:flutter/widgets.dart';

/// El largo (en caracteres que se ven) a partir del cual un título citado en un
/// aviso o un diálogo se acorta.
const int kQuotedTitleMax = 60;

/// [title] acortado con «…» para citarlo entre comillas en un aviso o un
/// diálogo (QA 1.0.7, c2): un título de 300 caracteres no debe hacer el aviso
/// tan alto como la pantalla. Corta por caracteres que se ven (no parte un
/// emoji ni una letra con tilde) y sin el espacio final.
String quotedTitle(String title, {int max = kQuotedTitleMax}) {
  final text = title.trim();
  final chars = text.characters;
  if (chars.length <= max) return text;
  return '${chars.take(max - 1).toString().trimRight()}…';
}
