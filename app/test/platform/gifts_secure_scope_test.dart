// El bloqueo de capturas de la versión de tienda (1.0.6): solo en Android, solo
// en la versión de tienda y solo mientras se ve una pantalla con regalos.
// Siempre emparejado (enable al entrar, disable al salir), también cuando
// otra pantalla la tapa o se solapan dos (tablet con paneles). El canal es el
// de siempre, simulado.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/platform/gifts_secure_scope.dart';
import 'package:regalos/core/platform/secure_screen.dart';

import '../helpers/fonts.dart';
import '../helpers/screens.dart';

/// Lo que el canal recibió, en orden.
List<String> _listen(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('com.dferrandizmont.regalos/incoming'),
    (call) async {
      calls.add(
        call.method == 'setSecure'
            ? 'setSecure:${call.arguments}'
            : call.method,
      );
      return null;
    },
  );
  return calls;
}

/// Pone la versión de tienda de [platform] (o, con [store] en falso, una
/// prerelease), corre [body] y lo deja todo como estaba: la comprobación de
/// invariantes de Flutter corre antes que los `addTearDown`.
Future<void> _inStore(
  Future<void> Function() body, {
  TargetPlatform platform = TargetPlatform.android,
  bool store = true,
}) async {
  debugGiftScreensSecure = store ? true : null;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugGiftScreensSecure = null;
    debugDefaultTargetPlatformOverride = null;
  }
}

void _testStore(
  String description,
  Future<void> Function(WidgetTester tester) body, {
  TargetPlatform platform = TargetPlatform.android,
  bool store = true,
}) => testWidgets(
  description,
  (tester) => _inStore(() => body(tester), platform: platform, store: store),
);

Widget _app(Widget home) => MaterialApp(home: home);

