// Móviles de la familia con webs: la fila «Web» frente a la de un móvil, la
// hoja de una web (sin aprobar ni cambiar persona, con «Permitir desbloquear
// otra vez») y la entrada «Conectar la web».
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/widgets/settings_icons.dart';
import 'package:regalos/core/widgets/stroke_icon.dart';
import 'package:regalos/features/sharing/presentation/share_screen.dart';
import 'package:regalos/features/sync/application/family_device_review.dart';
import 'package:regalos/features/sync/application/family_device_rows.dart';
import 'package:regalos/features/sync/application/family_devices.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/web_device/presentation/connect_web_flow.dart';

import '../../helpers/fake_sync_server.dart';
import '../../sync/invite_approval_view_test.dart' show screenApp;
import '../../sync/protected_harness.dart' show Phone, kListId;
import '../../sync/sync_harness.dart';
import '../../sharing/family_devices_list_test.dart' show markV2;
import 'mobile_web_support.dart';

class _Actions implements FamilyDeviceActions {
  final removed = <String>[];

  @override
  Future<DeviceRemovalPreview> previewRemoval(String deviceId) async =>
      const DeviceRemovalPreview(selfWouldWait: false);

  @override
  Future<List<DeviceReviewItem>> remove(
    String deviceId, {
    bool selfWaitAccepted = false,
  }) async {
    removed.add(deviceId);
    return const <DeviceReviewItem>[];
  }

  @override
  Future<void> approve(String deviceId, {String? recordDigest}) async {}
}

const _self = FamilyDeviceRow(
  deviceId: 'a',
  isSelf: true,
  personId: 'aritz',
  deviceName: 'Pixel de Aritz',
);
const _phoneNora = FamilyDeviceRow(
  deviceId: 'n',
  isSelf: false,
  personId: 'nora',
);
const _webNora = FamilyDeviceRow(
  deviceId: 'w',
  isSelf: false,
  personId: 'nora',
  isWeb: true,
);

Future<(SyncPhone, FakeHost)> _open(
  WidgetTester tester, {
  required List<FamilyDeviceRow> rows,
  bool canConnectWeb = false,
  Size size = phone375,
  FamilyDeviceActions? actions,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late SyncPhone a;
  await tester.runAsync(() async {
    a = await SyncPhone.create(FakeSyncServer());
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
    await markV2(a);
  });
  addTearDown(a.dispose);
  final host = FakeHost();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: a.c,
      child: ProviderScope(
        overrides: [
          familyDeviceRowsProvider.overrideWith((ref) async => rows),
          deviceReviewProvider.overrideWith((ref) async => DeviceReview.empty),
          pairingV2HostProvider.overrideWith(() => host),
          pairingV2AvailableProvider.overrideWithValue(canConnectWeb),
          if (actions != null)
            familyDeviceActionsProvider.overrideWithValue(actions),
        ],
        child: Builder(
          builder: (context) => screenApp(
            ProviderScope.containerOf(context),
            const ShareScreen(),
          ),
        ),
      ),
    ),
  );
  await settleMobile(tester);
  return (a, host);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.tap(find.text(text).first);
  await settleMobile(tester);
}

