import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/avatar_hero.dart';
import 'package:regalos/core/widgets/person_avatar.dart';
import 'package:regalos/core/widgets/status_checkbox.dart';

import '../helpers/fake_haptics.dart';
import '../helpers/screens.dart';

StatusGlyphPainter glyphOf(WidgetTester tester, String giftLabel) {
  final paint = tester.widget<CustomPaint>(
    find
        .descendant(
          of: find.ancestor(
            of: find.text(giftLabel),
            matching: find.byType(Row),
          ),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is StatusGlyphPainter,
          ),
        )
        .first,
  );
  return paint.painter! as StatusGlyphPainter;
}

void main() {
  final fake = FakeHaptics();
  setUp(fake.calls.clear);

  screenTest('marcar un regalo: háptica ligera y la casilla barre de ¼ a ½', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Aritz');

    // «Estación de bomberos» está en comprado (¼).
    const title = 'Estación de bomberos de bloques';
    await tester.scrollUntilVisible(
      find.text(title),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    expect(glyphOf(tester, title).sweep, 0.25);

    await tester.tap(
      find.bySemanticsLabel(
        'Cambiar estado de $title. Estado actual: Comprado',
      ),
    );
    await tester.pump();
    // Vibra cuando el sector termina de barrer, no con el toque.
    expect(fake.log, ['light+160']);
    // El dato se guarda al tocar; la casilla barre sin esperar a nada.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final mid = glyphOf(tester, title).sweep!;
    expect(mid, inExclusiveRange(0.26, 0.5));
    await settle(tester);
    expect(glyphOf(tester, title).sweep, closeTo(0.5, 0.001));
  }, overrides: [fake.provide]);

  screenTest('entregar un regalo: háptica media y el visto se dibuja', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Nora');
    const title = 'Cocinita de madera'; // envuelto
    await tester.scrollUntilVisible(
      find.text(title),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await tester.tap(
      find.bySemanticsLabel(
        'Cambiar estado de $title. Estado actual: Envuelto',
      ),
    );
    await tester.pump();
    expect(fake.log, ['medium+160']);
    await settle(tester);
    final p = glyphOf(tester, title);
    expect(p.grow, closeTo(1, 0.001));
    expect(p.check, 1);
  }, overrides: [fake.provide]);

  screenTest('con «Reducir movimiento» la casilla se funde: sin barrido', (
    tester,
    phone,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Aritz');
    const title = 'Estación de bomberos de bloques';
    await tester.scrollUntilVisible(
      find.text(title),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await tester.tap(
      find.bySemanticsLabel(
        'Cambiar estado de $title. Estado actual: Comprado',
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Sin barrido: la casilla es la estática de siempre (no hay pintor con
    // sector animado) y nada se escala ni se traslada.
    final row = find.ancestor(of: find.text(title), matching: find.byType(Row));
    expect(
      find.descendant(of: row, matching: find.byType(StatusGlyph)),
      findsWidgets,
    );
    for (final t in tester.widgetList<Transform>(
      find.descendant(of: row, matching: find.byType(Transform)),
    )) {
      expect(t.transform.storage[0], 1);
      expect(t.transform.getTranslation().length, 0);
    }
    // La háptica se queda, y sin viaje que esperar: es al momento.
    expect(fake.log, ['light+0']);
    await settle(tester);
  }, overrides: [fake.provide]);

  screenTest('al abrir una persona el avatar vuela de la fila a la cabecera', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);

    List<double> avatarSizes() => [
      for (final a in tester.widgetList<PersonAvatar>(
        find.byType(PersonAvatar),
      ))
        a.size,
    ];

    await tester.tap(find.text('Aritz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // En vuelo hay un avatar de un tamaño intermedio entre el de la fila (52)
    // y el de la cabecera (46), o al menos un vuelo en curso.
    expect(find.byType(AvatarHero), findsWidgets);
    final sizes = avatarSizes();
    expect(sizes.any((s) => s != 52 && s != 46), isTrue, reason: '$sizes');

    await settle(tester);
    // Asentada la pantalla, solo queda el avatar de la cabecera.
    expect(avatarSizes().where((s) => s == 46), isNotEmpty);
  });

  screenTest('con «Reducir movimiento» el avatar no vuela', (
    tester,
    phone,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tester.tap(find.text('Aritz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    for (final a in tester.widgetList<PersonAvatar>(
      find.byType(PersonAvatar),
    )) {
      expect(a.size == 52 || a.size == 46, isTrue, reason: '${a.size}');
    }
    await settle(tester);
  });
}
