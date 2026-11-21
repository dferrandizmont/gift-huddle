// La lista «Conectados» de Ajustes › Móviles de la familia: con la
// sincronización v2 sale del registro firmado (persona de cada móvil); en v1
// sigue siendo este móvil y, si está emparejado, el otro.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/sharing/presentation/share_screen.dart';
import 'package:regalos/features/sync/application/family_device_rows.dart';
import 'package:regalos/features/sync/application/family_devices.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';

import '../helpers/fake_sync_server.dart';
import '../sync/invite_approval_view_test.dart' show screenApp, phoneSize;
import '../sync/protected_harness.dart';
import '../sync/sync_harness.dart';

/// [load] como si fuera la lectura del registro v2 de este móvil.
Widget v2AppWith(
  ProviderContainer container,
  Future<List<FamilyDeviceRow>?> Function(Ref ref) load,
) => UncontrolledProviderScope(
  container: container,
  child: ProviderScope(
    overrides: [familyDeviceRowsProvider.overrideWith(load)],
    child: Builder(
      builder: (context) =>
          screenApp(ProviderScope.containerOf(context), const ShareScreen()),
    ),
  ),
);

/// Una sincronización que se quedó «a la espera del segundo móvil».
class _StillWaiting extends SyncController {
  @override
  SyncStatus build() => const SyncStatus(SyncPhase.waitingForPeer);
}

/// Como [v2App], con la sincronización a la espera del segundo móvil.
Widget v2AppWaiting(ProviderContainer container, List<FamilyDeviceRow> rows) =>
    v2AppWaitingWith(container, (ref) async => rows);

/// Como [v2AppWaiting], con la lectura del registro que se dé.
Widget v2AppWaitingWith(
  ProviderContainer container,
  Future<List<FamilyDeviceRow>?> Function(Ref ref) load,
) => UncontrolledProviderScope(
  container: container,
  child: ProviderScope(
    overrides: [
      familyDeviceRowsProvider.overrideWith(load),
      syncControllerProvider.overrideWith(_StillWaiting.new),
    ],
    child: Builder(
      builder: (context) =>
          screenApp(ProviderScope.containerOf(context), const ShareScreen()),
    ),
  ),
);

/// [rows] como si fueran los móviles del registro v2 de este móvil.
Widget v2App(ProviderContainer container, List<FamilyDeviceRow> rows) =>
    v2AppWith(container, (ref) async => rows);

/// Marca la familia de [a] como v2 (el protocolo se sabe por el documento).
Future<void> markV2(SyncPhone a) async {
  final doc = a.c.read(familyControllerProvider).value!.doc;
  final marked = doc.set(
    HlcClock(node: 'marca-v2'),
    Collections.meta,
    kProtocolRecordId,
    {kProtocolVersionField: kSyncProtocolV2},
  );
  await a.family.mergeRemote(marked, fromNode: 'marca-v2');
  expect(syncProtocolOf(a.c.read(familyControllerProvider).value!.doc), 2);
}

