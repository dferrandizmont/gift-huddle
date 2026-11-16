// La clave común por época en la web (ADR 0005, lote B5). La web es un
// dispositivo `kind: web` (ADR 0003): recibe candidatas por paquetes v4 y
// firma el común con su Ed25519, pero nunca crea candidatas, nunca reparte
// y nunca sella con una candidata cuyo reparto no esté hecho (B6 de la revisión de seguridad).
//
// Todo vive dentro de la caja cifrada (`vault.opened.data`), en la misma
// escritura atómica que el registro y la instantánea:
// - [kWebCommonKeysField]: el `CommonKeyState` (llavero, revisión y `kid`
//   del último común abierto o publicado, con la referencia `common`). Cada
//   candidata lleva su contexto de época, su audiencia y su procedencia.
// - [kWebCommonFloorField]: la marca irreversible del formato mínimo.
// - `snapshot.writerKey`: la clave Ed25519 con la que se verificó el común
//   guardado (formato 2), para reabrirlo sin la red.
// - [kWebSeenVersionField]: la versión más alta vista, aunque su común no se
//   haya podido abrir (el suelo contra la vuelta atrás).
// PIN, guarda y secreto de la caja no cambian al rotar la clave común: solo
// cambia el contenido.
library;

import 'dart:typed_data';

import '../../../core/sync/device_keys.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_candidate.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/family_envelope.dart';
import '../../../core/sync/family_key_bundle.dart';
import '../../../core/sync/key_bundle.dart' show KeyBundleException;
import '../../../core/sync/access_policy.dart' show livePeopleOf;
import '../../sync/application/common_v2.dart';
import '../../sync/application/common_v2_cutover.dart';
import '../data/vault_store.dart';

/// El estado de la clave común en la caja.
const String kWebCommonKeysField = 'commonKeys';

/// La marca irreversible del formato mínimo del común en la caja.
const String kWebCommonFloorField = 'commonFormatFloor';

/// La versión más alta del servidor que ha visto esta web.
const String kWebSeenVersionField = 'seenVersion';

/// La clave del escritor del común guardado, dentro de `snapshot`.
const String kWebWriterKeyField = 'writerKey';

/// La marca del formato mínimo de la caja: 1 si no la hay; una que no se
/// entiende cuenta como 2 (como en los móviles); una posterior se devuelve
/// tal cual (hay que actualizar).
int webCommonFloor(VaultJson data) {
  final v = data[kWebCommonFloorField];
  if (v == null) return 1;
  if (v is int && v >= 1) return v;
  return kCommonFormatLatest;
}

/// El estado de la clave común de la caja. Sin él y con la marca puesta,
/// lanza [CommonStateException]: perder las claves no se arregla empezando
/// con un llavero vacío. Un estado dañado lanza [FamilyKeyException].
CommonKeyState webCommonKeys(VaultJson data) {
  final raw = data[kWebCommonKeysField];
  if (raw == null) {
    if (webCommonFloor(data) >= kCommonFormatLatest) {
      throw const CommonStateException('falta el estado de la clave común');
    }
    return CommonKeyState();
  }
  return CommonKeyState.fromJson(raw);
}

/// Abre el común de la instantánea guardada en la caja. El formato 2 se abre
/// con su candidata (por `kid`, referenciada como `common`) y la clave del
/// escritor con la que se verificó al guardarlo. El formato 1 solo puede
/// estar guardado si se guardó antes de la marca: tras ella la web nunca
/// guarda una instantánea en formato 1.
Future<FamilyDoc> openSavedCommon(
  VaultJson data, {
  required String listId,
  required String syncId,
}) async {
  final snapshot = data['snapshot'] as Map;
  final bytes = decodeBase64Url(snapshot['common'] as String);
  if (isFamilyEnvelope(bytes)) {
    final writerKey = decodeBase64Url(snapshot[kWebWriterKeyField] as String);
    final opened = await openFamilyEnvelope(
      bytes,
      expectedListId: listId,
      expectedSyncId: syncId,
      resolveWriter: (_, _) => writerKey,
      keyring: webCommonKeys(data).keyring,
    );
    return opened.doc;
  }
  final plain = await open(
    bytes,
    key: FamilyKey.fromBase64Url(data['familyKey'] as String),
    expectedListId: listId,
  );
  return FamilyDoc.fromJson(plain.doc);
}

