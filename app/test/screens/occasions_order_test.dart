import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/domain/occasion_order.dart';
import 'package:regalos/features/occasions/application/occasion_rows.dart';

import '../helpers/screens.dart';

Occasion _occasion(
  String id,
  OccasionKind kind,
  int month,
  int day, {
  String name = '',
  String? recipientId,
  bool recurring = true,
  int? year,
}) => Occasion(
  id: id,
  kind: kind,
  rawKind: kind.name,
  name: name,
  month: month,
  day: day,
  year: year,
  recurring: recurring,
  recipientId: recipientId,
  archived: false,
);

void main() {
  // Hoy es el 9 de noviembre de 2026.
  screenTest('Ocasiones va por días, sin grupos, en el mismo orden que Hoy', (
    tester,
    phone,
  ) async {
    await bareFamily(tester, phone);
    await tester.runAsync(() async {
      final c = familyOf(phone);
      await c.upsertRecipient(
        const Recipient(id: 'leo', name: 'Leo', colorIndex: 0, archived: false),
      );
      // Desordenadas a propósito: la fecha manda, no el tipo.
      await c.upsertOccasion(_occasion('kings', OccasionKind.kings, 12, 27));
      await c.upsertOccasion(
        _occasion(
          'past',
          OccasionKind.custom,
          3,
          1,
          name: 'Comunión',
          recurring: false,
          year: 2026,
        ),
      );
      await c.upsertOccasion(_occasion('xmas', OccasionKind.santa, 12, 15));
      await c.upsertOccasion(_occasion('tio', OccasionKind.tio, 12, 14));
      await c.upsertOccasion(
        _occasion('leo', OccasionKind.birthday, 11, 19, recipientId: 'leo'),
      );
    });
    await pumpRegalos(tester, phone);
    await tester.tap(find.text('Ocasiones').last);
    await settle(tester);

    final shown = <String, double>{
      'leo': tester.getTopLeft(find.text('Cumpleaños de Leo')).dy,
      'tio': tester.getTopLeft(find.text('Tió')).dy,
      'xmas': tester.getTopLeft(find.text('Navidad')).dy,
      'kings': tester.getTopLeft(find.text('Reyes')).dy,
      'past': tester.getTopLeft(find.text('Comunión')).dy,
    };
    final onScreen = (shown.keys.toList()
      ..sort((a, b) => shown[a]!.compareTo(shown[b]!)));
    expect(onScreen, ['leo', 'tio', 'xmas', 'kings', 'past']);

    // Sin cabeceras de grupo.
    expect(find.text('Fiestas'), findsNothing);
    expect(find.text('Cumpleaños'), findsNothing);

    // Hoy: el mismo orden (la que ya pasó no está en la cuenta atrás).
    final today = [
      for (final next in phone.container.read(upcomingOccasionsProvider))
        next.occasion.id,
    ];
    expect(today, ['leo', 'tio', 'xmas', 'kings']);
    expect(onScreen.take(today.length), today);
  }, size: const Size(390, 1900));

  test('solo con ocasiones pasadas, la primera es la primera por nombre', () {
    final now = DateTime(2026, 11, 9, 10);
    final viaje = _occasion(
      'a',
      OccasionKind.custom,
      3,
      1,
      name: 'Viaje',
      recurring: false,
      year: 2026,
    );
    final aniversario = _occasion(
      'z',
      OccasionKind.custom,
      2,
      1,
      name: 'Aniversario',
      recurring: false,
      year: 2026,
    );
    expect(
      occasionsByDaysLeft(
        [viaje, aniversario],
        now,
        includePassed: true,
      ).map((o) => o.id),
      ['z', 'a'],
    );
    expect(nextOccasionRowId([viaje, aniversario], now), 'z');
  });
}
