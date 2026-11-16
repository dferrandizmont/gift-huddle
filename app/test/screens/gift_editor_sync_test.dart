import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';

import '../helpers/memory_stores.dart';
import '../helpers/screens.dart';

const _giftId = 'g2';
const _title = 'Libro de dinosaurios con solapas';

Future<void> _openEditor(WidgetTester tester, FakePhone phone) async {
  await seedSample(tester, phone);
  await pumpRegalos(tester, phone);
  await tapText(tester, 'Aritz');
  await tapText(tester, _title);
  expect(find.text('Editar regalo'), findsOneWidget);
}

Future<SyncRecord> _record(WidgetTester tester, FakePhone phone) async =>
    (await familyState(tester, phone)).doc.record(Collections.gifts, _giftId)!;

Future<FamilyDoc> _receive(
  WidgetTester tester,
  FakePhone phone,
  Map<String, Object?> fields,
) async {
  final state = await familyState(tester, phone);
  final remote = state.doc.set(
    HlcClock(node: 'remote', last: state.doc.maxStamp),
    Collections.gifts,
    _giftId,
    fields,
  );
  await tester.runAsync(
    () => familyOf(phone).mergeRemote(remote, fromNode: 'remote'),
  );
  await settle(tester);
  return remote;
}

void _expectUntouched(
  SyncRecord before,
  SyncRecord after, {
  Set<String> changed = const {},
}) {
  for (final entry in before.fields.entries) {
    if (changed.contains(entry.key)) {
      continue;
    }
    expect(after.field(entry.key)?.stamp, entry.value.stamp, reason: entry.key);
    expect(
      canonicalJsonOf(after[entry.key]),
      canonicalJsonOf(entry.value.value),
      reason: entry.key,
    );
  }
}

void main() {
  const tall = Size(390, 1500);

  screenTest('guardar conserva la edición local y otros campos remotos', (
    tester,
    phone,
  ) async {
    await _openEditor(tester, phone);
    await tester.enterText(
      find.widgetWithText(TextField, 'Regalo'),
      'Libro de dinosaurios grande',
    );
    final remote = await _receive(tester, phone, {
      'actualCents': 1599,
      'status': 'bought',
      'requestedBy': const RequestedByName('Nora').toFields(),
      'requestNote': 'Para leer juntos',
      'futureField': 'kept',
    });
    final before = await _record(tester, phone);

    await tapText(tester, 'Guardar');

    final after = await _record(tester, phone);
    expect(after['title'], 'Libro de dinosaurios grande');
    expect(after['actualCents'], 1599);
    expect(after['status'], 'bought');
    expect(after.field('title')!.stamp > remote.maxStamp!, isTrue);
    _expectUntouched(before, after, changed: {'title'});
    // El resultado sigue ganando cuando vuelve a fusionarse con el otro móvil.
    final saved = (await familyState(tester, phone)).doc;
    expect(remote.merge(saved).canonicalJson(), saved.canonicalJson());
  }, size: tall);

  screenTest('en el mismo campo gana el importe guardado por el usuario', (
    tester,
    phone,
  ) async {
    await _openEditor(tester, phone);
    await tester.enterText(find.widgetWithText(TextField, 'Previsto'), '21,50');
    final remote = await _receive(tester, phone, {
      'plannedCents': 1900,
      'title': 'Libro elegido por Nora',
    });
    final before = await _record(tester, phone);

    await tapText(tester, 'Guardar');

    final after = await _record(tester, phone);
    expect(after['plannedCents'], 2150);
    expect(after['title'], 'Libro elegido por Nora');
    expect(after.field('plannedCents')!.stamp > remote.maxStamp!, isTrue);
    _expectUntouched(before, after, changed: {'plannedCents'});
  }, size: tall);

  for (final revert in [false, true]) {
    screenTest(
      revert
          ? 'volver al valor inicial no pisa el título remoto'
          : 'guardar sin editar conserva los valores y sellos remotos',
      (tester, phone) async {
        await _openEditor(tester, phone);
        if (revert) {
          await tester.enterText(
            find.widgetWithText(TextField, 'Regalo'),
            'Otro libro',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Regalo'),
            _title,
          );
          // El mismo importe con otra escritura tampoco es una edición.
          await tester.enterText(
            find.widgetWithText(TextField, 'Previsto'),
            '18,00',
          );
        }
        await _receive(tester, phone, {
          'title': 'Libro elegido por Nora',
          'plannedCents': 2200,
          'status': 'bought',
        });
        final before = (await familyState(tester, phone)).doc;

        await tapText(tester, 'Guardar');

        expect(
          (await familyState(tester, phone)).doc.canonicalJson(),
          before.canonicalJson(),
        );
      },
      size: tall,
    );
  }

  screenTest('vaciar un campo escribe null y conserva los demás remotos', (
    tester,
    phone,
  ) async {
    await _openEditor(tester, phone);
    await tester.enterText(find.widgetWithText(TextField, 'Tienda'), '');
    final remote = await _receive(tester, phone, {
      'store': 'Otra librería',
      'actualCents': 1700,
    });
    final before = await _record(tester, phone);

    await tapText(tester, 'Guardar');

    final after = await _record(tester, phone);
    expect(after['store'], isNull);
    expect(after.field('store')!.stamp > remote.maxStamp!, isTrue);
    expect(after['actualCents'], 1700);
    _expectUntouched(before, after, changed: {'store'});
  }, size: tall);
}
