import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/hlc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/pairing_v2.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/family/data/device_keys_store.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/family/presentation/protection_actions.dart';
import 'package:regalos/features/family/presentation/protection_sheet.dart';

import '../helpers/memory_stores.dart' show FakePhone;
import '../helpers/other_phone.dart';
import '../helpers/screens.dart';
import '../helpers/tablet.dart';

// Fase 3, lote 6: la interfaz de los regalos en secreto. La lógica ya está
// probada en `test/sync/person_protection_app_test.dart`; aquí se comprueba
// lo que ve y toca la persona, con los proveedores de lectura sustituidos y un
// controlador que apunta las llamadas.

const Recipient _nora = Recipient(
  id: 'nora',
  name: 'Nora',
  colorIndex: 4,
  birthMonth: 6,
  birthDay: 12,
  birthYear: 2022,
  archived: false,
);

const List<Recipient> _people = <Recipient>[
  Recipient(
    id: 'aritz',
    name: 'Aritz',
    colorIndex: 0,
    birthMonth: 3,
    birthDay: 14,
    birthYear: 2019,
    archived: false,
  ),
  _nora,
  Recipient(
    id: 'leo',
    name: 'Leo',
    colorIndex: 3,
    birthMonth: 8,
    birthDay: 3,
    birthYear: 2024,
    archived: false,
  ),
];

/// El estado de la protección de Nora, que mueven las acciones del
/// controlador de prueba.
class _Status extends Notifier<PersonProtectionStatus> {
  @override
  PersonProtectionStatus build() => PersonProtectionStatus.unprotected;

  void set(PersonProtectionStatus status) => state = status;
}

final _status = NotifierProvider<_Status, PersonProtectionStatus>(_Status.new);

/// Los regalos pendientes que se ven; el reintento los quita o no.
class _Pending extends Notifier<List<PendingProtectedGift>> {
  @override
  List<PendingProtectedGift> build() => const <PendingProtectedGift>[];

  void set(List<PendingProtectedGift> pending) => state = pending;
}

final _pending = NotifierProvider<_Pending, List<PendingProtectedGift>>(
  _Pending.new,
);

Gift _gift(String id, String recipient, String title) => Gift(
  id: id,
  recipientId: recipient,
  title: title,
  status: GiftStatus.idea,
  rawStatus: 'idea',
  surprise: false,
  year: 2026,
);

/// Acciones de protección de prueba: apuntan las llamadas y mueven el estado.
class _Actions implements ProtectionActions {
  _Actions(this._ref);

  final Ref _ref;
  final List<String> calls = <String>[];

  /// Si es distinto de `null`, las acciones de protección fallan con ese
  /// motivo.
  ProtectedPersonReason? failWith;

  /// Si el reintento deja los pendientes.
  bool retryKeeps = false;

  void _maybeFail(String personId) {
    final reason = failWith;
    if (reason != null) {
      throw ProtectedPersonException(personId, reason: reason);
    }
  }

  @override
  Future<void> request(String personId) async {
    calls.add('request:$personId');
    _maybeFail(personId);
    _ref.read(_status.notifier).set(PersonProtectionStatus.requested);
  }

  @override
  Future<void> activate(String personId) async {
    calls.add('activate:$personId');
    _maybeFail(personId);
    _ref.read(_status.notifier).set(PersonProtectionStatus.active);
  }

  @override
  Future<void> deactivate(String personId) async {
    calls.add('deactivate:$personId');
    _maybeFail(personId);
    _ref.read(_status.notifier).set(PersonProtectionStatus.unprotected);
  }

  @override
  Future<void> retryPending(String personId) async {
    calls.add('retry:$personId');
    if (!retryKeeps) {
      _ref.read(_pending.notifier).set(const <PendingProtectedGift>[]);
    }
  }
}

/// Controlador de prueba: un guardado de regalo puede acabar rechazado.
class _Family extends FamilyController {
  final List<String> calls = <String>[];

  /// Cómo acaba un guardado de regalo: lo que lanza, o `null` para guardar.
  ProtectedPersonException? upsertThrows;

  @override
  Future<GiftWriteResult> upsertGiftResult(Gift gift, {Gift? original}) async {
    final error = upsertThrows;
    if (error != null) {
      calls.add('upsert-rejected');
      throw error;
    }
    return super.upsertGiftResult(gift, original: original);
  }
}

