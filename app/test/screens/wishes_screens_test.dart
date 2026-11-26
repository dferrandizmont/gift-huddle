// Las pantallas de los deseos propios (ADR 0010, fase 5): la lista de la
// persona con deseos y planes, el bloque fijo «Sorpresas», «Visible para», el
// buscador y las confirmaciones. Los datos entran por los providers de deseos
// y el servicio se sustituye por uno que apunta lo que se le pide.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/app.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart'
    show AuthorizedProjection, ProtectedPersonReason, SecretBlock;
import 'package:regalos/core/widgets/choice_grid.dart';
import 'package:regalos/features/family/presentation/giver_picker.dart'
    show GiverChip, GiverPicker;
import 'package:regalos/features/gifts/presentation/gift_editor_screen.dart'
    show GiftEditorScreen, giftEditorAsDialogProvider;
import 'package:regalos/core/sync/wish.dart';
import 'package:regalos/core/sync/wish_plan.dart';
import 'package:regalos/core/format/short_title.dart';
import 'package:regalos/core/theme/app_typography.dart';
import 'package:regalos/core/widgets/count_text.dart';
import 'package:regalos/core/theme/neutral_palette.dart';
import 'package:regalos/core/widgets/confirm_dialog.dart';
import 'package:regalos/core/widgets/empty_state.dart';
import 'package:regalos/core/widgets/wish_row.dart';
import 'package:regalos/core/widgets/gift_row.dart';
import 'package:regalos/core/widgets/regalos_switch.dart';
import 'package:regalos/core/widgets/status_checkbox.dart';
import 'package:regalos/features/family/presentation/reparto_grid.dart';
import 'package:regalos/features/family/presentation/reparto_sheet.dart'
    show kRepartoSheetKey;
import 'package:regalos/core/widgets/secret_block.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/application/gift_search.dart';
import 'package:regalos/features/family/application/wish_service.dart';
import 'package:regalos/features/gifts/presentation/person_list_screen.dart';
import 'package:regalos/features/gifts/presentation/wish_editor.dart';
import 'package:regalos/features/web_device/application/web_app_provider.dart';
import 'package:regalos/features/web_device/application/web_device_providers.dart';
import 'package:regalos/features/web_device/application/web_sync_engine.dart'
    show WebSyncStatus;
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fonts.dart';
import '../helpers/memory_stores.dart' show FakePhone;
import 'family_grid_test.dart' show openFamily;
import '../web_device/presentation/gate_test_support.dart';
import '../helpers/screens.dart';

const _wish = Wish(
  id: 'wbike',
  recipientId: 'nora',
  authorPersonId: 'nora',
  suggested: false,
  title: 'Bicicleta roja',
  year: 2026,
  size: '20',
  description: 'Con timbre',
);

/// Un deseo con todo lo que enseña el detalle: ocasión, talla, descripción y
/// enlace.
const _wishFull = Wish(
  id: 'wbike',
  recipientId: 'nora',
  authorPersonId: 'nora',
  suggested: false,
  title: 'Bicicleta roja',
  year: 2026,
  occasionId: 'seed-kings',
  size: '20',
  url: 'https://www.decathlon.es/es/p/bici',
  description: 'Con timbre',
);

const _wish2 = Wish(
  id: 'wbook',
  recipientId: 'nora',
  authorPersonId: 'aritz',
  suggested: true,
  title: 'Libro de volcanes',
  year: 2026,
);

WishPlan _plan(
  String id, {
  String claimant = 'aritz',
  GiftStatus status = GiftStatus.decided,
  String giver = 'us',
}) => WishPlan(
  planId: id,
  recipientId: 'nora',
  sourceWishId: 'wbike',
  claimantPersonId: claimant,
  title: 'Bicicleta roja',
  status: status,
  giverId: giver,
);

WishPlanRow _row(
  WishPlanState state, {
  List<WishPlan> plans = const [],
  Wish? wish = _wish,
}) => WishPlanRow(
  recipientId: 'nora',
  sourceWishId: 'wbike',
  state: state,
  plans: plans,
  wish: wish,
);

/// Un servicio de deseos que apunta lo que se le pide y responde con [next].
class _FakeWishService implements WishService {
  final List<String> calls = [];
  final List<PrivatePlanPatch> planPatches = [];
  final List<VisibleWishPatch> suggestPatches = [];
  WishResult next = const WishResult.ok();

  @override
  bool get canSuggest => true;

  @override
  bool get canConvertPlan => true;

  Future<WishResult> _do(String call) async {
    calls.add(call);
    return next;
  }

  @override
  Future<WishResult> createOwn(VisibleWishPatch patch) =>
      _do('create:${patch.title}');

  @override
  Future<WishResult> suggest(String recipientId, VisibleWishPatch patch) {
    suggestPatches.add(patch);
    return _do('suggest:$recipientId:${patch.title}:${patch.year}');
  }

  @override
  Future<WishResult> edit(String wishId, VisibleWishPatch patch) =>
      _do('edit:$wishId:${patch.title}');

  @override
  Future<WishResult> remove(String wishId) => _do('remove:$wishId');

  @override
  Future<WishResult> claim(String wishId, {String? giverId}) =>
      _do('claim:$wishId');

  @override
  Future<WishResult> editPlan(
    String person,
    String planId,
    PrivatePlanPatch patch,
  ) {
    planPatches.add(patch);
    return _do('editPlan:$person:$planId');
  }

  @override
  Future<WishResult> releasePlan(String person, String planId) =>
      _do('release:$person:$planId');

  @override
  Future<WishResult> deletePlan(String person, String planId) =>
      _do('deletePlan:$person:$planId');

  @override
  Future<WishResult> convertPlan(
    String person,
    String planId, {
    required int year,
    String? occasionId,
  }) => _do('convert:$person:$planId');
}

List<Override> _overrides(
  _FakeWishService service, {
  required String reader,
  List<Wish> wishes = const [_wish],
  List<WishPlanRow> rows = const [],
  Map<String, List<WishPlan>> plans = const {},
  bool own = false,
}) => [
  wishServiceProvider.overrideWithValue(service),
  wishReaderProvider.overrideWithValue(reader),
  visibleWishesForProvider.overrideWith(
    (ref, person) => [
      for (final w in wishes)
        if (w.recipientId == person) w,
    ],
  ),
  wishPlanRowsProvider.overrideWith(
    (ref, person) => [
      for (final r in rows)
        if (r.recipientId == person) r,
    ],
  ),
  projectedPlansByWishProvider.overrideWithValue(plans),
  if (own) ...[
    ownHiddenPeopleProvider.overrideWithValue({reader}),
    secretBlocksProvider.overrideWithValue([SecretBlock(reader)]),
  ],
];

/// Los regalos que son los planes de [_wish] para Nora (los trae la
/// proyección del móvil).
Future<void> _seedPlanGifts(
  WidgetTester tester,
  FakePhone phone,
  List<String> ids, {
  String? occasion,
  String giver = 'us',
  bool surprise = false,
}) async {
  await tester.runAsync(() async {
    for (final id in ids) {
      await familyOf(phone).upsertGift(
        Gift(
          id: id,
          recipientId: 'nora',
          title: 'Bicicleta roja',
          occasionId: occasion,
          giverId: giver,
          status: GiftStatus.decided,
          rawStatus: 'decided',
          plannedCents: 4000,
          surprise: surprise,
          year: 2026,
        ),
      );
    }
  });
}

/// Lleva [target] a la vista dentro del editor abierto (la lista del editor
/// acaba justo encima del botón «Guardar»).
Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.byType(Scrollable).last,
  );
  await settle(tester);
}

Future<void> _openNoraWithPlans(
  WidgetTester tester,
  FakePhone phone,
  List<String> plans, {
  bool surprise = false,
}) async {
  await seedSample(tester, phone);
  await _seedPlanGifts(tester, phone, plans, surprise: surprise);
  await pumpRegalos(tester, phone);
  await tester.ensureVisible(find.text('Nora').first);
  await tester.pump();
  await tapText(tester, 'Nora');
}

Future<void> _openNora(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone);
  await pumpRegalos(tester, phone);
  // Con letra grande la fila de Nora queda por debajo de la pantalla.
  await tester.ensureVisible(find.text('Nora').first);
  await tester.pump();
  await tapText(tester, 'Nora');
}

const _ownNote =
    'En este móvil no se ven los regalos para Nora. Solo otra persona de la '
    'familia puede cambiarlo, desde su móvil.';

/// Las filas de deseos que se pueden cambiar con la prueba en marcha (para
/// quitar el derecho al bloque con un editor abierto).
List<WishPlanRow> _holderInitial = const [];

class _RowsHolder extends Notifier<List<WishPlanRow>> {
  @override
  List<WishPlanRow> build() => _holderInitial;

  void set(List<WishPlanRow> rows) => state = rows;
}

final _rowsHolder = NotifierProvider<_RowsHolder, List<WishPlanRow>>(
  _RowsHolder.new,
);

/// Si la proyección autorizada se está recalculando (dudosa) en la prueba.
class _Uncertain extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final _uncertain = NotifierProvider<_Uncertain, bool>(_Uncertain.new);

/// Una proyección que se queda «cargando» mientras [_uncertain] está
/// encendido y, si no, se resuelve sin nada.
final _uncertainProjection = authorizedProjectionProvider.overrideWith((
  ref,
) async {
  if (ref.watch(_uncertain)) {
    await Completer<void>().future;
  }
  return null;
});

/// Como [_overrides], pero las filas de planes salen de [_rowsHolder] y los
/// planes de la proyección son los de [_holderInitial].
List<Override> _holderOverrides(
  _FakeWishService service, {
  required String reader,
  String planGiver = 'us',
}) => [
  wishServiceProvider.overrideWithValue(service),
  wishReaderProvider.overrideWithValue(reader),
  visibleWishesForProvider.overrideWith(
    (ref, person) => person == 'nora' ? const [_wish] : const <Wish>[],
  ),
  wishPlanRowsProvider.overrideWith(
    (ref, person) => [
      for (final r in ref.watch(_rowsHolder))
        if (r.recipientId == person) r,
    ],
  ),
  projectedPlansByWishProvider.overrideWith(
    (ref) => {
      'wbike': [_plan('p1', giver: planGiver)],
    },
  ),
];

