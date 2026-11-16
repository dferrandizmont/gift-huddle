// Capturas de las pantallas del código de recuperación, para mirarlas con
// ojos. Solo se hacen con `--dart-define=CAPTURE_RECOVERY=true` y se guardan en
// `build/screens/pantallas/recuperacion/` (ignorado por git):
//
//   cd app && flutter test test/screens/recovery_capture_test.dart \
//     --dart-define=CAPTURE_RECOVERY=true
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/motion/haptics.dart';
import 'package:regalos/core/widgets/settings_row.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/sync/application/recovery_providers.dart';

import '../helpers/fake_haptics.dart';
import '../helpers/fake_recovery.dart';
import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';
import '../helpers/settings_column.dart';
import '../helpers/tablet.dart';
import 'settings_test.dart' show openSettings;

const bool _capture = bool.fromEnvironment('CAPTURE_RECOVERY');

final GlobalKey _boundary = GlobalKey();
late FakeRecovery _fake;
String? _clipboard;

Future<void> _pump(WidgetTester tester, FakePhone phone) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: RepaintBoundary(key: _boundary, child: const RegalosApp()),
    ),
  );
  await settle(tester);
}

Future<void> _spin(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  if (!_capture) {
    test(
      'capturas del código de recuperación',
      () {},
      skip: 'solo con --dart-define=CAPTURE_RECOVERY=true',
    );
    return;
  }
  final configs = <(String, Size, Brightness)>[
    ('movil-claro', kPhoneSize, Brightness.light),
    ('movil-oscuro', kPhoneSize, Brightness.dark),
    ('tablet-horizontal-claro', kTabletLandscape, Brightness.light),
    ('tablet-vertical-oscuro', kTabletPortrait, Brightness.dark),
  ];
  for (final (name, size, brightness) in configs) {
    final overrides = <Override>[
      recoveryApplicationProvider.overrideWith(() => _fake),
      hapticsProvider.overrideWith((ref) => FakeHaptics()),
    ];
    screenTest(
      'capturas $name',
      (tester, phone) async {
        await tester.runAsync(loadInter);
        final display = (await tester.runAsync(sampleRecoveryDisplay))!;
        _fake = FakeRecovery(display: display);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => call.method == 'Clipboard.getData'
              ? <String, Object?>{'text': _clipboard}
              : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        _clipboard = display.words.join(' ');

        Future<void> shot(String file) async {
          await tester.runAsync(() async {
            final boundary =
                _boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1.5);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final out = File(
              'build/screens/pantallas/recuperacion/$file-$name.png',
            );
            await out.parent.create(recursive: true);
            await out.writeAsBytes(data!.buffer.asUint8List());
          });
        }

        await seedSample(tester, phone);
        await tester.runAsync(
          () => phone.container
              .read(selfRecipientIdProvider.notifier)
              .choose('aritz'),
        );
        await _pump(tester, phone);

        // Ajustes › Código de recuperación, y crear.
        await openSettings(tester);
        await shot('01-ajustes-lista');
        await tapVisible(
          tester,
          find.widgetWithText(SettingsRow, 'Código de recuperación'),
        );
        await shot('02-ajustes-sin-crear');
        await tapVisible(tester, find.text('Crear código de recuperación'));
        await shot('03-crear-explicacion');
        await tapText(tester, 'Continuar');
        await shot('04-crear-palabras');
        await tapText(tester, 'Ver código QR');
        await shot('05-crear-qr');
        await tapText(tester, 'Ver las palabras');
        await tapText(tester, 'Ya las he guardado');
        await shot('06-crear-comprobacion');
        final asked = RegExp(r'\d+')
            .allMatches(
              tester
                  .widgetList<Text>(find.textContaining('Escribe las palabras'))
                  .first
                  .data!,
            )
            .map((m) => int.parse(m[0]!))
            .toList();
        for (var i = 0; i < 3; i++) {
          await tester.enterText(
            find.byType(TextField).at(i),
            display.words[asked[i] - 1],
          );
        }
        await tapText(tester, 'Comprobar');
        await shot('07-crear-preparado');
        await tapText(tester, 'Listo');
        await shot('08-ajustes-preparado');

        // Recuperar.
        phone.container.read(routerProvider).go(AppRoutes.recover);
        await settle(tester);
        await shot('09-recuperar-vacio');
        await tapText(tester, 'Pegar las 24 palabras');
        await shot('10-recuperar-24');
        _fake.holdRestore = Completer<void>();
        final submit = find.widgetWithText(FilledButton, 'Recuperar la lista');
        await tester.tap(submit);
        _fake.reportPhase(RecoveryPhase.downloading);
        await _spin(tester);
        await shot('11-recuperar-progreso');
        _fake.holdRestore!.complete();
        await _spin(tester, 12);
        await shot('12-recuperar-resultado');

        // Un código que no vale.
        phone.container.read(routerProvider).go('/people');
        await settle(tester);
        phone.container.read(routerProvider).go(AppRoutes.recover);
        await settle(tester);
        await tapText(tester, 'Pegar las 24 palabras');
        _fake.restoreFinal = const RecoveryStatus(
          RecoveryReadiness.needsAttention,
          phase: RecoveryPhase.needsAttention,
          cause: 'not_found',
        );
        await tester.tap(submit);
        await _spin(tester, 12);
        await shot('13-recuperar-error');

        // Sin conexión, con «Reintentar».
        await tapText(tester, 'Escribir otro código');
        await tapText(tester, 'Pegar las 24 palabras');
        _fake.restoreError = const RecoveryApplicationException(
          'network',
          retryable: true,
        );
        await tester.tap(submit);
        await _spin(tester, 12);
        await shot('14-recuperar-sin-conexion');

        // La lista se ha pasado a otro móvil.
        _fake.push(const RecoveryStatus(RecoveryReadiness.transferred));
        await settle(tester);
        await shot('15-transferida');
      },
      size: size,
      brightness: brightness,
      overrides: overrides,
    );
  }
}