/// Las sustituciones de lectura de Nora: su [status] sale del proveedor de
/// prueba; [canConfirm] y [canDeactivate] dicen qué permite este móvil.
List<Override> _overrides({
  bool canConfirm = true,
  bool canDeactivate = true,
  ProtectedPersonReason? noraReason,
  bool noraSelectable = true,
  bool canRequest = true,
  ProtectedPersonReason? requestReason,
  bool ownPhone = false,
  Set<String> locked = const <String>{},
}) => [
  familyControllerProvider.overrideWith(_Family.new),
  protectionActionsProvider.overrideWith(_Actions.new),
  protectionAvailableProvider.overrideWithValue(true),
  giftRecipientAccessProvider.overrideWith((ref) async {
    final status = ref.watch(_status);
    return [
      for (final p in _people)
        if (p.id == 'nora')
          GiftRecipientAccess(
            recipient: p,
            status: status,
            canSelect: noraSelectable,
            canRequest: canRequest,
            requestReason: canRequest ? null : requestReason,
            viewerIsRecipient: ownPhone,
            reason: noraSelectable ? null : noraReason,
            canConfirm:
                canConfirm && status == PersonProtectionStatus.requested,
            canDeactivate:
                canDeactivate && status == PersonProtectionStatus.active,
          )
        else
          GiftRecipientAccess(
            recipient: p,
            status: PersonProtectionStatus.unprotected,
            canSelect: true,
          ),
    ];
  }),
  secretBlocksProvider.overrideWithValue([
    for (final id in locked) SecretBlock(id),
  ]),
  pendingProtectedGiftsProvider.overrideWith(
    (ref) async => ref.watch(_pending),
  ),
];

_Family _family(FakePhone phone) =>
    phone.container.read(familyControllerProvider.notifier) as _Family;

_Actions _actions(FakePhone phone) =>
    phone.container.read(protectionActionsProvider) as _Actions;

/// Abre la hoja de Nora desde su lista: Personas › Nora › editar.
Future<void> _openNoraSheet(WidgetTester tester) async {
  await tapText(tester, 'Nora');
  await tapLabel(tester, 'Editar persona');
  final row = find.text('Regalos en secreto');
  await tester.ensureVisible(row);
  await settle(tester);
}

