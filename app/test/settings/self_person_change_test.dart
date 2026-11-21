// «Este móvil es de» en una familia v2 (fase 3, lote 3b): la hoja que explica
// las consecuencias antes de cambiar, la espera de aprobación después, el
// aviso de cambios agotados y el comportamiento de siempre en v1 o sin otros
// móviles. El controlador real se prueba en `test/sync`; aquí `choose` es un
// doble que apunta a quién se pidió y devuelve lo que se le dice.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/sync/application/family_device_review.dart';
import 'package:regalos/features/sync/application/family_device_rows.dart';
import 'package:regalos/features/sync/application/family_devices.dart';

import '../helpers/memory_stores.dart';
import '../helpers/other_phone.dart';
import '../helpers/screens.dart';

class _FakeSelf extends SelfRecipient {
  ChangeSelfPersonResult result = ChangeSelfPersonResult.pendingApproval;
  Object? error;
  final calls = <String?>[];

  @override
  Future<ChangeSelfPersonResult> choose(String? recipientId) async {
    calls.add(recipientId);
    final e = error;
    if (e != null) throw e;
    return result;
  }
}

const _selfRow = FamilyDeviceRow(deviceId: 'a', isSelf: true);
const _otherRow = FamilyDeviceRow(deviceId: 'n', isSelf: false);

const _confirmTitle = '¿Cambiar de quién es este móvil?';
const _pendingTitle = 'Esperando aprobación de otro móvil';

var _fake = _FakeSelf();
var _rows = <FamilyDeviceRow>[_selfRow, _otherRow];
var _review = DeviceReview.empty;

final _overrides = [
  selfRecipientIdProvider.overrideWith(() => _fake),
  familyDeviceRowsProvider.overrideWith((ref) async => _rows),
  deviceReviewProvider.overrideWith((ref) async => _review),
];

Future<void> _open(
  WidgetTester tester,
  FakePhone phone, {
  bool v2 = true,
  String? self,
}) async {
  _fake = _FakeSelf();
  await seedSample(tester, phone);
  if (self != null) {
    await tester.runAsync(() => familyOf(phone).setSelfRecipient(self));
  }
  if (v2) {
    await tester.runAsync(
      () => changedElsewhere(
        phone,
        (doc, clock) => doc.set(clock, Collections.meta, kProtocolRecordId, {
          kProtocolVersionField: kSyncProtocolV2,
        }),
      ),
    );
  }
  await pumpRegalos(tester, phone);
  await tester.tap(find.text('Ajustes').last);
  await settle(tester);
  await tester.tap(find.text('Este móvil es de'));
  await settle(tester);
}

/// Toca una opción de la hoja y deja que baje sola y siga el cambio.
Future<void> _pick(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).last);
  await settleSaved(tester);
}

