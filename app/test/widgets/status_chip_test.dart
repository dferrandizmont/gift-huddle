import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/status_chip.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('muestra el nombre del estado en cada idioma', (tester) async {
    await pumpThemed(tester, const StatusChip(status: GiftStatus.wrapped));
    expect(find.text('Envuelto'), findsOneWidget);

    await pumpThemed(
      tester,
      const StatusChip(status: GiftStatus.wrapped),
      locale: const Locale('ca'),
    );
    expect(find.text('Embolicat'), findsOneWidget);

    await pumpThemed(
      tester,
      const StatusChip(status: GiftStatus.wrapped),
      locale: const Locale('en'),
    );
    expect(find.text('Wrapped'), findsOneWidget);
  });

  testWidgets('con onTap la zona táctil mide 44 px de alto', (tester) async {
    var taps = 0;
    await pumpThemed(
      tester,
      StatusChip(status: GiftStatus.bought, onTap: () => taps++),
    );
    final box = tester.getSize(
      find
          .ancestor(
            of: find.byType(InkWell),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(box.height, greaterThanOrEqualTo(44));
    await tester.tap(find.text('Comprado'));
    expect(taps, 1);
  });

  testWidgets('seleccionado lo dice en Semantics y no solo en color', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpThemed(
      tester,
      StatusChip(status: GiftStatus.bought, selected: true, onTap: () {}),
    );
    expect(
      tester.getSemantics(find.byType(StatusChip)),
      matchesSemantics(
        label: 'Comprado',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('no se rompe con el texto al 130 %', (tester) async {
    await pumpThemed(
      tester,
      const StatusChip(status: GiftStatus.delivered),
      textScale: 1.3,
      surfaceSize: const Size(200, 400),
    );
    expect(tester.takeException(), isNull);
  });
}