void main() {
  const tall = Size(390, 1500);

  group('hoja de protección', () {
    screenTest(
      'sin proteger: explica, pide, confirma y desactiva con confirmación',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openNoraSheet(tester);
        // La fila de la hoja de persona dice el estado de ahora.
        expect(find.text('Desactivados'), findsOneWidget);

        await tester.tap(find.text('Regalos en secreto'));
        await settle(tester);
        expect(find.text('Regalos en secreto para Nora'), findsOneWidget);
        // Qué significa, en llano.
        expect(
          find.textContaining('Nora no ve en su móvil qué regalos hay para Nora'),
          findsOneWidget,
        );
        expect(
          find.textContaining('ya habían llegado al móvil de'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Hace falta un móvil con permiso'),
          findsOneWidget,
        );
        expect(find.text('Pedir protección'), findsOneWidget);

        // Pedir: queda pedida, y como este móvil tiene permiso ofrece activar.
        await tapText(tester, 'Pedir protección');
        expect(_actions(phone).calls, ['request:nora']);
        expect(find.text('Protección pedida'), findsOneWidget);
        expect(find.text('Pedir protección'), findsNothing);
        expect(find.text('Activar ahora'), findsOneWidget);

        await tapText(tester, 'Activar ahora');
        expect(_actions(phone).calls, ['request:nora', 'activate:nora']);
        expect(find.text('Protección activa'), findsOneWidget);
        expect(
          find.text('Nora no ve ninguno de sus regalos en su móvil.'),
          findsOneWidget,
        );

        // Desactivar pide confirmación antes de llamar.
        await tapText(tester, 'Desactivar protección');
        expect(
          find.text('¿Desactivar los regalos en secreto para Nora?'),
          findsOneWidget,
        );
        expect(
          find.textContaining('también los que están pendientes'),
          findsOneWidget,
        );
        expect(_actions(phone).calls, ['request:nora', 'activate:nora']);
        await tapText(tester, 'Cancelar');
        expect(_actions(phone).calls, ['request:nora', 'activate:nora']);
        expect(find.text('Protección activa'), findsOneWidget);

        await tapText(tester, 'Desactivar protección');
        await tapText(tester, 'Desactivar');
        expect(_actions(phone).calls.last, 'deactivate:nora');
        // Vuelve al principio.
        expect(find.text('Pedir protección'), findsOneWidget);
        expect(find.text('Protección activa'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: tall,
      overrides: _overrides(),
    );

    screenTest(
      'pedida sin permiso: espera a otro móvil y no ofrece activar',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openNoraSheet(tester);
        await tester.tap(find.text('Regalos en secreto'));
        await settle(tester);
        await tapText(tester, 'Pedir protección');
        expect(find.text('Protección pedida'), findsOneWidget);
        expect(
          find.textContaining('Esperando a un móvil con permiso'),
          findsOneWidget,
        );
        expect(find.text('Activar ahora'), findsNothing);
      },
      size: tall,
      overrides: _overrides(canConfirm: false),
    );

    screenTest(
      'sin confirmador posible: no hay botón y se explica qué hacer',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openNoraSheet(tester);
        await tester.tap(find.text('Regalos en secreto'));
        await settle(tester);
        expect(
          find.byKey(const ValueKey<String>('protectionRequest')),
          findsNothing,
        );
        expect(find.text('Pedir protección'), findsNothing);
        expect(
          find.textContaining(
            'Para proteger los regalos de Nora hace falta un móvil de otra '
            'persona de la familia.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('elige de quién es este móvil'),
          findsOneWidget,
        );
        expect(_actions(phone).calls, isEmpty);
      },
      size: tall,
      overrides: _overrides(
        canRequest: false,
        requestReason: ProtectedPersonReason.noConfirmer,
      ),
    );

    screenTest(
      'sin confirmador en el móvil de Nora: no sugiere asignar este móvil',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openNoraSheet(tester);
        await tester.tap(find.text('Regalos en secreto'));
        await settle(tester);
        expect(
          find.byKey(const ValueKey<String>('protectionRequest')),
          findsNothing,
        );
        expect(
          find.textContaining(
            'Pide a otra persona de la familia que lo haga',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('elige de quién es este móvil'), findsNothing);
        expect(
          find.textContaining('Desde este móvil no se pueden proteger'),
          findsOneWidget,
        );
      },
      size: tall,
      overrides: _overrides(
        canRequest: false,
        requestReason: ProtectedPersonReason.noConfirmer,
        ownPhone: true,
      ),
    );

    screenTest(
      'con confirmador posible el botón sigue y no sale la ayuda',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openNoraSheet(tester);
        await tester.tap(find.text('Regalos en secreto'));
        await settle(tester);
        expect(
          find.byKey(const ValueKey<String>('protectionRequest')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('protectionRequestHelp')),
          findsNothing,
        );
      },
      size: tall,
      overrides: _overrides(),
    );

    screenTest(
      'el rechazo de la petición usa el texto del motivo, no el genérico',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        _actions(phone).failWith = ProtectedPersonReason.requesterPending;
        await _openNoraSheet(tester);
        await tester.tap(find.text('Regalos en secreto'));
        await settle(tester);
        await tapText(tester, 'Pedir protección');
        expect(
          find.textContaining('Falta que alguien de la familia apruebe'),
          findsOneWidget,
        );
        expect(
          find.textContaining('No se ha podido cambiar la protección'),
          findsNothing,
        );
      },
      size: tall,
      overrides: _overrides(),
    );

    screenTest(
      'activa sin clave: no se puede desactivar y lo dice',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openNoraSheet(tester);
        await tester.tap(find.text('Regalos en secreto'));
        await settle(tester);
        await tapText(tester, 'Pedir protección');
        await tapText(tester, 'Activar ahora');
        expect(find.text('Protección activa'), findsOneWidget);
        expect(find.text('Desactivar protección'), findsNothing);
        expect(
          find.textContaining('no puede desactivarla ahora'),
          findsOneWidget,
        );
      },
      size: tall,
      overrides: _overrides(canDeactivate: false),
    );

    screenTest(
      'un fallo de la lógica se explica con su motivo y no cambia nada',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        _actions(phone).failWith = ProtectedPersonReason.noEntitlement;
        await _openNoraSheet(tester);
        await tester.tap(find.text('Regalos en secreto'));
        await settle(tester);
        await tapText(tester, 'Pedir protección');
        expect(
          find.textContaining('no tiene acceso a los regalos en secreto'),
          findsOneWidget,
        );
        expect(find.text('Pedir protección'), findsOneWidget);
        expect(find.text('Protección pedida'), findsNothing);
      },
      size: tall,
      overrides: _overrides(),
    );

    screenTest(
      'en modo oscuro y con «Reducir movimiento» recorre los tres estados',
      (tester, phone) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openNoraSheet(tester);
        await tester.tap(find.text('Regalos en secreto'));
        await settle(tester);
        await tapText(tester, 'Pedir protección');
        expect(find.text('Protección pedida'), findsOneWidget);
        await tapText(tester, 'Activar ahora');
        expect(find.text('Protección activa'), findsOneWidget);
        await tapText(tester, 'Desactivar protección');
        await tapText(tester, 'Desactivar');
        expect(find.text('Pedir protección'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: tall,
      brightness: Brightness.dark,
      overrides: _overrides(),
    );

    for (final unreadableKeys in [false, true]) {
      screenTest('la hoja abierta retira Pedir protección tras el rechazo por '
          '${unreadableKeys ? 'claves ilegibles' : 'registro ausente'}', (
        tester,
        phone,
      ) async {
        await seedSample(tester, phone);
        await tester.runAsync(() async {
          final store = phone.container.read(familyStoreProvider);
          final identity = (await store.load())!.identity;
          final keys = await phone.container
              .read(deviceKeysStoreProvider)
              .create();
          final registry = await DeviceRegistry.empty(identity.listId)
              .withRecord(
                await DeviceRecord.create(
                  keys: keys,
                  listId: identity.listId,
                  deviceId: identity.node,
                  personId: 'aritz',
                ),
              );
          await store.saveRegistry(registry);
          await store.saveSyncV2(
            SyncIdentityV2(
              listId: identity.listId,
              deviceId: identity.node,
              syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
            ),
          );
          await changedElsewhere(
            phone,
            (doc, clock) => doc.set(
              clock,
              Collections.meta,
              kProtocolRecordId,
              {kProtocolVersionField: kSyncProtocolV2},
            ),
          );
        });

        await pumpRegalos(tester, phone);
        await _openNoraSheet(tester);
        await tapText(tester, 'Regalos en secreto');
        final request = find.byKey(const ValueKey<String>('protectionRequest'));
        expect(request, findsOneWidget);

        await tester.runAsync(() async {
          if (unreadableKeys) {
            await phone.secrets.write(kDeviceKeysSecret, 'unreadable');
          } else {
            await phone.files.delete('family.registry');
          }
        });
        expect(request, findsOneWidget);
        await tapText(tester, 'Pedir protección');
        expect(find.text('Regalos en secreto para Nora'), findsOneWidget);
        expect(request, findsNothing);
        final help = find.byKey(
          const ValueKey<String>('protectionRequestHelp'),
        );
        expect(tester.widget<Text>(help).data, contains('no está al día'));
        expect(tester.takeException(), isNull);
        // Deja terminar los reintentos de los proveedores dependientes.
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
      }, size: tall);
    }

    screenTest(
      'con identidad mixta la fila abre la explicación sin ofrecer la petición',
      (tester, phone) async {
        await seedSample(tester, phone);
        await tester.runAsync(() async {
          final store = phone.container.read(familyStoreProvider);
          final stored = (await store.load())!;
          final identity = stored.identity;
          final keys = await phone.container
              .read(deviceKeysStoreProvider)
              .create();
          await store.saveSyncV2(
            SyncIdentityV2(
              listId: identity.listId,
              deviceId: identity.node,
              syncId: 'AAAAAAAAAAAAAAAAAAAAAA',
            ),
          );
          final clock = HlcClock(
            node: identity.node,
            last: stored.doc.maxStamp,
          );
          await store.saveDoc(
            stored.doc.set(clock, Collections.meta, kProtocolRecordId, {
              kProtocolVersionField: kSyncProtocolV2,
            }),
          );
          var registry = DeviceRegistry.empty(identity.listId);
          for (final kind in DeviceKind.values) {
            registry = await registry.withRecord(
              await DeviceRecord.create(
                keys: keys,
                listId: identity.listId,
                deviceId: identity.node,
                personId: null,
                kind: kind,
              ),
            );
          }
          await store.saveRegistry(registry);
          phone.restart();
        });

        await pumpRegalos(tester, phone);
        await _openNoraSheet(tester);
        await tapText(tester, 'Regalos en secreto');
        expect(find.text('Regalos en secreto para Nora'), findsOneWidget);
        expect(
          find.textContaining(
            'No se sabe con seguridad de quién es este móvil',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('protectionRequest')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
      size: tall,
    );

    screenTest('sin la sincronización nueva la fila no sale', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapText(tester, 'Nora');
      await tapLabel(tester, 'Editar persona');
      expect(find.text('Regalos en secreto'), findsNothing);
    }, size: tall);

    screenTest(
      'la lista de una persona protegida enseña su estado y abre la hoja',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        phone.container
            .read(_status.notifier)
            .set(PersonProtectionStatus.active);
        await tapText(tester, 'Nora');
        expect(find.text('Activos'), findsOneWidget);
        await tapText(tester, 'Regalos en secreto');
        expect(find.text('Protección activa'), findsOneWidget);
      },
      size: tall,
      overrides: _overrides(),
    );
  });

  group('bloque secreto', () {
    screenTest(
      'Personas: la fila de Nora no lleva cifras y las demás sí',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        final strip = find.byKey(const ValueKey<String>('secret-strip:nora'));
        expect(strip, findsOneWidget);
        expect(find.text('Regalos en secreto para Nora'), findsOneWidget);
        final row = find.ancestor(of: strip, matching: find.byType(InkWell));
        // En la fila de Nora, el único texto con «regalo» es el del bloque.
        expect(
          find.descendant(
            of: row.first,
            matching: find.textContaining(
              RegExp('regalo', caseSensitive: false),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row.first,
            matching: find.textContaining(RegExp(r'\d+ regalos?')),
          ),
          findsNothing,
        );
        // Aritz sigue con sus cifras.
        expect(find.textContaining('5 regalos'), findsWidgets);
      },
      size: tall,
      overrides: _overrides(locked: {'nora'}),
    );

    screenTest(
      'detalle de persona: solo el bloque, sin lista, cifras ni botón de añadir',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Nora');
        expect(
          find.byKey(const ValueKey<String>('secret-block:nora')),
          findsOneWidget,
        );
        expect(find.text('Regalos en secreto para Nora'), findsOneWidget);
        expect(find.text('Este móvil no los muestra.'), findsOneWidget);
        expect(find.text('Puzle de 48 piezas'), findsNothing);
        expect(find.textContaining(RegExp(r'^\d+ regalos?$')), findsNothing);
        expect(find.byType(FloatingActionButton), findsNothing);
        // La hoja de la persona sigue disponible desde su cabecera.
        expect(find.bySemanticsLabel('Editar persona'), findsOneWidget);
      },
      size: tall,
      overrides: _overrides(locked: {'nora'}),
    );

    screenTest(
      'Reparto: la franja borrosa ocupa el sitio de las celdas de Nora',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Reparto');
        if (find.text('Todas').evaluate().isNotEmpty) {
          await tapText(tester, 'Todas');
        }
        expect(
          find.byKey(const ValueKey<String>('secret-strip:nora')),
          findsOneWidget,
        );
        expect(find.text('Regalos en secreto para Nora'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: tall,
      overrides: _overrides(locked: {'nora'}),
    );

    screenTest(
      'Ocasiones: la lista y el detalle llevan el bloque fijo',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Ocasiones');
        expect(
          find.byKey(const ValueKey<String>('secret-block:nora')),
          findsOneWidget,
        );
        await tapText(tester, 'Reyes');
        expect(
          find.byKey(const ValueKey<String>('secret-block:nora')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: tall,
      overrides: _overrides(locked: {'nora'}),
    );

    // Vista ancha: con dos paneles la fila lleva su franja y el detalle de
    // Nora, el bloque; en una columna ancha, lo mismo en su sitio.
    for (final size in kTabletSizes) {
      screenTest(
        'ventana ancha (${sizeLabel(size)}): franja en la lista y bloque en el detalle',
        (tester, phone) async {
          await seedSample(tester, phone);
          await pumpRegalos(tester, phone);
          expect(
            find.byKey(const ValueKey<String>('secret-strip:nora')),
            findsOneWidget,
          );
          await tapText(tester, 'Nora');
          expect(
            find.byKey(const ValueKey<String>('secret-block:nora')),
            findsOneWidget,
          );
          expect(find.byType(FloatingActionButton), findsNothing);
          expect(tester.takeException(), isNull);
        },
        size: size,
        overrides: _overrides(locked: {'nora'}),
      );
    }

    screenTest(
      'en modo oscuro y con «Reducir movimiento» se ve igual de fijo',
      (tester, phone) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        expect(
          find.byKey(const ValueKey<String>('secret-strip:nora')),
          findsOneWidget,
        );
        await tapText(tester, 'Nora');
        expect(
          find.byKey(const ValueKey<String>('secret-block:nora')),
          findsOneWidget,
        );
        // El bloque no tiene ninguna transformación animada.
        final block = find.byKey(const ValueKey<String>('secret-block:nora'));
        expect(
          find.descendant(of: block, matching: find.byType(AnimatedOpacity)),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
      size: tall,
      brightness: Brightness.dark,
      overrides: _overrides(locked: {'nora'}),
    );
  });

  group('editor de regalo', () {
    Future<void> openEditorChoosing(WidgetTester tester) async {
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Añadir regalo'),
      );
      await settle(tester);
    }

    screenTest(
      'la persona protegida que este móvil no puede elegir sale apagada, con su motivo',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openEditorChoosing(tester);
        await tester.tap(find.text('Para quién').first);
        await settle(tester);
        expect(
          find.textContaining('no tiene acceso a los regalos en secreto'),
          findsOneWidget,
        );
        // Tocarla no la elige.
        await tester.tap(find.text('Nora').last);
        await settle(tester);
        expect(find.textContaining('no tiene acceso'), findsWidgets);
        await tester.tap(find.text('Leo').last);
        await settle(tester);
        expect(find.textContaining('no tiene acceso'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: tall,
      overrides: _overrides(
        noraSelectable: false,
        noraReason: ProtectedPersonReason.noEntitlement,
      ),
    );

    screenTest(
      'con una persona protegida elegida de antemano, el aviso sale junto al campo',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Nora');
        await tester.tap(find.byTooltip('Añadir regalo'));
        await settle(tester);
        expect(find.textContaining('Este móvil es de Nora'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Cuento');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        // No guarda y el formulario sigue ahí.
        expect(find.text('Nuevo regalo'), findsOneWidget);
        expect(_family(phone).calls, isNot(contains('upsert-rejected')));
      },
      size: tall,
      overrides: _overrides(
        noraSelectable: false,
        noraReason: ProtectedPersonReason.ownRequestsRestricted,
      ),
    );

    screenTest(
      'si el guardado se rechaza, el motivo sale arriba y el formulario se conserva',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        _family(phone).upsertThrows = const ProtectedPersonException(
          'leo',
          reason: ProtectedPersonReason.blockFull,
        );
        await tapText(tester, 'Leo');
        await tester.tap(find.byTooltip('Añadir regalo'));
        await settle(tester);
        await tester.enterText(find.byType(TextField).first, 'Cuento');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(find.textContaining('Has llegado al límite'), findsOneWidget);
        expect(
          find.textContaining('No se ha guardado el regalo.'),
          findsOneWidget,
        );
        expect(find.text('Nuevo regalo'), findsOneWidget);
        expect(find.text('Cuento'), findsOneWidget);
        expect(find.text('Guardar'), findsOneWidget);
      },
      size: tall,
      overrides: _overrides(),
    );

    screenTest(
      'si queda guardado solo en este móvil, lo dice sin afirmar que se compartió',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        _family(phone).upsertThrows = const ProtectedPersonException(
          'leo',
          reason: ProtectedPersonReason.blockFull,
          savedLocally: true,
        );
        await tapText(tester, 'Leo');
        await tester.tap(find.byTooltip('Añadir regalo'));
        await settle(tester);
        await tester.enterText(find.byType(TextField).first, 'Cuento');
        await tester.tap(find.text('Guardar'));
        await settle(tester);
        expect(find.text('Nuevo regalo'), findsNothing);
        expect(
          find.text(
            'Guardado solo en este móvil. Aún falta añadirlo a la lista y compartirlo.',
          ),
          findsOneWidget,
        );
        expect(find.text('Ver pendientes'), findsOneWidget);
      },
      size: tall,
      overrides: _overrides(),
    );

    screenTest(
      'la petición propia con la protección activa explica la restricción',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tapText(tester, 'Leo');
        await tester.tap(find.byTooltip('Añadir regalo'));
        await settle(tester);
        final switchRow = find.text('Es un encargo: lo pidió alguien');
        await tester.ensureVisible(switchRow);
        await tester.tap(switchRow);
        await settle(tester);
        // «Lo pidió»: Nora (la persona de este móvil).
        await tester.ensureVisible(find.text('Quién lo pidió'));
        await tester.tap(find.text('Quién lo pidió'));
        await settle(tester);
        await tester.tap(find.text('Nora').last);
        await settle(tester);
        expect(
          find.textContaining('no puedes añadir ni ver regalos para ti'),
          findsOneWidget,
        );
      },
      size: tall,
      overrides: [
        ..._overrides(),
        selfRecipientIdProvider.overrideWith(_Nora.new),
        ownGiftRequestStateProvider.overrideWith(
          (ref) async => OwnGiftRequestState.protectionRestricted,
        ),
      ],
    );
  });

  group('regalos pendientes', () {
    final pending = [
      PendingProtectedGift(
        'nora',
        _gift('p1', 'nora', 'Cocinita de madera'),
        ProtectedPersonReason.blockFull,
      ),
      PendingProtectedGift(
        'nora',
        _gift('p2', 'nora', 'Puzle grande'),
        ProtectedPersonReason.blockFull,
      ),
    ];

    screenTest(
      'el aviso cuenta los pendientes y la hoja deja reintentar hasta vaciarlos',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        expect(find.textContaining('pendientes de guardar'), findsNothing);
        phone.container.read(_pending.notifier).set(pending);
        await settle(tester);
        expect(find.text('2 regalos pendientes de guardar'), findsOneWidget);
        await tapText(tester, 'Ver');
        expect(find.text('Regalos pendientes'), findsOneWidget);
        expect(
          find.textContaining('Si pierdes el móvil antes de que se añadan'),
          findsOneWidget,
        );
        expect(find.text('Cocinita de madera'), findsOneWidget);
        expect(find.text('Puzle grande'), findsOneWidget);
        await tapText(tester, 'Reintentar');
        expect(_actions(phone).calls, ['retry:nora']);
        expect(find.text('Todo guardado'), findsOneWidget);
        expect(find.text('Cocinita de madera'), findsNothing);
        await tapText(tester, 'Cerrar');
        expect(find.textContaining('pendientes de guardar'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: tall,
      overrides: _overrides(),
    );

    screenTest(
      'si siguen sin caber, la hoja lo dice y conserva los regalos',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        _actions(phone).retryKeeps = true;
        phone.container.read(_pending.notifier).set(pending);
        await settle(tester);
        await tapText(tester, 'Ver');
        await tapText(tester, 'Reintentar');
        expect(find.textContaining('Todavía no hay sitio'), findsOneWidget);
        expect(find.text('Cocinita de madera'), findsOneWidget);
        expect(find.text('Todo guardado'), findsNothing);
      },
      size: tall,
      overrides: _overrides(),
    );

    screenTest(
      'desde la persona, la hoja enseña solo los suyos (modo oscuro, sin movimiento)',
      (tester, phone) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        phone.container.read(_pending.notifier).set([
          ...pending,
          PendingProtectedGift(
            'leo',
            _gift('p3', 'leo', 'Tren de cartón'),
            ProtectedPersonReason.writerSlotsFull,
          ),
        ]);
        await settle(tester);
        await tapText(tester, 'Leo');
        expect(find.text('1 regalo pendiente de guardar'), findsOneWidget);
        await tapText(tester, 'Ver');
        expect(find.text('Tren de cartón'), findsOneWidget);
        expect(find.text('Cocinita de madera'), findsNothing);
        expect(
          find.textContaining('ha llegado a su límite de regalos en secreto'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: tall,
      brightness: Brightness.dark,
      overrides: _overrides(),
    );
  });
}

class _Nora extends SelfRecipient {
  @override
  String? build() => 'nora';
}
