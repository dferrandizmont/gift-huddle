import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/family_doc.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/core/sync/protected_doc.dart';
import 'package:regalos/core/widgets/section_header.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/family_providers.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/family/domain/delete_impact.dart';
import 'package:regalos/features/family/domain/family_errors.dart';
import 'package:regalos/features/family/presentation/reparto_sheet.dart';
import 'package:regalos/features/settings/presentation/manage_screens.dart';

import '../helpers/other_phone.dart';
import '../helpers/screens.dart';
import 'family_grid_test.dart' show openFamily;

const _tall = Size(390, 1500);

const _ok = 0;
const _gone = 1;
const _error = 2;

/// Cómo está la proyección autorizada: [_ok]; [_gone], con Aritz protegido y
/// sus regalos retirados (este móvil no puede abrir su bloque secreto); o
/// [_error], que falla al calcularse.
class _Locked extends Notifier<int> {
  @override
  int build() => _ok;

  void set(int value) => state = value;
}

final _lockedProvider = NotifierProvider<_Locked, int>(_Locked.new);

FamilyDoc _withoutAritz(FamilyDoc doc) => FamilyDoc(
  listId: doc.listId,
  collections: {
    ...doc.collections,
    Collections.gifts: {
      for (final entry
          in doc.collections[Collections.gifts]?.entries ??
              const <MapEntry<String, SyncRecord>>[])
        if (entry.value['recipientId'] != 'aritz') entry.key: entry.value,
    },
  },
);

/// El impacto de eliminar a quien regala, sin los regalos de Aritz cuando este
/// móvil ya no puede verlos (lo que calcularía con la proyección autorizada).
class _ImpactFamily extends FamilyController {
  @override
  Future<DeleteImpact> giverAliasDeleteImpact(String id) async {
    final impact = await super.giverAliasDeleteImpact(id);
    if (ref.read(_lockedProvider) != _gone) {
      return impact;
    }
    final doc = (await future).doc;
    return DeleteImpact.ofGiverAlias(
      FamilyView.fromDoc(_withoutAritz(doc)),
      id,
    );
  }
}

/// Borrar un regalo falla, y recalcular el impacto de eliminar falla cuando
/// la proyección está en [_gone].
class _FailingFamily extends FamilyController {
  @override
  Future<bool> deleteGiftWithUndo(String id) =>
      throw StateError('no se puede borrar');

  @override
  Future<DeleteImpact> giverAliasDeleteImpact(String id) async {
    if (ref.read(_lockedProvider) == _gone) {
      throw StateError('no se puede recalcular');
    }
    return super.giverAliasDeleteImpact(id);
  }
}

/// El recálculo del impacto llega en desorden: cada llamada tras abrir el
/// aviso espera a su puerta; la más reciente trae el impacto sin los regalos
/// de Aritz y las anteriores, con todos.
class _SequencedFamily extends FamilyController {
  final Map<int, Completer<void>> gates = <int, Completer<void>>{};
  int calls = 0;

  @override
  Future<DeleteImpact> giverAliasDeleteImpact(String id) async {
    final call = ++calls;
    final impact = await super.giverAliasDeleteImpact(id);
    if (call == 1) {
      return impact;
    }
    await (gates[call] = gates[call] ?? Completer<void>()).future;
    if (call != calls) {
      return impact;
    }
    final doc = (await future).doc;
    return DeleteImpact.ofGiverAlias(
      FamilyView.fromDoc(_withoutAritz(doc)),
      id,
    );
  }

  void release(int call) => (gates[call] ??= Completer<void>()).complete();
}

/// Nora resulta ser la persona de otro móvil de la familia.
class _OtherOwnerFamily extends FamilyController {
  @override
  Future<void> deleteRecipient(String id, {DeleteImpact? expectedImpact}) =>
      throw DevicePersonException(
        recipientId: id,
        owner: DevicePersonOwner.otherDevice,
      );
}

/// Una proyección autorizada a medida: Aritz protegido (con `hideOwnGifts`),
/// y, si [_Locked], sin sus regalos, como los dejaría un móvil que no puede
/// abrir su bloque secreto.
final _protectedAritz = authorizedProjectionProvider.overrideWith((ref) async {
  final family = ref.watch(familyControllerProvider).value;
  if (family == null) {
    return null;
  }
  final mode = ref.watch(_lockedProvider);
  if (mode == _error) {
    throw StateError('la proyección falla');
  }
  final doc = family.doc;
  final merged = mode == _gone ? _withoutAritz(doc) : doc;
  return AuthorizedProjection(
    doc: merged,
    secretGiftIds: const {},
    lockedBlocks: const [],
    openedScopes: const {},
    policies: {'aritz': const PolicyState(hideOwnGifts: true, rev: 1)},
  );
});

const _libro = 'Libro de dinosaurios con solapas';

Gift _gift(FamilyState state, String startsWith) =>
    state.view.gifts.firstWhere((g) => g.title.startsWith(startsWith));

/// El quién regala de [title] resuelto: la persona enlazada, o `null`.
String? _giverPerson(FamilyState state, String title) =>
    state.view.resolveGiver(_gift(state, title).giverId)?.recipientId;

