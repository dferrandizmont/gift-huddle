import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/motion/success_mark.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/features/sharing/presentation/scan_viewfinder.dart';
import 'package:regalos/features/family/domain/family_errors.dart';
import 'package:regalos/features/family/presentation/family_texts.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/l10n/app_localizations_es.dart';
import 'package:regalos/features/sharing/application/incoming_share.dart';
import 'package:regalos/features/sharing/application/pairing_service.dart';
import 'package:regalos/features/sharing/application/share_service.dart';
import 'package:regalos/core/widgets/regalos_switch.dart';
import 'package:regalos/core/widgets/sheet_parts.dart';
import 'package:regalos/features/sharing/presentation/pairing_qr_view.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';

/// Espera a lo que corre fuera de la interfaz (cifrado, hilos aparte).
Future<void> waitReal(WidgetTester tester, [int ms = 400]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await settle(tester);
}

/// Pulsa el botón del lector de pruebas y deja correr lo real. No usa
/// `pumpAndSettle`: mientras se une, el lector enseña un indicador que no
/// para.
Future<void> scan(WidgetTester tester) async {
  await tester.tap(find.text('Leer código'));
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Un segundo móvil con la familia de muestra.
Future<FakePhone> sampleOwner(WidgetTester tester) async {
  final other = FakePhone();
  addTearDown(other.dispose);
  await seedSample(tester, other);
  return other;
}

void main() {
  const tall = Size(390, 1500);

  /// Abre Ajustes › Móviles de la familia.
  Future<void> openDevices(WidgetTester tester) async {
    await tester.tap(find.text('Ajustes').last);
    await settle(tester);
    await tapText(tester, 'Móviles de la familia');
  }

  screenTest(
    'Móviles de la familia: el estado, los conectados, un botón y una fila',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openDevices(tester);
      for (final text in [
        'Solo en este móvil',
        'Conectados',
        'Móvil de prueba',
        'Este móvil',
        'Conectar otro móvil',
        'Más opciones',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      // Las siete filas de antes ya no están aquí.
      for (final gone in [
        'Sincronización',
        'Invitar a alguien',
        'Unirme con un enlace',
        'Enseñar QR para emparejar',
        'Unirme con QR',
        'Enviar cambios',
        'Pegar cambios',
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      // Solo hay un botón, y con un solo móvil no se ofrece enviar la lista.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Enviar la lista ahora'), findsNothing);
    },
    size: tall,
  );

  screenTest('«Conectar otro móvil» pregunta dónde está y «Está aquí» '
      'dibuja el QR en la misma hoja', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openDevices(tester);
    await tapText(tester, 'Conectar otro móvil');
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('¿Dónde está el otro móvil?'), findsOneWidget);
    expect(find.text('Está aquí'), findsOneWidget);
    expect(find.text('Está lejos'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);

    await tapText(tester, 'Está aquí');
    // Sigue siendo la misma hoja, en su segundo paso.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('¿Dónde está el otro móvil?'), findsNothing);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      find.bySemanticsLabel('Código QR para conectar otro móvil'),
      findsOneWidget,
    );
    expect(find.textContaining('No hagas captura'), findsOneWidget);
    expect(find.textContaining('toca «Unirme a una familia», luego «Escanear el QR»'), findsOneWidget);

    // El código es el del servicio de emparejar, con la clave de la familia.
    final expected = await tester.runAsync(
      () => phone.container.read(pairingServiceProvider).qrTextForPairing(),
    );
    final shown = await tester.runAsync(
      () => phone.container.read(pairingQrProvider.future),
    );
    expect(shown, expected);
    expect(PairingPayload.parse(shown!).deviceName, 'Móvil de prueba');

    // La flecha vuelve a la pregunta sin cerrar la hoja; «Cerrar» la baja.
    await tapLabel(tester, 'Volver a Conectar otro móvil');
    expect(find.text('¿Dónde está el otro móvil?'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    await tapText(tester, 'Está aquí');
    await tapText(tester, 'Cerrar');
    expect(find.byType(BottomSheet), findsNothing);
  }, size: tall);

  screenTest('«Está lejos» cierra la hoja y abre la invitación con enlace', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openDevices(tester);
    await tapText(tester, 'Conectar otro móvil');
    await tapText(tester, 'Está lejos');
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Invitar a alguien'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Volver a Móviles de la familia'),
      findsOneWidget,
    );
  }, size: tall);

  screenTest('el paso de una hoja entra 44 px desde la derecha; con '
      '«Reducir movimiento» solo se funde', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openDevices(tester);
    await tapText(tester, 'Más opciones');
    Finder step() => find.descendant(
      of: find.byType(SheetSteps),
      matching: find.byType(Transform),
    );
    double dx() =>
        tester.widget<Transform>(step().first).transform.getTranslation().x;
    expect(dx(), 0);
    await tester.tap(find.text('Unir este móvil a otra familia').last);
    await tester.pump();
    expect(dx(), SheetSteps.travel);
    await tester.pump(const Duration(milliseconds: 120));
    expect(dx(), inExclusiveRange(0, SheetSteps.travel));
    await settle(tester);
    expect(dx(), 0);
    // Volver entra desde el otro lado.
    await tester.tap(find.bySemanticsLabel('Volver a Más opciones'));
    await tester.pump();
    expect(dx(), -SheetSteps.travel);
    await settle(tester);

    // Con «Reducir movimiento» no hay traslación ni cambio de alto animado.
    await tester.tapAt(const Offset(195, 60));
    await settle(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pump();
    await tapText(tester, 'Más opciones');
    await tester.tap(find.text('Unir este móvil a otra familia').last);
    await tester.pump();
    expect(step(), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SheetSteps),
        matching: find.byType(AnimatedSize),
      ),
      findsNothing,
    );
    final fade = tester.widget<Opacity>(
      find
          .descendant(
            of: find.byType(SheetSteps),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(fade.opacity, 0);
    await tester.pump(const Duration(milliseconds: 75));
    double opacity() => tester
        .widget<Opacity>(
          find
              .descendant(
                of: find.byType(SheetSteps),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    // A mitad del fundido de 150 ms: ni corte ni muelle.
    expect(opacity(), closeTo(0.5, 0.05));
    await tester.pump(const Duration(milliseconds: 80));
    expect(opacity(), 1);
  }, size: tall);

  screenTest(
    '«Más opciones» lleva a unirse a otra familia con su aviso',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openDevices(tester);
      await tapText(tester, 'Más opciones');
      // Sin servidor no hay nada que dejar de sincronizar ni nota del servidor.
      expect(find.text('Dejar de sincronizar'), findsNothing);
      expect(find.text('Cómo se protege la lista'), findsNothing);
      await tester.tap(find.text('Unir este móvil a otra familia').last);
      await settle(tester);
      expect(find.textContaining('se sustituye y se pierden'), findsOneWidget);
      expect(find.text('Pegar un enlace de invitación'), findsOneWidget);
      await tapText(tester, 'Escanear su QR');
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Leer código'), findsOneWidget);
    },
    size: tall,
    scanner: (context, onCode) => const Text('Leer código'),
  );

  screenTest(
    'el QR entra con escala de 0,96 a 1 y fundido, 120 ms después de pintarse',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openDevices(tester);
      await tapText(tester, 'Conectar otro móvil');
      await tester.tap(find.text('Está aquí'));
      await tester.pump();
      // Espera (sin avanzar el reloj de las animaciones) a que llegue el
      // código: el fotograma en que se pinta es el que arranca su entrada.
      final code = find.byType(QrImageView);
      for (var i = 0; i < 40 && code.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      expect(code, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 20));
      double fade() => tester
          .widget<Opacity>(
            find.ancestor(of: code, matching: find.byType(Opacity)).first,
          )
          .opacity;
      double scale() => tester
          .widgetList<Transform>(
            find.ancestor(of: code, matching: find.byType(Transform)),
          )
          .map((t) => t.transform.storage[0])
          .fold<double>(1, (a, b) => a < b ? a : b);
      // Durante los primeros 120 ms no se ve, y ya parte de 0,96.
      expect(fade(), 0);
      expect(scale(), closeTo(0.96, 0.001));
      await tester.pump(const Duration(milliseconds: 200));
      expect(fade(), inExclusiveRange(0, 1.001));
      expect(scale(), inInclusiveRange(0.96, 1.01));
      await tester.pumpAndSettle();
      // Se queda quieto: ni respira ni parpadea.
      expect(fade(), 1);
      expect(scale(), 1);
      expect(tester.hasRunningAnimations, isFalse);
    },
    size: tall,
  );

  String qr = '';
  screenTest(
    '«Escanear el QR» lee el código, empareja y vuelve a Personas',
    (tester, phone) async {
      final owner = await sampleOwner(tester);
      qr = (await tester.runAsync(
        () => owner.container.read(pairingServiceProvider).qrTextForPairing(),
      ))!;
      await pumpRegalos(tester, phone);
      await tapWelcomeChoice(tester, 'Escanear el QR');
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre de este móvil'),
        'Móvil de Eva',
      );
      // El visor tiene sus cuatro esquinas en reposo, en blanco.
      expect(find.byType(ScanViewfinder), findsOneWidget);
      expect(
        tester.state<ScanViewfinderState>(find.byType(ScanViewfinder)).locked,
        isFalse,
      );
      await scan(tester);
      // Con familia nueva y sin PIN, la app pide crearlo antes de seguir.
      expect(find.text('Crea un PIN'), findsOneWidget);
      await tapText(tester, 'Ahora no');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Móviles conectados'), findsOneWidget);
      expect(find.textContaining('familia de Móvil de prueba'), findsOneWidget);
      // Es una hoja con el sello de éxito, ya no un diálogo.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(SuccessMark), findsOneWidget);
      await tester.tap(find.text('Hecho'));
      await settle(tester);

      final state = await familyState(tester, phone);
      expect(state.paired, isTrue);
      expect(state.identity!.peerName, 'Móvil de prueba');
      expect(state.identity!.deviceName, 'Móvil de Eva');
      expect(state.listId, (await familyState(tester, owner)).listId);
      // Ya en Personas (todavía sin datos: el otro móvil los envía).
      expect(find.text('Aún no hay personas'), findsOneWidget);
    },
    scanner: (context, onCode) => TextButton(
      onPressed: () => onCode(qr),
      child: const Text('Leer código'),
    ),
  );

  screenTest(
    'unirse teniendo datos pide confirmar antes de sustituir la lista',
    (tester, phone) async {
      final owner = await sampleOwner(tester);
      qr = (await tester.runAsync(
        () => owner.container.read(pairingServiceProvider).qrTextForPairing(),
      ))!;
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      final before = (await familyState(tester, phone)).listId;
      phone.container.read(routerProvider).push('/join');
      await settle(tester);

      await scan(tester);
      expect(find.text('Este móvil ya tiene una lista'), findsOneWidget);
      // Cancelar no toca nada.
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect((await familyState(tester, phone)).listId, before);

      await scan(tester);
      await tester.tap(find.text('Sustituir y unirme'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Móviles conectados'), findsOneWidget);
      await tester.tap(find.text('Hecho'));
      await settle(tester);
      final after = await familyState(tester, phone);
      expect(after.listId, isNot(before));
      expect(after.listId, (await familyState(tester, owner)).listId);
    },
    scanner: (context, onCode) => TextButton(
      onPressed: () => onCode(qr),
      child: const Text('Leer código'),
    ),
  );

  screenTest(
    'un código que no es de la app avisa sin emparejar',
    (tester, phone) async {
      qr = 'hola';
      await pumpRegalos(tester, phone);
      await tapWelcomeChoice(tester, 'Escanear el QR');
      await tapText(tester, 'Leer código');
      await waitReal(tester);
      expect(find.text('Este código QR no es de Gift Huddle.'), findsOneWidget);
      expect((await familyState(tester, phone)).hasFamily, isFalse);
    },
    scanner: (context, onCode) => TextButton(
      onPressed: () => onCode(qr),
      child: const Text('Leer código'),
    ),
  );

  /// Empareja el móvil de la prueba con uno con datos y deja el de la prueba
  /// con su lista vacía y la app montada.
  Future<FakePhone> pairWithOwner(WidgetTester tester, FakePhone phone) async {
    final owner = await sampleOwner(tester);
    await tester.runAsync(() async {
      final qrText = await owner.container
          .read(pairingServiceProvider)
          .qrTextForPairing();
      await phone.container
          .read(pairingServiceProvider)
          .joinFromQr(qrText, deviceName: 'Móvil de Eva');
      await phone.container.read(lockControllerProvider.notifier).skipSetup();
    });
    await pumpRegalos(tester, phone);
    return owner;
  }

  screenTest('un fichero .regalos abierto desde fuera enseña su resumen', (
    tester,
    phone,
  ) async {
    final owner = await pairWithOwner(tester, phone);
    final bytes = await tester.runAsync(
      () => owner.container.read(shareServiceProvider).buildEnvelope(),
    );
    await tester.runAsync(
      () => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        kIncomingChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onFile', bytes),
        ),
        (_) {},
      ),
    );
    await waitReal(tester, 800);
    expect(find.text('Cambios recibidos'), findsOneWidget);
    expect(find.text('10 regalos nuevos'), findsOneWidget);
    await tapText(tester, 'Hecho');
    expect(find.text('Cambios recibidos'), findsNothing);

    // La lista llegó: Personas ya enseña a las tres personas.
    expect(find.text('Aritz'), findsOneWidget);

    // El mismo envío otra vez no trae nada nuevo.
    await tester.runAsync(
      () => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        kIncomingChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onFile', bytes),
        ),
        (_) {},
      ),
    );
    await waitReal(tester, 800);
    expect(find.text('Ya lo tenías todo al día.'), findsOneWidget);
  }, size: tall);

  screenTest('un fichero que no sirve enseña el error traducido', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tester.runAsync(
      () => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        kIncomingChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onFile', Uint8List.fromList([1, 2, 3, 4])),
        ),
        (_) {},
      ),
    );
    await waitReal(tester);
    expect(find.text('No se pudo abrir el envío'), findsOneWidget);
    expect(
      find.text('Este fichero o texto no es un envío de Gift Huddle.'),
      findsOneWidget,
    );
    await tapText(tester, 'Cerrar');
    expect(find.text('No se pudo abrir el envío'), findsNothing);
  });

  screenTest('un fichero de otra familia lo dice con claridad', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    final stranger = await sampleOwner(tester);
    final bytes = await tester.runAsync(
      () => stranger.container.read(shareServiceProvider).buildEnvelope(),
    );
    await pumpRegalos(tester, phone);
    await tester.runAsync(
      () => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        kIncomingChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onFile', bytes),
        ),
        (_) {},
      ),
    );
    await waitReal(tester);
    expect(find.textContaining('es de otra familia'), findsOneWidget);
  });

  screenTest('no hay interruptor de sincronización en ninguna parte', (
    tester,
    phone,
  ) async {
    await pairWithOwner(tester, phone);
    await openDevices(tester);
    void noSwitch() {
      expect(find.byType(RegalosSwitch), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Sincronizar automáticamente'), findsNothing);
    }

    noSwitch();
    await tapText(tester, 'Más opciones');
    expect(find.byType(BottomSheet), findsOneWidget);
    noSwitch();
    await tester.tapAt(const Offset(195, 60));
    await settle(tester);
    await tapText(tester, 'Conectar otro móvil');
    expect(find.byType(BottomSheet), findsOneWidget);
    noSwitch();
    await tester.tapAt(const Offset(195, 60));
    await settle(tester);
    await tapLabel(tester, 'Volver a Ajustes');
    await tapText(tester, 'Copia de seguridad');
    noSwitch();
  }, size: tall);

  screenTest('con dos móviles la lista enseña los dos y, sin servidor, '
      'ofrece enviar la lista', (tester, phone) async {
    await pairWithOwner(tester, phone);
    await tester.tap(find.text('Ajustes').last);
    await settle(tester);
    expect(find.bySemanticsLabel('Móviles de la familia. 2'), findsOneWidget);
    await tapText(tester, 'Móviles de la familia');
    for (final text in [
      'Conectados por fichero o QR',
      'Sin sincronización automática: envía la lista cuando cambie.',
      'Móvil de Eva',
      'Este móvil',
      'Móvil de prueba',
      'Conectado a esta familia',
      'Enviar la lista ahora',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  }, size: tall);

  screenTest('Copia de seguridad: guardar, recuperar y la nota de hoy', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tester.tap(find.text('Ajustes').last);
    await settle(tester);
    await tapText(tester, 'Copia de seguridad');
    for (final text in ['Guardar una copia', 'Recuperar una copia']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(
      find.textContaining('solo se abre en un móvil que ya esté conectado'),
      findsOneWidget,
    );
    // El código de recuperación (ADR 0004) aún no funciona: no se enseña.
    expect(find.textContaining('Código de recuperación'), findsNothing);
    expect(find.textContaining('Pronto'), findsNothing);

    await tapText(tester, 'Recuperar una copia');
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Pegar desde el portapapeles'), findsOneWidget);
    expect(find.textContaining('tócalo en Archivos'), findsOneWidget);
  }, size: tall);

  screenTest('«Recuperar una copia» importa el texto del portapapeles', (
    tester,
    phone,
  ) async {
    final owner = await pairWithOwner(tester, phone);
    final bytes = await tester.runAsync(
      () => owner.container.read(shareServiceProvider).buildEnvelope(),
    );
    var clipboard = '';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': clipboard};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.text('Ajustes').last);
    await settle(tester);
    await tapText(tester, 'Copia de seguridad');

    Future<void> paste() async {
      await tapText(tester, 'Recuperar una copia');
      await tapText(tester, 'Pegar desde el portapapeles');
    }

    // Portapapeles vacío.
    await paste();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.textContaining('No hay nada que pegar'), findsOneWidget);

    // Texto que no es un envío.
    clipboard = 'hola';
    await paste();
    await waitReal(tester);
    expect(find.text('No se pudo abrir el envío'), findsOneWidget);
    await tapText(tester, 'Cerrar');

    // El enlace de un envío de verdad.
    clipboard = envelopeToLink(bytes!);
    await paste();
    await waitReal(tester, 800);
    expect(find.text('Cambios recibidos'), findsOneWidget);
    expect(find.text('10 regalos nuevos'), findsOneWidget);
  }, size: tall);

  test('el resumen distingue nuevos, cambiados y borrados', () {
    final es = AppLocalizationsEs();
    expect(
      importSummaryText(
        es,
        const ImportSummary(giftsAdded: 3, giftsChanged: 2),
      ),
      '3 regalos nuevos, 2 cambiados',
    );
    expect(
      importSummaryText(
        es,
        const ImportSummary(giftsAdded: 1, giftsDeleted: 1),
      ),
      '1 regalo nuevo, 1 borrado',
    );
    expect(
      importSummaryText(es, const ImportSummary(docChanged: true)),
      'Se han actualizado personas u ocasiones.',
    );
    expect(
      importSummaryText(es, const ImportSummary()),
      'Ya lo tenías todo al día.',
    );
  });
}