void main() {
  group('la lista', () {
    testWidgets('una web sale como «Web de Nora» con icono de ordenador; un '
        'móvil, como siempre', (tester) async {
      await _open(tester, rows: const [_self, _phoneNora, _webNora]);
      expect(find.text('Web de Nora'), findsOneWidget);
      expect(find.text('Ordenador conectado a esta familia'), findsOneWidget);
      // El móvil de Nora sigue con su nombre y su frase de siempre.
      expect(find.text('Nora'), findsOneWidget);
      expect(find.text('Conectado a esta familia'), findsOneWidget);
      // El contador cuenta todos los dispositivos activos.
      expect(find.text('3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('el icono de la fila de web es el del ordenador y el del '
        'móvil, el del móvil', (tester) async {
      await _open(tester, rows: const [_self, _phoneNora, _webNora]);
      Finder iconOf(String title, StrokeIconBuilder icon) => find.descendant(
        of: find
            .ancestor(of: find.text(title), matching: find.byType(Row))
            .first,
        matching: find.byWidgetPredicate(
          (w) => w is StrokeIcon && w.builder == icon,
        ),
      );
      expect(iconOf('Web de Nora', SettingsIcons.computer), findsOneWidget);
      expect(iconOf('Web de Nora', SettingsIcons.phone), findsNothing);
      expect(iconOf('Nora', SettingsIcons.phone), findsOneWidget);
      expect(iconOf('Nora', SettingsIcons.computer), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('una web sin persona conocida se llama solo «Web»', (
      tester,
    ) async {
      await _open(
        tester,
        rows: const [
          _self,
          FamilyDeviceRow(deviceId: 'w', isSelf: false, isWeb: true),
        ],
      );
      expect(find.text('Web'), findsOneWidget);
      expect(find.text('Otro móvil'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('la hoja de una web', () {
    testWidgets('sin aprobar ni cambiar persona; con permitir desbloquear y '
        'quitar', (tester) async {
      await _open(tester, rows: const [_self, _webNora]);
      await _tapText(tester, 'Web de Nora');
      expect(find.text('Permitir más intentos de PIN'), findsOneWidget);
      expect(find.text('Quitar esta web'), findsOneWidget);
      expect(
        find.text('Este ordenador dejará de recibir los cambios de la lista.'),
        findsOneWidget,
      );
      expect(find.text('Quitar este móvil'), findsNothing);
      expect(find.textContaining('Sí, es de'), findsNothing);
      expect(find.textContaining('¿Este móvil es de'), findsNothing);
      expect(find.text('De quién es'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('quitar una web habla de la web y del ordenador, no del '
        'móvil', (tester) async {
      final actions = _Actions();
      await _open(tester, rows: const [_self, _webNora], actions: actions);
      await _tapText(tester, 'Web de Nora');
      await _tapText(tester, 'Quitar esta web');
      expect(find.text('¿Quitar esta web?'), findsOneWidget);
      expect(
        find.textContaining('Este ordenador dejará de tener acceso'),
        findsOneWidget,
      );
      expect(find.text('Quitar web'), findsOneWidget);
      expect(find.text('¿Quitar este móvil?'), findsNothing);
      expect(find.text('Quitar móvil'), findsNothing);
      await _tapText(tester, 'Cancelar');
      expect(actions.removed, isEmpty);
      await _tapText(tester, 'Quitar esta web');
      await _tapText(tester, 'Quitar web');
      expect(actions.removed, ['w']);
      expect(find.text('Web quitada'), findsOneWidget);
      expect(find.text('Móvil quitado'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('si quitar una web falla, el error habla de la web', (
      tester,
    ) async {
      await _open(tester, rows: const [_self, _webNora]);
      await _tapText(tester, 'Web de Nora');
      await _tapText(tester, 'Quitar esta web');
      // La vista previa del motor de pruebas es asíncrona de verdad.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await settleMobile(tester);
      expect(
        find.text(
          'No se ha podido quitar la web. Inténtalo de nuevo con conexión.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('quitar el móvil'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('«Permitir desbloquear otra vez» pide confirmar: cancelar no '
        'hace nada', (tester) async {
      final (_, host) = await _open(tester, rows: const [_self, _webNora]);
      await _tapText(tester, 'Web de Nora');
      await _tapText(tester, 'Permitir más intentos de PIN');
      expect(find.text('¿Permitir más intentos de PIN?'), findsOneWidget);
      await _tapText(tester, 'Cancelar');
      expect(host.calls, isNot(contains('resume:w')));
      expect(find.textContaining('Listo.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('confirmar llama a resumeWebUnlock y dice el resultado', (
      tester,
    ) async {
      final (_, host) = await _open(tester, rows: const [_self, _webNora]);
      await _tapText(tester, 'Web de Nora');
      await _tapText(tester, 'Permitir más intentos de PIN');
      await _tapText(tester, 'Permitir');
      expect(host.calls, contains('resume:w'));
      expect(
        find.text('Listo. La web vuelve a aceptar el PIN.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('si falla, lo dice sin error crudo', (tester) async {
      final (_, host) = await _open(tester, rows: const [_self, _webNora]);
      host.resumeError = StateError('sin red');
      await _tapText(tester, 'Web de Nora');
      await _tapText(tester, 'Permitir más intentos de PIN');
      await _tapText(tester, 'Permitir');
      expect(
        find.text(
          'No se han podido permitir más intentos de PIN. Comprueba la conexión e inténtalo de nuevo.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('la hoja de un móvil no ofrece desbloquear', (tester) async {
      await _open(tester, rows: const [_self, _phoneNora]);
      await _tapText(tester, 'Nora');
      expect(find.text('Permitir más intentos de PIN'), findsNothing);
      expect(find.text('Quitar este móvil'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('«Conectar la web»', () {
    testWidgets('sale cuando se sincroniza y abre la pantalla', (tester) async {
      await _open(tester, rows: const [_self], canConnectWeb: true);
      expect(find.text('Conectar la web'), findsOneWidget);
      expect(
        find.text('Para apuntar regalos desde el ordenador.'),
        findsOneWidget,
      );
      await _tapText(tester, 'Conectar la web');
      expect(find.byType(ConnectWebScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin sincronización v2 no sale', (tester) async {
      await _open(tester, rows: const [_self]);
      expect(find.text('Conectar la web'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  test('familyDeviceRows marca isWeb desde la ficha firmada', () async {
    final a = await Phone.create('aritz-phone', 'aritz', 1);
    final w = await Phone.create('nora-web', 'nora', 3);
    final ra = await a.record();
    final rw = await DeviceRecord.create(
      keys: w.keys,
      listId: kListId,
      deviceId: w.id,
      personId: 'nora',
      kind: DeviceKind.web,
    );
    final registry = await DeviceRegistry.empty(kListId).withDeclarations(
      records: [ra, rw],
      vouches: [await Vouch.create(keys: a.keys, voucher: ra, record: rw)],
      anchor: RegistryAnchor(
        deviceId: a.id,
        signingKey: a.keys.publicKeys.signing,
      ),
    );
    final rows = familyDeviceRows(await a.viewOf(registry));
    expect(rows.map((r) => (r.deviceId, r.isWeb)).toList(), [
      ('aritz-phone', false),
      ('nora-web', true),
    ]);
  });
}
