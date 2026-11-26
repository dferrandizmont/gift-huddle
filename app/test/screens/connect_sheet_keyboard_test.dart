// «Conectar otro móvil» › «¿Quién eres?» / «¿Para quién es el móvil nuevo?» ›
// «Nadie» / «No estoy en la lista» (QA 1.0.7, M1b y M1c): con el teclado
// abierto, el campo del nombre y «Continuar» se ven a la vez, sin desplazar,
// también cuando sale el aviso y con letra grande. En vertical y en
// horizontal (en horizontal, al menos «Continuar»).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/features/family/application/self_person_gate.dart';
import 'package:regalos/features/sharing/presentation/connect_sheet.dart';
import 'package:regalos/features/sync/presentation/invite_screen.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fake_self_gate.dart';
import '../helpers/fonts.dart';

/// Quien conecta: con [selfId] el móvil ya es de alguien y la pregunta es
/// «¿Para quién es el móvil nuevo?»; sin él, «¿Quién eres?».
class _Host extends PairingV2HostController {
  _Host(this.selfId);

  final String? selfId;
  final newPeople = <({String name, bool noGifts})>[];

  @override
  PairingV2HostState build() => PairingV2HostState(
    PairingV2HostPhase.choosePerson,
    people: const [
      PairingV2Person('nora', 'Nora'),
      PairingV2Person('leo', 'Leo'),
      PairingV2Person('aritz', 'Aritz'),
    ],
    selfPersonId: selfId,
  );

  @override
  Future<void> choose() async {}

  @override
  Future<void> startForNewPerson(String name, {bool noGifts = false}) async {
    newPeople.add((name: name, noGifts: noGifts));
  }

  @override
  void dismiss() {}
}

Future<(FakeGate, _Host)> _openAndPick(
  WidgetTester tester,
  Size size,
  double keyboard,
  String option, {
  String? selfId,
  double textScale = 1,
  // El iPhone: barra de estado arriba y, abajo, el indicador de inicio, que el
  // teclado cubre (el relleno baja a 0, `viewPadding` no).
  double safeTop = 0,
  double safeBottom = 0,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1
    ..padding = FakeViewPadding(top: safeTop, bottom: safeBottom)
    ..viewPadding = FakeViewPadding(top: safeTop, bottom: safeBottom);
  addTearDown(tester.view.reset);
  final gate = FakeGate();
  final host = _Host(selfId);
  // El `ProviderScope` va por encima de la app: la hoja cuelga del navegador
  // raíz, no del `home`.
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        pairingV2AvailableProvider.overrideWithValue(true),
        selfPersonGateActionsProvider.overrideWithValue(gate),
        selfPersonGateProvider.overrideWith(
          (ref) async => const SelfPersonGate(suggestedName: ''),
        ),
        pairingV2HostProvider.overrideWith(() => host),
      ],
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(AccentId.lavender.palette, Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showConnectSheet(context),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
  await tester.tap(find.text(l10n.devicesHereTitle));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(ValueKey<String>(option)));
  await tester.tap(find.byKey(ValueKey<String>(option)));
  await tester.pumpAndSettle();
  // El teclado se abre: lo hace el sistema, no la prueba. No se toca la hoja
  // ni se desplaza nada a mano desde aquí.
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.view.padding = FakeViewPadding(
    top: safeTop,
    bottom: math.max(0, safeBottom - keyboard),
  );
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpAndSettle();
  return (gate, host);
}

final _next = find.byKey(const ValueKey<String>('personPickerContinue'));

/// El campo y «Continuar» a la vez, por encima del teclado y dentro de la
/// pantalla, sin desplazar nada.
void _expectBothAbove(WidgetTester tester, Size size, double keyboard) {
  final top = size.height - keyboard;
  final field = tester.getRect(find.byType(TextField));
  final next = tester.getRect(_next);
  expect(field.top, greaterThanOrEqualTo(0));
  expect(field.bottom, lessThanOrEqualTo(top));
  expect(next.top, greaterThanOrEqualTo(0));
  expect(next.bottom, lessThanOrEqualTo(top));
  expect(tester.takeException(), isNull);
}

