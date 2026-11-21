// La guía «Cómo funciona»: cuándo se abre, cómo se cierra, cómo se ve en móvil
// y en tablet y qué hace con «Reducir movimiento».
//
// Las demostraciones corren en bucle: estas pruebas nunca esperan a que la
// pantalla se «asiente» (`pumpAndSettle` no acabaría); avanzan el tiempo a
// mano.
//
// Con `--dart-define=CAPTURE_TOUR=true` además se hacen capturas de las seis
// páginas en `build/screens/pantallas/tour/` (ignorado por git; móvil, tablet,
// claro y oscuro).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/regalos_nav_bar.dart';
import 'package:regalos/features/tour/application/tour_state.dart';
import 'package:regalos/features/tour/presentation/tour_demos.dart';
import 'package:regalos/features/tour/presentation/tour_screen.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import '../helpers/screens.dart';
import '../helpers/tablet.dart';
import 'first_run_test.dart' show addPerson;

const bool _capture = bool.fromEnvironment('CAPTURE_TOUR');

const List<String> _titles = [
  'Apunta cada regalo',
  'Márcalo como comprado',
  'Personas y ocasiones',
  'La familia comparte la lista',
  'Sorpresas a salvo',
  'También en el ordenador',
];

final GlobalKey _boundary = GlobalKey();

/// Deja pasar un rato de tiempo real (cifrado, almacenes) y de fotogramas,
/// sin esperar a que nada acabe: la guía tiene una demostración en bucle.
Future<void> settleTour(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Pasa por la bienvenida hasta el final, sin PIN.
Future<void> finishWelcome(WidgetTester tester, FakePhone phone) async {
  await pumpRegalos(tester, phone);
  await tapText(tester, 'Empezar');
  await addPerson(tester, 'Aritz');
  await tapText(tester, 'Siguiente');
  await tapText(tester, 'Siguiente');
  await tapText(tester, 'Siguiente');
  await tester.tap(find.text('Ahora no'));
  await settleTour(tester);
}

/// Monta solo la guía, con el tema de la app.
Future<void> pumpTour(
  WidgetTester tester, {
  Size size = kPhoneSize,
  double textScale = 1,
  bool reduce = false,
  Brightness brightness = Brightness.light,
  bool fromSettings = false,
  VoidCallback? onClose,
  bool capture = false,
  Locale locale = const Locale('es'),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = await mockPrefs({kTourSeenKey: false});
  Widget app = MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildTheme(AccentId.lavender.palette, brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduce,
      ),
      child: child!,
    ),
    home: TourScreen(fromSettings: fromSettings, onClose: onClose ?? () {}),
  );
  if (capture) {
    app = RepaintBoundary(key: _boundary, child: app);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: app,
    ),
  );
  await tester.pump();
}

/// Pulsa «Siguiente» y deja acabar el deslizamiento de la página.
Future<void> next(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  // Y el movimiento de «Atrás» y de los puntos, que arranca al cambiar de
  // página.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Ninguna letra de la demostración baja de 12 y ningún texto se recorta (ni
/// con «…» ni por líneas de más).
void checkStageText(WidgetTester tester) {
  final texts = find.descendant(
    of: find.byType(TourStage),
    matching: find.byType(RichText),
  );
  for (final element in texts.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text.toPlainText();
    final size = paragraph.text.style?.fontSize;
    expect(size, isNotNull, reason: text);
    expect(size, greaterThanOrEqualTo(12), reason: text);
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'recortado: $text (${element.debugGetCreatorChain(8)})',
    );
  }
}

Rect _stageRect(WidgetTester tester) => tester.getRect(
  find
      .ancestor(of: find.byType(TourStage), matching: find.byType(FittedBox))
      .first,
);