void main() {
  setUpAll(loadInter);

  group('en el móvil de la propia persona', () {
    final service = _FakeWishService();

    screenTest(
      've su deseo con la etiqueta, sin estado ni acciones de otros, y el '
      'bloque fijo «Sorpresas» con su frase',
      (tester, phone) async {
        await _openNora(tester, phone);
        expect(find.text('Bicicleta roja'), findsOneWidget);
        expect(find.text('Libro de volcanes'), findsOneWidget);
        expect(find.text('Deseo'), findsNWidgets(2));
        // Nada de lo que hacen los demás.
        expect(find.text('Lo regalo yo'), findsNothing);
        expect(find.text('Nadie lo ha cogido'), findsNothing);
        expect(find.textContaining('Lo ha cogido'), findsNothing);
        // El bloque fijo se llama «Sorpresas», conserva su frase y no cuenta
        // nada.
        expect(find.text('Sorpresas'), findsOneWidget);
        expect(find.text(_ownNote), findsOneWidget);
        expect(find.textContaining('Regalos en secreto'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(SecretBlockCard),
            matching: find.textContaining(RegExp(r'\d')),
          ),
          findsNothing,
        );
        expect(find.byTooltip('Añadir deseo'), findsOneWidget);
        expect(find.byTooltip('Añadir regalo'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        service,
        reader: 'nora',
        wishes: const [_wish, _wish2],
        own: true,
      ),
    );

    screenTest(
      'el bloque «Sorpresas» está aunque no haya ningún deseo, y la lista '
      'vacía lo explica',
      (tester, phone) async {
        await _openNora(tester, phone);
        expect(find.text('Sorpresas'), findsOneWidget);
        expect(find.text('Aún no has apuntado ningún deseo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        service,
        reader: 'nora',
        wishes: const [],
        own: true,
      ),
    );

    screenTest(
      'apuntar un deseo: el «+» abre el editor y guarda por el servicio',
      (tester, phone) async {
        service.calls.clear();
        await _openNora(tester, phone);
        await tester.tap(find.byTooltip('Añadir deseo'));
        await settle(tester);
        expect(find.text('Nuevo deseo'), findsOneWidget);
        // Sin título no se guarda nada y se dice.
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(service.calls, isEmpty);
        expect(find.text('Escribe qué regalo es.'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Patines');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(service.calls, ['create:Patines']);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        service,
        reader: 'nora',
        wishes: const [],
        own: true,
      ),
    );
  });

  group('editar y quitar un deseo propio', () {
    final service = _FakeWishService();
    final overrides = _overrides(
      service,
      reader: 'nora',
      wishes: const [_wish],
      own: true,
    );

    screenTest('tocar el deseo lo abre; guardar llama a editar', (
      tester,
      phone,
    ) async {
      service.calls.clear();
      await _openNora(tester, phone);
      await tester.tap(find.text('Bicicleta roja'));
      await settle(tester);
      expect(find.text('Editar deseo'), findsOneWidget);
      expect(find.text('Con timbre'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Bicicleta azul');
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(service.calls, ['edit:wbike:Bicicleta azul']);
    }, overrides: overrides);

    screenTest('quitar un deseo pide confirmación; cancelar no hace nada', (
      tester,
      phone,
    ) async {
      service.calls.clear();
      await _openNora(tester, phone);
      await tester.tap(find.text('Bicicleta roja'));
      await settle(tester);
      final quitar = find.text('Quitar de mi lista');
      await _reveal(tester, quitar);
      await tester.tap(quitar);
      await settle(tester);
      expect(find.byType(ConfirmDialog), findsOneWidget);
      expect(
        find.text('¿Quitar «Bicicleta roja» de tu lista?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar').last);
      await settle(tester);
      expect(service.calls, isEmpty);
      // Confirmar sí lo quita.
      await tester.tap(quitar);
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(ConfirmDialog),
          matching: find.text('Quitar'),
        ),
      );
      await settle(tester);
      expect(service.calls, ['remove:wbike']);
    }, overrides: overrides);

    screenTest('un error del servicio se dice con su texto corto', (
      tester,
      phone,
    ) async {
      service.calls.clear();
      service.next = const WishResult.failed(WishProblem.capReached);
      addTearDown(() => service.next = const WishResult.ok());
      await _openNora(tester, phone);
      await tester.tap(find.text('Bicicleta roja'));
      await settle(tester);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(
        find.text(
          'Ya hay 200 deseos en esta lista. Quita alguno para añadir otro.',
        ),
        findsWidgets,
      );
      // El editor sigue abierto: no se pierde lo escrito.
      expect(find.text('Editar deseo'), findsOneWidget);
    }, overrides: overrides);
  });

  group('los demás ven el estado y las acciones', () {
    screenTest(
      'un deseo libre: etiqueta, «Nadie lo ha cogido» y «Lo regalo yo»',
      (tester, phone) async {
        await _openNora(tester, phone);
        expect(find.text('Bicicleta roja'), findsOneWidget);
        expect(find.text('Deseo'), findsOneWidget);
        // Con el botón no hay «Nadie lo ha cogido»: el botón ya lo dice.
        expect(find.text('Nadie lo ha cogido'), findsNothing);
        expect(find.text('Lo regalo yo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        rows: [_row(WishPlanState.available)],
      ),
    );

    final claimService = _FakeWishService();
    screenTest(
      '«Lo regalo yo» pide coger el deseo al servicio',
      (tester, phone) async {
        claimService.calls.clear();
        await _openNora(tester, phone);
        await tester.tap(find.text('Lo regalo yo'));
        await settle(tester);
        expect(claimService.calls, ['claim:wbike']);
        expect(find.text('Has cogido «Bicicleta roja»'), findsOneWidget);
      },
      overrides: _overrides(
        claimService,
        reader: 'aritz',
        rows: [_row(WishPlanState.available)],
      ),
    );

    final failing = _FakeWishService()
      ..next = const WishResult.failed(WishProblem.alreadyClaimed);
    screenTest(
      'coger un deseo que otra persona acaba de coger dice «Otra persona ya '
      'lo ha cogido»',
      (tester, phone) async {
        await _openNora(tester, phone);
        await tester.tap(find.text('Lo regalo yo'));
        await settle(tester);
        expect(find.text('Otra persona ya lo ha cogido.'), findsOneWidget);
      },
      overrides: _overrides(
        failing,
        reader: 'aritz',
        rows: [_row(WishPlanState.available)],
      ),
    );

    screenTest(
      'un deseo cogido sale una vez, como su regalo, con «Deseo» y quién lo '
      'cogió',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1']);
        expect(find.text('Bicicleta roja'), findsOneWidget);
        expect(find.text('Deseo'), findsOneWidget);
        expect(find.text('Lo has cogido tú'), findsOneWidget);
        expect(find.text('Lo regalo yo'), findsNothing);
        expect(find.text('Nadie lo ha cogido'), findsNothing);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        rows: [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );

    screenTest(
      'un deseo cogido por otra persona dice quién',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1']);
        expect(find.text('Lo ha cogido Aritz'), findsOneWidget);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'leo',
        rows: [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );

    screenTest(
      'dos personas lo cogieron: aviso claro en las dos filas',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1', 'p2']);
        expect(
          find.text('Dos personas lo han cogido. Que una lo suelte.'),
          findsNWidgets(2),
        );
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        rows: [
          _row(
            WishPlanState.conflictingClaims,
            plans: [
              _plan('p1'),
              _plan('p2', claimant: 'leo'),
            ],
          ),
        ],
        plans: {
          'wbike': [_plan('p1'), _plan('p2', claimant: 'leo')],
        },
      ),
    );

    screenTest(
      '«Nora lo quitó de su lista» cuando se quitó un deseo ya cogido',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1']);
        expect(find.text('Nora lo quitó de su lista'), findsOneWidget);
        expect(find.text('Lo regalo yo'), findsNothing);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        wishes: const [],
        rows: [
          _row(WishPlanState.removedFromList, plans: [_plan('p1')], wish: null),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );
  });

  group('el detalle de un deseo', () {
    final service = _FakeWishService();
    // Una hoja que mide lo que contiene: el asa y el contenido, no la pantalla.
    final sheet = find.byType(BottomSheet);
    // El botón del detalle, no el de la fila que queda detrás (también es un
    // FilledButton tonal con el mismo texto).
    Finder claim([Finder? within]) => find.descendant(
      of: within ?? sheet,
      matching: find.widgetWithText(FilledButton, 'Lo regalo yo'),
    );

    /// Abre el detalle del deseo de Nora tal como lo abre la lista de otra
    /// persona, sin pasar por la lista (la de quien lo ve a través de un móvil
    /// que no abre el bloque no lo enseña).
    Future<void> openDetail(WidgetTester tester) async {
      final context = tester.element(find.byType(Scaffold).first);
      unawaited(openWishDetail(context, person: 'nora', wishId: 'wbike'));
      await settle(tester);
    }

    screenTest(
      'dice la ocasión, la talla, la descripción, el enlace y que nadie lo ha '
      'cogido, y «Lo regalo yo» es la acción principal',
      (tester, phone) async {
        service.calls.clear();
        await _openNora(tester, phone);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        expect(sheet, findsOneWidget);
        for (final text in [
          'Bicicleta roja',
          'Deseo',
          'Nora',
          'Estado',
          'Nadie lo ha cogido',
          'Ocasión',
          'Talla o edad',
          '20',
          'Descripción',
          'Con timbre',
          'Abrir enlace: decathlon.es',
        ]) {
          expect(
            find.descendant(of: sheet, matching: find.text(text)),
            findsOneWidget,
            reason: text,
          );
        }
        expect(
          find.descendant(of: sheet, matching: find.textContaining('Reyes')),
          findsOneWidget,
        );
        // Mide lo que contiene, no la pantalla entera.
        expect(tester.getSize(sheet).height, lessThan(600));
        // La acción principal, a lo ancho.
        expect(tester.getSize(claim()).width, greaterThan(300));
        await tester.tap(claim());
        await settle(tester);
        expect(service.calls, ['claim:wbike']);
        expect(sheet, findsNothing);
        expect(find.text('Has cogido «Bicicleta roja»'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        service,
        reader: 'aritz',
        wishes: const [_wishFull],
        rows: [_row(WishPlanState.available, wish: _wishFull)],
      ),
    );

    screenTest(
      'un deseo con lo mínimo no deja huecos: título, estado y el botón',
      (tester, phone) async {
        await _openNora(tester, phone);
        await tester.tap(find.text('Libro de volcanes'));
        await settle(tester);
        expect(sheet, findsOneWidget);
        expect(
          find.descendant(of: sheet, matching: find.text('Nadie lo ha cogido')),
          findsOneWidget,
        );
        for (final label in ['Ocasión', 'Talla o edad', 'Descripción']) {
          expect(
            find.descendant(of: sheet, matching: find.text(label)),
            findsNothing,
            reason: label,
          );
        }
        expect(tester.getSize(sheet).height, lessThan(380));
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        wishes: const [_wish2],
        rows: [
          WishPlanRow(
            recipientId: 'nora',
            sourceWishId: 'wbook',
            state: WishPlanState.available,
            plans: const [],
            wish: _wish2,
          ),
        ],
      ),
    );

    screenTest(
      'privacidad: en el móvil de la propia persona no hay estado ni «Lo '
      'regalo yo», y nunca dice quién lo ha cogido',
      (tester, phone) async {
        await _openNora(tester, phone);
        await openDetail(tester);
        expect(sheet, findsOneWidget);
        expect(
          find.descendant(of: sheet, matching: find.text('Bicicleta roja')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sheet, matching: find.text('Con timbre')),
          findsOneWidget,
        );
        for (final text in [
          'Estado',
          'Nadie lo ha cogido',
          'Lo regalo yo',
          'Lo ha cogido Aritz',
          'Lo has cogido tú',
        ]) {
          expect(find.text(text), findsNothing, reason: text);
        }
        // Solo se puede cerrar.
        expect(
          find.descendant(
            of: sheet,
            matching: find.widgetWithText(TextButton, 'Cerrar'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        service,
        reader: 'nora',
        wishes: const [_wishFull],
        own: true,
      ),
    );

    screenTest(
      'un móvil que no abre el bloque de la persona no ve estado ni acción',
      (tester, phone) async {
        await _openNora(tester, phone);
        await openDetail(tester);
        expect(sheet, findsOneWidget);
        expect(find.text('Estado'), findsNothing);
        expect(find.text('Nadie lo ha cogido'), findsNothing);
        expect(find.text('Lo regalo yo'), findsNothing);
        expect(
          find.descendant(of: sheet, matching: find.text('Con timbre')),
          findsOneWidget,
        );
      },
      overrides: _overrides(
        service,
        reader: 'aritz',
        wishes: const [_wishFull],
      ),
    );

    screenTest(
      'si otra persona lo ha cogido lo dice, y no ofrece cogerlo',
      (tester, phone) async {
        await _openNora(tester, phone);
        await openDetail(tester);
        expect(find.text('Lo ha cogido Leo'), findsOneWidget);
        expect(find.text('Lo regalo yo'), findsNothing);
      },
      overrides: _overrides(
        service,
        reader: 'aritz',
        wishes: const [_wishFull],
        rows: [
          _row(
            WishPlanState.claimed,
            plans: [_plan('p1', claimant: 'leo')],
            wish: _wishFull,
          ),
        ],
        plans: {
          'wbike': [_plan('p1', claimant: 'leo')],
        },
      ),
    );

    screenTest(
      'con letra al doble no desborda y el botón sigue a mano',
      (tester, phone) async {
        await _openNora(tester, phone);
        await openDetail(tester);
        expect(sheet, findsOneWidget);
        expect(claim(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      textScale: 2,
      overrides: _overrides(
        service,
        reader: 'aritz',
        wishes: const [_wishFull],
        rows: [_row(WishPlanState.available, wish: _wishFull)],
      ),
    );

    screenTest(
      'en la web de escritorio es un diálogo, con el mismo contenido',
      (tester, phone) async {
        await _openNora(tester, phone);
        await openDetail(tester);
        expect(sheet, findsNothing);
        // La lista de detrás dice «Nadie lo ha cogido» y la talla; el diálogo,
        // además, el estado, la descripción y el botón principal.
        final dialog = find.byType(WishDetail);
        expect(dialog, findsOneWidget);
        expect(
          find.descendant(
            of: dialog,
            matching: find.text('Nadie lo ha cogido'),
          ),
          findsOneWidget,
        );
        expect(find.text('Estado'), findsOneWidget);
        expect(find.text('Con timbre'), findsWidgets);
        expect(claim(dialog), findsOneWidget);
      },
      size: const Size(1536, 864),
      overrides: [
        ..._overrides(
          service,
          reader: 'aritz',
          wishes: const [_wishFull],
          rows: [_row(WishPlanState.available, wish: _wishFull)],
        ),
        giftEditorAsDialogProvider.overrideWithValue(true),
      ],
    );
  });

  group('el plan de un deseo cogido', () {
    final service = _FakeWishService();

    screenTest(
      'tocar la fila abre el plan; soltar pide confirmación',
      (tester, phone) async {
        service.calls.clear();
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        expect(find.text('Deseo cogido'), findsOneWidget);
        final soltar = find.text('Soltar');
        await _reveal(tester, soltar);
        await tester.tap(soltar);
        await settle(tester);
        expect(find.byType(ConfirmDialog), findsOneWidget);
        expect(find.text('¿Soltar «Bicicleta roja»?'), findsOneWidget);
        await tester.tap(find.text('Cancelar').last);
        await settle(tester);
        expect(service.calls, isEmpty);
        await tester.tap(soltar);
        await settle(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(ConfirmDialog),
            matching: find.text('Soltar'),
          ),
        );
        await settle(tester);
        expect(service.calls, ['release:nora:p1']);
        expect(find.text('Lo has soltado'), findsOneWidget);
      },
      overrides: _overrides(
        service,
        reader: 'aritz',
        rows: [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );

    screenTest(
      'guardar lo suyo llama a editar el plan; convertir en sorpresa pide '
      'confirmación',
      (tester, phone) async {
        service.calls.clear();
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(service.calls, ['editPlan:nora:p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        final convertir = find.text('Convertir en sorpresa');
        await _reveal(tester, convertir);
        await tester.tap(convertir);
        await settle(tester);
        expect(find.byType(ConfirmDialog), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(ConfirmDialog),
            matching: find.text('Convertir'),
          ),
        );
        await settle(tester);
        expect(service.calls.last, 'convert:nora:p1');
      },
      overrides: _overrides(
        service,
        reader: 'aritz',
        rows: [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );

    final removedService = _FakeWishService();
    screenTest(
      'si Nora lo quitó, se puede borrar la reserva con confirmación',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        final borrar = find.text('Eliminar mi reserva');
        await _reveal(tester, borrar);
        await tester.tap(borrar);
        await settle(tester);
        expect(
          find.text('¿Eliminar tu reserva de «Bicicleta roja»?'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancelar').last);
        await settle(tester);
        expect(removedService.calls, isEmpty);
        await tester.tap(borrar);
        await settle(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(ConfirmDialog),
            matching: find.text('Eliminar'),
          ),
        );
        await settle(tester);
        expect(removedService.calls, ['deletePlan:nora:p1']);
      },
      overrides: _overrides(
        removedService,
        reader: 'aritz',
        wishes: const [],
        rows: [
          _row(WishPlanState.removedFromList, plans: [_plan('p1')], wish: null),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );

    final conflictService = _FakeWishService();
    screenTest(
      'con dos reservas, el plan explica el conflicto y deja soltar',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1', 'p2']);
        await tester.tap(find.text('Bicicleta roja').first);
        await settle(tester);
        expect(find.text('Deseo cogido'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(WishPlanEditor),
            matching: find.text(
              'Dos personas lo han cogido. Que una lo suelte.',
            ),
          ),
          findsOneWidget,
        );
      },
      overrides: _overrides(
        conflictService,
        reader: 'aritz',
        rows: [
          _row(
            WishPlanState.conflictingClaims,
            plans: [
              _plan('p1'),
              _plan('p2', claimant: 'leo'),
            ],
          ),
        ],
        plans: {
          'wbike': [_plan('p1'), _plan('p2', claimant: 'leo')],
        },
      ),
    );
  });

  group('«Visible para»', () {
    final service = _FakeWishService();
    final overrides = [
      wishServiceProvider.overrideWithValue(service),
      wishReaderProvider.overrideWithValue('aritz'),
      canSuggestWishProvider.overrideWith((ref, id) => id == 'nora'),
    ];

    screenTest('para quien tiene móvil sale apagado y guarda un deseo', (
      tester,
      phone,
    ) async {
      service.calls.clear();
      await _openNora(tester, phone);
      await tester.tap(find.byTooltip('Añadir regalo'));
      await settle(tester);
      expect(find.text('Visible para Nora'), findsOneWidget);
      final switchRow = find.byKey(
        const ValueKey<String>('gift-visible-switch'),
      );
      expect(switchRow, findsOneWidget);
      expect(
        tester
            .widget<RegalosSwitch>(
              find.descendant(
                of: switchRow,
                matching: find.byType(RegalosSwitch),
              ),
            )
            .value,
        isFalse,
      );
      await tester.enterText(find.byType(TextField).first, 'Patines');
      await tester.tap(switchRow);
      await settle(tester);
      expect(
        tester
            .widget<RegalosSwitch>(
              find.descendant(
                of: switchRow,
                matching: find.byType(RegalosSwitch),
              ),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(service.calls, ['suggest:nora:Patines:2026']);
    }, overrides: overrides);

    screenTest('apagado, el regalo se guarda como siempre (sorpresa)', (
      tester,
      phone,
    ) async {
      service.calls.clear();
      await _openNora(tester, phone);
      await tester.tap(find.byTooltip('Añadir regalo'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Patines');
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(service.calls, isEmpty);
      expect(find.text('Patines'), findsOneWidget);
    }, overrides: overrides);

    screenTest('para quien no tiene móvil (Leo) no hay nada nuevo', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapText(tester, 'Leo');
      await tester.tap(find.byTooltip('Añadir regalo'));
      await settle(tester);
      expect(find.textContaining('Visible para'), findsNothing);
      expect(tester.takeException(), isNull);
    }, overrides: overrides);
  });

  group('buscador', () {
    screenTest(
      'sale una fila por deseo, con su etiqueta y la persona',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.byTooltip('Buscar regalos'));
        await settle(tester);
        await tester.enterText(
          find.byKey(const ValueKey<String>('people-gift-search')),
          'bici',
        );
        await settle(tester);
        expect(find.text('Bicicleta roja'), findsOneWidget);
        expect(find.text('Deseo'), findsOneWidget);
        expect(find.text('Nora'), findsWidgets);
        // Tocar el deseo de otra persona lo abre para leerlo y cogerlo.
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        expect(find.text('Lo regalo yo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: [
        ..._overrides(
          _FakeWishService(),
          reader: 'aritz',
          rows: [_row(WishPlanState.available)],
        ),
        searchResultsProvider.overrideWith(
          (ref, q) => const SearchResults(gifts: [], wishes: [_wish]),
        ),
      ],
    );
  });

  group('no desborda', () {
    for (final (scale, dark) in [(2.0, false), (1.0, true), (2.0, true)]) {
      screenTest(
        'la persona de este móvil: letra $scale, oscuro $dark',
        (tester, phone) async {
          await _openNora(tester, phone);
          expect(find.text('Sorpresas'), findsOneWidget);
          await tester.tap(find.text('Bicicleta roja'));
          await settle(tester);
          expect(find.text('Editar deseo'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        textScale: scale,
        brightness: dark ? Brightness.dark : Brightness.light,
        overrides: _overrides(
          _FakeWishService(),
          reader: 'nora',
          wishes: const [_wish, _wish2],
          own: true,
        ),
      );
      screenTest(
        'quien lo coge: letra $scale, oscuro $dark',
        (tester, phone) async {
          await _openNoraWithPlans(tester, phone, ['p1', 'p2']);
          await _reveal(tester, find.text('Libro de volcanes'));
          expect(find.text('Libro de volcanes'), findsOneWidget);
          await tester.ensureVisible(find.text('Bicicleta roja').first);
          await settle(tester);
          await tester.tap(find.text('Bicicleta roja').first);
          await settle(tester);
          expect(find.text('Deseo cogido'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        textScale: scale,
        brightness: dark ? Brightness.dark : Brightness.light,
        overrides: _overrides(
          _FakeWishService(),
          reader: 'aritz',
          wishes: const [_wish, _wish2],
          rows: [
            _row(
              WishPlanState.conflictingClaims,
              plans: [
                _plan('p1'),
                _plan('p2', claimant: 'leo'),
              ],
            ),
            WishPlanRow(
              recipientId: 'nora',
              sourceWishId: 'wbook',
              state: WishPlanState.available,
              plans: const [],
              wish: _wish2,
            ),
          ],
          plans: {
            'wbike': [_plan('p1'), _plan('p2', claimant: 'leo')],
          },
        ),
      );
    }
  });

  group('tableta, horizontal y escritorio', () {
    for (final (name, size) in [
      ('tableta 800', const Size(800, 1280)),
      ('horizontal 1280', const Size(1280, 800)),
      ('escritorio 1536', const Size(1536, 864)),
    ]) {
      screenTest(
        'la persona de este dispositivo en $name: bloque, deseos y botón',
        (tester, phone) async {
          await _openNora(tester, phone);
          // Con dos paneles, la fila de la lista también lleva su franja.
          expect(
            find.descendant(
              of: find.byType(PersonListScreen),
              matching: find.text('Sorpresas'),
            ),
            findsOneWidget,
          );
          expect(find.text('Bicicleta roja'), findsOneWidget);
          expect(find.text('Lo regalo yo'), findsNothing);
          // Con dos paneles, «Añadir deseo» va en la cabecera; si no, el «+».
          expect(
            find
                    .byKey(const ValueKey<String>('add-wish-header'))
                    .evaluate()
                    .length +
                find.byTooltip('Añadir deseo').evaluate().length,
            1,
          );
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: _overrides(
          _FakeWishService(),
          reader: 'nora',
          wishes: const [_wish, _wish2],
          own: true,
        ),
      );
      screenTest(
        'quien abre el bloque en $name: estado y acción',
        (tester, phone) async {
          await _openNora(tester, phone);
          expect(find.text('Nadie lo ha cogido'), findsNothing);
          expect(find.text('Lo regalo yo'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: _overrides(
          _FakeWishService(),
          reader: 'aritz',
          rows: [_row(WishPlanState.available)],
        ),
      );
    }

    screenTest(
      'en escritorio, un deseo cogido y uno quitado salen como filas '
      'de la tabla',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1']);
        expect(find.text('Deseo'), findsOneWidget);
        expect(find.text('Nora lo quitó de su lista'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1536, 864),
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        wishes: const [],
        rows: [
          _row(WishPlanState.removedFromList, plans: [_plan('p1')], wish: null),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );
  });

  group('idiomas y movimiento reducido', () {
    for (final (lang, surprises, wish, add) in [
      ('ca', 'Sorpreses', 'Desig', 'Afegir un desig'),
      ('en', 'Surprises', 'Wish', 'Add wish'),
    ]) {
      screenTest(
        'la persona de este dispositivo en $lang',
        (tester, phone) async {
          tester.platformDispatcher.localesTestValue = [Locale(lang)];
          tester.platformDispatcher.localeTestValue = Locale(lang);
          await _openNora(tester, phone);
          expect(find.text(surprises), findsOneWidget);
          expect(find.text(wish), findsOneWidget);
          expect(find.byTooltip(add), findsOneWidget);
          await tester.tap(find.text('Bicicleta roja'));
          await settle(tester);
          expect(tester.takeException(), isNull);
        },
        textScale: 2,
        overrides: _overrides(_FakeWishService(), reader: 'nora', own: true),
      );
      screenTest(
        'quien lo coge en $lang: conflicto y plan',
        (tester, phone) async {
          tester.platformDispatcher.localesTestValue = [Locale(lang)];
          tester.platformDispatcher.localeTestValue = Locale(lang);
          await _openNoraWithPlans(tester, phone, ['p1', 'p2']);
          final l10n = lookupAppLocalizations(Locale(lang));
          expect(find.text(l10n.wishConflict), findsNWidgets(2));
          await tester.ensureVisible(find.text('Bicicleta roja').first);
          await settle(tester);
          await tester.tap(find.text('Bicicleta roja').first);
          await settle(tester);
          expect(find.text(l10n.wishPlanTitle), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        textScale: 2,
        overrides: _overrides(
          _FakeWishService(),
          reader: 'aritz',
          rows: [
            _row(
              WishPlanState.conflictingClaims,
              plans: [
                _plan('p1'),
                _plan('p2', claimant: 'leo'),
              ],
            ),
          ],
          plans: {
            'wbike': [_plan('p1'), _plan('p2', claimant: 'leo')],
          },
        ),
      );
    }

    screenTest('con movimiento reducido todo sigue funcionando', (
      tester,
      phone,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await _openNora(tester, phone);
      expect(find.text('Sorpresas'), findsOneWidget);
      await tester.tap(find.text('Bicicleta roja'));
      await settle(tester);
      expect(find.text('Editar deseo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, overrides: _overrides(_FakeWishService(), reader: 'nora', own: true));
  });

  group('la web', () {
    List<Override> web() => [
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

    Future<void> mountNora(WidgetTester tester, FakePhone phone) async {
      await seedSample(tester, phone);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: phone.container,
          child: const RegalosApp(webSession: true),
        ),
      );
      await settle(tester);
      await tapText(tester, 'Nora');
    }

    screenTest(
      'sin proyección, el deseo cogido sale como fila desde el motor',
      (tester, phone) async {
        await mountNora(tester, phone);
        expect(find.text('Bicicleta roja'), findsOneWidget);
        expect(find.text('Deseo'), findsOneWidget);
        expect(find.text('Lo ha cogido Aritz'), findsOneWidget);
        expect(find.text('Lo regalo yo'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      overrides: [
        ...web(),
        ..._overrides(
          _FakeWishService(),
          reader: 'leo',
          wishes: const [],
          rows: const [],
        ),
        wishPlanStateRowsProvider.overrideWith(
          (ref, person) => person == 'nora'
              ? [
                  _row(WishPlanState.claimed, plans: [_plan('p1')]),
                ]
              : const [],
        ),
      ],
    );

    screenTest(
      'la web de Nora: «Sorpresas» con «este ordenador» y sus deseos',
      (tester, phone) async {
        await mountNora(tester, phone);
        expect(find.text('Sorpresas'), findsOneWidget);
        expect(
          find.text(
            'En este ordenador no se ven los regalos para Nora. Solo otra '
            'persona de la familia puede cambiarlo, desde su móvil.',
          ),
          findsOneWidget,
        );
        expect(find.text('Bicicleta roja'), findsOneWidget);
        expect(find.byTooltip('Añadir deseo'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // La sesión de la web deja un temporizador de reposo: se suelta.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 10));
      },
      overrides: [
        ...web(),
        ..._overrides(
          _FakeWishService(),
          reader: 'nora',
          wishes: const [_wish],
          own: true,
        ),
      ],
    );
  });

  group('la ocasión', () {
    screenTest(
      'los deseos de la ocasión salen en la ficha de su persona, con etiqueta',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Ocasiones');
        await tapText(tester, 'Reyes');
        expect(find.text('Libro de volcanes'), findsOneWidget);
        expect(find.text('Deseo'), findsOneWidget);
        await tester.tap(find.text('Libro de volcanes'));
        await settle(tester);
        // Quien mira no es Nora: se abre para leerlo y cogerlo.
        expect(find.text('Lo regalo yo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        wishes: [
          Wish(
            id: _wish2.id,
            recipientId: 'nora',
            authorPersonId: 'nora',
            suggested: false,
            title: _wish2.title,
            year: 2026,
            occasionId: 'seed-kings',
          ),
        ],
        rows: [
          WishPlanRow(
            recipientId: 'nora',
            sourceWishId: 'wbook',
            state: WishPlanState.available,
            plans: const [],
            wish: _wish2,
          ),
        ],
      ),
    );
  });

  group('Reparto', () {
    const tall = Size(390, 1500);

    screenTest(
      'la franja fija de la propia persona se llama «Sorpresas»; la de otra, '
      'como siempre',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openFamily(tester, all: false);
        final nora = find.byKey(const ValueKey<String>('secret-strip:nora'));
        final aritz = find.byKey(const ValueKey<String>('secret-strip:aritz'));
        expect(
          find.descendant(of: nora, matching: find.text('Sorpresas')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: aritz,
            matching: find.text('Regalos en secreto para Aritz'),
          ),
          findsOneWidget,
        );
        expect(find.byType(RepartoGrid), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: tall,
      overrides: [
        ownHiddenPeopleProvider.overrideWithValue({'nora'}),
        secretBlocksProvider.overrideWithValue(const [
          SecretBlock('aritz'),
          SecretBlock('nora'),
        ]),
      ],
    );

    final service = _FakeWishService();
    Future<void> openTioList(WidgetTester tester, FakePhone phone) async {
      await seedSample(tester, phone);
      await _seedPlanGifts(
        tester,
        phone,
        ['p1'],
        occasion: 'seed-tio',
        giver: 'pere',
      );
      await pumpRegalos(tester, phone);
      await openFamily(tester, all: false);
      await tester.tap(find.bySemanticsLabel('Por ocasión'));
      await settle(tester);
    }

    final planOverrides = _overrides(
      service,
      reader: 'aritz',
      rows: [
        _row(WishPlanState.claimed, plans: [_plan('p1')]),
      ],
      plans: {
        'wbike': [_plan('p1')],
      },
    );

    screenTest(
      'cambiar quién regala un deseo cogido edita su plan, no el regalo',
      (tester, phone) async {
        service.calls.clear();
        service.planPatches.clear();
        await openTioList(tester, phone);
        expect(find.text('Bicicleta roja'), findsOneWidget);
        await tester.tap(
          find.bySemanticsLabel(RegExp('^Quién regala: Tío Pere')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Yayos de Terrassa'));
        await settle(tester);
        await settle(tester);
        expect(service.calls, ['editPlan:nora:p1']);
        expect(service.planPatches.single.giverId, 'yayos');
        // El regalo (la vista del plan) no se ha tocado: sigue con Tío Pere.
        final state = await familyState(tester, phone);
        expect(
          state.view.gifts.firstWhere((g) => g.id == 'p1').giverId,
          'pere',
        );
        expect(tester.takeException(), isNull);
      },
      size: tall,
      overrides: planOverrides,
    );

    screenTest(
      '«Nadie» deja el plan sin quien regala (lo vacía)',
      (tester, phone) async {
        service.calls.clear();
        service.planPatches.clear();
        await openTioList(tester, phone);
        await tester.tap(
          find.bySemanticsLabel(RegExp('^Quién regala: Tío Pere')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Nadie'));
        await settle(tester);
        await settle(tester);
        expect(service.calls, ['editPlan:nora:p1']);
        expect(service.planPatches.single.giverId, isNull);
        expect(service.planPatches.single.clear, {WishPlanField.giverId});
      },
      size: tall,
      overrides: planOverrides,
    );

    final failing = _FakeWishService()
      ..next = const WishResult.failed(WishProblem.blockUnavailable);
    screenTest(
      'si el plan no se puede cambiar, lo dice',
      (tester, phone) async {
        await openTioList(tester, phone);
        await tester.tap(
          find.bySemanticsLabel(RegExp('^Quién regala: Tío Pere')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Yayos de Terrassa'));
        await settle(tester);
        await settle(tester);
        expect(failing.calls, ['editPlan:nora:p1']);
        expect(find.byType(SnackBar), findsOneWidget);
      },
      size: tall,
      overrides: _overrides(
        failing,
        reader: 'aritz',
        rows: [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );
  });

  group('cambios sin guardar', () {
    final service = _FakeWishService();
    final own = _overrides(
      service,
      reader: 'nora',
      wishes: const [_wish],
      own: true,
    );
    Finder keep() => find.text('Seguir editando');

    screenTest(
      'el editor de un deseo pregunta al cerrar con cambios, con los textos '
      'del editor de regalos; sin cambios, cierra',
      (tester, phone) async {
        await _openNora(tester, phone);
        // Sin cambios: «Cerrar» cierra sin preguntar.
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        await tapLabel(tester, 'Cerrar');
        expect(find.text('Editar deseo'), findsNothing);
        expect(find.text('¿Descartar los cambios?'), findsNothing);
        // Con cambios: pregunta; seguir editando conserva lo escrito.
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        await tester.enterText(find.byType(TextField).first, 'Otra cosa');
        await tapLabel(tester, 'Cerrar');
        expect(find.text('¿Descartar los cambios?'), findsOneWidget);
        expect(
          find.text('Los cambios de este deseo todavía no se han guardado.'),
          findsOneWidget,
        );
        expect(
          find.text('Los cambios de este regalo todavía no se han guardado.'),
          findsNothing,
        );
        await tester.tap(keep());
        await settle(tester);
        expect(find.text('Editar deseo'), findsOneWidget);
        expect(find.text('Otra cosa'), findsOneWidget);
        // Descartar cierra sin guardar nada.
        await tapLabel(tester, 'Cerrar');
        await tester.tap(find.text('Descartar'));
        await settle(tester);
        expect(find.text('Editar deseo'), findsNothing);
        expect(service.calls, isEmpty);
      },
      overrides: own,
    );

    screenTest('el gesto de volver también pregunta, y guardar no pregunta', (
      tester,
      phone,
    ) async {
      service.calls.clear();
      await _openNora(tester, phone);
      await tester.tap(find.text('Bicicleta roja'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Otra cosa');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
      await tester.tap(keep());
      await settle(tester);
      await tester.tap(find.text('Guardar'));
      await settle(tester);
      expect(service.calls, ['edit:wbike:Otra cosa']);
      expect(find.text('¿Descartar los cambios?'), findsNothing);
      expect(find.text('Editar deseo'), findsNothing);
    }, overrides: own);

    screenTest(
      'el gesto de borde de iOS en el editor de un deseo pregunta con cambios '
      'y cierra sin ellos',
      (tester, phone) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          Future<void> swipe() async {
            final gesture = await tester.startGesture(const Offset(3, 420));
            await gesture.moveBy(const Offset(40, 0));
            await tester.pump();
            await gesture.moveBy(const Offset(80, 0));
            await gesture.up();
            await settle(tester);
          }

          await _openNora(tester, phone);
          await tester.tap(find.text('Bicicleta roja'));
          await settle(tester);
          expect(find.text('Editar deseo'), findsOneWidget);
          await swipe();
          expect(find.text('Editar deseo'), findsNothing);
          expect(find.text('¿Descartar los cambios?'), findsNothing);
          await tester.tap(find.text('Bicicleta roja'));
          await settle(tester);
          await tester.enterText(find.byType(TextField).first, 'Otra cosa');
          await swipe();
          expect(find.text('¿Descartar los cambios?'), findsOneWidget);
          expect(
            find.text('Los cambios de este deseo todavía no se han guardado.'),
            findsOneWidget,
          );
          await tester.tap(keep());
          await settle(tester);
          expect(find.text('Otra cosa'), findsOneWidget);
          await swipe();
          await tester.tap(find.text('Descartar'));
          await settle(tester);
          expect(find.text('Editar deseo'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
      overrides: own,
    );

    screenTest('un deseo nuevo sin escribir cierra; escrito, pregunta', (
      tester,
      phone,
    ) async {
      await _openNora(tester, phone);
      await tester.tap(find.byTooltip('Añadir deseo'));
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Nuevo deseo'), findsNothing);
      await tester.tap(find.byTooltip('Añadir deseo'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Patines');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
    }, overrides: own);

    final planService = _FakeWishService();
    final plan = _overrides(
      planService,
      reader: 'aritz',
      rows: [
        _row(WishPlanState.claimed, plans: [_plan('p1')]),
      ],
      plans: {
        'wbike': [_plan('p1')],
      },
    );

    screenTest(
      'el editor del plan pregunta con cambios (también con volver) y no sin '
      'ellos',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        expect(find.text('Deseo cogido'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(find.text('Deseo cogido'), findsNothing);
        expect(find.text('¿Descartar los cambios?'), findsNothing);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        await tester.enterText(find.widgetWithText(TextField, 'Tienda'), 'Sol');
        await tapLabel(tester, 'Cerrar');
        expect(find.text('¿Descartar los cambios?'), findsOneWidget);
        await tester.tap(keep());
        await settle(tester);
        expect(find.text('Deseo cogido'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await settle(tester);
        await tester.tap(find.text('Descartar'));
        await settle(tester);
        expect(find.text('Deseo cogido'), findsNothing);
        expect(planService.calls, isEmpty);
      },
      overrides: plan,
    );
  });

  group('revisión de interfaz', () {
    final service = _FakeWishService();
    final others = _overrides(
      service,
      reader: 'aritz',
      rows: [_row(WishPlanState.available)],
    );

    screenTest(
      '«Lo regalo yo» tiene zona táctil de 48 × 48 y el lector lee título, '
      '«Deseo» y estado antes del botón',
      (tester, phone) async {
        await _openNora(tester, phone);
        final button = find.widgetWithText(FilledButton, 'Lo regalo yo');
        final size = tester.getSize(button);
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
        // El texto de la fila es un solo nodo (con el estado, que se oye aunque
        // no se vea); el botón, otro, con el título del deseo.
        final text = find.bySemanticsLabel(
          RegExp('Bicicleta roja\\. Deseo.*Nadie lo ha cogido'),
        );
        expect(text, findsOneWidget);
        final action = find.bySemanticsLabel('Lo regalo yo: Bicicleta roja');
        expect(action, findsOneWidget);
        expect(
          tester.getTopLeft(text).dx,
          lessThan(tester.getTopLeft(action).dx),
        );
        // La fila mide como una de regalo: el botón va en la línea del título.
        expect(tester.getSize(find.byType(WishRow)).height, lessThan(80));
        expect(tester.takeException(), isNull);
      },
      overrides: others,
    );

    test('el texto de aviso pasa AA (4,5:1) sobre fondo y tarjeta, en claro y '
        'en oscuro', () {
      double lum(Color c) {
        double f(double v) => v <= 0.03928
            ? v / 12.92
            : math.pow((v + 0.055) / 1.055, 2.4) as double;
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
      }

      double contrast(Color a, Color b) {
        final x = lum(a) + 0.05;
        final y = lum(b) + 0.05;
        return x > y ? x / y : y / x;
      }

      for (final n in [NeutralPalette.light, NeutralPalette.dark]) {
        final style = RegalosTextStyles(
          text: n.text,
          secondary: n.textSecondary,
          warning: n.danger,
        ).metaWarning;
        for (final bg in [n.bg, n.surface, n.sheet]) {
          expect(contrast(style.color!, bg), greaterThanOrEqualTo(4.5));
        }
      }
    });

    screenTest(
      'la lista de deseos vacía usa el vacío compartido, con su acción',
      (tester, phone) async {
        service.calls.clear();
        await _openNora(tester, phone);
        expect(find.byType(EmptyState), findsOneWidget);
        expect(find.text('Sorpresas'), findsOneWidget);
        expect(find.text('Aún no has apuntado ningún deseo'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey<String>('empty-wish-add')));
        await settle(tester);
        expect(find.text('Nuevo deseo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        service,
        reader: 'nora',
        wishes: const [],
        own: true,
      ),
    );

    screenTest(
      'el vacío cabe con letra al doble, en oscuro y en horizontal',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        // En horizontal la fila de Nora queda por debajo: se baja la lista.
        await tester.scrollUntilVisible(
          find.text('Nora'),
          80,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axis == Axis.vertical,
              )
              .first,
        );
        await tester.drag(
          find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axis == Axis.vertical,
              )
              .first,
          const Offset(0, -160),
        );
        await settle(tester);
        await tapText(tester, 'Nora');
        expect(find.text('Sorpresas'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byType(EmptyState),
          80,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axis == Axis.vertical,
              )
              .last,
        );
        expect(find.byType(EmptyState), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: const Size(844, 390),
      textScale: 2,
      brightness: Brightness.dark,
      overrides: _overrides(
        service,
        reader: 'nora',
        wishes: const [],
        own: true,
      ),
    );

    screenTest(
      '«Visible para» va justo debajo del título, antes de «Quién regala»',
      (tester, phone) async {
        await _openNora(tester, phone);
        await tester.tap(find.byTooltip('Añadir regalo'));
        await settle(tester);
        final title = tester.getTopLeft(find.byType(TextField).first).dy;
        final visible = tester.getTopLeft(find.text('Visible para Nora')).dy;
        final giver = tester.getTopLeft(find.text('Quién regala').first).dy;
        expect(visible, greaterThan(title));
        expect(visible, lessThan(giver));
        expect(
          find.text(
            'Nora lo verá como un deseo más. Solo Nora podrá cambiarlo.',
          ),
          findsOneWidget,
        );
      },
      overrides: [
        wishServiceProvider.overrideWithValue(service),
        wishReaderProvider.overrideWithValue('aritz'),
        canSuggestWishProvider.overrideWith((ref, id) => id == 'nora'),
      ],
    );

    final planOverrides = _overrides(
      service,
      reader: 'aritz',
      rows: [
        _row(WishPlanState.claimed, plans: [_plan('p1')]),
      ],
      plans: {
        'wbike': [_plan('p1')],
      },
    );

    screenTest(
      'el plan: el título usa el rótulo del regalo, el enlace de compra dice '
      'su sitio y hay 24 entre «Convertir» y lo destructivo',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        expect(
          find.text('El deseo es de Nora. Aquí solo apuntas lo tuyo.'),
          findsOneWidget,
        );
        final link = find.widgetWithText(TextField, 'Enlace de compra');
        await _reveal(tester, link);
        await tester.enterText(link, 'https://www.amzn.eu/d/abc');
        await settle(tester);
        expect(find.text('amzn.eu'), findsOneWidget);
        final convert = find.text('Convertir en sorpresa');
        await _reveal(tester, convert);
        final hint = find.text(
          'Pasa a ser un regalo sorpresa, separado del deseo.',
        );
        final release = find.widgetWithText(OutlinedButton, 'Soltar');
        final gap =
            tester.getTopLeft(release).dy - tester.getBottomLeft(hint).dy;
        expect(gap, greaterThanOrEqualTo(24));
      },
      overrides: planOverrides,
    );

    screenTest(
      'el editor de un deseo usa el rótulo del título del regalo',
      (tester, phone) async {
        await _openNora(tester, phone);
        await tester.tap(find.byTooltip('Añadir deseo'));
        await settle(tester);
        expect(find.widgetWithText(TextField, 'Regalo'), findsOneWidget);
        expect(find.text('Qué te gustaría'), findsNothing);
      },
      overrides: _overrides(
        service,
        reader: 'nora',
        wishes: const [],
        own: true,
      ),
    );

    screenTest('quitar un deseo avisa de que no se puede deshacer', (
      tester,
      phone,
    ) async {
      await _openNora(tester, phone);
      await tester.tap(find.text('Bicicleta roja'));
      await settle(tester);
      final quitar = find.text('Quitar de mi lista');
      await _reveal(tester, quitar);
      await tester.tap(quitar);
      await settle(tester);
      expect(
        find.text(
          'Se quita de tu lista y de la que ve tu familia. No se puede '
          'deshacer.',
        ),
        findsOneWidget,
      );
    }, overrides: _overrides(service, reader: 'nora', own: true));

    screenTest(
      'el bloque «Sorpresas» se lee una sola vez, en la ficha y en Personas',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        // Personas: la franja de Nora no duplica título y frase.
        expect(find.bySemanticsLabel(RegExp('Sorpresas')).evaluate().length, 1);
        await tester.ensureVisible(find.text('Nora').first);
        await tester.pump();
        await tapText(tester, 'Nora');
        expect(find.bySemanticsLabel(RegExp('Sorpresas')), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('Sorpresas.*En este móvil no se ven')),
          findsOneWidget,
        );
      },
      overrides: _overrides(service, reader: 'nora', own: true),
    );
  });

  group('versiones mezcladas (todos los móviles en la 1.0.7)', () {
    const needUpdate = WishResult.failed(
      WishProblem.devicesNeedUpdate,
      devicesNeedUpdate: true,
    );
    const text =
        'Para coger deseos, todos los móviles de la familia necesitan la '
        'última versión.';

    test('el error del modelo se convierte en su propio problema', () {
      expect(
        wishProblemForPlanError(WishPlanError.devicesNeedUpdate),
        WishProblem.devicesNeedUpdate,
      );
      final result = wishResultFromPlanWrite(
        WishPlanWrite.failed(
          FamilyDoc.empty('l'),
          WishPlanError.devicesNeedUpdate,
        ),
      );
      expect(result.ok, isFalse);
      expect(result.problem, WishProblem.devicesNeedUpdate);
      expect(result.devicesNeedUpdate, isTrue);
      // Los demás bloqueos siguen siendo «ahora no se puede abrir».
      expect(
        wishProblemForPlanError(WishPlanError.unavailable),
        WishProblem.blockUnavailable,
      );
      for (final lang in ['es', 'ca', 'en']) {
        final l10n = lookupAppLocalizations(Locale(lang));
        expect(
          wishProblemText(l10n, needUpdate),
          l10n.wishProblemDevicesNeedUpdate,
        );
      }
    });

    final claimService = _FakeWishService()..next = needUpdate;
    screenTest(
      'coger un deseo lo dice con su texto y no deja nada hecho',
      (tester, phone) async {
        await _openNora(tester, phone);
        await tester.tap(find.text('Lo regalo yo'));
        await settle(tester);
        expect(find.text(text), findsOneWidget);
        expect(find.text('Has cogido «Bicicleta roja»'), findsNothing);
      },
      overrides: _overrides(
        claimService,
        reader: 'aritz',
        rows: [_row(WishPlanState.available)],
      ),
    );

    final notConnected = _FakeWishService()
      ..next = const WishResult.failed(
        WishProblem.blockUnavailable,
        reason: ProtectedPersonReason.requiresV2,
      );
    screenTest(
      'coger con este móvil sin la versión nueva: texto de deseos, el aviso no '
      'tapa el botón y «Cómo conectarlo» lleva a Móviles de la familia',
      (tester, phone) async {
        await _openNora(tester, phone);
        await tester.tap(find.text('Lo regalo yo'));
        await settle(tester);
        expect(
          find.text(
            'Para coger deseos, este móvil tiene que estar conectado a la '
            'familia con la versión nueva.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('regalos en secreto'), findsNothing);
        // El botón sigue a la vista y fuera del aviso: se puede volver a
        // intentar.
        final button = find.widgetWithText(FilledButton, 'Lo regalo yo');
        expect(button, findsOneWidget);
        expect(
          tester
              .getRect(button)
              .overlaps(tester.getRect(find.byType(SnackBar))),
          isFalse,
        );
        await tester.tap(find.text('Cómo conectarlo'));
        await settle(tester);
        expect(find.text('Móviles de la familia'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        notConnected,
        reader: 'aritz',
        rows: [_row(WishPlanState.available)],
      ),
    );

    final planService = _FakeWishService()..next = needUpdate;
    final planOverrides = _overrides(
      planService,
      reader: 'aritz',
      rows: [
        _row(WishPlanState.claimed, plans: [_plan('p1')]),
      ],
      plans: {
        'wbike': [_plan('p1')],
      },
    );

    screenTest(
      'guardar, soltar y convertir un plan lo dicen y dejan el editor abierto',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(find.text(text), findsWidgets);
        expect(find.text('Deseo cogido'), findsOneWidget);
        // Soltar, tras confirmar.
        final soltar = find.text('Soltar');
        await _reveal(tester, soltar);
        await tester.tap(soltar);
        await settle(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(ConfirmDialog),
            matching: find.text('Soltar'),
          ),
        );
        await settle(tester);
        // El aviso anterior puede estar saliendo todavía.
        expect(find.text(text), findsWidgets);
        expect(find.text('Deseo cogido'), findsOneWidget);
        expect(planService.calls, ['editPlan:nora:p1', 'release:nora:p1']);
      },
      overrides: planOverrides,
    );

    screenTest(
      'cambiar el quién regala de un deseo cogido en Reparto lo dice',
      (tester, phone) async {
        planService.calls.clear();
        await seedSample(tester, phone);
        await _seedPlanGifts(
          tester,
          phone,
          ['p1'],
          occasion: 'seed-tio',
          giver: 'pere',
        );
        await pumpRegalos(tester, phone);
        await openFamily(tester, all: false);
        await tester.tap(find.bySemanticsLabel('Por ocasión'));
        await settle(tester);
        await tester.tap(
          find.bySemanticsLabel(RegExp('^Quién regala: Tío Pere')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Yayos de Terrassa'));
        await settle(tester);
        await settle(tester);
        expect(planService.calls, ['editPlan:nora:p1']);
        expect(find.text(text), findsOneWidget);
      },
      size: const Size(390, 1500),
      overrides: planOverrides,
    );
  });

  group('arreglos de la QA 1.0.7', () {
    final bookRow = WishPlanRow(
      recipientId: 'nora',
      sourceWishId: 'wbook',
      state: WishPlanState.available,
      plans: const [],
      wish: _wish2,
    );

    // m1 (Daniel: cuentas separadas): en otros móviles los deseos sin coger se
    // cuentan aparte de los regalos.
    screenTest(
      'm1: Personas y la cabecera de la persona cuentan los deseos aparte',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        // Nora tiene 4 regalos de muestra y 2 deseos sin coger.
        expect(find.textContaining('4 regalos · 2 deseos'), findsOneWidget);
        await tester.ensureVisible(find.text('Nora').first);
        await tester.pump();
        await tapText(tester, 'Nora');
        expect(find.bySemanticsLabel('4 regalos'), findsOneWidget);
        expect(find.bySemanticsLabel('2 deseos'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        wishes: const [_wish, _wish2],
        rows: [_row(WishPlanState.available), bookRow],
      ),
    );

    // Un deseo cogido sale como su plan (un regalo): no se cuenta dos veces.
    screenTest(
      'm1: un deseo cogido cuenta como regalo, no como deseo',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1']);
        expect(find.bySemanticsLabel('5 regalos'), findsOneWidget);
        expect(find.bySemanticsLabel('1 deseo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        wishes: const [_wish, _wish2],
        rows: [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
          bookRow,
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );

    // En el móvil de la propia persona no sale ninguna cuenta nueva.
    screenTest(
      'm1: en el móvil de Nora, Personas no suma deseos a nada',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        expect(find.textContaining('deseos'), findsNothing);
        expect(find.textContaining('regalos · '), findsNothing);
        await tester.ensureVisible(find.text('Nora').first);
        await tester.pump();
        await tapText(tester, 'Nora');
        // Lo de siempre: «2 deseos» en la cabecera y nada de regalos.
        expect(find.textContaining('2 deseos'), findsOneWidget);
        expect(find.textContaining(RegExp(r'\d regalos')), findsNothing);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'nora',
        wishes: const [_wish, _wish2],
        own: true,
      ),
    );

    screenTest(
      'm1: Ocasiones y el detalle de la ocasión cuentan los deseos aparte',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Ocasiones');
        // Reyes: 6 regalos de muestra y un deseo.
        expect(find.textContaining('6 regalos · 1 deseo'), findsOneWidget);
        await tapText(tester, 'Reyes');
        expect(find.text('2 regalos · 1 deseo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        wishes: [
          Wish(
            id: _wish2.id,
            recipientId: 'nora',
            authorPersonId: 'nora',
            suggested: false,
            title: _wish2.title,
            year: 2026,
            occasionId: 'seed-kings',
          ),
        ],
        rows: [bookRow],
      ),
    );

    test('m1: una ocasión que solo tiene deseos dice cuántos', () {
      for (final lang in ['es', 'ca', 'en']) {
        final l10n = lookupAppLocalizations(Locale(lang));
        expect(giftsAndWishesText(l10n, 0, 0), l10n.giftCount(0));
        expect(giftsAndWishesText(l10n, 0, 4), l10n.wishCount(4));
        expect(giftsAndWishesText(l10n, 1, 0), l10n.giftCount(1));
        expect(
          giftsAndWishesText(l10n, 2, 4),
          '${l10n.giftCount(2)} · ${l10n.wishCount(4)}',
        );
      }
      final es = lookupAppLocalizations(const Locale('es'));
      expect(giftsAndWishesText(es, 2, 4), '2 regalos · 4 deseos');
      expect(giftsAndWishesText(es, 0, 1), '1 deseo');
    });

    // m2 (Daniel: solo «Deseo»).
    screenTest(
      'm2: un deseo cogido lleva solo «Deseo», nunca también «Sorpresa»',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1'], surprise: true);
        expect(find.text('Deseo'), findsOneWidget);
        expect(find.text('Sorpresa'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        rows: [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );

    // m3: lo escrito y sin guardar pasa a la sorpresa.
    final convertService = _FakeWishService();
    screenTest(
      'm3: convertir en sorpresa lleva lo escrito y sin guardar',
      (tester, phone) async {
        convertService.calls.clear();
        convertService.planPatches.clear();
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        final store = find.widgetWithText(TextField, 'Tienda');
        await _reveal(tester, store);
        await tester.enterText(store, 'Decathlon');
        final planned = find.widgetWithText(TextField, 'Previsto');
        await _reveal(tester, planned);
        await tester.enterText(planned, '120');
        final convertir = find.text('Convertir en sorpresa');
        await _reveal(tester, convertir);
        await tester.tap(convertir);
        await settle(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(ConfirmDialog),
            matching: find.text('Convertir'),
          ),
        );
        await settle(tester);
        // Primero se guarda lo escrito en el plan y luego se convierte.
        expect(convertService.calls, ['editPlan:nora:p1', 'convert:nora:p1']);
        expect(convertService.planPatches.single.store, 'Decathlon');
        expect(convertService.planPatches.single.plannedCents, 12000);
        expect(find.text('Ahora es una sorpresa'), findsOneWidget);
      },
      overrides: _overrides(
        convertService,
        reader: 'aritz',
        rows: [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );

    // Sin cambios no se guarda nada antes de convertir.
    final plainService = _FakeWishService();
    screenTest(
      'm3: sin cambios, convertir no guarda antes',
      (tester, phone) async {
        plainService.calls.clear();
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        final convertir = find.text('Convertir en sorpresa');
        await _reveal(tester, convertir);
        await tester.tap(convertir);
        await settle(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(ConfirmDialog),
            matching: find.text('Convertir'),
          ),
        );
        await settle(tester);
        expect(plainService.calls, ['convert:nora:p1']);
      },
      overrides: _overrides(
        plainService,
        reader: 'aritz',
        rows: [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );

    // m4: el botón de añadir deseo se lee con su nombre.
    screenTest(
      'm4: el botón de añadir deseo de la propia persona tiene nombre',
      (tester, phone) async {
        await _openNora(tester, phone);
        final fab = find.byType(FloatingActionButton);
        // El nodo del botón lleva el nombre él mismo, no solo la ayuda.
        final node = find
            .ancestor(of: fab, matching: find.byType(Semantics))
            .first;
        expect(tester.getSemantics(node).label, 'Añadir deseo');
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'nora',
        wishes: const [],
        own: true,
      ),
    );

    screenTest(
      'm4: y el de añadir regalo, el suyo',
      (tester, phone) async {
        await _openNora(tester, phone);
        final node = find
            .ancestor(
              of: find.byType(FloatingActionButton),
              matching: find.byType(Semantics),
            )
            .first;
        expect(tester.getSemantics(node).label, 'Añadir regalo');
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        rows: [_row(WishPlanState.available)],
      ),
    );

    // m5: un enlace de compra que no vale se dice en su campo.
    final linkService = _FakeWishService();
    screenTest(
      'm5: un enlace de compra no válido se explica en su campo y no guarda',
      (tester, phone) async {
        linkService.calls.clear();
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        final field = find.widgetWithText(TextField, 'Enlace de compra');
        await _reveal(tester, field);
        await tester.enterText(field, 'esto no es un enlace');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(find.text('El enlace de compra no es válido.'), findsOneWidget);
        expect(find.textContaining('Revisa lo escrito'), findsNothing);
        expect(linkService.calls, isEmpty);
        // Corregido, guarda.
        await tester.enterText(field, 'https://www.decathlon.es/bici');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(linkService.calls, ['editPlan:nora:p1']);
      },
      overrides: _overrides(
        linkService,
        reader: 'aritz',
        rows: [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );

    // c2: un título larguísimo se cita acortado.
    final longTitle = List.filled(30, 'Bicicleta').join(' ');
    final longWish = Wish(
      id: 'wlong',
      recipientId: 'nora',
      authorPersonId: 'nora',
      suggested: false,
      title: longTitle,
      year: 2026,
    );
    final longService = _FakeWishService();
    screenTest(
      'c2: «Has cogido «…»» cita el título acortado, en una o dos líneas',
      (tester, phone) async {
        await _openNora(tester, phone);
        await tester.ensureVisible(find.text('Lo regalo yo'));
        await tester.pump();
        await tester.tap(find.text('Lo regalo yo'));
        await settle(tester);
        final notice = find.textContaining('Has cogido «');
        expect(notice, findsOneWidget);
        final text = tester.widget<Text>(notice).data!;
        expect(text.length, lessThan(80));
        expect(text, contains('…»'));
        expect(tester.getSize(notice).height, lessThan(60));
      },
      overrides: _overrides(
        longService,
        reader: 'aritz',
        wishes: [longWish],
        rows: [
          WishPlanRow(
            recipientId: 'nora',
            sourceWishId: 'wlong',
            state: WishPlanState.available,
            plans: const [],
            wish: longWish,
          ),
        ],
      ),
    );

    final longPlan = WishPlan(
      planId: 'p1',
      recipientId: 'nora',
      sourceWishId: 'wbike',
      claimantPersonId: 'aritz',
      title: List.filled(10, 'Bicicleta').join(' '),
      status: GiftStatus.decided,
      giverId: 'us',
    );
    final dialogService = _FakeWishService();
    screenTest(
      'c2: «¿Soltar «…»?» y «¿Convertir «…»?» no ocupan la pantalla',
      (tester, phone) async {
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        for (final label in ['Soltar', 'Convertir en sorpresa']) {
          final button = find.text(label);
          await _reveal(tester, button);
          await tester.tap(button);
          await settle(tester);
          final dialog = find.byType(ConfirmDialog);
          expect(dialog, findsOneWidget);
          expect(
            find.descendant(of: dialog, matching: find.textContaining('…')),
            findsOneWidget,
          );
          // El título citado ocupa una o dos líneas, no la pantalla.
          expect(
            tester
                .getSize(
                  find.descendant(
                    of: dialog,
                    matching: find.textContaining('…'),
                  ),
                )
                .height,
            lessThan(90),
          );
          await tester.tap(find.text('Cancelar').last);
          await settle(tester);
        }
      },
      overrides: _overrides(
        dialogService,
        reader: 'aritz',
        rows: [
          WishPlanRow(
            recipientId: 'nora',
            sourceWishId: 'wbike',
            state: WishPlanState.claimed,
            plans: [longPlan],
            wish: _wish,
          ),
        ],
        plans: {
          'wbike': [longPlan],
        },
      ),
    );

    test('c2: quotedTitle corta por caracteres que se ven', () {
      expect(quotedTitle('  Bici  '), 'Bici');
      expect(quotedTitle('a' * 60), 'a' * 60);
      final cut = quotedTitle('a' * 61);
      expect(cut, '${'a' * 59}…');
      // Un emoji de varias partes no se parte.
      final family = '👨‍👩‍👧‍👦';
      final emoji = quotedTitle(family * 70);
      expect(emoji, '${family * 59}…');
      expect(quotedTitle('${'a' * 58} ${'b' * 30}'), '${'a' * 58}…');
    });
  });

  group('textos de los errores', () {
    test('cada problema tiene su frase corta en es, ca y en', () {
      for (final lang in ['es', 'ca', 'en']) {
        final l10n = lookupAppLocalizations(Locale(lang));
        for (final problem in WishProblem.values) {
          final text = wishProblemText(
            l10n,
            WishResult.failed(problem),
            name: 'Nora',
          );
          expect(text, isNotEmpty, reason: '$lang $problem');
          expect(text.length, lessThan(120), reason: '$lang $problem');
          expect(text, isNot(contains(RegExp(r'padre|mamá|papá|pare|mare'))));
        }
      }
    });
  });

  group('revisión final de los deseos propios', () {
    final service = _FakeWishService();

    // ---- 1: la nota privada nunca pasa a la descripción pública ----
    final suggestOverrides = [
      wishServiceProvider.overrideWithValue(service),
      wishReaderProvider.overrideWithValue('aritz'),
      canSuggestWishProvider.overrideWith((ref, id) => id == 'nora'),
    ];
    final noteField = find.byKey(const ValueKey<String>('gift-note'));
    final descriptionField = find.byKey(
      const ValueKey<String>('gift-description'),
    );
    String textOf(WidgetTester tester, Finder f) =>
        tester.widget<TextField>(f).controller!.text;
    Future<void> toggleVisible(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('gift-visible-switch')),
      );
      await settle(tester);
    }

    screenTest(
      '1: encender «Visible para» no lleva la nota privada a la descripción; '
      'apagarlo ni encenderlo de nuevo mueven texto de un campo al otro',
      (tester, phone) async {
        service
          ..calls.clear()
          ..suggestPatches.clear();
        await _openNora(tester, phone);
        await tester.tap(find.byTooltip('Añadir regalo'));
        await settle(tester);
        await tester.enterText(find.byType(TextField).first, 'Patines');
        await openMoreDetails(tester);
        await tester.enterText(noteField, 'ya comprado, 80 €');
        expect(descriptionField, findsNothing);

        // Encendido: la descripción empieza vacía, no con la nota.
        await toggleVisible(tester);
        expect(noteField, findsNothing);
        expect(textOf(tester, descriptionField), isEmpty);
        expect(find.text('ya comprado, 80 €'), findsNothing);
        await tester.enterText(descriptionField, 'Con timbre');

        // Apagado: la nota vuelve intacta y la descripción no se cuela.
        await toggleVisible(tester);
        expect(descriptionField, findsNothing);
        expect(textOf(tester, noteField), 'ya comprado, 80 €');
        expect(find.text('Con timbre'), findsNothing);

        // Otra vez encendido: la descripción sigue siendo la suya.
        await toggleVisible(tester);
        expect(textOf(tester, descriptionField), 'Con timbre');
        expect(find.text('ya comprado, 80 €'), findsNothing);

        await tester.tap(find.text('Guardar'));
        await settle(tester);
        // Lo único que llega al deseo (el común) es lo escrito en la
        // descripción: ninguna palabra de la nota.
        expect(service.calls, ['suggest:nora:Patines:2026']);
        final patch = service.suggestPatches.single;
        expect(patch.description, 'Con timbre');
        expect(patch.toString(), isNot(contains('ya comprado')));
        expect(patch.title, 'Patines');
      },
      size: const Size(390, 2400),
      overrides: suggestOverrides,
    );

    screenTest(
      '1: en el otro sentido, la descripción pública no se queda como nota de '
      'la sorpresa',
      (tester, phone) async {
        service
          ..calls.clear()
          ..suggestPatches.clear();
        await _openNora(tester, phone);
        await tester.tap(find.byTooltip('Añadir regalo'));
        await settle(tester);
        await tester.enterText(find.byType(TextField).first, 'Cometa');
        await openMoreDetails(tester);
        await toggleVisible(tester);
        await tester.enterText(descriptionField, 'texto público');
        await toggleVisible(tester);
        expect(textOf(tester, noteField), isEmpty);
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        // Se guarda como sorpresa, sin deseo y sin la descripción como nota.
        expect(service.calls, isEmpty);
        final state = await familyState(tester, phone);
        final gift = state.view.gifts.firstWhere((g) => g.title == 'Cometa');
        expect(gift.note, isNull);
        expect(gift.title, 'Cometa');
      },
      size: const Size(390, 2400),
      overrides: suggestOverrides,
    );

    // ---- 11: añadir deseo según quién mira; sugerencia sin clave privada ----
    final unpaired = _FakeWishService();
    screenTest(
      '11: en el móvil de Nora aún sin emparejar, su ficha apunta deseos, no '
      'regalos para ella',
      (tester, phone) async {
        unpaired.calls.clear();
        await _openNora(tester, phone);
        expect(find.byTooltip('Añadir deseo'), findsOneWidget);
        expect(find.byTooltip('Añadir regalo'), findsNothing);
        await tester.tap(find.byTooltip('Añadir deseo'));
        await settle(tester);
        expect(find.text('Nuevo deseo'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Patines');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(unpaired.calls, ['create:Patines']);
        // Ningún regalo de Nora para ella.
        final state = await familyState(tester, phone);
        expect(
          state.view.gifts.where(
            (g) => g.recipientId == 'nora' && g.title == 'Patines',
          ),
          isEmpty,
        );
      },
      // Sin «Sorpresas» ni ocultación: es el móvil de Nora y nada más.
      overrides: _overrides(
        unpaired,
        reader: 'nora',
        wishes: const [],
        own: false,
      ),
    );

    final blockedService = _FakeWishService();
    screenTest(
      '11: una sugerencia visible para otra persona se guarda aunque falte la '
      'clave privada de sus sorpresas',
      (tester, phone) async {
        blockedService
          ..calls.clear()
          ..suggestPatches.clear();
        await _openNora(tester, phone);
        await tester.tap(find.byTooltip('Añadir regalo'));
        await settle(tester);
        await tester.enterText(find.byType(TextField).first, 'Patines');
        // Sin «Visible para», no se puede guardar para ella.
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(blockedService.calls, isEmpty);
        // Con «Visible para» no hace falta esa clave: guarda el deseo.
        await toggleVisible(tester);
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(blockedService.calls, ['suggest:nora:Patines:2026']);
      },
      overrides: [
        wishServiceProvider.overrideWithValue(blockedService),
        wishReaderProvider.overrideWithValue('aritz'),
        canSuggestWishProvider.overrideWith((ref, id) => id == 'nora'),
        giftRecipientAccessProvider.overrideWith((ref) async {
          return [
            for (final id in ['aritz', 'nora', 'leo'])
              GiftRecipientAccess(
                recipient: Recipient(
                  id: id,
                  name: id == 'aritz'
                      ? 'Aritz'
                      : id == 'nora'
                      ? 'Nora'
                      : 'Leo',
                  colorIndex: 0,
                  archived: false,
                ),
                status: id == 'nora'
                    ? PersonProtectionStatus.active
                    : PersonProtectionStatus.unprotected,
                canSelect: id != 'nora',
                reason: id == 'nora'
                    ? ProtectedPersonReason.missingEpochKey
                    : null,
              ),
          ];
        }),
      ],
    );
  });

  group('revisión final: el plan en el editor', () {
    // ---- 2: el editor retira sus campos y sus diálogos al perder el plan ----
    screenTest(
      '2: si el plan deja de estar autorizado, el editor y su confirmación se '
      'cierran y no queda nada suyo en pantalla ni en accesibilidad',
      (tester, phone) async {
        _holderInitial = [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ];
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        expect(find.text('Deseo cogido'), findsOneWidget);
        final notes = find.byType(TextField).last;
        await _reveal(tester, notes);
        await tester.enterText(notes, 'secreto 123');
        await tester.pump();
        final soltar = find.text('Soltar');
        await _reveal(tester, soltar);
        await tester.tap(soltar);
        await settle(tester);
        expect(find.byType(ConfirmDialog), findsOneWidget);
        expect(find.text('secreto 123'), findsOneWidget);

        // Le quitan el derecho al bloque con el editor y la confirmación
        // abiertos.
        phone.container.read(_rowsHolder.notifier).set(const []);
        await settle(tester);
        expect(find.byType(ConfirmDialog), findsNothing);
        expect(find.byType(WishPlanEditor), findsNothing);
        expect(find.text('Deseo cogido'), findsNothing);
        expect(find.text('secreto 123', skipOffstage: false), findsNothing);
        expect(
          find.text('Este regalo ya no se puede ver en este móvil.'),
          findsOneWidget,
        );
        // El árbol de accesibilidad tampoco lleva nada del plan.
        expect(find.bySemanticsLabel(RegExp('secreto 123')), findsNothing);
        expect(find.bySemanticsLabel('Soltar'), findsNothing);
        expect(find.bySemanticsLabel('Guardar'), findsNothing);
        expect(find.bySemanticsLabel('Deseo cogido'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      overrides: _holderOverrides(_FakeWishService(), reader: 'aritz'),
    );

    // ---- 8: solo quien lo cogió cambia su plan ----
    final leoService = _FakeWishService();
    screenTest(
      '8: en el móvil de Leo, el plan de Aritz se ve sin acciones; la casilla '
      'y el editor no cambian nada',
      (tester, phone) async {
        leoService.calls.clear();
        await _openNoraWithPlans(tester, phone, ['p1']);
        // La casilla de la fila no cambia el estado de un plan ajeno.
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text('Bicicleta roja'),
              matching: find.byType(GiftRow),
            ),
            matching: find.byType(StatusCheckbox),
          ),
        );
        await settle(tester);
        expect(leoService.calls, isEmpty);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        expect(find.text('Deseo cogido'), findsOneWidget);
        expect(find.text('Lo ha cogido Aritz'), findsWidgets);
        expect(
          find.text('Solo Aritz puede cambiarlo o soltarlo.'),
          findsOneWidget,
        );
        for (final action in [
          'Soltar',
          'Guardar',
          'Convertir en sorpresa',
          'Eliminar mi reserva',
        ]) {
          expect(find.text(action), findsNothing, reason: action);
        }
        expect(find.byType(TextField), findsNothing);
        expect(leoService.calls, isEmpty);
      },
      overrides: _overrides(
        leoService,
        reader: 'leo',
        rows: [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );

    final leoRemoved = _FakeWishService();
    screenTest(
      '8: tras quitarlo Nora de su lista, Leo tampoco puede eliminar la '
      'reserva de Aritz',
      (tester, phone) async {
        leoRemoved.calls.clear();
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        expect(find.text('Deseo cogido'), findsOneWidget);
        expect(find.text('Nora lo quitó de su lista'), findsWidgets);
        expect(
          find.text('Solo Aritz puede cambiarlo o soltarlo.'),
          findsOneWidget,
        );
        for (final action in [
          'Soltar',
          'Guardar',
          'Convertir en sorpresa',
          'Eliminar mi reserva',
        ]) {
          expect(find.text(action), findsNothing, reason: action);
        }
        expect(leoRemoved.calls, isEmpty);
      },
      overrides: _overrides(
        leoRemoved,
        reader: 'leo',
        rows: [
          _row(WishPlanState.removedFromList, plans: [_plan('p1')], wish: null),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );
  });

  group('revisión final: Reparto con una persona de regalador', () {
    const tall = Size(390, 1500);
    final repartoService = _FakeWishService();
    final planOverrides = _overrides(
      repartoService,
      reader: 'aritz',
      rows: [
        _row(WishPlanState.claimed, plans: [_plan('p1')]),
      ],
      plans: {
        'wbike': [_plan('p1')],
      },
    );

    Future<void> seedPlan(WidgetTester tester, FakePhone phone) async {
      repartoService
        ..calls.clear()
        ..planPatches.clear();
      await seedSample(tester, phone);
      await _seedPlanGifts(
        tester,
        phone,
        ['p1'],
        occasion: 'seed-tio',
        giver: 'pere',
      );
      await pumpRegalos(tester, phone);
    }

    Future<void> expectPlanAssignedToLeo(
      WidgetTester tester,
      FakePhone phone,
    ) async {
      // Va por el plan, con quién regala privado en su `giverId`, nunca por
      // `assignPersonAsGiver` con el id del plan.
      expect(repartoService.calls, ['editPlan:nora:p1']);
      final state = await familyState(tester, phone);
      final leoGiver = state.view.giverForPerson('leo');
      expect(leoGiver, isNotNull);
      expect(repartoService.planPatches.single.giverId, leoGiver!.id);
      // El regalo (la vista del plan) no se ha tocado.
      expect(state.view.gifts.firstWhere((g) => g.id == 'p1').giverId, 'pere');
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    }

    screenTest(
      '10: la lista por ocasión asigna una persona a un deseo cogido por su '
      'plan',
      (tester, phone) async {
        await seedPlan(tester, phone);
        await openFamily(tester, all: false);
        await tester.tap(find.bySemanticsLabel('Por ocasión'));
        await settle(tester);
        await tester.tap(
          find.bySemanticsLabel(RegExp('^Quién regala: Tío Pere')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.bySemanticsLabel('Leo'));
        await settle(tester);
        await settle(tester);
        await expectPlanAssignedToLeo(tester, phone);
      },
      size: tall,
      overrides: planOverrides,
    );

    screenTest(
      '10: la hoja de una celda asigna una persona a un deseo cogido por su '
      'plan',
      (tester, phone) async {
        await seedPlan(tester, phone);
        await openFamily(tester);
        await tester.tap(
          find.bySemanticsLabel(RegExp('^Tío Pere para Nora: 2 regalos')),
        );
        await settle(tester);
        await tester.tap(
          find.bySemanticsLabel(RegExp('^Quién regala: Tío Pere')).first,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(
          find.descendant(
            of: find.byKey(kRepartoSheetKey),
            matching: find.bySemanticsLabel('Leo'),
          ),
        );
        await settle(tester);
        await settle(tester);
        await expectPlanAssignedToLeo(tester, phone);
      },
      size: tall,
      overrides: planOverrides,
    );
  });

  group('segunda revisión final: 2, 3, 9, 10 y 11', () {
    // ---- 2: Personas → Añadir regalo → la persona de este móvil ----
    Future<void> pickNoraInGeneralAdd(WidgetTester tester) async {
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Añadir regalo'),
      );
      await settle(tester);
      expect(find.byType(GiftEditorScreen), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Para quién')));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Nora'),
        ),
      );
      await settle(tester);
    }

    for (final (label, own) in [
      ('sin emparejar', false),
      ('emparejado', true),
    ]) {
      final service = _FakeWishService();
      screenTest(
        '2: en el móvil de Nora $label, Personas → Añadir regalo → Nora crea '
        'un deseo, nunca un regalo',
        (tester, phone) async {
          service.calls.clear();
          await seedSample(tester, phone);
          await pumpRegalos(tester, phone);
          await pickNoraInGeneralAdd(tester);
          // El editor de regalos se cierra y se abre el de deseos.
          expect(find.byType(GiftEditorScreen), findsNothing);
          expect(find.text('Nuevo deseo'), findsOneWidget);
          await tester.enterText(find.byType(TextField).first, 'Patines');
          await tester.tap(find.text('Guardar'));
          await settle(tester);
          expect(service.calls, ['create:Patines']);
          final state = await familyState(tester, phone);
          expect(state.view.gifts.where((g) => g.title == 'Patines'), isEmpty);
          expect(tester.takeException(), isNull);
        },
        overrides: _overrides(
          service,
          reader: 'nora',
          wishes: const [],
          own: own,
        ),
      );
    }

    final soleService = _FakeWishService();
    screenTest(
      '2: si Nora es la única persona activa y viene preseleccionada, el alta '
      'general abre directamente el deseo',
      (tester, phone) async {
        soleService.calls.clear();
        await seedSample(tester, phone);
        await tester.runAsync(() async {
          final c = familyOf(phone);
          for (final (id, name) in [('aritz', 'Aritz'), ('leo', 'Leo')]) {
            await c.upsertRecipient(
              Recipient(id: id, name: name, colorIndex: 0, archived: true),
            );
          }
        });
        await pumpRegalos(tester, phone);
        await tester.tap(
          find.widgetWithText(FloatingActionButton, 'Añadir regalo'),
        );
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsNothing);
        expect(find.text('Nuevo deseo'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Cometa');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(soleService.calls, ['create:Cometa']);
        final state = await familyState(tester, phone);
        expect(state.view.gifts.where((g) => g.title == 'Cometa'), isEmpty);
      },
      overrides: _overrides(
        soleService,
        reader: 'nora',
        wishes: const [],
        own: false,
      ),
    );

    // ---- 2: elegir a la propia persona en cualquier selector lleva el borrador
    final draftService = _FakeWishService();
    screenTest(
      '2: Nora abre «Añadir regalo» desde la ficha de Aritz, escribe título, '
      'ocasión y nota, y se elige a sí misma: el deseo lleva título y ocasión, '
      'sin la nota, y no se guarda nada hasta «Guardar»',
      (tester, phone) async {
        draftService.calls.clear();
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Aritz');
        await tester.tap(find.byTooltip('Añadir regalo'));
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Patines');
        await tester.tap(find.bySemanticsLabel(RegExp(r'^Ocasión')).first);
        await settle(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Reyes'),
          ),
        );
        await settle(tester);
        await openMoreDetails(tester);
        await tester.enterText(
          find.byKey(const ValueKey<String>('gift-note')),
          'ya comprado, 80 €',
        );
        await tester.tap(find.bySemanticsLabel(RegExp(r'^Para quién')));
        await settle(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Nora'),
          ),
        );
        await settle(tester);

        expect(find.byType(GiftEditorScreen), findsNothing);
        expect(find.text('Nuevo deseo'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'Patines',
        );
        expect(
          find.bySemanticsLabel(RegExp(r'^Ocasión, Reyes')),
          findsOneWidget,
        );
        // Ni la nota privada ni ningún precio pasan al deseo.
        expect(
          find.text('ya comprado, 80 €', skipOffstage: false),
          findsNothing,
        );
        expect(find.textContaining('Previsto'), findsNothing);
        // Nada guardado todavía.
        expect(draftService.calls, isEmpty);
        var state = await familyState(tester, phone);
        expect(state.view.gifts.where((g) => g.title == 'Patines'), isEmpty);

        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(draftService.calls, ['create:Patines']);
        state = await familyState(tester, phone);
        expect(state.view.gifts.where((g) => g.title == 'Patines'), isEmpty);
        expect(tester.takeException(), isNull);
      },
      size: const Size(390, 2400),
      overrides: _overrides(
        draftService,
        reader: 'nora',
        wishes: const [],
        own: false,
      ),
    );

    // ---- 3 (bajo): desde una ocasión, el deseo solo salta si es la única ----
    final occasionService = _FakeWishService();
    screenTest(
      'desde una ocasión, «Añadir regalo» abre el selector de personas, no el '
      'deseo, si la persona de este móvil es la primera pero hay más',
      (tester, phone) async {
        occasionService.calls.clear();
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Ocasiones');
        await tapText(tester, 'Reyes');
        await tester.tap(find.byTooltip('Añadir regalo'));
        await settle(tester);
        expect(find.text('Nuevo deseo'), findsNothing);
        expect(find.byType(GiftEditorScreen), findsOneWidget);
        // «Para quién» arriba y sin elegir.
        expect(find.bySemanticsLabel(RegExp(r'^Para quién')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        occasionService,
        reader: 'aritz',
        wishes: const [],
        own: false,
      ),
    );

    final soleOccasionService = _FakeWishService();
    screenTest(
      'desde una ocasión, si la persona de este móvil es la única, «Añadir '
      'regalo» abre su deseo con esa ocasión',
      (tester, phone) async {
        soleOccasionService.calls.clear();
        await seedSample(tester, phone);
        await tester.runAsync(() async {
          final c = familyOf(phone);
          for (final (id, name) in [('aritz', 'Aritz'), ('leo', 'Leo')]) {
            await c.upsertRecipient(
              Recipient(id: id, name: name, colorIndex: 0, archived: true),
            );
          }
        });
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Ocasiones');
        await tapText(tester, 'Reyes');
        await tester.tap(find.byTooltip('Añadir regalo'));
        await settle(tester);
        expect(find.byType(GiftEditorScreen), findsNothing);
        expect(find.text('Nuevo deseo'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp(r'^Ocasión, Reyes')),
          findsOneWidget,
        );
        expect(soleOccasionService.calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        soleOccasionService,
        reader: 'nora',
        wishes: const [],
        own: false,
      ),
    );

    // ---- 3: el selector de estado y el editor, con la autorización dudosa ----
    screenTest(
      '3: el selector de estado de la casilla se cierra si se revoca el acceso '
      'con él abierto',
      (tester, phone) async {
        _holderInitial = [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ];
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.longPress(
          find.descendant(
            of: find.ancestor(
              of: find.text('Bicicleta roja'),
              matching: find.byType(GiftRow),
            ),
            matching: find.byType(StatusCheckbox),
          ),
        );
        await settle(tester);
        expect(find.byType(ChoiceGrid), findsOneWidget);
        expect(find.text('Estado de Bicicleta roja'), findsOneWidget);

        phone.container.read(_rowsHolder.notifier).set(const []);
        await settle(tester);
        expect(find.byType(ChoiceGrid), findsNothing);
        expect(find.textContaining('Estado de Bicicleta'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      overrides: _holderOverrides(_FakeWishService(), reader: 'aritz'),
    );

    screenTest(
      '3: si se revoca el acceso entre la pulsación larga y el primer pintado '
      'de la hoja, no se ve nunca el título ni el estado y la hoja se cierra',
      (tester, phone) async {
        _holderInitial = [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ];
        await _openNoraWithPlans(tester, phone, ['p1']);
        final checkbox = find.descendant(
          of: find.ancestor(
            of: find.text('Bicicleta roja'),
            matching: find.byType(GiftRow),
          ),
          matching: find.byType(StatusCheckbox),
        );
        final gesture = await tester.startGesture(tester.getCenter(checkbox));
        // Justo después de que salte la pulsación larga (500 ms) y antes del
        // primer fotograma de la hoja, se quita el acceso.
        Timer(
          const Duration(milliseconds: 510),
          () => phone.container.read(_rowsHolder.notifier).set(const []),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(ChoiceGrid), findsNothing);
        expect(find.textContaining('Estado de'), findsNothing);
        await gesture.up();
        await tester.pump();
        expect(find.byType(ChoiceGrid), findsNothing);
        expect(find.textContaining('Estado de'), findsNothing);
        await settle(tester);
        expect(find.byType(ChoiceGrid), findsNothing);
        expect(find.textContaining('Estado de'), findsNothing);
        expect(
          ModalRoute.of(tester.element(find.byType(PersonListScreen)))
              ?.isCurrent,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
      overrides: _holderOverrides(_FakeWishService(), reader: 'aritz'),
    );

    screenTest(
      '3: el selector «Quién regala» del editor del plan se cierra si se '
      'revoca el acceso o se duda de él con la hoja abierta',
      (tester, phone) async {
        _holderInitial = [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ];
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        final giverField = find.bySemanticsLabel(RegExp(r'^Quién regala'));
        int pere() => find.text('Tío Pere').evaluate().length;
        final base = pere();

        // Dudosa: la hoja se retira, el editor se queda sin lo privado.
        await tester.tap(giverField.first);
        await settle(tester);
        expect(pere(), base + 1);
        phone.container.read(_uncertain.notifier).set(true);
        await settle(tester);
        expect(pere(), base);
        expect(find.text('Deseo cogido'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp(r'^Quién regala')), findsNothing);
        phone.container.read(_uncertain.notifier).set(false);
        await settle(tester);
        expect(find.bySemanticsLabel(RegExp(r'^Quién regala')), findsWidgets);

        // Revocada: la hoja y el editor se van, sin dejar la asignación.
        await tester.tap(giverField.first);
        await settle(tester);
        expect(pere(), base + 1);
        phone.container.read(_rowsHolder.notifier).set(const []);
        await settle(tester);
        expect(pere(), base);
        expect(find.byType(WishPlanEditor), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: const Size(390, 1500),
      overrides: [
        ..._holderOverrides(_FakeWishService(), reader: 'aritz'),
        _uncertainProjection,
      ],
    );

    screenTest(
      '3: el selector de estado también se retira mientras se recalcula la '
      'autorización, y no se abre si ya es dudosa',
      (tester, phone) async {
        _holderInitial = [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ];
        await _openNoraWithPlans(tester, phone, ['p1']);
        final checkbox = find.descendant(
          of: find.ancestor(
            of: find.text('Bicicleta roja'),
            matching: find.byType(GiftRow),
          ),
          matching: find.byType(StatusCheckbox),
        );
        await tester.longPress(checkbox);
        await settle(tester);
        expect(find.byType(ChoiceGrid), findsOneWidget);

        phone.container.read(_uncertain.notifier).set(true);
        await settle(tester);
        expect(find.byType(ChoiceGrid), findsNothing);
        expect(find.textContaining('Estado de Bicicleta'), findsNothing);

        // Con la autorización dudosa ni se abre.
        await tester.longPress(checkbox);
        await settle(tester);
        expect(find.byType(ChoiceGrid), findsNothing);

        phone.container.read(_uncertain.notifier).set(false);
        await settle(tester);
        await tester.longPress(checkbox);
        await settle(tester);
        expect(find.byType(ChoiceGrid), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: [
        ..._holderOverrides(_FakeWishService(), reader: 'aritz'),
        _uncertainProjection,
      ],
    );

    var gate = Completer<AuthorizedProjection?>();
    screenTest(
      '3: mientras se recalcula qué puede ver este móvil, el editor del plan '
      'no enseña precios, tienda ni notas hasta que las filas confirman',
      (tester, phone) async {
        gate = Completer<AuthorizedProjection?>();
        _holderInitial = [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ];
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        expect(find.text('Deseo cogido'), findsOneWidget);
        // Dudosa: nada de lo privado, ni en pantalla ni en accesibilidad, y
        // no se puede guardar.
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Previsto'), findsNothing);
        expect(find.bySemanticsLabel('Tienda'), findsNothing);
        expect(find.bySemanticsLabel('Notas'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Guardar'),
              )
              .onPressed,
          isNull,
        );

        gate.complete(null);
        await settle(tester);
        expect(find.byType(TextField), findsWidgets);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Guardar'),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
      overrides: [
        ..._holderOverrides(_FakeWishService(), reader: 'aritz'),
        authorizedProjectionProvider.overrideWith((ref) => gate.future),
      ],
    );

    // ---- 9: un quién regala que ya no existe se ve como «Sin asignar» ----
    final ghostService = _FakeWishService();
    screenTest(
      '9: un plan cuyo quién regala se borró (la web no toca los planes) se '
      've como «Sin asignar» y no rompe nada',
      (tester, phone) async {
        _holderInitial = [
          _row(WishPlanState.claimed, plans: [_plan('p1', giver: 'borrado')]),
        ];
        await _openNoraWithPlans(tester, phone, ['p1']);
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        expect(find.text('Deseo cogido'), findsOneWidget);
        expect(find.text('Sin asignar'), findsOneWidget);
        // Guardar sin tocar ese campo no pierde la referencia: ni la cambia
        // ni la vacía.
        ghostService.planPatches.clear();
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        final patch = ghostService.planPatches.single;
        expect(patch.giverId, isNull);
        expect(patch.clear, isNot(contains(WishPlanField.giverId)));
        expect(tester.takeException(), isNull);
      },
      overrides: _holderOverrides(
        ghostService,
        reader: 'aritz',
        planGiver: 'borrado',
      ),
    );

    // ---- 10: Reparto, quien no cogió el plan no elige quién regala ----
    final leoService = _FakeWishService();
    final leoOverrides = _overrides(
      leoService,
      reader: 'leo',
      rows: [
        _row(WishPlanState.claimed, plans: [_plan('p1')]),
      ],
      plans: {
        'wbike': [_plan('p1')],
      },
    );
    Future<void> seedAritzPlan(WidgetTester tester, FakePhone phone) async {
      leoService.calls.clear();
      await seedSample(tester, phone);
      await _seedPlanGifts(
        tester,
        phone,
        ['p1'],
        occasion: 'seed-tio',
        giver: 'pere',
      );
      await pumpRegalos(tester, phone);
    }

    Future<void> expectNoGiverPickerForLeo(
      WidgetTester tester,
      FakePhone phone,
    ) async {
      final readOnly = tester
          .widgetList<GiverChip>(find.byType(GiverChip))
          .where((c) => c.onTap == null)
          .toList();
      expect(
        readOnly,
        hasLength(1),
        reason: 'el plan de Aritz va sin selector',
      );
      // Tocar el chip no abre ningún selector ni crea a nadie.
      await tester.tap(find.byWidget(readOnly.single));
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(find.byType(GiverPicker), findsNothing);
      expect(leoService.calls, isEmpty);
      final state = await familyState(tester, phone);
      expect(state.view.giverForPerson('leo'), isNull);
      expect(tester.takeException(), isNull);
    }

    screenTest(
      '10: en el móvil de Leo, la lista de Reparto por ocasión no ofrece '
      'elegir quién regala el plan de Aritz',
      (tester, phone) async {
        await seedAritzPlan(tester, phone);
        await openFamily(tester, all: false);
        await tester.tap(find.bySemanticsLabel('Por ocasión'));
        await settle(tester);
        await expectNoGiverPickerForLeo(tester, phone);
      },
      size: const Size(390, 1500),
      overrides: leoOverrides,
    );

    screenTest(
      '10: en el móvil de Leo, la hoja de una celda de Reparto no ofrece '
      'elegir quién regala el plan de Aritz',
      (tester, phone) async {
        await seedAritzPlan(tester, phone);
        await openFamily(tester);
        await tester.tap(
          find.bySemanticsLabel(RegExp('^Tío Pere para Nora: 2 regalos')),
        );
        await settle(tester);
        await expectNoGiverPickerForLeo(tester, phone);
      },
      size: const Size(390, 1500),
      overrides: leoOverrides,
    );

    // ---- 11: la ficha de una persona con el bloque cerrado ----
    final lockedService = _FakeWishService();
    final lockedOverrides = [
      wishServiceProvider.overrideWithValue(lockedService),
      wishReaderProvider.overrideWithValue('aritz'),
      // La ficha de Nora está cerrada para este móvil: lo decide el bloque,
      // no el selector de personas.
      secretBlocksProvider.overrideWithValue([const SecretBlock('nora')]),
      canSuggestWishProvider.overrideWith((ref, id) => id == 'nora'),
      giftRecipientAccessProvider.overrideWith((ref) async {
        return [
          for (final id in ['aritz', 'nora', 'leo'])
            GiftRecipientAccess(
              recipient: Recipient(
                id: id,
                name: id == 'aritz'
                    ? 'Aritz'
                    : id == 'nora'
                    ? 'Nora'
                    : 'Leo',
                colorIndex: 0,
                archived: false,
              ),
              status: id == 'nora'
                  ? PersonProtectionStatus.active
                  : PersonProtectionStatus.unprotected,
              canSelect: id != 'nora',
              reason: id == 'nora'
                  ? ProtectedPersonReason.missingEpochKey
                  : null,
            ),
        ];
      }),
    ];

    for (final (name, size) in [
      ('móvil', const Size(390, 2400)),
      ('escritorio', const Size(1280, 800)),
    ]) {
      screenTest(
        '11: con el bloque de Nora cerrado, su ficha en $name guarda un '
        'botón para sugerir un deseo visible, con «Visible para» fijo y la '
        'sorpresa apagada con su motivo',
        (tester, phone) async {
          lockedService.calls.clear();
          await _openNora(tester, phone);
          expect(find.text('Sorpresas'), findsNothing);
          // Ni «Añadir regalo» ni «Añadir deseo» (no es su móvil): solo sugerir.
          expect(find.byTooltip('Añadir regalo'), findsNothing);
          expect(find.byTooltip('Añadir deseo'), findsNothing);
          final suggest = size.width >= 1000
              ? find.byKey(const ValueKey<String>('suggest-wish-header'))
              : find.byTooltip('Sugerir un deseo');
          expect(suggest, findsOneWidget);
          await tester.tap(suggest);
          await settle(tester);

          // «Visible para Nora»: encendido y fijo.
          final visible = find.byKey(
            const ValueKey<String>('gift-visible-switch'),
          );
          expect(visible, findsOneWidget);
          expect(find.text('Visible para Nora'), findsOneWidget);
          expect(
            tester.widget<RegalosSwitch>(
              find.descendant(
                of: visible,
                matching: find.byType(RegalosSwitch),
              ),
            ),
            isA<RegalosSwitch>()
                .having((s) => s.value, 'value', isTrue)
                .having((s) => s.onChanged, 'onChanged', isNull),
          );
          await tester.tap(visible);
          await settle(tester);
          expect(
            tester
                .widget<RegalosSwitch>(
                  find.descendant(
                    of: visible,
                    matching: find.byType(RegalosSwitch),
                  ),
                )
                .value,
            isTrue,
          );
          // La sorpresa, apagada y con su motivo.
          final surprise = find.byKey(
            const ValueKey<String>('gift-surprise-disabled'),
          );
          expect(surprise, findsOneWidget);
          expect(
            find.text(
              'Desde este móvil no se puede guardar una sorpresa para Nora: '
              'solo un deseo visible.',
            ),
            findsOneWidget,
          );
          expect(
            tester
                .widget<RegalosSwitch>(
                  find.descendant(
                    of: surprise,
                    matching: find.byType(RegalosSwitch),
                  ),
                )
                .onChanged,
            isNull,
          );

          await tester.enterText(find.byType(TextField).first, 'Patines');
          await tester.tap(find.text('Guardar'));
          await settle(tester);
          expect(lockedService.calls, ['suggest:nora:Patines:2026']);
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: lockedOverrides,
      );
    }
  });

  // Cuatro cambios de Daniel del 26-11 (QA 1.0.7: m9, m11 y el tablero).
  group('menores de 1.0.7', () {
    const cometa = Wish(
      id: 'wcometa',
      recipientId: 'extra0',
      authorPersonId: 'extra0',
      suggested: false,
      title: 'Cometa',
      year: 2026,
    );

    Future<void> seedExtra(WidgetTester tester, FakePhone phone) =>
        seedSample(tester, phone, extraPeople: 1);

    screenTest(
      'm11: quien no tiene regalos pero sí deseos dice solo «1 deseo» en '
      'Personas y en la cabecera',
      (tester, phone) async {
        await seedExtra(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.ensureVisible(find.text('Extra 1').first);
        await tester.pump();
        // La fila de Personas: sin «Sin regalos ·».
        expect(find.textContaining('Sin regalos ·'), findsNothing);
        expect(find.textContaining('1 deseo'), findsOneWidget);
        await tapText(tester, 'Extra 1');
        expect(find.textContaining('Sin regalos ·'), findsNothing);
        expect(find.text('1 deseo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        wishes: const [cometa],
      ),
    );

    screenTest('m11: con regalos y deseos sigue «N regalos · N deseo»', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tester.ensureVisible(find.text('Nora').first);
      await tester.pump();
      expect(
        find.textContaining(RegExp(r'\d+ regalos? · 1 deseo')),
        findsOneWidget,
      );
      await tapText(tester, 'Nora');
      // La cabecera: los regalos («N regalos ·») y, aparte, «1 deseo».
      expect(find.bySemanticsLabel('1 deseo'), findsOneWidget);
      expect(find.textContaining('Sin regalos'), findsNothing);
      expect(tester.takeException(), isNull);
    }, overrides: _overrides(_FakeWishService(), reader: 'aritz'));

    screenTest(
      'm9: la ficha de un deseo cogido es un botón con título, etiqueta y '
      'estado',
      (tester, phone) async {
        final handle = tester.ensureSemantics();
        await _openNoraWithPlans(tester, phone, ['p1']);
        final node = tester.getSemantics(
          find.descendant(
            of: find.byType(GiftRow),
            matching: find.text('Bicicleta roja'),
          ),
        );
        final data = node.getSemanticsData();
        expect(data.label, contains('Bicicleta roja'));
        expect(data.label, contains('Deseo'));
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.flagsCollection.isButton, isTrue);
        // Un solo nodo de botón para la ficha (el InkWell de dentro no suma
        // otro): sin contar la casilla de estado, que es otro botón.
        final buttons = <SemanticsNode>[];
        void walk(SemanticsNode n) {
          final d = n.getSemanticsData();
          if (d.flagsCollection.isButton &&
              d.label.contains('Bicicleta roja') &&
              !d.label.contains('Cambiar estado')) {
            buttons.add(n);
          }
          n.visitChildren((c) {
            walk(c);
            return true;
          });
        }

        walk(
          tester.getSemantics(
            find.ancestor(
              of: find.text('Bicicleta roja'),
              matching: find.byType(GiftRow),
            ),
          ),
        );
        expect(buttons, hasLength(1));
        // Y tocarla abre el editor «Deseo cogido».
        await tester.tap(find.text('Bicicleta roja'));
        await settle(tester);
        expect(find.text('Deseo cogido'), findsWidgets);
        handle.dispose();
      },
      overrides: _overrides(
        _FakeWishService(),
        reader: 'aritz',
        rows: [
          _row(WishPlanState.claimed, plans: [_plan('p1')]),
        ],
        plans: {
          'wbike': [_plan('p1')],
        },
      ),
    );

    screenTest(
      'tablero: la barra de personas cuenta los deseos, con la misma regla',
      (tester, phone) async {
        await seedExtra(tester, phone);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: phone.container,
            child: const RegalosApp(webSession: true),
          ),
        );
        await settle(tester);
        // Extra 1 no tiene regalos y sí un deseo: solo «1 deseo».
        expect(
          find.descendant(
            of: find.bySemanticsLabel(RegExp('^Extra 1')),
            matching: find.text('1 deseo'),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Sin regalos ·'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 10));
      },
      size: const Size(1536, 864),
      overrides: [
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
        ..._overrides(
          _FakeWishService(),
          reader: 'aritz',
          wishes: const [cometa],
        ),
      ],
    );
  });
}
