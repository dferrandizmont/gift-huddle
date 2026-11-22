import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/application/pairing_v2_flow.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../../helpers/fake_haptics.dart';

import 'package:regalos/core/motion/haptics.dart';

/// Un QR de la web que `WebPairingQr.parse` acepta (dos campos de 16 ceros).
const String validWebQr =
    'https://web.gifthuddle.app/w#AAAAAAAAAAAAAAAAAAAAAA.AAAAAAAAAAAAAAAAAAAAAA';

/// Una invitación de móvil: no es el QR de una web.
const String mobileInviteQr = 'https://gifthuddle.app/i#abcdefabcdef';

const Size phone375 = Size(375, 812);
const Size desktop1280 = Size(1280, 800);

/// La familia de muestra (Aritz, Nora y Leo; Nora archivada si [archived]) sin
/// tocar el disco.
class FakeFamily extends FamilyController {
  /// Crea la familia con [people] (nombre → archivada).
  FakeFamily([Map<String, bool>? people, this.self])
    : people = people ?? const {'Aritz': false, 'Nora': false, 'Leo': false};

  /// La persona de «Yo» de este móvil, si tiene.
  final String? self;

  /// Nombre de cada persona y si está archivada.
  final Map<String, bool> people;

  @override
  Future<FamilyState> build() async {
    var doc = FamilyDoc.empty('lista');
    final clock = HlcClock(node: 'prueba');
    for (final entry in people.entries) {
      doc = doc.set(
        clock,
        Collections.recipients,
        entry.key.toLowerCase(),
        Recipient(
          id: entry.key.toLowerCase(),
          name: entry.key,
          colorIndex: 0,
          archived: entry.value,
        ).toFields(),
      );
    }
    return FamilyState(
      doc: doc,
      identity: FamilyIdentity(
        listId: 'lista',
        node: 'prueba',
        deviceName: 'Pixel de prueba',
        selfRecipientId: self,
      ),
    );
  }
}

/// El anfitrión del emparejamiento de las pruebas: apunta lo que se le pide y
/// deja a la prueba mover la fase con [push].
class FakeHost extends PairingV2HostController {
  /// Lo pedido, en orden.
  final List<String> calls = <String>[];

  /// Lo que lanza el siguiente [startWeb], si algo.
  Object? startError;

  /// Lo que lanza [resumeWebUnlock], si algo.
  Object? resumeError;

  /// El último QR con que se empezó.
  String? lastQr;

  /// Si [resumeWebUnlock] espera a [resumeGate] antes de acabar.
  Completer<void>? resumeGate;

  @override
  PairingV2HostState build() =>
      const PairingV2HostState(PairingV2HostPhase.idle);

  /// Cambia el estado, como haría el motor.
  void push(PairingV2HostState next) => state = next;

  @override
  Future<void> startWeb(
    String qr, {
    String? guestPerson,
    String origin = kWebPairingOrigin,
  }) async {
    calls.add('startWeb:$guestPerson');
    lastQr = qr;
    final error = startError;
    if (error != null) throw error;
    state = const PairingV2HostState(PairingV2HostPhase.preparing);
  }

  @override
  Future<void> resumeWebUnlock(String deviceId, {guard}) async {
    calls.add('resume:$deviceId');
    await resumeGate?.future;
    final error = resumeError;
    if (error != null) throw error;
  }

  @override
  Future<void> confirm() async => calls.add('confirm');

  @override
  Future<void> confirmPerson() async => calls.add('confirmPerson');

  @override
  Future<void> confirmMigration() async => calls.add('confirmMigration');

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    state = const PairingV2HostState(PairingV2HostPhase.cancelled);
  }

  @override
  void dismiss() {
    calls.add('dismiss');
    state = const PairingV2HostState(PairingV2HostPhase.idle);
  }
}

/// Monta [home] como la app: tema, idiomas, Riverpod con [overrides] y el
/// tamaño de ventana [size].
Future<void> pumpMobileWeb(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
  Locale locale = const Locale('es'),
  Size size = phone375,
  Duration settle = const Duration(milliseconds: 700),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hapticsProvider.overrideWithValue(FakeHaptics()),
        ...overrides,
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(AccentId.lavender.palette, Brightness.light),
        home: home,
      ),
    ),
  );
  await tester.pump();
  if (settle > Duration.zero) await tester.pump(settle);
}

/// Deja correr las animaciones sin esperar a los indicadores de espera.
Future<void> settleMobile(WidgetTester tester, [int steps = 6]) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}
