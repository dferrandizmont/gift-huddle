// Capturas para el pulido final de interfaz, en `build/screens/pulido-play/`
// (ignorado por git). Solo con
//
//   cd app && flutter test test/screens/pulido_capture_test.dart \
//     --dart-define=CAPTURE_PULIDO=antes
//
// El valor es la subcarpeta de la carpeta de capturas de prueba (`antes`, `despues`). Opcional:
// `--dart-define=CAPTURE_COMBOS=m-claro-es-1,t8-oscuro-en-1.3` para elegir
// combinaciones (formato `<tamaño>-<tema>-<idioma>-<letra>`; tamaños `m`
// móvil, `t8` tablet 800x1280, `t12` tablet 1280x800).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';

import 'package:regalos/features/sync/application/recovery_providers.dart';

import '../helpers/fake_recovery.dart';
import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/tablet.dart';

const String _dir = String.fromEnvironment('CAPTURE_PULIDO');
const String _combosArg = String.fromEnvironment('CAPTURE_COMBOS');

final GlobalKey _boundary = GlobalKey();

const List<String> _defaultCombos = [
  'm-claro-es-1',
  'm-oscuro-es-1',
  'm-claro-en-1.3',
  'm-oscuro-ca-1.3',
  't8-claro-es-1',
  't8-oscuro-es-1',
  't12-claro-es-1',
  't12-oscuro-es-1',
];

Future<void> _loadFonts() async {
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

Future<void> _mount(WidgetTester tester, FakePhone phone) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: RepaintBoundary(key: _boundary, child: const RegalosApp()),
    ),
  );
  await settle(tester);
}

Future<void> _shot(
  WidgetTester tester,
  String combo,
  String name, {
  bool settleFirst = true,
}) async {
  if (settleFirst) {
    await settle(tester);
  }
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/screens/pulido-play/$_dir/$combo/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}

void _go(FakePhone phone, String path) =>
    phone.container.read(routerProvider).go(path);

void _combo(String combo) {
  final parts = combo.split('-');
  final size = switch (parts[0]) {
    't8' => kTabletPortrait,
    't12' => kTabletLandscape,
    _ => kPhoneSize,
  };
  final brightness = parts[1] == 'oscuro' ? Brightness.dark : Brightness.light;
  final lang = parts[2];
  final scale = double.parse(parts[3]);
  final locale = Locale(lang, lang == 'en' ? 'GB' : 'ES');

  void setLocale(WidgetTester tester) {
    tester.platformDispatcher.localesTestValue = [locale];
    tester.platformDispatcher.localeTestValue = locale;
  }

  screenTest(
    'primer uso $combo',
    (tester, phone) async {
      setLocale(tester);
      await _mount(tester, phone);
      await _shot(tester, combo, 'p01-bienvenida');
      _go(phone, '/recover');
      await _shot(tester, combo, 'p02-recuperar');
      _go(phone, '/tour');
      await _shot(tester, combo, 'p03-guia');
    },
    size: size,
    brightness: brightness,
    textScale: scale,
  );

  screenTest(
    'guía $combo',
    (tester, phone) async {
      setLocale(tester);
      await seedSample(tester, phone);
      await _mount(tester, phone);
      _go(phone, '/tour?from=settings');
      for (var page = 1; page <= 5; page++) {
        await tester.pump(const Duration(milliseconds: 2500));
        await _shot(tester, combo, 'g0$page-guia', settleFirst: false);
        final next = find.byIcon(Icons.arrow_forward);
        if (next.evaluate().isEmpty) {
          await tester.dragFrom(
            Offset(size.width * 0.8, size.height * 0.5),
            Offset(-size.width * 0.6, 0),
          );
        } else {
          await tester.tap(next.first);
        }
        await tester.pump(const Duration(milliseconds: 800));
      }
    },
    size: size,
    brightness: brightness,
    textScale: scale,
  );

  screenTest(
    'compartir con recuperación $combo',
    (tester, phone) async {
      setLocale(tester);
      await seedSample(tester, phone);
      await _mount(tester, phone);
      _go(phone, '/settings/share');
      await _shot(tester, combo, 'a11b-compartir-recuperacion');
    },
    size: size,
    brightness: brightness,
    textScale: scale,
    overrides: [
      recoveryApplicationProvider.overrideWith(
        () => FakeRecovery(
          initial: const RecoveryStatus(RecoveryReadiness.prepared),
        ),
      ),
    ],
  );

  screenTest(
    'pantallas $combo',
    (tester, phone) async {
      setLocale(tester);
      await seedSample(tester, phone);
      await _mount(tester, phone);
      await _shot(tester, combo, 'a01-personas');
      for (final (name, path) in const [
        ('a02-lista-aritz', '/people/aritz'),
        ('a03-lista-nora', '/people/nora'),
        ('a04-familia', '/family'),
        ('a05-ocasiones', '/occasions'),
        ('a06-reyes', '/occasions/seed-kings'),
        ('a07-cumple-nora', '/occasions/birthday-nora'),
        ('a08-presupuesto', '/occasions/budget'),
        ('a09-ajustes', '/settings'),
        ('a10-seguridad', '/settings/security'),
        ('a11-compartir', '/settings/share'),
        ('a12-copia', '/settings/backup'),
        ('a13-personas', '/settings/people'),
        ('a14-quien-regala', '/settings/givers'),
        ('a15-apariencia', '/settings/appearance'),
      ]) {
        _go(phone, path);
        await _shot(tester, combo, name);
      }
      for (final (name, path) in const [
        ('a18-persona-nueva', '/people'),
        ('a19-ocasion-nueva', '/occasions'),
      ]) {
        _go(phone, path);
        await settle(tester);
        final add = find.byIcon(Icons.add);
        if (add.evaluate().isNotEmpty) {
          await tester.tap(add.first);
          await _shot(tester, combo, name);
          await tester.binding.handlePopRoute();
          await settle(tester);
        }
      }
      _go(phone, '/people/aritz');
      await settle(tester);
      if (find.byType(FloatingActionButton).evaluate().isNotEmpty) {
        await tester.tap(find.byType(FloatingActionButton));
        await _shot(tester, combo, 'a16-regalo-nuevo');
        expect(find.byType(GiftEditorScreen), findsWidgets);
      }
    },
    size: size,
    brightness: brightness,
    textScale: scale,
  );
}

void main() {
  if (_dir.isEmpty) {
    test(
      'capturas',
      () {},
      skip: 'Solo con --dart-define=CAPTURE_PULIDO=<carpeta>',
    );
    return;
  }
  setUpAll(() async {
    await _loadFonts();
    await loadInter();
  });
  final combos = _combosArg.isEmpty ? _defaultCombos : _combosArg.split(',');
  for (final combo in combos) {
    group(combo, () => _combo(combo));
  }
}
