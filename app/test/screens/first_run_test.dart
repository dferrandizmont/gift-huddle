import 'package:flutter/material.dart';
import 'package:regalos/core/widgets/occasion_countdown_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/pop_in.dart';
import 'package:regalos/core/motion/step_segments.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/presentation/family_texts.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/onboarding/presentation/onboarding_screen.dart';
import 'package:regalos/l10n/app_localizations_es.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';

Future<void> addPerson(
  WidgetTester tester,
  String name, {
  String? relation,
}) async {
  await tapText(tester, 'Añadir persona');
  await tester.enterText(find.widgetWithText(TextField, 'Nombre'), name);
  if (relation != null) {
    await tester.enterText(
      find.widgetWithText(TextField, 'Relación (opcional)'),
      relation,
    );
  }
  await tapText(tester, 'Guardar');
}

void main() {
  // Entre pasos, eje compartido horizontal e indicador de segmentos (M).
  group('el movimiento del primer uso', () {
    double fillOf(WidgetTester tester, int i) => tester
        .widget<Transform>(
          find
              .descendant(
                of: find.byType(StepSegments),
                matching: find.byType(Transform),
              )
              .at(i),
        )
        .transform
        .storage[0];

    screenTest('los pasos se cruzan con un eje compartido y el indicador '
        'llena un segmento', (tester, phone) async {
      await pumpRegalos(tester, phone);
      // Cinco pasos, cinco segmentos; el primero ya lleno.
      expect(
        find.descendant(
          of: find.byType(StepSegments),
          matching: find.byType(Transform),
        ),
        findsNWidgets(5),
      );
      expect(fillOf(tester, 0), 1);
      expect(fillOf(tester, 1), 0);
      final title = find.text('Te damos la bienvenida a Gift Huddle');
      final rest = tester.getTopLeft(title).dx;

      await tester.tap(find.text('Empezar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // El paso que se va sale hacia atrás y el que llega viene de delante.
      expect(title, findsOneWidget);
      expect(find.text('¿A quién le regaláis?'), findsOneWidget);
      expect(tester.getTopLeft(title).dx, lessThan(rest));
      expect(fillOf(tester, 1), inExclusiveRange(0, 1.01));
      await tester.pump(const Duration(milliseconds: 200));
      expect(title, findsNothing);
      await tester.pumpAndSettle();
      expect(fillOf(tester, 1), 1);
      expect(fillOf(tester, 2), 0);

      // Al volver, el segmento se vacía.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // Vuelve el paso de antes, ahora desde atrás (al revés).
      expect(title, findsOneWidget);
      expect(find.text('¿A quién le regaláis?'), findsOneWidget);
      expect(tester.getTopLeft(title).dx, lessThan(rest));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(title).dx, closeTo(rest, 0.01));
      expect(fillOf(tester, 1), 0);
      expect(find.text('¿A quién le regaláis?'), findsNothing);
    });

    screenTest('la persona que se añade se despliega y su avatar rebota', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      await tapText(tester, 'Empezar');
      await addPerson(tester, 'Aritz');
      // Su avatar entra con el rebote (PopIn) y no se pinta a tamaño pleno.
      expect(find.byType(PopIn), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Aritz'), findsOneWidget);
      // Quitarla pliega la fila.
      await tester.tap(find.bySemanticsLabel('Quitar a Aritz'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Aritz'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Aritz'), findsNothing);
    });

    screenTest('el pie con «Siguiente» sube con un fundido al salir de la '
        'bienvenida', (tester, phone) async {
      await pumpRegalos(tester, phone);
      expect(find.text('Siguiente'), findsNothing);
      await tester.tap(find.text('Empezar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final next = find.text('Siguiente');
      expect(next, findsOneWidget);
      double opacity() => tester
          .widget<FadeTransition>(
            find
                .ancestor(of: next, matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value;
      expect(opacity(), lessThan(1));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    screenTest('la entrada de la bienvenida se ve una vez: al volver atrás no '
        'se repite', (tester, phone) async {
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Empezar'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final title = find.text('Te damos la bienvenida a Gift Huddle');
      expect(title, findsOneWidget);
      // Nada sube en vertical: solo el eje compartido (horizontal).
      for (final t in tester.widgetList<Transform>(
        find.ancestor(of: title, matching: find.byType(Transform)),
      )) {
        expect(t.transform.getTranslation().y, 0);
      }
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    screenTest('con «Reducir movimiento» los pasos se cruzan sin moverse', (
      tester,
      phone,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpRegalos(tester, phone);
      final title = find.text('Te damos la bienvenida a Gift Huddle');
      final rest = tester.getTopLeft(title).dx;
      await tester.tap(find.text('Empezar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // (El sistema acorta los controladores normales: el paso que se va puede
      // haber desaparecido ya. Si sigue, no se ha movido ni un píxel.)
      if (title.evaluate().isNotEmpty) {
        expect(tester.getTopLeft(title).dx, rest);
      }
      await tester.pumpAndSettle();
      expect(title, findsNothing);
      expect(find.text('¿A quién le regaláis?'), findsOneWidget);
    });
  });

  screenTest('el primer uso va de la bienvenida a Personas, sin PIN', (
    tester,
    phone,
  ) async {
    await pumpRegalos(tester, phone);

    // Bienvenida: qué es la app y que nada sale del móvil.
    expect(find.text('Te damos la bienvenida a Gift Huddle'), findsOneWidget);
    expect(
      find.textContaining('Sin cuentas. Si sincronizáis dos móviles'),
      findsOneWidget,
    );
    expect(find.text('Paso 1 de 5'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre de este móvil'),
      'Móvil de Ana',
    );
    await tapText(tester, 'Empezar');

    // Personas: no se puede seguir sin ninguna.
    expect(find.text('¿A quién le regaláis?'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Siguiente'))
          .onPressed,
      isNull,
    );
    await addPerson(tester, 'Aritz', relation: 'Hijo');
    await addPerson(tester, 'Nora');
    expect(find.text('Aritz'), findsOneWidget);
    expect(find.text('Nora'), findsOneWidget);
    await tapText(tester, 'Siguiente');

    // Quién regala: «Nosotros» viene creado y paga la casa.
    expect(find.text('¿Quién regala?'), findsOneWidget);
    expect(find.text('Nosotros'), findsOneWidget);
    expect(find.text('Paga la casa'), findsOneWidget);
    await tapLabel(tester, 'Añadir Abuelos');
    expect(find.text('Abuelos'), findsWidgets);
    await tapText(tester, 'Siguiente');

    // Ocasiones: ES propone Navidad y Reyes; se añade el Tió.
    expect(find.text('¿Cuándo hay regalos?'), findsOneWidget);
    CheckboxListTile tile(String name) =>
        tester.widget(find.widgetWithText(CheckboxListTile, name));
    expect(tile('Navidad').value, isTrue);
    expect(tile('Reyes').value, isTrue);
    expect(tile('Tió').value, isFalse);
    await tapText(tester, 'Tió');
    await tapText(tester, 'Siguiente');

    // PIN: se explica por qué y se puede dejar para luego.
    expect(find.text('Protege los regalos'), findsOneWidget);
    expect(
      find.textContaining('para que nadie vea los regalos si coge el móvil'),
      findsOneWidget,
    );
    await tapText(tester, 'Ahora no');

    // Ya en Personas, con la cuenta atrás y las dos personas.
    expect(find.text('Te damos la bienvenida a Gift Huddle'), findsNothing);
    expect(find.text('Aritz'), findsOneWidget);
    expect(find.text('Nora'), findsOneWidget);
    expect(find.byType(OccasionCountdownCard), findsWidgets);

    final state = await familyState(tester, phone);
    expect(state.hasFamily, isTrue);
    expect(state.identity!.deviceName, 'Móvil de Ana');
    expect(state.view.recipients.map((r) => r.name), ['Aritz', 'Nora']);
    expect(
      state.view.recipients.firstWhere((r) => r.name == 'Aritz').relation,
      'Hijo',
    );
    expect(state.view.givers.map((g) => g.name), ['Abuelos', 'Nosotros']);
    expect(
      state.view.givers.firstWhere((g) => g.name == 'Nosotros').householdPays,
      isTrue,
    );
    expect(
      state.view.occasions.map((o) => o.kind),
      unorderedEquals([
        OccasionKind.tio,
        OccasionKind.santa,
        OccasionKind.kings,
      ]),
    );
    final lock = (await tester.runAsync(
      () => phone.container.read(lockControllerProvider.future),
    ))!;
    expect(lock.enabled, isFalse);
  });

  screenTest('con PIN, Personas enseña a todos y la cuenta atrás al terminar', (
    tester,
    phone,
  ) async {
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Empezar');
    await addPerson(tester, 'Aritz', relation: 'Hijo');
    await addPerson(tester, 'Nora');
    await tapText(tester, 'Siguiente');
    await tapLabel(tester, 'Añadir Abuelos');
    await tapText(tester, 'Siguiente');
    await tapText(tester, 'Tió');
    await tapText(tester, 'Siguiente');
    await tapText(tester, 'Crear PIN');

    // El PIN, escrito y repetido.
    for (var round = 0; round < 2; round++) {
      for (final digit in '2468'.split('')) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      if (round == 0) {
        await tapText(tester, 'Continuar');
      } else {
        await tester.tap(find.text('Guardar PIN'));
        // El móvil de prueba tiene huella: se ofrece y se deja para luego.
        await tester.pump();
        await tapText(tester, 'Ahora no');
      }
    }

    // Fotogramas sueltos mientras el disco guarda, como en un móvil.
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      // ignore: avoid_print
      print(
        '$i aritz=${find.text('Aritz').evaluate().length} nora=${find.text('Nora').evaluate().length} dias=${find.byType(OccasionCountdownCard).evaluate().length}',
      );
    }

    // Sin cambiar de pestaña: ya están las dos personas y la cuenta atrás.
    expect(find.text('Aritz'), findsOneWidget);
    expect(find.text('Nora'), findsOneWidget);
    expect(find.byType(OccasionCountdownCard), findsWidgets);
    final lock = (await tester.runAsync(
      () => phone.container.read(lockControllerProvider.future),
    ))!;
    expect(lock.pinSet, isTrue);
  }, writeDelay: const Duration(milliseconds: 90));

  screenTest('se puede volver atrás y los datos se conservan', (
    tester,
    phone,
  ) async {
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Empezar');
    await addPerson(tester, 'Leo');
    await tapText(tester, 'Siguiente');
    await tapLabel(tester, 'Atrás');
    expect(find.text('Leo'), findsOneWidget);
    expect(find.text('Paso 2 de 5'), findsOneWidget);
  });

  screenTest('con cumpleaños, el paso de ocasiones los muestra', (
    tester,
    phone,
  ) async {
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Empezar');
    await tapText(tester, 'Añadir persona');
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Nora');
    await tapText(tester, 'Elegir fecha');
    await tapText(tester, 'ACEPTAR');
    await tapText(tester, 'Guardar');
    await tapText(tester, 'Siguiente');
    await tapText(tester, 'Siguiente');
    expect(find.textContaining('Cumpleaños de Nora'), findsOneWidget);
  });

  screenTest('«Escanear el QR» sale de la bienvenida', (tester, phone) async {
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Escanear el QR');
    expect(
      find.text('Apunta la cámara al código QR del otro móvil.'),
      findsOneWidget,
    );
  }, scanner: (context, onCode) => const SizedBox());

  screenTest(
    '«Unirme con un enlace» sale de la bienvenida, sin crear antes una lista',
    (tester, phone) async {
      final semantics = tester.ensureSemantics();
      await pumpRegalos(tester, phone);
      await tester.ensureVisible(find.text('Unirme con un enlace'));
      await tester.pump();
      await tapText(tester, 'Unirme con un enlace');
      expect(
        find.text(
          'Pega el enlace que te enviaron. Quien te invitó tendrá que aceptar '
          'tu petición.',
        ),
        findsOneWidget,
      );
      // Pide un nombre corto para este móvil y no habla de Ajustes.
      expect(
        find.widgetWithText(TextField, 'Nombre de este móvil'),
        findsOneWidget,
      );
      expect(find.text('Compartir'), findsNothing);
      // Y se vuelve a la bienvenida.
      await tester.tap(find.bySemanticsLabel('Atrás'));
      await settle(tester);
      expect(find.text('Te damos la bienvenida a Gift Huddle'), findsOneWidget);
      semantics.dispose();
    },
    scanner: (context, onCode) => const SizedBox(),
  );

  test('la región: catalán es Cataluña; otro idioma, el país del móvil', () {
    expect(regionFor(const Locale('ca'), const Locale('es', 'ES')), 'ES-CT');
    expect(regionFor(const Locale('es'), const Locale('ca', 'ES')), 'ES-CT');
    expect(regionFor(const Locale('es'), const Locale('es', 'ES')), 'ES');
    expect(regionFor(const Locale('en'), const Locale('en')), '');
  });

  test(
    'commitOnboarding publica la familia entera de una vez, sin pasos a medias',
    () async {
      final phone = FakePhone();
      addTearDown(phone.dispose);
      // Todo lo que ve la app mientras se guarda el primer uso.
      final seen = <FamilyState>[];
      phone.container.listen<AsyncValue<FamilyState>>(
        familyControllerProvider,
        (_, next) {
          final value = next.value;
          if (value != null) {
            seen.add(value);
          }
        },
      );
      await phone.container.read(familyControllerProvider.future);
      await commitOnboarding(
        familyOf(phone),
        OnboardingDraft(
          people: [
            const Recipient(
              id: 'p',
              name: 'Aritz',
              colorIndex: 0,
              archived: false,
            ),
            const Recipient(
              id: 'n',
              name: 'Nora',
              colorIndex: 1,
              archived: false,
            ),
          ],
          givers: [
            const Giver(
              id: 'u',
              name: 'Nosotros',
              colorIndex: 0,
              householdPays: true,
              archived: false,
            ),
          ],
          kinds: {OccasionKind.tio, OccasionKind.santa, OccasionKind.kings},
        ),
        deviceName: 'Móvil',
        region: 'ES-CT',
      );
      // La ruta sale del primer uso en cuanto hay familia: ese primer estado
      // ya tiene que traer personas y ocasiones.
      final first = seen.firstWhere((state) => state.hasFamily);
      expect(first.view.recipients.map((r) => r.name), ['Aritz', 'Nora']);
      expect(first.view.givers, hasLength(1));
      expect(first.view.occasions, hasLength(3));
    },
  );

  test(
    'commitOnboarding guarda familia, personas, quien regala y ocasiones',
    () async {
      final phone = FakePhone();
      addTearDown(phone.dispose);
      final draft = OnboardingDraft(
        people: [
          const Recipient(
            id: 'p',
            name: 'Aritz',
            colorIndex: 0,
            birthMonth: 3,
            birthDay: 1,
            archived: false,
          ),
        ],
        givers: [
          const Giver(
            id: 'u',
            name: 'Nosotros',
            colorIndex: 0,
            householdPays: true,
            archived: false,
          ),
        ],
        kinds: {OccasionKind.kings},
        extraOccasions: [
          const Occasion(
            id: 'c',
            kind: OccasionKind.custom,
            rawKind: 'custom',
            name: 'Comunión',
            month: 5,
            day: 20,
            recurring: false,
            year: 2027,
            archived: false,
          ),
        ],
      );
      await commitOnboarding(
        familyOf(phone),
        draft,
        deviceName: 'Móvil',
        region: 'ES',
      );
      final state = await phone.container.read(familyControllerProvider.future);
      expect(state.hasFamily, isTrue);
      expect(state.view.recipients.single.name, 'Aritz');
      expect(state.view.givers.single.householdPays, isTrue);
      expect(
        state.view.occasions.map(
          (o) => occasionTitle(AppLocalizationsEs(), o, personName: 'Aritz'),
        ),
        unorderedEquals(['Reyes', 'Comunión', 'Cumpleaños de Aritz']),
      );
      // Las de serie no guardan el nombre: lo pone cada móvil en su idioma.
      expect(
        state.view.occasions.map((o) => o.name),
        unorderedEquals(['', '', 'Comunión']),
      );
    },
  );
}