void main() {
  setUpAll(loadInter);

  group('cuándo se abre', () {
    screenTest(
      'al terminar la bienvenida la primera vez se abre la guía, «Saltar» la '
      'cierra y se recuerda que ya se vio',
      (tester, phone) async {
        await finishWelcome(tester, phone);
        expect(find.text('Apunta cada regalo'), findsOneWidget);
        expect(find.text('Saltar'), findsOneWidget);
        expect(find.text('Siguiente'), findsOneWidget);
        // Es una pantalla entera: sin la navegación de Personas detrás.
        expect(find.byType(RegalosNavBar), findsNothing);
        // Ya se anotó: si la app se cierra aquí, no vuelve a salir sola.
        expect(phone.prefs!.getBool(kTourSeenKey), isTrue);

        await tester.tap(find.text('Saltar'));
        await settleTour(tester);
        expect(find.text('Apunta cada regalo'), findsNothing);
        expect(find.byType(RegalosNavBar), findsOneWidget);
        expect(find.text('Aritz'), findsOneWidget);
      },
      prefs: {kTourSeenKey: false},
    );

    screenTest(
      'la segunda vez (ya vista) la bienvenida acaba directamente en Personas',
      (tester, phone) async {
        await finishWelcome(tester, phone);
        await settle(tester);
        expect(find.text('Apunta cada regalo'), findsNothing);
        expect(find.text('Aritz'), findsOneWidget);
      },
    );

    screenTest(
      'recorrida entera, el último botón es «Empezar» y lleva a Personas',
      (tester, phone) async {
        await finishWelcome(tester, phone);
        for (var i = 0; i < 5; i++) {
          expect(find.text(_titles[i]), findsOneWidget);
          expect(find.text('Saltar'), findsOneWidget);
          await next(tester);
        }
        expect(find.text(_titles[5]), findsOneWidget);
        expect(find.text('Siguiente'), findsNothing);
        expect(find.text('Saltar'), findsOneWidget);
        await tester.tap(find.text('Empezar'));
        await settleTour(tester);
        expect(find.text(_titles[5]), findsNothing);
        expect(find.text('Aritz'), findsOneWidget);
      },
      prefs: {kTourSeenKey: false},
    );

    screenTest(
      'desde Ajustes se abre siempre y se cierra volviendo a Ajustes',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Ajustes').last);
        await settle(tester);
        final row = find.text('Cómo funciona');
        expect(row, findsOneWidget);
        await tester.ensureVisible(row);
        await tester.pump();
        await tester.tap(row);
        await settleTour(tester);
        expect(find.text('Apunta cada regalo'), findsOneWidget);
        // Desde Ajustes el final es «Hecho», no «Empezar».
        for (var i = 0; i < 5; i++) {
          await next(tester);
        }
        expect(find.text('Empezar'), findsNothing);
        await tester.tap(find.text('Hecho'));
        await settleTour(tester);
        expect(find.text(_titles[5]), findsNothing);
        expect(find.text('Cómo funciona'), findsOneWidget);

        // Y se puede volver a abrir, y «Saltar» también vuelve a Ajustes.
        await tester.tap(find.text('Cómo funciona'));
        await settleTour(tester);
        expect(find.text('Apunta cada regalo'), findsOneWidget);
        await tester.tap(find.text('Saltar'));
        await settleTour(tester);
        expect(find.text('Apunta cada regalo'), findsNothing);
        expect(find.text('Cómo funciona'), findsOneWidget);
      },
    );

    screenTest(
      'en tablet horizontal la fila de Ajustes abre la guía por encima',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Ajustes').last);
        await settle(tester);
        await tester.tap(find.text('Cómo funciona'));
        await settleTour(tester);
        expect(find.text('Apunta cada regalo'), findsOneWidget);
        // Es una pantalla entera: sin la navegación detrás.
        expect(find.text('Personas'), findsNothing);
        await tester.tap(find.text('Saltar'));
        await settleTour(tester);
        expect(find.text('Cómo funciona'), findsOneWidget);
      },
      size: kTabletLandscape,
    );
  });

  group('cómo se ve', () {
    testWidgets('en el móvil la demostración va arriba y el texto debajo', (
      tester,
    ) async {
      await pumpTour(tester);
      final stage = _stageRect(tester);
      final title = tester.getRect(find.text(_titles[0]));
      expect(stage.bottom, lessThanOrEqualTo(title.top));
      expect(stage.width, 340);
      expect(stage.height, 280);
      expect(stage.center.dx, closeTo(195, 0.5));
    });

    testWidgets('en el móvil estrecho la demostración se encoge, no se sale', (
      tester,
    ) async {
      await pumpTour(tester, size: const Size(320, 640));
      final stage = _stageRect(tester);
      expect(stage.width, lessThanOrEqualTo(320 - 48 + 0.01));
      expect(stage.left, greaterThanOrEqualTo(0));
    });

    testWidgets(
      'en tablet horizontal la demostración y el texto van lado a lado, '
      'centrados y sin estirarse',
      (tester) async {
        const size = kTabletLandscape;
        await pumpTour(tester, size: size);
        final stage = _stageRect(tester);
        final title = tester.getRect(find.text(_titles[0]));
        expect(stage.right, lessThanOrEqualTo(title.left));
        // A la misma altura, uno al lado del otro.
        expect(stage.top, lessThan(title.bottom));
        expect(title.top, lessThan(stage.bottom));
        // No se estira: como mucho 1,25 veces.
        expect(stage.width, lessThanOrEqualTo(340 * 1.25 + 0.01));
        expect(stage.width, greaterThan(300));
        // En una columna de 960 centrada: ni pegada a un borde ni al otro.
        final margin = (size.width - 960) / 2;
        expect(stage.left, greaterThanOrEqualTo(margin));
        expect(title.right, lessThanOrEqualTo(size.width - margin));
        // El conjunto está centrado en la ventana.
        final body = tester.getRect(find.textContaining('Elige para quién es el regalo'));
        final right = title.right > body.right ? title.right : body.right;
        expect(
          (stage.left + right) / 2,
          closeTo(size.width / 2, size.width * 0.12),
        );
      },
    );

    testWidgets(
      'en tablet vertical la demostración va arriba y el texto debajo, '
      'centrados, sin estirarse y en una columna cómoda',
      (tester) async {
        const size = kTabletPortrait;
        await pumpTour(tester, size: size);
        final stage = _stageRect(tester);
        final title = tester.getRect(find.text(_titles[0]));
        final body = tester.getRect(find.textContaining('Elige para quién es el regalo'));
        expect(stage.bottom, lessThanOrEqualTo(title.top));
        // Llena la columna de 520 si cabe en el alto, con los mismos bordes
        // que el texto.
        expect(stage.center.dx, closeTo(size.width / 2, 0.5));
        expect(stage.width, closeTo(520, 0.5));
        final column = (size.width - 520) / 2;
        expect(stage.left, closeTo(column, 0.5));
        expect(title.left, closeTo(column, 0.5));
        expect(body.right, lessThanOrEqualTo(size.width - column + 0.5));
      },
    );

    testWidgets(
      'el móvil girado va lado a lado y la demostración cabe en el alto',
      (tester) async {
        await pumpTour(tester, size: const Size(844, 390));
        final stage = _stageRect(tester);
        final title = tester.getRect(find.text(_titles[0]));
        expect(stage.right, lessThanOrEqualTo(title.left));
        expect(stage.bottom, lessThanOrEqualTo(390));
        expect(stage.top, greaterThanOrEqualTo(0));
      },
    );

    testWidgets(
      '«Saltar» y el indicador de página están en todas las páginas',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpTour(tester);
        for (var i = 0; i < 6; i++) {
          expect(find.text('Saltar'), findsOneWidget);
          expect(find.bySemanticsLabel('Página ${i + 1} de 6'), findsOneWidget);
          expect(find.text(_titles[i]), findsOneWidget);
          if (i < 5) {
            await next(tester);
          }
        }
        semantics.dispose();
      },
    );

    testWidgets('«Atrás» aparece desde la segunda página y vuelve; «Siguiente» '
        'ocupa todo el ancho en la primera y los puntos van en su eje', (
      tester,
    ) async {
      await pumpTour(tester);
      Rect nextRect() => tester.getRect(find.byType(FilledButton));
      Rect dotsRect() =>
          tester.getRect(find.byKey(const ValueKey('tour-dots')));
      double backOpacity() => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.text('Atrás'),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      // Primera página: «Siguiente» de borde a borde de la columna (24 de
      // margen en un móvil de 390) y los puntos centrados sobre él.
      expect(nextRect().left, 24);
      expect(nextRect().right, 390 - 24);
      expect(dotsRect().center.dx, closeTo(nextRect().center.dx, 0.5));
      expect(backOpacity(), 0);
      await next(tester);
      // Segunda: «Atrás» a la izquierda, «Siguiente» más estrecho y los puntos
      // siguen centrados sobre él.
      expect(backOpacity(), 1);
      expect(nextRect().right, 390 - 24);
      expect(nextRect().left, greaterThan(24 + 60));
      expect(dotsRect().center.dx, closeTo(nextRect().center.dx, 0.5));
      final back = tester.getRect(find.text('Atrás'));
      expect(back.right, lessThan(nextRect().left));
      expect(back.left, greaterThanOrEqualTo(24));
      await tester.tap(find.text('Atrás'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(_titles[0]), findsOneWidget);
      expect(backOpacity(), 0);
      expect(nextRect().left, 24);
    });

    testWidgets('con «Reducir movimiento» el hueco de «Atrás» salta', (
      tester,
    ) async {
      await pumpTour(tester, reduce: true);
      Rect nextRect() => tester.getRect(find.byType(FilledButton));
      expect(nextRect().left, 24);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      // En el mismo fotograma ya está en su sitio.
      expect(nextRect().left, greaterThan(24 + 60));
    });

    testWidgets('la cabecera, el texto y los botones comparten bordes', (
      tester,
    ) async {
      await pumpTour(tester);
      final header = tester.getRect(find.text('Cómo funciona'));
      final title = tester.getRect(find.text(_titles[0]));
      final stage = _stageRect(tester);
      expect(header.left, closeTo(title.left, 0.5));
      expect(stage.left, closeTo(title.left + 1, 0.5));
      final skip = tester.getRect(find.text('Saltar'));
      expect(skip.right, closeTo(390 - 24, 0.5));
    });

    testWidgets('en tablet vertical la cabecera cae sobre la columna de 520', (
      tester,
    ) async {
      await pumpTour(tester, size: kTabletPortrait);
      final header = tester.getRect(find.text('Cómo funciona'));
      final title = tester.getRect(find.text(_titles[0]));
      expect(header.left, closeTo(title.left, 0.5));
      expect(title.left, closeTo((800 - 520) / 2, 0.5));
      final skip = tester.getRect(find.text('Saltar'));
      expect(skip.right, closeTo(800 - (800 - 520) / 2, 0.5));
    });

    for (final locale in const [Locale('es'), Locale('ca'), Locale('en')]) {
      for (final size in [kPhoneSize, kTabletPortrait, kTabletLandscape]) {
        testWidgets('la demostración no cambia de sitio de una página a otra '
            '(${locale.languageCode}, ${sizeLabel(size)})', (tester) async {
          await pumpTour(tester, size: size, locale: locale);
          final first = _stageRect(tester);
          for (var i = 1; i < 6; i++) {
            await next(tester);
            final rect = _stageRect(tester);
            expect(rect.top, closeTo(first.top, 0.01), reason: 'página $i');
            expect(rect.left, closeTo(first.left, 0.01));
            expect(rect.size, first.size);
          }
        });
      }
    }

    testWidgets('se pasa de página con el gesto', (tester) async {
      await pumpTour(tester);
      await tester.fling(find.byType(PageView), const Offset(-150, 0), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text(_titles[1]), findsOneWidget);
      await tester.fling(find.byType(PageView), const Offset(150, 0), 1000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text(_titles[0]), findsOneWidget);
    });

    testWidgets(
      'el botón Atrás del sistema retrocede y, en la primera, cierra',
      (tester) async {
        var closed = 0;
        await pumpTour(tester, onClose: () => closed++);
        await next(tester);
        expect(find.text(_titles[1]), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text(_titles[0]), findsOneWidget);
        expect(closed, 0);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(closed, 1);
      },
    );

    testWidgets(
      'el parallax: la demostración viaja más despacio que la página',
      (tester) async {
        await pumpTour(tester);
        final restStage = _stageRect(tester).left;
        final gesture = await tester.startGesture(const Offset(300, 400));
        await gesture.moveBy(const Offset(-200, 0));
        await tester.pump();
        final movedStage = _stageRect(tester).left;
        // La página se ha movido 200 y la demostración, menos.
        expect(restStage - movedStage, inExclusiveRange(0, 200));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 800));
      },
    );

    testWidgets('nada redondeado: ningún borde pasa de radio 8', (
      tester,
    ) async {
      await pumpTour(tester);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 4500));
        for (final box in tester.widgetList<DecoratedBox>(
          find.byType(DecoratedBox),
        )) {
          final decoration = box.decoration;
          if (decoration is BoxDecoration &&
              decoration.borderRadius is BorderRadius) {
            final radius = (decoration.borderRadius! as BorderRadius).topLeft.x;
            expect(radius, lessThanOrEqualTo(8));
          }
        }
        for (final clip in tester.widgetList<ClipRRect>(
          find.byType(ClipRRect),
        )) {
          expect(
            (clip.borderRadius as BorderRadius).topLeft.x,
            lessThanOrEqualTo(8),
          );
        }
        if (i < 5) {
          await next(tester);
        }
      }
    });
  });

  group('sin desbordes ni errores', () {
    // Cada demostración se muestrea en varios instantes de su vuelta: el
    // editor abierto, la fila plegada, el reparto, el paquete cifrado...
    Future<void> walk(
      WidgetTester tester, {
      required int samples,
      required int stepMs,
      bool es = true,
    }) async {
      for (var i = 0; i < 6; i++) {
        for (var s = 0; s < samples; s++) {
          await tester.pump(Duration(milliseconds: stepMs));
          checkStageText(tester);
        }
        if (es) {
          expect(find.text(_titles[i]), findsOneWidget);
        }
        if (i < 5) {
          await next(tester);
        }
      }
    }

    testWidgets('móvil, claro', (tester) async {
      await pumpTour(tester);
      await walk(tester, samples: 18, stepMs: 500);
    });

    for (final locale in const [Locale('ca'), Locale('en')]) {
      testWidgets('móvil y tablet vertical en ${locale.languageCode}', (
        tester,
      ) async {
        await pumpTour(tester, locale: locale);
        await walk(tester, samples: 18, stepMs: 500, es: false);
      });
      testWidgets('tablet vertical en ${locale.languageCode}', (tester) async {
        await pumpTour(tester, size: kTabletPortrait, locale: locale);
        await walk(tester, samples: 9, stepMs: 1000, es: false);
      });
    }

    testWidgets('móvil, oscuro y letra al doble', (tester) async {
      await pumpTour(tester, brightness: Brightness.dark, textScale: 2);
      await walk(tester, samples: 6, stepMs: 1500);
      // Con letra grande la página se desplaza en vez de desbordar.
      expect(tester.takeException(), isNull);
    });

    testWidgets('móvil pequeño y letra al máximo', (tester) async {
      await pumpTour(tester, size: const Size(320, 568), textScale: 3);
      await walk(tester, samples: 4, stepMs: 2000);
    });

    for (final size in [...kTabletSizes, const Size(844, 390)]) {
      testWidgets('tablet o móvil girado, oscuro (${sizeLabel(size)})', (
        tester,
      ) async {
        await pumpTour(tester, size: size, brightness: Brightness.dark);
        await walk(tester, samples: 6, stepMs: 1500);
      });
    }
  });

  group('movimiento', () {
    testWidgets('la demostración corre sola, en bucle, y vuelve a empezar', (
      tester,
    ) async {
      await pumpTour(tester);
      expect(tester.hasRunningAnimations, isTrue);
      await next(tester);
      // Página 2 (detalle de una ocasión): «Pendiente de comprar» tiene dos;
      // a mitad de vuelta, uno; al acabar la vuelta, otra vez dos.
      expect(find.text('2 regalos'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 4500));
      expect(find.text('1 regalo'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 4500));
      expect(find.text('2 regalos'), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('al volver a una página la demostración empieza de nuevo', (
      tester,
    ) async {
      await pumpTour(tester);
      await next(tester);
      await tester.pump(const Duration(milliseconds: 4500));
      expect(find.text('1 regalo'), findsOneWidget);
      await next(tester);
      await tester.tap(find.text('Atrás'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text(_titles[1]), findsOneWidget);
      expect(find.text('2 regalos'), findsOneWidget);
    });

    testWidgets('al irse de una página su demostración se queda quieta', (
      tester,
    ) async {
      await pumpTour(tester);
      await next(tester);
      await next(tester);
      // En la página 3 solo corre la de la página 3.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(_titles[2]), findsOneWidget);
      expect(find.text('Pendiente de comprar'), findsNothing);
    });

    testWidgets('con «Reducir movimiento» no hay bucle ni parallax y cada '
        'demostración se queda en su estado final', (tester) async {
      await pumpTour(tester, reduce: true);
      // Nada corre: la pantalla se asienta.
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      // El botón cambia de página sin deslizar.
      await tester.tap(find.text('Siguiente'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(_titles[1]), findsOneWidget);
      await tester.pumpAndSettle();
      // El estado final de la página 2: el regalo ya no está en «Pendiente de
      // comprar» (queda uno), «por llegar» lo cuenta y el aviso con
      // «Deshacer» está a la vista.
      expect(find.text('1 regalo'), findsOneWidget);
      expect(find.text('Patinete: Comprado'), findsOneWidget);
      expect(find.text('Pendiente de comprar'), findsOneWidget);
      expect(find.text('por llegar'), findsOneWidget);
      expect(find.text('Listo'), findsNothing);
      expect(find.text('Deshacer'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('con «Reducir movimiento» el gesto no mueve la demostración '
        'por su cuenta', (tester) async {
      await pumpTour(tester, reduce: true);
      final rest = _stageRect(tester).left;
      final gesture = await tester.startGesture(const Offset(300, 400));
      await gesture.moveBy(const Offset(-200, 0));
      await tester.pump();
      // La demostración se mueve exactamente lo que la página: 200.
      expect(rest - _stageRect(tester).left, closeTo(200, 0.5));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('«Saltar» llama a cerrar', (tester) async {
      var closed = 0;
      await pumpTour(tester, onClose: () => closed++);
      await tester.tap(find.text('Saltar'));
      expect(closed, 1);
    });

    testWidgets('la guía se anota como vista al abrirse', (tester) async {
      await pumpTour(tester);
      final context = tester.element(find.byType(TourScreen));
      final container = ProviderScope.containerOf(context);
      expect(container.read(tourSeenProvider).seen, isTrue);
      expect(container.read(tourAfterWelcomeProvider).pending, isFalse);
    });
  });

  group('capturas', () {
    Future<void> shot(WidgetTester tester, String name) async {
      await tester.runAsync(() async {
        final boundary =
            _boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/screens/pantallas/tour/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
      });
    }

    // Instantes de cada página (en ms desde que entra) que se capturan: los
    // que mejor enseñan lo que la página explica.
    const at = [
      [1500, 3200, 5700, 7900],
      [1500, 3300, 4500, 6500],
      [1500, 3000, 5000, 7000],
      [1500, 3800, 5000, 6200, 7500],
      [2000, 3500, 5600, 8000],
      [1500, 3500, 5000, 7200],
    ];
    const es = Locale('es');
    final configs = <(String, Size, Brightness, Locale)>[
      ('movil-claro', kPhoneSize, Brightness.light, es),
      ('movil-oscuro', kPhoneSize, Brightness.dark, es),
      ('tablet-horizontal-claro', kTabletLandscape, Brightness.light, es),
      ('tablet-vertical-oscuro', kTabletPortrait, Brightness.dark, es),
      (
        'tablet-vertical-ca',
        kTabletPortrait,
        Brightness.light,
        const Locale('ca'),
      ),
      ('movil-ca', kPhoneSize, Brightness.light, const Locale('ca')),
      ('movil-en', kPhoneSize, Brightness.light, const Locale('en')),
    ];
    for (final (name, size, brightness, locale) in configs) {
      testWidgets('capturas $name', (tester) async {
        await pumpTour(
          tester,
          size: size,
          brightness: brightness,
          locale: locale,
          capture: true,
        );
        for (var i = 0; i < 6; i++) {
          var last = 0;
          for (var k = 0; k < at[i].length; k++) {
            // Un poco antes del instante, para que lo que se anima al llegar
            // (fichas, puntos) ya esté asentado; el resto, hasta el instante.
            await tester.pump(Duration(milliseconds: at[i][k] - last - 250));
            await tester.pump(const Duration(milliseconds: 250));
            last = at[i][k];
            await shot(tester, '${i + 1}${String.fromCharCode(97 + k)}-$name');
          }
          if (i < 5) {
            await next(tester);
          }
        }
      }, skip: !_capture);
    }
  });
}
