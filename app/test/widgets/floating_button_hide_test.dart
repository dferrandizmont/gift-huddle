// El «+» o «Añadir regalo» se esconde con el teclado abierto (y con `hidden`,
// la búsqueda) para no tapar lo que se escribe o se busca, y vuelve al
// cerrarse.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/layout/content_gutter.dart';

import '../helpers/pump_app.dart';

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(ContentFloatingButton),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

Widget _fab({bool hidden = false}) => ContentFloatingButton(
  maxWidth: 640,
  hidden: hidden,
  child: FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add)),
);

void main() {
  testWidgets('con el teclado abierto se esconde y no recibe toques; al '
      'cerrarlo vuelve', (tester) async {
    await pumpThemed(tester, _fab());
    expect(_opacity(tester), 1);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(_opacity(tester), 0);
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.byType(FloatingActionButton),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
    );
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
  });

  testWidgets(
    'solo se repinta si el teclado cambia, no con cualquier cambio de '
    'métricas',
    (tester) async {
      await pumpThemed(tester, _fab());
      final element = tester.element(find.byType(ContentFloatingButton));
      await tester.pumpAndSettle();
      expect(element.dirty, isFalse);
      // Métricas que no son del teclado: nada que repintar.
      tester.binding.handleMetricsChanged();
      expect(element.dirty, isFalse);
      // El teclado se abre: se repinta.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      expect(element.dirty, isTrue);
      await tester.pumpAndSettle();
      // Sigue abierto y las métricas cambian otra vez: no se repinta.
      tester.binding.handleMetricsChanged();
      expect(element.dirty, isFalse);
    },
  );

  testWidgets('con `hidden` (la búsqueda abierta) se esconde sin teclado', (
    tester,
  ) async {
    await pumpThemed(tester, _fab(hidden: true));
    await tester.pumpAndSettle();
    expect(_opacity(tester), 0);
    await pumpThemed(tester, _fab());
    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
  });
}
