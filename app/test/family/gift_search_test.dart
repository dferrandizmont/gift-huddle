import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/gift_search.dart';

Gift _gift({
  String title = 'Camión de bomberos',
  String? note,
  String? store,
}) => Gift(
  id: 'g1',
  recipientId: 'aritz',
  title: title,
  status: GiftStatus.idea,
  rawStatus: 'idea',
  note: note,
  store: store,
  surprise: false,
  year: 2026,
);

void main() {
  group('searchFold', () {
    test('minúsculas y sin tildes', () {
      expect(searchFold('CAMIÓN'), 'camion');
      expect(searchFold('Muñeca'), 'muneca');
      expect(searchFold('Cuina Ça'), 'cuina ca');
    });
  });

  group('giftMatchesQuery', () {
    test('por el nombre, sin importar mayúsculas ni tildes', () {
      expect(giftMatchesQuery(_gift(), 'Aritz', 'camion'), isTrue);
      expect(giftMatchesQuery(_gift(), 'Aritz', 'BOMBEROS'), isTrue);
      expect(giftMatchesQuery(_gift(), 'Aritz', 'tren'), isFalse);
      expect(
        giftMatchesQuery(_gift(title: 'Camio\u0301n'), 'Aritz', 'camion'),
        isTrue,
      );
      expect(
        giftMatchesQuery(_gift(title: 'Camión'), 'Aritz', 'camio\u0301n'),
        isTrue,
      );
    });

    test('por la nota, la tienda y la persona', () {
      final g = _gift(note: 'Con sirena', store: 'Juguettos');
      expect(giftMatchesQuery(g, 'Nora', 'sirena'), isTrue);
      expect(giftMatchesQuery(g, 'Nora', 'juguet'), isTrue);
      expect(giftMatchesQuery(g, 'Nora', 'nora'), isTrue);
      expect(giftMatchesQuery(g, 'Nora', 'leo'), isFalse);
    });

    test('todas las palabras tienen que aparecer, en cualquier campo', () {
      final g = _gift(note: 'Con sirena');
      expect(giftMatchesQuery(g, 'Nora', 'camion nora'), isTrue);
      expect(giftMatchesQuery(g, 'Nora', 'sirena  camion'), isTrue);
      expect(giftMatchesQuery(g, 'Nora', 'camion leo'), isFalse);
    });

    test('sin nada escrito no casa ningún regalo', () {
      expect(giftMatchesQuery(_gift(), 'Aritz', ''), isFalse);
      expect(giftMatchesQuery(_gift(), 'Aritz', '   '), isFalse);
    });
  });

  test('libera la consulta anterior al dejar de observarla', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final previous = giftSearchProvider('camion');
    final subscription = container.listen(previous, (_, _) {});
    final current = container.listen(giftSearchProvider('nora'), (_, _) {});
    subscription.close();
    await container.pump();
    expect(container.read(previous.exists), isFalse);
    expect(container.read(giftSearchProvider('nora').exists), isTrue);
    current.close();
  });
}
