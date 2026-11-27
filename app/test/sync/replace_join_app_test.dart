// M1 (QA iOS 1.0.5 y 1.0.6): un móvil que ya tiene su lista entra en otra
// familia con un enlace y pulsa «Sustituir y unirme». Al terminar tiene que
// quedar en Personas con la lista nueva y la hoja final, una sola vez, sin
// excepciones; ni pantalla en blanco (una columna) ni en negro (dos paneles).
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' show StatefulNavigationShell;
import 'package:regalos/app/root_navigator.dart';
import 'package:regalos/app/router.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/family/application/own_gifts_notice.dart'
    show kOwnGiftsHiddenSeenKey;
import 'package:regalos/features/family/application/self_person_gate.dart';
import 'package:regalos/features/lock/application/lock_controller.dart';
import 'package:regalos/features/lock/application/lock_gate_state.dart';
import 'package:regalos/features/lock/presentation/lock_screen.dart';
import 'package:regalos/features/sync/application/pairing_v2_controller.dart';
import 'package:regalos/features/sync/application/replace_join_hold.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/domain/sync_status.dart' show SyncPhase;
import 'package:regalos/features/sync/invites/incoming_invite.dart';
import 'package:regalos/features/sync/presentation/join_invite_screen.dart';
import 'package:regalos/l10n/app_localizations.dart';

import '../helpers/fake_sync_server.dart';
import '../helpers/fake_worker_v2.dart';
import '../helpers/memory_stores.dart';
import '../helpers/pump_app.dart';
import '../helpers/screens.dart';
import 'sync_harness.dart';

/// A: la familia que invita, con Aritz (su móvil), Nora y Leo. Empieza a
/// invitar a un móvil para Nora.
Future<FakePhone> _host(List<Override> overrides) async {
  final a = FakePhone(
    prefs: await mockPrefs(),
    syncHost: null,
    extraOverrides: overrides,
  );
  a.container.read(syncControllerProvider);
  await a.container.read(familyControllerProvider.future);
  final fam = a.container.read(familyControllerProvider.notifier);
  await fam.createFamily(deviceName: 'Aritz');
  for (final (id, name) in [
    ('a-aritz', 'Aritz'),
    ('a-nora', 'Nora'),
    ('a-leo', 'Leo'),
  ]) {
    await fam.upsertRecipient(
      Recipient(id: id, name: name, colorIndex: 0, archived: false),
    );
  }
  await a.container.read(selfPersonGateActionsProvider).choose('a-aritz');
  await a.container
      .read(pairingV2HostProvider.notifier)
      .start(guestPerson: 'a-nora');
  return a;
}

List<Override> _overrides(FakeWorkerV2 worker) => [
  syncHostProvider.overrideWithValue(kTestHost),
  invitationOriginProvider.overrideWithValue(''),
  syncTransportProvider.overrideWithValue(FakeSyncServer().connect()),
  syncV2TransportProvider.overrideWithValue(worker.client()),
  syncTimingProvider.overrideWithValue(kFastTiming),
  pairingV2AvailableProvider.overrideWithValue(true),
];

String _inviteOf(FakePhone host) {
  final link = host.container.read(pairingV2HostProvider).link!;
  return link.substring(link.indexOf('#') + 1);
}

class _LockedPin extends LockController {
  @override
  Future<AppLockState> build() async => AppLockState(
    pinSet: true,
    enabled: true,
    biometrics: false,
    locked: true,
  );
}

/// Si la pantalla de unirse se cierra a media instalación, y qué viene luego.
enum _Close { no, yes, thenForm, thenLink, resetAfterDone }

/// Los enlaces que llegan, a mano.
class _TestLinks extends IncomingInviteController {
  @override
  String? build() => null;

  void push(String id) => state = id;
}

