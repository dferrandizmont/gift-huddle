import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';

int oldDistance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = min(min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost);
    }
    final swap = previous; previous = current; current = swap;
  }
  return previous[b.length];
}
bool oldSimilar(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  final shorter = a.length <= b.length ? a : b;
  final longer = a.length <= b.length ? b : a;
  if (shorter.length >= 5 && longer.contains(shorter)) return true;
  final threshold = shorter.length < 8 ? 1 : shorter.length <= 14 ? 2 : 3;
  if (longer.length - shorter.length > threshold) return false;
  if (a.codeUnitAt(0) != b.codeUnitAt(0)) return false;
  return oldDistance(a, b) <= threshold;
}
List<(String, String, String)> oldPairs(FamilyView view) {
  final result = <(String, String, String)>[];
  for (final person in view.recipients) {
    final gifts = view.giftsFor(person.id);
    for (var i = 0; i < gifts.length; i++) {
      for (var j = i + 1; j < gifts.length; j++) {
        if (oldSimilar(_normalizeTitle(gifts[i].title), _normalizeTitle(gifts[j].title))) {
          result.add((person.id, gifts[i].id, gifts[j].id));
        }
      }
    }
  }
  return result;
}
FamilyView makeView(List<String> titles) => FamilyView(
  recipients: [for (var i = 0; i < 3; i++) Recipient(id: 'r$i', name: ['Aritz', 'Nora', 'Leo'][i], colorIndex: i, archived: false)],
  givers: [], occasions: [],
  gifts: [for (var i = 0; i < titles.length; i++) Gift(id: 'g$i', recipientId: 'r${i % 3}', title: titles[i], status: GiftStatus.idea, rawStatus: 'idea', surprise: false, year: 2026)],
);
List<(String, String, String)> actual(FamilyView view) => [
  for (final pair in view.possibleDuplicates()) (pair.recipientId, pair.first.id, pair.second.id),
];
void main() {
  test('límites, igualdad y contención con distinta inicial', () {
    for (final titles in [
      ['', '', ' ', ''], ['ABCDE', 'nada', 'nada', 'xxABCDEyy'],
      ['abcde', 'x', 'x', 'abcdf'], ['abcdefgh', 'x', 'x', 'abcdexyz'],
      ['abcdefghijklmnop', 'x', 'x', 'abcdefghijklmxyz'],
      ['Cámara', 'x', 'x', 'camara'], ['😀abcde', 'x', 'x', 'z😀abcde'],
    ]) {
      final view = makeView(titles);
      expect(actual(view), oldPairs(view), reason: '$titles');
    }
    expect(actual(makeView(['ABCDE', 'x', 'x', 'xxABCDEyy'])), hasLength(1));
  });
  test('equivalencia aleatoria con la implementación anterior', () {
    final random = Random(7319);
    const alphabet = 'abcde éß';
    for (var run = 0; run < 80; run++) {
      final titles = <String>[];
      for (var i = 0; i < 45; i++) {
        if (titles.isNotEmpty && random.nextInt(3) == 0) {
          final base = titles[random.nextInt(titles.length)];
          titles.add(random.nextBool() ? '${base}abc' : 'x$base');
        } else {
          titles.add(List.generate(random.nextInt(20), (_) => alphabet[random.nextInt(alphabet.length)]).join());
        }
      }
      final view = makeView(titles);
      expect(actual(view), oldPairs(view), reason: 'run $run');
    }
  });
  test('tres personas con 300 regalos parecidos', () {
    final view = makeView(List.generate(900, (i) => 'regalo parecido número ${i ~/ 3}'));
    expect(actual(view), isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

String _normalizeTitle(String title) {
  final buffer = StringBuffer();
  for (final rune in title.toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    final plain = _accents[character] ?? character;
    for (final plainRune in plain.runes) {
      if (!_isWhitespace(plainRune)) {
        buffer.writeCharCode(plainRune);
      }
    }
  }
  return buffer.toString();
}

/// Whether the rune is a space or a tab.
bool _isWhitespace(int rune) =>
    rune == 0x20 || rune == 0x09 || rune == 0x0a || rune == 0x0d;

/// The letters of the latin alphabet with their accent.
const Map<String, String> _accents = <String, String>{
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'ē': 'e',
  'ę': 'e',
  'ė': 'e',
  'ě': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ī': 'i',
  'į': 'i',
  'ı': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ø': 'o',
  'ō': 'o',
  'ő': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ū': 'u',
  'ů': 'u',
  'ű': 'u',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ņ': 'n',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'ý': 'y',
  'ÿ': 'y',
  'š': 's',
  'ś': 's',
  'ş': 's',
  'ș': 's',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
  'ď': 'd',
  'đ': 'd',
  'ð': 'd',
  'þ': 'th',
  'ł': 'l',
  'ĺ': 'l',
  'ļ': 'l',
  'ŀ': 'l',
  'ğ': 'g',
  'ģ': 'g',
  'ĝ': 'g',
  'ġ': 'g',
  'ħ': 'h',
  'ĥ': 'h',
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
  'µ': 'u',
};