/// Hace un cambio en la zona de la app (no en `runAsync`), con la hoja o el
/// diálogo abiertos: la cola del controlador ya la ha usado la interfaz en
/// esa zona y la siguiente operación tiene que avanzar en ella.
Future<T> _inApp<T>(WidgetTester tester, Future<T> Function() change) async {
  final result = change();
  await settle(tester);
  return result;
}

/// «Cancelar» del diálogo que está encima (no el de la hoja de debajo).
Future<void> _cancelDialog(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar').last);
  await settle(tester);
}

Future<void> _openEditor(WidgetTester tester, {String title = _libro}) async {
  await tapText(tester, 'Aritz');
  await tapText(tester, title);
  expect(find.text('Editar regalo'), findsOneWidget);
}

Future<void> _openGiverPicker(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel(RegExp('^Quién regala, ')));
  await settle(tester);
}

Future<void> _tapLast(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

void main() {
  group('sección «Personas» del editor de regalo', () {
    screenTest('ofrece las personas, sin crear nada hasta guardar', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openEditor(tester);
      await _openGiverPicker(tester);

      // Los quién regala de siempre y, debajo, las personas (sin Aritz, a quien
      // se regala).
      expect(find.text('Tío Pere'), findsWidgets);
      expect(find.widgetWithText(SectionHeader, 'Personas'), findsOneWidget);
      expect(find.text('Nora'), findsWidgets);
      expect(find.text('Leo'), findsWidgets);
      expect(find.text('Sin asignar'), findsWidgets);

      await _tapLast(tester, 'Nora');
      expect(find.bySemanticsLabel('Quién regala, Nora'), findsOneWidget);
      // Cancelar no crea nada: ni quién regala para Nora ni cambia el regalo.
      await tester.tap(find.bySemanticsLabel('Cerrar'));
      await settle(tester);
      final state = await familyState(tester, phone);
      expect(state.view.giverForPerson('nora'), isNull);
      expect(_gift(state, _libro).giverId, 'marta');
    }, size: _tall);

    screenTest('al guardar asigna a la persona y crea su quién regala', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openEditor(tester);
      await _openGiverPicker(tester);
      await _tapLast(tester, 'Nora');
      await tapText(tester, 'Guardar');

      final state = await familyState(tester, phone);
      expect(_giverPerson(state, _libro), 'nora');
      expect(
        state.view.allGivers.where((g) => g.recipientId == 'nora'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    }, size: _tall);

    screenTest('si su quién regala estaba archivado, lo recupera', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await tester.runAsync(() async {
        final controller = familyOf(phone);
        final giver = await controller.addPersonAsGiver('nora');
        await controller.archiveGiver(giver!.id);
      });
      await pumpRegalos(tester, phone);
      await _openEditor(tester);
      await _openGiverPicker(tester);
      expect(find.text('Volverá a la lista de quienes regalan'), findsOneWidget);
      await _tapLast(tester, 'Nora');
      await tapText(tester, 'Guardar');

      final state = await familyState(tester, phone);
      expect(_giverPerson(state, _libro), 'nora');
      final givers = state.view.allGivers.where((g) => g.recipientId == 'nora');
      // Se recupera el de siempre: no se crea otro.
      expect(givers, hasLength(1));
      expect(givers.single.archived, isFalse);
    }, size: _tall);

    screenTest(
      'en un regalo secreto pide primero añadirla como quién regala',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openEditor(tester);
        await _openGiverPicker(tester);
        expect(find.text('Primero se añade a quienes regalan'), findsWidgets);

        // Elegirla no la asigna: explica por qué y deja cancelar sin crear nada.
        await _tapLast(tester, 'Nora');
        expect(find.text('¿Añadir a Nora a la lista de quienes regalan?'), findsOneWidget);
        expect(
          find.textContaining('Primero, añade a '),
          findsOneWidget,
        );
        await _cancelDialog(tester);
        var state = await familyState(tester, phone);
        expect(state.view.giverForPerson('nora'), isNull);
        expect(find.bySemanticsLabel(RegExp('^Quién regala, Tía')), findsOne);

        // Confirmar la añade para toda la familia y la deja elegida.
        await _openGiverPicker(tester);
        await _tapLast(tester, 'Nora');
        await tapText(tester, 'Añadir a Nora');
        state = await familyState(tester, phone);
        expect(state.view.giverForPerson('nora'), isNotNull);
        expect(find.bySemanticsLabel('Quién regala, Nora'), findsOneWidget);
        await tapText(tester, 'Guardar');
        state = await familyState(tester, phone);
        expect(_giverPerson(state, _libro), 'nora');
        expect(tester.takeException(), isNull);
      },
      size: _tall,
      overrides: [_protectedAritz],
    );

    screenTest(
      'si el regalo deja de estar autorizado, el editor se cierra solo sin '
      'guardar y avisa',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openEditor(tester);
        await tester.enterText(
          find.widgetWithText(TextField, 'Regalo'),
          'Otro título que no se guarda',
        );
        final before = await familyState(tester, phone);

        phone.container.read(_lockedProvider.notifier).set(_gone);
        await settle(tester);

        expect(find.text('Editar regalo'), findsNothing);
        // Cierre automático: no se pregunta «¿Descartar los cambios?».
        expect(find.text('¿Descartar los cambios?'), findsNothing);
        expect(find.text('Otro título que no se guarda'), findsNothing);
        expect(
          find.text('Este regalo ya no se puede ver en este móvil.'),
          findsOneWidget,
        );
        // No se guardó nada.
        final after = await familyState(tester, phone);
        expect(after.doc.canonicalJson(), before.doc.canonicalJson());
        expect(tester.takeException(), isNull);
      },
      size: _tall,
      overrides: [_protectedAritz],
    );
  });

  group('sección «Personas» de Reparto', () {
    screenTest('la hoja de una celda asigna a la persona al momento', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester);
      await tester.tap(
        find.bySemanticsLabel(RegExp('^Nosotros para Aritz: 2 regalos')),
      );
      await settle(tester);
      await tester.tap(
        find.bySemanticsLabel(RegExp('^Quién regala: Nosotros')).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final sheet = find.byKey(kRepartoSheetKey);
      expect(
        find.descendant(
          of: sheet,
          matching: find.widgetWithText(SectionHeader, 'Personas'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Personas')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: sheet, matching: find.bySemanticsLabel('Nora')),
      );
      await settle(tester);
      await settle(tester);

      final state = await familyState(tester, phone);
      expect(_giverPerson(state, 'Estación'), 'nora');
      expect(state.view.giverForPerson('nora'), isNotNull);
      expect(tester.takeException(), isNull);
    }, size: _tall);

    screenTest('la lista por ocasión asigna a la persona al momento', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openFamily(tester, all: false);
      await tester.tap(find.bySemanticsLabel('Por ocasión'));
      await settle(tester);
      await tester.tap(
        find.bySemanticsLabel(RegExp('^Quién regala: Tía Marta y Jordi')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Personas'), findsWidgets);
      await tester.tap(find.bySemanticsLabel('Leo'));
      await settle(tester);
      await settle(tester);

      final state = await familyState(tester, phone);
      expect(_giverPerson(state, _libro), 'leo');
      expect(tester.takeException(), isNull);
    }, size: _tall);

    screenTest(
      'en un regalo secreto la lista por ocasión pide primero añadirla',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openFamily(tester, all: false);
        await tester.tap(find.bySemanticsLabel('Por ocasión'));
        await settle(tester);
        await tester.tap(
          find.bySemanticsLabel(RegExp('^Quién regala: Tía Marta y Jordi')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(
          find.bySemanticsLabel('Nora. Primero se añade a quienes regalan'),
        );
        await settle(tester);
        expect(find.text('¿Añadir a Nora a la lista de quienes regalan?'), findsOneWidget);
        await _cancelDialog(tester);
        var state = await familyState(tester, phone);
        expect(state.view.giverForPerson('nora'), isNull);
        expect(_gift(state, _libro).giverId, 'marta');

        await tester.tap(
          find.bySemanticsLabel('Nora. Primero se añade a quienes regalan'),
        );
        await settle(tester);
        await tapText(tester, 'Añadir a Nora');
        await settle(tester);
        state = await familyState(tester, phone);
        expect(_giverPerson(state, _libro), 'nora');
        expect(tester.takeException(), isNull);
      },
      size: _tall,
      overrides: [_protectedAritz],
    );
  });

  group('sin desbordes', () {
    for (final dark in [false, true]) {
      screenTest(
        'la sección «Personas» y su paso previo caben con letra al 200 %'
        '${dark ? ' en oscuro' : ''}',
        (tester, phone) async {
          await seedSample(tester, phone);
          await pumpRegalos(tester, phone);
          await openFamily(tester, all: false);
          await tester.tap(find.bySemanticsLabel('Por ocasión'));
          await settle(tester);
          await tester.tap(
            find.bySemanticsLabel(RegExp('^Quién regala: Tía Marta y Jordi')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('Personas'), findsWidgets);
          final chip = find.bySemanticsLabel(
            'Nora. Primero se añade a quienes regalan',
          );
          await tester.ensureVisible(chip);
          await tester.pump();
          await tester.tap(chip);
          await settle(tester);
          expect(
            find.text('¿Añadir a Nora a la lista de quienes regalan?'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
        size: const Size(520, 2400),
        textScale: 2,
        brightness: dark ? Brightness.dark : Brightness.light,
        overrides: [_protectedAritz],
      );
    }
  });

  group('diálogos de borrado y quién regala enlazado', () {
    Future<void> openGivers(WidgetTester tester) async {
      await tester.tap(find.text('Ajustes').last);
      await settle(tester);
      await tapText(tester, 'Quién regala');
    }

    Future<void> openPeople(WidgetTester tester) async {
      await tester.tap(find.text('Ajustes').last);
      await settle(tester);
      await tapText(tester, 'Personas');
    }

    Finder rowOf(String name) =>
        find.ancestor(of: find.text(name), matching: find.byType(ManageRow));

    Finder buttonOf(String name, String label) => find.descendant(
      of: rowOf(name),
      matching: find.widgetWithText(TextButton, label),
    );

    screenTest(
      'eliminar a quien regala nombra sus regalos y, si cambió, pide confirmar '
      'de nuevo',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openGivers(tester);
        await tester.tap(buttonOf('Nosotros', 'Eliminar'));
        await settle(tester);

        expect(find.text('¿Eliminar a Nosotros?'), findsOneWidget);
        expect(
          find.textContaining('Sus 4 regalos seguirán en la lista sin nadie asignado en «Quién regala».'),
          findsOneWidget,
        );
        expect(
          find.textContaining('«Pijama de astronautas, talla 8»'),
          findsOneWidget,
        );
        expect(find.textContaining('Patinete'), findsNothing);

        // Otro móvil cambia un regalo mientras el aviso está abierto.
        await _inApp(
          tester,
          () => changedElsewhere(
            phone,
            (doc, clock) =>
                doc.set(clock, Collections.gifts, 'g5', {'giverId': 'us'}),
          ),
        );
        await settle(tester);

        // El aviso se reabre solo, con lo nuevo, y no se ha eliminado nada.
        expect(find.text('¿Eliminar a Nosotros?'), findsOneWidget);
        expect(
          find.textContaining('La lista ha cambiado. Antes de confirmar'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Sus 5 regalos seguirán en la lista sin nadie asignado en «Quién regala».'),
          findsOneWidget,
        );
        expect(find.textContaining('«Patinete»'), findsOneWidget);
        var state = await familyState(tester, phone);
        expect(state.view.givers.map((g) => g.id), contains('us'));

        await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
        await settle(tester);
        state = await familyState(tester, phone);
        expect(state.view.givers.map((g) => g.id), isNot(contains('us')));
        expect(tester.takeException(), isNull);
      },
      size: _tall,
    );

    screenTest(
      'eliminar a una persona que también regala explica que su nombre sigue '
      'en los regalos que hace a otras personas',
      (tester, phone) async {
        await seedSample(tester, phone);
        await tester.runAsync(
          () async => familyOf(phone).addPersonAsGiver('leo'),
        );
        await pumpRegalos(tester, phone);
        await openPeople(tester);
        await tester.tap(buttonOf('Leo', 'Eliminar'));
        await settle(tester);
        expect(find.text('¿Eliminar a Leo?'), findsOneWidget);
        expect(
          find.textContaining(
            'Su nombre seguirá en «Quién regala»',
          ),
          findsOneWidget,
        );
        // Quien no regala no lo dice.
        await _cancelDialog(tester);
        await tester.tap(buttonOf('Nora', 'Eliminar'));
        await settle(tester);
        expect(find.textContaining('seguirá en «Quién regala»'), findsNothing);
      },
      size: _tall,
    );

    screenTest(
      'si la persona resulta ser la de otro móvil, lo explica y no la elimina',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await openPeople(tester);
        await tester.tap(buttonOf('Nora', 'Eliminar'));
        await settle(tester);
        expect(find.text('¿Eliminar a Nora?'), findsOneWidget);
        // Mientras tanto, este móvil pasa a ser el de Nora.
        await _inApp(
          tester,
          () => phone.container
              .read(selfRecipientIdProvider.notifier)
              .choose('nora'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
        await settle(tester);

        expect(find.text('Este móvil es de Nora'), findsOneWidget);
        expect(
          find.textContaining('Para eliminar o archivar a'),
          findsOneWidget,
        );
        await tapText(tester, 'Entendido');
        final state = await familyState(tester, phone);
        expect(state.view.recipients.map((r) => r.id), contains('nora'));
        expect(tester.takeException(), isNull);
      },
      size: _tall,
    );

    screenTest(
      'un quién regala enlazado lo dice, no deja editar su nombre y se puede '
      'desenlazar con confirmación',
      (tester, phone) async {
        await seedSample(tester, phone);
        await tester.runAsync(() => familyOf(phone).linkGiver('pere', 'leo'));
        await pumpRegalos(tester, phone);
        await openGivers(tester);
        expect(
          find.text(
            'Enlazado a una persona: su nombre y color se cambian en Personas.',
          ),
          findsOneWidget,
        );
        await tapText(tester, 'Leo');
        expect(find.text('Editar quién regala'), findsOneWidget);
        final field = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Nombre'),
        );
        expect(field.enabled, isFalse);
        expect(
          find.text(
            'El nombre y el color son los de Leo. Cámbialos en Personas.',
          ),
          findsOneWidget,
        );

        // Cancelar la confirmación no cambia nada.
        await tapText(tester, 'Desenlazar de la persona');
        expect(find.text('¿Desenlazar de Leo?'), findsOneWidget);
        await _cancelDialog(tester);
        var state = await familyState(tester, phone);
        expect(
          state.view.allGivers.firstWhere((g) => g.id == 'pere').recipientId,
          'leo',
        );

        await tapText(tester, 'Desenlazar de la persona');
        await tester.tap(find.widgetWithText(FilledButton, 'Desenlazar'));
        await settle(tester);
        state = await familyState(tester, phone);
        final pere = state.view.allGivers.firstWhere((g) => g.id == 'pere');
        expect(pere.recipientId, isNull);
        // Conserva el nombre de ahora y su nombre ya se puede editar.
        expect(pere.name, 'Leo');
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, 'Nombre'))
              .enabled,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
      size: _tall,
    );

    screenTest('un quién regala manual se enlaza a una persona', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await openGivers(tester);
      await tapText(tester, 'Tío Pere');
      await tapText(tester, 'Enlazar con una persona');
      await _tapLast(tester, 'Nora');
      expect(find.text('¿Enlazar con Nora?'), findsOneWidget);
      await _cancelDialog(tester);
      var state = await familyState(tester, phone);
      expect(
        state.view.allGivers.firstWhere((g) => g.id == 'pere').recipientId,
        isNull,
      );

      await tapText(tester, 'Enlazar con una persona');
      await _tapLast(tester, 'Nora');
      await tester.tap(find.widgetWithText(FilledButton, 'Enlazar'));
      await settle(tester);
      state = await familyState(tester, phone);
      final pere = state.view.allGivers.firstWhere((g) => g.id == 'pere');
      expect(pere.recipientId, 'nora');
      expect(pere.name, 'Nora');
      expect(tester.takeException(), isNull);
    }, size: _tall);
  });

  group('autorización incierta, diálogos y avisos', () {
    screenTest(
      'una lápida en el común (el regalo pasó a un ámbito secreto) cierra el '
      'editor y retira el formulario',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openEditor(tester);
        await tester.enterText(
          find.widgetWithText(TextField, 'Regalo'),
          'Otro título que no se guarda',
        );
        await _inApp(
          tester,
          () => changedElsewhere(
            phone,
            (doc, clock) => doc.delete(clock, Collections.gifts, 'g2'),
          ),
        );
        expect(find.text('Editar regalo'), findsNothing);
        expect(find.text('Otro título que no se guarda'), findsNothing);
        expect(
          find.text('Este regalo ya no se puede ver en este móvil.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: _tall,
    );

    screenTest(
      'con la proyección en error no pinta los campos y los recupera al '
      'resolverse',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openEditor(tester);
        expect(find.text(_libro), findsWidgets);

        phone.container.read(_lockedProvider.notifier).set(_error);
        await settle(tester);
        expect(find.text('Editar regalo'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Regalo'), findsNothing);
        expect(find.bySemanticsLabel(RegExp('^Quién regala, ')), findsNothing);

        phone.container.read(_lockedProvider.notifier).set(_ok);
        await settle(tester);
        expect(find.widgetWithText(TextField, 'Regalo'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('^Quién regala, ')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: _tall,
      overrides: [_protectedAritz],
    );

    screenTest(
      'mientras guarda no pinta los campos aunque la autorización cambie',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openEditor(tester);
        await tester.enterText(
          find.widgetWithText(TextField, 'Regalo'),
          'Otro título',
        );
        phone.files.writeDelay = const Duration(seconds: 2);
        await tester.tap(find.text('Guardar'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Otro título'), findsNothing);
        expect(find.widgetWithText(TextField, 'Regalo'), findsNothing);

        phone.container.read(_lockedProvider.notifier).set(_gone);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Otro título'), findsNothing);
        phone.files.writeDelay = Duration.zero;
        await settle(tester);
        expect(find.text('Editar regalo'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: _tall,
      overrides: [_protectedAritz],
    );

    screenTest(
      'el aviso de borrar el regalo se cierra con el editor si se pierde la '
      'autorización',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openEditor(tester);
        await tester.ensureVisible(find.text('Borrar regalo'));
        await tester.pump();
        await tester.tap(find.text('Borrar regalo'));
        await settle(tester);
        expect(find.text('¿Borrar «$_libro»?'), findsOneWidget);

        phone.container.read(_lockedProvider.notifier).set(_gone);
        await settle(tester);
        expect(find.textContaining('¿Borrar «'), findsNothing);
        expect(find.text('Editar regalo'), findsNothing);
        expect(
          find.text('Este regalo ya no se puede ver en este móvil.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: _tall,
      overrides: [_protectedAritz],
    );

    screenTest(
      'el aviso de eliminar a quien regala se reabre sin los regalos que ya no '
      'se ven',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Ajustes').last);
        await settle(tester);
        await tapText(tester, 'Quién regala');
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text('Nosotros'),
              matching: find.byType(ManageRow),
            ),
            matching: find.widgetWithText(TextButton, 'Eliminar'),
          ),
        );
        await settle(tester);
        expect(find.text('¿Eliminar a Nosotros?'), findsOneWidget);
        expect(
          find.textContaining('«Pijama de astronautas, talla 8»'),
          findsOneWidget,
        );

        phone.container.read(_lockedProvider.notifier).set(_gone);
        await settle(tester);
        await settle(tester);
        expect(find.text('¿Eliminar a Nosotros?'), findsOneWidget);
        expect(
          find.textContaining('La lista ha cambiado. Antes de confirmar'),
          findsOneWidget,
        );
        expect(find.textContaining('Pijama de astronautas'), findsNothing);
        expect(find.textContaining('«Cocinita de madera»'), findsOneWidget);
        await _cancelDialog(tester);
        expect(tester.takeException(), isNull);
      },
      size: _tall,
      overrides: [
        _protectedAritz,
        familyControllerProvider.overrideWith(_ImpactFamily.new),
      ],
    );

    screenTest('la persona elegida sigue en el campo si se da de alta en otro '
        'móvil', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openEditor(tester);
      await _openGiverPicker(tester);
      await _tapLast(tester, 'Nora');
      expect(find.bySemanticsLabel('Quién regala, Nora'), findsOneWidget);

      await _inApp(tester, () => familyOf(phone).addPersonAsGiver('nora'));
      expect(find.bySemanticsLabel('Quién regala, Nora'), findsOneWidget);
      await tapText(tester, 'Guardar');

      final state = await familyState(tester, phone);
      expect(_giverPerson(state, _libro), 'nora');
      expect(
        state.view.allGivers.where((g) => g.recipientId == 'nora'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    }, size: _tall);

    screenTest('si la persona elegida se archiva, el aviso lo dice y el '
        'formulario se conserva', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await _openEditor(tester);
      await _openGiverPicker(tester);
      await _tapLast(tester, 'Nora');
      await _inApp(
        tester,
        () => changedElsewhere(
          phone,
          (doc, clock) => doc.set(clock, Collections.recipients, 'nora', {
            'archived': true,
          }),
        ),
      );
      expect(find.bySemanticsLabel('Quién regala, Nora'), findsOneWidget);
      await tapText(tester, 'Guardar');
      expect(
        find.text('No se ha guardado: esa persona está archivada.'),
        findsWidgets,
      );
      expect(find.text('Editar regalo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _tall);

    Future<void> openLinkedLeo(WidgetTester tester) async {
      await tester.tap(find.text('Ajustes').last);
      await settle(tester);
      await tapText(tester, 'Quién regala');
      await tapText(tester, 'Leo');
      expect(find.text('Editar quién regala'), findsOneWidget);
    }

    screenTest('desenlazar algo que otro móvil ya cambió avisa y refresca', (
      tester,
      phone,
    ) async {
      await seedSample(tester, phone);
      await tester.runAsync(() => familyOf(phone).linkGiver('pere', 'leo'));
      await pumpRegalos(tester, phone);
      await openLinkedLeo(tester);
      await tapText(tester, 'Desenlazar de la persona');
      expect(find.text('¿Desenlazar de Leo?'), findsOneWidget);
      await _inApp(
        tester,
        () => changedElsewhere(
          phone,
          (doc, clock) => doc.set(clock, Collections.givers, 'pere', {
            Giver.recipientIdField: null,
          }),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Desenlazar'));
      await settle(tester);
      expect(find.text('Ya no estaba enlazado a Leo.'), findsOneWidget);
      // La hoja se refresca: ya no está enlazado y su nombre se puede editar.
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, 'Nombre'))
            .enabled,
        isTrue,
      );
      expect(find.text('Enlazar con una persona'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _tall);

    screenTest(
      'si la persona cambia de nombre con la hoja abierta, el campo la '
      'sigue',
      (tester, phone) async {
        await seedSample(tester, phone);
        await tester.runAsync(() => familyOf(phone).linkGiver('pere', 'leo'));
        await pumpRegalos(tester, phone);
        await openLinkedLeo(tester);
        await _inApp(
          tester,
          () => changedElsewhere(
            phone,
            (doc, clock) => doc.set(clock, Collections.recipients, 'leo', {
              'name': 'Leo Martí',
            }),
          ),
        );
        final field = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Nombre'),
        );
        expect(field.controller!.text, 'Leo Martí');
        expect(tester.takeException(), isNull);
      },
      size: _tall,
    );

    screenTest(
      'eliminar a la persona de otro móvil explica que tiene su propio móvil',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Ajustes').last);
        await settle(tester);
        await tapText(tester, 'Personas');
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text('Nora'),
              matching: find.byType(ManageRow),
            ),
            matching: find.widgetWithText(TextButton, 'Eliminar'),
          ),
        );
        await settle(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
        await settle(tester);

        expect(find.text('Nora tiene su propio móvil'), findsOneWidget);
        expect(
          find.text(
            'Nora tiene su propio móvil en la familia, así que no se puede '
            'eliminar ni archivar desde aquí.',
          ),
          findsOneWidget,
        );
        await tapText(tester, 'Entendido');
        expect(find.text('Nora tiene su propio móvil'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      size: _tall,
      overrides: [familyControllerProvider.overrideWith(_OtherOwnerFamily.new)],
    );
  });

  group('ronda 3', () {
    screenTest(
      'con «Borrar regalo» abierto, si la proyección falla el diálogo se '
      'cierra',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openEditor(tester);
        await tester.ensureVisible(find.text('Borrar regalo'));
        await tester.pump();
        await tester.tap(find.text('Borrar regalo'));
        await settle(tester);
        expect(find.text('¿Borrar «$_libro»?'), findsOneWidget);

        phone.container.read(_lockedProvider.notifier).set(_error);
        await settle(tester);
        expect(find.textContaining('¿Borrar «'), findsNothing);
        // El editor sigue, sin pintar los campos.
        expect(find.text('Editar regalo'), findsOneWidget);
        expect(find.widgetWithText(TextField, 'Regalo'), findsNothing);
        phone.container.read(_lockedProvider.notifier).set(_ok);
        await settle(tester);
        expect(tester.takeException(), isNull);
      },
      size: _tall,
      overrides: [_protectedAritz],
    );

    screenTest('el aviso de regalo parecido se cierra si el regalo citado deja de verse, '
        'también al crear uno nuevo', (tester, phone) async {
      await seedSample(tester, phone);
      await pumpRegalos(tester, phone);
      await tapText(tester, 'Aritz');
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      expect(find.text('Nuevo regalo'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Regalo'), _libro);
      await tapText(tester, 'Guardar');
      expect(find.text('Posible duplicado'), findsOneWidget);

      await _inApp(
        tester,
        () => changedElsewhere(
          phone,
          (doc, clock) => doc.delete(clock, Collections.gifts, 'g2'),
        ),
      );
      expect(find.text('Posible duplicado'), findsNothing);
      expect(find.text('Nuevo regalo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, size: _tall);

    screenTest(
      'si borrar falla, el editor vuelve a comprobar la autorización',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openEditor(tester);
        await tester.ensureVisible(find.text('Borrar regalo'));
        await tester.pump();
        await tester.tap(find.text('Borrar regalo'));
        await settle(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
        await settle(tester);
        expect(
          find.text('No se ha podido eliminar. Inténtalo de nuevo.'),
          findsWidgets,
        );
        expect(find.text('Editar regalo'), findsOneWidget);

        // Si ahora se pierde la autorización, el editor se cierra: el borrado
        // fallido no lo dejó marcado como «borrando».
        phone.container.read(_lockedProvider.notifier).set(_gone);
        await settle(tester);
        expect(find.text('Editar regalo'), findsNothing);
        expect(
          find.text('Este regalo ya no se puede ver en este móvil.'),
          findsOneWidget,
        );
      },
      size: _tall,
      overrides: [
        _protectedAritz,
        familyControllerProvider.overrideWith(_FailingFamily.new),
      ],
    );

    screenTest(
      'un regalo vivo cuyo destinatario tiene lápida queda fuera de la vista y '
      'cierra el editor',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await _openEditor(tester);
        await _inApp(tester, () => deletedElsewhere(phone, 'aritz'));
        expect(find.text('Editar regalo'), findsNothing);
        expect(
          find.text('Este regalo ya no se puede ver en este móvil.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: _tall,
    );

    screenTest(
      'si el recálculo del impacto falla, el aviso de eliminar se cierra con un '
      'aviso neutro',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Ajustes').last);
        await settle(tester);
        await tapText(tester, 'Quién regala');
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text('Nosotros'),
              matching: find.byType(ManageRow),
            ),
            matching: find.widgetWithText(TextButton, 'Eliminar'),
          ),
        );
        await settle(tester);
        expect(find.textContaining('«Pijama de astronautas'), findsOneWidget);

        phone.container.read(_lockedProvider.notifier).set(_gone);
        await settle(tester);
        await settle(tester);
        expect(find.textContaining('Pijama de astronautas'), findsNothing);
        expect(find.text('¿Eliminar a Nosotros?'), findsNothing);
        expect(
          find.text(
            'No se ha podido comprobar qué se eliminaría. Inténtalo de nuevo.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      size: _tall,
      overrides: [
        _protectedAritz,
        familyControllerProvider.overrideWith(_FailingFamily.new),
      ],
    );

    screenTest(
      'tras un desenlace remoto, el campo toma el nombre que conserva y no se '
      'pisa al guardar',
      (tester, phone) async {
        await seedSample(tester, phone);
        await tester.runAsync(() => familyOf(phone).linkGiver('pere', 'leo'));
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Ajustes').last);
        await settle(tester);
        await tapText(tester, 'Quién regala');
        await tapText(tester, 'Leo');
        await _inApp(
          tester,
          () => changedElsewhere(
            phone,
            (doc, clock) => doc.setChanged(clock, Collections.givers, 'pere', {
              Giver.recipientIdField: null,
              'name': 'Leo antiguo',
            }),
          ),
        );
        final field = find.widgetWithText(TextField, 'Nombre');
        expect(tester.widget<TextField>(field).controller!.text, 'Leo antiguo');
        expect(tester.widget<TextField>(field).enabled, isTrue);
        await tapText(tester, 'Guardar');
        final state = await familyState(tester, phone);
        expect(
          state.view.allGivers.firstWhere((g) => g.id == 'pere').name,
          'Leo antiguo',
        );
      },
      size: _tall,
    );

    screenTest(
      'si la persona ya escribió un nombre, un cambio remoto no lo pisa',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Ajustes').last);
        await settle(tester);
        await tapText(tester, 'Quién regala');
        await tapText(tester, 'Tío Pere');
        final field = find.widgetWithText(TextField, 'Nombre');
        await tester.enterText(field, 'Mi nombre');
        await _inApp(
          tester,
          () => changedElsewhere(
            phone,
            (doc, clock) =>
                doc.set(clock, Collections.givers, 'pere', {'name': 'Pere II'}),
          ),
        );
        expect(tester.widget<TextField>(field).controller!.text, 'Mi nombre');
        await tapText(tester, 'Guardar');
        final state = await familyState(tester, phone);
        expect(
          state.view.allGivers.firstWhere((g) => g.id == 'pere').name,
          'Mi nombre',
        );
      },
      size: _tall,
    );

    screenTest(
      'sin tocar el nombre, un renombrado remoto lo actualiza y guardar lo '
      'conserva',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Ajustes').last);
        await settle(tester);
        await tapText(tester, 'Quién regala');
        await tapText(tester, 'Tío Pere');
        await _inApp(
          tester,
          () => changedElsewhere(
            phone,
            (doc, clock) =>
                doc.set(clock, Collections.givers, 'pere', {'name': 'Pere II'}),
          ),
        );
        final field = find.widgetWithText(TextField, 'Nombre');
        expect(tester.widget<TextField>(field).controller!.text, 'Pere II');
        await tapText(tester, 'Guardar');
        final state = await familyState(tester, phone);
        expect(
          state.view.allGivers.firstWhere((g) => g.id == 'pere').name,
          'Pere II',
        );
      },
      size: _tall,
    );

    screenTest(
      'con dos cambios seguidos, el aviso de eliminar no enseña nada hasta el '
      'recálculo más reciente y descarta los anteriores',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Ajustes').last);
        await settle(tester);
        await tapText(tester, 'Quién regala');
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text('Nosotros'),
              matching: find.byType(ManageRow),
            ),
            matching: find.widgetWithText(TextButton, 'Eliminar'),
          ),
        );
        await settle(tester);
        expect(find.textContaining('«Pijama de astronautas'), findsOneWidget);
        final family = phone.container.read(
          familyControllerProvider.notifier,
        ) as _SequencedFamily;

        // Primer cambio: su recálculo queda esperando.
        await _inApp(
          tester,
          () => changedElsewhere(
            phone,
            (doc, clock) =>
                doc.set(clock, Collections.givers, 'pere', {'name': 'Pere II'}),
          ),
        );
        expect(find.textContaining('Pijama de astronautas'), findsNothing);
        expect(find.text('Comprobando lo que se elimina…'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Eliminar'),
              )
              .onPressed,
          isNull,
        );

        // Segundo cambio: sigue sin enseñar nada.
        await _inApp(
          tester,
          () => changedElsewhere(
            phone,
            (doc, clock) => doc.set(clock, Collections.givers, 'pere', {
              'name': 'Pere III',
            }),
          ),
        );
        expect(family.calls, greaterThanOrEqualTo(3));
        expect(find.text('Comprobando lo que se elimina…'), findsOneWidget);

        // Llega primero el más reciente: ya enseña, sin lo de Aritz.
        family.release(family.calls);
        await settle(tester);
        expect(find.textContaining('Pijama de astronautas'), findsNothing);
        expect(find.textContaining('«Cocinita de madera»'), findsOneWidget);

        // Los anteriores llegan tarde, con todo: se descartan.
        for (var call = 2; call < family.calls; call++) {
          family.release(call);
        }
        await settle(tester);
        expect(find.textContaining('Pijama de astronautas'), findsNothing);
        expect(find.textContaining('«Cocinita de madera»'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      size: _tall,
      overrides: [familyControllerProvider.overrideWith(_SequencedFamily.new)],
    );

    screenTest(
      'pulsar «Eliminar» sobre el aviso anterior, antes de que repinte con el '
      'cambio, no borra con lo que no se vio',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.tap(find.text('Ajustes').last);
        await settle(tester);
        await tapText(tester, 'Quién regala');
        await tester.tap(
          find.descendant(
            of: find.ancestor(
              of: find.text('Nosotros'),
              matching: find.byType(ManageRow),
            ),
            matching: find.widgetWithText(TextButton, 'Eliminar'),
          ),
        );
        await settle(tester);
        expect(find.textContaining('Sus 4 regalos'), findsOneWidget);
        final button = find.widgetWithText(FilledButton, 'Eliminar');

        // Un regalo más pasa a quien regala, y se pulsa sin que haya habido
        // ningún fotograma entre medias: el botón sigue siendo el del aviso
        // anterior.
        final change = changedElsewhere(
          phone,
          (doc, clock) =>
              doc.set(clock, Collections.gifts, 'g5', {'giverId': 'us'}),
        );
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
        }
        await change;
        await tester.tap(button);
        await settle(tester);

        // No se borró: vuelve a pedir confirmación con lo nuevo.
        var state = await familyState(tester, phone);
        expect(state.view.givers.map((g) => g.id), contains('us'));
        expect(find.text('¿Eliminar a Nosotros?'), findsOneWidget);
        expect(
          find.textContaining('La lista ha cambiado. Antes de confirmar'),
          findsOneWidget,
        );
        expect(find.textContaining('Sus 5 regalos'), findsOneWidget);
        expect(find.textContaining('«Patinete»'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
        await settle(tester);
        state = await familyState(tester, phone);
        expect(state.view.givers.map((g) => g.id), isNot(contains('us')));
        expect(tester.takeException(), isNull);
      },
      size: _tall,
    );
  });
}
