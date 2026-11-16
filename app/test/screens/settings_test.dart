import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app_info.dart';
import 'package:regalos/core/motion/haptics.dart';
import 'package:regalos/core/motion/shake.dart';
import 'package:regalos/core/motion/success_mark.dart';
import 'package:regalos/core/widgets/sheet_parts.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';

import '../helpers/fake_haptics.dart';
import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../widgets/motion_shared_test.dart' show moving;

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Ajustes').last);
  await settle(tester);
}

Future<void> typePin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump();
  }
}

Future<AppLockState> lockState(WidgetTester tester, FakePhone phone) async =>
    (await tester.runAsync(
      () => phone.container.read(lockControllerProvider.future),
    ))!;

void main() {
  const tall = Size(390, 1500);

  test('la versión de Acerca de coincide con pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(kAppVersion, match!.group(1));
  });

  screenTest('el idioma se elige en una hoja con un visto, no en un '
      'desplegable', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    // La fila enseña el valor de ahora y no tiene nada desplegado.
    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('Sistema'), findsOneWidget);
    expect(find.text('Español'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.text('Idioma'));
    await settle(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    // Los nombres van en su propia lengua; «Sistema» dice cuál es ahora.
    for (final name in ['Español', 'Català', 'English', 'Ahora: Español']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Sistema'), findsNWidgets(2));
    // Un solo visto, en la opción elegida.
    expect(find.byType(DrawnCheck), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Sistema. Ahora: Español')),
      isSemantics(
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('English')),
      isSemantics(hasCheckedState: true, isChecked: false),
    );

    // Al tocar otra, su visto se dibuja y la hoja baja sola.
    await tester.tap(find.text('English'));
    await tester.pump();
    expect(find.byType(DrawnCheck), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(CheckOptionRow, 'English'),
        matching: find.byType(DrawnCheck),
      ),
      findsOneWidget,
    );
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
    expect(phone.prefs!.getString('locale'), 'en');

    // Y se vuelve al idioma del sistema (español en la prueba).
    await tester.tap(find.text('Language'));
    await settle(tester);
    await tester.tap(find.text('System'));
    await settle(tester);
    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('Sistema'), findsOneWidget);
    expect(phone.prefs!.getString('locale'), isNull);
  });

  screenTest('cerrar la hoja de idioma sin elegir no cambia nada', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    await tester.tap(find.text('Idioma'));
    await settle(tester);
    await tester.tapAt(const Offset(195, 60));
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Idioma'), findsOneWidget);
    expect(phone.prefs!.getString('locale'), isNull);
  });

  screenTest('con «Reducir movimiento» la hoja de idioma también elige y '
      'se cierra', (tester, phone) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    await tester.tap(find.text('Idioma'));
    await settle(tester);
    await tester.tap(find.text('Català'));
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Idioma'), findsOneWidget);
    expect(find.text('Català'), findsOneWidget);
    expect(find.text('Ajustos'), findsWidgets);
  });

  screenTest('Ajustes tiene cuatro grupos en orden de uso, con el valor de '
      'cada fila', (tester, phone) async {
    await seedSample(tester, phone, pin: true);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    // Los grupos, de arriba abajo.
    final groups = ['Familia', 'Este móvil', 'Compartir y copia', 'Acerca de'];
    final tops = [for (final g in groups) tester.getTopLeft(find.text(g)).dy];
    expect(tops, [...tops]..sort());
    // Lo de antes ya no está.
    for (final gone in [
      'Tu lista',
      'Privacidad y compartir',
      'La app',
      'Seguridad',
      'Compartir',
      'Cambiar, renombrar y archivar',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }

    /// La fila con ese título, por su etiqueta accesible: «título. valor».
    void row(String label) =>
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    final occasions = (await familyState(tester, phone)).view.occasions.length;
    row('Personas. 3');
    row('Quién regala. 6');
    row('Ocasiones. $occasions');
    row('Archivo. 0');
    row('Este móvil es de. Nadie');
    row('Bloqueo. PIN');
    row('Idioma. Sistema');
    row('Apariencia. Lavanda · Sistema');
    row('Móviles de la familia. Solo este');
    row('Copia de seguridad');
    row('Acerca de Gift Huddle. $kAppVersion');

    // Cada fila va en su grupo.
    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y('Archivo'), inExclusiveRange(tops[0], tops[1]));
    expect(y('Este móvil es de'), inExclusiveRange(tops[1], y('Bloqueo')));
    expect(y('Bloqueo'), inExclusiveRange(tops[1], tops[2]));
    expect(y('Idioma'), inExclusiveRange(tops[1], tops[2]));
    expect(y('Apariencia'), inExclusiveRange(tops[1], tops[2]));
    expect(y('Móviles de la familia'), inExclusiveRange(tops[2], tops[3]));
    expect(y('Copia de seguridad'), inExclusiveRange(tops[2], tops[3]));
    expect(find.textContaining('Ko-fi'), findsNothing);

    // Lo del ADR 0004 que aún no funciona no se enseña, ni como «Pronto».
    expect(find.textContaining('Pronto'), findsNothing);

    await tapText(tester, 'Acerca de Gift Huddle');
    expect(find.text('Gift Huddle'), findsOneWidget);
    expect(find.textContaining('solo salen del móvil'), findsOneWidget);
  }, size: tall);

  final shakeHaptics = FakeHaptics();
  screenTest('Pedir el PIN actual: uno erróneo tiembla de verdad y vibra con '
      'error', (tester, phone) async {
    await seedSample(tester, phone, pin: true);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    await tapText(tester, 'Bloqueo');
    await tester.tap(find.bySemanticsLabel('Bloqueo con PIN'));
    await settle(tester);
    await typePin(tester, '0000');
    await tester.tap(find.text('Continuar'));
    // La comprobación del PIN es real: se le da tiempo y luego se mide el
    // temblor fotograma a fotograma.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(ShakeX), findsOneWidget);
    expect(moving(tester, find.byType(ShakeX)), isNotEmpty);
    expect(shakeHaptics.levels, contains(HapticLevel.error));
    await settle(tester);
  }, overrides: [shakeHaptics.provide]);

  screenTest('Bloqueo: quitar el PIN, ponerlo, cambiarlo y la biometría', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone, pin: true);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    await tapText(tester, 'Bloqueo');
    expect(find.text('Bloqueo con PIN'), findsOneWidget);

    // Quitar el PIN pide el PIN: uno malo avisa de los intentos.
    await tester.tap(find.bySemanticsLabel('Bloqueo con PIN'));
    await settle(tester);
    expect(find.text('Quitar el PIN'), findsOneWidget);
    await typePin(tester, '0000');
    await tapText(tester, 'Continuar');
    expect(
      find.textContaining('PIN incorrecto. Quedan 4 intentos'),
      findsOneWidget,
    );
    await typePin(tester, '1234');
    await tapText(tester, 'Continuar');
    expect(find.text('Bloqueo desactivado.'), findsOneWidget);
    var lock = await lockState(tester, phone);
    expect(lock.enabled, isFalse);
    expect(lock.pinSet, isFalse);

    // Volver a ponerlo: se escribe y se repite.
    await tester.tap(find.bySemanticsLabel('Bloqueo con PIN'));
    await settle(tester);
    expect(find.text('Crea un PIN'), findsOneWidget);
    await typePin(tester, '4321');
    await tapText(tester, 'Continuar');
    expect(find.text('Repite el PIN'), findsOneWidget);
    await typePin(tester, '4321');
    await tapText(tester, 'Guardar PIN');
    // Con huella en el móvil se ofrece activarla; se deja para luego.
    expect(find.text('¿Activar huella o rostro?'), findsOneWidget);
    await tapText(tester, 'Ahora no');
    expect(find.text('PIN activado.'), findsOneWidget);
    lock = await lockState(tester, phone);
    expect(lock.enabled && lock.pinSet, isTrue);

    // Cambiarlo: primero el actual, luego el nuevo.
    await tapText(tester, 'Cambiar PIN');
    expect(find.text('Escribe tu PIN actual.'), findsOneWidget);
    await typePin(tester, '4321');
    await tapText(tester, 'Continuar');
    expect(find.text('Crea un PIN'), findsOneWidget);
    await typePin(tester, '1111');
    await tapText(tester, 'Continuar');
    await typePin(tester, '1111');
    await tapText(tester, 'Guardar PIN');
    await tapText(tester, 'Ahora no');
    expect(find.text('PIN cambiado.'), findsOneWidget);
    // El PIN nuevo es el que abre la app.
    await tester.runAsync(
      () => phone.container.read(lockControllerProvider.notifier).lockNow(),
    );
    await settle(tester);
    expect(find.text('Introduce tu PIN'), findsOneWidget);
    // El PIN guardado conoce su longitud: se comprueba al completarlo y no
    // hay botón «Desbloquear».
    expect(find.text('Desbloquear'), findsNothing);
    await typePin(tester, '1111');
    await settle(tester);
    expect(find.text('Introduce tu PIN'), findsNothing);

    // Huella o rostro.
    await tester.tap(find.bySemanticsLabel('Huella o rostro'));
    await settle(tester);
    lock = await lockState(tester, phone);
    expect(lock.biometrics, isTrue);
    expect(phone.biometrics.prompts, 1);
    await tester.tap(find.bySemanticsLabel('Huella o rostro'));
    await settle(tester);
    lock = await lockState(tester, phone);
    expect(lock.biometrics, isFalse);
  }, size: tall);

  screenTest('Bloqueo: sin PIN no se puede cambiar ni usar la biometría', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    await tapText(tester, 'Bloqueo');
    await tester.tap(find.bySemanticsLabel('Huella o rostro'));
    await settle(tester);
    expect((await lockState(tester, phone)).biometrics, isFalse);
    await tester.tap(find.text('Cambiar PIN'));
    await settle(tester);
    expect(find.text('Escribe tu PIN actual.'), findsNothing);
  }, size: tall);

  screenTest('Bloqueo avisa si el móvil no tiene biometría', (
    tester,
    phone,
  ) async {
    phone.biometrics.available = false;
    await seedSample(tester, phone, pin: true);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    await tapText(tester, 'Bloqueo');
    expect(
      find.text('Este móvil no tiene huella ni rostro configurados.'),
      findsOneWidget,
    );
  }, size: tall);

  screenTest('gestionar personas: renombrar, añadir y archivar', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    await tapText(tester, 'Personas');
    expect(find.text('Aritz'), findsOneWidget);
    expect(find.text('Archivar'), findsNWidgets(3));

    // Renombrar.
    await tapText(tester, 'Leo');
    expect(find.text('Editar persona'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre'),
      'Leo Martí',
    );
    await tapText(tester, 'Guardar');
    expect(find.text('Leo Martí'), findsOneWidget);

    // Añadir con cumpleaños: crea su ocasión.
    await tapText(tester, 'Añadir persona');
    await tester.enterText(find.widgetWithText(TextField, 'Nombre'), 'Mara');
    await tapText(tester, 'Elegir fecha');
    await tapText(tester, 'ACEPTAR');
    await tapText(tester, 'Guardar');
    expect(find.text('Mara'), findsOneWidget);
    var state = await familyState(tester, phone);
    final mara = state.view.recipients.firstWhere((r) => r.name == 'Mara');
    expect(state.view.occasions.any((o) => o.recipientId == mara.id), isTrue);

    // Archivar: sale de esta pantalla y de las listas, con sus regalos.
    await tester.tap(find.bySemanticsLabel('Archivar Nora'));
    await settle(tester);
    expect(find.text('Nora'), findsNothing);
    expect(find.text('En el archivo'), findsNothing);
    expect(find.text('Recuperar'), findsNothing);
    expect(find.textContaining('Ajustes › Archivo'), findsOneWidget);
    state = await familyState(tester, phone);
    expect(state.view.recipients.map((r) => r.name), isNot(contains('Nora')));
    expect(
      state.fullView.gifts.where((g) => g.recipientId == 'nora'),
      isNotEmpty,
    );
  }, size: tall);

  screenTest('Archivo junta lo archivado de las tres listas y lo recupera', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await tester.runAsync(() async {
      final c = familyOf(phone);
      await c.archiveRecipient('nora', archived: true);
      await c.archiveGiver('pere', archived: true);
      await c.archiveOccasion('seed-santa', archived: true);
    });
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    expect(find.bySemanticsLabel('Archivo. 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Personas. 2'), findsOneWidget);

    await tapText(tester, 'Archivo');
    expect(
      find.text('Fuera de las listas, con sus regalos guardados.'),
      findsOneWidget,
    );
    // Un grupo por lista, con lo suyo.
    for (final text in [
      'Personas',
      'Quién regala',
      'Ocasiones',
      'Nora',
      'Tío Pere',
      'Navidad',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.text('Recuperar'), findsNWidgets(3));
    expect(find.text('Eliminar'), findsNWidgets(3));
    expect(find.text('Archivar'), findsNothing);

    // Recuperar: la fila se pliega y vuelve a su lista.
    await tester.tap(find.bySemanticsLabel('Recuperar Nora'));
    await settle(tester);
    expect(find.text('Nora'), findsNothing);
    expect(find.text('Recuperar'), findsNWidgets(2));
    final state = await familyState(tester, phone);
    expect(state.view.recipients.map((r) => r.name), contains('Nora'));

    await tapLabel(tester, 'Volver a Ajustes');
    expect(find.bySemanticsLabel('Archivo. 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Personas. 3'), findsOneWidget);
  }, size: tall);

  screenTest('Archivo vacío lo dice', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    await tapText(tester, 'Archivo');
    expect(find.text('No hay nada archivado.'), findsOneWidget);
    expect(find.text('Recuperar'), findsNothing);
  }, size: tall);

  screenTest('eliminar una persona: confirma con la consecuencia y se pliega', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    await tapText(tester, 'Personas');
    expect(find.text('Eliminar'), findsNWidgets(3));

    // Cancelar no toca nada.
    await tester.tap(find.bySemanticsLabel('Eliminar Nora'));
    await settle(tester);
    expect(find.text('¿Eliminar a Nora?'), findsOneWidget);
    expect(
      find.textContaining('Se eliminarán también sus 4 regalos.'),
      findsOneWidget,
    );
    expect(find.textContaining('No se puede deshacer.'), findsOneWidget);
    await tapText(tester, 'Cancelar');
    expect(find.text('¿Eliminar a Nora?'), findsNothing);
    var state = await familyState(tester, phone);
    expect(state.fullView.recipients.map((r) => r.id), contains('nora'));

    // Confirmar: la persona, sus regalos y su cumpleaños desaparecen.
    await tester.tap(find.bySemanticsLabel('Eliminar Nora'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await settle(tester);
    expect(find.text('Nora'), findsNothing);
    state = await familyState(tester, phone);
    expect(state.fullView.recipients.map((r) => r.id), isNot(contains('nora')));
    expect(
      state.fullView.allGifts.where((g) => g.recipientId == 'nora'),
      isEmpty,
    );
    expect(state.doc.canonicalJson(), isNot(contains('Cocinita')));
  }, size: tall);

  screenTest('eliminar quien regala y una ocasión: sus regalos se quedan', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    await tapText(tester, 'Quién regala');
    await tester.tap(find.bySemanticsLabel('Eliminar Tío Pere'));
    await settle(tester);
    expect(find.text('¿Eliminar a Tío Pere?'), findsOneWidget);
    expect(
      find.textContaining('Su regalo se quedará sin quién regala.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await settle(tester);
    var state = await familyState(tester, phone);
    expect(state.fullView.givers.map((g) => g.id), isNot(contains('pere')));
    final libro = state.fullView.allGifts.firstWhere((g) => g.id == 'g10');
    expect(libro.giverId, isNull);

    await tapLabel(tester, 'Volver a Ajustes');
    await tapText(tester, 'Ocasiones');
    await tester.tap(find.bySemanticsLabel('Eliminar Reyes').first);
    await settle(tester);
    expect(find.textContaining('se quedarán sin ocasión.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await settle(tester);
    state = await familyState(tester, phone);
    expect(
      state.fullView.occasions.map((o) => o.id),
      isNot(contains('seed-kings')),
    );
    expect(
      state.fullView.allGifts.where((g) => g.occasionId == 'seed-kings'),
      isEmpty,
    );
    expect(state.fullView.allGifts.any((g) => g.id == 'g10'), isTrue);
  }, size: tall);

  screenTest('gestionar quién regala y ocasiones: editar y archivar', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openSettings(tester);
    await tapText(tester, 'Quién regala');
    expect(find.text('Paga la casa'), findsOneWidget);
    await tapText(tester, 'Tío Pere');
    expect(find.text('Editar quién regala'), findsOneWidget);
    // «Paga la casa» se enciende desde la hoja.
    await tester.tap(find.bySemanticsLabel('Paga la casa').last);
    await tester.pump();
    await tapText(tester, 'Guardar');
    var state = await familyState(tester, phone);
    expect(
      state.view.givers.firstWhere((g) => g.id == 'pere').householdPays,
      isTrue,
    );
    await tester.tap(find.bySemanticsLabel('Archivar Tío Pere'));
    await settle(tester);
    state = await familyState(tester, phone);
    expect(state.view.givers.map((g) => g.id), isNot(contains('pere')));

    await tapLabel(tester, 'Volver a Ajustes');
    await tapText(tester, 'Ocasiones');
    await tapText(tester, 'Navidad');
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre'),
      'Navidad en casa',
    );
    await tapText(tester, 'Guardar');
    expect(find.text('Navidad en casa'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Archivar Navidad en casa'));
    await settle(tester);
    state = await familyState(tester, phone);
    expect(
      state.view.occasions.firstWhere((o) => o.id == 'seed-santa').archived,
      isTrue,
    );
  }, size: tall);
}
