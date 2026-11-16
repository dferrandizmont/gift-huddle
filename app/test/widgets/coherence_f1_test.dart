import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/pane_scope.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/focus_ring.dart';
import 'package:regalos/core/widgets/pointer_surface.dart';
import 'package:regalos/core/widgets/screen_header.dart';
import 'package:regalos/core/widgets/settings_row.dart';

import '../helpers/pump_app.dart';

// Arreglos de la revisión de coherencia visual de la web de escritorio (F1):
// tinte del ratón, filete de foco, cabecera del detalle y fila de Ajustes.

/// Cuánto baja el título de [ScreenHeader] desde el borde de la cabecera.
double _titleDy(WidgetTester tester, String title) =>
    tester.getTopLeft(find.text(title)).dy -
    tester.getTopLeft(find.byType(ScreenHeader)).dy;

void main() {
  group('PointerSurface', () {
    Future<Color> tintOf(WidgetTester tester, Brightness brightness) async {
      await pumpThemed(
        tester,
        const SizedBox(
          width: 200,
          height: 60,
          child: PointerSurface(child: SizedBox.expand()),
        ),
        brightness: brightness,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(PointerSurface)));
      await tester.pumpAndSettle();
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(PointerSurface),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final color = (box.decoration! as BoxDecoration).color!;
      await mouse.removePointer();
      return color;
    }

    testWidgets('en oscuro tiñe al 12 % y en claro al 7 %', (tester) async {
      final dark = await tintOf(tester, Brightness.dark);
      expect(dark.a, closeTo(0.12, 0.005));
      final light = await tintOf(tester, Brightness.light);
      expect(light.a, closeTo(0.07, 0.005));
    });
  });

  group('FocusRingPainter', () {
    testWidgets('deja 2 px de fondo entre el control y el filete', (
      tester,
    ) async {
      const gap = Color(0xFF123456);
      const ink = Color(0xFF654321);
      const rect = Rect.fromLTWH(20, 20, 100, 40);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 100,
            child: CustomPaint(painter: FocusRingPainter(rect, ink, gap)),
          ),
        ),
      );
      final box = tester.renderObject(find.byType(CustomPaint).first);
      // Primero el hueco (2 px, entre el borde y el filete) y, por fuera, el
      // filete de 2 px: de 2 a 4 px del control.
      expect(
        box,
        paints
          ..rrect(
            rrect: RRect.fromRectAndRadius(
              rect.inflate(1),
              const Radius.circular(8),
            ),
            color: gap,
            strokeWidth: 2,
          )
          ..rrect(
            rrect: RRect.fromRectAndRadius(
              rect.inflate(3),
              const Radius.circular(8),
            ),
            color: ink,
            strokeWidth: 2,
          ),
      );
    });

    testWidgets('sin rectángulo no pinta nada', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 50,
            height: 50,
            child: CustomPaint(
              painter: FocusRingPainter(null, Color(0xFF000000)),
            ),
          ),
        ),
      );
      expect(
        tester.renderObject(find.byType(CustomPaint).first),
        paintsNothing,
      );
    });
  });

  group('ScreenHeader en el panel de detalle', () {
    // Como en la pantalla de verdad: dentro de una columna sin alto fijo.
    Widget unbounded(Widget child) => SingleChildScrollView(child: child);
    Widget detail(PaneRole role, {bool compact = false}) => unbounded(
      PaneScope(
        role: role,
        child: ScreenHeader(
          title: 'Tió',
          subtitle: 'Del 24 al 26 de diciembre',
          compactTitle: compact,
        ),
      ),
    );

    testWidgets('el título cae en la misma línea que el de la lista', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        unbounded(
          const ScreenHeader(
            title: 'Ocasiones',
            actions: [SizedBox.square(dimension: 44)],
          ),
        ),
      );
      final listDy = _titleDy(tester, 'Ocasiones');
      await pumpThemed(tester, detail(PaneRole.detail));
      expect(_titleDy(tester, 'Tió'), listDy);
    });

    testWidgets('con título pequeño también', (tester) async {
      await pumpThemed(
        tester,
        unbounded(
          const ScreenHeader(
            title: 'Ajustes',
            compactTitle: true,
            actions: [SizedBox.square(dimension: 44)],
          ),
        ),
      );
      final listDy = _titleDy(tester, 'Ajustes');
      await pumpThemed(tester, detail(PaneRole.detail, compact: true));
      expect(_titleDy(tester, 'Tió'), listDy);
    });

    testWidgets('en el móvil no cambia: el título sube al borde', (
      tester,
    ) async {
      await pumpThemed(tester, detail(PaneRole.single));
      // 8 de relleno de la cabecera y nada más encima del título.
      expect(_titleDy(tester, 'Tió'), 8);
    });
  });

  group('SettingsRow', () {
    PointerSurface surface(WidgetTester tester) =>
        tester.widget<PointerSurface>(find.byType(PointerSurface));

    testWidgets('en el panel de lista el tinte lleva esquinas, elegida o no', (
      tester,
    ) async {
      for (final selected in [false, true]) {
        await pumpThemed(
          tester,
          PaneScope(
            role: PaneRole.list,
            child: SettingsRow(
              title: 'Personas',
              selected: selected,
              onTap: () {},
            ),
          ),
        );
        expect(surface(tester).radius, RegalosShape.card);
      }
    });

    testWidgets('en el móvil, recto salvo la elegida (como hoy)', (
      tester,
    ) async {
      await pumpThemed(tester, SettingsRow(title: 'Personas', onTap: () {}));
      expect(surface(tester).radius, BorderRadius.zero);
      await pumpThemed(
        tester,
        PaneScope(
          role: PaneRole.detail,
          child: SettingsRow(title: 'Personas', onTap: () {}),
        ),
      );
      expect(surface(tester).radius, BorderRadius.zero);
    });

    testWidgets('hintMaxLines acorta el texto en una línea con elipsis', (
      tester,
    ) async {
      const url = 'https://ko-fi.com/una-direccion-muy-larga-que-no-cabe-nunca';
      await pumpThemed(
        tester,
        const SizedBox(
          width: 220,
          child: SettingsRow(title: 'Ko-fi', hint: url, hintMaxLines: 1),
        ),
      );
      final text = tester.widget<Text>(find.text(url));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin hintMaxLines, el texto no se recorta', (tester) async {
      await pumpThemed(
        tester,
        const SettingsRow(title: 'Borrar', hint: 'Borra todo lo de este móvil'),
      );
      final text = tester.widget<Text>(
        find.text('Borra todo lo de este móvil'),
      );
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
    });
  });
}
