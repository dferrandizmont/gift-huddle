// «No estoy en la lista» con un nombre que ya existe (QA 1.0.7, m8): antes de
// crear a otra persona, el selector pregunta «Ya hay alguien llamado Leo en la lista. ¿Eres
// tú?» con «Soy yo» (elige a la existente) y «Es otra persona» (crea la nueva).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart'
    show PairingV2Person;
import 'package:regalos/features/sync/presentation/person_picker.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

class _Calls {
  final List<String> persons = [];
  final List<String> news = [];
}

Widget _picker(
  _Calls calls, {
  bool ask = true,
  List<PairingV2Person> people = const [
    PairingV2Person('a', 'Aritz'),
    PairingV2Person('n', 'Nora'),
    PairingV2Person('l', 'Leo'),
    PairingV2Person('m', 'María'),
  ],
}) => SingleChildScrollView(
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Builder(
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return PersonPicker(
          title: 'Titulo',
          body: 'Cuerpo',
          people: people,
          notOnListLabel: 'No estoy en la lista',
          nobodyLabel: 'Nadie',
          nameLabel: 'Nombre',
          onPerson: calls.persons.add,
          onNew: (name, {required noGifts}) => calls.news.add('$name:$noGifts'),
          sameNameAsk: ask
              ? SameNameAsk(
                  title: l10n.personSameNameTitle,
                  body: l10n.whoAreYouSameNameBody,
                  yes: l10n.whoAreYouSameNameYes,
                  no: l10n.personSameNameOther,
                )
              : null,
        );
      },
    ),
  ),
);

Future<void> _type(WidgetTester tester, String option, String name) async {
  await tester.tap(find.byKey(ValueKey<String>(option)));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), name);
  await tester.pump();
  await tester.ensureVisible(
    find.byKey(const ValueKey<String>('personPickerContinue')),
  );
  await tester.tap(find.byKey(const ValueKey<String>('personPickerContinue')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadInter);

  group('personNameKey', () {
    test('sin mayúsculas, sin acentos y sin espacios de más', () {
      expect(personNameKey('  LEO '), 'leo');
      expect(personNameKey('María  José'), 'maria jose');
      expect(personNameKey('Joan\tCarles'), 'joan carles');
      expect(personNameKey('Ñandú'), 'nandu');
      expect(personNameKey(''), '');
    });
  });

  testWidgets('el mismo nombre pregunta y «Soy yo» elige a la persona '
      'existente', (tester) async {
    final calls = _Calls();
    await pumpThemed(tester, _picker(calls));
    await _type(tester, 'notOnList', '  leo ');
    expect(find.text('Ya hay alguien llamado Leo en la lista'), findsOneWidget);
    expect(find.textContaining('¿Eres tú?'), findsOneWidget);
    expect(calls.persons, isEmpty);
    expect(calls.news, isEmpty);
    await tester.tap(find.text('Soy yo'));
    await tester.pumpAndSettle();
    expect(calls.persons, ['l']);
    expect(calls.news, isEmpty);
    expect(find.text('Ya hay alguien llamado Leo en la lista'), findsNothing);
  });

  testWidgets('«Es otra persona» crea la nueva con lo escrito', (tester) async {
    final calls = _Calls();
    await pumpThemed(tester, _picker(calls));
    await _type(tester, 'notOnList', 'Leo');
    await tester.tap(find.text('Es otra persona'));
    await tester.pumpAndSettle();
    expect(calls.news, ['Leo:false']);
    expect(calls.persons, isEmpty);
  });

  testWidgets('sin acentos: «maria» es «María»', (tester) async {
    final calls = _Calls();
    await pumpThemed(tester, _picker(calls));
    await _type(tester, 'notOnList', 'maria');
    expect(find.text('Ya hay alguien llamado María en la lista'), findsOneWidget);
    await tester.tap(find.text('Soy yo'));
    await tester.pumpAndSettle();
    expect(calls.persons, ['m']);
  });

  testWidgets('cerrar el aviso sin elegir no hace nada', (tester) async {
    final calls = _Calls();
    await pumpThemed(tester, _picker(calls));
    await _type(tester, 'notOnList', 'Leo');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Ya hay alguien llamado Leo en la lista'), findsNothing);
    expect(calls.persons, isEmpty);
    expect(calls.news, isEmpty);
    // El campo sigue con el nombre y se puede continuar otra vez.
    expect(find.widgetWithText(TextField, 'Leo'), findsOneWidget);
  });

  testWidgets('un nombre nuevo no pregunta', (tester) async {
    final calls = _Calls();
    await pumpThemed(tester, _picker(calls));
    await _type(tester, 'notOnList', 'Zed');
    expect(find.textContaining('Ya hay'), findsNothing);
    expect(calls.news, ['Zed:false']);
  });

  testWidgets('«Nadie» y un selector sin aviso no preguntan', (tester) async {
    final nobody = _Calls();
    await pumpThemed(tester, _picker(nobody));
    await _type(tester, 'nobody', 'Leo');
    expect(find.textContaining('Ya hay'), findsNothing);
    expect(nobody.news, ['Leo:true']);

    final plain = _Calls();
    await pumpThemed(tester, _picker(plain, ask: false));
    await _type(tester, 'notOnList', 'Leo');
    expect(find.textContaining('Ya hay'), findsNothing);
    expect(plain.news, ['Leo:false']);
  });

  for (final (locale, title, yes, no) in [
    (
      const Locale('ca'),
      'Ja hi ha algú anomenat Leo a la llista',
      'Sóc jo',
      'És una altra persona',
    ),
    (
      const Locale('en'),
      'Someone called Leo is already on the list',
      "That's me",
      'Someone else',
    ),
  ]) {
    testWidgets('${locale.languageCode}: textos del aviso', (tester) async {
      final calls = _Calls();
      await pumpThemed(tester, _picker(calls), locale: locale);
      await _type(tester, 'notOnList', 'leo');
      expect(find.text(title), findsOneWidget);
      expect(find.text(yes), findsOneWidget);
      expect(find.text(no), findsOneWidget);
      await tester.tap(find.text(no));
      await tester.pumpAndSettle();
      expect(calls.news, ['leo:false']);
    });
  }

  testWidgets('con letra enorme el aviso no desborda y los botones se '
      'apilan', (tester) async {
    final calls = _Calls();
    await pumpThemed(
      tester,
      _picker(calls),
      textScale: 2,
      surfaceSize: const Size(360, 740),
    );
    await _type(tester, 'notOnList', 'Leo');
    expect(find.text('Soy yo'), findsOneWidget);
    expect(find.text('Es otra persona'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
