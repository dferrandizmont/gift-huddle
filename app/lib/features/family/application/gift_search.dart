import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/model.dart';
import 'family_providers.dart';

const String _from = 'áàâäãåéèêëíìîïóòôöõúùûüñçÁÀÂÄÃÅÉÈÊËÍÌÎÏÓÒÔÖÕÚÙÛÜÑÇ';
const String _to = 'aaaaaaeeeeiiiiooooouuuuncAAAAAAEEEEIIIIOOOOOUUUUNC';

/// [text] en minúsculas y sin tildes ni diéresis, para comparar lo escrito en
/// el buscador con los textos de los regalos sin que importen las mayúsculas
/// («regalo» encuentra «Regalo»; «camion» encuentra «Camión»).
String searchFold(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0x0300 && rune <= 0x036f) continue;
    final char = String.fromCharCode(rune);
    final at = _from.indexOf(char);
    out.write(at < 0 ? char : _to[at]);
  }
  return out.toString().toLowerCase();
}

/// Si [gift] (de [personName]) casa con [query]: cada palabra escrita tiene que
/// aparecer en el nombre del regalo, en su nota, en la tienda o en el nombre de
/// la persona. Sin palabras, no casa nada.
bool giftMatchesQuery(Gift gift, String? personName, String query) {
  final terms = searchFold(query)
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (terms.isEmpty) {
    return false;
  }
  final haystack = searchFold(
    [
      gift.title,
      gift.note,
      gift.store,
      personName,
    ].whereType<String>().join('\n'),
  );
  return terms.every(haystack.contains);
}

/// Los regalos de las personas activas que casan con [query], por orden de
/// persona y de título.
final giftSearchProvider = Provider.autoDispose.family<List<Gift>, String>((
  ref,
  query,
) {
  final view = ref.watch(familyViewProvider);
  final names = {for (final r in view.recipients) r.id: r.name};
  return [
    for (final gift in view.gifts)
      if (names.containsKey(gift.recipientId) &&
          giftMatchesQuery(gift, names[gift.recipientId], query))
        gift,
  ];
});
