// Móviles de la familia, gestión (fase 3, lote «Móviles»): cada fila se
// toca y abre su hoja; quitar un móvil con aviso N7 y consecuencias; y la
// bandeja «Revisar móviles», uno a uno. Las acciones son un doble que apunta
// lo que se le pide; el controlador real se prueba en
// `test/sync/family_device_review_app_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/sharing/presentation/share_screen.dart';
import 'package:regalos/features/sync/application/family_device_review.dart';
import 'package:regalos/features/sync/application/family_device_rows.dart';
import 'package:regalos/features/sync/application/family_devices.dart';

import '../helpers/fake_sync_server.dart';
import '../sync/invite_approval_view_test.dart' show screenApp, phoneSize;
import '../sync/sync_harness.dart';
import 'family_devices_list_test.dart' show markV2;

class _ReviewState extends Notifier<DeviceReview> {
  @override
  DeviceReview build() => DeviceReview.empty;

  void set(DeviceReview review) => state = review;
}

final _reviewState = NotifierProvider<_ReviewState, DeviceReview>(
  _ReviewState.new,
);

class _Actions implements FamilyDeviceActions {
  _Actions(this.container);

  final ProviderContainer container;
  final calls = <String>[];
  var preview = const DeviceRemovalPreview(selfWouldWait: false);
  List<DeviceReviewItem> orphansOnRemove = const [];
  bool failApprove = false;
  final digests = <String?>[];

  /// La próxima aprobación falla porque el móvil publicó otra ficha: esta.
  DeviceReviewItem? staleOnApprove;

  /// El primer quitar avisa de que cambió la situación (N7).
  bool changeOnFirstRemove = false;

  /// Lo que lanza el siguiente quitar, si algo.
  Object? removeError;

  void _drop(String id) {
    final review = container.read(_reviewState);
    container
        .read(_reviewState.notifier)
        .set(
          DeviceReview([
            for (final i in review.items)
              if (i.deviceId != id) i,
          ]),
        );
  }

  @override
  Future<DeviceRemovalPreview> previewRemoval(String deviceId) async {
    calls.add('preview $deviceId');
    return preview;
  }

  @override
  Future<List<DeviceReviewItem>> remove(
    String deviceId, {
    bool selfWaitAccepted = false,
  }) async {
    calls.add('remove $deviceId');
    if (changeOnFirstRemove) {
      changeOnFirstRemove = false;
      preview = const DeviceRemovalPreview(selfWouldWait: true);
      throw const DeviceRemovalChangedException();
    }
    final error = removeError;
    if (error != null) {
      removeError = null;
      _drop(deviceId);
      throw error;
    }
    _drop(deviceId);
    if (orphansOnRemove.isNotEmpty) {
      final review = container.read(_reviewState);
      container
          .read(_reviewState.notifier)
          .set(DeviceReview([...review.items, ...orphansOnRemove]));
    }
    return orphansOnRemove;
  }

  @override
  Future<void> approve(String deviceId, {String? recordDigest}) async {
    calls.add('approve $deviceId');
    digests.add(recordDigest);
    final stale = staleOnApprove;
    if (stale != null) {
      staleOnApprove = null;
      container.read(_reviewState.notifier).set(DeviceReview([stale]));
      throw const DeviceRecordChangedException();
    }
    if (failApprove) throw StateError('sin red');
    _drop(deviceId);
  }
}

const _self = FamilyDeviceRow(
  deviceId: 'a',
  isSelf: true,
  personId: 'aritz',
  deviceName: 'Pixel de Aritz',
);
const _nora = FamilyDeviceRow(deviceId: 'n', isSelf: false, personId: 'nora');

DeviceReviewItem _item(String id, String person, DeviceReviewReason reason) =>
    DeviceReviewItem(
      deviceId: id,
      personId: person,
      reason: reason,
      recordDigest: 'd-$id',
    );

