import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/layout/pane_selection.dart';
import 'package:regalos/core/motion/rolling_number.dart';
import 'package:regalos/core/motion/success_mark.dart';
import 'package:regalos/core/motion/unfold_section.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/theme/occasion_theme.dart';
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/core/widgets/confirm_dialog.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';

import '../helpers/screens.dart';

// La pasada de movimiento de Ocasiones y del editor de regalo: lo que se ve al
// marcar un regalo como comprado desde una ocasión, al desplegar los campos del
// pedido, al avisar de un duplicado y al elegir el tipo «Otra».

void main() {
  const tall = Size(390, 1900);
  final button = find.widgetWithText(FloatingActionButton, 'Añadir regalo');

  screenTest(
    'detalle de ocasión: marcar como comprado pliega la fila de «Por comprar» '
    'y avisa con Deshacer',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      phone.container.read(routerProvider).go('/occasions/seed-kings');
      await settle(tester);

      const title = 'Bici de 20" con cambios';
      // Una vez entre las personas y otra en «Por comprar» (la segunda).
      expect(find.text(title), findsNWidgets(2));
      double buyRowHeight() => tester
          .getSize(
            find
                .ancestor(
                  of: find.text(title).last,
                  matching: find.byWidgetPredicate(
                    (w) => w is ClipRect && w.child is Align,
                  ),
                )
                .first,
          )
          .height;
      final full = buyRowHeight();
      await tester.tap(
        find.bySemanticsLabel('Marcar como comprado: $title').first,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // La fila enseña su cambio un momento (la casilla barre) y no se pliega
      // hasta pasada la espera: sigue entera.
      expect(find.text(title), findsNWidgets(2));
      expect(buyRowHeight(), closeTo(full, 0.5));

      // Ya plegándose: más baja que entera, pero aún ahí.
      await tester.pump(const Duration(milliseconds: 330));
      expect(find.text(title), findsNWidgets(2));
      expect(buyRowHeight(), lessThan(full));
      expect(buyRowHeight(), greaterThan(0));

      await settle(tester);
      expect(find.text(title), findsOneWidget);
      expect(find.text('Deshacer'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);

      // Deshacer la vuelve a «Por comprar».
      await tester.tap(find.text('Deshacer'));
      await settle(tester);
      expect(find.text(title), findsNWidgets(2));
    },
    inlineDocumentTasks: true,
    size: tall,
  );

  screenTest(
    'detalle de ocasión: con «Reducir movimiento» la fila se va sin viajar',
    (tester, phone) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      phone.container.read(routerProvider).go('/occasions/seed-kings');
      await settle(tester);
      const title = 'Bici de 20" con cambios';
      await tester.tap(
        find.bySemanticsLabel('Marcar como comprado: $title').first,
      );
      await settle(tester);
      expect(find.text(title), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    },
    size: tall,
  );

  screenTest(
    'editor: los campos del pedido se despliegan al activar el interruptor y '
    'se pliegan al apagarlo',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(button);
      await settle(tester);

      const switchLabel = 'Es un encargo: lo pidió alguien';
      const nameLabel = 'Nombre de quien lo pidió';
      expect(find.text(nameLabel), findsNothing);
      expect(find.byType(UnfoldSection), findsWidgets);

      await tester.tap(find.text(switchLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Ya a la vista mientras crece.
      expect(find.text('Quién lo pidió'), findsWidgets);
      expect(find.text(nameLabel), findsOneWidget);
      await settle(tester);
      expect(find.text(nameLabel), findsOneWidget);

      await tester.tap(find.text(switchLabel));
      await settle(tester);
      expect(find.text(nameLabel), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    },
    size: tall,
  );

  screenTest(
    'editor: un duplicado avisa con el diálogo de la app, y «Revisar» no guarda',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final before = (await familyState(tester, phone)).view.gifts.length;

      await tester.tap(button);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Para quién')).first);
      await settle(tester);
      await tester.tap(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.text('Nora'),
            )
            .first,
      );
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Regalo'),
        'Puzle de 48 piezas',
      );
      await tapText(tester, 'Guardar');
      expect(find.byType(RegalosDialogSurface), findsOneWidget);
      expect(find.text('Posible duplicado'), findsOneWidget);

      await tapText(tester, 'Revisar');
      expect(find.byType(RegalosDialogSurface), findsNothing);
      expect(find.byType(GiftEditorScreen), findsOneWidget);
      expect((await familyState(tester, phone)).view.gifts.length, before);

      await tapText(tester, 'Guardar');
      await tapText(tester, 'Guardar igualmente');
      expect(find.byType(GiftEditorScreen), findsNothing);
      expect((await familyState(tester, phone)).view.gifts.length, before + 1);
    },
    size: tall,
  );

  screenTest(
    'editor: guardar sin título lleva la vista hasta el campo con el error',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(button);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Para quién')).first);
      await settle(tester);
      await tester.tap(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.text('Nora'),
            )
            .first,
      );
      await settle(tester);
      // Con la pantalla baja el título queda lejos de «Guardar»: se baja la
      // lista hasta abajo del todo y se guarda sin título.
      await tester.drag(find.byType(ListView).last, const Offset(0, -2000));
      await settle(tester);
      final field = find.widgetWithText(TextField, 'Regalo');
      // Fuera de la vista (y, en una lista perezosa, sin montar).
      expect(
        field.evaluate().isEmpty || tester.getTopLeft(field).dy < 0,
        isTrue,
      );

      await tapText(tester, 'Guardar');
      expect(find.text('Escribe qué regalo es.'), findsOneWidget);
      // La vista subió hasta el campo y el cursor está en él.
      final top = tester.getTopLeft(field).dy;
      expect(top, greaterThanOrEqualTo(0));
      expect(top, lessThan(500));
      final editable = tester.widget<TextField>(field);
      expect(editable.focusNode!.hasFocus, isTrue);
      expect(tester.hasRunningAnimations, isFalse);
    },
    size: const Size(390, 600),
  );

  screenTest(
    'ocasiones: cambiar la fecha reordena la lista y la fila viaja a su puesto',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Ocasiones').last);
      await settle(tester);

      final kings = find.text('Reyes');
      expect(kings, findsOneWidget);
      final before = tester.getTopLeft(kings).dy;
      final full = (await familyState(tester, phone)).view.occasions;
      final o = full.firstWhere((o) => o.id == 'seed-kings');
      await tester.runAsync(
        () => phone.container
            .read(familyControllerProvider.notifier)
            .upsertOccasion(
              Occasion(
                id: o.id,
                kind: o.kind,
                rawKind: o.rawKind,
                name: o.name,
                month: 11,
                day: 12,
                year: o.year,
                recurring: o.recurring,
                recipientId: o.recipientId,
                archived: o.archived,
                color: o.color,
                icon: o.icon,
              ),
            ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 40));
      // Pasa a ser la primera: a mitad de camino no está ni donde estaba ni
      // donde acabará.
      final moving = tester.getTopLeft(kings).dy;
      await settle(tester);
      final after = tester.getTopLeft(kings).dy;
      expect(after, lessThan(before));
      expect(moving, isNot(closeTo(after, 0.5)));
      expect(find.text('12 de noviembre'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    },
    size: tall,
  );

  screenTest(
    'presupuesto: las cifras ruedan, pasarse tiñe de aviso y cumplirlo '
    'dibuja un visto',
    (tester, phone) async {
      await seedSample(tester, phone);
      await setBudgets(tester, phone, {
        'seed-santa': 15000,
        'seed-kings': 30000,
      });
      await pumpRegalos(tester, phone);
      phone.container.read(routerProvider).go('/occasions/budget');
      await settle(tester);
      // Las tres cifras son de las que ruedan.
      expect(find.byType(RollingNumber), findsWidgets);
      expect(find.byType(DrawnCheck), findsNothing);

      // Las cifras de arriba cuentan solo las ocasiones con presupuesto.
      final t = phone.container.read(budgetProvider).budgeted;
      final left = t.leftCents!;
      expect(left, greaterThan(0));
      Gift spend(String id, int cents) => Gift(
        id: id,
        recipientId: 'aritz',
        title: 'Gasto $id',
        giverId: 'us',
        occasionId: 'seed-kings',
        status: GiftStatus.bought,
        rawStatus: 'bought',
        actualCents: cents,
        surprise: false,
        year: 2026,
      );
      // Gasta justo lo que quedaba: «Queda 0» y un visto que se dibuja.
      await driveAsync(
        tester,
        () => familyOf(phone).upsertGift(spend('met', left)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(DrawnCheck), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
      await settle(tester);

      // Y se pasa: el visto se va, la etiqueta cambia y la cifra se tiñe.
      await driveAsync(
        tester,
        () => familyOf(phone).upsertGift(spend('over', 500)),
      );
      await settle(tester);
      expect(find.byType(DrawnCheck), findsNothing);
      expect(find.text('Te pasas'), findsOneWidget);
      final tokens = Theme.of(tester.element(find.text('Te pasas')))
          .extension<RegalosTokens>()!;
      final colors = tester
          .widgetList<RollingNumber>(find.byType(RollingNumber))
          .map((n) => n.style.color);
      expect(colors, contains(tokens.danger));
      expect(tester.hasRunningAnimations, isFalse);
    },
    size: tall,
  );

  for (final dark in [false, true]) {
    screenTest(
      'dos paneles: la fila elegida de Ocasiones lleva el color de su '
      'ocasión (${dark ? 'oscuro' : 'claro'}), y «Presupuesto» el del acento',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(
          find.descendant(
            of: find.bySemanticsLabel('Navegación principal'),
            matching: find.text('Ocasiones'),
          ),
        );
        await settle(tester);

        final occasions = (await familyState(tester, phone)).view.occasions;
        final tio = OccasionTheme.forOccasion(
          occasions.firstWhere((o) => o.id == 'seed-tio'),
        ).palette;
        final kings = OccasionTheme.forOccasion(
          occasions.firstWhere((o) => o.id == 'seed-kings'),
        ).palette;
        SelectionScope scope() =>
            tester.widget<SelectionScope>(find.byType(SelectionScope));

        // La próxima ocasión (Tió) sale elegida, con su pastel y su tinta.
        expect(
          scope().fill,
          dark ? tio.tintaD.withValues(alpha: 0.12) : tio.pastel,
        );
        expect(scope().border, dark ? tio.tintaD : tio.tinta);

        // Otra ocasión: cambia a la suya.
        await tester.tap(find.text('Reyes').first);
        await settle(tester);
        expect(
          scope().fill,
          dark ? kings.tintaD.withValues(alpha: 0.12) : kings.pastel,
        );
        expect(scope().fill, isNot(tio.pastel));

        // «Presupuesto» no es una ocasión: el del acento.
        await tester.tap(find.text('Presupuesto de la casa').first);
        await settle(tester);
        final tokens = Theme.of(tester.element(find.byType(SelectionScope)))
            .extension<RegalosTokens>()!;
        expect(scope().fill, tokens.selection);
        expect(scope().border, tokens.ink);
        expect(tester.hasRunningAnimations, isFalse);
      },
      size: const Size(1280, 800),
      brightness: dark ? Brightness.dark : Brightness.light,
    );
  }
}