String _where(String? selfId) =>
    selfId == null ? 'Quién eres' : 'Para quién es el móvil nuevo';

void main() {
  setUpAll(loadInter);

  const portrait = Size(412, 915);
  const portraitKeyboard = 336.0;

  for (final selfId in <String?>[null, 'nora']) {
    testWidgets('Nadie pide su propio nombre en ${_where(selfId)}', (
      tester,
    ) async {
      final (gate, host) = await _openAndPick(
        tester,
        portrait,
        portraitKeyboard,
        'notOnList',
        selfId: selfId,
      );
      final field = find.byType(TextField);
      await tester.enterText(field, 'Aritz');
      await tester.pumpAndSettle();
      final nobody = find.byKey(const ValueKey<String>('nobody'));
      await tester.ensureVisible(nobody);
      await tester.tap(nobody);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(tester.widget<FilledButton>(_next).onPressed, isNull);
      expect(gate.calls, isEmpty);
      expect(host.newPeople, isEmpty);

      await tester.enterText(field, ' Leo ');
      await tester.pumpAndSettle();
      _expectBothAbove(tester, portrait, portraitKeyboard);
      await tester.tap(_next);
      await tester.pumpAndSettle();
      if (selfId == null) {
        expect(gate.calls, ['nobody:Leo']);
      } else {
        expect(host.newPeople, [(name: 'Leo', noGifts: true)]);
      }
    });

    for (final scale in [1.0, 1.5]) {
      for (final option in ['nobody', 'notOnList']) {
        testWidgets(
          'vertical, teclado, ${_where(selfId)}, $option, letra x$scale: '
          'campo y Continuar a la vez',
          (tester) async {
            await _openAndPick(
              tester,
              portrait,
              portraitKeyboard,
              option,
              selfId: selfId,
              textScale: scale,
            );
            _expectBothAbove(tester, portrait, portraitKeyboard);
          },
        );
      }

      testWidgets(
        'vertical, teclado, ${_where(selfId)}, letra x$scale: tras escribir '
        '(con aviso) Continuar sigue a la vista',
        (tester) async {
          await _openAndPick(
            tester,
            portrait,
            portraitKeyboard,
            'notOnList',
            selfId: selfId,
            textScale: scale,
          );
          await tester.enterText(find.byType(TextField), 'Marta');
          await tester.pumpAndSettle();
          if (selfId != null) {
            // El aviso de que los regalos pasan a ser secretos.
            expect(find.textContaining('pasan a estar en secreto'), findsOne);
          }
          _expectBothAbove(tester, portrait, portraitKeyboard);
        },
      );
    }
  }

  testWidgets('vertical con un teclado muy alto (450): Continuar a la vista '
      'tras escribir', (tester) async {
    await _openAndPick(tester, portrait, 450, 'notOnList', selfId: 'nora');
    await tester.enterText(find.byType(TextField), 'Marta');
    await tester.pumpAndSettle();
    _expectBothAbove(tester, portrait, 450);
  });

  for (final selfId in <String?>[null, 'nora']) {
    testWidgets(
      'horizontal, teclado, ${_where(selfId)}: Continuar queda por encima '
      'del teclado sin desplazar la hoja',
      (tester) async {
        const size = Size(915, 412);
        const keyboard = 190.0;
        await _openAndPick(tester, size, keyboard, 'nobody', selfId: selfId);
        final top = size.height - keyboard;
        expect(tester.getRect(_next).bottom, lessThanOrEqualTo(top));
        expect(tester.getRect(_next).top, greaterThanOrEqualTo(0));
        await tester.enterText(find.byType(TextField), 'Marta');
        await tester.pumpAndSettle();
        expect(tester.getRect(_next).bottom, lessThanOrEqualTo(top));
        expect(tester.getRect(_next).top, greaterThanOrEqualTo(0));
        expect(tester.takeException(), isNull);
      },
    );
  }

  // QA iOS 1.0.7, M1 (iPhone XR): el teclado tapaba «Continuar» en «¿Quién
  // eres?». Mismas pruebas con la geometría del iPhone: barra de estado y
  // indicador de inicio, en un 375×667 (teclado de 260, sin indicador) y en un
  // 390×844 (teclado de 336, que cubre el indicador), con letra x1 y x1,5.
  for (final (size, keyboard, top, bottom) in <(Size, double, double, double)>[
    (const Size(375, 667), 260.0, 20.0, 0.0),
    (const Size(390, 844), 336.0, 47.0, 34.0),
  ]) {
    for (final selfId in <String?>[null, 'nora']) {
      for (final scale in [1.0, 1.5]) {
        for (final option in ['nobody', 'notOnList']) {
          testWidgets('iPhone ${size.width.toInt()}x${size.height.toInt()}, '
              '${_where(selfId)}, $option, letra x$scale: campo y Continuar a '
              'la vez, también tras escribir', (tester) async {
            await _openAndPick(
              tester,
              size,
              keyboard,
              option,
              selfId: selfId,
              textScale: scale,
              safeTop: top,
              safeBottom: bottom,
            );
            _expectBothAbove(tester, size, keyboard);
            await tester.enterText(find.byType(TextField), 'Marta');
            await tester.pumpAndSettle();
            _expectBothAbove(tester, size, keyboard);
          });
        }
      }
    }
  }

  // «Está lejos»: la misma pregunta en la pantalla de invitar con enlace, que
  // no es una hoja sino un `Scaffold` con su propio desplazamiento.
  for (final (size, keyboard, top, bottom) in <(Size, double, double, double)>[
    (const Size(375, 667), 260.0, 20.0, 0.0),
    (const Size(390, 844), 336.0, 47.0, 34.0),
    (const Size(414, 896), 336.0, 48.0, 34.0),
  ]) {
    for (final selfId in <String?>[null, 'nora']) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          'iPhone ${size.width.toInt()}x${size.height.toInt()}, pantalla de '
          'invitar, ${_where(selfId)}, letra x$scale: campo y Continuar a la '
          'vez',
          (tester) async {
            tester.view
              ..physicalSize = size
              ..devicePixelRatio = 1
              ..padding = FakeViewPadding(top: top, bottom: bottom)
              ..viewPadding = FakeViewPadding(top: top, bottom: bottom);
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              ProviderScope(
                overrides: <Override>[
                  pairingV2AvailableProvider.overrideWithValue(true),
                  selfPersonGateActionsProvider.overrideWithValue(FakeGate()),
                  selfPersonGateProvider.overrideWith(
                    (ref) async => const SelfPersonGate(suggestedName: 'Aritz'),
                  ),
                  pairingV2HostProvider.overrideWith(() => _Host(selfId)),
                ],
                child: MaterialApp(
                  locale: const Locale('es'),
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: AppLocalizations.supportedLocales,
                  theme: buildTheme(
                    AccentId.lavender.palette,
                    Brightness.light,
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: const InviteScreen(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byKey(const ValueKey('notOnList')));
            await tester.tap(find.byKey(const ValueKey('notOnList')));
            await tester.pumpAndSettle();
            tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
            tester.view.padding = FakeViewPadding(
              top: top,
              bottom: math.max(0, bottom - keyboard),
            );
            addTearDown(tester.view.resetViewInsets);
            await tester.pumpAndSettle();
            _expectBothAbove(tester, size, keyboard);
            await tester.enterText(find.byType(TextField), 'Marta');
            await tester.pumpAndSettle();
            _expectBothAbove(tester, size, keyboard);
          },
        );
      }
    }
  }
}
