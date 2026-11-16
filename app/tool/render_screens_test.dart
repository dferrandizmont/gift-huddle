// Captures de las pantallas reales de la app (sin emulador) para compararlas
// con la maqueta de diseño.
// Ejecutar: flutter test tool/render_screens_test.dart
// Variables: SCREENS_H (alto lógico, 844 por defecto), SCREENS_PREFIX (por defecto «», p. ej. «antes-»), SCREENS_DARK=1 (modo oscuro; escribe en la carpeta de capturas del tema oscuro) y SCREENS_ONLY
// (nombres separados por comas). Está fuera de test/ para que la suite normal
// no escriba estas capturas; salen en `build/screens/` (ignorado por git).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clock/clock.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:regalos/core/widgets/header_button.dart';
import 'package:regalos/core/widgets/picker_field.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/features/family/presentation/family_screen.dart';
import 'package:regalos/features/family/presentation/reparto_outside.dart';
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';

import '../test/helpers/memory_stores.dart';
import '../test/helpers/pump_app.dart';
import '../test/helpers/screens.dart';

const _outDir = 'build/screens/rediseno-v3/app';
const _repartoDir = 'build/screens/reparto/app';
const _darkDir = 'build/screens/oscuro/app';

/// Las hojas de Ajustes y Compartir, junto a su maqueta.
const _settingsDir = 'build/screens/ajustes/app';

/// Con `SCREENS_DARK=1` el teléfono simulado va en modo oscuro.
bool get _dark => Platform.environment['SCREENS_DARK'] == '1';

/// Roboto de la caché del SDK de Flutter, para que no salgan cajas.
Future<void> _loadFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  // Los botones de texto del tema no heredan la familia y en las pruebas caen
  // a Ahem (cajas): se les da Roboto también con ese nombre.
  for (final family in const ['Roboto']) {
    final loader = FontLoader(family);
    for (final f in const [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
      'roboto-light.ttf',
      'roboto-black.ttf',
      'roboto-italic.ttf',
    ]) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  // Inter, la fuente de la app (si no, el texto sale como cajas).
  final inter = FontLoader('Inter');
  for (final f in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/inter/Inter-$f.ttf').readAsBytesSync();
    inter.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await inter.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('$dir/materialicons-regular.otf').readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

Future<void> _shot(
  WidgetTester tester,
  String name, {
  String dir = _outDir,
  bool settleFirst = true,
}) async {
  final prefix = Platform.environment['SCREENS_PREFIX'] ?? '';
  final only = Platform.environment['SCREENS_ONLY'];
  if (only != null && !only.split(',').contains(name)) return;
  if (settleFirst) {
    await settle(tester);
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  final boundary = tester.renderObject(
    find.byType(RepaintBoundary).first,
  ) as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File('${_dark ? _darkDir : dir}/$prefix$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

/// Monta la app entera con un RepaintBoundary fuera (la pantalla de bloqueo
/// no trae ninguno) para poder capturarla.
Future<void> _pump(WidgetTester tester, FakePhone phone) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: const RepaintBoundary(child: RegalosApp()),
    ),
  );
  await settle(tester);
}

void _phone(WidgetTester tester) {
  // Sin el aro de foco de teclado (un móvil táctil no lo pinta).
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
  tester.view
    ..physicalSize = Size(
      780,
      2 * double.parse(Platform.environment['SCREENS_H'] ?? '844'),
    )
    ..devicePixelRatio = 2;
}

/// Como `screenTest`, pero sin semántica y con las sombras encendidas.
void renderTest(
  String description,
  Future<void> Function(WidgetTester tester, FakePhone phone) body,
) {
  testWidgets(description, (tester) async {
    // Con las sombras apagadas (lo normal en pruebas) salen como un aro negro.
    debugDisableShadows = false;
    tester.view
      ..physicalSize = Size(
        780,
        2 * double.parse(Platform.environment['SCREENS_H'] ?? '844'),
      )
      ..devicePixelRatio = 2;
    tester.platformDispatcher.localesTestValue = const [Locale('es', 'ES')];
    tester.platformDispatcher.localeTestValue = const Locale('es', 'ES');
    if (_dark) {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    }
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    for (final name in const [
      'com.llfbandit.app_links/events',
      'com.llfbandit.app_links/messages',
    ]) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        (call) async => null,
      );
    }
    final phone = FakePhone(prefs: await mockPrefs());
    addTearDown(phone.dispose);
    try {
      await withClock(Clock.fixed(kToday), () => body(tester, phone));
    } finally {
      debugDisableShadows = true;
    }
  });
}

