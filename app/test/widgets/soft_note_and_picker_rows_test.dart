// La nota suave única y las filas del selector de persona: lo que pide la
// revisión de coherencia visual (1.0.6).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/regalos_shape.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/core/widgets/person_avatar.dart';
import 'package:regalos/core/widgets/settings_icons.dart';
import 'package:regalos/core/widgets/soft_note.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart'
    show PairingV2Person;
import 'package:regalos/features/sync/presentation/person_picker.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

Widget _picker() => SingleChildScrollView(
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: PersonPicker(
      title: 'Titulo',
      body: 'Cuerpo',
      people: const [
        PairingV2Person('a', 'Aritz'),
        PairingV2Person('n', 'Nora'),
        PairingV2Person('l', 'Leo'),
      ],
      notOnListLabel: 'No esta',
      nobodyLabel: 'Nadie',
      nameLabel: 'Nombre',
      onPerson: (_) {},
      onNew: (_, {required noGifts}) {},
    ),
  ),
);

void main() {
  setUpAll(loadInter);

  group('SoftNote', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fondo suave, radio 8, texto meta y un solo nodo · x$scale', (
        tester,
      ) async {
        await pumpThemed(
          tester,
          SoftNote(icon: SettingsIcons.lock, text: 'Una nota'),
          textScale: scale,
        );
        final box = tester.widget<Container>(
          find.descendant(
            of: find.byType(SoftNote),
            matching: find.byType(Container),
          ),
        );
        final deco = box.decoration! as BoxDecoration;
        final t = RegalosTokens.of(tester.element(find.byType(SoftNote)));
        expect(deco.color, t.soft);
        expect(deco.borderRadius, RegalosShape.card);
        final text = tester.widget<Text>(find.text('Una nota'));
        expect(text.style!.color, t.textOnSoft);
        // El icono crece con la letra y usa el color sobre suave.
        final icon = tester.widget<StrokeIcon>(find.byType(StrokeIcon));
        expect(icon.size, 18 * scale);
        expect(icon.color, t.textOnSoft);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('con acción, el botón va bajo la frase', (tester) async {
      await pumpThemed(
        tester,
        SoftNote(
          icon: SettingsIcons.lock,
          text: 'Una nota',
          action: TextButton(onPressed: () {}, child: const Text('Entendido')),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Entendido')).dy,
        greaterThan(tester.getBottomLeft(find.text('Una nota')).dy - 1),
      );
    });
  });

  group('filas del selector', () {
    testWidgets('elegir una fila no mueve su texto ni el de las demás', (
      tester,
    ) async {
      await pumpThemed(tester, _picker(), surfaceSize: const Size(390, 900));
      await tester.pumpAndSettle();
      final before = {
        for (final n in ['Aritz', 'Nora', 'Leo', 'No esta', 'Nadie'])
          n: tester.getTopLeft(find.text(n)),
      };
      await tester.tap(find.text('Nora'));
      await tester.pump();
      await tester.pumpAndSettle();
      for (final n in before.keys) {
        expect(tester.getTopLeft(find.text(n)), before[n], reason: n);
      }
    });

    testWidgets('el fondo de la fila elegida sale 8 por cada lado', (
      tester,
    ) async {
      await pumpThemed(tester, _picker(), surfaceSize: const Size(390, 900));
      await tester.tap(find.text('Nora'));
      await tester.pump();
      await tester.pumpAndSettle();
      final row = tester.getRect(find.byKey(const ValueKey('person:n')));
      expect(row.left, 16);
      final tint = find.descendant(
        of: find.byKey(const ValueKey('person:n')),
        matching: find.byType(DecoratedBox),
      );
      expect(tester.getRect(tint.first).left, 8);
    });

    testWidgets('el filete falta en la primera fila y en la elegida y la '
        'siguiente', (tester) async {
      await pumpThemed(tester, _picker(), surfaceSize: const Size(390, 900));
      int borders() {
        var n = 0;
        for (final key in const [
          'person:a',
          'person:n',
          'person:l',
          'notOnList',
          'nobody',
        ]) {
          final containers = tester.widgetList<Container>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Container),
            ),
          );
          final withBorder = containers.where((c) {
            final d = c.decoration;
            // El filete oculto sigue ahí, transparente.
            return d is BoxDecoration &&
                d.border != null &&
                (d.border! as Border).top.color != Colors.transparent;
          });
          n += withBorder.length;
        }
        return n;
      }

      // Nada elegido: filete en las cuatro que no son la primera.
      expect(borders(), 4);
      await tester.tap(find.text('Nora'));
      await tester.pump();
      await tester.pumpAndSettle();
      // Elegida «Nora» (2.ª): sin filete ella y la siguiente.
      expect(borders(), 2);
    });

    testWidgets('el visto se hace sitio siempre y las esquinas del icono son '
        'las del avatar', (tester) async {
      await pumpThemed(tester, _picker(), surfaceSize: const Size(390, 900));
      final icon = find.descendant(
        of: find.byKey(const ValueKey('notOnList')),
        matching: find.byType(Container),
      );
      final deco = tester.widget<Container>(icon.first).decoration;
      // El primer contenedor es el de la fila; el del icono es de 40.
      final iconBox = tester
          .widgetList<Container>(icon)
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.borderRadius != null);
      expect(
        iconBox.borderRadius,
        BorderRadius.circular(PersonAvatar.radiusFor(40)),
      );
      expect(deco, isNotNull);
    });
  });
}
