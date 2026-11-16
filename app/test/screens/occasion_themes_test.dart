import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/countdown_card.dart';
import 'package:regalos/features/occasions/presentation/occasion_garland.dart';
import 'package:regalos/features/settings/application/appearance_provider.dart';

import '../helpers/screens.dart';

Occasion _occasion(
  OccasionKind kind, {
  String? color,
  String? icon,
  int month = 3,
  int day = 10,
}) => Occasion(
  id: 'o-${kind.name}',
  kind: kind,
  rawKind: kind.name,
  name: 'Fiesta ${kind.name}',
  month: month,
  day: day,
  recurring: true,
  archived: false,
  color: color,
  icon: icon,
);

void main() {
  // El adorno fino (línea, rombo y punto) bajo el título de la ocasión.
  final ornament = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_Ornament',
  );

  // Navidad, Tió, Reyes y cumpleaños llevan la guirnalda de Tabler en lugar
  // del filete; el resto, el filete.
  final garland = find.byType(OccasionGarland);
  void expectAdornment(String themeId, {String? reason}) {
    final hasGarland = const {
      'christmas',
      'tio',
      'kings',
      'birthday',
    }.contains(themeId);
    expect(garland, hasGarland ? findsOneWidget : findsNothing, reason: reason);
    expect(
      ornament,
      hasGarland ? findsNothing : findsOneWidget,
      reason: reason,
    );
  }

  RegalosTokens tokens(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(CountdownCard)))
          .extension<RegalosTokens>()!;

  /// Los temas que salen en la pantalla de cada tipo de ocasión.
  const expected = <OccasionKind, String>{
    OccasionKind.santa: 'christmas',
    OccasionKind.tio: 'tio',
    OccasionKind.kings: 'kings',
    OccasionKind.chineseNewYear: 'chineseNewYear',
    OccasionKind.wedding: 'wedding',
    OccasionKind.anniversary: 'anniversary',
    OccasionKind.santJordi: 'santJordi',
    OccasionKind.valentine: 'valentine',
    OccasionKind.baptism: 'baptism',
    OccasionKind.communion: 'communion',
    OccasionKind.graduation: 'graduation',
  };

  for (final brightness in Brightness.values) {
    screenTest(
      'cada ocasión tiene su tema y su adorno (${brightness.name})',
      (tester, phone) async {
        await bareFamily(tester, phone);
        await tester.runAsync(() async {
          final c = familyOf(phone);
          for (final kind in expected.keys) {
            await c.upsertOccasion(_occasion(kind));
          }
          await c.upsertOccasion(
            _occasion(OccasionKind.custom, color: 'teal', icon: 'music'),
          );
        });
        await pumpRegalos(tester, phone);
        for (final entry in expected.entries) {
          phone.container
              .read(routerProvider)
              .go('/occasions/o-${entry.key.name}');
          await settle(tester);
          expect(tester.takeException(), isNull, reason: entry.key.name);
          expect(tokens(tester).occasion?.id, entry.value);
          // Sin cabecera ilustrada: solo el adorno fino bajo el título.
          expectAdornment(entry.value, reason: entry.key.name);
          // La tarjeta de cuenta atrás toma el color del tema.
          final deco =
              tester
                      .widget<Container>(
                        find
                            .descendant(
                              of: find.byType(CountdownCard),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration!
                  as BoxDecoration;
          final palette = tokens(tester).occasion!.palette;
          expect(
            deco.color,
            brightness == Brightness.dark ? palette.tintD : palette.pastel,
            reason: entry.key.name,
          );
        }
        // Una ocasión «Otra» lleva el color y el icono elegidos.
        phone.container.read(routerProvider).go('/occasions/o-custom');
        await settle(tester);
        expect(tokens(tester).occasion?.id, 'custom-teal');
        expect(tokens(tester).occasion?.icon, kOccasionIcons['music']);
        expect(
          tokens(tester).fill,
          brightness == Brightness.dark
              ? kOccasionColors
                    .firstWhere((c) => c.name == 'teal')
                    .palette
                    .pastelD
              : kOccasionColors
                    .firstWhere((c) => c.name == 'teal')
                    .palette
                    .pastel,
        );
      },
      size: const Size(390, 1900),
      brightness: brightness,
    );
  }

  screenTest('con el interruptor apagado todo vuelve al tema estándar', (
    tester,
    phone,
  ) async {
    await bareFamily(tester, phone);
    await tester.runAsync(() async {
      final c = familyOf(phone);
      for (final kind in expected.keys) {
        await c.upsertOccasion(_occasion(kind));
      }
      await c.upsertOccasion(_occasion(OccasionKind.custom, color: 'rose'));
    });
    await pumpRegalos(tester, phone);
    phone.container
        .read(appearanceProvider.notifier)
        .setOccasionThemes(enabled: false);
    final ids = [for (final k in expected.keys) 'o-${k.name}', 'o-custom'];
    for (final id in ids) {
      phone.container.read(routerProvider).go('/occasions/$id');
      await settle(tester);
      expect(tester.takeException(), isNull, reason: id);
      expect(tokens(tester).occasion, isNull, reason: id);
      expect(ornament, findsNothing, reason: id);
      expect(garland, findsNothing, reason: id);
      expect(tokens(tester).fill, AccentId.lavender.palette.pastel);
      expect(tokens(tester).cardBorder, isNull);
    }
    // Y al encenderlo vuelve el tema, sin cambiar de pantalla.
    phone.container
        .read(appearanceProvider.notifier)
        .setOccasionThemes(enabled: true);
    await settle(tester);
    expect(ornament, findsOneWidget);
    expect(tokens(tester).occasion?.id, 'custom-rose');
  }, size: const Size(390, 1900));

  screenTest('Navidad, el Tió y Reyes enseñan su adorno en la pantalla '
      'real de la familia de muestra', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    for (final (id, theme) in [
      ('seed-santa', 'christmas'),
      ('seed-tio', 'tio'),
      ('seed-kings', 'kings'),
      ('birthday-nora', 'birthday'),
    ]) {
      phone.container.read(routerProvider).go('/occasions/$id');
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(tokens(tester).occasion?.id, theme);
      expectAdornment(theme, reason: id);
    }
  }, size: const Size(390, 1900));

  screenTest(
    'las cabeceras aguantan el texto al 130 % en 360 px',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      for (final id in [
        'seed-santa',
        'seed-tio',
        'seed-kings',
        'birthday-nora',
      ]) {
        phone.container.read(routerProvider).go('/occasions/$id');
        await settle(tester);
        expect(tester.takeException(), isNull, reason: id);
      }
    },
    size: const Size(360, 1900),
    textScale: 1.3,
  );
}
