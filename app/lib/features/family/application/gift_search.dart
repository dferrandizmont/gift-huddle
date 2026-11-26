import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/model.dart';
import '../../../core/sync/wish.dart';
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

/// Si [wish] (de [personName]) casa con [query]: cada palabra escrita tiene
/// que aparecer en el título, la descripción o el enlace del deseo, o en el
/// nombre de la persona. Solo mira lo visible: lo que otros apuntan (tienda,
/// notas) está en el plan, no aquí.
bool wishMatchesQuery(Wish wish, String? personName, String query) {
  final terms = searchFold(query)
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (terms.isEmpty) {
    return false;
  }
  final haystack = searchFold(
    [
      wish.title,
      wish.description,
      wish.url,
      personName,
    ].whereType<String>().join('\n'),
  );
  return terms.every(haystack.contains);
}

/// Lo que encuentra el buscador: los regalos y los deseos que todavía no son
/// un regalo para este lector.
class SearchResults {
  /// Crea el resultado.
  const SearchResults({required this.gifts, required this.wishes});

  /// Los regalos que casan. Entre ellos, los planes (vistos como regalo) de
  /// un lector autorizado, también cuando casa el texto de su deseo.
  final List<Gift> gifts;

  /// Los deseos que casan y que no tienen plan en este móvil: la fila del
  /// deseo y la de su plan nunca salen las dos.
  final List<Wish> wishes;
}

/// Regalos y deseos de las personas activas que casan con [query].
///
/// Los deseos se buscan por título, descripción y enlace para cualquier
/// lector. La tienda y las notas de quien regala solo existen en los planes
/// de los bloques que este móvil abre, así que solo ahí se buscan. Un deseo
/// con plan sale una vez, como su plan.
final searchResultsProvider = Provider.autoDispose
    .family<SearchResults, String>((ref, query) {
      final view = ref.watch(familyViewProvider);
      final names = {for (final r in view.recipients) r.id: r.name};
      final wishById = {for (final w in view.allVisibleWishes) w.id: w};
      // El móvil lleva los planes en su proyección; la web, en su motor.
      final plansByWish = {
        ...view.plansByWish,
        ...ref.watch(webWishPlansProvider),
      };
      final wishOfPlan = <String, Wish>{
        for (final e in plansByWish.entries)
          for (final plan in e.value)
            if (wishById[e.key] case final Wish wish) plan.planId: wish,
      };
      bool giftFound(Gift gift) {
        final name = names[gift.recipientId];
        if (giftMatchesQuery(gift, name, query)) return true;
        final wish = wishOfPlan[gift.id];
        return wish != null && wishMatchesQuery(wish, name, query);
      }

      return SearchResults(
        gifts: [
          for (final gift in [
            ...view.gifts,
            for (final person in names.keys)
              ...ref.watch(webPlanGiftsProvider(person)),
          ])
            if (names.containsKey(gift.recipientId) && giftFound(gift)) gift,
        ],
        wishes: [
          for (final wish in view.visibleWishes)
            if (names.containsKey(wish.recipientId) &&
                (plansByWish[wish.id]?.isEmpty ?? true) &&
                wishMatchesQuery(wish, names[wish.recipientId], query))
              wish,
        ],
      );
    });

/// Los regalos de las personas activas que casan con [query], por orden de
/// persona y de título (con los planes de deseos de un lector autorizado).
final giftSearchProvider = Provider.autoDispose.family<List<Gift>, String>(
  (ref, query) => ref.watch(searchResultsProvider(query)).gifts,
);