void main() {
  setUpAll(_loadFonts);

  renderTest('personas', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await _shot(tester, 'personas');
  });

  renderTest('regalos-persona', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await tapText(tester, 'Aritz');
    await _shot(tester, 'regalos-persona');
  });

  renderTest('ocasiones', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await tester.tap(find.text('Ocasiones').last);
    await settle(tester);
    await _shot(tester, 'ocasiones');
  });

  renderTest('ocasion-detalle', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await tester.tap(find.text('Ocasiones').last);
    await settle(tester);
    await tapText(tester, 'Papá Noel');
    await _shot(tester, 'ocasion-detalle');
  });

  // Reparto: la rejilla con 3 y con 6 personas que reciben, y la hoja que
  // crece desde una celda (a mitad del vuelo y asentada).
  Future<void> openReparto(WidgetTester tester) async {
    await tester.tap(find.text('Reparto').last);
    await settle(tester);
    if (find.text('Todas').evaluate().isNotEmpty) {
      await tester.tap(find.text('Todas'));
      await settle(tester);
    }
  }

  renderTest('reparto', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await openReparto(tester);
    await _shot(tester, 'reparto-3', dir: _repartoDir);
  });

  renderTest('reparto-6', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone, extraPeople: 3);
    await _pump(tester, phone);
    await openReparto(tester);
    await _shot(tester, 'reparto-6', dir: _repartoDir);
  });

  renderTest('reparto-hoja', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await openReparto(tester);
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Nosotros para Aritz: 2 regalos')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    await _shot(
      tester,
      'reparto-hoja-vuelo',
      dir: _repartoDir,
      settleFirst: false,
    );
    await settle(tester);
    await _shot(tester, 'reparto-hoja', dir: _repartoDir);
    // Con la fila de chips de quién regala desplegada.
    await tester.tap(
      find.bySemanticsLabel(RegExp('^Quién regala: Nosotros')).first,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    await _shot(
      tester,
      'reparto-hoja-chips-vuelo',
      dir: _repartoDir,
      settleFirst: false,
    );
    await settle(tester);
    await _shot(tester, 'reparto-hoja-chips', dir: _repartoDir);
  });

  // Reparto por ocasión (vista C) y el cambio entre las dos vistas: a mitad
  // del vuelo de los regalos y asentado; también la barra inferior con su
  // recuadro a mitad de deslizamiento.
  renderTest('reparto-ocasion', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await openReparto(tester);
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));
    await _shot(
      tester,
      'reparto-c-vuelo',
      dir: _repartoDir,
      settleFirst: false,
    );
    await settle(tester);
    await _shot(tester, 'reparto-c', dir: _repartoDir);
    // Con la fila de chips de quién regala desplegada.
    await tester.tap(find.bySemanticsLabel(RegExp('^Quién regala: ')).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    await _shot(
      tester,
      'reparto-c-chips-vuelo',
      dir: _repartoDir,
      settleFirst: false,
    );
    await settle(tester);
    await _shot(tester, 'reparto-c-chips', dir: _repartoDir);
    // Y de vuelta a la rejilla.
    await tester.tap(find.bySemanticsLabel('Rejilla'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));
    await _shot(
      tester,
      'reparto-b-vuelta-vuelo',
      dir: _repartoDir,
      settleFirst: false,
    );
    await settle(tester);
    await _shot(tester, 'reparto-b-vuelta', dir: _repartoDir);
  });

  // Los nombres y avatares de quienes reciben viajan con los regalos: a
  // mitad del vuelo de la rejilla a la lista y de la lista a la rejilla.
  renderTest('reparto-nombres', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await openReparto(tester);
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    await _shot(
      tester,
      'reparto-nombres-vuelo',
      dir: _repartoDir,
      settleFirst: false,
    );
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Rejilla'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    await _shot(
      tester,
      'reparto-nombres-vuelta',
      dir: _repartoDir,
      settleFirst: false,
    );
  });

  // La lista por ocasión acaba con «Fuera del reparto · N» (con Leo), plegado
  // y desplegado.
  renderTest('reparto-c-fuera', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await tester.runAsync(() async {
      await familyOf(phone).setRecipientInReparto('leo', false);
    });
    await _pump(tester, phone);
    await openReparto(tester);
    await tester.tap(find.bySemanticsLabel('Por ocasión'));
    await settle(tester);
    final toggle = find.byKey(kRepartoOutsideToggleKey);
    await tester.ensureVisible(toggle);
    await settle(tester);
    await _shot(tester, 'reparto-c-fuera-plegado', dir: _repartoDir);
    await tester.tap(toggle);
    await settle(tester);
    await tester.ensureVisible(find.byKey(repartoIncludeKey('leo')));
    await settle(tester);
    await _shot(tester, 'reparto-c-fuera', dir: _repartoDir);
  });

  // Excluir del reparto: la rejilla de Reyes con la franja gris de Aritz, la
  // ficha de la persona y el bloque «Fuera del reparto» desplegado (con Leo).
  renderTest('reparto-excluir', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await tester.runAsync(() async {
      await familyOf(phone)
          .setRecipientSkipOccasion('aritz', 'seed-kings', skip: true);
      await familyOf(phone).setRecipientInReparto('leo', false);
    });
    await _pump(tester, phone);
    await openReparto(tester);
    // «Todas»: Aritz sigue y bajo su nombre pone «Sin Reyes».
    await _shot(tester, 'reparto-sin-reyes', dir: _repartoDir);
    final reyes = find.descendant(
      of: find.byKey(kOccasionChipsKey),
      matching: find.text('Reyes'),
    );
    await tester.ensureVisible(reyes);
    await tester.tap(reyes);
    await settle(tester);
    await tester.tap(find.byKey(kRepartoOutsideToggleKey));
    await settle(tester);
    await _shot(tester, 'reparto-fuera', dir: _repartoDir);
    // La ficha de Aritz, subiendo desde su nombre (a mitad y asentada).
    await tester.tap(find.bySemanticsLabel('Abrir la ficha de Aritz').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    await _shot(
      tester,
      'reparto-ficha-vuelo',
      dir: _repartoDir,
      settleFirst: false,
    );
    await settle(tester);
    await _shot(tester, 'reparto-ficha', dir: _repartoDir);
  });

  renderTest('barra', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await tester.tap(find.text('Reparto').last);
    await settle(tester);
    await tester.tap(find.text('Ocasiones').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    await _shot(
      tester,
      'barra-deslizando',
      dir: _repartoDir,
      settleFirst: false,
    );
    await settle(tester);
    await _shot(tester, 'barra', dir: _repartoDir);
  });

  renderTest('editor-regalo', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await tapText(tester, 'Aritz');
    await tapText(tester, 'Pijama de astronautas, talla 8');
    await _shot(tester, 'editor-regalo');
  });

  renderTest('selector-ocasion', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await tapText(tester, 'Aritz');
    await tapText(tester, 'Pijama de astronautas, talla 8');
    await tester.tap(find.byType(PickerField<String>).at(2));
    await settle(tester);
    await _shot(tester, 'selector-ocasion');
  });

  renderTest('editor-regalo-borrar', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await tapText(tester, 'Aritz');
    await tapText(tester, 'Pijama de astronautas, talla 8');
    // El final del formulario: «Borrar regalo» sobre «Guardar».
    await tester.scrollUntilVisible(
      find.text('Borrar regalo'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(GiftEditorScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await _shot(tester, 'editor-regalo-borrar');
  });

  renderTest('ocasion-nueva', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await tester.tap(find.text('Ocasiones').last);
    await settle(tester);
    await tester.tap(find.byType(HeaderIconButton).first);
    await settle(tester);
    // La rejilla de tipos, con uno elegido («Reyes» también está en la
    // pantalla de debajo: el de la hoja es el último).
    await tester.tap(find.text('Reyes').last);
    await settle(tester);
    await _shot(tester, 'ocasion-nueva');
  });

  renderTest('ajustes-personas', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await tester.tap(find.text('Ajustes').last);
    await settle(tester);
    await tapText(tester, 'Personas');
    await _shot(tester, 'ajustes-personas');
  });

  renderTest('ajustes', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    await _pump(tester, phone);
    await tester.tap(find.text('Ajustes').last);
    await settle(tester);
    await _shot(tester, 'ajustes');
    // La hoja de idioma, con el visto en «Sistema».
    await tester.tap(find.text('Idioma'));
    await settle(tester);
    await _shot(tester, 'ajustes-idioma', dir: _settingsDir);
    // La hoja «¿De quién es este móvil?», con el visto en Nora.
    await tester.tapAt(const Offset(195, 60));
    await settle(tester);
    await tester.runAsync(() => familyOf(phone).setSelfRecipient('nora'));
    await settle(tester);
    await tester.tap(find.text('Este móvil es de'));
    await settle(tester);
    await _shot(tester, 'ajustes-de-quien', dir: _settingsDir);
  });

  renderTest('compartir', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    // Con un segundo móvil conectado, para que salga la lista.
    await tester.runAsync(
      () => familyOf(phone).markPaired(peerName: 'Móvil de Nora'),
    );
    await _pump(tester, phone);
    await tester.tap(find.text('Ajustes').last);
    await settle(tester);
    await tapText(tester, 'Móviles de la familia');
    await _shot(tester, 'compartir');
    // La hoja «Conectar otro móvil».
    await tapText(tester, 'Conectar otro móvil');
    await _shot(tester, 'compartir-conectar', dir: _settingsDir);
  });

  renderTest('bloqueo', (tester, phone) async {
    _phone(tester);
    await seedSample(tester, phone);
    // Un PIN de 6 cifras con huella, y la app bloqueada.
    await tester.runAsync(() async {
      final lock = phone.container.read(lockControllerProvider.notifier);
      await lock.setPin('123456');
      await lock.setBiometrics(true, reason: 'x');
      phone.biometrics.succeeds = false;
      await lock.lockNow();
    });
    await _pump(tester, phone);
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    await _shot(tester, 'bloqueo');
  });
}
