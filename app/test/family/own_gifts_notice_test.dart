// El aviso de una vez de «ya no ves tus regalos en este móvil» (1.0.6): cuándo
// toca, que se apunta lo visto y cómo se ve el diálogo en español e inglés,
// claro y oscuro, con letra grande y sin movimiento. Y el bloque fijo de la
// ficha de la propia persona.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/prefs/shared_preferences_provider.dart';
import 'package:regalos/core/theme/theme.dart';
import 'package:regalos/core/widgets/secret_block.dart';
import 'package:regalos/features/family/application/own_gifts_notice.dart';
import 'package:regalos/features/family/presentation/own_gifts_notice_listener.dart';
import 'package:regalos/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

/// La situación que la prueba va moviendo.
class _Sit extends Notifier<OwnGiftsSituation?> {
  @override
  OwnGiftsSituation? build() => null;

  void set(OwnGiftsSituation? next) => state = next;
}

final _sit = NotifierProvider<_Sit, OwnGiftsSituation?>(_Sit.new);

const _hidden = OwnGiftsSituation(hidden: true, settled: true, name: 'Aritz');
const _alone = OwnGiftsSituation(hidden: false, settled: true, name: 'Aritz');

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold)));

void main() {
  setUpAll(loadInter);

  group('cuándo toca el aviso', () {
    Future<SharedPreferences> prefs([Map<String, Object> v = const {}]) =>
        mockPrefs(v);

    test('oculto y sin avisar nunca: avisa una vez y lo apunta', () async {
      final p = await prefs();
      final first = nextOwnGiftsNotice(p, _hidden);
      expect(first?.kind, OwnGiftsNoticeKind.hidden);
      expect(first?.personName, 'Aritz');
      expect(p.getBool(kOwnGiftsHiddenSeenKey), isTrue);
      expect(p.getBool(kOwnGiftsWasHiddenKey), isTrue);
      expect(nextOwnGiftsNotice(p, _hidden), isNull);
    });

    test('al quedarse solo, avisa una vez y no se repite', () async {
      final p = await prefs({
        kOwnGiftsHiddenSeenKey: true,
        kOwnGiftsWasHiddenKey: true,
      });
      final alone = nextOwnGiftsNotice(p, _alone);
      expect(alone?.kind, OwnGiftsNoticeKind.alone);
      expect(p.getBool(kOwnGiftsWasHiddenKey), isFalse);
      expect(nextOwnGiftsNotice(p, _alone), isNull);
    });

    test('sin el registro leído no se dice que se quedó solo', () async {
      final p = await prefs({
        kOwnGiftsHiddenSeenKey: true,
        kOwnGiftsWasHiddenKey: true,
      });
      const loading = OwnGiftsSituation(
        hidden: false,
        settled: false,
        name: 'Aritz',
      );
      expect(nextOwnGiftsNotice(p, loading), isNull);
      expect(p.getBool(kOwnGiftsWasHiddenKey), isTrue);
    });

    test('un móvil que nunca estuvo acompañado no avisa de nada', () async {
      final p = await prefs();
      expect(nextOwnGiftsNotice(p, _alone), isNull);
      expect(nextOwnGiftsNotice(p, null), isNull);
    });

    test('quien entra con la hoja final ya lo sabe: no se avisa otra vez', () {
      return prefs().then((p) {
        markOwnGiftsHiddenSeen(p);
        expect(nextOwnGiftsNotice(p, _hidden), isNull);
        // Pero si luego se queda solo, sí.
        expect(nextOwnGiftsNotice(p, _alone)?.kind, OwnGiftsNoticeKind.alone);
      });
    });
  });

  group('el escuchador', () {
    testWidgets('enseña el aviso una sola vez, espera a que se cierre una hoja '
        'y avisa también de que se ha quedado solo', (tester) async {
      final prefs = await mockPrefs();
      final key = GlobalKey<NavigatorState>();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ownGiftsSituationProvider.overrideWith((ref) => ref.watch(_sit)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: key,
            locale: const Locale('es'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildTheme(AccentId.lavender.palette, Brightness.light),
            builder: (context, child) =>
                OwnGiftsNoticeListener(navigatorKey: key, child: child!),
            home: const Scaffold(body: Text('Personas')),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(OwnGiftsNoticeDialog), findsNothing);

      // Una hoja abierta: el aviso espera sin apuntarse como visto.
      showModalBottomSheet<void>(
        context: key.currentContext!,
        builder: (_) => const SizedBox(height: 120, child: Text('Hoja')),
      );
      await tester.pumpAndSettle();
      container.read(_sit.notifier).set(_hidden);
      await tester.pump();
      await tester.pump();
      expect(find.byType(OwnGiftsNoticeDialog), findsNothing);
      expect(prefs.getBool(kOwnGiftsHiddenSeenKey), isNull);

      // Al cerrar la hoja, sale el aviso (el reintento de 2 s).
      key.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(OwnGiftsNoticeDialog), findsOneWidget);
      expect(
        find.text(
          'En este móvil no se ven los regalos para Aritz. Solo otra persona '
          'de la familia puede cambiarlo, desde su móvil.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(find.byType(OwnGiftsNoticeDialog), findsNothing);

      // No se repite aunque cambie la situación y vuelva.
      container.read(_sit.notifier).set(null);
      await tester.pump();
      container.read(_sit.notifier).set(_hidden);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(OwnGiftsNoticeDialog), findsNothing);

      // El móvil se queda solo: el aviso de que sus regalos en secreto no
      // están en él.
      container.read(_sit.notifier).set(_alone);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(OwnGiftsNoticeDialog), findsOneWidget);
      expect(
        find.textContaining('ya no está conectado a ningún otro'),
        findsOneWidget,
      );
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(find.byType(OwnGiftsNoticeDialog), findsNothing);
    });
  });

  for (final brightness in Brightness.values) {
    for (final locale in const ['es', 'en']) {
      for (final big in [false, true]) {
        for (final reduce in [false, true]) {
          final label =
              '$locale ${brightness.name} ${big ? 'x2' : 'x1'}'
              '${reduce ? ' sin movimiento' : ''}';
          group('diálogo · $label', () {
            for (final kind in OwnGiftsNoticeKind.values) {
              testWidgets('${kind.name}: título, frase y «Entendido»', (
                tester,
              ) async {
                await pumpThemed(
                  tester,
                  OwnGiftsNoticeDialog(notice: OwnGiftsNotice(kind, 'Aritz')),
                  locale: Locale(locale),
                  brightness: brightness,
                  textScale: big ? 2 : 1,
                  disableAnimations: reduce,
                  surfaceSize: const Size(360, 640),
                );
                final l10n = _l10n(tester);
                expect(
                  find.text(l10n.ownGiftsNoticeTitle('Aritz')),
                  findsOneWidget,
                );
                expect(
                  find.text(
                    kind == OwnGiftsNoticeKind.hidden
                        ? l10n.ownGiftsHiddenBody('Aritz')
                        : l10n.ownGiftsAloneNotice('Aritz'),
                  ),
                  findsOneWidget,
                );
                expect(find.text(l10n.actionUnderstood), findsOneWidget);
                expect(tester.takeException(), isNull);
              });
            }

            testWidgets('el bloque de la propia persona crece con el texto, no '
                'con los regalos', (tester) async {
              await pumpThemed(
                tester,
                Builder(
                  builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SecretBlockCard(
                        key: const ValueKey('own'),
                        name: 'Aritz',
                        note: AppLocalizations.of(context)
                            .ownGiftsHiddenBody('Aritz'),
                      ),
                      const SizedBox(height: 8),
                      const SecretBlockCard(
                        key: ValueKey('other'),
                        name: 'Nora',
                      ),
                    ],
                  ),
                ),
                locale: Locale(locale),
                brightness: brightness,
                textScale: big ? 2 : 1,
                disableAnimations: reduce,
                surfaceSize: const Size(360, 900),
              );
              final l10n = _l10n(tester);
              expect(
                find.text(l10n.ownGiftsHiddenBody('Aritz')),
                findsOneWidget,
              );
              // El de otra persona sigue midiendo lo de siempre (con letra normal).
              final other = tester.getSize(find.byKey(const ValueKey('other')));
              if (big) {
                expect(
                  other.height,
                  greaterThanOrEqualTo(SecretBlockCard.height),
                );
              } else {
                expect(other.height, SecretBlockCard.height);
              }
              expect(
                tester.getSize(find.byKey(const ValueKey('own'))).height,
                greaterThanOrEqualTo(SecretBlockCard.height),
              );
              expect(tester.takeException(), isNull);
            });
          });
        }
      }
    }
  }
}
