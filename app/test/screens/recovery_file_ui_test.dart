// El fichero de recuperación en la interfaz (ADR 0008): guardar y compartir
// desde las palabras, la contraseña opcional, «Comprobar un fichero»,
// «Recuperar con fichero» desde la bienvenida y los ficheros que llegan desde
// Archivos. La capa de aplicación del código va falseada
// (`helpers/fake_recovery.dart`) y la plataforma también
// (`helpers/fake_document_exchange.dart`); el formato y el flujo real los
// prueban `test/sync`.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/motion/haptics.dart';
import 'package:regalos/core/platform/document_exchange.dart';
import 'package:regalos/features/recovery/presentation/recovery_file_save_screen.dart';
import 'package:regalos/features/recovery/presentation/recovery_restore_screen.dart';
import 'package:regalos/features/sync/application/recovery_file_flow.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';

import '../helpers/fake_document_exchange.dart';
import '../helpers/fake_haptics.dart';
import '../helpers/fake_recovery.dart';
import '../helpers/memory_stores.dart' show FakePhone;
import '../helpers/pump_app.dart';
import '../helpers/screens.dart';
import 'recovery_ui_test.dart' show openRecoveryRow, spin;

late FakeRecovery fake;
late FakeDocumentExchange exchange;
late FakeHaptics haptics;
late RecoveryCodeDisplay display;
late SlowFileController slow;
bool hasFamily = false;

/// El flujo del fichero con la derivación de la contraseña a mano: con
/// contraseña no deriva de verdad (Argon2 tarda segundos), espera a [gate] y
/// sella la variante abierta.
class SlowFileController extends RecoveryFileController {
  Completer<void>? gate;
  int cancels = 0;

  /// Si deriva de verdad (Argon2), sin esperar a [gate].
  bool real = false;

  @override
  Future<PreparedRecoveryFile> prepare(
    RecoveryCodeDisplay display, {
    String? password,
    String? repeat,
  }) async {
    if (password == null || real) {
      return super.prepare(display, password: password, repeat: repeat);
    }
    state = const RecoveryFileState(activity: RecoveryFileActivity.deriving);
    await gate!.future;
    state = const RecoveryFileState();
    return super.prepare(display);
  }

  @override
  void cancel() {
    cancels++;
    final g = gate;
    if (g != null && !g.isCompleted) {
      g.completeError(
        const RecoveryFileFlowException(RecoveryFileFlowError.cancelled),
      );
    }
    state = const RecoveryFileState();
  }
}

List<Override> _overrides() => [
  recoveryApplicationProvider.overrideWith(() => fake),
  hapticsProvider.overrideWith((ref) => haptics),
  documentExchangeProvider.overrideWith((ref) => exchange),
  recoveryFileHasFamilyProvider.overrideWith(
    (ref) =>
        () async => hasFamily,
  ),
  recoveryFileProvider.overrideWith(() => slow),
];

void fileTest(
  String description,
  Future<void> Function(WidgetTester tester, FakePhone phone) body, {
  RecoveryStatus initial = const RecoveryStatus(RecoveryReadiness.absent),
  bool family = false,
  Size size = const Size(390, 844),
  double textScale = 1,
}) {
  screenTest(
    description,
    (tester, phone) async {
      haptics = FakeHaptics();
      exchange = FakeDocumentExchange();
      slow = SlowFileController();
      hasFamily = family;
      display = (await tester.runAsync(sampleRecoveryDisplay))!;
      fake = FakeRecovery(initial: initial, display: display);
      await body(tester, phone);
    },
    size: size,
    textScale: textScale,
    overrides: _overrides(),
  );
}

Future<void> createUntilWords(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone);
  await pumpRegalos(tester, phone);
  await openRecoveryRow(tester);
  await tapScrolling(tester, 'Crear código de recuperación');
  await tapScrolling(tester, 'Continuar');
}

