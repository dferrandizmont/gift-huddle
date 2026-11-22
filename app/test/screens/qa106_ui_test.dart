// Arreglos de interfaz de la QA 1.0.6 (M2, m3, m5, m6, m7): la ficha de quien
// no debe ver sus regalos no se pinta normal ni un fotograma (también al
// girar), la tarjeta de Móviles dice que otro móvil está conectando, el
// nombre que se propone en «¿Quién eres?» nunca es el modelo del móvil y el
// QR de invitar y su código no se capturan en la versión de tienda.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/device/device_name.dart'
    show suggestedDeviceNameProvider;
import 'package:regalos/core/platform/gifts_secure_scope.dart';
import 'package:regalos/core/sync/family_doc.dart' show FamilyDoc;
import 'package:regalos/core/sync/protected_doc.dart' show AuthorizedProjection;
import 'package:regalos/core/widgets/budget_meter.dart';
import 'package:regalos/core/widgets/filter_pill.dart';
import 'package:regalos/core/widgets/secret_block.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/application/self_person_gate.dart';
import 'package:regalos/features/sharing/presentation/pairing_qr_view.dart';
import 'package:regalos/features/sync/presentation/person_picker.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';
import 'package:regalos/features/sync/presentation/code_card.dart';

import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart' show FakePhone;
import '../helpers/pump_app.dart' show pumpThemed;
import '../helpers/screens.dart';

class _WaitingSync extends SyncController {
  @override
  SyncStatus build() => const SyncStatus(SyncPhase.waitingForPeer);
}

class _HostDone extends PairingV2HostController {
  @override
  PairingV2HostState build() =>
      const PairingV2HostState(PairingV2HostPhase.done);
}

/// Cuántas veces se ha vuelto a pedir la proyección (como tras sincronizar).
class _Tick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final _tick = NotifierProvider<_Tick, int>(_Tick.new);

