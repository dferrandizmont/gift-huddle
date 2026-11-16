// Capturas de todas las pantallas en claro y oscuro, para revisarlas a ojo.
//
// No corre con el resto de pruebas: hay que pedirlo con
//   flutter test test/screens/capture_test.dart --dart-define=CAPTURE=true
// Las imágenes van a `build/screens/` (ignorado por git): `pantallas/` para las
// pantallas y `temas/` para los temas de ocasión.
//
// Con `--dart-define=CAPTURE_TABLET=true` además, hace solo las pantallas a
// 800 × 1280 y 1280 × 800 (los tamaños del plan de tablet), en
// subcarpetas por orientación de la carpeta de capturas de prueba.
//
// Con `--dart-define=CAPTURE_WEB=true` además, hace las pantallas principales
// con la app en modo web a los anchos de escritorio (`kWebDesktopSizes`), en
// la carpeta de capturas de prueba.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/lock/presentation/pin_pad.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;

import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/tablet.dart';
import '../web_device/presentation/gate_test_support.dart';

const bool _capture = bool.fromEnvironment('CAPTURE');
const bool _tablet = bool.fromEnvironment('CAPTURE_TABLET');
const bool _web = bool.fromEnvironment('CAPTURE_WEB');

/// Las ventanas de escritorio de la web (la guía de diseño de escritorio):
/// 1280, el portátil de 15″ al 125 %, el monitor de 27″ y el ultrapanorámico.
const List<Size> kWebDesktopSizes = [
  Size(1280, 720),
  Size(1536, 740),
  Size(2560, 1300),
  Size(3440, 1300),
];

final GlobalKey _boundary = GlobalKey();

/// Carga Roboto del SDK: sin ella las pruebas pintan el texto con bloques.
///
/// También la registra como «Ahem», la fuente de las pruebas para el texto sin
/// familia (los botones), para que las capturas se lean.
Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    return;
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File(
            '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
  for (final family in ['Roboto', 'Ahem']) {
    final loader = FontLoader(family);
    for (final name in ['regular', 'medium', 'bold']) {
      final file = File(
        '$root/bin/cache/artifacts/material_fonts/roboto-$name.ttf',
      );
      if (file.existsSync()) {
        loader.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }
}

Future<void> _mount(
  WidgetTester tester,
  FakePhone phone, {
  bool web = false,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: RepaintBoundary(
        key: _boundary,
        child: RegalosApp(webSession: web),
      ),
    ),
  );
  await settle(tester);
}

Future<void> _shot(
  WidgetTester tester,
  String name, {
  String dir = 'pantallas',
  double pixelRatio = 2,
}) async {
  await settle(tester);
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/screens/$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}

void _go(FakePhone phone, String path) =>
    phone.container.read(routerProvider).go(path);

/// Escribe [pin] en el teclado del PIN que está a la vista.
Future<void> _typePin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(
      find.descendant(of: find.byType(PinPad), matching: find.text(digit)),
    );
    await tester.pump();
  }
}

/// En las capturas no hay cámara: un fondo oscuro en su sitio.
Widget _fakeCamera(BuildContext context, ValueChanged<String> onCode) =>
    const ColoredBox(color: Color(0xFF2A2A31));