/// Pulsa un texto, desplazando hasta él si queda fuera de la pantalla.
Future<void> tapScrolling(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

Future<void> openFileScreen(WidgetTester tester, FakePhone phone) async {
  await createUntilWords(tester, phone);
  final action = find.text('Guardar en un fichero');
  await tester.ensureVisible(action);
  await tester.pump();
  await tester.tap(action);
  await settle(tester);
}

Finder get saveButton => find.widgetWithText(FilledButton, 'Guardar');

/// Escribe en el campo [i] (0 y 1: contraseña y repetición) y deja acabar la
/// comprobación en vivo.
Future<void> typeIn(WidgetTester tester, int i, String text) async {
  await tester.enterText(find.byType(TextField).at(i), text);
  await settle(tester);
}

const _good = 'tulipan sobrecama velero hostil';

void main() {
  late RecoveryFileVectors vectors;
  setUpAll(() => vectors = RecoveryFileVectors.load());

  group('guardar en un fichero', () {
    fileTest('la acción está en las palabras y abre una pantalla sin '
        'contraseña por defecto', (tester, phone) async {
      await openFileScreen(tester, phone);
      expect(find.text('Proteger con contraseña'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('no lo envíes a la familia'), findsOneWidget);
      expect(
        find.textContaining('vale tanto como las palabras'),
        findsOneWidget,
      );
      expect(find.text('Compartir'), findsOneWidget);
    });

    fileTest('guardar con el selector comprueba el código y se puede guardar '
        'otra copia', (tester, phone) async {
      await openFileScreen(tester, phone);
      await tester.tap(saveButton);
      await settle(tester);
      expect(exchange.saved, hasLength(1));
      expect(exchange.names.single, startsWith('gift-huddle-recuperacion-'));
      expect(exchange.names.single, endsWith('.gifthuddle'));
      expect(fake.calls, contains('confirm'));
      expect(find.text('Fichero guardado'), findsOneWidget);
      expect(find.textContaining('el código está comprobado'), findsOneWidget);
      expect(haptics.levels, contains(HapticLevel.success));
      await tester.tap(find.text('Guardar otra copia'));
      await settle(tester);
      expect(exchange.saved, hasLength(2));
      await tapText(tester, 'Continuar');
      // Como si se hubieran comprobado las palabras: estado real de la copia.
      expect(find.text('Código preparado'), findsOneWidget);
      expect(find.text('Tus 24 palabras'), findsNothing);
    });

    fileTest('cerrar el selector no guarda ni comprueba nada', (
      tester,
      phone,
    ) async {
      await openFileScreen(tester, phone);
      exchange.readBack = (_) => null;
      await tester.tap(saveButton);
      await settle(tester);
      expect(exchange.saved, hasLength(1));
      expect(fake.calls, isNot(contains('confirm')));
      expect(find.text('Fichero guardado'), findsNothing);
      expect(find.textContaining('No se ha podido'), findsNothing);
    });

    fileTest('si lo releído no coincide lo dice y no comprueba', (
      tester,
      phone,
    ) async {
      await openFileScreen(tester, phone);
      exchange.readBack = (w) => Uint8List.fromList(w.reversed.toList());
      await tester.tap(saveButton);
      await settle(tester);
      expect(
        find.text('No se ha podido comprobar lo guardado'),
        findsOneWidget,
      );
      expect(fake.calls, isNot(contains('confirm')));
      expect(haptics.levels, contains(HapticLevel.error));
    });

    fileTest('compartir no comprueba el código y dice que es personal', (
      tester,
      phone,
    ) async {
      await openFileScreen(tester, phone);
      await tester.tap(find.text('Compartir'));
      await settle(tester);
      expect(exchange.shared, hasLength(1));
      expect(exchange.sharedTexts.single, contains('Es personal'));
      expect(exchange.sharedTexts.single, contains('no lo reenvíes'));
      expect(fake.calls, isNot(contains('confirm')));
      expect(find.text('Fichero guardado'), findsNothing);
    });

    fileTest('la contraseña es opcional: campos ocultos y motivo en vivo', (
      tester,
      phone,
    ) async {
      await openFileScreen(tester, phone);
      await tester.tap(find.text('Proteger con contraseña'));
      await settle(tester);
      expect(find.byType(TextField), findsNWidgets(2));
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.obscureText, isTrue);
        expect(field.autocorrect, isFalse);
        expect(field.enableSuggestions, isFalse);
        expect(field.enableIMEPersonalizedLearning, isFalse);
        expect(field.smartDashesType, SmartDashesType.disabled);
        expect(field.smartQuotesType, SmartQuotesType.disabled);
        expect(field.autofillHints, contains(AutofillHints.newPassword));
      }
      expect(find.textContaining('Mínimo 15 caracteres'), findsOneWidget);
      expect(find.textContaining('elegidas al azar'), findsOneWidget);
      expect(
        find.textContaining('Las 24 palabras seguirán valiendo'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

      await typeIn(tester, 0, 'corta');
      expect(find.text('Es muy corta: mínimo 15 caracteres.'), findsOneWidget);
      await typeIn(tester, 0, '1234567890123456');
      expect(find.text('No puede ser solo números.'), findsOneWidget);
      await typeIn(tester, 0, _good);
      expect(find.textContaining('Es muy corta'), findsNothing);
      await typeIn(tester, 1, 'otra distinta');
      expect(find.text('Las dos contraseñas no coinciden.'), findsOneWidget);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      await typeIn(tester, 1, _good);
      expect(find.text('Las dos contraseñas no coinciden.'), findsNothing);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
      // Quitar la casilla vuelve a la variante abierta y vacía los campos.
      await tester.tap(find.text('Proteger con contraseña'));
      await settle(tester);
      expect(find.byType(TextField), findsNothing);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    });

    fileTest('la derivación enseña su progreso y se puede cancelar', (
      tester,
      phone,
    ) async {
      await openFileScreen(tester, phone);
      slow.gate = Completer<void>();
      await tester.tap(find.text('Proteger con contraseña'));
      await settle(tester);
      await typeIn(tester, 0, _good);
      await typeIn(tester, 1, _good);
      await tester.tap(saveButton);
      await spin(tester);
      expect(find.text('Protegiendo el fichero…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(saveButton, findsNothing);
      await tester.tap(find.text('Cancelar'));
      await spin(tester, 10);
      expect(slow.cancels, 1);
      expect(find.text('Protegiendo el fichero…'), findsNothing);
      expect(find.textContaining('No se ha podido'), findsNothing);
      expect(exchange.saved, isEmpty);

      // Otra vez, ahora hasta el final.
      slow.gate = Completer<void>();
      await tester.tap(saveButton);
      await spin(tester);
      expect(find.text('Protegiendo el fichero…'), findsOneWidget);
      slow.gate!.complete();
      await settle(tester);
      expect(exchange.saved, hasLength(1));
      expect(find.text('Fichero guardado'), findsOneWidget);
    });
  });

  group('móvil pequeño con la letra al máximo', () {
    fileTest(
      'tras guardar, el pie es un solo botón y lo demás se desplaza',
      (tester, phone) async {
        await openFileScreen(tester, phone);
        await tester.tap(saveButton);
        await settle(tester);
        expect(find.text('Fichero guardado'), findsOneWidget);
        final footer = find.widgetWithText(FilledButton, 'Continuar');
        expect(footer, findsOneWidget);
        expect(tester.getRect(footer).bottom, lessThanOrEqualTo(640));
        // Las otras dos acciones se alcanzan desplazando el cuerpo.
        final again = find.text('Guardar otra copia');
        await tester.ensureVisible(again);
        await tester.pump();
        await tester.tap(again);
        await settle(tester);
        expect(exchange.saved, hasLength(2));
        await tester.ensureVisible(find.text('Compartir'));
        expect(tester.takeException(), isNull);
      },
      size: const Size(360, 640),
      textScale: 2,
    );

    fileTest(
      'con contraseña y derivando, «Cancelar» sigue a la vista',
      (tester, phone) async {
        await openFileScreen(tester, phone);
        slow.gate = Completer<void>();
        final protect = find.text('Proteger con contraseña');
        await tester.ensureVisible(protect);
        await tester.pump();
        await tester.tap(protect);
        await settle(tester);
        await typeIn(tester, 0, _good);
        await typeIn(tester, 1, _good);
        // El botón de ver mide al menos 48.
        expect(
          tester.getSize(find.widgetWithText(TextButton, 'Ver').first).height,
          greaterThanOrEqualTo(48),
        );
        await tester.tap(saveButton);
        await spin(tester);
        final cancel = find.text('Cancelar');
        expect(cancel, findsOneWidget);
        expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(640));
        expect(tester.takeException(), isNull);
        await tester.tap(cancel);
        await spin(tester, 6);
        expect(slow.cancels, 1);
      },
      size: const Size(360, 640),
      textScale: 2,
    );
  });

  group('segunda ronda de revisión', () {
    Future<void> untilCount(
      WidgetTester tester,
      int Function() count,
      int n,
    ) async {
      for (var i = 0; i < 600 && count() < n; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> toConfirm(WidgetTester tester, FakePhone phone) async {
      await pumpRegalos(tester, phone);
      phone.container.read(routerProvider).go(AppRoutes.recoverFile);
      await settle(tester);
      exchange.picked = vectors.open;
      await tapText(tester, 'Elegir fichero');
      expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
    }

    fileTest('un segundo fichero espera mientras se restaura y se descarta '
        'si la restauración acaba bien', (tester, phone) async {
      await toConfirm(tester, phone);
      fake.holdRestore = Completer<void>();
      await tester.tap(find.widgetWithText(FilledButton, 'Recuperar la lista'));
      await spin(tester);
      final flow = phone.container.read(recoveryFileProvider.notifier);
      await tester.runAsync(() => flow.receive(vectors.open));
      await spin(tester);
      expect(phone.container.read(recoveryFileProvider).waiting, isNotNull);
      expect(find.text('Ha llegado otro fichero'), findsNothing);
      expect(fake.calls, contains('file'));
      fake.holdRestore!.complete();
      await spin(tester, 10);
      expect(find.text('Lista recuperada'), findsOneWidget);
      expect(find.text('Ha llegado otro fichero'), findsNothing);
      expect(phone.container.read(recoveryFileProvider).waiting, isNull);
    });

    fileTest('si la restauración falla, se ofrece cambiar al que esperaba', (
      tester,
      phone,
    ) async {
      await toConfirm(tester, phone);
      fake.holdRestore = Completer<void>();
      fake.restoreError = const RecoveryApplicationException('not_found');
      await tester.tap(find.widgetWithText(FilledButton, 'Recuperar la lista'));
      await spin(tester);
      final flow = phone.container.read(recoveryFileProvider.notifier);
      await tester.runAsync(() => flow.receive(vectors.open));
      await spin(tester);
      expect(find.text('Ha llegado otro fichero'), findsNothing);
      fake.holdRestore!.complete();
      await spin(tester, 10);
      expect(find.text('Ese código no abre ninguna lista'), findsOneWidget);
      expect(find.text('Ha llegado otro fichero'), findsOneWidget);
      // Aceptar el nuevo sale del error del anterior y lo adopta.
      await tapText(tester, 'Cambiar de fichero');
      await spin(tester, 6);
      expect(find.text('Ese código no abre ninguna lista'), findsNothing);
      expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
      expect(
        phone.container.read(recoveryFileProvider).selection?.opened,
        isTrue,
      );
    });

    fileTest('aceptar otro fichero mientras se abandona el fallido deja mandar '
        'al último', (tester, phone) async {
      await toConfirm(tester, phone);
      fake.restoreError = const RecoveryApplicationException('not_found');
      await tapText(tester, 'Recuperar la lista');
      await spin(tester, 6);
      expect(find.text('Ese código no abre ninguna lista'), findsOneWidget);
      // Queda una recuperación a medias: abandonarla tarda.
      fake.push(
        const RecoveryStatus(
          RecoveryReadiness.needsAttention,
          phase: RecoveryPhase.needsAttention,
          cause: 'not_found',
        ),
      );
      fake.holdAbandon = Completer<void>();
      final flow = phone.container.read(recoveryFileProvider.notifier);
      // B es un fichero roto; C, uno protegido.
      await tester.runAsync(
        () => flow.receive(Uint8List.fromList(List<int>.filled(9, 1))),
      );
      await spin(tester, 8);
      await tester.tap(find.text('Cambiar de fichero'));
      await settle(tester);
      await tester.runAsync(() => flow.receive(vectors.protectedAscii));
      await spin(tester, 8);
      await tester.tap(find.text('Cambiar de fichero'));
      await settle(tester);
      // Las dos adopciones esperan al abandono; la última es la del fichero
      // actual.
      expect(
        phone.container.read(recoveryFileProvider).selection?.variant,
        RecoveryFileVariant.protected,
      );
      expect(fake.calls.where((c) => c == 'abandon'), hasLength(2));
      fake.holdAbandon!.complete();
      await spin(tester, 10);
      // C sigue siendo el fichero actual y pide su contraseña; B no lo soltó.
      expect(find.text('Contraseña del fichero'), findsOneWidget);
      expect(find.text('No es un fichero de recuperación'), findsNothing);
      final state = phone.container.read(recoveryFileProvider);
      expect(state.selection?.variant, RecoveryFileVariant.protected);
      expect(fake.calls.where((c) => c == 'file'), hasLength(1));
    });

    fileTest('un tercer fichero protegido no hereda la apertura pendiente del '
        'segundo', (tester, phone) async {
      await pumpRegalos(tester, phone);
      final flow = phone.container.read(recoveryFileProvider.notifier);
      await tester.runAsync(() => flow.receive(vectors.protectedAscii));
      await settle(tester);
      await tester.enterText(find.byType(TextField), vectors.asciiPassword);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Abrir el fichero'));
      await spin(tester, 2);
      // B (abierto) se acepta mientras deriva A: su apertura queda pendiente.
      await tester.runAsync(() => flow.receive(vectors.open));
      await spin(tester, 2);
      await tester.tap(find.text('Cambiar de fichero'));
      await spin(tester, 2);
      // C (protegido) sustituye a B antes de que acabe A.
      await tester.runAsync(() => flow.receive(vectors.protectedAscii));
      await spin(tester, 10);
      expect(find.text('Ha llegado otro fichero'), findsOneWidget);
      await tester.tap(find.text('Cambiar de fichero'));
      await spin(tester, 2);
      // Tiempo de sobra para que acabe la derivación de A y se vea si algo se
      // abre solo con la contraseña vacía.
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await spin(tester, 4);
      expect(find.text('Contraseña del fichero'), findsOneWidget);
      expect(find.text('Contraseña incorrecta o fichero dañado'), findsNothing);
      expect(find.text('¿Recuperar con este fichero?'), findsNothing);
      final state = phone.container.read(recoveryFileProvider);
      expect(state.activity, RecoveryFileActivity.idle);
      expect(state.selection?.opened, isFalse);
    });

    fileTest('aceptar un fichero abierto mientras se deriva el protegido lo '
        'abre en cuanto acaba el anterior', (tester, phone) async {
      await pumpRegalos(tester, phone);
      final flow = phone.container.read(recoveryFileProvider.notifier);
      await tester.runAsync(() => flow.receive(vectors.protectedAscii));
      await settle(tester);
      await tester.enterText(find.byType(TextField), vectors.asciiPassword);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Abrir el fichero'));
      await spin(tester, 2);
      expect(find.text('Protegiendo el fichero…'), findsOneWidget);
      await tester.runAsync(() => flow.receive(vectors.open));
      await spin(tester, 2);
      expect(find.text('Ha llegado otro fichero'), findsOneWidget);
      await tester.tap(find.text('Cambiar de fichero'));
      await spin(tester, 2);
      // El protegido acaba (o se cancela) y entonces se abre el nuevo.
      for (var i = 0; i < 600; i++) {
        if (find.text('¿Recuperar con este fichero?').evaluate().isNotEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await spin(tester, 4);
      expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
      expect(fake.calls, isEmpty);
    });

    fileTest('cada exportación protegida lleva su propia sal y nonce', (
      tester,
      phone,
    ) async {
      await openFileScreen(tester, phone);
      slow.real = true;
      final protect = find.text('Proteger con contraseña');
      await tester.ensureVisible(protect);
      await tester.pump();
      await tester.tap(protect);
      await settle(tester);
      await typeIn(tester, 0, _good);
      await typeIn(tester, 1, _good);
      await tester.tap(saveButton);
      await untilCount(tester, () => exchange.saved.length, 1);
      await spin(tester, 4);
      final again = find.text('Guardar otra copia');
      await tester.ensureVisible(again);
      await tester.pump();
      await tester.tap(again);
      await untilCount(tester, () => exchange.saved.length, 2);
      await spin(tester, 4);
      expect(exchange.saved, hasLength(2));
      // GHK: magia(4) + largo(2) + cabecera (con la sal) + nonce(12) + ...
      List<int> header(Uint8List b) => b.sublist(6, 6 + ((b[4] << 8) | b[5]));
      List<int> nonce(Uint8List b) {
        final end = 6 + ((b[4] << 8) | b[5]);
        return b.sublist(end, end + 12);
      }

      expect(header(exchange.saved[0]), isNot(header(exchange.saved[1])));
      expect(nonce(exchange.saved[0]), isNot(nonce(exchange.saved[1])));
      expect(exchange.saved[0], isNot(exchange.saved[1]));
    });

    fileTest('si la normalización NFC falla, lo dice y no deja guardar', (
      tester,
      phone,
    ) async {
      await openFileScreen(tester, phone);
      final protect = find.text('Proteger con contraseña');
      await tester.ensureVisible(protect);
      await tester.pump();
      await tester.tap(protect);
      await settle(tester);
      exchange.normalizeError = const DocumentPickerException(
        DocumentPickerFailure.unavailable,
      );
      await typeIn(tester, 0, _good);
      expect(
        find.text('Este móvil no puede abrir el selector de ficheros'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    });
  });

  group('persona cambiada', () {
    fileTest('guardar cuando cambió la persona lo dice y no comprueba', (
      tester,
      phone,
    ) async {
      await openFileScreen(tester, phone);
      fake.confirmError = const RecoveryApplicationException('person_changed');
      await tester.tap(saveButton);
      await settle(tester);
      expect(
        find.text('Este código ya no es el de tu persona actual'),
        findsOneWidget,
      );
      expect(find.textContaining('Crea un código nuevo'), findsOneWidget);
      expect(find.text('Fichero guardado'), findsNothing);
    });

    fileTest('comprobar un fichero con la persona cambiada lo dice', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      fake.possessionError = const RecoveryApplicationException(
        'person_changed',
      );
      await tapText(tester, 'Comprobar un fichero');
      exchange.picked = vectors.open;
      await tapText(tester, 'Elegir fichero');
      expect(
        find.text('Este código ya no es el de tu persona actual'),
        findsOneWidget,
      );
      expect(find.text('Código comprobado'), findsNothing);
    }, initial: const RecoveryStatus(RecoveryReadiness.confirmationPending));
  });

  group('comprobar un fichero', () {
    fileTest('un fichero que abre el código lo deja comprobado', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      expect(find.text('Falta comprobar el código'), findsOneWidget);
      await tapText(tester, 'Comprobar un fichero');
      expect(
        find.textContaining('No se guarda ni se envía nada'),
        findsOneWidget,
      );
      exchange.picked = vectors.open;
      await tapText(tester, 'Elegir fichero');
      expect(fake.calls, contains('possession'));
      expect(find.text('Código comprobado'), findsOneWidget);
      await tapText(tester, 'Listo');
      expect(find.text('Código preparado'), findsOneWidget);
    }, initial: const RecoveryStatus(RecoveryReadiness.confirmationPending));

    fileTest('un fichero protegido pide la contraseña antes de nada', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      await tapText(tester, 'Comprobar un fichero');
      exchange.picked = vectors.protectedAscii;
      await tapText(tester, 'Elegir fichero');
      expect(find.text('Contraseña del fichero'), findsOneWidget);
      expect(fake.calls, isNot(contains('possession')));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
      expect(field.autofillHints, contains(AutofillHints.password));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Abrir el fichero'),
            )
            .onPressed,
        isNull,
      );
      await tapText(tester, 'Elegir otro fichero');
      expect(find.text('Elegir fichero'), findsOneWidget);
    }, initial: const RecoveryStatus(RecoveryReadiness.confirmationPending));

    fileTest('lo que no es un fichero de recuperación se dice', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      await tapText(tester, 'Comprobar un fichero');
      exchange.picked = Uint8List.fromList(List<int>.filled(12, 7));
      await tapText(tester, 'Elegir fichero');
      expect(find.text('No es un fichero de recuperación'), findsOneWidget);
      expect(fake.calls, isNot(contains('possession')));
    }, initial: const RecoveryStatus(RecoveryReadiness.confirmationPending));

    fileTest('un fichero de otro código lo dice', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      fake.possessionError = const RecoveryApplicationException(
        'not_current_code',
      );
      await tapText(tester, 'Comprobar un fichero');
      exchange.picked = vectors.open;
      await tapText(tester, 'Elegir fichero');
      expect(find.text('Este fichero es de otro código'), findsOneWidget);
      expect(find.text('Código comprobado'), findsNothing);
    }, initial: const RecoveryStatus(RecoveryReadiness.confirmationPending));
  });

  group('recuperar con fichero', () {
    Future<void> openFromWelcome(WidgetTester tester) async {
      final button = find.text('Recuperar con fichero');
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await settle(tester);
    }

    fileTest('la bienvenida lo ofrece junto al código de palabras', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      expect(find.text('Tengo un código de recuperación'), findsOneWidget);
      expect(find.text('Recuperar con fichero'), findsOneWidget);
      await openFromWelcome(tester);
      expect(find.text('Recuperar con un fichero'), findsOneWidget);
      await tapLabel(tester, 'Atrás');
      expect(find.text('Recuperar con fichero'), findsOneWidget);
    });

    fileTest('el fichero abierto pide confirmación y recupera como las '
        'palabras', (tester, phone) async {
      await pumpRegalos(tester, phone);
      await openFromWelcome(tester);
      exchange.picked = vectors.open;
      await tapText(tester, 'Elegir fichero');
      expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
      expect(fake.calls, isNot(contains('file')));
      fake.holdRestore = Completer<void>();
      await tester.tap(find.widgetWithText(FilledButton, 'Recuperar la lista'));
      await spin(tester);
      expect(find.text('Recuperando la lista'), findsOneWidget);
      expect(find.text('Buscando la copia'), findsOneWidget);
      expect(fake.calls, contains('file'));
      fake.holdRestore!.complete();
      await spin(tester, 10);
      expect(find.text('Lista recuperada'), findsOneWidget);
      expect(haptics.levels, contains(HapticLevel.success));
    });

    fileTest('un error de la recuperación deja elegir otro fichero', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      await openFromWelcome(tester);
      exchange.picked = vectors.open;
      await tapText(tester, 'Elegir fichero');
      fake.restoreError = const RecoveryApplicationException('not_found');
      await tapText(tester, 'Recuperar la lista');
      await spin(tester, 6);
      expect(find.text('Ese código no abre ninguna lista'), findsOneWidget);
      await tapText(tester, 'Elegir otro fichero');
      expect(find.text('Recuperar con un fichero'), findsOneWidget);
    });

    fileTest('el fichero protegido pide la contraseña y no deriva sin ella', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      await openFromWelcome(tester);
      exchange.picked = vectors.protectedAscii;
      await tapText(tester, 'Elegir fichero');
      expect(find.text('Contraseña del fichero'), findsOneWidget);
      expect(
        find.textContaining('Escribe la contraseña que pusiste'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Abrir el fichero'),
            )
            .onPressed,
        isNull,
      );
      expect(fake.calls, isEmpty);
    });

    /// Espera (en tiempo real) a que la derivación de Argon2 acabe y se vea
    /// [text].
    Future<void> untilText(WidgetTester tester, String text) async {
      for (var i = 0; i < 600; i++) {
        if (find.text(text).evaluate().isNotEmpty) return;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    fileTest('la contraseña real abre el fichero con progreso y Cancelar; una '
        'errónea lo dice sin perder el campo', (tester, phone) async {
      await pumpRegalos(tester, phone);
      await openFromWelcome(tester);
      exchange.picked = vectors.protectedAscii;
      await tapText(tester, 'Elegir fichero');
      await tester.enterText(find.byType(TextField), 'contraseña equivocada');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Abrir el fichero'));
      await spin(tester, 2);
      expect(find.text('Protegiendo el fichero…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      await untilText(tester, 'Contraseña incorrecta o fichero dañado');
      await spin(tester, 4);
      expect(
        find.text('Contraseña incorrecta o fichero dañado'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(haptics.levels, contains(HapticLevel.error));
      // Con la buena, a la confirmación; nada se envía hasta pulsar.
      await tester.enterText(find.byType(TextField), vectors.asciiPassword);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Abrir el fichero'));
      await untilText(tester, '¿Recuperar con este fichero?');
      await spin(tester, 6);
      expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
      expect(fake.calls, isEmpty);
    });

    fileTest('no es un fichero de recuperación', (tester, phone) async {
      await pumpRegalos(tester, phone);
      await openFromWelcome(tester);
      exchange.picked = Uint8List.fromList(List<int>.filled(12, 9));
      await tapText(tester, 'Elegir fichero');
      expect(find.text('No es un fichero de recuperación'), findsOneWidget);
      expect(find.text('Elegir fichero'), findsOneWidget);
    });

    fileTest('un móvil con lista solo avisa de que el fichero es para uno '
        'vacío', (tester, phone) async {
      await pumpRegalos(tester, phone);
      await openFromWelcome(tester);
      hasFamily = true;
      exchange.picked = vectors.open;
      await tapText(tester, 'Elegir fichero');
      expect(find.text('Este móvil ya tiene una lista'), findsOneWidget);
      expect(fake.calls, isEmpty);
    });

    fileTest('abrir un fichero con la app lleva a la contraseña', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      final flow = phone.container.read(recoveryFileProvider.notifier);
      await tester.runAsync(() => flow.receive(vectors.protectedAscii));
      await settle(tester);
      expect(find.text('Contraseña del fichero'), findsOneWidget);
      expect(
        find.text('Has abierto un fichero de recuperación.'),
        findsOneWidget,
      );
      expect(fake.calls, isEmpty);
    });

    fileTest('un fichero abierto con la app, sin contraseña, pide '
        'confirmación', (tester, phone) async {
      await pumpRegalos(tester, phone);
      final flow = phone.container.read(recoveryFileProvider.notifier);
      await tester.runAsync(() => flow.receive(vectors.open));
      await settle(tester);
      expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
      expect(fake.calls, isEmpty);
    });

    fileTest('un fichero roto o un móvil con lista solo avisan', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      final flow = phone.container.read(recoveryFileProvider.notifier);
      await tester.runAsync(
        () => flow.receive(Uint8List.fromList(List<int>.filled(9, 1))),
      );
      await settle(tester);
      expect(find.text('No es un fichero de recuperación'), findsOneWidget);
      expect(phone.container.read(recoveryFileProvider).selection, isNull);
      await tapText(tester, 'Cerrar');

      hasFamily = true;
      await tester.runAsync(() => flow.receive(vectors.open));
      await settle(tester);
      expect(find.text('Este móvil ya tiene una lista'), findsOneWidget);
      expect(find.text('¿Recuperar con este fichero?'), findsNothing);
      expect(phone.container.read(recoveryFileProvider).selection, isNull);
      await tapText(tester, 'Cerrar');
    });

    fileTest('otro fichero mientras se usa uno pregunta antes de cambiar', (
      tester,
      phone,
    ) async {
      await pumpRegalos(tester, phone);
      final flow = phone.container.read(recoveryFileProvider.notifier);
      await tester.runAsync(() => flow.receive(vectors.protectedAscii));
      await settle(tester);
      await tester.runAsync(() => flow.receive(vectors.open));
      await settle(tester);
      expect(find.text('Ha llegado otro fichero'), findsOneWidget);
      // Seguir con el actual: nada cambia.
      await tapText(tester, 'Seguir con el actual');
      expect(find.text('Contraseña del fichero'), findsOneWidget);
      await tester.runAsync(() => flow.receive(vectors.open));
      await settle(tester);
      await tapText(tester, 'Cambiar de fichero');
      expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
    });
  });

  group('cambiar el código', () {
    fileTest('avisa de que los ficheros y las palabras anteriores dejan de '
        'servir', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openRecoveryRow(tester);
      expect(
        find.text('Los ficheros y las palabras anteriores dejarán de servir.'),
        findsOneWidget,
      );
      await tapText(tester, 'Cambiar el código');
      expect(
        find.textContaining(
          'los ficheros y las palabras anteriores dejarán de servir',
        ),
        findsOneWidget,
      );
    }, initial: const RecoveryStatus(RecoveryReadiness.prepared));
  });

  group('catalán con la letra al máximo', () {
    Future<void> pumpCa(WidgetTester tester, Widget Function() screen) async {
      haptics = FakeHaptics();
      exchange = FakeDocumentExchange();
      slow = SlowFileController();
      hasFamily = false;
      display = (await tester.runAsync(sampleRecoveryDisplay))!;
      fake = FakeRecovery(display: display);
      final scope = await scopeWith(const SizedBox());
      await pumpThemed(
        tester,
        ProviderScope(
          overrides: [..._overrides(), ...scope.overrides],
          child: screen(),
        ),
        locale: const Locale('ca'),
        textScale: 2,
      );
      await settle(tester);
    }

    testWidgets('guardar en un fitxer cap sense desbordar', (tester) async {
      await pumpCa(tester, () => RecoveryFileSaveScreen(display: display));
      final protect = find.text('Protegeix amb contrasenya');
      expect(protect, findsOneWidget);
      await tester.ensureVisible(protect);
      await tester.pump();
      await tester.tap(protect);
      await settle(tester);
      await typeIn(tester, 0, 'abc');
      await typeIn(tester, 1, 'abd');
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('contrasenya'), findsWidgets);
    });

    testWidgets('recuperar amb un fitxer cap sense desbordar', (tester) async {
      await pumpCa(tester, () => const RecoveryRestoreScreen(fileMode: true));
      exchange.picked = Uint8List.fromList(List<int>.filled(12, 9));
      await tester.tap(find.text('Tria un fitxer'));
      await settle(tester);
      expect(find.text('No és un fitxer de recuperació'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
