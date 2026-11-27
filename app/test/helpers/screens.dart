import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/more_details.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart'
    show GiftEditorScreen;
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/storage_providers.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/sharing/presentation/join_qr_screen.dart';
import 'package:regalos/features/tour/application/tour_state.dart';

import 'memory_stores.dart';
import 'pump_app.dart';

/// Hoy en las pruebas de pantallas: faltan 58 días para Reyes.
final DateTime kToday = DateTime(2026, 11, 9, 10);

/// Una prueba de pantalla: un móvil de prueba, el reloj parado en [kToday] y el
/// idioma del móvil en español.
void screenTest(
  String description,
  Future<void> Function(WidgetTester tester, FakePhone phone) body, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  ScannerBuilder? scanner,
  Duration writeDelay = Duration.zero,
  bool inlineDocumentTasks = false,
  List<Override> overrides = const <Override>[],
  String? syncHost = '',
  Map<String, Object> prefs = const <String, Object>{},
}) {
  // Por defecto la guía «Cómo funciona» ya está vista: si no, al terminar la
  // bienvenida se abriría sola y su demostración en bucle impediría que
  // `pumpAndSettle` acabe en las pruebas que solo pasan por la bienvenida. Las
  // de la guía piden lo contrario con `prefs: {kTourSeenKey: false}`.
  final initialPrefs = <String, Object>{kTourSeenKey: true, ...prefs};
  testWidgets(description, (tester) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    tester.platformDispatcher.localesTestValue = const [Locale('es', 'ES')];
    tester.platformDispatcher.localeTestValue = const Locale('es', 'ES');
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final semantics = tester.ensureSemantics();
    // Sin código nativo: los canales de enlaces y de ficheros no responden.
    for (final name in const [
      'com.llfbandit.app_links/events',
      'com.llfbandit.app_links/messages',
    ]) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (call) async => null,
      );
    }
    final phone = FakePhone(
      prefs: await mockPrefs(initialPrefs),
      writeDelay: writeDelay,
      syncHost: syncHost,
      extraOverrides: [
        if (inlineDocumentTasks)
          familyStoreProvider.overrideWith(
            (ref) => FamilyStore(
              secrets: ref.watch(secretStoreProvider),
              files: ref.watch(fileStoreProvider),
              deviceKeys: ref.watch(deviceKeysStoreProvider),
              runDocumentTask: _runInline,
            ),
          ),
        if (scanner != null) scannerBuilderProvider.overrideWithValue(scanner),
        ...overrides,
      ],
    );
    addTearDown(phone.dispose);
    try {
      await withClock(Clock.fixed(kToday), () => body(tester, phone));
    } finally {
      // Borrar un regalo deja un temporizador (el aviso con «Deshacer») que
      // escribe la lápida al caducar: se adelanta para no dejarlo pendiente.
      try {
        await flushDeletes(tester, phone);
      } on Object {
        // La prueba ya falló por otra cosa: no se esconde con otro error.
      }
      semantics.dispose();
    }
  });
}

Future<T> _runInline<T>(Future<T> Function() task) => task();

/// Ejecuta [action] (una escritura del controlador, por ejemplo) desde la zona
/// de la prueba y la espera repintando. Úsalo en vez de `runAsync` cuando la
/// interfaz ya ha escrito antes: la cola de escrituras del controlador cuelga
/// de futuros de la zona de la prueba, cuyos microtareas solo avanzan al
/// repintar; desde `runAsync` la espera no acababa nunca.
Future<T> driveAsync<T>(
  WidgetTester tester,
  Future<T> Function() action,
) async {
  var done = false;
  Object? error;
  StackTrace? trace;
  T? value;
  final run = action().then<void>(
    (v) {
      value = v;
      done = true;
    },
    onError: (Object e, StackTrace s) {
      error = e;
      trace = s;
      done = true;
    },
  );
  for (var i = 0; i < 300 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  if (!done) {
    throw StateError('driveAsync: la escritura no acabó en 3 s');
  }
  await run;
  if (error != null) Error.throwWithStackTrace(error!, trace!);
  return value as T;
}

/// Escribe ya las lápidas de los regalos que esperan el final del aviso con
/// «Deshacer» (véase [driveAsync]).
Future<void> flushDeletes(WidgetTester tester, FakePhone phone) => driveAsync(
  tester,
  () => phone.container
      .read(familyControllerProvider.notifier)
      .flushPendingDeletes(),
);

/// Abre «Más detalles» del editor de regalos (precio real, tienda, enlace,
/// talla y nota) si está plegada, bajando la lista hasta ella si hace falta.
/// No hace nada si ya está abierta, si el editor lleva todo abierto (dos
/// columnas) o si no hay editor de regalos a la vista.
Future<void> openMoreDetails(WidgetTester tester) async {
  final editor = find.byType(GiftEditorScreen);
  if (editor.evaluate().isEmpty) return;
  final toggle = find.text('Más detalles');
  final scrollable = find
      .descendant(of: editor, matching: find.byType(Scrollable))
      .first;
  try {
    await tester.scrollUntilVisible(
      toggle,
      100,
      maxScrolls: 20,
      scrollable: scrollable,
    );
  } on Object {
    return;
  }
  final section = find.byType(MoreDetails);
  if (section.evaluate().isEmpty ||
      tester.widget<MoreDetails>(section.first).open) {
    return;
  }
  // Entera y por encima del pie del panel: se baja del todo.
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pump();
  await tester.tap(toggle);
  await settle(tester);
}

/// Deja acabar los futuros reales (cifrado, almacenes) y repinta.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 150));
  }
  await tester.pumpAndSettle();
}

