// El fichero de recuperación en la interfaz (ADR 0008): guardar y compartir
// desde las palabras, la contraseña opcional, «Comprobar un fichero»,
// «Recuperar con fichero» desde la bienvenida y los ficheros que llegan desde
// Archivos. La capa de aplicación del código va falseada
// (`helpers/fake_recovery.dart`) y la plataforma también
// (`helpers/fake_document_exchange.dart`); el formato y el flujo real los
// prueban `test/sync`.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/storage_providers.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/app/root_navigator.dart';
import 'package:regalos/core/motion/haptics.dart';
import 'package:regalos/core/platform/document_exchange.dart';
import 'package:regalos/core/platform/document_exchange_native.dart';
import 'package:regalos/features/sharing/application/incoming_share.dart';
import 'package:regalos/features/recovery/application/recovery_hold.dart';
import 'package:regalos/features/recovery/presentation/recovery_file_save_screen.dart';
import 'package:regalos/features/recovery/presentation/recovery_file_listener.dart';
import 'package:regalos/features/recovery/presentation/recovery_file_parts.dart';
import 'package:regalos/features/recovery/presentation/recovery_restore_screen.dart';
import 'package:regalos/features/sync/application/recovery_file_flow.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fake_document_exchange.dart';
import '../helpers/fake_haptics.dart';
import '../helpers/fake_recovery.dart';
import '../helpers/memory_stores.dart' show FakePhone;
import '../helpers/pump_app.dart';
import '../helpers/screens.dart';
import 'recovery_ui_test.dart' show openRecoveryRow, spin;

late FakeRecovery fake;
late FakeDocumentExchange exchange;
NativeDocumentExchange? initialExchange;
late FakeHaptics haptics;
late RecoveryCodeDisplay display;
late SlowFileController slow;
bool hasFamily = false;
late Completer<FamilyState> familyLoad;
late Completer<Uint8List> openingKey;

class ControlledFamilyController extends FamilyController {
  @override
  Future<FamilyState> build() => familyLoad.future;
}

class UnreadableFamilyStore extends FamilyStore {
  UnreadableFamilyStore({
    required super.secrets,
    required super.files,
    required super.deviceKeys,
  });

  bool? family;
  int reads = 0;

  @override
  Future<bool> hasFamily() async {
    reads++;
    final result = family;
    if (result == null) {
      throw const FamilyStoreException('test storage failure');
    }
    return result;
  }
}

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

List<Override> _overrides({
  bool controlledFamily = false,
  bool unreadableFamily = false,
  bool holdOpening = false,
}) => [
  if (controlledFamily)
    familyControllerProvider.overrideWith(ControlledFamilyController.new),
  recoveryApplicationProvider.overrideWith(() => fake),
  hapticsProvider.overrideWith((ref) => haptics),
  documentExchangeProvider.overrideWith((ref) => initialExchange ?? exchange),
  if (unreadableFamily)
    familyStoreProvider.overrideWith(
      (ref) => UnreadableFamilyStore(
        secrets: ref.watch(secretStoreProvider),
        files: ref.watch(fileStoreProvider),
        deviceKeys: ref.watch(deviceKeysStoreProvider),
      ),
    )
  else
    recoveryFileHasFamilyProvider.overrideWith(
      (ref) =>
          () async => hasFamily,
    ),
  recoveryFileProvider.overrideWith(() => slow),
  if (holdOpening)
    recoveryFileDeriverProvider.overrideWithValue((_, _) => openingKey.future),
];

void fileTest(
  String description,
  Future<void> Function(WidgetTester tester, FakePhone phone) body, {
  RecoveryStatus initial = const RecoveryStatus(RecoveryReadiness.absent),
  bool family = false,
  bool controlledFamily = false,
  bool unreadableFamily = false,
  bool holdOpening = false,
  Size size = const Size(390, 844),
  double textScale = 1,
}) {
  screenTest(
    description,
    (tester, phone) async {
      haptics = FakeHaptics();
      exchange = FakeDocumentExchange();
      initialExchange = null;
      slow = SlowFileController();
      hasFamily = family;
      familyLoad = Completer<FamilyState>();
      openingKey = Completer<Uint8List>();
      display = (await tester.runAsync(sampleRecoveryDisplay))!;
      fake = FakeRecovery(initial: initial, display: display);
      await body(tester, phone);
    },
    size: size,
    textScale: textScale,
    overrides: _overrides(
      controlledFamily: controlledFamily,
      unreadableFamily: unreadableFamily,
      holdOpening: holdOpening,
    ),
  );
}

