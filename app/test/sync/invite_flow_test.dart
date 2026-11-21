import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/application/family_controller.dart';
import 'package:regalos/features/sync/application/sync_controller.dart';
import 'package:regalos/features/sync/data/sync_config.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/domain/sync_status.dart';
import 'package:regalos/features/sync/invites/invite_crypto.dart';
import 'package:regalos/features/sync/invites/invite_guest.dart';
import 'package:regalos/features/sync/invites/invite_host.dart';

import '../helpers/fake_sync_server.dart';
import 'sync_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSyncServer server;
  final phones = <SyncPhone>[];

  setUp(() => server = FakeSyncServer());
  tearDown(() {
    for (final p in phones) {
      p.dispose();
    }
    phones.clear();
  });

  Future<SyncPhone> newPhone({SyncTiming timing = kFastTiming}) async {
    final p = await SyncPhone.create(server, timing: timing);
    phones.add(p);
    return p;
  }

  InviteHostState host(SyncPhone p) => p.c.read(inviteHostProvider);
  InviteGuestState guest(SyncPhone p) => p.c.read(inviteGuestProvider);

  /// Mantiene viva la pantalla del invitado (es autoDispose).
  void keepGuest(SyncPhone p) {
    final sub = p.c.listen(inviteGuestProvider, (_, _) {});
    addTearDown(sub.close);
  }

  /// A con familia y datos; invitación creada; devuelve el enlace.
  Future<(SyncPhone, String)> invited() async {
    final a = await newPhone();
    await a.createFamily();
    await a.putGift('g1', 'Pijama');
    await a.sync.syncNow();
    await a.c.read(inviteHostProvider.notifier).create();
    expect(host(a).phase, InvitePhase.waiting, reason: '${host(a).issue}');
    return (a, host(a).link!);
  }

  test('el flujo entero: enlace, petición, código en los dos móviles, confirmación y entrada', () async {
    final (a, link) = await invited();
    expect(link, startsWith('https://$kTestHost/i#'));
    expect(
      link,
      isNot(contains('=')),
      reason: 'el enlace no contiene ninguna clave',
    );

    final b = await newPhone();
    keepGuest(b);
    await b.c
        .read(inviteGuestProvider.notifier)
        .begin('Te invito: $link', deviceName: 'Móvil de Marta');
    expect(guest(b).phase, JoinPhase.waiting);

    // A ve la petición con el nombre y el código.
    await eventually(
      () => host(a).phase == InvitePhase.request,
      reason: 'la petición',
    );
    expect(host(a).guestName, 'Móvil de Marta');
    final codeA = host(a).code!;
    expect(codeA, matches(RegExp(r'^\d{6}$')));

    // B ve el MISMO código antes de que A confirme nada.
    await eventually(
      () => guest(b).phase == JoinPhase.compare,
      reason: 'el código en B',
    );
    expect(guest(b).code, codeA);
    // Todavía no se ha entregado ninguna clave: B no tiene familia.
    expect((await b.hasFamily()), isFalse);
    expect(server.calls['approve'], isNull);

    // A compara y da acceso.
    expect((await a.family.future).paired, isFalse);
    await a.c.read(inviteHostProvider.notifier).approve();
    expect(host(a).phase, InvitePhase.approved);
    // Quien invita queda emparejado con el nombre que escribió el otro móvil,
    // sin esperar a que el otro suba nada (Ajustes › Compartir lo enseña).
    final hostState = await a.family.future;
    expect(hostState.paired, isTrue);
    expect(hostState.identity!.peerName, 'Móvil de Marta');
    await eventually(
      () => guest(b).phase == JoinPhase.joined,
      reason: 'que B entre',
    );

    // B está en la familia de A, con la misma clave, y recibe la lista.
    expect(await b.listId(), await a.listId());
    expect(b.family.familyKey, a.family.familyKey);
    await b.sync.syncNow();
    await converge([a, b]);
    expect((await b.gift('g1'))!.title, 'Pijama');
    // La invitación murió en el servidor.
    expect(server.openInvites, 0);
  });

  test(
    'una invitación sin nombre no adopta un nombre de sustitución',
    () async {
      final (a, link) = await invited();
      final b = await newPhone();
      keepGuest(b);
      await b.c.read(inviteGuestProvider.notifier).begin(link, deviceName: '');
      await eventually(
        () => host(a).phase == InvitePhase.request,
        reason: 'la petición sin nombre',
      );
      expect(host(a).guestName, isEmpty);
    await eventually(
      () => guest(b).phase == JoinPhase.compare,
      reason: 'el código antes de aprobar la petición sin nombre',
    );
      await a.c.read(inviteHostProvider.notifier).approve();
      await eventually(
        () => guest(b).phase == JoinPhase.joined,
        reason: 'entrada sin nombre',
      );
      expect((await b.family.future).identity!.deviceName, isEmpty);
    },
  );

  test('si el servidor cambia la clave de A, los códigos de los dos móviles no coinciden y B no recibe la clave', () async {
    final (a, link) = await invited();
    final evil = await InviteCrypto.generateKeyPair();
    server.tamperOfferKey = (_) => evil.publicKey;
    final b = await newPhone();
    keepGuest(b);
    await b.c
        .read(inviteGuestProvider.notifier)
        .begin(link, deviceName: 'Marta');
    await eventually(() => host(a).phase == InvitePhase.request);
    await eventually(() => guest(b).phase == JoinPhase.compare);
    expect(
      guest(b).code,
      isNot(host(a).code),
      reason: 'los códigos deben diferir',
    );

    // Aunque A diera acceso, el paquete no se abre con otra clave de A.
    await a.c.read(inviteHostProvider.notifier).approve();
    await eventually(() => guest(b).phase == JoinPhase.failed);
    expect(guest(b).issue, JoinIssue.tampered);
    expect((await b.hasFamily()), isFalse);
  });

  test('si el servidor cambia la clave de B, los códigos no coinciden y B no recibe la clave', () async {
    final (a, link) = await invited();
    final evil = await InviteCrypto.generateKeyPair();
    server.tamperRequestKey = (_) => evil.publicKey;
    final b = await newPhone();
    keepGuest(b);
    await b.c
        .read(inviteGuestProvider.notifier)
        .begin(link, deviceName: 'Marta');
    await eventually(() => host(a).phase == InvitePhase.request);
    await eventually(() => guest(b).phase == JoinPhase.compare);
    expect(guest(b).code, isNot(host(a).code));

    // A hace caso a la persona: los códigos no coinciden, rechaza. No se
    // entrega nada.
    await a.c.read(inviteHostProvider.notifier).reject();
    expect(host(a).phase, InvitePhase.rejected);
    await eventually(() => guest(b).phase == JoinPhase.gone);
    expect((await b.hasFamily()), isFalse);
    expect(server.calls['approve'], isNull);
  });

  test('aunque A diera acceso a una clave cambiada, el paquete cifrado para otro no se abre en B', () async {
    final (a, link) = await invited();
    final evil = await InviteCrypto.generateKeyPair();
    server.tamperRequestKey = (_) => evil.publicKey;
    final b = await newPhone();
    keepGuest(b);
    await b.c
        .read(inviteGuestProvider.notifier)
        .begin(link, deviceName: 'Marta');
    await eventually(() => host(a).phase == InvitePhase.request);
    await eventually(() => guest(b).phase == JoinPhase.compare);
    await a.c.read(inviteHostProvider.notifier).approve();
    await eventually(() => guest(b).phase == JoinPhase.failed);
    expect(guest(b).issue, JoinIssue.tampered);
    expect((await b.hasFamily()), isFalse);
  });

  test('si la oferta de A cambia entre dos consultas, B aborta', () async {
    final (a, link) = await invited();
    final evil = await InviteCrypto.generateKeyPair();
    var calls = 0;
    // La primera vez sale la clave buena; las siguientes, otra.
    server.tamperOfferKey = (real) => ++calls == 1 ? real : evil.publicKey;
    final b = await newPhone();
    keepGuest(b);
    await b.c
        .read(inviteGuestProvider.notifier)
        .begin(link, deviceName: 'Marta');
    await eventually(
      () => guest(b).phase == JoinPhase.failed,
      reason: 'abortar',
    );
    expect(guest(b).issue, JoinIssue.tampered);
    expect(host(a).phase, isNot(InvitePhase.approved));
  });

  test(
    'una clave de orden bajo se rechaza: en A (petición) y en B (oferta)',
    () async {
      final (a, link) = await invited();
      final zeros = Uint8List(32);

      // Alguien con el enlace pide entrar con una clave de ceros.
      await server.connect().requestJoin(
        link.split('#').last,
        publicKey: zeros,
        deviceName: 'Intruso',
      );
      await eventually(
        () =>
            host(a).phase == InvitePhase.failed ||
            host(a).phase == InvitePhase.rejected,
      );
      expect(server.calls['offer'], isNull, reason: 'A no ofrece nada');
      expect(server.calls['approve'], isNull);

      // Un servidor que ofrece una clave de ceros a B.
      final (a2, link2) = await invitedFrom(newPhone);
      server.tamperOfferKey = (_) => zeros;
      final b = await newPhone();
      keepGuest(b);
      await b.c
          .read(inviteGuestProvider.notifier)
          .begin(link2, deviceName: 'Marta');
      await eventually(() => guest(b).phase == JoinPhase.failed);
      expect(guest(b).issue, JoinIssue.tampered);
      expect(a2, isNotNull);
    },
  );

  test(
    'el nombre del móvil que pide entrar se limpia antes de enseñarlo',
    () async {
      final (a, link) = await invited();
      final b = await newPhone();
      keepGuest(b);
      await b.c
          .read(inviteGuestProvider.notifier)
          .begin(link, deviceName: '\u202EMarta\u200B\u2066');
      // Lo que B manda ya va limpio...
      await eventually(() => host(a).phase == InvitePhase.request);
      expect(host(a).guestName, 'Marta');

      // ...y aunque otro cliente mandase caracteres raros, A los quita.
      final (a2, link2) = await invitedFrom(newPhone);
      await server.connect().requestJoin(
        link2.split('#').last,
        publicKey: (await InviteCrypto.generateKeyPair()).publicKey,
        deviceName: 'Ana\u202E\u200B\u0007 Pérez',
      );
      await eventually(() => host(a2).phase == InvitePhase.request);
      expect(host(a2).guestName, 'Ana Pérez');
    },
  );

  test('rechazar mata la invitación y B ve que no se ha aceptado', () async {
    final (a, link) = await invited();
    final b = await newPhone();
    keepGuest(b);
    await b.c
        .read(inviteGuestProvider.notifier)
        .begin(link, deviceName: 'Marta');
    await eventually(() => host(a).phase == InvitePhase.request);
    await a.c.read(inviteHostProvider.notifier).reject();
    await eventually(() => guest(b).phase == JoinPhase.gone);
    expect((await b.hasFamily()), isFalse);
  });

  test('una segunda persona con el mismo enlace recibe «ya pedida»', () async {
    final (a, link) = await invited();
    final b = await newPhone();
    keepGuest(b);
    await b.c
        .read(inviteGuestProvider.notifier)
        .begin(link, deviceName: 'Marta');
    final c = await newPhone();
    keepGuest(c);
    await c.c
        .read(inviteGuestProvider.notifier)
        .begin(link, deviceName: 'Intruso');
    expect(guest(c).phase, JoinPhase.taken);
    await eventually(() => host(a).phase == InvitePhase.request);
    expect(host(a).guestName, 'Marta');
  });

  test(
    'caducidad: A ve caducar la invitación y B ve «caducada o no aceptada»',
    () async {
      final (a, link) = await invited();
      final b = await newPhone();
      keepGuest(b);
      await b.c
          .read(inviteGuestProvider.notifier)
          .begin(link, deviceName: 'Marta');
      await eventually(() => guest(b).phase == JoinPhase.compare);
      server.expireInvites();
      await eventually(() => guest(b).phase == JoinPhase.gone);
      // A, que ya había ofrecido, intenta dar acceso a una invitación muerta.
      await a.c.read(inviteHostProvider.notifier).approve();
      expect(host(a).phase, InvitePhase.expired);
      expect((await b.hasFamily()), isFalse);
    },
  );

  test('caducidad sin petición: A pasa a caducada', () async {
    final (a, _) = await invited();
    server.expireInvites();
    await eventually(() => host(a).phase == InvitePhase.expired);
  });

  test(
    'si nadie acepta en 10 minutos (aquí, el tope de la prueba) B se rinde',
    () async {
      final (_, link) = await invited();
      final b = await newPhone(
        timing: const SyncTiming(
          invitePoll: Duration(milliseconds: 30),
          inviteHostPoll: Duration(hours: 1),
          inviteTimeout: Duration(milliseconds: 250),
        ),
      );
      keepGuest(b);
      await b.c
          .read(inviteGuestProvider.notifier)
          .begin(link, deviceName: 'Marta');
      await eventually(
        () => guest(b).phase == JoinPhase.gone,
        reason: 'el tope de espera',
      );
    },
  );

  test(
    'B cancela porque el código no coincide: no entra y A no da acceso',
    () async {
      final (a, link) = await invited();
      final b = await newPhone();
      keepGuest(b);
      await b.c
          .read(inviteGuestProvider.notifier)
          .begin(link, deviceName: 'Marta');
      await eventually(() => guest(b).phase == JoinPhase.compare);
      b.c.read(inviteGuestProvider.notifier).reject();
      expect(guest(b).phase, JoinPhase.mismatch);
      expect((await b.hasFamily()), isFalse);
      expect(server.calls['approve'], isNull);
      expect(
        host(a).phase,
        InvitePhase.request,
        reason: 'A sigue esperando su confirmación',
      );
    },
  );

  test('si B ya tiene una lista con datos pide confirmar el cambio, igual que con el QR', () async {
    final (a, link) = await invited();
    final b = await newPhone();
    keepGuest(b);
    await b.createFamily('Móvil de Marta');
    await b.putGift('mio', 'Algo mío');
    await b.c
        .read(inviteGuestProvider.notifier)
        .begin(link, deviceName: 'Marta');
    expect(guest(b).phase, JoinPhase.conflict);
    expect(
      server.calls['join'],
      isNull,
      reason: 'no se pide nada hasta confirmar',
    );
    expect(host(a).phase, InvitePhase.waiting);

    await b.c.read(inviteGuestProvider.notifier).confirmReplace();
    await eventually(() => host(a).phase == InvitePhase.request);
    await eventually(() => guest(b).phase == JoinPhase.compare);
    await a.c.read(inviteHostProvider.notifier).approve();
    await eventually(() => guest(b).phase == JoinPhase.joined);
    expect(guest(b).replaced, isTrue);
    expect(await b.listId(), await a.listId());
    expect(
      await b.gift('mio'),
      isNull,
      reason: 'la lista anterior se sustituyó',
    );
  });

  test('si B no quiere sustituir su lista, no pasa nada', () async {
    final (_, link) = await invited();
    final b = await newPhone();
    keepGuest(b);
    await b.createFamily();
    await b.putGift('mio', 'Algo mío');
    final listId = await b.listId();
    await b.c
        .read(inviteGuestProvider.notifier)
        .begin(link, deviceName: 'Marta');
    expect(guest(b).phase, JoinPhase.conflict);
    b.c.read(inviteGuestProvider.notifier).reset();
    expect(await b.listId(), listId);
    expect((await b.gift('mio'))!.title, 'Algo mío');
  });

  test(
    'enlace de otro servidor, texto cualquiera o sin servidor: error claro',
    () async {
      final b = await newPhone();
      keepGuest(b);
      final controller = b.c.read(inviteGuestProvider.notifier);
      await controller.begin(
        'https://evil.example/i#oKGio6SlpqeoqaqrrK2urw',
        deviceName: 'M',
      );
      expect(guest(b).issue, JoinIssue.badLink);
      await controller.begin('hola', deviceName: 'M');
      expect(guest(b).issue, JoinIssue.badLink);
      await controller.begin(
        'https://$kTestHost/i#oKGio6SlpqeoqaqrrK2urw',
        deviceName: 'M',
      );
      expect(
        guest(b).phase,
        JoinPhase.gone,
        reason: 'el servidor no la conoce',
      );

      final plain = FakePhone2.withoutServer();
      addTearDown(plain.dispose);
      final sub = plain.c.listen(inviteGuestProvider, (_, _) {});
      addTearDown(sub.close);
      await plain.c
          .read(inviteGuestProvider.notifier)
          .begin(
            'https://$kTestHost/i#oKGio6SlpqeoqaqrrK2urw',
            deviceName: 'M',
          );
      expect(plain.c.read(inviteGuestProvider).issue, JoinIssue.unavailable);
    },
  );

  test('sin la sincronización encendida no se puede invitar', () async {
    final a = await newPhone();
    await a.createFamily();
    await a.sync.setEnabled(false);
    await a.c.read(inviteHostProvider.notifier).create();
    expect(host(a).phase, InvitePhase.failed);
    expect(host(a).issue, InviteHostIssue.notReady);
    expect(server.openInvites, 0);
  });

  test('la invitación sobrevive a cerrar y abrir la app', () async {
    final (a, link) = await invited();
    final id = link.split('#').last;
    a.phone.restart();
    a.c.read(syncControllerProvider); // arranca la sincronización
    a.c.read(inviteHostProvider);
    await eventually(
      () => host(a).phase == InvitePhase.waiting,
      reason: 'restaurar',
    );
    expect(host(a).inviteId, id);
    expect(host(a).link, link);

    final b = await newPhone();
    keepGuest(b);
    await b.c
        .read(inviteGuestProvider.notifier)
        .begin(link, deviceName: 'Marta');
    await eventually(() => host(a).phase == InvitePhase.request);
  });

  test('cancelar la invitación la mata en el servidor', () async {
    final (a, link) = await invited();
    await a.c.read(inviteHostProvider.notifier).reject();
    expect(host(a).phase, InvitePhase.rejected);
    expect(server.openInvites, 0);
    final b = await newPhone();
    keepGuest(b);
    await b.c.read(inviteGuestProvider.notifier).begin(link, deviceName: 'M');
    expect(guest(b).phase, JoinPhase.gone);
  });

  test(
    'crear la invitación exige estar sincronizado: sin red, falla con aviso',
    () async {
      final a = await newPhone();
      await a.createFamily();
      a.transport.offline = true;
      await a.c.read(inviteHostProvider.notifier).create();
      expect(host(a).phase, InvitePhase.failed);
      expect(a.status.phase, SyncPhase.offline);
    },
  );

  test('la oferta llega a B antes de la confirmación y la aprobación no se acepta sin oferta (servidor falso)', () async {
    final (a, link) = await invited();
    final id = link.split('#').last;
    final t = server.connect();
    await expectLater(
      t.approveInvite(
        (await a.sync.credentials())!,
        id,
        InviteApproval(ciphertext: Uint8List(40), nonce: Uint8List(12)),
      ),
      throwsA(isA<SyncTransportException>()),
    );
  });
}

/// Crea una invitación en un móvil nuevo (para pruebas con dos invitaciones).
Future<(SyncPhone, String)> invitedFrom(
  Future<SyncPhone> Function() make,
) async {
  final a = await make();
  await a.createFamily();
  await a.sync.syncNow();
  await a.c.read(inviteHostProvider.notifier).create();
  return (a, a.c.read(inviteHostProvider).link!);
}

/// Un contenedor sin servidor, para probar la desactivación.
class FakePhone2 {
  FakePhone2._(this.c);

  factory FakePhone2.withoutServer() => FakePhone2._(
    ProviderContainer(
      retry: familyRetry,
      overrides: [syncHostProvider.overrideWithValue('')],
    ),
  );

  final ProviderContainer c;

  void dispose() => c.dispose();
}
