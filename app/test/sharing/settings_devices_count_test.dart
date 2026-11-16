// La fila «Móviles de la familia» de Ajustes cuenta los móviles reales: en v2
// sale del registro firmado (la web cuenta), con el móvil retirado es 1, y
// mientras el registro carga o falla no afirma ningún número. En v1,
// emparejado sigue siendo 2.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/settings/presentation/settings_screen.dart';
import 'package:regalos/features/sync/application/family_device_rows.dart';
import 'package:regalos/features/sync/application/family_devices.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';

import '../helpers/fake_sync_server.dart';
import '../sync/invite_approval_view_test.dart' show screenApp, phoneSize;
import '../sync/sync_harness.dart';
import 'family_devices_list_test.dart' show markV2;

class _Removed extends SyncController {
  @override
  SyncStatus build() => const SyncStatus(SyncPhase.removed);
}

/// Cuenta las lecturas del registro: subirla fuerza una recarga.
class _Reloads extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final _reloads = NotifierProvider<_Reloads, int>(_Reloads.new);

const _self = FamilyDeviceRow(deviceId: 'a', isSelf: true, personId: 'aritz');
const _nora = FamilyDeviceRow(deviceId: 'n', isSelf: false, personId: 'nora');
const _leo = FamilyDeviceRow(deviceId: 'l', isSelf: false, personId: 'leo');
const _web = FamilyDeviceRow(deviceId: 'w', isSelf: false, isWeb: true);

Future<SyncPhone> _phone(
  WidgetTester tester, {
  required bool v2,
  bool paired = false,
}) async {
  phoneSize(tester);
  late SyncPhone a;
  await tester.runAsync(() async {
    a = await SyncPhone.create(FakeSyncServer());
    await a.createFamily('Pixel de Aritz');
    if (paired) await a.family.markPaired(peerName: 'Móvil de Nora');
    if (v2) await markV2(a);
  });
  addTearDown(a.dispose);
  return a;
}

Future<void> _show(
  WidgetTester tester,
  SyncPhone a, {
  Future<List<FamilyDeviceRow>?> Function(Ref ref)? rows,
  bool removed = false,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: a.c,
      child: ProviderScope(
        overrides: [
          if (rows != null) familyDeviceRowsProvider.overrideWith(rows),
          if (removed) syncControllerProvider.overrideWith(_Removed.new),
        ],
        child: Builder(
          builder: (context) => screenApp(
            ProviderScope.containerOf(context),
            const SettingsScreen(),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Finder _row(String value) =>
    find.bySemanticsLabel('Móviles de la familia. $value');

final _anyCount = RegExp(r'^Móviles de la familia\. \d');
final _onlyThis = RegExp(r'^Móviles de la familia\. Solo');

void main() {
  testWidgets('v2 al recargar o fallar el registro, no se afirma el número '
      'viejo aunque Riverpod lo conserve', (tester) async {
    final handle = tester.ensureSemantics();
    final a = await _phone(tester, v2: true, paired: true);
    Future<List<FamilyDeviceRow>?> Function() next = () async => const [
      _self,
      _nora,
      _leo,
    ];
    await _show(
      tester,
      a,
      rows: (ref) {
        ref.watch(_reloads);
        return next();
      },
    );
    expect(_row('3'), findsOneWidget);
    // El proveedor con el doble está en el ámbito de la pantalla.
    ProviderContainer scope() =>
        ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));

    // Recarga en curso: el valor anterior sigue en el provider, no se enseña.
    final gate = Completer<List<FamilyDeviceRow>?>();
    next = () => gate.future;
    a.c.read(_reloads.notifier).bump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final reading = scope().read(familyDeviceRowsProvider);
    expect(reading.isLoading, isTrue);
    expect(reading.hasValue, isTrue, reason: 'Riverpod conserva el anterior');
    expect(find.bySemanticsLabel(_anyCount), findsNothing);
    expect(find.bySemanticsLabel(_onlyThis), findsNothing);

    // Llega el dato nuevo: ahora sí.
    gate.complete(const [_self, _nora]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_row('2'), findsOneWidget);

    // Falla la siguiente lectura: tampoco se afirma el número viejo.
    next = () async => throw StateError('registro ilegible');
    a.c.read(_reloads.notifier).bump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final failed = scope().read(familyDeviceRowsProvider);
    expect(failed.hasError, isTrue);
    expect(failed.hasValue, isTrue, reason: 'Riverpod conserva el anterior');
    expect(find.bySemanticsLabel(_anyCount), findsNothing);
    expect(find.bySemanticsLabel(_onlyThis), findsNothing);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });

  testWidgets('v2 con tres móviles, la web incluida: dice 3', (tester) async {
    final handle = tester.ensureSemantics();
    final a = await _phone(tester, v2: true, paired: true);
    await _show(tester, a, rows: (ref) async => const [_self, _nora, _web]);
    expect(_row('3'), findsOneWidget);
    expect(_row('2'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });

  testWidgets('v2 con cuatro móviles: dice 4, no 2', (tester) async {
    final handle = tester.ensureSemantics();
    final a = await _phone(tester, v2: true, paired: true);
    await _show(
      tester,
      a,
      rows: (ref) async => const [_self, _nora, _leo, _web],
    );
    expect(_row('4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });

  testWidgets('v2 con solo este móvil en el registro: «Solo este», aunque la '
      'marca de v1 siga puesta', (tester) async {
    final handle = tester.ensureSemantics();
    final a = await _phone(tester, v2: true, paired: true);
    await _show(tester, a, rows: (ref) async => const [_self]);
    expect(_row('Solo este'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });

  testWidgets('v2 con este móvil retirado: 1 y el estado, nunca 2', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final a = await _phone(tester, v2: true, paired: true);
    await _show(tester, a, rows: (ref) async => const [_self], removed: true);
    expect(
      find.bySemanticsLabel(RegExp(r'^Móviles de la familia\. 1 · ')),
      findsOneWidget,
    );
    expect(_row('2'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });

  testWidgets('v2 mientras carga el registro: no afirma ningún número', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final a = await _phone(tester, v2: true, paired: true);
    final gate = Completer<List<FamilyDeviceRow>?>();
    await _show(tester, a, rows: (ref) => gate.future);
    expect(find.bySemanticsLabel(_anyCount), findsNothing);
    expect(find.bySemanticsLabel(_onlyThis), findsNothing);
    // Al llegar, el número real.
    gate.complete(const [_self, _nora, _leo]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_row('3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });

  testWidgets('v2 si falla la lectura del registro: no afirma ningún número', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final a = await _phone(tester, v2: true, paired: true);
    await _show(
      tester,
      a,
      rows: (ref) async => throw StateError('registro ilegible'),
    );
    expect(find.bySemanticsLabel(_anyCount), findsNothing);
    expect(find.bySemanticsLabel(_onlyThis), findsNothing);
    expect(find.bySemanticsLabel('Móviles de la familia'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });

  testWidgets('v1 emparejado: sigue siendo 2', (tester) async {
    final handle = tester.ensureSemantics();
    final a = await _phone(tester, v2: false, paired: true);
    await _show(tester, a);
    expect(
      find.bySemanticsLabel(RegExp(r'^Móviles de la familia\. 2')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });

  testWidgets('v1 sin emparejar: «Solo este»', (tester) async {
    final handle = tester.ensureSemantics();
    final a = await _phone(tester, v2: false);
    await _show(tester, a);
    expect(_row('Solo este'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });
}