void main() {
  setUp(() {
    _rows = [_selfRow, _otherRow];
    _review = DeviceReview.empty;
  });

  screenTest('v2 con otros móviles: explica las consecuencias y no cambia '
      'hasta confirmar', (tester, phone) async {
    await _open(tester, phone);
    await _pick(tester, 'Nora');
    expect(find.text(_confirmTitle), findsOneWidget);
    expect(
      find.text(
        'Este móvil dejará de ver los regalos de Nora y sus sorpresas.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('no verás las sorpresas de nadie'),
      findsOneWidget,
    );
    expect(
      find.textContaining('volver a confirmar algunos móviles'),
      findsOneWidget,
    );
    expect(_fake.calls, isEmpty);

    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect(find.text(_confirmTitle), findsNothing);
    expect(_fake.calls, isEmpty);
  }, overrides: _overrides);

  screenTest('v2: confirmar cambia y enseña «Esperando aprobación»', (
    tester,
    phone,
  ) async {
    await _open(tester, phone);
    await _pick(tester, 'Nora');
    await tester.tap(find.text('Cambiar de persona'));
    await settle(tester);
    expect(_fake.calls, ['nora']);
    expect(find.text(_pendingTitle), findsOneWidget);
    expect(find.textContaining('Este móvil ya es de Nora'), findsOneWidget);
    // Sin móviles sueltos no hay bandeja que abrir.
    expect(find.text('Revisar móviles'), findsNothing);
    await tester.tap(find.text('Entendido'));
    await settle(tester);
    expect(find.text(_pendingTitle), findsNothing);
  }, overrides: _overrides);

  screenTest('v2: elegir «Nadie» usa el texto sin persona', (
    tester,
    phone,
  ) async {
    await _open(tester, phone, self: 'nora');
    await _pick(tester, 'Nadie');
    expect(
      find.text(
        'Este móvil se quedará sin persona asignada y no podrá ver sorpresas '
        'mientras siga así.',
      ),
      findsOneWidget,
    );
    // Sin persona, que otro móvil lo apruebe no devuelve las sorpresas: no se
    // promete.
    expect(find.textContaining('Hasta que se apruebe el cambio'), findsNothing);
    await tester.tap(find.text('Cambiar de persona'));
    await settle(tester);
    expect(_fake.calls, [null]);
    expect(
      find.textContaining('Aunque lo aprueben, no podrá ver sorpresas'),
      findsOneWidget,
    );
  }, overrides: _overrides);

  screenTest('el selector dice que la elección se comparte en v2, no en v1', (
    tester,
    phone,
  ) async {
    await _open(tester, phone);
    expect(
      find.textContaining('El cambio se comparte con los demás móviles'),
      findsOneWidget,
    );
    expect(find.textContaining('no se comparte'), findsNothing);
  }, overrides: _overrides);

  screenTest('el selector de v1 conserva «no se comparte»', (
    tester,
    phone,
  ) async {
    await _open(tester, phone, v2: false);
    expect(
      find.text('Solo vale en este móvil; no se comparte.'),
      findsOneWidget,
    );
  }, overrides: _overrides);

  screenTest('v2 con móviles sueltos: la espera ofrece «Revisar móviles»', (
    tester,
    phone,
  ) async {
    _review = const DeviceReview([
      DeviceReviewItem(
        deviceId: 'l',
        personId: 'leo',
        reason: DeviceReviewReason.orphan,
        recordDigest: 'd-l',
      ),
    ]);
    await _open(tester, phone);
    await _pick(tester, 'Nora');
    await tester.tap(find.text('Cambiar de persona'));
    await settle(tester);
    expect(find.text(_pendingTitle), findsOneWidget);
    expect(find.textContaining('esperan que los confirmes'), findsOneWidget);
    await tester.tap(find.text('Revisar móviles'));
    await settle(tester);
    expect(find.text('¿Este móvil es de Leo?'), findsOneWidget);
  }, overrides: _overrides);

  screenTest('v2 sin otros móviles: sin hoja de aviso, pero sí la espera', (
    tester,
    phone,
  ) async {
    _rows = [_selfRow];
    await _open(tester, phone);
    await _pick(tester, 'Nora');
    expect(find.text(_confirmTitle), findsNothing);
    expect(_fake.calls, ['nora']);
    expect(find.text(_pendingTitle), findsOneWidget);
  }, overrides: _overrides);

  screenTest('v1: se cambia sin hoja de aviso y sin espera', (
    tester,
    phone,
  ) async {
    await _open(tester, phone, v2: false);
    _fake.result = ChangeSelfPersonResult.localOnly;
    await _pick(tester, 'Nora');
    expect(find.text(_confirmTitle), findsNothing);
    expect(find.text(_pendingTitle), findsNothing);
    expect(_fake.calls, ['nora']);
  }, overrides: _overrides);

  screenTest('sin cambios que hacer (unchanged) no enseña nada', (
    tester,
    phone,
  ) async {
    await _open(tester, phone);
    _fake.result = ChangeSelfPersonResult.unchanged;
    await _pick(tester, 'Nora');
    await tester.tap(find.text('Cambiar de persona'));
    await settle(tester);
    expect(_fake.calls, ['nora']);
    expect(find.text(_pendingTitle), findsNothing);
  }, overrides: _overrides);

  screenTest('cambios agotados: explica que puede volver a conectarse como '
      'móvil nuevo', (tester, phone) async {
    await _open(tester, phone);
    _fake.error = const SelfPersonSequenceExhaustedException();
    await _pick(tester, 'Nora');
    await tester.tap(find.text('Cambiar de persona'));
    await settle(tester);
    expect(
      find.text('Este móvil ya no puede cambiar de persona'),
      findsOneWidget,
    );
    expect(find.textContaining('como un móvil nuevo'), findsOneWidget);
    expect(find.text(_pendingTitle), findsNothing);
    await tester.tap(find.text('Entendido'));
    await settle(tester);
    expect(find.textContaining('ya no puede cambiar'), findsNothing);
  }, overrides: _overrides);

  screenTest('un fallo al guardar avisa y no enseña la espera', (
    tester,
    phone,
  ) async {
    await _open(tester, phone);
    _fake.error = StateError('almacén');
    await _pick(tester, 'Nora');
    await tester.tap(find.text('Cambiar de persona'));
    await settle(tester);
    expect(
      find.text('No se ha podido guardar. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(find.text(_pendingTitle), findsNothing);
  }, overrides: _overrides);

  screenTest(
    'la hoja de aviso, en modo oscuro y con «Reducir movimiento»',
    (tester, phone) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await _open(tester, phone);
      await _pick(tester, 'Leo');
      expect(find.text(_confirmTitle), findsOneWidget);
      await tester.tap(find.text('Cambiar de persona'));
      await settle(tester);
      expect(find.text(_pendingTitle), findsOneWidget);
    },
    brightness: Brightness.dark,
    overrides: _overrides,
  );
}