void _scenes(
  Brightness brightness,
  String suffix, {
  Size size = kPhoneSize,
  String dir = 'pantallas',
  double pixelRatio = 2,
  List<Override> overrides = const <Override>[],
  bool onlyMain = false,
}) {
  Future<void> shot(WidgetTester tester, String name) =>
      _shot(tester, name, dir: dir, pixelRatio: pixelRatio);

  if (onlyMain) {
    _mainScenes(brightness, suffix, size, shot, overrides);
    return;
  }

  screenTest(
    'primer uso $suffix',
    (tester, phone) async {
      await _mount(tester, phone);
      await shot(tester, 'p01-bienvenida-$suffix');
      await tapText(tester, 'Empezar');
      await tapText(tester, 'Añadir persona');
      await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Nora');
      await tester.enterText(
        find.widgetWithText(TextField, 'Relación (opcional)'),
        'Sobrina',
      );
      await shot(tester, 'p02-persona-hoja-$suffix');
      await tapText(tester, 'Guardar');
      await tapText(tester, 'Añadir persona');
      await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Aritz');
      await tapText(tester, 'Guardar');
      await shot(tester, 'p03-personas-$suffix');
      await tapText(tester, 'Siguiente');
      await tapLabel(tester, 'Añadir Abuelos');
      await shot(tester, 'p04-quien-regala-$suffix');
      await tapText(tester, 'Siguiente');
      await shot(tester, 'p05-ocasiones-$suffix');
      await tapText(tester, 'Siguiente');
      await shot(tester, 'p06-pin-$suffix');
      await tapText(tester, 'Crear PIN');
      await shot(tester, 'p07-crear-pin-$suffix');
    },
    brightness: brightness,
    size: size,
  );

  screenTest(
    'unirse con QR o con enlace $suffix',
    (tester, phone) async {
      await _mount(tester, phone);
      await tapText(tester, 'Escanear el QR');
      await shot(tester, 'p08-escanear-qr-$suffix');
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.ensureVisible(find.text('Unirme con un enlace'));
      await tester.pump();
      await tapText(tester, 'Unirme con un enlace');
      await shot(tester, 'p09-unirse-enlace-$suffix');
    },
    brightness: brightness,
    size: size,
    scanner: _fakeCamera,
  );

  screenTest(
    'bloqueo, PIN y QR de emparejar $suffix',
    (tester, phone) async {
      await seedSample(tester, phone, pin: true);
      await _mount(tester, phone);
      await tester.runAsync(
        () => phone.container.read(lockControllerProvider.notifier).lockNow(),
      );
      await shot(tester, 'd01-bloqueo-$suffix');
      await _typePin(tester, '0000');
      await shot(tester, 'd02-bloqueo-pin-erroneo-$suffix');
      await _typePin(tester, '1234');
      await settle(tester);

      _go(phone, '/settings/security');
      await settle(tester);
      await tapText(tester, 'Cambiar PIN');
      await shot(tester, 'd03-pin-actual-$suffix');
      await _typePin(tester, '1234');
      await tapText(tester, 'Continuar');
      await _typePin(tester, '43');
      await shot(tester, 'd04-pin-nuevo-$suffix');
      await tester.binding.handlePopRoute();
      await settle(tester);

      _go(phone, '/settings/share');
      await settle(tester);
      await tapText(tester, 'Conectar otro móvil');
      await tapText(tester, 'Está aquí');
      await shot(tester, 'd05-ensenar-qr-$suffix');
    },
    brightness: brightness,
    size: size,
  );

  _mainScenes(brightness, suffix, size, shot, const <Override>[]);

  screenTest(
    'rejilla con más personas y letra grande $suffix',
    (tester, phone) async {
      await seedSample(tester, phone, extraPeople: 2);
      await _mount(tester, phone);
      _go(phone, '/family');
      await shot(tester, 'b01-familia-5-personas-$suffix');
    },
    brightness: brightness,
    size: size,
  );
  _restScenes(brightness, suffix, size, shot);
}

