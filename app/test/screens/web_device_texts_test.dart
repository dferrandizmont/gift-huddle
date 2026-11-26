// m9 (QA 1.0.6): en la web, lo que habla del propio dispositivo dice «este
// ordenador» y no «este móvil»: el bloque en secreto, el de la propia persona,
// el aviso de una vez, Acerca de y los avisos y motivos del editor. En el
// móvil, todo sigue igual. La web se fuerza con `webAppProvider` (sin
// `--platform chrome`).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/app_info.dart';
import 'package:regalos/core/sync/protected_doc.dart'
    show ProtectedPersonReason, SecretBlock;
import 'package:regalos/core/widgets/secret_block.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/application/own_gifts_notice.dart';
import 'package:regalos/features/family/domain/family_errors.dart'
    show GiftWriteResult;
import 'package:regalos/features/family/presentation/giver_person_flow.dart';
import 'package:regalos/features/family/presentation/own_gifts_notice_listener.dart';
import 'package:regalos/features/family/presentation/protection_texts.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import '../helpers/screens.dart';
import '../web_device/presentation/gate_test_support.dart';

const _ownWeb =
    'En este ordenador no se ven los regalos para Aritz. Solo otra persona de '
    'la familia puede cambiarlo, desde su móvil.';

List<Override> _web() => [
  webAppProvider.overrideWithValue(true),
  webGateActionsProvider.overrideWithValue(FakeGateActions()),
  webDeviceStateProvider.overrideWithValue(
    const WebDeviceState(
      status: WebSyncStatus.confirmed,
      hasRoots: true,
      setAsideChanges: 0,
      persistenceDenied: false,
    ),
  ),
];

final _blocks = <Override>[
  ownHiddenPeopleProvider.overrideWithValue({'aritz'}),
  secretBlocksProvider.overrideWithValue(const [
    SecretBlock('aritz'),
    SecretBlock('nora'),
  ]),
];

Future<void> _mountWeb(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: const RegalosApp(webSession: true),
    ),
  );
  await settle(tester);
}

void main() {
  setUpAll(loadInter);

  screenTest(
    'la ficha de la propia persona y la de otra dicen «este ordenador»',
    (tester, phone) async {
      await _mountWeb(tester, phone);
      await tapText(tester, 'Aritz');
      expect(find.text(_ownWeb), findsOneWidget);
      expect(find.textContaining('este móvil'), findsNothing);
      await tapLabel(tester, 'Volver a Personas');
      await tapText(tester, 'Nora');
      expect(find.text('Este ordenador no los muestra.'), findsOneWidget);
      expect(find.text('Este móvil no los muestra.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    overrides: [..._web(), ..._blocks],
  );

  screenTest('en el móvil, la ficha sigue diciendo «este móvil»', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await tapText(tester, 'Nora');
    expect(find.text('Este móvil no los muestra.'), findsOneWidget);
    expect(find.text('Este ordenador no los muestra.'), findsNothing);
  }, overrides: _blocks);

  screenTest(
    'Ajustes enseña la versión de la app y Acerca de, en la web, habla de este ordenador',
    (tester, phone) async {
      await _mountWeb(tester, phone);
      await tester.tap(find.text('Ajustes').last);
      await settle(tester);
      expect(find.text(kAppVersion), findsOneWidget);
      await tapText(tester, 'Acerca de Gift Huddle');
      expect(
        find.text(
          'Sin cuentas ni publicidad. La lista solo sale de este ordenador '
          'para sincronizarse con los móviles de tu familia, y siempre va '
          'cifrada.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('sale de tu móvil'), findsNothing);
    },
    size: const Size(390, 1200),
    overrides: _web(),
  );

  for (final locale in const ['es', 'ca', 'en']) {
    for (final kind in OwnGiftsNoticeKind.values) {
      testWidgets('aviso de una vez en la web ($locale, ${kind.name})', (
        tester,
      ) async {
        await pumpThemed(
          tester,
          OwnGiftsNoticeDialog(
            notice: OwnGiftsNotice(kind, 'Aritz'),
            web: true,
          ),
          locale: Locale(locale),
          surfaceSize: const Size(360, 640),
        );
        final l10n = lookupAppLocalizations(Locale(locale));
        expect(
          find.text(
            kind == OwnGiftsNoticeKind.hidden
                ? l10n.ownGiftsHiddenBodyWeb('Aritz')
                : l10n.ownGiftsAloneNoticeWeb('Aritz'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  group('los textos de la web no hablan del móvil propio', () {
    // Lo que en cada idioma nombra el propio móvil.
    const phoneWords = {
      'es': ['este móvil', 'Este móvil'],
      'ca': ['aquest mòbil', 'Aquest mòbil'],
      'en': ['this phone', 'This phone'],
    };
    const computerWords = {
      'es': 'ordenador',
      'ca': 'ordinador',
      'en': 'computer',
    };

    for (final locale in const ['es', 'ca', 'en']) {
      test(locale, () {
        final l10n = lookupAppLocalizations(Locale(locale));
        final web = <String>[
          secretBlockNoteText(l10n, web: true),
          secretBlockLabel(l10n, 'Nora', web: true),
          protectionReasonText(
            l10n,
            ProtectedPersonReason.ownGiftsHidden,
            'Aritz',
            web: true,
          ),
          protectionReasonText(
            l10n,
            ProtectedPersonReason.requiresV2,
            'Nora',
            web: true,
          ),
          giftNotSavedText(l10n, web: true),
          giftWriteResultText(l10n, GiftWriteResult.giftDeleted, web: true),
          giftWriteResultText(l10n, GiftWriteResult.giftUnavailable, web: true),
          l10n.manageLockedThisDeviceWeb,
          l10n.devicePersonBlockedThisTitleWeb('Aritz'),
          l10n.devicePersonBlockedThisBodyWeb('Aritz'),
          l10n.giftNoLongerVisibleWeb,
          l10n.giftOwnRequestRestrictedWeb,
          l10n.aboutPrivacyWeb,
        ];
        for (final text in web) {
          for (final word in phoneWords[locale]!) {
            expect(text, isNot(contains(word)), reason: text);
          }
        }
        // Lo que nombra el dispositivo dice «ordenador».
        for (final text in [
          web[0],
          web[2],
          web[4],
          web[6],
          ...web.sublist(7),
        ]) {
          expect(
            text.toLowerCase(),
            contains(computerWords[locale]),
            reason: text,
          );
        }
        // La versión nueva solo se arregla desde el móvil.
        expect(web[3], l10n.protectionReason_webUseMobile('Nora'));
        // Sin la web, lo de siempre.
        expect(secretBlockNoteText(l10n), l10n.secretBlockNote);
        expect(
          protectionReasonText(l10n, ProtectedPersonReason.requiresV2, 'Nora'),
          l10n.protectionReason_requiresV2('Nora'),
        );
        expect(
          giftWriteResultText(l10n, GiftWriteResult.giftDeleted),
          l10n.giftNotSaved,
        );
      });
    }
  });
}
