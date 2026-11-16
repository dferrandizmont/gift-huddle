import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/platform/document_exchange.dart'
    show tempDirectoryProvider;
import 'package:regalos/core/theme/regalos_tokens.dart';
import 'package:regalos/core/widgets/confirm_dialog.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/settings/presentation/erase_all_dialog.dart';
import 'package:regalos/features/settings/presentation/pin_verify_screen.dart';
import 'package:regalos/features/sync/data/sync_config.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/memory_stores.dart' show FakePhone;
import '../helpers/screens.dart';
import '../sync/sync_harness.dart' show kFastTiming, kTestHost;
import 'family_grid_test.dart' show expectNoRoundShapes;

/// «Borrar todo» en Ajustes: la fila roja del final, la doble confirmación,
/// el borrado del servidor y del móvil, y qué pasa sin red.
void main() {
  const tall = Size(390, 1500);
  const welcome = 'Te damos la bienvenida a Gift Huddle';
  const hint = 'La lista, el PIN y los ajustes de este móvil.';
  const serverNote =
      'Antes, este móvil sale de la sincronización de la familia; si es el '
      'último, también se borra la copia cifrada del servidor.';
  const failedTitle = 'No se ha podido contactar con el servidor';

  late Directory temp;
  setUpAll(() => temp = Directory.systemTemp.createTempSync('regalos_erase_'));
  tearDownAll(() => temp.deleteSync(recursive: true));

  /// Sin tocar la carpeta temporal de verdad.
  final Override tempOverride = tempDirectoryProvider.overrideWithValue(
    () async => temp,
  );

  /// Un móvil con servidor de sincronización (el falso).
  List<Override> withServer(FakeSyncTransport transport) => [
    tempOverride,
    syncHostProvider.overrideWithValue(kTestHost),
    // Las invitaciones, en el mismo origen que el servidor de pruebas.
    invitationOriginProvider.overrideWithValue(''),
    syncTransportProvider.overrideWithValue(transport),
    syncTimingProvider.overrideWithValue(kFastTiming),
  ];

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.text('Ajustes').last);
    await settle(tester);
  }

  /// Teclea [pin] en la pantalla que lo pide y pulsa «Continuar».
  Future<void> enterPin(WidgetTester tester, String pin) async {
    expect(find.byType(PinVerifyScreen), findsOneWidget);
    for (final digit in pin.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tapText(tester, 'Continuar');
  }

  /// Ajustes › Borrar todo › Continuar: deja abierto el último paso. Con
  /// [pin], el móvil tiene ese PIN y hay que escribirlo por el camino.
  Future<void> toLastStep(WidgetTester tester, {String? pin}) async {
    await openSettings(tester);
    await tapText(tester, 'Borrar todo');
    expect(find.text('¿Borrar todo?'), findsOneWidget);
    await tapText(tester, 'Continuar');
    if (pin != null) {
      await enterPin(tester, pin);
    }
    expect(find.byType(PinVerifyScreen), findsNothing);
    expect(find.byType(EraseAllDialog), findsOneWidget);
  }

  Future<void> typeWord(WidgetTester tester, String word) async {
    await tester.enterText(find.byKey(kEraseAllFieldKey), word);
    await tester.pump();
  }

  bool confirmEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(kEraseAllConfirmKey)).onPressed !=
      null;

  Future<void> confirm(WidgetTester tester) async {
    await typeWord(tester, 'BORRAR');
    await tester.tap(find.byKey(kEraseAllConfirmKey));
    await settle(tester);
  }

  /// La app ha vuelto al primer uso y en este móvil no queda nada.
  Future<void> expectFirstUse(WidgetTester tester, FakePhone phone) async {
    expect(find.text(welcome), findsOneWidget);
    expect(find.byType(EraseAllDialog), findsNothing);
    expect(find.text('Borrar todo'), findsNothing);
    expect((await familyState(tester, phone)).hasFamily, isFalse);
    expect(phone.secrets.values, isEmpty);
    expect(phone.files.files, isEmpty);
    final lock = (await tester.runAsync(
      () => phone.container.read(lockControllerProvider.future),
    ))!;
    expect(lock.pinSet, isFalse);
    expect(lock.locked, isFalse);
    expect(tester.takeException(), isNull);
  }

  /// Nada se ha borrado: sigue en Ajustes con su lista.
  Future<void> expectUntouched(WidgetTester tester, FakePhone phone) async {
    expect(find.byType(EraseAllDialog), findsNothing);
    expect(find.text(welcome), findsNothing);
    expect(find.text('Borrar todo'), findsOneWidget);
    final state = await familyState(tester, phone);
    expect(state.hasFamily, isTrue);
    expect(state.view.recipients, hasLength(3));
    expect(phone.files.files, isNotEmpty);
  }

  screenTest(
    '«Borrar todo» es la última fila de Ajustes, apartada y en rojo',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettings(tester);
      final row = find.bySemanticsLabel('Borrar todo. $hint');
      expect(row, findsOneWidget);
      // Debajo de todo lo demás, con aire por encima.
      final title = find.text('Borrar todo');
      final about = tester.getRect(find.text('Acerca de Gift Huddle'));
      expect(tester.getTopLeft(title).dy, greaterThan(about.bottom + 28));
      final t = RegalosTokens.of(tester.element(title));
      expect(tester.widget<Text>(title).style!.color, t.danger);
      expect(find.text(hint), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    size: tall,
    overrides: [tempOverride],
  );

  screenTest(
    'pide dos confirmaciones: un diálogo que avisa de que no se puede '
    'deshacer y escribir BORRAR; cancelar en cualquiera no borra nada (sin '
    'PIN configurado no se pide ninguno)',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettings(tester);

      // Primer paso: qué se borra, que no se deshace y que los demás
      // móviles conservan su copia. Sin servidor no se habla de él.
      await tapText(tester, 'Borrar todo');
      expect(find.byType(ConfirmDialog), findsOneWidget);
      expect(find.text('¿Borrar todo?'), findsOneWidget);
      expect(find.textContaining('No se puede deshacer'), findsOneWidget);
      expect(
        find.textContaining(
          'Los demás móviles de tu familia conservan su copia',
        ),
        findsOneWidget,
      );
      expect(find.textContaining(serverNote), findsNothing);
      await tapText(tester, 'Cancelar');
      await expectUntouched(tester, phone);

      // Segundo paso: el botón rojo no se activa hasta escribir la palabra.
      await tapText(tester, 'Borrar todo');
      await tapText(tester, 'Continuar');
      expect(find.byType(ConfirmDialog), findsNothing);
      expect(find.byType(PinVerifyScreen), findsNothing);
      expect(find.byType(EraseAllDialog), findsOneWidget);
      expect(find.text('Último paso'), findsOneWidget);
      expect(find.textContaining('Escribe BORRAR'), findsOneWidget);
      expect(confirmEnabled(tester), isFalse);
      await tester.tap(find.byKey(kEraseAllConfirmKey), warnIfMissed: false);
      await settle(tester);
      expect(find.byType(EraseAllDialog), findsOneWidget);
      await typeWord(tester, 'BORRA');
      expect(confirmEnabled(tester), isFalse);
      await typeWord(tester, 'borrar todo');
      expect(confirmEnabled(tester), isFalse);
      // Vale sin distinguir mayúsculas ni espacios de más.
      await typeWord(tester, ' borrar ');
      expect(confirmEnabled(tester), isTrue);
      expectNoRoundShapes(tester, find.byType(EraseAllDialog));
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Cancelar');
      await expectUntouched(tester, phone);

      // Tocar fuera también lo deja.
      await tapText(tester, 'Borrar todo');
      await tapText(tester, 'Continuar');
      await typeWord(tester, 'BORRAR');
      await tester.tapAt(const Offset(195, 20));
      await settle(tester);
      await expectUntouched(tester, phone);
    },
    size: tall,
    overrides: [tempOverride],
  );

  screenTest(
    'sin sincronización: al confirmar borra todo lo de este móvil (también '
    'el PIN) y la app vuelve al primer uso',
    (tester, phone) async {
      await seedSample(tester, phone, pin: true);
      await pumpRegalos(tester, phone);
      await toLastStep(tester, pin: '1234');
      await confirm(tester);
      await expectFirstUse(tester, phone);
      expect(phone.secureWipes, 1);
    },
    size: tall,
    overrides: [tempOverride],
  );

  screenTest(
    'con PIN, entre el primer diálogo y el último paso pide el PIN: con uno '
    'incorrecto o saliendo no se borra nada; con el correcto se sigue',
    (tester, phone) async {
      await seedSample(tester, phone, pin: true);
      await pumpRegalos(tester, phone);
      await openSettings(tester);
      await tapText(tester, 'Borrar todo');
      await tapText(tester, 'Continuar');

      // Antes de poder escribir BORRAR, el PIN.
      expect(find.byType(EraseAllDialog), findsNothing);
      expect(find.byType(PinVerifyScreen), findsOneWidget);
      expect(
        find.text('Escribe tu PIN para seguir con el borrado.'),
        findsOneWidget,
      );
      expect(phone.biometrics.prompts, 0);

      // Uno incorrecto: avisa, sigue pidiéndolo y no se llega al último paso.
      await enterPin(tester, '0000');
      expect(find.textContaining('PIN incorrecto'), findsOneWidget);
      expect(find.byType(PinVerifyScreen), findsOneWidget);
      expect(find.byType(EraseAllDialog), findsNothing);
      expect(tester.takeException(), isNull);

      // Salir sin acertar lo deja todo como estaba, también el PIN.
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.byType(PinVerifyScreen), findsNothing);
      await expectUntouched(tester, phone);
      final lock = (await tester.runAsync(
        () => phone.container.read(lockControllerProvider.future),
      ))!;
      expect(lock.pinSet, isTrue);
      expect(phone.secureWipes, 0);

      // Con el correcto se llega al último paso y se borra.
      await tapText(tester, 'Borrar todo');
      await tapText(tester, 'Continuar');
      await enterPin(tester, '1234');
      expect(find.byType(PinVerifyScreen), findsNothing);
      expect(find.byType(EraseAllDialog), findsOneWidget);
      await confirm(tester);
      await expectFirstUse(tester, phone);
    },
    size: tall,
    overrides: [tempOverride],
  );

  screenTest(
    'con huella o rostro activados basta con pasarlos; si fallan o se '
    'cancelan, queda el PIN',
    (tester, phone) async {
      await seedSample(tester, phone, pin: true);
      await tester.runAsync(
        () => phone.container
            .read(lockControllerProvider.notifier)
            .setBiometrics(true, reason: 'prueba'),
      );
      expect(phone.biometrics.prompts, 1);
      await pumpRegalos(tester, phone);
      await openSettings(tester);

      // La huella sale bien: directo al último paso, sin teclear el PIN.
      await tapText(tester, 'Borrar todo');
      await tapText(tester, 'Continuar');
      expect(phone.biometrics.prompts, 2);
      expect(find.byType(PinVerifyScreen), findsNothing);
      expect(find.byType(EraseAllDialog), findsOneWidget);
      await tapText(tester, 'Cancelar');
      await expectUntouched(tester, phone);

      // La huella falla: se pide el PIN y sin él no se sigue.
      phone.biometrics.succeeds = false;
      await tapText(tester, 'Borrar todo');
      await tapText(tester, 'Continuar');
      expect(phone.biometrics.prompts, 3);
      expect(find.byType(EraseAllDialog), findsNothing);
      expect(find.byType(PinVerifyScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      await expectUntouched(tester, phone);

      await tapText(tester, 'Borrar todo');
      await tapText(tester, 'Continuar');
      await enterPin(tester, '1234');
      expect(find.byType(EraseAllDialog), findsOneWidget);
      await confirm(tester);
      await expectFirstUse(tester, phone);
    },
    size: tall,
    overrides: [tempOverride],
  );

  {
    final server = FakeSyncServer();
    final transport = server.connect();
    screenTest(
      'con sincronización: lo dice en el primer diálogo, borra primero la '
      'copia del servidor y después lo de este móvil',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openSettings(tester);
        await tapText(tester, 'Borrar todo');
        expect(find.textContaining(serverNote), findsOneWidget);
        await tapText(tester, 'Continuar');
        expect(server.calls['delete'], isNull);
        await confirm(tester);
        expect(server.calls['delete'], 1);
        await expectFirstUse(tester, phone);
      },
      size: tall,
      overrides: withServer(transport),
      syncHost: null,
    );
  }

  {
    final server = FakeSyncServer();
    final transport = server.connect();
    screenTest(
      'sin red avisa y deja elegir: cancelar no borra nada y reintentar con '
      'red lo borra todo',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        transport.offline = true;
        await toLastStep(tester);
        await confirm(tester);

        // El servidor no responde: tres salidas y nada borrado.
        expect(server.calls['delete'], 1);
        expect(find.byType(EraseAllDialog), findsOneWidget);
        expect(find.text(failedTitle), findsOneWidget);
        expect(
          find.textContaining('la copia cifrada se queda en el servidor'),
          findsOneWidget,
        );
        for (final label in [
          'Reintentar',
          'Borrar solo este móvil',
          'Cancelar',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expectNoRoundShapes(tester, find.byType(EraseAllDialog));
        expect(tester.takeException(), isNull);

        // Reintentar sin red vuelve al mismo aviso.
        await tapText(tester, 'Reintentar');
        expect(server.calls['delete'], 2);
        expect(find.text(failedTitle), findsOneWidget);

        // Cancelar lo deja todo como estaba.
        await tapText(tester, 'Cancelar');
        await expectUntouched(tester, phone);

        // Otra vez, y ahora vuelve la red antes de reintentar.
        await tapText(tester, 'Borrar todo');
        await tapText(tester, 'Continuar');
        await confirm(tester);
        expect(find.text(failedTitle), findsOneWidget);
        transport.offline = false;
        await tapText(tester, 'Reintentar');
        expect(server.calls['delete'], 4);
        await expectFirstUse(tester, phone);
      },
      size: tall,
      overrides: withServer(transport),
      syncHost: null,
    );
  }

  {
    final server = FakeSyncServer();
    final transport = server.connect();
    screenTest(
      'sin red se puede borrar solo este móvil',
      (tester, phone) async {
        await seedSample(tester, phone, pin: true);
        await pumpRegalos(tester, phone);
        transport.offline = true;
        await toLastStep(tester, pin: '1234');
        await confirm(tester);
        expect(find.text(failedTitle), findsOneWidget);
        await tapText(tester, 'Borrar solo este móvil');
        // El servidor solo recibió el intento que falló.
        expect(server.calls['delete'], 1);
        await expectFirstUse(tester, phone);
      },
      size: tall,
      overrides: withServer(transport),
      syncHost: null,
    );
  }

  screenTest(
    'en inglés la palabra es DELETE y con la letra grande el diálogo cabe',
    (tester, phone) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Settings').last);
      await settle(tester);
      final row = find.text('Delete everything');
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await settle(tester);
      expect(find.text('Delete everything?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Continue');
      expect(find.textContaining('Type DELETE'), findsOneWidget);
      await typeWord(tester, 'BORRAR');
      expect(confirmEnabled(tester), isFalse);
      await typeWord(tester, 'delete');
      expect(confirmEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(kEraseAllConfirmKey));
      await settle(tester);
      expect((await familyState(tester, phone)).hasFamily, isFalse);
      expect(phone.secrets.values, isEmpty);
    },
    size: tall,
    textScale: 1.3,
    overrides: [tempOverride],
  );
}
