// El código de recuperación en la interfaz: crear, comprobar, cambiar, quitar,
// recuperar con palabras o QR, cada error en lenguaje llano y la lista que se
// ha pasado a otro móvil. La capa de aplicación va falseada
// (`helpers/fake_recovery.dart`); la lógica real la prueban `test/sync`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/motion/haptics.dart';
import 'package:regalos/core/widgets/settings_row.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/recovery/presentation/recovery_problem.dart';
import 'package:regalos/features/recovery/presentation/transferred_gate.dart';
import 'package:regalos/features/sharing/presentation/join_qr_screen.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';

import '../helpers/fake_haptics.dart';
import '../helpers/fake_recovery.dart';
import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/settings_column.dart';
import '../helpers/tablet.dart';
import 'settings_test.dart' show openSettings;

late FakeRecovery fake;
late FakeHaptics haptics;
late RecoveryCodeDisplay display;

final List<String> clipboardWrites = [];
String? clipboardText;

List<Override> _overrides() => [
  recoveryApplicationProvider.overrideWith(() => fake),
  hapticsProvider.overrideWith((ref) => haptics),
];

/// Una prueba de pantalla con la capa de recuperación falseada.
void recoveryTest(
  String description,
  Future<void> Function(WidgetTester tester, FakePhone phone) body, {
  RecoveryStatus initial = const RecoveryStatus(RecoveryReadiness.absent),
  Size size = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  ScannerBuilder? scanner,
}) {
  screenTest(
    description,
    (tester, phone) async {
      haptics = FakeHaptics();
      clipboardWrites.clear();
      clipboardText = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return clipboardText == null
                ? null
                : <String, Object?>{'text': clipboardText};
          }
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add((call.arguments as Map)['text'] as String);
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
      display = (await tester.runAsync(sampleRecoveryDisplay))!;
      fake = FakeRecovery(initial: initial, display: display);
      await body(tester, phone);
    },
    size: size,
    textScale: textScale,
    brightness: brightness,
    scanner: scanner,
    overrides: _overrides(),
  );
}

/// Un rato de fotogramas sin esperar a que acabe nada: con un indicador
/// girando, `pumpAndSettle` no acabaría.
Future<void> spin(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// «Tengo un código de recuperación» de la bienvenida, aunque quede por debajo
/// del pliegue.
Future<void> openRecover(WidgetTester tester) async {
  final button = find.text('Tengo un código de recuperación');
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await settle(tester);
}

Future<void> openRecoveryRow(WidgetTester tester) async {
  await openSettings(tester);
  await tapVisible(
    tester,
    find.widgetWithText(SettingsRow, 'Código de recuperación'),
  );
}

/// Cada palabra de la prueba es de verdad una del código.
Finder word(String text) => find.text(text);

/// Escribe en el campo de palabra [i] (empieza en 0).
Future<void> typeWord(WidgetTester tester, int i, String text) async {
  await tester.enterText(find.byType(TextField).at(i), text);
  await tester.pump();
}

Future<void> pasteAll(WidgetTester tester, String text) async {
  clipboardText = text;
  await tester.tap(find.text('Pegar las 24 palabras'));
  await settle(tester);
}

Finder get submit => find.widgetWithText(FilledButton, 'Recuperar la lista');

/// Las tres palabras que pide la comprobación, leídas de su texto.
List<int> askedNumbers(WidgetTester tester) {
  final text = tester
      .widgetList<Text>(find.textContaining('Escribe las palabras'))
      .first
      .data!;
  return RegExp(r'\d+').allMatches(text).map((m) => int.parse(m[0]!)).toList();
}

Future<void> createUntilWords(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone);
  await pumpRegalos(tester, phone);
  await openRecoveryRow(tester);
  await tapText(tester, 'Crear código de recuperación');
  await tapText(tester, 'Continuar');
}