/// Como [settle], y además deja acabar el guardado de la persona de «Yo»
/// elegida desde la hoja de Ajustes.
///
/// Esa elección arranca justo al cerrarse la hoja (a los 340 ms de pulsar), y
/// su guardado pasa por la cola del almacén de claves, que nació en la zona
/// real (al sembrar con `runAsync`): sus pasos solo avanzan con un hueco de
/// tiempo real. `settle` lo da, pero antes de que arranque el guardado.
Future<void> settleSaved(WidgetTester tester) async {
  await settle(tester);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await settle(tester);
}

/// Monta la app entera sobre el móvil de prueba.
Future<void> pumpRegalos(WidgetTester tester, FakePhone phone) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: const RegalosApp(),
    ),
  );
  await settle(tester);
}

FamilyController familyOf(FakePhone phone) =>
    phone.container.read(familyControllerProvider.notifier);

/// Pone el presupuesto de varias ocasiones por id, en céntimos (`null` lo
/// quita). La muestra no trae ninguno.
Future<void> setBudgets(
  WidgetTester tester,
  FakePhone phone,
  Map<String, int?> budgets,
) async {
  await driveAsync(tester, () async {
    for (final entry in budgets.entries) {
      await familyOf(phone).setOccasionBudget(entry.key, entry.value);
    }
  });
  await tester.pump();
}

Future<FamilyState> familyState(WidgetTester tester, FakePhone phone) async =>
    (await tester.runAsync(
      () => phone.container.read(familyControllerProvider.future),
    ))!;

