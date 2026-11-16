import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/status_checkbox.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('mide 44 px o más y avisa del toque', (tester) async {
    var taps = 0;
    await pumpThemed(
      tester,
      StatusCheckbox(
        status: GiftStatus.bought,
        itemName: 'Patinete',
        onTap: () => taps++,
      ),
    );
    final size = tester.getSize(find.byType(StatusCheckbox));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    await tester.tap(find.byType(StatusCheckbox));
    expect(taps, 1);
  });

  testWidgets(
    'una pulsación de 400 ms abre el selector y no cuenta como toque',
    (tester) async {
      var taps = 0;
      var longs = 0;
      await pumpThemed(
        tester,
        StatusCheckbox(
          status: GiftStatus.bought,
          itemName: 'Patinete',
          onTap: () => taps++,
          onLongPress: () => longs++,
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(StatusCheckbox)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pump();
      expect(longs, 1);
      expect(taps, 0);
      // Un toque corto sigue siendo un toque.
      await tester.tap(find.byType(StatusCheckbox));
      expect(taps, 1);
      expect(longs, 1);
    },
  );

  testWidgets('Semantics dice el regalo y el estado en español', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpThemed(
      tester,
      StatusCheckbox(
        status: GiftStatus.arrived,
        itemName: 'Patinete',
        onTap: () {},
      ),
    );
    expect(
      find.bySemanticsLabel('Cambiar estado de Patinete. Estado actual: Llegó'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('sin onTap solo informa del estado', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpThemed(
      tester,
      const StatusCheckbox(status: GiftStatus.idea, itemName: 'Patinete'),
      locale: const Locale('en'),
    );
    expect(find.bySemanticsLabel('Status: Idea'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('cada estado dibuja una forma distinta', (tester) async {
    // El estado no puede depender solo del color: comparamos los fotogramas.
    final shots = <String>[];
    for (final status in GiftStatus.values) {
      final key = GlobalKey();
      await pumpThemed(
        tester,
        RepaintBoundary(
          key: key,
          child: StatusGlyph(status: status, size: 48),
        ),
      );
      final image = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await boundary.toImage();
        final data = await img.toByteData();
        return data!.buffer.asUint8List().join(',');
      });
      shots.add(image!);
    }
    expect(shots.toSet().length, GiftStatus.values.length);
  });

  test('el relleno crece con el avance del estado', () {
    final fills = GiftStatus.values.map((s) => s.fill).toList();
    expect(fills, [0, 0, 0.25, 0.5, 0.75, 1]);
  });
}