void main() {
  group('Ajustes › Código de recuperación', () {
    recoveryTest('la fila dice el estado real y abre la pantalla', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettings(tester);
      final row = find.widgetWithText(SettingsRow, 'Código de recuperación');
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Sin crear')),
        findsOneWidget,
      );
      await tapVisible(tester, row);
      expect(
        find.text(
          'Prepara un código para recuperar la lista si pierdes este móvil',
        ),
        findsOneWidget,
      );
      expect(find.text('Crear código de recuperación'), findsOneWidget);
      // Dice qué recupera y qué no, sin tecnicismos.
      expect(
        find.textContaining('todo lo que este móvil puede ver'),
        findsOneWidget,
      );
      expect(find.textContaining('No recuperan lo que nunca'), findsOneWidget);
      for (final banned in ['credencial', 'cápsula', 'Worker']) {
        expect(find.textContaining(banned), findsNothing);
      }
    });

    for (final (initial, value) in [
      (const RecoveryStatus(RecoveryReadiness.prepared), 'Preparado'),
      (
        const RecoveryStatus(RecoveryReadiness.confirmationPending),
        'Sin comprobar',
      ),
      (const RecoveryStatus(RecoveryReadiness.updatePending), 'Preparando'),
      (
        const RecoveryStatus(
          RecoveryReadiness.needsAttention,
          cause: 'network',
        ),
        'Revisar',
      ),
    ]) {
      recoveryTest('la fila dice «$value» con ese estado', (
        tester,
        phone,
      ) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openSettings(tester);
        expect(
          find.descendant(
            of: find.widgetWithText(SettingsRow, 'Código de recuperación'),
            matching: find.text(value),
          ),
          findsOneWidget,
        );
      }, initial: initial);
    }

    recoveryTest(
      'preparado: se puede cambiar y quitar, y no hay nada más que hacer',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openRecoveryRow(tester);
        expect(find.text('Código preparado'), findsOneWidget);
        expect(find.text('Cambiar el código'), findsOneWidget);
        expect(find.text('Quitar el código'), findsOneWidget);
        expect(find.text('Crear código de recuperación'), findsNothing);
      },
      initial: const RecoveryStatus(RecoveryReadiness.prepared),
    );

    recoveryTest('quitar el código pide confirmación, como todo borrado', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      await tapText(tester, 'Quitar el código');
      expect(find.text('¿Quitar el código de recuperación?'), findsOneWidget);
      // Con otro móvil o la web conectados, la lista sigue en el servidor:
      // no sale el aviso de que se borra.
      expect(fake.calls, contains('removalCheck'));
      expect(find.textContaining('también se borra la copia'), findsNothing);
      // Cancelar no quita nada.
      await tapText(tester, 'Cancelar');
      expect(fake.calls, isNot(contains('retire')));
      await tapText(tester, 'Quitar el código');
      await tapText(tester, 'Quitar código');
      expect(fake.calls, contains('retire'));
      expect(find.text('Código quitado'), findsOneWidget);
      // El estado vuelve al principio.
      expect(find.text('Crear código de recuperación'), findsOneWidget);
    }, initial: const RecoveryStatus(RecoveryReadiness.prepared));

    recoveryTest(
      'quitar el código sin otro móvil ni la web avisa de que también se '
      'borra la copia del servidor',
      (tester, phone) async {
        fake.removalStops = true;
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openRecoveryRow(tester);
        await tapText(tester, 'Quitar el código');
        expect(find.text('¿Quitar el código de recuperación?'), findsOneWidget);
        expect(
          find.textContaining('también se borra la copia cifrada de la lista'),
          findsOneWidget,
        );
        await tapText(tester, 'Quitar código');
        expect(fake.calls, contains('retire'));
      },
      initial: const RecoveryStatus(RecoveryReadiness.prepared),
    );

    recoveryTest(
      'necesita atención: dice la causa en llano y reintenta',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openRecoveryRow(tester);
        expect(find.text('Hay que revisar el código'), findsOneWidget);
        expect(find.textContaining('Sin conexión'), findsOneWidget);
        await tapText(tester, 'Reintentar');
        expect(fake.calls, contains('retry'));
      },
      initial: const RecoveryStatus(
        RecoveryReadiness.needsAttention,
        cause: 'network',
      ),
    );

    recoveryTest('actualización pendiente: se dice sin llamarlo «preparado»', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettings(tester);
      final row = find.widgetWithText(SettingsRow, 'Código de recuperación');
      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await spin(tester);
      expect(find.text('Preparando la copia…'), findsOneWidget);
      expect(find.text('Código preparado'), findsNothing);
    }, initial: const RecoveryStatus(RecoveryReadiness.updatePending));
  });

  recoveryTest(
    'unconfirmed code offers a replacement after leaving the words',
    (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      expect(find.text('Falta comprobar las palabras'), findsOneWidget);
      expect(find.text('Código preparado'), findsNothing);
      await tapText(tester, 'Continuar');
      await tapText(tester, 'Continuar');
      expect(fake.calls, contains('rotate'));
      expect(fake.calls, isNot(contains('create')));
      expect(find.text('Tus 24 palabras'), findsOneWidget);
    },
    initial: const RecoveryStatus(RecoveryReadiness.confirmationPending),
  );

  group('crear el código', () {
    recoveryTest('explicación, palabras numeradas, QR, comprobación y estado '
        'real', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      await tapText(tester, 'Crear código de recuperación');

      // Explicación: qué recupera, quién puede entrar, qué no recupera.
      expect(find.text('Crear el código'), findsOneWidget);
      expect(
        find.textContaining('papel o guárdalas en un gestor'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Quien las tenga puede entrar'),
        findsOneWidget,
      );
      expect(find.textContaining('nunca se sincronizó'), findsOneWidget);
      expect(fake.calls, isNot(contains('create')));

      // Sin PIN en la familia de muestra: pasa la autenticación y crea.
      await tapText(tester, 'Continuar');
      expect(fake.calls, contains('create'));
      expect(find.text('Tus 24 palabras'), findsOneWidget);
      expect(find.textContaining('no podrás volver a verlas'), findsOneWidget);
      expect(find.textContaining('No hagas captura'), findsOneWidget);
      for (var i = 0; i < 24; i++) {
        expect(
          find.text('${i + 1}'),
          findsOneWidget,
          reason: 'número ${i + 1}',
        );
        expect(word(display.words[i]), findsWidgets);
      }

      // El QR imprimible.
      await tapText(tester, 'Ver código QR');
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text(display.words.first), findsNothing);
      await tapText(tester, 'Ver las palabras');
      expect(find.byType(QrImageView), findsNothing);

      // Nada se copia al portapapeles.
      expect(clipboardWrites, isEmpty);
      expect(find.text('Copiar'), findsNothing);

      // Comprobación de tres palabras por su número.
      await tapText(tester, 'Ya las he guardado');
      expect(find.text('Comprueba que las has guardado'), findsOneWidget);
      final asked = askedNumbers(tester);
      expect(asked, hasLength(3));
      expect(asked.toSet(), hasLength(3));
      expect(asked, [...asked]..sort());
      // Una palabra mal escrita no deja pasar.
      for (var i = 0; i < 3; i++) {
        await tester.enterText(
          find.byType(TextField).at(i),
          i == 1 ? 'nada' : display.words[asked[i] - 1],
        );
      }
      await tapText(tester, 'Comprobar');
      expect(
        find.text('Alguna palabra no coincide. Míralas otra vez.'),
        findsOneWidget,
      );
      expect(haptics.levels, contains(HapticLevel.error));
      expect(fake.calls, isNot(contains('confirm')));
      // Y se puede volver a ver la lista.
      await tapText(tester, 'Ver las palabras otra vez');
      expect(find.text('Tus 24 palabras'), findsOneWidget);
      await tapText(tester, 'Ya las he guardado');
      for (var i = 0; i < 3; i++) {
        await tester.enterText(
          find.byType(TextField).at(i),
          display.words[askedNumbers(tester)[i] - 1].toUpperCase(),
        );
      }
      await tapText(tester, 'Comprobar');

      // Solo dice «preparado» cuando el estado lo confirma.
      expect(find.text('Código preparado'), findsOneWidget);
      expect(fake.calls, contains('confirm'));
      expect(find.widgetWithText(FilledButton, 'Listo'), findsOneWidget);
      expect(haptics.levels, contains(HapticLevel.success));
      await tapText(tester, 'Listo');
      expect(find.text('Código preparado'), findsOneWidget);
      expect(find.text('Cambiar el código'), findsOneWidget);
    });

    recoveryTest('mientras la copia no está confirmada dice «Preparando…», no '
        '«preparado»', (tester, phone) async {
      fake.afterCreate = const RecoveryStatus(RecoveryReadiness.updatePending);
      await createUntilWords(tester, phone);
      await tapText(tester, 'Ya las he guardado');
      final asked = askedNumbers(tester);
      for (var i = 0; i < 3; i++) {
        await tester.enterText(
          find.byType(TextField).at(i),
          display.words[asked[i] - 1],
        );
      }
      await tester.tap(find.text('Comprobar'));
      await spin(tester);
      expect(find.text('Preparando la copia…'), findsOneWidget);
      expect(find.textContaining('Todavía no está listo'), findsOneWidget);
      expect(find.text('Código preparado'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Listo'), findsNothing);
      expect(find.text('Cerrar y seguir luego'), findsOneWidget);
      // El estado real cambia y la pantalla lo sigue.
      fake.push(const RecoveryStatus(RecoveryReadiness.prepared));
      await spin(tester);
      expect(find.text('Código preparado'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Listo'), findsOneWidget);
    });

    recoveryTest('si la copia necesita atención lo dice y deja reintentar', (
      tester,
      phone,
    ) async {
      fake.afterCreate = const RecoveryStatus(
        RecoveryReadiness.needsAttention,
        cause: 'server',
      );
      await createUntilWords(tester, phone);
      await tapText(tester, 'Ya las he guardado');
      final asked = askedNumbers(tester);
      for (var i = 0; i < 3; i++) {
        await tester.enterText(
          find.byType(TextField).at(i),
          display.words[asked[i] - 1],
        );
      }
      await tapText(tester, 'Comprobar');
      expect(find.text('Hay que revisar el código'), findsOneWidget);
      await tapText(tester, 'Reintentar');
      expect(fake.calls, contains('retry'));
    });

    recoveryTest('salir de las palabras pide confirmación y no se pierden si '
        'se sigue', (tester, phone) async {
      await createUntilWords(tester, phone);
      await tapLabel(tester, 'Atrás');
      expect(find.text('¿Salir sin guardar las palabras?'), findsOneWidget);
      await tapText(tester, 'Seguir aquí');
      expect(find.text('Tus 24 palabras'), findsOneWidget);
      expect(word(display.words[0]), findsWidgets);
      await tapLabel(tester, 'Atrás');
      await tapText(tester, 'Salir');
      expect(find.text('Tus 24 palabras'), findsNothing);
      expect(find.text('Falta comprobar las palabras'), findsOneWidget);
      expect(find.text('Código preparado'), findsNothing);
    });

    recoveryTest('las palabras se tapan cuando la app deja de verse', (
      tester,
      phone,
    ) async {
      await createUntilWords(tester, phone);
      expect(word(display.words[0]), findsWidgets);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Palabras ocultas'), findsOneWidget);
      expect(find.text(display.words[0]), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Palabras ocultas'), findsNothing);
      expect(word(display.words[0]), findsWidgets);
    });

    recoveryTest(
      'cambiar el código usa su propio texto y la misma comprobación',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openRecoveryRow(tester);
        await tapText(tester, 'Cambiar el código');
        expect(
          find.textContaining('El anterior dejará de valer'),
          findsWidgets,
        );
        await tapText(tester, 'Continuar');
        expect(fake.calls, contains('rotate'));
        expect(find.text('Tus 24 palabras'), findsOneWidget);
      },
      initial: const RecoveryStatus(RecoveryReadiness.prepared),
    );

    recoveryTest('una creación cortada recupera sus palabras sin pedirlas otra '
        'vez', (tester, phone) async {
      fake.reclaim = display;
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      await tapText(tester, 'Crear código de recuperación');
      await settle(tester);
      // Las palabras guardadas no se enseñan ni se consumen hasta pasar el
      // PIN o la huella (aquí no hay PIN: basta con continuar).
      expect(find.text('Tus 24 palabras'), findsNothing);
      expect(fake.calls, isNot(contains('take')));
      await tapText(tester, 'Continuar');
      expect(find.text('Tus 24 palabras'), findsOneWidget);
      expect(fake.calls, contains('take'));
      expect(fake.calls, isNot(contains('create')));
    });

    recoveryTest('un fallo de red se explica y se puede reintentar', (
      tester,
      phone,
    ) async {
      fake.createError = const RecoveryApplicationException(
        'network',
        retryable: true,
      );
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      await tapText(tester, 'Crear código de recuperación');
      await tapText(tester, 'Continuar');
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.text('Tus 24 palabras'), findsNothing);
      fake.createError = null;
      await tapText(tester, 'Continuar');
      expect(find.text('Tus 24 palabras'), findsOneWidget);
    });

    recoveryTest('si la copia no queda preparada no enseña las palabras, '
        'enseña progreso y reintenta', (tester, phone) async {
      fake.createError = const RecoveryApplicationException(
        'publication_pending',
        retryable: true,
      );
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      await tapText(tester, 'Crear código de recuperación');
      await tester.tap(find.text('Continuar'));
      // La comprobación del PIN y el almacén son reales: se les da tiempo.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await spin(tester, 8);
      expect(find.text('Preparando la copia…'), findsOneWidget);
      expect(find.text('Tus 24 palabras'), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      // Cuando por fin está confirmada, se recuperan las palabras guardadas.
      fake.reclaim = display;
      await tester.tap(find.text('Reintentar'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await spin(tester, 8);
      expect(fake.calls, contains('retry'));
      // Hay palabras guardadas: se enseñan al continuar, no antes.
      expect(find.text('Tus 24 palabras'), findsNothing);
      await tapText(tester, 'Continuar');
      expect(find.text('Tus 24 palabras'), findsOneWidget);
    });

    recoveryTest('crear pide el PIN antes de enseñar nada', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone, pin: true);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      await tapText(tester, 'Crear código de recuperación');
      await tapText(tester, 'Continuar');
      expect(
        find.text('Escribe tu PIN para ver las palabras.'),
        findsOneWidget,
      );
      expect(fake.calls, isNot(contains('create')));
      for (final digit in '0000'.split('')) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tapText(tester, 'Continuar');
      expect(find.textContaining('PIN incorrecto'), findsOneWidget);
      expect(fake.calls, isNot(contains('create')));
      for (final digit in '1234'.split('')) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.tap(find.text('Continuar'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await settle(tester);
      expect(fake.calls, contains('create'));
      expect(find.text('Tus 24 palabras'), findsOneWidget);
    });
  });

  group('recuperar con el código', () {
    recoveryTest('la bienvenida lleva a escribir las 24 palabras', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      expect(find.text('Tengo un código de recuperación'), findsOneWidget);
      await openRecover(tester);
      expect(find.text('Recuperar la lista'), findsNWidgets(2));
      expect(find.byType(TextField), findsNWidgets(24));
      expect(find.text('0 de 24 palabras'), findsOneWidget);
      expect(submit.evaluate().single.widget, isA<FilledButton>());
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      // Atrás vuelve a la bienvenida.
      await tapLabel(tester, 'Atrás');
      expect(find.text('Tengo un código de recuperación'), findsOneWidget);
    });

    recoveryTest('cada casilla de palabra es un único campo con su etiqueta', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      await openRecover(tester);
      // Todos los nodos de campo de texto del árbol de accesibilidad.
      final fields = <SemanticsNode>[];
      void visit(SemanticsNode node) {
        if (node.getSemanticsData().flagsCollection.isTextField) {
          fields.add(node);
        }
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      // La raíz de la vista, que es quien lleva el árbol de accesibilidad.
      visit(
        tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!,
      );
      expect(fields, hasLength(24));
      for (var i = 0; i < 24; i++) {
        expect(
          fields.where((n) => n.label == 'Palabra ${i + 1}'),
          hasLength(1),
          reason: 'Palabra ${i + 1}',
        );
      }
    });

    recoveryTest('autocompleta, valida cada palabra y cuenta las que valen', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      await openRecover(tester);
      await typeWord(tester, 0, 'aban');
      expect(find.widgetWithText(InkWell, 'abandon'), findsOneWidget);
      await tester.tap(find.widgetWithText(InkWell, 'abandon'));
      await settle(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'abandon',
      );
      expect(find.text('1 de 24 palabras'), findsOneWidget);
      // Una palabra que no existe, avisada con su número.
      await typeWord(tester, 4, 'zzzz');
      expect(find.text('La palabra 5 no está en la lista.'), findsOneWidget);
      await typeWord(tester, 4, 'able');
      expect(find.text('La palabra 5 no está en la lista.'), findsNothing);
      expect(find.text('2 de 24 palabras'), findsOneWidget);
    });

    recoveryTest('pegar las 24 de golpe, en el botón y en cualquier campo', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      await openRecover(tester);
      await tapText(tester, 'Pegar las 24 palabras');
      expect(find.text('No hay nada copiado.'), findsOneWidget);
      await pasteAll(tester, 'solo tres palabras');
      expect(find.text('Lo copiado no tiene 24 palabras.'), findsOneWidget);
      await pasteAll(tester, display.words.join(' '));
      expect(find.text('24 de 24 palabras'), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      // En un campo suelto, varias palabras pegadas se reparten.
      for (var i = 0; i < 24; i++) {
        await tester.enterText(find.byType(TextField).at(i), '');
      }
      await tester.pump();
      await tester.enterText(
        find.byType(TextField).at(3),
        display.words.skip(3).take(4).join(' '),
      );
      await settle(tester);
      expect(find.text('4 de 24 palabras'), findsOneWidget);
    });

    recoveryTest('la suma de control se comprueba antes de enviar', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      await openRecover(tester);
      // Dos palabras cambiadas de sitio: todas valen, el conjunto no.
      final swapped = [...display.words];
      final first = swapped[0];
      swapped[0] = swapped[1] == first ? swapped[2] : swapped[1];
      swapped[1] = first;
      await pasteAll(tester, swapped.join(' '));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await settle(tester);
      expect(find.textContaining('no forman un código válido'), findsOneWidget);
      expect(fake.calls, isNot(contains('words')));
      expect(haptics.levels, contains(HapticLevel.error));
    });

    recoveryTest('recupera con las palabras: progreso real y a quién '
        'pertenece el móvil', (tester, phone) async {
      await seedSample(tester, phone);
      await tester.runAsync(
        () => phone.container
            .read(selfRecipientIdProvider.notifier)
            .choose('aritz'),
      );
      await pumpRegalos(tester, phone);
      phone.container.read(routerProvider).go(AppRoutes.recover);
      await settle(tester);
      await pasteAll(tester, display.words.join(' '));
      fake.holdRestore = Completer<void>();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await spin(tester);
      // Se envía lo escrito y los campos se vacían.
      expect(fake.lastWords, display.words.join(' '));
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Recuperando la lista'), findsOneWidget);
      for (final step in [
        'Buscando la copia',
        'Comprobando el código',
        'Descargando la lista',
        'Instalando en este móvil',
      ]) {
        expect(find.text(step), findsOneWidget);
      }
      expect(find.text('Lista recuperada'), findsNothing);
      // Las fases reales mueven la lista de pasos.
      Finder semanticsOf(String label) => find.bySemanticsLabel(label);
      expect(
        tester.getSemantics(semanticsOf('Buscando la copia')).value,
        isNot('hecho'),
      );
      fake.reportPhase(RecoveryPhase.downloading);
      await spin(tester);
      expect(
        tester.getSemantics(semanticsOf('Buscando la copia')).value,
        'hecho',
      );
      expect(
        tester.getSemantics(semanticsOf('Comprobando el código')).value,
        'hecho',
      );
      expect(
        tester.getSemantics(semanticsOf('Instalando en este móvil')).value,
        isNot('hecho'),
      );
      fake.holdRestore!.complete();
      await spin(tester, 10);
      expect(find.text('Lista recuperada'), findsOneWidget);
      expect(find.text('Este móvil es de Aritz.'), findsOneWidget);
      expect(find.text('Tu lista tiene 3 personas.'), findsOneWidget);
      expect(haptics.levels, contains(HapticLevel.success));
      await tapText(tester, 'Entrar en la lista');
      expect(find.text('Lista recuperada'), findsNothing);
    });

    recoveryTest('en un móvil nuevo se ve el resultado antes que el aviso del '
        'PIN, y «Entrar en la lista» lleva a la app y luego al PIN', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      await openRecover(tester);
      await pasteAll(tester, display.words.join(' '));
      fake.holdRestore = Completer<void>();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await spin(tester);
      // La lista se instala en este móvil: a partir de aquí hay familia y sin
      // PIN, que es cuando el aviso de crearlo se adelantaba.
      await tester.runAsync(
        () => familyOf(phone).createFamily(deviceName: 'Móvil nuevo'),
      );
      fake.holdRestore!.complete();
      await spin(tester, 12);
      expect(find.text('Lista recuperada'), findsOneWidget);
      expect(find.text('Entrar en la lista'), findsOneWidget);
      expect(find.text('Crea un PIN'), findsNothing);
      // Entrar lleva a la app y ahí, ya, el aviso del PIN.
      await tester.tap(find.text('Entrar en la lista'));
      await settle(tester);
      expect(find.text('Lista recuperada'), findsNothing);
      expect(find.text('Crea un PIN'), findsOneWidget);
      final router = phone.container.read(routerProvider);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        startsWith('/people'),
      );
    });

    recoveryTest('un móvil sin persona asignada lo dice y lleva a Ajustes', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      phone.container.read(routerProvider).go(AppRoutes.recover);
      await settle(tester);
      await pasteAll(tester, display.words.join(' '));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await spin(tester, 10);
      expect(find.textContaining('no tiene persona asignada'), findsOneWidget);
    });

    group('errores tipados', () {
      for (final (name, error, status, title, other, retry) in [
        (
          'sin conexión',
          const RecoveryApplicationException('network', retryable: true),
          null,
          'Sin conexión',
          false,
          true,
        ),
        (
          'código incorrecto',
          null,
          const RecoveryStatus(
            RecoveryReadiness.needsAttention,
            phase: RecoveryPhase.needsAttention,
            cause: 'not_found',
          ),
          'Ese código no abre ninguna lista',
          true,
          false,
        ),
        (
          'código retirado',
          null,
          const RecoveryStatus(
            RecoveryReadiness.needsAttention,
            phase: RecoveryPhase.needsAttention,
            cause: 'recovery_retired',
          ),
          'Ese código ya no vale',
          true,
          false,
        ),
        (
          'móvil quitado de la familia',
          null,
          const RecoveryStatus(
            RecoveryReadiness.needsAttention,
            phase: RecoveryPhase.needsAttention,
            cause: 'revoked',
          ),
          'Este móvil ya no está en la familia',
          true,
          false,
        ),
        (
          'recuperación incompleta',
          null,
          const RecoveryStatus(
            RecoveryReadiness.needsAttention,
            phase: RecoveryPhase.needsAttention,
            cause: 'missing_common_keyring',
          ),
          'La recuperación se quedó a medias',
          false,
          true,
        ),
        (
          'otra operación en marcha',
          const RecoveryApplicationException('operation_pending'),
          null,
          'Hay otra operación en marcha',
          false,
          true,
        ),
      ]) {
        recoveryTest('$name: explica y ofrece lo que se puede hacer', (
          tester,
          phone,
        ) async {
          await pumpRegalos(tester, phone);
          await openRecover(tester);
          await pasteAll(tester, display.words.join(' '));
          fake.restoreError = error;
          fake.restoreFinal = status;
          await tester.ensureVisible(submit);
          await tester.tap(submit);
          await spin(tester, 10);
          expect(find.text(title), findsOneWidget);
          expect(
            find.widgetWithText(FilledButton, 'Escribir otro código'),
            other ? findsOneWidget : findsNothing,
          );
          expect(
            find.text('Reintentar'),
            retry ? findsOneWidget : findsNothing,
          );
          expect(haptics.levels, contains(HapticLevel.error));
          // Nada técnico en pantalla.
          for (final banned in [
            'credencial',
            'cápsula',
            'Worker',
            'not_found',
          ]) {
            expect(find.textContaining(banned), findsNothing);
          }
          if (other) {
            await tapText(tester, 'Escribir otro código');
            expect(fake.calls, contains('abandon'));
            expect(find.byType(TextField), findsNWidgets(24));
            expect(find.text('0 de 24 palabras'), findsOneWidget);
          }
          if (retry) {
            fake.restoreFinal = const RecoveryStatus(
              RecoveryReadiness.prepared,
            );
            await tester.tap(find.text('Reintentar'));
            await spin(tester, 10);
            expect(fake.calls, contains('retry'));
            expect(find.text('Lista recuperada'), findsOneWidget);
          }
        });
      }

      recoveryTest('un código de otra familia pide confirmar y repite con '
          'sustitución', (tester, phone) async {
        await pumpRegalos(tester, phone);
        await openRecover(tester);
        await pasteAll(tester, display.words.join(' '));
        fake.restoreFinal = const RecoveryStatus(
          RecoveryReadiness.needsAttention,
          phase: RecoveryPhase.needsAttention,
          cause: 'different_family',
        );
        await tester.tap(submit);
        await spin(tester, 10);
        expect(find.text('¿Sustituir la lista de este móvil?'), findsOneWidget);
        expect(
          find.textContaining('sustituirá a la que tienes en este móvil'),
          findsOneWidget,
        );
        // Cancelar deja el aviso, sin sustituir nada.
        await tester.tap(find.text('Cancelar'));
        await spin(tester, 6);
        expect(find.text('Este código es de otra familia'), findsOneWidget);
        expect(fake.calls, ['words']);
        // Confirmar repite la misma petición con la sustitución.
        fake.restoreFinal = const RecoveryStatus(RecoveryReadiness.prepared);
        await tester.tap(find.widgetWithText(FilledButton, 'Sustituir'));
        await spin(tester, 6);
        await tester.tap(find.text('Sustituir').last);
        await spin(tester, 10);
        expect(fake.calls, ['words', 'words+replace']);
        expect(fake.lastWords, display.words.join(' '));
        expect(find.text('Lista recuperada'), findsOneWidget);
      });

      recoveryTest('cancelar la recuperación pide confirmar y vuelve a las '
          'palabras', (tester, phone) async {
        await pumpRegalos(tester, phone);
        await openRecover(tester);
        await pasteAll(tester, display.words.join(' '));
        fake.restoreError = const RecoveryApplicationException(
          'network',
          retryable: true,
        );
        await tester.tap(submit);
        await spin(tester, 10);
        await tester.tap(find.text('Cancelar la recuperación'));
        await spin(tester, 6);
        expect(find.text('¿Cancelar la recuperación?'), findsOneWidget);
        await tester.tap(find.text('Seguir'));
        await spin(tester, 6);
        expect(fake.calls, isNot(contains('abandon')));
        await tester.tap(find.text('Cancelar la recuperación'));
        await spin(tester, 6);
        await tester.tap(find.text('Cancelar recuperación'));
        await spin(tester, 6);
        expect(fake.calls, contains('abandon'));
        expect(find.byType(TextField), findsNWidgets(24));
      });

      recoveryTest('si cancelar falla, lo dice y se queda donde estaba', (
        tester,
        phone,
      ) async {
        fake.abandonError = StateError('x');
        await pumpRegalos(tester, phone);
        await openRecover(tester);
        await pasteAll(tester, display.words.join(' '));
        fake.restoreFinal = const RecoveryStatus(
          RecoveryReadiness.needsAttention,
          phase: RecoveryPhase.needsAttention,
          cause: 'not_found',
        );
        await tester.tap(submit);
        await spin(tester, 10);
        await tester.tap(find.text('Escribir otro código'));
        await spin(tester, 6);
        expect(find.textContaining('No se ha podido cancelar'), findsOneWidget);
        expect(find.text('Ese código no abre ninguna lista'), findsOneWidget);
      });

      test('cada código técnico cae en un grupo con texto', () {
        expect(recoveryProblemOf('network'), RecoveryProblem.offline);
        expect(recoveryProblemOf('not_found'), RecoveryProblem.wrongCode);
        expect(recoveryProblemOf('recovery_retired'), RecoveryProblem.retired);
        expect(recoveryProblemOf('revoked'), RecoveryProblem.removed);
        expect(
          recoveryProblemOf('generation_gone'),
          RecoveryProblem.incomplete,
        );
        expect(recoveryProblemOf('algo_raro'), RecoveryProblem.other);
        expect(
          recoveryProblemOfException(
            const RecoveryApplicationException('x', retryable: true),
          ),
          RecoveryProblem.offline,
        );
      });
    });

    recoveryTest(
      'al volver con una recuperación a medias se ve su estado, no el '
      'formulario',
      (tester, phone) async {
        await pumpRegalos(tester, phone);
        await openRecover(tester);
        expect(find.byType(TextField), findsNWidgets(24));
        fake.push(
          const RecoveryStatus(
            RecoveryReadiness.needsAttention,
            phase: RecoveryPhase.needsAttention,
            cause: 'recovery_retired',
          ),
        );
        await settle(tester);
        expect(find.text('Ese código ya no vale'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      },
    );

    recoveryTest(
      'una recuperación en marcha enseña su progreso',
      (tester, phone) async {
        await pumpRegalos(tester, phone);
        final button = find.text('Tengo un código de recuperación');
        await tester.ensureVisible(button);
        await tester.pump();
        await tester.tap(button);
        await spin(tester, 10);
        expect(find.text('Recuperando la lista'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      },
      initial: const RecoveryStatus(
        RecoveryReadiness.updatePending,
        phase: RecoveryPhase.downloading,
      ),
    );

    recoveryTest(
      'escanear el QR: lee el código y recupera; otro QR se avisa',
      (tester, phone) async {
        await pumpRegalos(tester, phone);
        await openRecover(tester);
        await tapText(tester, 'Escanear el QR');
        expect(find.text('Escanear el QR del código'), findsOneWidget);
        await tester.tap(find.text('leer otro'));
        await settle(tester);
        expect(
          find.text('Ese QR no es un código de recuperación.'),
          findsOneWidget,
        );
        expect(fake.calls, isNot(contains('qr')));
        await tester.tap(find.text('leer código'));
        await spin(tester, 12);
        expect(fake.lastQr, display.qrText);
        expect(find.text('Lista recuperada'), findsOneWidget);
      },
      scanner: (context, onCode) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: () => onCode('https://otra.cosa/'),
            child: const Text('leer otro'),
          ),
          TextButton(
            onPressed: () => onCode(display.qrText),
            child: const Text('leer código'),
          ),
        ],
      ),
    );
  });

  group('la lista se ha pasado a otro móvil', () {
    recoveryTest(
      'pantalla tranquila de solo lectura, sin acciones de edición',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        expect(
          find.text('Esta lista se ha pasado a otro móvil'),
          findsOneWidget,
        );
        expect(find.textContaining('copia de solo lectura'), findsOneWidget);
        expect(find.text('Solo lectura'), findsOneWidget);
        // Lo que había sigue a la vista.
        Finder inside(String text) => find.descendant(
          of: find.byType(TransferredScreen),
          matching: find.text(text),
        );
        expect(inside('Aritz'), findsOneWidget);
        expect(inside('Nora'), findsOneWidget);
        expect(inside('Leo'), findsOneWidget);
        expect(inside('Estación de bomberos de bloques'), findsOneWidget);
        // Ni botones ni campos: nada que editar.
        // Solo hay dos salidas: recuperar con el código o borrar todo.
        expect(
          find.descendant(
            of: find.byType(TransferredScreen),
            matching: find.byType(FilledButton),
          ),
          findsOneWidget,
        );
        for (final type in [TextButton, TextField, FloatingActionButton]) {
          expect(
            find.descendant(
              of: find.byType(TransferredScreen),
              matching: find.byType(type),
            ),
            findsNothing,
            reason: '$type',
          );
        }
        // La app de debajo ya no se toca ni se lee.
        expect(find.byType(FloatingActionButton).hitTestable(), findsNothing);
        expect(find.text('Ajustes').hitTestable(), findsNothing);
      },
      initial: const RecoveryStatus(RecoveryReadiness.transferred),
    );

    recoveryTest(
      'también en una tablet',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        expect(
          find.text('Esta lista se ha pasado a otro móvil'),
          findsOneWidget,
        );
        final title = tester.getRect(
          find.text('Esta lista se ha pasado a otro móvil'),
        );
        expect(title.width, lessThanOrEqualTo(520));
        expect(tester.takeException(), isNull);
      },
      initial: const RecoveryStatus(RecoveryReadiness.transferred),
      size: kTabletLandscape,
    );

    recoveryTest(
      'si se pasa mientras se usa, la pantalla aparece sin tocar nada',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        expect(find.text('Esta lista se ha pasado a otro móvil'), findsNothing);
        fake.push(const RecoveryStatus(RecoveryReadiness.transferred));
        await settle(tester);
        expect(
          find.text('Esta lista se ha pasado a otro móvil'),
          findsOneWidget,
        );
      },
    );
  });

  group('tablet, letra grande y «Reducir movimiento»', () {
    recoveryTest('la pantalla de Ajustes va en su panel de detalle', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openSettings(tester);
      await tapVisible(
        tester,
        find.widgetWithText(SettingsRow, 'Código de recuperación'),
      );
      // La lista sigue a la izquierda y el apartado, a la derecha.
      expect(find.text('Crear código de recuperación'), findsOneWidget);
      expect(
        find.widgetWithText(SettingsRow, 'Código de recuperación'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }, size: kTabletLandscape);

    recoveryTest('crear en tablet vertical cabe en su columna', (
      tester,
      phone,
    ) async {
      await createUntilWords(tester, phone);
      final grid = tester.getRect(find.text(display.words.first).first);
      expect(grid.width, greaterThan(0));
      expect(find.text('Tus 24 palabras'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: kTabletPortrait);

    recoveryTest('recuperar en tablet va en una columna de 520', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      await openRecover(tester);
      final field = tester.getRect(find.byType(TextField).first);
      final last = tester.getRect(find.byType(TextField).at(23));
      expect(last.right - field.left, lessThanOrEqualTo(520));
      expect(tester.takeException(), isNull);
    }, size: kTabletPortrait);

    for (final scale in [1.3, 2.0]) {
      recoveryTest('con la letra al ${(scale * 100).round()} % nada desborda', (
        tester,
        phone,
      ) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        // El desborde de la tarjeta de cuenta atrás de Personas es de la
        // fuente de prueba (ver `text_scale_200_test.dart`): se descarta aquí
        // para que lo que viene mida solo estas pantallas.
        tester.takeException();
        await openRecoveryRow(tester);
        expect(tester.takeException(), isNull);
        await tapVisible(tester, find.text('Crear código de recuperación'));
        await tapText(tester, 'Continuar');
        expect(find.text('Tus 24 palabras'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tapText(tester, 'Ya las he guardado');
        expect(tester.takeException(), isNull);
        await tapText(tester, 'Ver las palabras otra vez');
        await tapLabel(tester, 'Atrás');
        await tapText(tester, 'Salir');
        phone.container.read(routerProvider).go(AppRoutes.recover);
        await settle(tester);
        expect(find.byType(TextField), findsNWidgets(24));
        expect(tester.takeException(), isNull);
      }, textScale: scale);
    }

    recoveryTest('con «Reducir movimiento» todo funciona igual, sin viajes', (
      tester,
      phone,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await createUntilWords(tester, phone);
      expect(find.text('Tus 24 palabras'), findsOneWidget);
      await tapText(tester, 'Ya las he guardado');
      final asked = askedNumbers(tester);
      for (var i = 0; i < 3; i++) {
        await tester.enterText(
          find.byType(TextField).at(i),
          display.words[asked[i] - 1],
        );
      }
      await tapText(tester, 'Comprobar');
      expect(find.text('Código preparado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    recoveryTest('en oscuro se ve igual', (tester, phone) async {
      await createUntilWords(tester, phone);
      expect(find.text('Tus 24 palabras'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, brightness: Brightness.dark);
  });
}
