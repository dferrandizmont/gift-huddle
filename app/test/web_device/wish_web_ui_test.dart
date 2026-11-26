// ADR 0010 (1.0.7), revisión final: la web con su almacén REAL (`WebFamilyStore`
// sobre el motor W5 y el Worker falso). Un deseo de Nora que coge la web de
// Aritz tiene que seguirse por Persona, Ocasión y Búsqueda antes y después de
// cogerlo, y su fila tiene que abrir el plan y sus acciones (estado, editar,
// soltar) por el motor de la web, no por la proyección del móvil (que en la
// web está vacía).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/sync/wish_plan.dart';
import 'package:regalos/core/widgets/confirm_dialog.dart';
import 'package:regalos/core/widgets/gift_row.dart';
import 'package:regalos/core/widgets/gift_status_map.dart';
import 'package:regalos/core/widgets/pane_list_row.dart';
import 'package:regalos/core/widgets/status_checkbox.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/web_board/presentation/board_lanes_view.dart'
    show BoardLanesView;
import 'package:regalos/features/web_board/presentation/web_budget_page.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_controller.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;
import 'package:regalos/features/web_device/data/web_device_keys_store.dart';
import 'package:regalos/features/web_device/data/web_family_store.dart';

import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart' show FakePhone;
import '../helpers/screens.dart';
import 'presentation/gate_test_support.dart';
import 'web_engine_support.dart';
import 'web_secrets_test.dart' show protectNora;

WebHarness? _h;
bool _live = false;

WebHarness get _harness => _h!;

/// Lo que cambia la web (la sesión de verdad recarga el controlador al cambiar
/// el candidato del motor).
List<Override> _webOverrides() => [
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
  familyStoreProvider.overrideWith(
    (ref) => WebFamilyStore(_harness.vault, _harness.engine),
  ),
  deviceKeysStoreProvider.overrideWith(
    (ref) => WebDeviceKeysStore(_harness.vault),
  ),
  syncTransportProvider.overrideWithValue(null),
  syncV2TransportProvider.overrideWithValue(null),
  syncControllerProvider.overrideWith(() => WebSyncController(_harness.engine)),
  localRegistryViewProvider.overrideWith((ref) async {
    await ref.watch(familyControllerProvider.future);
    return _harness.engine.view;
  }),
  screenRegistryViewProvider.overrideWith(
    (ref) => ref
        .watch(familyControllerProvider)
        .whenData((_) => _harness.engine.screenView),
  ),
  webSyncEngineProvider.overrideWith((ref) => _harness.engine),
];

const _occasion = 'oc-kings';
const _budgetPlanId = 'budget-plan';
const _householdGiver = {
  'name': 'Aritz',
  'colorIndex': 0,
  'householdPays': true,
  'archived': false,
};

/// La web de Aritz con el deseo `w1` de Nora (Bicicleta roja, en Reyes)
/// publicado por el móvil de Aritz, y la persona de Nora protegida.
Future<void> _setup(
  WidgetTester tester,
  FakePhone phone, {
  bool withGift = true,
}) => tester.runAsync(() => _seedHarness(phone, withGift: withGift));

Future<void> _seedHarness(FakePhone phone, {required bool withGift}) async {
  _live = false;
  final h = WebHarness(
    webPerson: 'aritz',
    onChanged: () {
      if (!_live) return;
      unawaited(
        phone.container
            .read(familyControllerProvider.notifier)
            .reloadStoredCandidate()
            .catchError((Object _) {}),
      );
    },
  );
  _h = h;
  await h.setup();
  await protectNora(h);
  if (!withGift) {
    h.phone.scopes['nora'] = h.phone.scopes['nora']!.delete(
      h.phone.clock,
      Collections.gifts,
      's1',
    );
    h.phone.state = h.phone.state.copyWith(deferred: {'nora'});
  }
  h.phone.doc = h.phone.doc
      .set(h.phone.clock, Collections.occasions, _occasion, {
        'kind': 'custom',
        'name': 'Reyes',
        'month': 1,
        'day': 6,
        'recurring': true,
        'archived': false,
      })
      .set(h.phone.clock, Collections.wishes, 'w1', {
        'recipientId': 'nora',
        'authorPersonId': 'nora',
        'suggested': false,
        'title': 'Bicicleta roja',
        'occasionId': _occasion,
        'year': 2026,
      });
  await h.phone.engine(h.client).sync();
  await h.engine.sync();
}

