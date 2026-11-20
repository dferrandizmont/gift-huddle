import 'package:flutter/material.dart' show InkWell;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/gift_row.dart';
import 'package:regalos/core/widgets/link_icon_button.dart';

import '../helpers/pump_app.dart';

void main() {
  testWidgets('muestra nombre, quien regala, precio y estado', (tester) async {
    await pumpThemed(
      tester,
      const GiftRow(
        name: 'Estación de bomberos de bloques',
        giverName: 'Nosotros',
        giverColorIndex: 0,
        price: '49,99 €',
        status: GiftStatus.bought,
      ),
    );
    expect(find.text('Estación de bomberos de bloques'), findsOneWidget);
    expect(find.text('Nosotros'), findsOneWidget);
    expect(find.text('49,99 €'), findsOneWidget);
    expect(find.text('Comprado'), findsOneWidget);
  });

  testWidgets('la casilla de estado avisa del toque', (tester) async {
    var taps = 0;
    await pumpThemed(
      tester,
      GiftRow(
        name: 'Patinete',
        giverName: 'Sin asignar',
        status: GiftStatus.idea,
        onStatusTap: () => taps++,
      ),
    );
    await tester.tap(
      find.bySemanticsLabel(RegExp('Cambiar estado de Patinete')),
    );
    expect(taps, 1);
  });

  testWidgets('la fila mide al menos 60 px y no desborda al 130 %', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      const GiftRow(
        name: 'Libro de dinosaurios con solapas y pegatinas',
        giverName: 'Tía Marta y Jordi',
        giverColorIndex: 1,
        price: '18 €',
        note: 'Lo pidió Aritz',
        status: GiftStatus.decided,
      ),
      textScale: 1.3,
      surfaceSize: const Size(320, 600),
    );
    expect(
      tester.getSize(find.byType(GiftRow)).height,
      greaterThanOrEqualTo(60),
    );
    expect(tester.takeException(), isNull);
  });

  // Un precio no se corta ni se parte: lo que mide su caja pintada tiene que
  // ser, como poco, lo que necesita el texto en una sola línea (un `Text` sin
  // salto recortado por el ancho sigue sin avisar de nada).
  void expectWhole(WidgetTester tester, String amount) {
    final finder = find.text(amount);
    expect(finder, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    final needed = painter.width;
    final oneLine = painter.height;
    painter.dispose();
    expect(
      paragraph.size.width,
      greaterThanOrEqualTo(needed - 0.5),
      reason:
          'el precio se queda corto: necesita $needed y tiene '
          '${paragraph.size.width}',
    );
    expect(
      paragraph.size.height,
      lessThanOrEqualTo(oneLine + 0.5),
      reason: 'el precio se parte en varias líneas',
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    final row = tester.getRect(find.byType(GiftRow));
    expect(tester.getRect(finder).right, lessThanOrEqualTo(row.right));
  }

  final longName = List.filled(200, 'x').join();
  const amount = '99999,99 €';

  for (final scale in const [1.0, 1.5, 2.0]) {
    testWidgets('en columnas el precio nunca se corta ($scale)', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        GiftRow(
          name: longName,
          giverName: 'Nosotros',
          giverColorIndex: 0,
          price: amount,
          status: GiftStatus.bought,
          columnsFrom: 400,
        ),
        textScale: scale,
        surfaceSize: const Size(900, 4000),
      );
      expect(tester.takeException(), isNull);
      expectWhole(tester, amount);
    });
  }

  for (final width in const [320.0, 390.0]) {
    testWidgets('en la ficha de $width px el precio no se parte a 2.0', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        GiftRow(
          name: longName,
          giverName: 'Nosotros',
          giverColorIndex: 0,
          price: amount,
          status: GiftStatus.bought,
        ),
        textScale: 2,
        surfaceSize: Size(width, 6000),
      );
      expect(tester.takeException(), isNull);
      expectWhole(tester, amount);
    });
  }

  testWidgets('en la ficha, con lo previsto, el importe sigue entero', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      GiftRow(
        name: longName,
        giverName: 'Nosotros',
        status: GiftStatus.bought,
        price: '$amount (previsto 55 €)',
      ),
      textScale: 2,
      surfaceSize: const Size(320, 6000),
    );
    expect(tester.takeException(), isNull);
    expectWhole(tester, amount);
    expect(find.text('previsto 55 €'), findsOneWidget);
  });

  group('enlace del regalo', () {
    testWidgets('se ve como el sitio y avisa del toque sin abrir la fila', (
      tester,
    ) async {
      var links = 0;
      var rows = 0;
      await pumpThemed(
        tester,
        GiftRow(
          name: 'Cometa',
          giverName: 'Nosotros',
          status: GiftStatus.idea,
          linkHost: 'amzn.eu',
          linkLabel: 'Abrir enlace: amzn.eu',
          onLinkTap: () => links++,
          onTap: () => rows++,
        ),
      );
      expect(find.text('amzn.eu'), findsOneWidget);
      await tester.tap(find.text('amzn.eu'));
      await tester.pump();
      expect(links, 1);
      expect(rows, 0);
      expect(find.bySemanticsLabel('Abrir enlace: amzn.eu'), findsOneWidget);
    });

    testWidgets('la fila no crece por tener enlace, ni en la ficha ni en '
        'columnas', (tester) async {
      for (final columns in [false, true]) {
        Future<double> height({required bool withLink}) async {
          await pumpThemed(
            tester,
            GiftRow(
              name: 'Cometa de seda',
              giverName: 'Nosotros',
              status: GiftStatus.idea,
              price: '18 €',
              linkHost: withLink ? 'amzn.eu' : null,
              onLinkTap: withLink ? () {} : null,
              columnsFrom: columns ? 100 : null,
            ),
            surfaceSize: columns ? const Size(900, 600) : const Size(390, 600),
          );
          return tester.getSize(find.byType(GiftRow)).height;
        }

        final without = await height(withLink: false);
        final with_ = await height(withLink: true);
        expect(with_, without, reason: 'columns=$columns');
      }
    });

    testWidgets('la zona de toque mide 44 de ancho como mínimo', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        GiftRow(
          name: 'Cometa',
          giverName: 'Nosotros',
          status: GiftStatus.idea,
          linkHost: 'a.co',
          onLinkTap: () {},
        ),
      );
      final box = tester.getSize(
        find.descendant(
          of: find.byType(GiftLinkLabel),
          matching: find.byType(InkWell),
        ),
      );
      expect(box.width, greaterThanOrEqualTo(44));
    });

    testWidgets('el «·» y el sitio largo pasan juntos y el sitio se corta', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        GiftRow(
          name: 'Cometa',
          giverName: 'Tía Marta y Jordi de Terrassa',
          status: GiftStatus.idea,
          linkHost: 'una-tienda-con-un-nombre-muy-largo.example.com',
          onLinkTap: () {},
        ),
        surfaceSize: const Size(320, 600),
      );
      final label = tester.getRect(find.byType(GiftLinkLabel));
      expect(label.width, lessThanOrEqualTo(GiftLinkLabel.maxWidth));
      // El separador está dentro del mismo grupo que el enlace.
      expect(
        find.descendant(
          of: find.byType(GiftLinkLabel),
          matching: find.text('·'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin enlace no hay marca', (tester) async {
      await pumpThemed(
        tester,
        const GiftRow(
          name: 'Cometa',
          giverName: 'Nosotros',
          status: GiftStatus.idea,
        ),
      );
      expect(find.byType(GiftLinkLabel), findsNothing);
    });

    testWidgets('con letra grande, un sitio largo no desborda', (tester) async {
      for (final columns in [false, true]) {
        await pumpThemed(
          tester,
          GiftRow(
            name: 'Cometa de seda con cola larga y colores',
            giverName: 'Tía Marta y Jordi',
            status: GiftStatus.idea,
            price: '18 €',
            linkHost: 'una-tienda-con-un-nombre-muy-largo.example.com',
            onLinkTap: () {},
            columnsFrom: columns ? 100 : null,
          ),
          textScale: 1.3,
          surfaceSize: columns ? const Size(900, 600) : const Size(320, 600),
        );
        expect(tester.takeException(), isNull, reason: 'columns=$columns');
      }
    });
  });
}