void main() {
  setUpAll(loadInter);

  group('m5: al recalcular la proyección se conserva lo último pintado', () {
    screenTest(
      'mientras recarga, lo que se pinta sigue siendo la última proyección',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        // La proyección de prueba se reconoce por el id de su lista.
        expect(
          phone.container.read(projectedFamilyDocProvider).listId,
          'proyectada',
        );
        // Sincronizar ahora: la proyección se vuelve a calcular y no acaba.
        phone.container.read(_tick.notifier).bump();
        await tester.pump();
        expect(
          phone.container.read(projectedFamilyDocProvider).listId,
          'proyectada',
        );
        expect(tester.takeException(), isNull);
      },
      overrides: [
        authorizedProjectionProvider.overrideWith((ref) async {
          final n = ref.watch(_tick);
          await ref.watch(familyControllerProvider.future);
          if (n > 0) return Completer<AuthorizedProjection?>().future;
          return AuthorizedProjection(
            secretGiftIds: const <String>{},
            lockedBlocks: const [],
            openedScopes: const {},
            policies: const {},
            doc: FamilyDoc.empty('proyectada'),
          );
        }),
      ],
    );
  });

  group('M2: la ficha de la propia persona no se pinta normal', () {
    screenTest(
      'con la proyección sin calcular, desde el primer fotograma y al girar '
      'solo está el bloque',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Aritz');
        void onlyTheBlock() {
          expect(find.byType(SecretBlockCard), findsOneWidget);
          expect(find.byType(BudgetMeter), findsNothing);
          expect(find.text('Sin regalos'), findsNothing);
          expect(find.byType(FilterPill), findsNothing);
        }

        onlyTheBlock();
        // Girar: cada fotograma, solo el bloque.
        tester.view.physicalSize = const Size(844, 390);
        await tester.pump();
        onlyTheBlock();
        await tester.pump(const Duration(milliseconds: 16));
        onlyTheBlock();
        await settle(tester);
        onlyTheBlock();
        tester.view.physicalSize = const Size(390, 844);
        await tester.pump();
        onlyTheBlock();
        await settle(tester);
        onlyTheBlock();
        expect(tester.takeException(), isNull);
      },
      overrides: [
        ownHiddenPeopleProvider.overrideWithValue({'aritz'}),
        // La proyección no acaba: la decisión de ocultar no depende de ella.
        authorizedProjectionProvider.overrideWith(
          (ref) => Completer<AuthorizedProjection?>().future,
        ),
      ],
    );
  });

  group('m3: «Conectando otro móvil» en vez de «Solo en este móvil»', () {
    Future<void> openDevices(WidgetTester tester, FakePhone phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.tap(find.text('Ajustes').last);
      await settle(tester);
      await tapText(tester, 'Móviles de la familia');
    }

    screenTest(
      'sin nadie conectando la tarjeta dice «Solo en este móvil»',
      (tester, phone) async {
        await openDevices(tester, phone);
        expect(find.text('Solo en este móvil'), findsOneWidget);
        expect(find.text('Conectando otro móvil'), findsNothing);
      },
      size: const Size(390, 1500),
      overrides: [syncControllerProvider.overrideWith(_WaitingSync.new)],
    );

    screenTest(
      'con acceso enviado y el invitado sin terminar, dice que lo espera',
      (tester, phone) async {
        await openDevices(tester, phone);
        expect(find.text('Conectando otro móvil'), findsOneWidget);
        expect(
          find.text('Esperando a que el otro móvil termine de conectarse.'),
          findsOneWidget,
        );
        expect(find.text('Solo en este móvil'), findsNothing);
      },
      size: const Size(390, 1500),
      overrides: [
        syncControllerProvider.overrideWith(_WaitingSync.new),
        pairingV2HostProvider.overrideWith(_HostDone.new),
      ],
    );
  });

  group('m6: el nombre que se propone nunca es el modelo del móvil', () {
    Future<SelfPersonGate> gate(WidgetTester tester, FakePhone phone) async {
      await seedSample(tester, phone);
      return (await tester.runAsync(() async {
        // El modelo se lee antes: el estado no lo espera.
        await phone.container.read(suggestedDeviceNameProvider.future);
        return phone.container.read(selfPersonGateProvider.future);
      }))!;
    }

    screenTest(
      'si el nombre guardado es el modelo, el campo queda vacío',
      (tester, phone) async {
        expect((await gate(tester, phone)).suggestedName, isEmpty);
      },
      overrides: [
        suggestedDeviceNameProvider.overrideWith(
          (ref) async => 'móvil de prueba',
        ),
      ],
    );

    screenTest(
      'si es un nombre escrito en la bienvenida, se propone ese',
      (tester, phone) async {
        expect((await gate(tester, phone)).suggestedName, 'Móvil de prueba');
      },
      overrides: [
        suggestedDeviceNameProvider.overrideWith(
          (ref) async => 'OnePlus KB2003',
        ),
      ],
    );
  });

  testWidgets('m6: la persona de este móvil lleva su nota y no sale elegida', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      PersonPicker(
        title: 'Título',
        body: 'Cuerpo',
        people: const [
          PairingV2Person('nora', 'Nora'),
          PairingV2Person('leo', 'Leo'),
        ],
        notOnListLabel: 'No está',
        nobodyLabel: 'Nadie',
        nameLabel: 'Nombre',
        onPerson: (_) {},
        onNew: (_, {required noGifts}) {},
        thisPhonePersonId: 'leo',
      ),
    );
    expect(find.text('Este móvil'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('person:leo')),
        matching: find.text('Este móvil'),
      ),
      findsOneWidget,
    );
    // No sale elegida: «Continuar» sigue apagado.
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('personPickerContinue')),
          )
          .onPressed,
      isNull,
    );
  });

  group('m7: el QR de invitar y su código no se capturan en la tienda', () {
    Future<void> inStore(WidgetTester tester, Widget child) async {
      debugGiftScreensSecure = true;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final calls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.dferrandizmont.regalos/incoming'),
          (call) async {
            if (call.method == 'setSecure') calls.add('${call.arguments}');
            return null;
          },
        );
        await pumpThemed(tester, Scaffold(body: Center(child: child)));
        await tester.pump();
        expect(calls, ['true']);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(calls, ['true', 'false']);
      } finally {
        debugGiftScreensSecure = null;
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('el QR', (tester) async {
      await inStore(
        tester,
        const PairingQrFrame(data: 'https://example.test/i#abc', side: 200),
      );
    });

    testWidgets('el código de verificación', (tester) async {
      await inStore(
        tester,
        const VerificationCodeCard(label: 'Código', code: '123456'),
      );
    });
  });
}