Future<void> _buyWish(WebHarness h, int actualCents) async {
  final mobile = h.phone;
  final view = await mobile.view();
  final taken = mobile.scopes['nora']!.claimWish(
    mobile.clock,
    view,
    mobile.doc,
    'w1',
    planId: _budgetPlanId,
  );
  expect(taken.ok, isTrue, reason: '${taken.error}');
  final edited = taken.scope.editPlan(
    mobile.clock,
    view,
    _budgetPlanId,
    PrivatePlanPatch(actualCents: actualCents, status: GiftStatus.bought),
  );
  expect(edited.ok, isTrue, reason: '${edited.error}');
  mobile.scopes['nora'] = edited.scope;
  mobile.state = mobile.state.copyWith(deferred: {'nora'});
  await mobile.engine(h.client).sync();
  await h.engine.sync();
}

Future<void> _mount(WidgetTester tester, FakePhone phone) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: phone.container,
      child: const RegalosApp(webSession: true),
    ),
  );
  await settle(tester);
  _live = true;
}

/// La sesión de la web deja un temporizador de reposo: se suelta.
Future<void> _unmount(WidgetTester tester) async {
  _live = false;
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 10));
  _harness.close();
}

/// Lo que ve el motor de la web del plan de `w1`.
WishPlan? _enginePlan() => _harness.engine
    .wishPlanRows('nora')
    .expand((r) => r.plans)
    .where((p) => p.sourceWishId == 'w1')
    .firstOrNull;

Future<void> _closeSearch(WidgetTester tester) async {
  await tester.tap(find.text('Cancelar'));
  await settle(tester);
}

Future<void> _openSearch(WidgetTester tester, String query) async {
  await tester.tap(find.byTooltip('Buscar regalos'));
  await settle(tester);
  await tester.enterText(
    find.byKey(const ValueKey<String>('people-gift-search')),
    query,
  );
  await settle(tester);
}

