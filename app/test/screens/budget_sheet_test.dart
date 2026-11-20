import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/occasions/presentation/budget_sheet.dart';

import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import '../helpers/screens.dart';

const _santaId = 'seed-santa';
final _field = find.byKey(const ValueKey<String>('budget-sheet-field'));

Future<void> _open(WidgetTester tester, FakePhone phone, {String? id}) async {
  await pumpThemed(
    tester,
    UncontrolledProviderScope(
      container: phone.container,
      child: Consumer(
        builder: (context, ref, _) => FilledButton(
          onPressed: () => editOccasionBudget(
            context,
            occasion: id == null
                ? null
                : ref.read(familyViewProvider).occasionsById[id]!,
          ),
          child: const Text('Abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

String _amount(WidgetTester tester) =>
    tester.widget<TextField>(_field).controller!.text;

Future<void> _mergeBudget(
  WidgetTester tester,
  FakePhone phone,
  int cents,
) async {
  final local = (await familyState(tester, phone)).doc;
  final remoteClock = HlcClock(node: 'remote', last: local.maxStamp);
  final remote = local.set(remoteClock, Collections.occasions, _santaId, {
    Occasion.budgetField: cents,
  });
  await tester.runAsync(
    () => familyOf(phone).mergeRemote(remote, fromNode: remoteClock.node),
  );
  await tester.pump();
  final merged = (await familyState(tester, phone)).doc;
  expect(
    merged.record(Collections.occasions, _santaId)?.field(Occasion.budgetField),
    remote.record(Collections.occasions, _santaId)?.field(Occasion.budgetField),
  );
}

Future<void> _saveWithoutWriting(WidgetTester tester, FakePhone phone) async {
  final before = (await familyState(tester, phone)).doc;
  await tester.tap(find.text('Guardar'));
  await settleSaved(tester);
  expect(_field, findsNothing);
  expect(
    (await familyState(tester, phone)).doc.canonicalJson(),
    before.canonicalJson(),
  );
}

void main() {
  for (final initial in <int?>[10000, null]) {
    screenTest(
      'guardar el importe inicial ($initial) conserva el cambio remoto',
      (tester, phone) async {
        await seedSample(tester, phone);
        if (initial != null) {
          await setBudgets(tester, phone, {_santaId: initial});
        }
        await _open(tester, phone, id: _santaId);
        expect(_amount(tester), initial == null ? '' : '100');

        await _mergeBudget(tester, phone, 15000);
        await _saveWithoutWriting(tester, phone);
      },
    );
  }

  screenTest('elegir otra ocasión toma el presupuesto de ese momento', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await _open(tester, phone);
    expect(_amount(tester), isEmpty);

    await _mergeBudget(tester, phone, 12000);
    await tester.tap(find.text('Tió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Navidad'));
    await tester.pumpAndSettle();
    expect(_amount(tester), '120');

    await _mergeBudget(tester, phone, 15000);
    await _saveWithoutWriting(tester, phone);
  });

  screenTest(
    'el selector general nombra los cumpleaños de las personas archivadas',
    (tester, phone) async {
      await seedSample(tester, phone);
      await tester.runAsync(() async {
        await familyOf(phone).archiveRecipient('nora');
        await familyOf(phone).archiveRecipient('leo');
      });
      await tester.pump();
      await _open(tester, phone);
      await tester.tap(find.text('Tió'));
      await tester.pumpAndSettle();
      expect(find.text('Cumpleaños de Nora'), findsOneWidget);
      expect(find.text('Cumpleaños de Leo'), findsOneWidget);
      expect(find.text('Cumpleaños'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  screenTest('la hoja guarda aunque la sincronización retire su botón', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    phone.container.read(routerProvider).go('/occasions/budget');
    await settle(tester);
    final access = find.byKey(
      const ValueKey<String>('budget-set-first'),
      skipOffstage: false,
    );
    await tester.tap(access);
    await settle(tester);
    expect(_amount(tester), isEmpty);

    await _mergeBudget(tester, phone, 12000);
    await settle(tester);
    expect(access, findsNothing);
    await tester.tap(find.text('Tió').hitTestable());
    await settle(tester);
    await tester.tap(find.text('Navidad').hitTestable());
    await settle(tester);
    expect(_amount(tester), '120');
    await tester.enterText(_field, '135');
    await tester.tap(find.text('Guardar'));
    await settleSaved(tester);

    expect(_field, findsNothing);
    final view = phone.container.read(familyViewProvider);
    expect(view.occasionsById[_santaId]!.budgetCents, 13500);
    expect(tester.takeException(), isNull);
  }, size: const Size(390, 1500));
}