/// Las pantallas principales con la muestra de siempre.
void _mainScenes(
  Brightness brightness,
  String suffix,
  Size size,
  Future<void> Function(WidgetTester tester, String name) shot,
  List<Override> overrides,
) {
  screenTest(
    'pantallas $suffix',
    (tester, phone) async {
      await seedSample(tester, phone);
      await _mount(tester, phone, web: overrides.isNotEmpty);
      await shot(tester, 'a01-personas-$suffix');
      _go(phone, '/people/aritz');
      await shot(tester, 'a02-lista-aritz-$suffix');
      _go(phone, '/people/aritz?giver=us');
      await shot(tester, 'a03-lista-aritz-filtrada-$suffix');
      _go(phone, '/family');
      await shot(tester, 'a04-familia-$suffix');
      _go(phone, '/occasions');
      await shot(tester, 'a05-ocasiones-$suffix');
      _go(phone, '/occasions/seed-kings');
      await shot(tester, 'a06-reyes-$suffix');
      _go(phone, '/occasions/birthday-nora');
      await shot(tester, 'a07-cumple-nora-$suffix');
      _go(phone, '/occasions/budget');
      await shot(tester, 'a08-presupuesto-$suffix');
      _go(phone, '/settings');
      await shot(tester, 'a09-ajustes-$suffix');
      _go(phone, '/settings/security');
      await shot(tester, 'a10-seguridad-$suffix');
      _go(phone, '/settings/share');
      await shot(tester, 'a11-compartir-$suffix');
      _go(phone, '/settings/backup');
      await shot(tester, 'a12-copia-$suffix');
      _go(phone, '/settings/people');
      await shot(tester, 'a13-gestionar-personas-$suffix');
      _go(phone, '/settings/givers');
      await shot(tester, 'a14-gestionar-quien-regala-$suffix');

      _go(phone, '/people/aritz');
      await settle(tester);
      // En escritorio no hay «+» flotante: la N abre el editor de la persona
      // elegida.
      if (find.byType(FloatingActionButton).evaluate().isNotEmpty) {
        await tester.tap(find.byType(FloatingActionButton));
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      }
      await shot(tester, 'a15-regalo-nuevo-$suffix');
      await settle(tester);
      final editorScroll = find
          .descendant(
            of: find.byType(GiftEditorScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Es un encargo: lo pidió alguien'),
        300,
        // Con dos paneles hay listas debajo: la del editor es la suya.
        scrollable: editorScroll,
      );
      await tapText(tester, 'Es un encargo: lo pidió alguien');
      await tester.drag(editorScroll, const Offset(0, -400));
      await shot(tester, 'a16-regalo-encargo-$suffix');

      if (overrides.isNotEmpty) {
        // El tablero «Hoy» con el editor fijo a la derecha, sobre un regalo
        // de un carril.
        _go(phone, '/people');
        await settle(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        await shot(tester, 'a00-hoy-$suffix');
        await tester.tap(find.text('Bici de 20" con cambios').first);
        await shot(tester, 'a17-hoy-editor-$suffix');
      }
    },
    brightness: brightness,
    size: size,
    overrides: overrides,
  );
}

void _restScenes(
  Brightness brightness,
  String suffix,
  Size size,
  Future<void> Function(WidgetTester tester, String name) shot,
) {
  screenTest(
    'texto al 130 por ciento $suffix',
    (tester, phone) async {
      await seedSample(tester, phone);
      await _mount(tester, phone);
      _go(phone, '/family');
      await shot(tester, 'c01-familia-130-$suffix');
      _go(phone, '/people/aritz');
      await shot(tester, 'c02-lista-130-$suffix');
      _go(phone, '/occasions/seed-kings');
      await shot(tester, 'c03-reyes-130-$suffix');
    },
    brightness: brightness,
    textScale: 1.3,
    size: size,
  );
}

Occasion _extra(
  String id,
  OccasionKind kind,
  int month,
  int day,
  String name, {
  String? color,
  String? icon,
}) => Occasion(
  id: id,
  kind: kind,
  rawKind: kind.name,
  name: name,
  month: month,
  day: day,
  recurring: true,
  archived: false,
  color: color,
  icon: icon,
);

/// Capturas de los temas de ocasión, el carrusel, la barra, Reparto y el
/// teclado del PIN, a la carpeta de capturas de prueba.
void _themeScenes(Brightness brightness, String suffix) {
  Future<void> shot(WidgetTester tester, String name) =>
      _shot(tester, '$name-$suffix', dir: 'temas');

  screenTest('temas de ocasión $suffix', (tester, phone) async {
    await seedSample(tester, phone);
    await tester.runAsync(() async {
      final c = familyOf(phone);
      for (final o in [
        _extra('x-cny', OccasionKind.chineseNewYear, 2, 6, 'Año Nuevo Chino'),
        _extra('x-boda', OccasionKind.wedding, 6, 20, 'Boda de Marta'),
        _extra('x-aniv', OccasionKind.anniversary, 9, 3, 'Aniversario'),
        _extra('x-jordi', OccasionKind.santJordi, 4, 23, 'Sant Jordi'),
        _extra('x-valentin', OccasionKind.valentine, 2, 14, 'San Valentín'),
        _extra('x-bautizo', OccasionKind.baptism, 5, 2, 'Bautizo de Leo'),
        _extra('x-comunion', OccasionKind.communion, 5, 20, 'Comunión de Nora'),
        _extra('x-grado', OccasionKind.graduation, 6, 25, 'Fin de curso'),
        _extra(
          'x-otra',
          OccasionKind.custom,
          7,
          1,
          'Excursión',
          color: 'teal',
          icon: 'trip',
        ),
      ]) {
        await c.upsertOccasion(o);
      }
    });
    await _mount(tester, phone);
    for (final (id, name) in [
      ('seed-santa', 'santa'),
      ('seed-tio', 'tio'),
      ('seed-kings', 'reyes'),
      ('birthday-nora', 'cumple'),
      ('x-cny', 'ano-nuevo-chino'),
      ('x-boda', 'boda'),
      ('x-aniv', 'aniversario'),
      ('x-jordi', 'sant-jordi'),
      ('x-valentin', 'san-valentin'),
      ('x-bautizo', 'bautizo'),
      ('x-comunion', 'comunion'),
      ('x-grado', 'graduacion'),
      ('x-otra', 'otra'),
    ]) {
      _go(phone, '/occasions/$id');
      await shot(tester, 'tema-$name');
    }
  }, brightness: brightness);

  screenTest('carrusel, barra y Reparto $suffix', (tester, phone) async {
    await seedSample(tester, phone);
    await _mount(tester, phone);
    await shot(tester, 'carrusel-1');
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await settle(tester);
    await shot(tester, 'carrusel-2');
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await settle(tester);
    await shot(tester, 'carrusel-4');
    _go(phone, '/family');
    await shot(tester, 'reparto-cercana');
    await tester.tap(find.text('Todas'));
    await settle(tester);
    await shot(tester, 'reparto-todas');
    await tester.tap(find.text('Reyes').first);
    await settle(tester);
    await shot(tester, 'reparto-reyes');
    _go(phone, '/occasions');
    await shot(tester, 'barra-ocasiones');
    _go(phone, '/settings');
    await shot(tester, 'barra-ajustes');
  }, brightness: brightness);

  screenTest('Reparto con un nombre largo $suffix', (tester, phone) async {
    await seedSample(tester, phone);
    await tester.runAsync(
      () => familyOf(phone).upsertGiver(
        const Giver(
          id: 'long',
          name: 'Grandparents',
          colorIndex: 2,
          householdPays: false,
          archived: false,
        ),
      ),
    );
    await _mount(tester, phone);
    _go(phone, '/family');
    await settle(tester);
    await tester.tap(find.text('Todas'));
    await settle(tester);
    await shot(tester, 'reparto-nombre-largo');
  }, brightness: brightness);

  screenTest(
    'hoja de nueva ocasión $suffix',
    (tester, phone) async {
      await seedSample(tester, phone);
      await _mount(tester, phone);
      _go(phone, '/occasions');
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Nueva ocasión').first);
      await settle(tester);
      await shot(tester, 'hoja-tipos');
      await tester.tap(find.bySemanticsLabel('Otra').first);
      await settle(tester);
      await shot(tester, 'hoja-otra');
    },
    brightness: brightness,
    size: const Size(390, 1300),
  );

  screenTest('teclado del PIN $suffix', (tester, phone) async {
    await seedSample(tester, phone, pin: true);
    await _mount(tester, phone);
    await tester.runAsync(
      () => phone.container.read(lockControllerProvider.notifier).lockNow(),
    );
    await settle(tester);
    await shot(tester, 'pin-teclado');
    final gesture = await tester.startGesture(tester.getCenter(find.text('5')));
    await tester.pump(const Duration(milliseconds: 120));
    await shot(tester, 'pin-tecla-pulsada');
    await gesture.up();
  }, brightness: brightness);
}

void main() {
  if (!_capture) {
    test('capturas', () {}, skip: 'Solo con --dart-define=CAPTURE=true');
    return;
  }
  setUpAll(() async {
    await _loadRoboto();
    await loadInter();
  });
  if (_web) {
    for (final size in kWebDesktopSizes) {
      final label = '${size.width.round()}x${size.height.round()}';
      for (final (brightness, suffix) in const [
        (Brightness.light, 'claro'),
        (Brightness.dark, 'oscuro'),
      ]) {
        group(
          'web $label $suffix',
          () => _scenes(
            brightness,
            suffix,
            size: size,
            dir: 'pantallas/web-$label',
            pixelRatio: 1,
            overrides: [
              webAppProvider.overrideWithValue(true),
              webGateActionsProvider.overrideWithValue(FakeGateActions()),
              webDeviceStateProvider.overrideWithValue(
                const WebDeviceState(
                  status: WebSyncStatus.confirmed,
                  hasRoots: true,
                  setAsideChanges: 0,
                  persistenceDenied: false,
                ),
              ),
            ],
            onlyMain: true,
          ),
        );
      }
    }
    return;
  }
  if (_tablet) {
    for (final size in kTabletSizes) {
      final label = '${size.width.round()}x${size.height.round()}';
      for (final (brightness, suffix) in const [
        (Brightness.light, 'claro'),
        (Brightness.dark, 'oscuro'),
      ]) {
        group(
          'tablet $label $suffix',
          () => _scenes(
            brightness,
            suffix,
            size: size,
            dir: 'pantallas/tablet-$label',
            pixelRatio: 1,
          ),
        );
      }
    }
    return;
  }
  group('claro', () => _scenes(Brightness.light, 'claro'));
  group('oscuro', () => _scenes(Brightness.dark, 'oscuro'));
  group('temas claro', () => _themeScenes(Brightness.light, 'claro'));
  group('temas oscuro', () => _themeScenes(Brightness.dark, 'oscuro'));
}
