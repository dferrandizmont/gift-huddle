// Las barras de desplazamiento de la app: finas, de tinta suave y con el radio
// de la app, claras u oscuras; y el arrastre con el ratón solo donde se pide.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/accent_palette.dart';
import 'package:regalos/core/theme/app_scrollbar.dart';
import 'package:regalos/core/theme/app_theme.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';

ScrollbarThemeData _themeOf(Brightness brightness) =>
    buildTheme(AccentId.rose.palette, brightness).scrollbarTheme;

void main() {
  group('tema de las barras', () {
    for (final brightness in Brightness.values) {
      test('fina, con radio pequeño y tinta suave en ${brightness.name}', () {
        final theme = _themeOf(brightness);
        double thickness(Set<WidgetState> s) => theme.thickness!.resolve(s)!;
        Color thumb(Set<WidgetState> s) => theme.thumbColor!.resolve(s)!;
        // 6 en reposo y algo más ancha con el ratón encima o al arrastrar.
        expect(thickness({}), AppScrollbar.thickness);
        expect(thickness({WidgetState.hovered}), AppScrollbar.hoverThickness);
        expect(thickness({WidgetState.dragged}), AppScrollbar.hoverThickness);
        expect(AppScrollbar.thickness, lessThanOrEqualTo(6));
        // El radio, de 4 como mucho (nada de píldoras).
        expect(theme.radius!.x, lessThanOrEqualTo(4));
        // Tinta con poca opacidad que sube con el ratón y al arrastrar.
        expect(thumb({}).a, lessThanOrEqualTo(0.4));
        expect(thumb({WidgetState.hovered}).a, greaterThan(thumb({}).a));
        expect(
          thumb({WidgetState.dragged}).a,
          greaterThan(thumb({WidgetState.hovered}).a),
        );
        expect(thumb({WidgetState.dragged}).a, lessThan(0.8));
        // La tinta es la del texto: clara u oscura según el tema.
        expect(
          thumb({}).computeLuminance(),
          brightness == Brightness.light ? lessThan(0.5) : greaterThan(0.5),
        );
        // Sin pista de fondo.
        expect(theme.trackVisibility, isNull);
      });
    }
  });

  test(
    'en oscuro el pulgar en reposo llega a 3:1 sobre el fondo y la columna',
    () {
      final dark = buildTheme(AccentId.rose.palette, Brightness.dark);
      final t = dark.extension<RegalosTokens>()!;
      final thumb = dark.scrollbarTheme.thumbColor!.resolve({})!;
      double contrast(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        return (la > lb ? la + 0.05 : lb + 0.05) /
            (la > lb ? lb + 0.05 : la + 0.05);
      }

      for (final surface in [t.bg, t.surface]) {
        final over = Color.alphaBlend(thumb, surface);
        expect(contrast(over, surface), greaterThanOrEqualTo(3));
      }
    },
  );

  group('arrastre con el ratón', () {
    Future<double> dragged(
      WidgetTester tester, {
      required bool mouseDrag,
    }) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      Widget list() => SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        child: const SizedBox(width: 2000, height: 100),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 100,
            child: mouseDrag ? MouseDragScroll(child: list()) : list(),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        const Offset(200, 50),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      return controller.offset;
    }

    testWidgets('con MouseDragScroll la lista sigue al ratón', (tester) async {
      expect(await dragged(tester, mouseDrag: true), greaterThan(0));
    });

    testWidgets('sin él, el ratón no la arrastra (usa la rueda)', (
      tester,
    ) async {
      expect(await dragged(tester, mouseDrag: false), 0);
    });
  });
}