Future<FakePhone> _seededPhone(WidgetTester tester) async {
  final phone = FakePhone();
  addTearDown(phone.dispose);
  await seedSample(tester, phone);
  return phone;
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
    fileTest('Files retries when the navigator is absent on the first frame', (
      tester,
      phone,
    ) async {
      await familyState(tester, phone);
      await tester.runAsync(
        () => phone.container
            .read(recoveryFileProvider.notifier)
            .receive(vectors.protectedAscii),
      );
      final selection = phone.container.read(recoveryFileProvider).selection;
      final ready = ValueNotifier(false);
      addTearDown(ready.dispose);
      await pumpThemed(
        tester,
        UncontrolledProviderScope(
          container: phone.container,
          child: Builder(
            builder: (context) => MaterialApp.router(
              theme: Theme.of(context),
              locale: const Locale('es'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: phone.container.read(routerProvider),
              builder: (_, child) => RecoveryFileListener(
                navigatorKey: rootNavigatorKey,
                child: ValueListenableBuilder(
                  valueListenable: ready,
                  builder: (_, visible, _) =>
                      visible ? child! : const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(rootNavigatorKey.currentContext, isNull);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        phone.container.read(recoveryFileProvider).selection,
        same(selection),
      );
      // No provider event accompanies the navigator becoming available.
      ready.value = true;
      await settle(tester);
      expect(find.text('Contraseña del fichero'), findsOneWidget);
      expect(
        find.text('Has abierto un fichero de recuperación.'),
        findsOneWidget,
      );
      expect(fake.calls, isEmpty);
    });

    for (final loadedFamily in [false, true]) {
      fileTest('Files waits for controlled family load: $loadedFamily', (
        tester,
        phone,
      ) async {
        if (loadedFamily) {
          await tester.runAsync(
            () => phone.container
                .read(lockControllerProvider.notifier)
                .skipSetup(),
          );
        }
        final existing = loadedFamily
            ? await familyState(tester, await _seededPhone(tester))
            : FamilyState.noFamily();
        await tester.runAsync(
          () => phone.container
              .read(recoveryFileProvider.notifier)
              .receive(vectors.protectedAscii),
        );
        final selection = phone.container.read(recoveryFileProvider).selection;
        await pumpRegalos(tester, phone);
        expect(
          phone.container.read(familyControllerProvider).isLoading,
          isTrue,
        );
        expect(find.byType(RecoveryRestoreScreen), findsNothing);
        expect(
          phone.container.read(recoveryFileProvider).selection,
          same(selection),
        );
        familyLoad.complete(existing);
        await settle(tester);
        if (loadedFamily) {
          expect(find.text('Este móvil ya tiene una lista'), findsOneWidget);
          expect(find.byType(RecoveryRestoreScreen), findsNothing);
        } else {
          expect(find.text('Contraseña del fichero'), findsOneWidget);
          expect(
            phone.container.read(recoveryFileProvider).selection,
            same(selection),
          );
          final router = phone.container.read(routerProvider);
          expect(router.state.uri.path, AppRoutes.recoverFile);
          expect(find.byType(RecoveryRestoreScreen), findsOneWidget);
          // Repeated navigator/family signals must not add a second route.
          router.refresh();
          await settle(tester);
          await tapLabel(tester, 'Atrás');
          expect(find.byType(RecoveryRestoreScreen), findsNothing);
          expect(router.state.uri.path, AppRoutes.welcome);
        }
        expect(fake.calls, isEmpty);
      }, controlledFamily: true);
    }

    fileTest('Files queued before a recovery screen opens adopt the latest', (
      tester,
      phone,
    ) async {
      final flow = phone.container.read(recoveryFileProvider.notifier);
      await tester.runAsync(() => flow.receive(vectors.protectedAscii));
      await tester.runAsync(() => flow.receive(vectors.open));
      await pumpRegalos(tester, phone);
      familyLoad.complete(FamilyState.noFamily());
      await settle(tester);
      expect(find.text('Ha llegado otro fichero'), findsNothing);
      expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
      expect(
        phone.container.read(recoveryFileProvider).selection!.variant,
        RecoveryFileVariant.open,
      );
      expect(phone.container.read(recoveryFileProvider).waiting, isNull);
      expect(fake.calls, isEmpty);
    }, controlledFamily: true);

    for (final loadedFamily in [false, true]) {
      fileTest(
        'Files retry after both storage reads fail: family=$loadedFamily',
        (tester, phone) async {
          if (loadedFamily) {
            await tester.runAsync(
              () => phone.container
                  .read(lockControllerProvider.notifier)
                  .skipSetup(),
            );
          }
          final recovered = loadedFamily
              ? await familyState(tester, await _seededPhone(tester))
              : FamilyState.noFamily();
          await tester.runAsync(
            () => phone.container
                .read(recoveryFileProvider.notifier)
                .receive(vectors.protectedAscii),
          );
          final selection = phone.container
              .read(recoveryFileProvider)
              .selection;
          final store = phone.container.read(
            familyStoreProvider,
          ) as UnreadableFamilyStore;
          expect(store.reads, 1);
          expect(selection, isNotNull);
          expect(selection!.hasFamily, isNull);
          await pumpRegalos(tester, phone);
          familyLoad.completeError(
            const FamilyStoreException('test storage failure'),
          );
          await settle(tester);
          expect(
            find.text('No se ha podido leer la lista de este móvil'),
            findsOneWidget,
          );
          expect(find.byType(RecoveryRestoreScreen), findsNothing);
          expect(
            phone.container.read(recoveryFileProvider).selection,
            same(selection),
          );
          store.family = loadedFamily;
          familyLoad = Completer<FamilyState>();
          await tapText(tester, 'Reintentar');
          expect(
            phone.container.read(familyControllerProvider).isLoading,
            isTrue,
          );
          familyLoad.complete(recovered);
          await settle(tester);
          if (loadedFamily) {
            expect(find.text('Este móvil ya tiene una lista'), findsOneWidget);
            expect(find.byType(RecoveryRestoreScreen), findsNothing);
            expect(
              phone.container.read(recoveryFileProvider).selection,
              isNull,
            );
          } else {
            expect(find.text('Contraseña del fichero'), findsOneWidget);
            expect(
              phone.container.read(recoveryFileProvider).selection,
              same(selection),
            );
            expect(find.byType(RecoveryRestoreScreen), findsOneWidget);
            expect(
              phone.container.read(routerProvider).state.uri.path,
              AppRoutes.recoverFile,
            );
          }
          expect(fake.calls, isEmpty);
        },
        controlledFamily: true,
        unreadableFamily: true,
      );
    }

    for (final arrival in ['before runApp', 'onFile']) {
      for (final variant in [
        'protected',
        'open',
        'invalid',
        'garbage',
        'family',
      ]) {
        fileTest('Files channel $arrival: $variant', (tester, phone) async {
          final bytes = switch (variant) {
            'garbage' => Uint8List.fromList('hola'.codeUnits),
            'protected' => vectors.protectedAscii,
            'invalid' => Uint8List.fromList([0x47, 0x48, 0x4b, 1]),
            _ => vectors.open,
          };
          hasFamily = variant == 'family';
          final messenger = tester.binding.defaultBinaryMessenger;
          var initialRequests = 0;
          messenger.setMockMethodCallHandler(kIncomingChannel, (call) async {
            if (call.method != 'takeInitialFile') return null;
            initialRequests++;
            return arrival == 'before runApp' ? bytes : null;
          });
          addTearDown(
            () => messenger.setMockMethodCallHandler(kIncomingChannel, null),
          );
          final temp = Directory.systemTemp.createTempSync('gifthuddle-m1-');
          addTearDown(() => temp.deleteSync(recursive: true));
          initialExchange = NativeDocumentExchange(() async => temp);
          if (variant == 'family') await seedSample(tester, phone);
          phone.container.read(incomingShareProvider);
          if (arrival == 'onFile') {
            await pumpRegalos(tester, phone);
            await tester.runAsync(
              () => messenger.handlePlatformMessage(
                kIncomingChannel.name,
                const StandardMethodCodec().encodeMethodCall(
                  MethodCall('onFile', bytes),
                ),
                (_) {},
              ),
            );
          } else {
            await tester.runAsync(() => pumpEventQueue());
          }
          final state = phone.container.read(recoveryFileProvider);
          if (arrival == 'before runApp' && variant != 'garbage') {
            expect(state.selection, isNotNull);
          }
          expect(state.waiting, isNull);
          if (arrival == 'before runApp') {
            await pumpRegalos(tester, phone);
          } else {
            await settle(tester);
          }
          expect(initialRequests, 1);
          expect(
            find.text(switch (variant) {
              'protected' => 'Contraseña del fichero',
              'open' => '¿Recuperar con este fichero?',
              'garbage' => 'No se pudo abrir el envío',
              'invalid' => 'No es un fichero de recuperación',
              _ => 'Este móvil ya tiene una lista',
            }),
            findsOneWidget,
            reason:
                'route=${phone.container.read(routerProvider).routeInformationProvider.value.uri}; '
                'selection=${phone.container.read(recoveryFileProvider).selection}; '
                'waiting=${phone.container.read(recoveryFileProvider).waiting}',
          );
          expect(fake.calls, isEmpty);
          if (variant == 'garbage') {
            expect(
              find.text('Este fichero o texto no es un envío de Gift Huddle.'),
              findsOneWidget,
            );
          }
          expect(phone.container.read(incomingShareProvider), isNull);
          if (variant == 'family' ||
              variant == 'invalid' ||
              variant == 'garbage') {
            expect(
              phone.container.read(recoveryFileProvider).selection,
              isNull,
            );
            expect(find.byType(RecoveryRestoreScreen), findsNothing);
          } else {
            expect(find.byType(RecoveryRestoreScreen), findsOneWidget);
          }
        });
      }
    }

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

    Future<void> startFilesChannel(WidgetTester tester, FakePhone phone) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(kIncomingChannel, (call) async {
        if (call.method == 'normalizeNfc') return call.arguments;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(kIncomingChannel, null),
      );
      final temp = Directory.systemTemp.createTempSync('gifthuddle-back-');
      addTearDown(() => temp.deleteSync(recursive: true));
      initialExchange = NativeDocumentExchange(() async => temp);
      phone.container.read(incomingShareProvider);
      await pumpRegalos(tester, phone);
    }

    Future<void> onFile(
      WidgetTester tester,
      Uint8List bytes, {
      bool settleAfter = true,
    }) async {
      await tester.runAsync(
        () => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          kIncomingChannel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onFile', bytes),
          ),
          (_) {},
        ),
      );
      if (settleAfter) await settle(tester);
    }

    Future<void> confirmProtectedFile(WidgetTester tester) async {
      await onFile(tester, vectors.protectedAscii);
      expect(find.text('Contraseña del fichero'), findsOneWidget);
      await tester.enterText(find.byType(TextField), vectors.asciiPassword);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Abrir el fichero'));
      await untilText(tester, '¿Recuperar con este fichero?');
      await settle(tester);
      expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
    }

    for (final systemBack in [false, true]) {
      fileTest('onFile after protected confirmation and back '
          '(system=$systemBack) opens the new file', (tester, phone) async {
        await startFilesChannel(tester, phone);
        await confirmProtectedFile(tester);
        expect(
          phone.container.read(recoveryFileProvider).selection!.opened,
          isTrue,
        );
        if (systemBack) {
          await tester.binding.handlePopRoute();
          await settle(tester);
        } else {
          await tapLabel(tester, 'Atrás');
        }
        expect(find.byType(RecoveryRestoreScreen), findsNothing);
        expect(
          phone.container.read(routerProvider).state.uri.path,
          AppRoutes.welcome,
        );
        expect(phone.container.read(recoveryFileScreenOpenProvider), 0);
        expect(phone.container.read(recoveryFileProvider).selection, isNull);
        expect(phone.container.read(recoveryFileProvider).waiting, isNull);
        await onFile(tester, vectors.open);
        expect(find.text('Ha llegado otro fichero'), findsNothing);
        expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
        expect(phone.container.read(recoveryFileScreenOpenProvider), 1);
        expect(fake.calls, isEmpty);
      });
    }

    for (final deriving in [false, true]) {
      for (final systemBack in [false, true]) {
        fileTest('onFile after leaving the password step '
            '(deriving=$deriving, system=$systemBack) opens the new file', (
          tester,
          phone,
        ) async {
          await startFilesChannel(tester, phone);
          await onFile(tester, vectors.protectedAscii);
          if (deriving) {
            await tester.enterText(
              find.byType(TextField),
              vectors.asciiPassword,
            );
            await tester.pump();
            await tester.tap(
              find.widgetWithText(FilledButton, 'Abrir el fichero'),
            );
            await spin(tester, 2);
            expect(
              phone.container.read(recoveryFileProvider).activity,
              RecoveryFileActivity.deriving,
            );
          }
          if (systemBack) {
            await tester.binding.handlePopRoute();
            await settle(tester);
          } else {
            await tapLabel(tester, 'Atrás');
          }
          expect(find.byType(RecoveryRestoreScreen), findsNothing);
          expect(phone.container.read(recoveryFileScreenOpenProvider), 0);
          final cleared = phone.container.read(recoveryFileProvider);
          expect(cleared.selection, isNull);
          expect(cleared.waiting, isNull);
          expect(cleared.activity, RecoveryFileActivity.idle);
          await onFile(tester, vectors.open);
          expect(find.text('Ha llegado otro fichero'), findsNothing);
          expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
          final current = phone.container.read(recoveryFileProvider).selection;
          if (deriving) {
            openingKey.completeError(StateError('cancelled derivation ended'));
            await settle(tester);
            expect(
              phone.container.read(recoveryFileProvider).selection,
              same(current),
            );
            expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
          }
          expect(phone.container.read(recoveryFileScreenOpenProvider), 1);
          expect(fake.calls, isEmpty);
        }, holdOpening: true);
      }
    }

    fileTest('onFile during the back transition survives the old dispose', (
      tester,
      phone,
    ) async {
      await startFilesChannel(tester, phone);
      await confirmProtectedFile(tester);
      final oldScreen = tester.state(find.byType(RecoveryRestoreScreen));
      final hold = phone.container.read(recoveryHoldProvider);
      expect(hold.value, isTrue);
      await tester.tap(find.bySemanticsLabel('Atrás').first);
      await tester.pump();
      expect(phone.container.read(recoveryFileScreenOpenProvider), 0);
      await onFile(tester, vectors.open);
      expect(find.text('Ha llegado otro fichero'), findsNothing);
      expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
      expect(
        phone.container.read(recoveryFileProvider).selection!.opened,
        isTrue,
      );
      expect(phone.container.read(recoveryFileScreenOpenProvider), 1);
      expect(oldScreen.mounted, isFalse);
      expect(hold.value, isTrue);

      fake.holdRestore = Completer<void>();
      await tester.tap(find.widgetWithText(FilledButton, 'Recuperar la lista'));
      await spin(tester);
      await tester.runAsync(
        () => familyOf(phone).createFamily(deviceName: 'Móvil nuevo'),
      );
      await spin(tester, 12);
      expect(hold.value, isTrue);
      expect(find.text('Recuperando la lista'), findsOneWidget);
      expect(find.text('Crea un PIN'), findsNothing);
      fake.holdRestore!.complete();
      await settle(tester);
      expect(hold.value, isTrue);
      expect(find.text('Lista recuperada'), findsOneWidget);
      expect(find.text('Crea un PIN'), findsNothing);
      await tester.tap(find.text('Entrar en la lista'));
      await settle(tester);
      expect(hold.value, isFalse);
      expect(find.text('Crea un PIN'), findsOneWidget);
    });

    fileTest('two onFile arrivals during a pending push open one screen', (
      tester,
      phone,
    ) async {
      await startFilesChannel(tester, phone);
      await onFile(tester, vectors.open, settleAfter: false);
      // El listener pide el push al final del fotograma; la pantalla aún no
      // se ha montado ni ha incrementado su contador.
      await tester.pump();
      expect(phone.container.read(recoveryFileScreenOpenProvider), 0);
      await onFile(tester, vectors.protectedAscii, settleAfter: false);
      await settle(tester);
      expect(
        find.byType(RecoveryRestoreScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(phone.container.read(recoveryFileScreenOpenProvider), 1);
      expect(fake.calls, isEmpty);
      await tapLabel(tester, 'Atrás');
      expect(
        find.byType(RecoveryRestoreScreen, skipOffstage: false),
        findsNothing,
      );
      expect(phone.container.read(recoveryFileScreenOpenProvider), 0);
    });

    fileTest('onFile during protected confirmation keeps or switches the '
        'visible file', (tester, phone) async {
      await startFilesChannel(tester, phone);
      await confirmProtectedFile(tester);
      final current = phone.container.read(recoveryFileProvider).selection;
      await onFile(tester, vectors.open);
      expect(find.text('Ha llegado otro fichero'), findsOneWidget);
      await tapText(tester, 'Seguir con el actual');
      expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
      expect(
        phone.container.read(recoveryFileProvider).selection,
        same(current),
      );
      expect(phone.container.read(recoveryFileProvider).waiting, isNull);
      await onFile(tester, vectors.open);
      await tapText(tester, 'Cambiar de fichero');
      expect(find.text('¿Recuperar con este fichero?'), findsOneWidget);
      expect(
        phone.container.read(recoveryFileProvider).selection!.variant,
        RecoveryFileVariant.open,
      );
      expect(
        phone.container.read(recoveryFileProvider).selection!.opened,
        isTrue,
      );
      expect(phone.container.read(recoveryFileProvider).waiting, isNull);
      expect(phone.container.read(recoveryFileScreenOpenProvider), 1);
      expect(fake.calls, isEmpty);
    });

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
