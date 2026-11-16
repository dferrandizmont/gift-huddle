import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/fit_text.dart';
import 'package:regalos/features/family/presentation/giver_picker.dart';
import 'package:regalos/features/family/presentation/reparto_occasion_view.dart'
    show kRepartoOccasionTabsKey;

import '../helpers/fonts.dart';
import '../helpers/screens.dart';
import 'text_scale_200_reparto_test.dart' show findTextProblems;

// Puntos concretos de «letra al 200 %» con datos escogidos para apretarlos: un
// nombre largo de persona, la cuenta del pie de la rejilla con dos cifras, el
// chip de quien regala apilado y FitText a letra 1,0.

Finder get _vertical => find
    .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
    .first;

/// Baja la pantalla de a poco hasta que [finder] existe.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 12 && finder.evaluate().isEmpty; i++) {
    await tester.drag(_vertical, const Offset(0, -200), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUpAll(loadInter);

  const tabs = <String, String>{'ca': 'Repartiment', 'es': 'Reparto'};
  const occasionView = <String, String>{
    'ca': 'Per ocasió',
    'es': 'Por ocasión',
  };

  for (final lang in ['ca', 'es']) {
    screenTest(
      '$lang 320x640 a letra 2.0: un nombre largo de persona se lee entero '
      'en la lista y, en la rejilla, a lo sumo acaba en «…» sin partirse',
      (tester, phone) async {
        tester.platformDispatcher.localesTestValue = [Locale(lang)];
        tester.platformDispatcher.localeTestValue = Locale(lang);
        await seedSample(tester, phone);
        await tester.runAsync(
          () => familyOf(phone).upsertRecipient(
            const Recipient(
              id: 'larga',
              name: 'Nora Aritzaleku',
              colorIndex: 2,
              archived: false,
            ),
          ),
        );
        await pumpRegalos(tester, phone);
        const screen = Size(320, 640);
        await tester.tap(find.text(tabs[lang]!).last);
        await settle(tester);
        // Rejilla: es lo que escribe la persona y la columna mide poco, así
        // que el nombre puede acabar en «…» (declarado aquí a propósito);
        // ninguna palabra se parte a mitad y no hay desbordes.
        final grid = findTextProblems(
          tester,
          screen,
          ellipsisOk: {'Nora Aritzaleku'},
        );
        expect(tester.takeException(), isNull);
        expect(grid, isEmpty, reason: grid.join('\n'));

        // Lista por ocasión: el nombre se lee entero, sin «…» en ninguna parte.
        await tester.tap(find.bySemanticsLabel(occasionView[lang]!));
        await settle(tester);
        final found = <String>[];
        for (var i = 0; i < 8; i++) {
          found.addAll(
            findTextProblems(tester, screen).map((p) => 'lista$i: $p'),
          );
          await tester.drag(
            _vertical,
            const Offset(0, -300),
            warnIfMissed: false,
          );
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(tester.takeException(), isNull);
        expect(found, isEmpty, reason: found.join('\n'));
      },
      size: const Size(320, 640),
      textScale: 2,
    );
  }

  screenTest(
    'es 320x640 a letra 2.0: la cuenta de cada quien regala del pie de la '
    'rejilla cabe con dos cifras y seis columnas',
    (tester, phone) async {
      tester.platformDispatcher.localesTestValue = const [Locale('es')];
      tester.platformDispatcher.localeTestValue = const Locale('es');
      await seedSample(tester, phone);
      await tester.runAsync(() async {
        for (var i = 0; i < 12; i++) {
          await familyOf(phone).upsertGift(
            Gift(
              id: 'extra$i',
              recipientId: const ['aritz', 'nora', 'leo'][i % 3],
              title: 'Regalo extra $i',
              giverId: 'us',
              occasionId: 'seed-kings',
              status: GiftStatus.idea,
              rawStatus: 'idea',
              surprise: false,
              year: 2026,
            ),
          );
        }
      });
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Reparto').last);
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Total'),
        200,
        scrollable: _vertical,
      );
      await tester.pump(const Duration(milliseconds: 300));
      // «Nosotros» tiene 14 regalos o más: dos cifras.
      final twoDigits = find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^\d\d$').hasMatch(w.data ?? ''),
      );
      expect(twoDigits, findsWidgets);
      final problems = findTextProblems(tester, const Size(320, 640));
      expect(tester.takeException(), isNull);
      expect(problems, isEmpty, reason: problems.join('\n'));
      for (final e in twoDigits.evaluate()) {
        final p = e.renderObject! as RenderParagraph;
        // Una sola línea: la cifra no se parte.
        expect(p.size.height, lessThan(40), reason: 'la cifra no se parte');
      }
    },
    size: const Size(320, 640),
    textScale: 2,
  );

  screenTest(
    'es 320x640 a letra 2.0: «Avis de Girona» se lee entero en el chip de '
    'quien regala de la hoja y de la lista',
    (tester, phone) async {
      tester.platformDispatcher.localesTestValue = const [Locale('es')];
      tester.platformDispatcher.localeTestValue = const Locale('es');
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      Future<void> check(String where) async {
        final chips = find.descendant(
          of: find.byType(GiverChip),
          matching: find.text('Avis de Girona'),
        );
        expect(chips, findsWidgets, reason: where);
        for (final e in chips.evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          expect(p.didExceedMaxLines, isFalse, reason: where);
        }
        final problems = findTextProblems(tester, const Size(320, 640));
        expect(tester.takeException(), isNull, reason: where);
        expect(problems, isEmpty, reason: '$where: ${problems.join('\n')}');
      }

      // La hoja de la celda «Avis de Girona» para Nora.
      await tester.tap(find.text('Reparto').last);
      await settle(tester);
      final cell = find.bySemanticsLabel(
        RegExp('^Avis de Girona para Nora: 1'),
      );
      await _reveal(tester, cell);
      await tester.ensureVisible(cell.first);
      await tester.pump();
      await tester.tap(cell.first);
      await settle(tester);
      await check('hoja');
      await tester.binding.handlePopRoute();
      await settle(tester);

      // La lista, en la pestaña de Navidad (el regalo de Nora).
      await tester.tap(find.bySemanticsLabel('Por ocasión'));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byKey(kRepartoOccasionTabsKey),
          matching: find.text('Navidad'),
        ),
      );
      await settle(tester);
      await _reveal(
        tester,
        find.descendant(
          of: find.byType(GiverChip),
          matching: find.text('Avis de Girona'),
        ),
      );
      await check('lista');
    },
    size: const Size(320, 640),
    textScale: 2,
  );

  screenTest(
    'a letra 1,0 cada FitText pinta su texto con el estilo y las líneas que '
    'le dieron, sin encoger nada (título de pantalla y nombre de persona)',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      for (final tab in ['Reparto', 'Personas', 'Ocasiones', 'Ajustes']) {
        await tester.tap(find.text(tab).last);
        await settle(tester);
        for (final view in tab == 'Reparto' ? [null, 'Por ocasión'] : [null]) {
          if (view != null) {
            await tester.tap(find.bySemanticsLabel(view));
            await settle(tester);
          }
          final fits = find.byType(FitText);
          expect(fits, findsWidgets, reason: '$tab $view');
          for (final e in fits.evaluate()) {
            final fit = e.widget as FitText;
            final text = tester.widget<Text>(
              find.descendant(
                of: find.byWidget(fit),
                matching: find.byType(Text),
              ),
            );
            expect(text.style, fit.style, reason: fit.text);
            expect(text.maxLines, fit.maxLines, reason: fit.text);
            expect(text.softWrap, isNull, reason: fit.text);
            expect(text.overflow, fit.overflow, reason: fit.text);
          }
        }
      }
    },
  );
}