/// La candidata con la que la web puede sellar, o null (entonces la web no
/// publica y retiene sus cambios cifrados en la cola).
///
/// La web no crea candidatas ni reparte, así que solo vuelve a sellar con la
/// del común remoto que acaba de abrir ([remoteKid]) y solo si:
/// - está en su llavero y no es histórica ni comprometida;
/// - sella desde [view] (la vista de su raíz): misma lista y generación,
///   contexto actual y audiencia exactamente igual a los activos con su
///   ficha, la web incluida;
/// - su reparto está hecho: cada miembro de la audiencia que no es la web,
///   ni su creador, ni [writer] (quien selló el común remoto con ella) tiene
///   en [packages] un paquete que lo entrega ([webDeliveredPackage]).
Future<FamilyCandidate?> webSealingCandidate({
  required FamilyKeyring keyring,
  required String? remoteKid,
  required String? writer,
  required RegistryView view,
  required DeviceRegistry registry,
  required String syncId,
  required String me,
  required List<Map<String, Object?>> packages,
}) async {
  if (remoteKid == null) return null;
  final entry = keyring.entry(remoteKid);
  if (entry == null || !entry.usable) return null;
  final candidate = entry.candidate;
  final self = view.member(me);
  if (self == null ||
      candidate.audienceOf(me)?.recordDigest != self.recordDigest ||
      !candidate.sealableIn(view, syncId: syncId)) {
    return null;
  }
  for (final m in candidate.audience) {
    if (m.deviceId == me ||
        m.deviceId == candidate.creator ||
        m.deviceId == writer) {
      continue;
    }
    var delivered = false;
    for (final p in packages) {
      if (p['to'] == m.deviceId &&
          await webDeliveredPackage(p, candidate, m, view, registry)) {
        delivered = true;
        break;
      }
    }
    if (!delivered) return null;
  }
  return candidate;
}

/// Si el paquete v4 [raw] entrega [candidate] a [to] (revisión de seguridad,
/// B1). Es más estricto que [usefulFamilyPackage] (el de los móviles, que no
/// cambia):
/// - el emisor es un miembro activo **móvil** de [view], con `fr` igual a su
///   ficha actual o a una anterior del mismo id, del mismo tipo y con la
///   misma clave de firma; ni él ni el destinatario están revocados;
/// - el destinatario es [to] con su ficha (`to`, `tr`) y esa ficha está en
///   el registro;
/// - la cabecera es la de la candidata: `l`, `sid`, `e`, `ctx`, `kid`, `c`,
///   `cr`, `cs` y la audiencia, idénticos;
/// - y la firma del emisor vale con su clave y la de acuerdo del destino.
/// No se puede abrir (no es para la web): esto prueba que lo firmó un
/// miembro para esa candidata, no que se abra.
Future<bool> webDeliveredPackage(
  Map<String, Object?> raw,
  FamilyCandidate candidate,
  AudienceMember to,
  RegistryView view,
  DeviceRegistry registry,
) async {
  final FamilyKeyBundle bundle;
  try {
    bundle = FamilyKeyBundle.fromJson(raw);
  } on KeyBundleException {
    return false;
  }
  final sender = view.member(bundle.fromDevice);
  final senderRecord = registry.recordByDigest(bundle.senderRecord);
  final recipient = registry.recordByDigest(bundle.recipientRecord);
  if (sender == null ||
      sender.kind != DeviceKind.mobile ||
      senderRecord == null ||
      senderRecord.deviceId != bundle.fromDevice ||
      senderRecord.kind != DeviceKind.mobile ||
      (bundle.senderRecord != sender.recordDigest &&
          !constantTimeEquals(senderRecord.keys.signing, sender.signingKey)) ||
      reallyRevoked(view, bundle.fromDevice) ||
      reallyRevoked(view, bundle.toDevice) ||
      bundle.toDevice != to.deviceId ||
      bundle.recipientRecord != to.recordDigest ||
      recipient == null ||
      recipient.deviceId != to.deviceId) {
    return false;
  }
  final sameAudience =
      bundle.audience.length == candidate.audience.length &&
      [
        for (var i = 0; i < bundle.audience.length; i++)
          bundle.audience[i] == candidate.audience[i],
      ].every((same) => same);
  if (bundle.listId != candidate.listId ||
      bundle.syncId != candidate.syncId ||
      bundle.epochNumber != candidate.epochNumber ||
      bundle.epochContext != candidate.epochContext ||
      bundle.kid != candidate.kid ||
      bundle.creator != candidate.creator ||
      bundle.creatorRecord != candidate.creatorRecord ||
      !constantTimeEquals(
        bundle.creatorSignature,
        candidate.creatorSignature,
      ) ||
      !sameAudience) {
    return false;
  }
  return bundle.verifySender(
    senderSigningKey: senderRecord.keys.signing,
    recipientAgreementKey: recipient.keys.agreement,
  );
}