void main() {
  group('familyDeviceRows (registro firmado)', () {
    test(
      'este móvil primero, la persona de cada ficha y los demás por id',
      () async {
        final aritz = await Phone.create('aritz-phone', 'aritz', 1);
        final nora = await Phone.create('nora-phone', 'nora', 2);
        final leo = await Phone.create('leo-phone', null, 3);
        var registry = DeviceRegistry.empty(kListId);
        for (final p in [aritz, nora, leo]) {
          registry = await registry.withRecord(await p.record());
        }
        // Aritz creó la familia y avala a los otros dos.
        for (final p in [nora, leo]) {
          registry = await registry.withVouch(
            await Vouch.create(
              keys: aritz.keys,
              voucher: await aritz.record(),
              record: await p.record(),
            ),
          );
        }
        final view = await aritz.viewOf(registry);

        final rows = familyDeviceRows(view, selfName: ' Pixel de Aritz ');
        expect(rows.map((r) => r.deviceId), [
          'aritz-phone',
          'leo-phone',
          'nora-phone',
        ]);
        expect(rows.map((r) => r.isSelf), [true, false, false]);
        expect(rows.map((r) => r.personId), ['aritz', null, 'nora']);
        expect(rows.first.deviceName, 'Pixel de Aritz');
        expect(rows.last.deviceName, isNull);
      },
    );
  });

  group('Móviles de la familia, lista de conectados', () {
    testWidgets('v2 con dos móviles: sale el nombre de la persona del otro', (
      tester,
    ) async {
      phoneSize(tester);
      final server = FakeSyncServer();
      late SyncPhone a;
      await tester.runAsync(() async {
        a = await SyncPhone.create(server);
        await a.createFamily('Pixel de Aritz');
        for (final name in ['Aritz', 'Nora', 'Leo']) {
          await a.family.upsertRecipient(
            Recipient(
              id: name.toLowerCase(),
              name: name,
              colorIndex: 0,
              archived: false,
            ),
          );
        }
      });
      addTearDown(a.dispose);
      await tester.runAsync(() => markV2(a));
      await tester.pumpWidget(
        v2App(a.c, const [
          FamilyDeviceRow(
            deviceId: 'a',
            isSelf: true,
            personId: 'aritz',
            deviceName: 'Pixel de Aritz',
          ),
          FamilyDeviceRow(deviceId: 'n', isSelf: false, personId: 'nora'),
        ]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Aritz'), findsOneWidget);
      expect(find.text('Este móvil'), findsOneWidget);
      expect(find.text('Nora'), findsOneWidget);
      expect(find.text('Conectado a esta familia'), findsOneWidget);
      expect(find.text('Otro móvil'), findsNothing);
      expect(find.text('2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('v2 con un móvil sin persona: «Otro móvil» y su aviso', (
      tester,
    ) async {
      phoneSize(tester);
      final server = FakeSyncServer();
      late SyncPhone a;
      await tester.runAsync(() async {
        a = await SyncPhone.create(server);
        await a.createFamily('Pixel de Aritz');
      });
      addTearDown(a.dispose);
      await tester.runAsync(() => markV2(a));
      await tester.pumpWidget(
        v2App(a.c, const [
          FamilyDeviceRow(
            deviceId: 'a',
            isSelf: true,
            deviceName: 'Pixel de Aritz',
          ),
          FamilyDeviceRow(deviceId: 'x', isSelf: false),
        ]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      // Este móvil no tiene persona: sale el nombre del móvil.
      expect(find.text('Pixel de Aritz'), findsOneWidget);
      expect(find.text('Otro móvil'), findsOneWidget);
      expect(
        find.text('Sin persona: aún no ve las sorpresas'),
        findsOneWidget,
      );
      expect(find.text('Conectado a esta familia'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('v2 con tres móviles: el contador es el real', (tester) async {
      phoneSize(tester);
      final server = FakeSyncServer();
      late SyncPhone a;
      await tester.runAsync(() async {
        a = await SyncPhone.create(server);
        await a.createFamily('Pixel de Aritz');
        for (final name in ['Aritz', 'Nora', 'Leo']) {
          await a.family.upsertRecipient(
            Recipient(
              id: name.toLowerCase(),
              name: name,
              colorIndex: 0,
              archived: false,
            ),
          );
        }
      });
      addTearDown(a.dispose);
      await tester.runAsync(() => markV2(a));
      await tester.pumpWidget(
        v2App(a.c, const [
          FamilyDeviceRow(deviceId: 'a', isSelf: true, personId: 'aritz'),
          FamilyDeviceRow(deviceId: 'l', isSelf: false, personId: 'leo'),
          FamilyDeviceRow(deviceId: 'n', isSelf: false, personId: 'nora'),
        ]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Aritz'), findsOneWidget);
      expect(find.text('Leo'), findsOneWidget);
      expect(find.text('Nora'), findsOneWidget);
      expect(find.text('Conectado a esta familia'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('v2 mientras se lee el registro: solo este móvil, sin '
        '«Otro móvil» ni contador; al llegar, entra la fila', (tester) async {
      phoneSize(tester);
      final server = FakeSyncServer();
      late SyncPhone a;
      await tester.runAsync(() async {
        a = await SyncPhone.create(server);
        await a.createFamily('Pixel de Aritz');
        await a.family.markPaired(peerName: 'Móvil de Nora');
        await markV2(a);
      });
      addTearDown(a.dispose);
      final gate = Completer<List<FamilyDeviceRow>?>();
      await tester.pumpWidget(v2AppWith(a.c, (ref) => gate.future));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      // El familiar emparejado en v1 no se pinta: la familia es v2.
      expect(find.text('Pixel de Aritz'), findsOneWidget);
      expect(find.text('Este móvil'), findsOneWidget);
      expect(find.text('Móvil de Nora'), findsNothing);
      expect(find.text('Otro móvil'), findsNothing);
      expect(find.text('2'), findsNothing);
      expect(
        find.text('No se ha podido leer la lista de móviles.'),
        findsNothing,
      );
      gate.complete(const [
        FamilyDeviceRow(
          deviceId: 'a',
          isSelf: true,
          personId: 'aritz',
          deviceName: 'Pixel de Aritz',
        ),
        FamilyDeviceRow(deviceId: 'n', isSelf: false, personId: 'nora'),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Otro móvil'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('v2 si falla la lectura: este móvil y una línea de error, '
        'nunca la lista de v1', (tester) async {
      phoneSize(tester);
      final server = FakeSyncServer();
      late SyncPhone a;
      await tester.runAsync(() async {
        a = await SyncPhone.create(server);
        await a.createFamily('Pixel de Aritz');
        await a.family.markPaired(peerName: 'Móvil de Nora');
        await markV2(a);
      });
      addTearDown(a.dispose);
      await tester.pumpWidget(
        v2AppWith(a.c, (ref) async => throw StateError('registro ilegible')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Pixel de Aritz'), findsOneWidget);
      expect(find.text('Móvil de Nora'), findsNothing);
      expect(find.text('Otro móvil'), findsNothing);
      expect(find.text('2'), findsNothing);
      expect(
        find.text('No se ha podido leer la lista de móviles.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    for (final identityPaired in [true, false]) {
      testWidgets('v2 con dos móviles ya en la lista: la tarjeta no dice «Solo '
          'en este móvil» aunque la sincronización siga a la espera '
          '(identidad emparejada: $identityPaired)', (tester) async {
        phoneSize(tester);
        final server = FakeSyncServer();
        late SyncPhone a;
        await tester.runAsync(() async {
          a = await SyncPhone.create(server);
          await a.createFamily('Pixel de Aritz');
          await markV2(a);
          // Mezclar la marca v2 «de otro móvil» deja la identidad emparejada.
          if (identityPaired) {
            await a.family.markPaired(peerName: 'Móvil de Nora');
          } else {
            await a.family.markUnpaired();
          }
        });
        addTearDown(a.dispose);
        await tester.pumpWidget(
          v2AppWaiting(a.c, const [
            FamilyDeviceRow(
              deviceId: 'a',
              isSelf: true,
              personId: 'aritz',
              deviceName: 'Pixel de Aritz',
            ),
            FamilyDeviceRow(deviceId: 'n', isSelf: false, personId: 'nora'),
          ]),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text('2'), findsOneWidget);
        expect(find.text('Solo en este móvil'), findsNothing);
        expect(find.text('La sincronización empezará cuando conectes otro móvil.'), findsNothing);
        expect(find.text('Pendiente de sincronizar'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }

    // Retirar al último compañero no llama a `markUnpaired`: la marca vieja de
    // la identidad puede seguir en `true` con un solo móvil en el registro.
    for (final identityPaired in [false, true]) {
      testWidgets('v2 con un solo móvil en el registro y la sincronización a '
          'la espera: «Solo en este móvil» (marca vieja: $identityPaired)', (
        tester,
      ) async {
        phoneSize(tester);
        final server = FakeSyncServer();
        late SyncPhone a;
        await tester.runAsync(() async {
          a = await SyncPhone.create(server);
          await a.createFamily('Pixel de Aritz');
          await markV2(a);
          if (identityPaired) {
            await a.family.markPaired(peerName: 'Móvil de Nora');
          } else {
            await a.family.markUnpaired();
          }
          expect(
            a.c.read(familyControllerProvider).value!.paired,
            identityPaired,
          );
        });
        addTearDown(a.dispose);
        await tester.pumpWidget(
          v2AppWaiting(a.c, const [
            FamilyDeviceRow(
              deviceId: 'a',
              isSelf: true,
              personId: 'aritz',
              deviceName: 'Pixel de Aritz',
            ),
          ]),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text('Solo en este móvil'), findsOneWidget);
        expect(
          find.text('La sincronización empezará cuando conectes otro móvil.'),
          findsOneWidget,
        );
        expect(find.text('Pendiente de sincronizar'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    }

    // Mientras el registro carga, falla o no existe (una migración a medias),
    // la marca vieja no basta para decir que hay una sincronización pendiente.
    final unknownRegistry =
        <String, Future<List<FamilyDeviceRow>?> Function(Ref ref)>{
          'carga': (ref) => Completer<List<FamilyDeviceRow>?>().future,
          'falla': (ref) async => throw StateError('registro ilegible'),
          'no existe (migración a medias)': (ref) async => null,
        };
    for (final entry in unknownRegistry.entries) {
      testWidgets('v2 con la marca vieja emparejada y el registro que '
          '${entry.key}: no afirma una sincronización pendiente', (
        tester,
      ) async {
        phoneSize(tester);
        final server = FakeSyncServer();
        late SyncPhone a;
        await tester.runAsync(() async {
          a = await SyncPhone.create(server);
          await a.createFamily('Pixel de Aritz');
          await markV2(a);
          await a.family.markPaired(peerName: 'Móvil de Nora');
        });
        addTearDown(a.dispose);
        await tester.pumpWidget(v2AppWaitingWith(a.c, entry.value));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text('Pendiente de sincronizar'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    }

    // Riverpod conserva el valor anterior durante una recarga y tras un
    // error: dos móviles leídos antes no bastan para afirmarlo después.
    final refreshes = <String, Future<List<FamilyDeviceRow>?> Function()>{
      'se recarga': () => Completer<List<FamilyDeviceRow>?>().future,
      'falla al recargar': () async => throw StateError('registro ilegible'),
    };
    for (final entry in refreshes.entries) {
      testWidgets('v2 con dos móviles leídos y el registro que '
          '${entry.key}: no afirma una sincronización pendiente', (
        tester,
      ) async {
        phoneSize(tester);
        final server = FakeSyncServer();
        late SyncPhone a;
        await tester.runAsync(() async {
          a = await SyncPhone.create(server);
          await a.createFamily('Pixel de Aritz');
          await markV2(a);
        });
        addTearDown(a.dispose);
        var reads = 0;
        await tester.pumpWidget(
          v2AppWaitingWith(a.c, (ref) {
            reads++;
            if (reads == 1) {
              return Future.value(const [
                FamilyDeviceRow(
                  deviceId: 'a',
                  isSelf: true,
                  personId: 'aritz',
                  deviceName: 'Pixel de Aritz',
                ),
                FamilyDeviceRow(deviceId: 'n', isSelf: false, personId: 'nora'),
              ]);
            }
            return entry.value();
          }),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        expect(find.text('Pendiente de sincronizar'), findsOneWidget);
        ProviderScope.containerOf(tester.element(find.byType(ShareScreen)))
            .invalidate(familyDeviceRowsProvider);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        // Tras un error, Riverpod reintenta la lectura por su cuenta.
        expect(reads, greaterThanOrEqualTo(2));
        expect(find.text('Pendiente de sincronizar'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('v1 emparejado: la lista de siempre', (tester) async {
      phoneSize(tester);
      final server = FakeSyncServer();
      late SyncPhone a;
      await tester.runAsync(() async {
        a = await SyncPhone.create(server);
        await a.createFamily('Pixel de Aritz');
        await a.family.markPaired(peerName: 'Móvil de Nora');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      addTearDown(a.dispose);
      await tester.pumpWidget(screenApp(a.c, const ShareScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Pixel de Aritz'), findsOneWidget);
      expect(find.text('Este móvil'), findsOneWidget);
      expect(find.text('Móvil de Nora'), findsOneWidget);
      expect(find.text('Conectado a esta familia'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