void main() {
  setUpAll(loadInter);

  group('el bloqueo', () {
    _testStore('entra al aparecer y sale al irse, una vez cada uno', (
      tester,
    ) async {
      final calls = _listen(tester);
      await tester.pumpWidget(
        _app(const GiftsSecureScope(child: Text('Regalos'))),
      );
      await tester.pump();
      expect(calls, ['setSecure:true']);
      await tester.pumpWidget(_app(const Text('Ajustes')));
      await tester.pump();
      expect(calls, ['setSecure:true', 'setSecure:false']);
    });

    _testStore('no hace nada fuera de la versión de tienda', (tester) async {
      final calls = _listen(tester);
      // `kStoreBuild` es falso en las pruebas: es una prerelease.
      expect(giftScreensSecure, isFalse);
      await tester.pumpWidget(
        _app(const GiftsSecureScope(child: Text('Regalos'))),
      );
      await tester.pump();
      await tester.pumpWidget(_app(const SizedBox()));
      expect(calls, isEmpty);
    }, store: false);

    _testStore('no hace nada en iOS', (tester) async {
      final calls = _listen(tester);
      await tester.pumpWidget(
        _app(const GiftsSecureScope(child: Text('Regalos'))),
      );
      await tester.pump();
      await tester.pumpWidget(_app(const SizedBox()));
      expect(calls, isEmpty);
    }, platform: TargetPlatform.iOS);

    _testStore('con enabled en falso (el bloque fijo) no pide nada y lo '
        'suelta al volver a enseñar regalos', (tester) async {
      final calls = _listen(tester);
      Widget scope(bool on) =>
          _app(GiftsSecureScope(enabled: on, child: const Text('Persona')));
      await tester.pumpWidget(scope(false));
      await tester.pump();
      expect(calls, isEmpty);
      await tester.pumpWidget(scope(true));
      await tester.pump();
      expect(calls, ['setSecure:true']);
      await tester.pumpWidget(scope(false));
      await tester.pump();
      expect(calls, ['setSecure:true', 'setSecure:false']);
    });

    _testStore('dos pantallas a la vez (tablet con paneles): el flag se quita '
        'al irse la última', (tester) async {
      final calls = _listen(tester);
      Widget two({required bool detail}) => _app(
        Row(
          children: [
            const Expanded(child: GiftsSecureScope(child: Text('Lista'))),
            Expanded(
              child: detail
                  ? const GiftsSecureScope(child: Text('Editor'))
                  : const SizedBox(),
            ),
          ],
        ),
      );
      await tester.pumpWidget(two(detail: true));
      await tester.pump();
      await tester.pumpWidget(two(detail: false));
      await tester.pump();
      // Se fue una; la otra sigue a la vista: el flag no se quita.
      expect(calls.where((c) => c == 'setSecure:false'), isEmpty);
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
      expect(calls.last, 'setSecure:false');
      expect(calls.where((c) => c == 'setSecure:false'), hasLength(1));
    });

    _testStore('una pantalla tapada por otra de página completa suelta el '
        'bloqueo y lo recupera al volver', (tester) async {
      final calls = _listen(tester);
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: const GiftsSecureScope(child: Text('Regalos')),
        ),
      );
      await tester.pump();
      expect(calls, ['setSecure:true']);
      key.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('Ajustes')),
      );
      await tester.pumpAndSettle();
      expect(calls.last, 'setSecure:false');
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(calls.last, 'setSecure:true');
    });

    _testStore('una hoja encima no la tapa: el bloqueo sigue', (tester) async {
      final calls = _listen(tester);
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: const GiftsSecureScope(child: Text('Regalos')),
        ),
      );
      await tester.pump();
      showModalBottomSheet<void>(
        context: key.currentContext!,
        builder: (_) => const SizedBox(height: 80),
      );
      await tester.pumpAndSettle();
      expect(calls, ['setSecure:true']);
    });

    _testStore('una rama inactiva (TickerMode apagado) no bloquea', (
      tester,
    ) async {
      final calls = _listen(tester);
      Widget branch(bool active) => _app(
        TickerMode(
          enabled: active,
          child: const GiftsSecureScope(child: Text('Regalos')),
        ),
      );
      await tester.pumpWidget(branch(false));
      await tester.pump();
      expect(calls, isEmpty);
      await tester.pumpWidget(branch(true));
      await tester.pump();
      expect(calls, ['setSecure:true']);
    });

    _testStore('las palabras de recuperación siguen bloqueando en una '
        'prerelease, con el mismo contador', (tester) async {
      final calls = _listen(tester);
      await enableSecureScreen();
      await tester.pumpWidget(
        _app(const GiftsSecureScope(child: Text('Regalos'))),
      );
      await tester.pump();
      await disableSecureScreen();
      // Es una prerelease: las pantallas de regalos no cuentan; las palabras sí.
      expect(calls, ['setSecure:true', 'setSecure:false']);
    }, store: false);
  });

  group('las pantallas', () {
    // Pantallas reales: qué pide cada una al canal.
    Future<void> end(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    screenTest(
      'la lista de regalos de una persona bloquea; Personas, Ajustes y '
      'Ocasiones no',
      (tester, phone) => _inStore(() async {
        final calls = _listen(tester);
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        // Personas sin buscar: se puede capturar.
        expect(calls.where((c) => c == 'setSecure:true'), isEmpty);
        await tapText(tester, 'Aritz');
        expect(calls.last, 'setSecure:true');
        await tapLabel(tester, 'Volver a Personas');
        expect(calls.last, 'setSecure:false');
        final before = calls.length;
        await tester.tap(find.text('Ajustes').last);
        await settle(tester);
        await tester.tap(find.text('Ocasiones').last);
        await settle(tester);
        expect(calls.skip(before).where((c) => c == 'setSecure:true'), isEmpty);
        await end(tester);
      }),
    );

    screenTest(
      'la búsqueda bloquea mientras hay resultados y se suelta al cancelar',
      (tester, phone) => _inStore(() async {
        final calls = _listen(tester);
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(
          find.byKey(const ValueKey<String>('people-gift-search-button')),
        );
        await settle(tester);
        // Con el campo vacío aún no hay regalos a la vista.
        expect(calls.where((c) => c == 'setSecure:true'), isEmpty);
        await tester.enterText(
          find.byKey(const ValueKey<String>('people-gift-search')),
          'puzle',
        );
        await settle(tester);
        expect(calls.last, 'setSecure:true');
        await tester.tap(
          find.byKey(const ValueKey<String>('people-gift-search-cancel')),
        );
        await settle(tester);
        expect(calls.last, 'setSecure:false');
        await end(tester);
      }),
    );

    screenTest(
      'Reparto y el editor de regalo bloquean',
      (tester, phone) => _inStore(() async {
        final calls = _listen(tester);
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Reparto').last);
        await settle(tester);
        expect(calls.last, 'setSecure:true');
        await tester.tap(find.text('Personas').last);
        await settle(tester);
        expect(calls.last, 'setSecure:false');
        // El editor, como hoja sobre la lista de una persona.
        await tapText(tester, 'Aritz');
        final trues = calls.where((c) => c == 'setSecure:true').length;
        await tester.tap(find.byType(FloatingActionButton));
        await settle(tester);
        expect(
          calls.where((c) => c == 'setSecure:true').length,
          greaterThan(trues),
        );
        await end(tester);
      }),
    );

    screenTest(
      'el detalle de una ocasión bloquea',
      (tester, phone) => _inStore(() async {
        final calls = _listen(tester);
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Ocasiones').last);
        await settle(tester);
        expect(calls.where((c) => c == 'setSecure:true'), isEmpty);
        await tapText(tester, 'Reyes');
        expect(calls.last, 'setSecure:true');
        await end(tester);
      }),
    );
  });
}