/// Rellena la familia de muestra: Aritz, Nora y Leo; «Nosotros», «Yayos de
/// Terrassa» y cuatro más; las ocasiones de Cataluña y unos cuantos regalos.
Future<void> seedSample(
  WidgetTester tester,
  FakePhone phone, {
  bool pin = false,
  int extraPeople = 0,
}) async {
  await tester.runAsync(() async {
    final c = familyOf(phone);
    await c.createFamily(deviceName: 'Móvil de prueba');
    final people = <Recipient>[
      const Recipient(
        id: 'aritz',
        name: 'Aritz',
        colorIndex: 0,
        birthMonth: 3,
        birthDay: 14,
        birthYear: 2019,
        archived: false,
      ),
      const Recipient(
        id: 'nora',
        name: 'Nora',
        colorIndex: 4,
        birthMonth: 6,
        birthDay: 12,
        birthYear: 2022,
        archived: false,
      ),
      const Recipient(
        id: 'leo',
        name: 'Leo',
        colorIndex: 3,
        birthMonth: 8,
        birthDay: 3,
        birthYear: 2024,
        archived: false,
      ),
      for (var i = 0; i < extraPeople; i++)
        Recipient(
          id: 'extra$i',
          name: 'Extra ${i + 1}',
          colorIndex: i,
          archived: false,
        ),
    ];
    for (final p in people) {
      await c.upsertRecipient(p);
    }
    const givers = <Giver>[
      Giver(
        id: 'us',
        name: 'Nosotros',
        colorIndex: 0,
        householdPays: true,
        archived: false,
      ),
      Giver(
        id: 'yayos',
        name: 'Yayos de Terrassa',
        colorIndex: 4,
        householdPays: false,
        archived: false,
      ),
      Giver(
        id: 'avis',
        name: 'Avis de Girona',
        colorIndex: 3,
        householdPays: false,
        archived: false,
      ),
      Giver(
        id: 'marta',
        name: 'Tía Marta y Jordi',
        colorIndex: 1,
        householdPays: false,
        archived: false,
      ),
      Giver(
        id: 'pere',
        name: 'Tío Pere',
        colorIndex: 2,
        householdPays: false,
        archived: false,
      ),
      Giver(
        id: 'anna',
        name: 'Padrina Anna',
        colorIndex: 5,
        householdPays: false,
        archived: false,
      ),
    ];
    for (final g in givers) {
      await c.upsertGiver(g);
    }
    await c.seedDefaultOccasions('ES-CT');

    Gift gift(
      String id,
      String recipient,
      String title, {
      String? giver,
      String? occasion,
      GiftStatus status = GiftStatus.idea,
      int? planned,
      int? actual,
      String? store,
      bool surprise = false,
      RequestedBy? requestedBy,
    }) => Gift(
      id: id,
      recipientId: recipient,
      title: title,
      giverId: giver,
      occasionId: occasion,
      status: status,
      rawStatus: status.name,
      plannedCents: planned,
      actualCents: actual,
      store: store,
      requestedBy: requestedBy,
      surprise: surprise,
      year: 2026,
    );

    final gifts = <Gift>[
      gift(
        'g1',
        'aritz',
        'Pijama de astronautas, talla 8',
        giver: 'us',
        occasion: 'seed-tio',
        status: GiftStatus.arrived,
        planned: 2400,
      ),
      gift(
        'g2',
        'aritz',
        'Libro de dinosaurios con solapas',
        giver: 'marta',
        occasion: 'seed-tio',
        planned: 1800,
        store: 'Librería',
      ),
      gift(
        'g3',
        'aritz',
        'Estación de bomberos de bloques',
        giver: 'us',
        occasion: 'seed-kings',
        status: GiftStatus.bought,
        planned: 5500,
        actual: 4999,
        requestedBy: const RequestedByRecipient('aritz'),
      ),
      gift(
        'g4',
        'aritz',
        'Bici de 20" con cambios',
        giver: 'yayos',
        occasion: 'seed-kings',
        status: GiftStatus.decided,
        planned: 18000,
        store: 'Decathlon',
        surprise: true,
      ),
      gift(
        'g5',
        'aritz',
        'Patinete',
        occasion: 'seed-kings',
        store: 'Juguetería del barrio',
      ),
      gift(
        'g6',
        'nora',
        'Puzle de 48 piezas',
        giver: 'avis',
        occasion: 'seed-santa',
        status: GiftStatus.decided,
        planned: 1900,
        store: 'Juguetería del barrio',
      ),
      gift(
        'g7',
        'nora',
        'Puzle de 48 piezas',
        giver: 'anna',
        occasion: 'seed-kings',
        planned: 3000,
      ),
      gift(
        'g8',
        'nora',
        'Cocinita de madera',
        giver: 'us',
        occasion: 'seed-santa',
        status: GiftStatus.wrapped,
        planned: 6450,
      ),
      gift(
        'g9',
        'leo',
        'Tren de madera',
        giver: 'us',
        occasion: 'seed-kings',
        status: GiftStatus.bought,
        planned: 3100,
      ),
      gift(
        'g10',
        'nora',
        'Libro de cuentos',
        giver: 'pere',
        occasion: 'seed-kings',
        status: GiftStatus.delivered,
        planned: 2500,
        actual: 2500,
      ),
    ];
    for (final g in gifts) {
      await c.upsertGift(g);
    }
    final lock = phone.container.read(lockControllerProvider.notifier);
    if (pin) {
      await lock.setPin('1234');
    } else {
      await lock.skipSetup();
    }
  });
}

/// Una familia recién creada, sin datos y sin PIN.
Future<void> bareFamily(WidgetTester tester, FakePhone phone) =>
    tester.runAsync(() async {
      await familyOf(phone).createFamily(deviceName: 'M');
      await phone.container.read(lockControllerProvider.notifier).skipSetup();
    });

/// Pulsa un texto y deja acabar lo que provoque.
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).first);
  await settle(tester);
}

/// Los textos que abren una hoja de la bienvenida: cada opción vive tras
/// «Unirme a una familia» o «Recuperar una copia».
const _joinChoices = ['Escanear el QR', 'Unirme con un enlace'];

/// En la bienvenida, abre la hoja que contiene [choice] y la elige: la opción
/// cierra la hoja y abre su pantalla.
Future<void> tapWelcomeChoice(WidgetTester tester, String choice) async {
  await openWelcomeSheet(tester, choice);
  await tester.tap(find.text(choice).last);
  await settle(tester);
}

/// En la bienvenida, abre la hoja que contiene [choice] sin elegir nada.
Future<void> openWelcomeSheet(WidgetTester tester, String choice) async {
  final opener = find.widgetWithText(
    OutlinedButton,
    _joinChoices.contains(choice)
        ? 'Unirme a una familia'
        : 'Recuperar una copia',
  );
  await tester.ensureVisible(opener);
  await tester.pump();
  await tester.tap(opener);
  await settle(tester);
}

/// Pulsa un control por su etiqueta accesible.
Future<void> tapLabel(WidgetTester tester, Pattern label) async {
  await tester.tap(find.bySemanticsLabel(label).first);
  await settle(tester);
}

/// Un importe como lo escribe `NumberFormat`: con espacio duro antes del euro.
String eur(String text) => text.replaceAll(' €', ' €');