Future<(SyncPhone, _Actions)> _open(
  WidgetTester tester, {
  List<FamilyDeviceRow> rows = const [_self, _nora],
  DeviceReview review = DeviceReview.empty,
}) async {
  phoneSize(tester);
  late SyncPhone a;
  await tester.runAsync(() async {
    a = await SyncPhone.create(FakeSyncServer());
    await a.createFamily('Pixel de Aritz');
    for (final name in ['Aritz', 'Nora', 'Leo']) {
      await a.family.upsertRecipient(
        Recipient(
          id: name.toLowerCase(),
          name: name,
          colorIndex: 0,
          archived: false,
        ),
      );
    }
    await markV2(a);
  });
  addTearDown(a.dispose);
  a.c.read(_reviewState.notifier).set(review);
  final actions = _Actions(a.c);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: a.c,
      child: ProviderScope(
        overrides: [
          familyDeviceRowsProvider.overrideWith((ref) async => rows),
          deviceReviewProvider.overrideWith(
            (ref) async => ref.watch(_reviewState),
          ),
          familyDeviceActionsProvider.overrideWithValue(actions),
        ],
        child: Builder(
          builder: (context) => screenApp(
            ProviderScope.containerOf(context),
            const ShareScreen(),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return (a, actions);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.tap(find.text(text).first);
  await _settle(tester);
}

void main() {
  group('la lista y la hoja de un móvil', () {
    testWidgets('el estado de cada fila: pendiente, congelado, sin persona', (
      tester,
    ) async {
      await _open(
        tester,
        rows: const [
          _self,
          _nora,
          FamilyDeviceRow(deviceId: 'x', isSelf: false),
        ],
        review: DeviceReview([
          _item('l', 'leo', DeviceReviewReason.newcomer),
          _item('n', 'nora', DeviceReviewReason.frozen),
        ]),
      );
      expect(find.text('Congelado: espera aprobación'), findsOneWidget);
      expect(find.text('Espera aprobación'), findsOneWidget);
      expect(
        find.text('Sin persona: aún no abre las sorpresas'),
        findsOneWidget,
      );
      // El contador es el de los móviles activos, no cuenta a los pendientes.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Hay móviles por revisar'), findsOneWidget);
      expect(find.text('2 móviles esperan que los confirmes.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tocar un móvil abre su hoja con quién es y su estado', (
      tester,
    ) async {
      await _open(tester);
      await _tapText(tester, 'Nora');
      expect(find.text('De quién es'), findsOneWidget);
      expect(find.text('Estado'), findsOneWidget);
      expect(
        find.text('Conectado'),
        findsNWidgets(2),
        reason: 'subtítulo y fila',
      );
      expect(find.text('Quitar este móvil'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('este móvil: su hoja no deja quitarlo y manda a «Dejar de '
        'sincronizar»', (tester) async {
      await _open(tester);
      await _tapText(tester, 'Aritz');
      expect(find.textContaining('Este es tu móvil'), findsOneWidget);
      expect(find.text('Quitar este móvil'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('quitar un móvil', () {
    testWidgets('pide confirmación con las consecuencias y quita', (
      tester,
    ) async {
      final (_, actions) = await _open(tester);
      await _tapText(tester, 'Nora');
      await _tapText(tester, 'Quitar este móvil');
      expect(actions.calls, ['preview n']);
      expect(find.text('¿Quitar este móvil?'), findsOneWidget);
      expect(
        find.textContaining('Lo que ya tiene guardado no se le puede borrar'),
        findsOneWidget,
      );
      expect(find.textContaining('puede perderse'), findsOneWidget);
      await _tapText(tester, 'Quitar móvil');
      expect(actions.calls, ['preview n', 'remove n']);
      expect(find.text('Móvil quitado'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('cancelar la confirmación no quita nada', (tester) async {
      final (_, actions) = await _open(tester);
      await _tapText(tester, 'Nora');
      await _tapText(tester, 'Quitar este móvil');
      await _tapText(tester, 'Cancelar');
      expect(actions.calls, ['preview n']);
      expect(find.text('Móvil quitado'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('N7: avisa antes si este móvil volvería a esperar aprobación', (
      tester,
    ) async {
      final (_, actions) = await _open(tester);
      actions.preview = const DeviceRemovalPreview(selfWouldWait: true);
      await _tapText(tester, 'Nora');
      await _tapText(tester, 'Quitar este móvil');
      expect(
        find.text('Este móvil volverá a esperar aprobación'),
        findsOneWidget,
      );
      // Primero el aviso; la confirmación general viene después.
      expect(find.text('¿Quitar este móvil?'), findsNothing);
      await _tapText(tester, 'Cancelar');
      expect(actions.calls, ['preview n']);
      expect(find.text('Móvil quitado'), findsNothing);

      // Otra vez: seguir con el aviso lleva a la confirmación.
      await _tapText(tester, 'Quitar este móvil');
      await _tapText(tester, 'Quitar igualmente');
      expect(find.text('¿Quitar este móvil?'), findsOneWidget);
      await _tapText(tester, 'Quitar móvil');
      expect(actions.calls.last, 'remove n');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'si quedan huérfanos, sigue la bandeja y se aprueban uno a uno',
      (tester) async {
        final (_, actions) = await _open(tester);
        actions.orphansOnRemove = [
          _item('l', 'leo', DeviceReviewReason.orphan),
        ];
        await _tapText(tester, 'Nora');
        await _tapText(tester, 'Quitar este móvil');
        await _tapText(tester, 'Quitar móvil');
        expect(actions.calls, ['preview n', 'remove n']);
        expect(find.text('¿Este móvil es de Leo?'), findsOneWidget);
        expect(find.textContaining('Dejó de estar enlazado'), findsOneWidget);
        await _tapText(tester, 'Sí, es de Leo');
        expect(actions.calls.last, 'approve l');
        expect(find.text('Todo revisado'), findsOneWidget);
        await _tapText(tester, 'Entendido');
        expect(find.text('Todo revisado'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('bandeja «Revisar móviles»', () {
    testWidgets('un pendiente y un huérfano: uno a uno, nunca en bloque', (
      tester,
    ) async {
      final (_, actions) = await _open(
        tester,
        rows: const [_self],
        review: DeviceReview([
          _item('l', 'leo', DeviceReviewReason.personChanged),
          _item('n', 'nora', DeviceReviewReason.orphan),
        ]),
      );
      expect(find.text('Hay móviles por revisar'), findsOneWidget);
      await _tapText(tester, 'Revisar móviles');
      expect(find.text('¿Este móvil es de Leo?'), findsOneWidget);
      expect(find.text('1 de 2'), findsOneWidget);
      // Un cambio de persona avisa de que podrá avalar a otros.
      expect(
        find.textContaining('podrá avalar a otros móviles'),
        findsOneWidget,
      );
      // No hay botón de aprobar todos.
      expect(find.textContaining('todos'), findsNothing);

      await _tapText(tester, 'Sí, es de Leo');
      expect(actions.calls, ['approve l']);
      expect(find.text('¿Este móvil es de Nora?'), findsOneWidget);
      expect(find.text('Todo revisado'), findsNothing);

      await _tapText(tester, 'Sí, es de Nora');
      expect(actions.calls, ['approve l', 'approve n']);
      expect(find.text('Todo revisado'), findsOneWidget);
      await _tapText(tester, 'Entendido');
      expect(find.text('Hay móviles por revisar'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('«Después» pasa al siguiente sin aprobar ni quitar', (
      tester,
    ) async {
      final (_, actions) = await _open(
        tester,
        rows: const [_self],
        review: DeviceReview([
          _item('l', 'leo', DeviceReviewReason.newcomer),
          _item('n', 'nora', DeviceReviewReason.detached),
        ]),
      );
      await _tapText(tester, 'Revisar móviles');
      expect(find.text('¿Este móvil es de Leo?'), findsOneWidget);
      await _tapText(tester, 'Después');
      expect(find.text('¿Este móvil es de Nora?'), findsOneWidget);
      expect(find.textContaining('te confirmó a ti'), findsOneWidget);
      expect(actions.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('quitar desde la bandeja pasa por la misma confirmación', (
      tester,
    ) async {
      final (_, actions) = await _open(
        tester,
        rows: const [_self],
        review: DeviceReview([_item('l', 'leo', DeviceReviewReason.newcomer)]),
      );
      await _tapText(tester, 'Revisar móviles');
      await _tapText(tester, 'Quitar este móvil');
      expect(find.text('¿Quitar este móvil?'), findsOneWidget);
      await _tapText(tester, 'Quitar móvil');
      expect(actions.calls, ['preview l', 'remove l']);
      expect(find.text('Todo revisado'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('si falla aprobar, lo dice y deja reintentar', (tester) async {
      final (_, actions) = await _open(
        tester,
        rows: const [_self],
        review: DeviceReview([_item('l', 'leo', DeviceReviewReason.newcomer)]),
      );
      actions.failApprove = true;
      await _tapText(tester, 'Revisar móviles');
      await _tapText(tester, 'Sí, es de Leo');
      expect(find.text('No se ha podido aprobar el móvil.'), findsOneWidget);
      actions.failApprove = false;
      await _tapText(tester, 'Sí, es de Leo');
      expect(find.text('Todo revisado'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('un móvil congelado se revisa igual y la hoja lo dice', (
      tester,
    ) async {
      await _open(
        tester,
        review: DeviceReview([_item('n', 'nora', DeviceReviewReason.frozen)]),
      );
      await _tapText(tester, 'Nora');
      expect(find.text('Congelado'), findsWidgets);
      await _tapText(tester, 'Aprobar este móvil');
      expect(find.text('¿Este móvil es de Nora?'), findsOneWidget);
      expect(
        find.textContaining('Sus cambios están congelados'),
        findsOneWidget,
      );
      await _tapText(tester, 'Sí, es de Nora');
      expect(find.text('Móvil aprobado'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('la ficha cambia mientras se revisa', () {
    testWidgets('en la bandeja: avisa, y se avala la ficha que ahora se '
        'enseña', (tester) async {
      final (a, actions) = await _open(
        tester,
        rows: const [_self],
        review: DeviceReview([_item('l', 'leo', DeviceReviewReason.newcomer)]),
      );
      await _tapText(tester, 'Revisar móviles');
      expect(find.text('¿Este móvil es de Leo?'), findsOneWidget);
      expect(find.textContaining('ha cambiado'), findsNothing);
      // El móvil publica una ficha nueva, ahora de Nora.
      a.c
          .read(_reviewState.notifier)
          .set(
            DeviceReview([
              const DeviceReviewItem(
                deviceId: 'l',
                personId: 'nora',
                reason: DeviceReviewReason.personChanged,
                recordDigest: 'd-l2',
              ),
            ]),
          );
      await _settle(tester);
      expect(find.text('¿Este móvil es de Nora?'), findsOneWidget);
      expect(
        find.text('Este móvil ha cambiado: revisa de nuevo.'),
        findsOneWidget,
      );
      await _tapText(tester, 'Sí, es de Nora');
      expect(actions.digests, ['d-l2']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('si falla el aval por la carrera, relee y vuelve a '
        'preguntar sin aprobar', (tester) async {
      final (_, actions) = await _open(
        tester,
        rows: const [_self],
        review: DeviceReview([_item('l', 'leo', DeviceReviewReason.newcomer)]),
      );
      actions.staleOnApprove = const DeviceReviewItem(
        deviceId: 'l',
        personId: 'nora',
        reason: DeviceReviewReason.personChanged,
        recordDigest: 'd-l2',
      );
      await _tapText(tester, 'Revisar móviles');
      await _tapText(tester, 'Sí, es de Leo');
      expect(actions.digests, ['d-l']);
      expect(find.text('Todo revisado'), findsNothing);
      expect(
        find.text('Este móvil ha cambiado: revisa de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('¿Este móvil es de Nora?'), findsOneWidget);
      expect(find.text('No se ha podido aprobar el móvil.'), findsNothing);
      await _tapText(tester, 'Sí, es de Nora');
      expect(actions.digests, ['d-l', 'd-l2']);
      expect(find.text('Todo revisado'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('en la hoja de un móvil: avisa y vuelve a preguntar', (
      tester,
    ) async {
      final (a, actions) = await _open(
        tester,
        review: DeviceReview([_item('n', 'nora', DeviceReviewReason.newcomer)]),
      );
      await _tapText(tester, 'Nora');
      await _tapText(tester, 'Aprobar este móvil');
      expect(find.text('¿Este móvil es de Nora?'), findsOneWidget);
      a.c
          .read(_reviewState.notifier)
          .set(
            DeviceReview([
              const DeviceReviewItem(
                deviceId: 'n',
                personId: 'leo',
                reason: DeviceReviewReason.personChanged,
                recordDigest: 'd-n2',
              ),
            ]),
          );
      await _settle(tester);
      expect(
        find.text('Este móvil ha cambiado: revisa de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('¿Este móvil es de Leo?'), findsOneWidget);
      await _tapText(tester, 'Sí, es de Leo');
      expect(actions.digests, ['d-n2']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('la ficha nueva sin persona', () {
    testWidgets('la pregunta y el botón salen de la ficha que se firma, no '
        'de la persona anterior', (tester) async {
      final (a, actions) = await _open(
        tester,
        review: DeviceReview([_item('n', 'nora', DeviceReviewReason.newcomer)]),
      );
      await _tapText(tester, 'Nora');
      await _tapText(tester, 'Aprobar este móvil');
      expect(find.text('¿Este móvil es de Nora?'), findsOneWidget);
      a.c
          .read(_reviewState.notifier)
          .set(
            DeviceReview([
              const DeviceReviewItem(
                deviceId: 'n',
                reason: DeviceReviewReason.personChanged,
                recordDigest: 'd-n2',
              ),
            ]),
          );
      await _settle(tester);
      expect(find.text('¿Aprobar este móvil?'), findsOneWidget);
      expect(find.text('¿Este móvil es de Nora?'), findsNothing);
      expect(find.text('Sí, es de Nora'), findsNothing);
      await _tapText(tester, 'Aprobar este móvil');
      expect(actions.digests, ['d-n2']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('quitar: casos límite', () {
    testWidgets('N7 se vuelve a comprobar justo antes: si cambió, avisa y '
        'pregunta de nuevo', (tester) async {
      final (_, actions) = await _open(tester);
      actions.changeOnFirstRemove = true;
      await _tapText(tester, 'Nora');
      await _tapText(tester, 'Quitar este móvil');
      await _tapText(tester, 'Quitar móvil');
      expect(actions.calls, ['preview n', 'remove n', 'preview n']);
      expect(
        find.text('Este móvil volverá a esperar aprobación'),
        findsOneWidget,
      );
      await _tapText(tester, 'Quitar igualmente');
      await _tapText(tester, 'Quitar móvil');
      expect(actions.calls.last, 'remove n');
      expect(find.text('Móvil quitado'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('quitado aquí pero falta cortar el acceso: lo dice, no '
        '«No se ha podido quitar»', (tester) async {
      final (_, actions) = await _open(tester);
      actions.removeError = const DeviceRemovalPendingException([]);
      await _tapText(tester, 'Nora');
      await _tapText(tester, 'Quitar este móvil');
      await _tapText(tester, 'Quitar móvil');
      expect(
        find.text(
          'Quitado de este móvil. Falta cortar su acceso: se hará en cuanto '
          'haya conexión.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('No se ha podido quitar'), findsNothing);
      expect(find.text('Móvil quitado'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('con huérfanos y corte pendiente, sigue la bandeja', (
      tester,
    ) async {
      final (a, actions) = await _open(tester);
      final orphan = _item('l', 'leo', DeviceReviewReason.orphan);
      actions.removeError = DeviceRemovalPendingException([orphan]);
      a.c.read(_reviewState.notifier).set(DeviceReview([orphan]));
      await _tapText(tester, 'Nora');
      await _tapText(tester, 'Quitar este móvil');
      await _tapText(tester, 'Quitar móvil');
      expect(find.text('¿Este móvil es de Leo?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('un huérfano con ficha cambiada avisa de que podrá avalar a '
        'otros', (tester) async {
      await _open(
        tester,
        rows: const [_self],
        review: const DeviceReview([
          DeviceReviewItem(
            deviceId: 'l',
            personId: 'leo',
            reason: DeviceReviewReason.orphan,
            recordDigest: 'd-l',
            recordChanged: true,
          ),
        ]),
      );
      await _tapText(tester, 'Revisar móviles');
      expect(find.textContaining('Dejó de estar enlazado'), findsOneWidget);
      expect(
        find.textContaining('podrá avalar a otros móviles'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}
