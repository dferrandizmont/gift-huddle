// La fila de un deseo (opción A, revisión del 26-11): «Lo regalo yo» compacto a
// la derecha, en la columna del estado en tablet, con su etiqueta para el
// lector de pantalla, sin «Nadie lo ha cogido» cuando hay botón y con el botón
// debajo (nunca recortado) con letra grande.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/accent_palette.dart';
import 'package:regalos/core/widgets/gift_row.dart';
import 'package:regalos/core/widgets/wish_row.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

WishRow _row({
  Future<bool> Function()? onAction,
  bool action = true,
  String? stateText = 'Nadie lo ha cogido',
  bool warning = false,
  double? columnsFrom,
  String title = 'Bicicleta con ruedines',
  String? detail = 'Rueda de 14 pulgadas',
}) => WishRow(
  title: title,
  detail: detail,
  stateText: stateText,
  warning: warning,
  actionLabel: action ? 'Lo regalo yo' : null,
  onAction: action ? (onAction ?? () async => true) : null,
  onTap: () {},
  accent: AccentId.lavender.palette,
  columnsFrom: columnsFrom,
);

Finder get _button => find.byType(FilledButton);

void main() {
  setUpAll(loadInter);

  testWidgets(
    'en el móvil mide como una fila de regalo y el botón va a la derecha, en '
    'la línea del título, sin «Nadie lo ha cogido»',
    (tester) async {
      await pumpThemed(tester, _row());
      final row = tester.getRect(find.byType(WishRow));
      expect(row.height, lessThan(70), reason: 'antes medía 115');
      final title = tester.getRect(find.text('Bicicleta con ruedines'));
      final button = tester.getRect(_button);
      // A la derecha del título y centrado con la fila.
      expect(button.left, greaterThan(title.right));
      expect((button.center.dy - row.center.dy).abs(), lessThan(8));
      // Pegado al margen derecho (16), como el precio de una fila de regalo.
      expect(row.right - button.right, closeTo(16, 1));
      expect(find.text('Nadie lo ha cogido'), findsNothing);
      // La segunda línea: «Deseo» y el detalle.
      expect(find.text('Deseo'), findsOneWidget);
      expect(find.textContaining('Rueda de 14 pulgadas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('el botón mide 36 de alto y su zona táctil 48 × 48 como mínimo', (
    tester,
  ) async {
    await pumpThemed(tester, _row());
    final tap = tester.getSize(_button);
    expect(tap.height, greaterThanOrEqualTo(48));
    expect(tap.width, greaterThanOrEqualTo(48));
    final visual = tester.getSize(
      find.descendant(of: _button, matching: find.byType(Material)).first,
    );
    expect(visual.height, kWishActionHeight);
    // Tonal: relleno pastel de la persona y radio 8.
    final material = tester.widget<Material>(
      find.descendant(of: _button, matching: find.byType(Material)).first,
    );
    expect(material.color, AccentId.lavender.palette.pastel);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('el lector de pantalla lee «Lo regalo yo: título» y el texto '
      'de la fila aparte, con el estado', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpThemed(tester, _row());
    expect(
      find.bySemanticsLabel('Lo regalo yo: Bicicleta con ruedines'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Lo regalo yo'), findsNothing);
    final text = find.bySemanticsLabel(
      RegExp('Bicicleta con ruedines\\. Deseo.*Nadie lo ha cogido'),
    );
    expect(text, findsOneWidget);
    expect(
      tester.getTopLeft(text).dx,
      lessThanOrEqualTo(
        tester
            .getTopLeft(
              find.bySemanticsLabel('Lo regalo yo: Bicicleta con ruedines'),
            )
            .dx,
      ),
    );
    handle.dispose();
  });

  testWidgets('con letra grande el botón cae debajo del texto y no se '
      'recorta', (tester) async {
    for (final scale in [1.5, 2.0]) {
      await pumpThemed(tester, _row(), textScale: scale);
      final title = tester.getRect(find.text('Bicicleta con ruedines'));
      final button = tester.getRect(_button);
      expect(
        button.top,
        greaterThanOrEqualTo(title.bottom - 1),
        reason: 'x$scale: debajo del título',
      );
      // Entero dentro de la pantalla y de la fila.
      final row = tester.getRect(find.byType(WishRow));
      expect(button.left, greaterThanOrEqualTo(row.left));
      expect(button.right, lessThanOrEqualTo(row.right));
      // La etiqueta cabe en su botón (no se recorta ni se parte).
      final label = tester.getRect(find.text('Lo regalo yo'));
      expect(label.right, lessThanOrEqualTo(button.right));
      expect(label.height, lessThan(40 * scale));
      expect(tester.takeException(), isNull, reason: 'x$scale');
    }
  });

  testWidgets('con poco ancho (320) y letra normal el botón sigue sin '
      'recortarse', (tester) async {
    await pumpThemed(
      tester,
      _row(title: 'Estación de bomberos de bloques grandes'),
      surfaceSize: const Size(320, 600),
    );
    final row = tester.getRect(find.byType(WishRow));
    final button = tester.getRect(_button);
    expect(button.right, lessThanOrEqualTo(row.right));
    expect(button.left, greaterThanOrEqualTo(row.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('en tablet va en columnas: el botón en la columna del estado, '
      'sin hueco bajo el título', (tester) async {
    await pumpThemed(
      tester,
      _row(columnsFrom: 720),
      surfaceSize: const Size(1000, 700),
    );
    final row = tester.getRect(find.byType(WishRow));
    final button = tester.getRect(_button);
    final title = tester.getRect(find.text('Bicicleta con ruedines'));
    // En la columna del estado: pasada la de quién regala y la del precio.
    expect(
      button.left,
      greaterThan(row.right - 16 - GiftRow.statusColumn - 8 - 4),
    );
    expect(button.right, lessThanOrEqualTo(row.right - 16));
    expect((button.center.dy - title.center.dy).abs(), lessThan(30));
    expect(row.height, lessThan(70));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tocar el botón llama a la acción y deja paso al estado; si '
      'falla, el botón vuelve', (tester) async {
    var taps = 0;
    var ok = true;
    await pumpThemed(
      tester,
      _row(
        onAction: () async {
          taps++;
          return ok;
        },
      ),
    );
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(_button, findsNothing);
    expect(find.text('Lo has cogido tú'), findsOneWidget);
  });

  testWidgets('si coger falla, el botón vuelve', (tester) async {
    await pumpThemed(tester, _row(onAction: () async => false));
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(_button, findsOneWidget);
    expect(find.text('Lo has cogido tú'), findsNothing);
  });

  testWidgets('sin botón se ve el estado; un aviso se ve siempre', (
    tester,
  ) async {
    await pumpThemed(tester, _row(action: false));
    expect(find.text('Nadie lo ha cogido'), findsOneWidget);
    expect(_button, findsNothing);
    await pumpThemed(
      tester,
      _row(stateText: 'Dos personas lo han cogido', warning: true),
    );
    expect(find.text('Dos personas lo han cogido'), findsOneWidget);
    expect(_button, findsOneWidget);
  });

  testWidgets('al pulsar el botón se encoge a 0,96; con «Reducir movimiento» '
      'no escala', (tester) async {
    for (final reduce in [false, true]) {
      await pumpThemed(tester, _row(), disableAnimations: reduce);
      final gesture = await tester.startGesture(tester.getCenter(_button));
      await tester.pump(const Duration(milliseconds: 100));
      final scale = tester
          .widget<AnimatedScale>(
            find.ancestor(of: _button, matching: find.byType(AnimatedScale)),
          )
          .scale;
      expect(scale, reduce ? 1 : 0.96, reason: 'reduce: $reduce');
      await gesture.cancel();
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'con letra ×2 «Lo has cogido tú» no se encoge: sigue en otra línea '
    'y el texto de la fila no se solapa con el botón',
    (tester) async {
      await pumpThemed(tester, _row(), textScale: 2);
      // El área táctil del texto (su InkWell) y la del botón no se pisan.
      final inkWell = tester.getRect(
        find
            .descendant(
              of: find.byType(WishRow),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(
        inkWell.bottom,
        lessThanOrEqualTo(tester.getRect(_button).top + 0.5),
      );
      await tester.tap(_button);
      await tester.pumpAndSettle();
      final claimed = find.text('Lo has cogido tú');
      expect(claimed, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(WishRow),
          matching: find.byType(FittedBox),
        ),
        findsNothing,
        reason: 'la letra no se encoge por debajo de lo legible',
      );
      final paragraph = tester.renderObject<RenderParagraph>(claimed);
      expect(paragraph.textScaler.scale(13), 26, reason: 'sigue a ×2');
      final row = tester.getRect(find.byType(WishRow));
      expect(tester.getRect(claimed).right, lessThanOrEqualTo(row.right));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('con letra normal el texto de la fila acaba antes de que '
      'empiece el botón', (tester) async {
    await pumpThemed(tester, _row());
    final inkWell = tester.getRect(
      find
          .descendant(of: find.byType(WishRow), matching: find.byType(InkWell))
          .first,
    );
    expect(
      inkWell.right,
      lessThanOrEqualTo(tester.getRect(_button).left + 0.5),
    );
  });

  testWidgets('tras coger, la fila no se queda fija en «Lo has cogido tú»: si la '
      'lista la reconstruye con la misma clave y el deseo sigue libre, vuelve '
      'el botón', (tester) async {
    Future<void> pumpRow() => pumpThemed(
      tester,
      KeyedSubtree(
        key: const ValueKey('wish-w1'),
        child: _row(onAction: () async => true),
      ),
    );
    await pumpRow();
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(find.text('Lo has cogido tú'), findsOneWidget);
    // La lista reconstruye la fila (mismo estado, misma clave): sigue el estado.
    await pumpRow();
    expect(find.text('Lo has cogido tú'), findsOneWidget);
    // Pasado un momento vuelve el botón.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Lo has cogido tú'), findsNothing);
    expect(_button, findsOneWidget);
    // Y se puede volver a coger.
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(find.text('Lo has cogido tú'), findsOneWidget);
    // Si la lista ya no la ofrece (el deseo se cogió de verdad), no hay botón.
    await pumpThemed(
      tester,
      KeyedSubtree(key: const ValueKey('wish-w1'), child: _row(action: false)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(_button, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en oscuro el botón usa el relleno oscuro de la persona', (
    tester,
  ) async {
    await pumpThemed(tester, _row(), brightness: Brightness.dark);
    final material = tester.widget<Material>(
      find.descendant(of: _button, matching: find.byType(Material)).first,
    );
    expect(material.color, AccentId.lavender.palette.pastelD);
  });
}
