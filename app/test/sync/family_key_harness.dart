// Ayudas de las pruebas del lote B1 del ADR 0005 (clave común por época).
import 'package:regalos/core/sync/device_registry.dart';
import 'package:regalos/core/sync/family_candidate.dart';

import 'protected_harness.dart';

/// Generación de las pruebas (22 caracteres).
const kSync = 'QUJDREVGR0hJSktMTU5PUA';

/// Otra generación.
const kOtherSync = 'WllZWllZWllZWllZWllZWg';

/// Un secreto fijo de 32 bytes que empieza en [seed] (nunca todo ceros).
List<int> secretOf(int seed) =>
    List<int>.generate(32, (i) => (seed + i) % 256 == 0 ? 1 : (seed + i) % 256);

/// El móvil de [family] con ese id.
Phone phoneOf(Family family, String id) =>
    [family.aritz, family.leo, family.nora].firstWhere((p) => p.id == id);

/// La candidata del móvil de [view] para su época, con secreto fijo y
/// firmada por su creador (o por [signer], para falsificar).
Future<FamilyCandidate> candidateFor(
  Family family,
  RegistryView view, {
  int seed = 7,
  String syncId = kSync,
  Iterable<AudienceMember>? audience,
  String? context,
  int? epoch,
  String? creator,
  String? creatorRecord,
  Phone? signer,
}) {
  final descriptor = EpochDescriptor.ofView(view, syncId: syncId);
  final who = creator ?? view.me;
  return FamilyCandidate.create(
    listId: view.listId,
    syncId: syncId,
    epochNumber: epoch ?? view.epoch,
    epochContext: context ?? descriptor.context,
    creator: who,
    creatorRecord: creatorRecord ?? view.member(who)!.recordDigest,
    audience: audience ?? descriptor.members,
    secret: secretOf(seed),
    creatorKeys: (signer ?? phoneOf(family, who)).keys,
  );
}

/// El registro de [family] con [revoked] revocado por Aritz.
Future<DeviceRegistry> withRevoked(Family family, Phone revoked) async =>
    family.registry.withRevocation(
      await Revocation.create(
        keys: family.aritz.keys,
        by: (await family.aritz.record()),
        deviceId: revoked.id,
      ),
    );

/// Una web confirmada por Aritz: su registro, el teléfono de la web y las
/// vistas de Aritz (su raíz) y de Leo.
Future<
  ({DeviceRegistry registry, Phone web, RegistryView root, RegistryView leo})
>
withWeb(Family family) async {
  final web = await Phone.create('web-1', null, 7);
  final record = await DeviceRecord.create(
    keys: web.keys,
    listId: kListId,
    deviceId: 'web-1',
    personId: null,
    kind: DeviceKind.web,
  );
  var registry = await family.registry.withRecord(record);
  registry = await registry.withVouch(
    await Vouch.create(
      keys: family.aritz.keys,
      voucher: await family.aritz.record(),
      record: record,
    ),
  );
  return (
    registry: registry,
    web: web,
    root: await family.aritz.viewOf(registry),
    leo: await family.leo.viewOf(registry),
  );
}