/// Si [bytes] dicen ser un sobre "RG" de un formato posterior al 2.
bool laterCommonFormat(Uint8List bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0x52 &&
    bytes[1] == 0x47 &&
    bytes[2] > kFamilyEnvelopeVersion;

/// Los campos de la caja de una web que se empareja con una familia que ya
/// usa el formato 2 del común (B7: `PairingV2Joined.commonFormat` y
/// `commonKeys`). Devuelve [data] (lo que la web guarda hoy al emparejarse)
/// con la marca, el llavero y una instantánea que la web sabe reabrir.
///
/// - Con [commonFormat] 1 devuelve [data] tal cual (el camino de siempre).
/// - Con 2: [commonKeys] tiene que traer en `lastKid` la candidata del
///   checkpoint; si no, [CommonStateException]. Un formato posterior lanza
///   [EnvelopeFormatException].
/// - La instantánea guardada lleva como común la base aprobada [common],
///   sellada **solo en local** con esa candidata y firmada por la propia web
///   ([keys]), con su `writerKey`: no se publica nunca. El resto de la
///   instantánea (versión, slots) es el de `data['snapshot']`. La primera
///   vuelta del motor la sustituye por el común remoto si lo abre.
/// - [registry] y [root] (el ancla del anfitrión) dan la vista con la que se
///   comprueba que la web es miembro con esas claves.
/// - [commonKeys] solo puede traer candidatas que hayan salido de
///   `FamilyKeyBundle.open` (con el creador verificado): aquí no se vuelven a
///   comprobar.
/// - [commonFormat] tiene que salir de la aprobación **firmada** por el
///   anfitrión, nunca del mínimo del servidor (que no va firmado).
/// - [syncId] es el de la caja (su cabecera) y el `listId`, el de [data]: al
///   final se reabre lo sellado con [openSavedCommon] y, si no abre, lanza
///   [CommonStateException] (no se instala una caja que no se puede leer).
Future<VaultJson> webCommonInstall(
  VaultJson data, {
  required int commonFormat,
  required CommonKeyState? commonKeys,
  required FamilyDoc common,
  required DeviceKeys keys,
  required String deviceId,
  required DeviceRegistry registry,
  required RegistryAnchor root,
  required String syncId,
}) async {
  if (commonFormat > kCommonFormatLatest) {
    throw const EnvelopeFormatException(
      'la familia usa un formato posterior del común: hay que actualizar',
    );
  }
  if (commonFormat < kCommonFormatLatest) return data;
  final lastKid = commonKeys?.lastKid;
  final entry = lastKid == null ? null : commonKeys!.keyring.entry(lastKid);
  if (entry == null) {
    throw const CommonStateException('falta la clave común del checkpoint');
  }
  final view = await registry.viewFor(
    me: root.deviceId,
    mySigningKey: root.signingKey,
    livePeople: livePeopleOf(common),
  );
  final writer = view.member(deviceId);
  if (writer == null) {
    throw const CommonStateException('la web no es miembro de la familia');
  }
  final bytes = await sealFamilyEnvelope(
    doc: common,
    candidate: entry.candidate,
    writer: writer,
    revision: commonKeys!.revision,
    signer: keys,
  );
  final state = CommonKeyState(
    keyring: withCommonReferences(
      commonKeys.keyring,
      lastKid: lastKid,
      outbox: const [],
      retained: const [],
    ),
    revision: commonKeys.revision,
    lastKid: lastKid,
  );
  final installed = <String, Object?>{
    ...data,
    kWebCommonKeysField: state.toJson(),
    kWebCommonFloorField: kCommonFormatLatest,
    'snapshot': {
      ...(data['snapshot']! as Map).cast<String, Object?>(),
      'common': encodeBase64Url(bytes),
      kWebWriterKeyField: encodeBase64Url(keys.publicKeys.signing),
    },
  };
  try {
    await openSavedCommon(
      installed,
      listId: data['listId']! as String,
      syncId: syncId,
    );
  } on Exception {
    throw const CommonStateException('la base instalada no se puede abrir');
  }
  return installed;
}
