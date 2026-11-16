// Capturas del tema oscuro de las pantallas clave, para compararlo a ojo
// (la guía del tema oscuro). Solo con
//
//   cd app && flutter test test/screens/dark_capture_test.dart \
//     --dart-define=CAPTURE_DARK=despues
//
// El valor es la subcarpeta de capturas del tema oscuro donde se guardan
// (`antes`, `despues`, `alternativa`), dentro de `build/screens/oscuro/`
// (ignorado por git). Siempre en oscuro: móvil y tablet vertical.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, SystemChannels;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/motion/haptics.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/settings_row.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/sharing/presentation/share_screen.dart';
import 'package:regalos/features/sync/application/family_device_review.dart';
import 'package:regalos/features/sync/application/family_device_rows.dart';
import 'package:regalos/features/sync/application/family_devices.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fake_haptics.dart';
import '../helpers/fake_recovery.dart';
import '../helpers/fake_sync_server.dart';
import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/settings_column.dart';
import '../helpers/tablet.dart';
import '../sharing/family_devices_list_test.dart' show markV2;
import '../sync/sync_harness.dart';

const String _dir = String.fromEnvironment('CAPTURE_DARK');

final GlobalKey _boundary = GlobalKey();
late FakeRecovery _fake;

Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) {
    return;
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File(
            '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
  for (final family in ['Roboto', 'Ahem']) {
    final loader = FontLoader(family);
    for (final name in ['regular', 'medium', 'bold']) {
      final file = File(
        '$root/bin/cache/artifacts/material_fonts/roboto-$name.ttf',
      );
      if (file.existsSync()) {
        loader.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    }
    await loader.load();
  }
}

Future<void> _shotRaw(WidgetTester tester, String name, double ratio) async {
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/screens/oscuro/$_dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}

Future<void> _shot(WidgetTester tester, String name, double ratio) async {
  await settle(tester);
  await _shotRaw(tester, name, ratio);
}

Future<void> _mount(WidgetTester tester, FakePhone phone) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: RepaintBoundary(key: _boundary, child: const RegalosApp()),
    ),
  );
  await settle(tester);
}

void _go(FakePhone phone, String path) =>
    phone.container.read(routerProvider).go(path);

class _Actions implements FamilyDeviceActions {
  @override
  Future<DeviceRemovalPreview> previewRemoval(String deviceId) async =>
      const DeviceRemovalPreview(selfWouldWait: false);

  @override
  Future<List<DeviceReviewItem>> remove(
    String deviceId, {
    bool selfWaitAccepted = false,
  }) async => const [];

  @override
  Future<void> approve(String deviceId, {String? recordDigest}) async {}
}

const _self = FamilyDeviceRow(
  deviceId: 'a',
  isSelf: true,
  personId: 'aritz',
  deviceName: 'Pixel de Aritz',
);
const _nora = FamilyDeviceRow(deviceId: 'n', isSelf: false, personId: 'nora');

void main() {
  if (_dir.isEmpty) {
    test('capturas del oscuro', () {}, skip: 'solo con CAPTURE_DARK=<carpeta>');
    return;
  }
  setUpAll(() async {
    await _loadRoboto();
    await loadInter();
  });

  for (final (label, size, ratio) in <(String, Size, double)>[
    ('movil', kPhoneSize, 2.0),
    ('tablet', kTabletPortrait, 1.0),
  ]) {
    final tablet = label == 'tablet';

    screenTest(
      'pantallas $label',
      (tester, phone) async {
        await seedSample(tester, phone);
        await _mount(tester, phone);
        Future<void> shot(String n) => _shot(tester, '$n-$label', ratio);
        await shot('01-hoy-personas');
        _go(phone, '/people/aritz');
        await shot('02-ficha-persona');
        _go(phone, '/occasions');
        await shot('03-ocasiones');
        _go(phone, '/occasions/seed-kings');
        await shot('03b-ocasion-reyes');
        _go(phone, '/family');
        await shot('03c-reparto');
        _go(phone, '/settings');
        await shot('05-ajustes');
        _go(phone, '/settings/appearance');
        await shot('05b-apariencia');
        _go(phone, '/settings/security');
        await shot('05c-seguridad');
        _go(phone, '/people/aritz');
        await settle(tester);
        if (find.byType(FloatingActionButton).evaluate().isNotEmpty) {
          await tester.tap(find.byType(FloatingActionButton));
          await shot('04-editor-regalo');
        }
      },
      brightness: Brightness.dark,
      size: size,
    );

    screenTest(
      'bienvenida $label',
      (tester, phone) async {
        await _mount(tester, phone);
        await _shot(tester, '07-bienvenida-$label', ratio);
      },
      brightness: Brightness.dark,
      size: size,
    );

    if (!tablet) {
      screenTest(
        'código de recuperación $label',
        (tester, phone) async {
          final display = (await tester.runAsync(sampleRecoveryDisplay))!;
          _fake = FakeRecovery(display: display);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => null,
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await seedSample(tester, phone);
          await tester.runAsync(
            () => phone.container
                .read(selfRecipientIdProvider.notifier)
                .choose('aritz'),
          );
          await _mount(tester, phone);
          await tester.tap(find.text('Ajustes').last);
          await settle(tester);
          await tapVisible(
            tester,
            find.widgetWithText(SettingsRow, 'Código de recuperación'),
          );
          await tapVisible(tester, find.text('Crear código de recuperación'));
          await tapText(tester, 'Continuar');
          await _shot(tester, '08-codigo-recuperacion-$label', ratio);
        },
        brightness: Brightness.dark,
        size: size,
        overrides: [
          recoveryApplicationProvider.overrideWith(() => _fake),
          hapticsProvider.overrideWith((ref) => FakeHaptics()),
        ],
      );
    }

    testWidgets('móviles de la familia con diálogo $label', (tester) async {
      await tester.runAsync(loadInter);
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
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: a.c,
          child: ProviderScope(
            overrides: [
              familyDeviceRowsProvider.overrideWith(
                (ref) async => const [_self, _nora],
              ),
              deviceReviewProvider.overrideWith(
                (ref) async => DeviceReview.empty,
              ),
              familyDeviceActionsProvider.overrideWithValue(_Actions()),
            ],
            child: RepaintBoundary(
              key: _boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: const Locale('es'),
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                theme: buildTheme(AccentId.lavender.palette, Brightness.dark),
                home: const ShareScreen(),
              ),
            ),
          ),
        ),
      );
      Future<void> pumpSome() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
      }

      await pumpSome();
      await tester.tap(find.text('Nora').first);
      await pumpSome();
      await tester.tap(find.text('Quitar este móvil').first);
      await pumpSome();
      await _shotRaw(tester, '06-moviles-dialogo-$label', ratio);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