void main() {
  test('la pantalla que entra se cierra mientras se instala la familia: '
      '«hecho» llega igual y no se corta la instalación', () async {
    final worker = FakeWorkerV2();
    final host = await _host(_overrides(worker));
    addTearDown(host.dispose);
    final b = FakePhone(
      prefs: await mockPrefs(),
      syncHost: null,
      extraOverrides: _overrides(worker),
    );
    addTearDown(b.dispose);
    b.container.read(syncControllerProvider);
    await b.container.read(familyControllerProvider.future);
    final own = b.container.read(familyControllerProvider.notifier);
    await own.createFamily(deviceName: 'B');
    await own.upsertRecipient(
      const Recipient(
        id: 'b-otro',
        name: 'Otro',
        colorIndex: 1,
        archived: false,
      ),
    );

    final guest = b.container.read(pairingV2GuestProvider.notifier);
    await guest.begin(_inviteOf(host));
    expect(
      b.container.read(pairingV2GuestProvider).phase,
      PairingV2GuestPhase.confirmReplace,
    );
    await guest.confirmReplace();
    await eventually(
      () =>
          host.container.read(pairingV2HostProvider).phase ==
              PairingV2HostPhase.compare &&
          b.container.read(pairingV2GuestProvider).phase ==
              PairingV2GuestPhase.compare,
      reason: 'los dos enseñan el código',
    );
    // Lo que hace la vista al desmontarse (el router la sacaba al quedarse
    // sin familia): reposar el emparejamiento en un microtask, en plena
    // instalación.
    var resets = 0;
    final hold = b.container.read(replaceJoinHoldProvider);
    var heldWhileEmpty = true;
    b.container.listen(familyControllerProvider, (_, next) {
      if (next.value?.hasFamily == false) {
        heldWhileEmpty = heldWhileEmpty && hold.value;
        expect(guest.installing, isTrue);
        scheduleMicrotask(() {
          resets++;
          guest
            ..reset()
            ..cancel();
          // Y otra invitación abierta encima: no pisa la que se instala.
          unawaited(guest.begin('BBBBBBBBBBBBBBBBBBBBBB'));
        });
      }
    });
    final phases = <PairingV2GuestPhase>[];
    b.container.listen(
      pairingV2GuestProvider,
      (_, next) => phases.add(next.phase),
    );
    guest.confirmCode();
    await host.container.read(pairingV2HostProvider.notifier).confirm();
    await eventually(
      () =>
          b.container.read(pairingV2GuestProvider).phase ==
          PairingV2GuestPhase.done,
      reason: '«hecho» aunque la vista se cerró',
    );
    expect(resets, 1, reason: 'la instalación pasó por la lista vacía');
    expect(phases, [
      PairingV2GuestPhase.waitingApproval,
      PairingV2GuestPhase.done,
    ], reason: 'ni reposo, ni cancelado, ni otra invitación a medias');
    expect(guest.claimDone(), isTrue);
    expect(guest.claimDone(), isFalse, reason: 'una sola vez');
    expect(heldWhileEmpty, isTrue, reason: 'el router no va a la bienvenida');
    expect(hold.value, isFalse, reason: 'se suelta al acabar');
    final family = b.container.read(familyControllerProvider).value!;
    expect(family.hasFamily, isTrue);
    expect(family.identity!.selfRecipientId, 'a-nora');
    expect(b.container.read(pairingV2GuestProvider).assignedPersonId, 'a-nora');
    // Ya acabado, reposar vuelve a funcionar.
    guest.reset();
    expect(
      b.container.read(pairingV2GuestProvider).phase,
      PairingV2GuestPhase.idle,
    );
  });

  test('el bloqueo vale también sin familia mientras se sustituye', () {
    const locked = AsyncData(
      AppLockState(
        pinSet: true,
        enabled: true,
        biometrics: false,
        locked: true,
      ),
    );
    final empty = AsyncData(FamilyState.noFamily());
    expect(
      lockGateContent(family: empty, lock: locked, recoveryHeld: false),
      LockGateContent.none,
      reason: 'primer uso: sin familia no hay PIN que pedir',
    );
    expect(
      lockGateContent(
        family: empty,
        lock: locked,
        recoveryHeld: false,
        replacingFamily: true,
      ),
      LockGateContent.locked,
    );
  });

  screenTest(
    'bloqueado a media sustitución: la pantalla de bloqueo tapa la app',
    (tester, phone) async {
      await pumpRegalos(tester, phone);
      expect(find.byType(LockScreen), findsNothing);
      final hold = phone.container.read(replaceJoinHoldProvider)..acquire();
      await settle(tester);
      expect(find.byType(LockScreen), findsOneWidget);
      hold.release();
      await settle(tester);
      expect(find.byType(LockScreen), findsNothing);
    },
    overrides: [lockControllerProvider.overrideWith(_LockedPin.new)],
  );

  for (final (label, size, close) in [
    ('una columna', const Size(390, 844), _Close.no),
    ('dos paneles', const Size(1024, 1366), _Close.no),
    (
      'la pantalla se cierra mientras se instala',
      const Size(390, 844),
      _Close.yes,
    ),
    (
      'se cierra y se abre otra en el formulario',
      const Size(390, 844),
      _Close.thenForm,
    ),
    (
      'se cierra y llega otro enlace a media instalación',
      const Size(390, 844),
      _Close.thenLink,
    ),
    (
      'se cierra y se repone antes de que la app recoja «hecho»',
      const Size(390, 844),
      _Close.resetAfterDone,
    ),
  ]) {
    final worker = FakeWorkerV2();
    final overrides = _overrides(worker);

    screenTest(
      'Sustituir y unirme con un enlace acaba en Personas con la lista nueva '
      'y la hoja final ($label)',
      (tester, phone) async {
        // B: este móvil, con su propia lista (la muestra).
        await seedSample(tester, phone);
        // A: la otra familia, con Aritz (su móvil), Nora y Leo. Invita a este
        // móvil para Nora.
        final host = (await tester.runAsync(() => _host(overrides)))!;
        addTearDown(host.dispose);
        expect(
          host.container.read(pairingV2HostProvider).phase,
          PairingV2HostPhase.waiting,
        );
        final inviteId = _inviteOf(host);

        // Cualquier excepción del árbol (la `GlobalKey` repetida, el
        // ancestro desactivado) hace fallar la prueba por sí sola.
        await pumpRegalos(tester, phone);
        // Ajustes › Móviles de la familia › Más opciones › «Unirme con un
        // enlace» abre la pantalla en el navegador raíz, encima de Ajustes.
        await tester.tap(find.text('Ajustes').last);
        await settle(tester);
        await tapText(tester, 'Móviles de la familia');
        unawaited(
          rootNavigatorKey.currentState!.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => JoinInviteScreen(initialInvite: inviteId),
            ),
          ),
        );
        await settle(tester);
        // Desde aquí hay indicadores de progreso que no acaban: se avanza a
        // pasos, con tiempo real para la red y el cifrado entre fotogramas.
        await tester.tap(find.text('Pedir entrada'));
        Future<void> until(bool Function() done, String reason) async {
          for (var i = 0; i < 150 && !done(); i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 40)),
            );
            await tester.pump(const Duration(milliseconds: 60));
          }
          expect(done(), isTrue, reason: reason);
        }

        PairingV2GuestPhase guest() =>
            phone.container.read(pairingV2GuestProvider).phase;
        await until(
          () =>
              find.text('Este móvil ya tiene una lista').evaluate().isNotEmpty,
          'pregunta si sustituir la lista',
        );
        await tester.tap(find.text('Sustituir y unirme'));
        // El primer layout inicia la animación de tamaño del paso. El botón
        // puede estar en el árbol antes de que su centro reciba el toque.
        final matchCode = find.text('Coinciden').hitTestable();
        await until(
          () =>
              guest() == PairingV2GuestPhase.compare &&
              host.container.read(pairingV2HostProvider).phase ==
                  PairingV2HostPhase.compare &&
              matchCode.evaluate().isNotEmpty,
          'los dos enseñan el código y se puede pulsar «Coinciden»',
        );
        // La causa de M1: al borrar la lista de este móvil, el router mandaba
        // a la bienvenida y, al instalar la nueva, de vuelta a Personas; las
        // cuatro pestañas se desmontaban y se volvían a montar a medias.
        final router = phone.container.read(routerProvider);
        final visited = <String>[];
        void onRoute() =>
            visited.add(router.routerDelegate.currentConfiguration.uri.path);
        router.routerDelegate.addListener(onRoute);
        addTearDown(() => router.routerDelegate.removeListener(onRoute));
        final shell = tester.state(
          find.byType(StatefulNavigationShell, skipOffstage: false),
        );
        // Lo que hay montado cuando llega «hecho».
        int? screensAtDone;
        phone.container.listen(pairingV2GuestProvider, (previous, next) {
          if (next.phase == PairingV2GuestPhase.done &&
              previous?.phase != PairingV2GuestPhase.done) {
            screensAtDone = find
                .byType(JoinInviteScreen, skipOffstage: false)
                .evaluate()
                .length;
            if (close == _Close.resetAfterDone) {
              // Antes del fotograma en que la app lo recoge: una vista que
              // se desmonta repone, y otra invitación se abre.
              final guest = phone.container.read(
                pairingV2GuestProvider.notifier,
              );
              scheduleMicrotask(() {
                guest.reset();
                unawaited(guest.begin('BBBBBBBBBBBBBBBBBBBBBB'));
              });
            }
          }
        });
        final hold = phone.container.read(replaceJoinHoldProvider);
        if (close != _Close.no) {
          // Quien cierra la pantalla de unirse a media instalación.
          void onHold() {
            if (!hold.value) return;
            hold.removeListener(onHold);
            rootNavigatorKey.currentState!.pop();
          }

          hold.addListener(onHold);
        }
        await tester.tap(matchCode);
        await tester.pump();
        expect(guest(), PairingV2GuestPhase.waitingApproval);
        await tester.runAsync(
          () => host.container.read(pairingV2HostProvider.notifier).confirm(),
        );
        if (close != _Close.no) {
          // La pantalla de antes se desmonta del todo (fuera también su
          // transición de salida) antes de que acabe la instalación.
          await until(
            () =>
                hold.value &&
                find
                    .byType(JoinInviteScreen, skipOffstage: false)
                    .evaluate()
                    .isEmpty,
            'la pantalla de antes desmontada a media instalación',
          );
          expect(
            phone.container.read(pairingV2GuestProvider).phase,
            PairingV2GuestPhase.waitingApproval,
          );
          expect(
            phone.container.read(joinInvitePresenceProvider).isActive,
            isFalse,
          );
        }
        if (close == _Close.thenLink) {
          // Un enlace de invitación que llega ahora no abre otra pantalla que
          // solo enseñaría el progreso de esta.
          final links = phone.container.read(
            incomingInviteProvider.notifier,
          ) as _TestLinks;
          expect(
            phone.container.read(pairingV2GuestProvider.notifier).installing,
            isTrue,
          );
          links.push(inviteId);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(
            find.byType(JoinInviteScreen, skipOffstage: false),
            findsNothing,
          );
          expect(phone.container.read(incomingInviteProvider), isNull);
        }
        if (close == _Close.thenForm) {
          // Otra pantalla de unirse, que se queda en el formulario (sin vista
          // que escuche el emparejamiento).
          unawaited(
            rootNavigatorKey.currentState!.push<void>(
              MaterialPageRoute<void>(
                builder: (_) => JoinInviteScreen(initialInvite: inviteId),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('Pedir entrada'), findsOneWidget);
        }
        // Hasta que la hoja final esté en pantalla, dejando correr cada paso
        // de la instalación entre fotogramas (como en el móvil).
        await until(
          () => find.text('Móviles conectados').evaluate().isNotEmpty,
          'la hoja final',
        );
        await settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Móviles conectados'), findsOneWidget);
        expect(
          find.text(
            'Ya estás en la familia. Este móvil es de Nora: aquí no verás '
            'los regalos para Nora.',
          ),
          findsOneWidget,
        );
        expect(
          find.byType(JoinInviteScreen, skipOffstage: false),
          findsNothing,
        );
        // La hoja salió: el aviso de una vez ya no hace falta.
        expect(phone.prefs!.getBool(kOwnGiftsHiddenSeenKey), isTrue);
        expect(screensAtDone, switch (close) {
          _Close.no => 1,
          _Close.yes || _Close.thenLink || _Close.resetAfterDone => 0,
          _Close.thenForm => 1,
        });
        expect(
          visited,
          isNot(contains(AppRoutes.welcome)),
          reason: 'sustituir no es un primer uso',
        );
        expect(
          tester.state(
            find.byType(StatefulNavigationShell, skipOffstage: false),
          ),
          same(shell),
          reason: 'las pestañas no se desmontan',
        );
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          startsWith(AppRoutes.people),
        );
        final family = phone.container.read(familyControllerProvider).value!;
        expect(family.identity!.selfRecipientId, 'a-nora');
        expect({
          for (final r in family.fullView.recipients) r.name,
        }, containsAll(<String>{'Aritz', 'Nora', 'Leo'}));
        // Lo de la lista sustituida no queda.
        expect(
          family.fullView.recipients.where((r) => r.id == 'aritz'),
          isEmpty,
        );
        // Cerrar la hoja deja Personas con la lista nueva, sin nada roto.
        await tester.tap(find.byType(FilledButton).last);
        await settle(tester);
        expect(find.text('Móviles conectados'), findsNothing);
        expect(find.text('Leo'), findsWidgets);
        expect(tester.takeException(), isNull);
        await until(
          () =>
              phone.container.read(syncControllerProvider).phase == SyncPhase.synced,
          'la sincronización posterior al emparejamiento',
        );
      },
      size: size,
      // Como en el móvil, guardar tarda: entre borrar la lista de este móvil
      // e instalar la nueva pasan fotogramas (sin espera, todo cabía en uno y
      // el router nunca veía la app sin familia).
      writeDelay: const Duration(milliseconds: 150),
      syncHost: null,
      overrides: [
        ...overrides,
        incomingInviteProvider.overrideWith(_TestLinks.new),
      ],
    );
  }

  testWidgets('sin hoja final no se da por visto el aviso de sus regalos', (
    tester,
  ) async {
    final phone = FakePhone(prefs: await mockPrefs());
    addTearDown(phone.dispose);
    await tester.runAsync(() async {
      await phone.container.read(familyControllerProvider.future);
      final fam = phone.container.read(familyControllerProvider.notifier);
      await fam.createFamily(deviceName: 'B');
      await fam.upsertRecipient(
        const Recipient(
          id: 'nora',
          name: 'Nora',
          colorIndex: 0,
          archived: false,
        ),
      );
    });
    // Sin la app montada no hay dónde enseñar la hoja.
    expect(rootNavigatorKey.currentContext, isNull);
    final finished = finishJoin(
      container: phone.container,
      l10n: lookupAppLocalizations(const Locale('es')),
      router: null,
      assignedPersonId: 'nora',
    );
    await tester.pump();
    await finished;
    expect(phone.prefs!.getBool(kOwnGiftsHiddenSeenKey), isNot(isTrue));
  });
}