void main() {
  setUpAll(loadInter);

  for (final (collision, giftDeleted, expectedCents) in [
    ('sin colisión', null, 2500),
    ('con una lápida de regalo', true, 2500),
    ('con un regalo vivo', false, 1700),
  ]) {
    screenTest(
      'Presupuesto web y móvil coinciden para un plan sin asignar $collision',
      (tester, phone) async {
        await _setup(tester, phone, withGift: false);
        final mobileBudget = await tester.runAsync(() async {
          final h = _harness;
          final mobile = h.phone;
          if (giftDeleted != null) {
            var scope = mobile.scopes['nora']!.set(
              mobile.clock,
              Collections.gifts,
              _budgetPlanId,
              {
                'recipientId': 'nora',
                'title': 'Libro',
                'status': 'bought',
                'year': 2026,
                'surprise': true,
                'occasionId': _occasion,
                'giverId': 'household',
                'actualCents': 1700,
              },
            );
            if (giftDeleted) {
              scope = scope.delete(
                mobile.clock,
                Collections.gifts,
                _budgetPlanId,
              );
            }
            mobile.scopes['nora'] = scope;
            mobile.doc = mobile.doc.set(
              mobile.clock,
              Collections.givers,
              'household',
              _householdGiver,
            );
          }
          await _buyWish(h, 2500);
          expect(_enginePlan()?.actualCents, 2500);
          expect(
            h.engine
                .scopeDocFor('nora')
                ?.record(Collections.gifts, _budgetPlanId)
                ?.isDeleted,
            giftDeleted,
          );
          final projection = await projectAuthorized(
            common: mobile.doc,
            slots: mobile.slotSet,
            keyring: mobile.keyring,
            view: await mobile.view(),
            localScopes: mobile.scopes,
          );
          expect(
            projection.view.planGiftIds,
            giftDeleted == false ? isEmpty : {_budgetPlanId},
          );
          return projection.view.budget();
        });
        await _mount(tester, phone);
        phone.container.read(routerProvider).go('/occasions/budget');
        await settle(tester);

        expect(find.byType(WebBudgetPage), findsOneWidget);
        final webBudget = phone.container.read(budgetProvider);
        expect(webBudget.ofRecipient('nora').plannedCents, expectedCents);
        expect(webBudget.ofOccasion(_occasion).spentCents, expectedCents);
        expect(webBudget.total, mobileBudget!.total);
        expect(webBudget.byOccasion, mobileBudget.byOccasion);
        expect(webBudget.byRecipient, mobileBudget.byRecipient);
        expect(webBudget.allGiftsByRecipient, mobileBudget.allGiftsByRecipient);
        expect(tester.takeException(), isNull);
        await _unmount(tester);
      },
      size: const Size(960, 900),
      overrides: _webOverrides(),
    );
  }

  test(
    'Presupuesto web excluye un plan sincronizado de una persona oculta',
    () async {
      final phone = FakePhone(extraOverrides: _webOverrides());
      addTearDown(phone.dispose);
      await _seedHarness(phone, withGift: false);
      final h = _harness;
      addTearDown(h.close);

      final mobile = h.phone;
      mobile.doc = mobile.doc
          .set(mobile.clock, Collections.givers, 'household', _householdGiver)
          .set(mobile.clock, Collections.occasions, _occasion, {
            'budgetCents': 10000,
          });
      for (final (id, title, price, occasionId) in [
        ('budgeted', 'Libro', 1500, _occasion),
        ('outside', 'Bufanda', 2000, null),
      ]) {
        mobile.doc = mobile.doc.set(mobile.clock, Collections.gifts, id, {
          'recipientId': 'leo',
          'title': title,
          'status': 'bought',
          'year': 2026,
          'surprise': false,
          'occasionId': occasionId,
          'giverId': 'household',
          'actualCents': price,
        });
      }
      await mobile.engine(h.client).sync();
      await h.engine.sync();
      // Simula el historial de la capa de pantalla con el ámbito abierto.
      h.engine.phonePeople = {...h.engine.phonePeople, 'nora'};
      expect(h.engine.screenHiddenPeople, contains('nora'));
      expect(h.engine.secrets.openedPeople, contains('nora'));
      expect(_enginePlan(), isNull);

      await phone.container.read(familyControllerProvider.future);
      final before = phone.container.read(budgetProvider);
      expect(before.total.spentCents, 3500);
      expect(before.budgeted.budgetCents, 10000);
      expect(before.budgeted.spentCents, 1500);
      expect(before.spentOutsideBudgetCents, 2000);
      expect(before.byRecipient.keys, ['leo']);
      expect(
        before.byOccasion.keys,
        unorderedEquals([_occasion, Budget.noOccasion]),
      );

      await _buyWish(h, 4000);
      h.engine.phonePeople = {...h.engine.phonePeople, 'nora'};
      await phone.container
          .read(familyControllerProvider.notifier)
          .reloadStoredCandidate();

      expect(h.engine.screenHiddenPeople, contains('nora'));
      final syncedPlans = phone.container
          .read(wishPlanStateRowsProvider('nora'))
          .expand((row) => row.plans);
      expect(syncedPlans.single.actualCents, 4000);
      final after = phone.container.read(budgetProvider);
      expect(after.total, before.total);
      expect(after.budgeted, before.budgeted);
      expect(after.spentOutsideBudgetCents, before.spentOutsideBudgetCents);
      expect(after.byRecipient, before.byRecipient);
      expect(after.allGiftsByRecipient, before.allGiftsByRecipient);
      expect(after.byOccasion, before.byOccasion);
    },
  );

  screenTest(
    'la fila clásica de Personas cuenta el único deseo cogido como regalo',
    (tester, phone) async {
      await _setup(tester, phone, withGift: false);
      await tester.runAsync(() async {
        final taken = await _harness.engine.claimWish('w1');
        expect(taken.ok, isTrue, reason: '${taken.error}');
      });
      await _mount(tester, phone);
      expect(find.byType(BoardLanesView), findsNothing);
      final nora = find.byWidgetPredicate(
        (widget) => widget is PaneListRow && widget.id == 'nora',
      );
      expect(nora, findsOneWidget);
      expect(
        find.descendant(of: nora, matching: find.text('1 regalo')),
        findsOneWidget,
      );
      await _unmount(tester);
    },
    size: const Size(960, 800),
    overrides: _webOverrides(),
  );

  // Segunda revisión final, 12: la ocasión del tablero de escritorio (desde
  // 1280) tiene que llevar los planes W5 igual que la lista estrecha.
  screenTest(
    '12: en 1280×800, la ocasión del tablero enseña el deseo que cogió la web '
    'en su carril y se puede abrir',
    (tester, phone) async {
      await _setup(tester, phone);
      await tester.runAsync(() async {
        final taken = await _harness.engine.claimWish('w1');
        expect(taken.error, isNull);
      });
      expect(_enginePlan(), isNotNull);
      await _mount(tester, phone);

      await tapText(tester, 'Ocasiones');
      await settle(tester);
      expect(find.byType(BoardLanesView), findsOneWidget);
      final card = find.descendant(
        of: find.byType(BoardLanesView),
        matching: find.text('Bicicleta roja'),
      );
      expect(card, findsOneWidget);

      // Y se abre como su plan (no como un regalo): «Deseo cogido».
      await tester.tap(card);
      await settle(tester);
      expect(find.text('Deseo cogido'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
    size: const Size(1280, 800),
    overrides: _webOverrides(),
  );

  screenTest(
    'el deseo, por Persona, Ocasión y Búsqueda, antes y después de cogerlo: '
    'la fila abre el plan y sus acciones van por el motor de la web',
    (tester, phone) async {
      await _setup(tester, phone);
      await _mount(tester, phone);

      // ANTES. Búsqueda: el deseo, libre.
      await _openSearch(tester, 'bici');
      expect(find.text('Bicicleta roja'), findsOneWidget);
      expect(find.text('Deseo'), findsOneWidget);
      expect(find.textContaining('Lo ha cogido'), findsNothing);
      expect(find.text('Lo has cogido tú'), findsNothing);
      await _closeSearch(tester);

      // ANTES. Ocasión: el deseo en la ficha de Nora.
      await tapText(tester, 'Ocasiones');
      await tapText(tester, 'Reyes');
      expect(find.text('Bicicleta roja'), findsOneWidget);
      expect(find.text('Deseo'), findsOneWidget);
      expect(find.text('Lo has cogido tú'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Volver a Ocasiones'));
      await settle(tester);
      await tapText(tester, 'Personas');

      // ANTES. Persona: el deseo libre, con «Lo regalo yo».
      await tapText(tester, 'Nora');
      expect(find.text('Bicicleta roja'), findsOneWidget);
      expect(find.text('Lo regalo yo'), findsOneWidget);

      // COGER (por el motor de la web).
      await tester.tap(find.text('Lo regalo yo'));
      await settle(tester);
      await settle(tester);
      final taken = _enginePlan();
      expect(taken, isNotNull, reason: 'el motor de la web tiene el plan');
      // DESPUÉS. Persona: una sola fila, ya como su plan.
      expect(find.text('Bicicleta roja'), findsOneWidget);
      expect(find.text('Lo regalo yo'), findsNothing);
      expect(find.text('Lo has cogido tú'), findsOneWidget);
      expect(find.text('Deseo'), findsOneWidget);

      // La casilla avanza el estado del plan por el motor de la web.
      final before = taken!.status;
      await tester.tap(
        find.descendant(
          of: find.byType(GiftRow),
          matching: find.byType(StatusCheckbox),
        ),
      );
      await settle(tester);
      await settle(tester);
      expect(_enginePlan()!.status, before.next);
      expect(tester.takeException(), isNull);

      // La fila abre el editor del plan (no uno de regalo): «Deseo cogido».
      await tester.tap(find.text('Bicicleta roja'));
      await settle(tester);
      expect(find.text('Deseo cogido'), findsOneWidget);
      // Editar: guardar una nota llega al motor.
      final notes = find.byType(TextField).last;
      await tester.scrollUntilVisible(
        notes,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(notes, 'Talla 20');
      // El aviso de «Comprado» se va antes de pulsar.
      await tester.pump(const Duration(seconds: 6));
      await settle(tester);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      await settle(tester);
      expect(_enginePlan()!.giverNote, 'Talla 20');

      await tester.tap(find.bySemanticsLabel('Volver a Personas'));
      await settle(tester);

      // DESPUÉS. Ocasión: el deseo cogido sigue ahí, con quién lo cogió.
      await tapText(tester, 'Ocasiones');
      await tapText(tester, 'Reyes');
      expect(find.text('Bicicleta roja'), findsWidgets);
      expect(find.text('Lo has cogido tú'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Volver a Ocasiones'));
      await settle(tester);

      // DESPUÉS. Búsqueda: sale una vez, con quién lo cogió.
      await tapText(tester, 'Personas');
      await _openSearch(tester, 'bici');
      expect(find.text('Bicicleta roja'), findsOneWidget);
      expect(find.text('Lo has cogido tú'), findsOneWidget);
      await _closeSearch(tester);

      // Lo que la web hizo queda en su cola privada hacia el móvil de Aritz
      // (la recogida del móvil ya la prueban las pruebas del motor).
      expect(_enginePlan()!.giverNote, 'Talla 20');

      // SOLTAR desde el editor del plan, por el motor.
      await tapText(tester, 'Nora');
      await tester.tap(find.text('Bicicleta roja'));
      await settle(tester);
      final soltar = find.text('Soltar');
      await tester.scrollUntilVisible(
        soltar,
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(soltar);
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(ConfirmDialog),
          matching: find.text('Soltar'),
        ),
      );
      await settle(tester);
      await settle(tester);
      expect(_enginePlan(), isNull);
      expect(find.text('Lo regalo yo'), findsOneWidget);
      expect(find.text('Lo has cogido tú'), findsNothing);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
    overrides: _webOverrides(),
  );
}
