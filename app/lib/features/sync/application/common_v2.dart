// La clave común por época en los móviles (ADR 0005, lote B3): lo que el
// ciclo guarda entre vueltas y la parte del ciclo de `SyncV2Engine` que
// trata el común sellado con candidatas cuando el interruptor
// `V2SyncState.commonFormatV2` está encendido.
//
// Orden (sección 4 del ADR): el motor recupera las operaciones, lee la
// instantánea, verifica y fusiona el registro y resuelve los permisos; aquí
// se abren y guardan los paquetes v4 dirigidos a este móvil ([receive],
// pasos 5 y 6), se verifica, abre y fusiona el común y, después de las
// sorpresas, se elige o crea la candidata, se persiste con su reparto antes
// de sellar ([prepare], pasos 8 y 9) y, si el `PUT` entra, se apunta
// ([accepted]).
//
// No depende de Flutter.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../core/sync/device_keys.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/platform/task_runner.dart';
import '../../../core/sync/exchange_file.dart';
import '../../../core/sync/family_candidate.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/family_envelope.dart';
import '../../../core/sync/family_key_bundle.dart';
import '../../../core/sync/key_bundle.dart' show KeyBundleException;
import '../../../core/sync/pairing_v2.dart' show syncProtocolOf;
import '../../family/domain/family_errors.dart' show ImportClockDriftException;
import 'common_v2_cutover.dart';
import 'sync_v2_engine.dart' show SyncV2Local;

/// Vueltas de sincronización (`sync()`, no reintentos tras `412`) con el
/// mismo común remoto que es basura demostrable antes de sustituirlo: un
/// sobre que no abre con la candidata exacta, o de un id sin ninguna
/// presencia enlazada en el registro. Se cuentan vueltas, no horas: el
/// reloj de pared se puede mover.
const int kCommonUnreadableRounds = 3;

/// Comunes reintentables (falta la clave, escritor por confirmar, basura
/// cifrada) que se guardan aparte, con sus bytes.
const int kMaxRetainedWaiting = 4;

/// Comunes de un revocado que se guardan aparte, con sus bytes, para la
/// recuperación explícita.
const int kMaxRetainedRevoked = 2;

/// Comunes falsos de los que se guarda solo el resumen (nunca los bytes).
const int kMaxRetainedForged = 16;

/// Comunes de ficheros `.regalos` (B6) que esperan su clave o a su escritor:
/// su propio cupo, para que un fichero nunca desaloje a un común del
/// servidor.
const int kMaxRetainedFiles = 4;

/// Paquetes que acepta el Worker en una instantánea (`V2_MAX_PACKAGES`).
const int kV2MaxKeyPackages = 512;

/// Bytes de los paquetes que acepta el Worker (`V2_MAX_PACKAGES_BYTES`).
const int kV2MaxKeyPackagesBytes = 256 * 1024;

/// Paquetes v4 ajenos de un mismo emisor que se vuelven a subir, y tope del
/// Worker por escritor (`V2_MAX_PACKAGES_PER_WRITER`).
const int kMaxFamilyPackagesPerSender = 128;

/// Paquetes propios (v3 y v4 juntos) que acepta el Worker por escritor
/// (`V2_MAX_PACKAGES_PER_WRITER`): la cuarta parte de la lista.
const int kV2MaxPackagesPerWriter = 128;

/// Bytes de los paquetes propios que acepta el Worker por escritor
/// (`V2_MAX_PACKAGE_BYTES_PER_WRITER`): la suma del JSON de cada uno.
const int kV2MaxPackageBytesPerWriter = 64 * 1024;

/// [v3] sin los v3 propios ([me]) más antiguos que hagan falta para que lo
/// propio de [v3] y [v4] juntos quepa en el tope por escritor del Worker
/// ([kV2MaxPackagesPerWriter] y [kV2MaxPackageBytesPerWriter]): así el `PUT`
/// nunca falla por eso. Los v4 propios (el reparto del común) no se tocan.
List<Map<String, Object?>> trimOwnPackages(
  List<Map<String, Object?>> v3,
  List<Map<String, Object?>> v4, {
  required String me,
}) {
  int size(Map<String, Object?> p) => utf8.encode(jsonEncode(p)).length;
  var count = 0;
  var bytes = 0;
  for (final p in [...v3, ...v4]) {
    if (p['from'] != me) continue;
    count++;
    bytes += size(p);
  }
  if (count <= kV2MaxPackagesPerWriter &&
      bytes <= kV2MaxPackageBytesPerWriter) {
    return v3;
  }
  final out = <Map<String, Object?>>[];
  for (final p in v3) {
    if (p['from'] == me &&
        (count > kV2MaxPackagesPerWriter ||
            bytes > kV2MaxPackageBytesPerWriter)) {
      count--;
      bytes -= size(p);
      continue;
    }
    out.add(p);
  }
  return out;
}

/// A partir de aquí se olvidan las candidatas que ya no sellan, no tienen
/// referencias ni se buscan (las de época más baja primero). El tope duro
/// del llavero es [kMaxFamilyCandidates].
const int kCommonKeyringSoftLimit = 192;

/// Referencia de la candidata del último común abierto o publicado.
const String kCommonRef = 'common';

/// Referencia de la candidata con paquetes pendientes de subir.
const String kOutboxRef = 'outbox';

const _retainedRefPrefix = 'retained:';

/// Referencia de un común retenido (por su hash).
String retainedRef(String hash) =>
    '$_retainedRefPrefix${hash.substring(0, 32)}';

/// El estado de la clave común no se puede leer o ha desaparecido: nunca se
/// vuelve a empezar en silencio con un llavero vacío.
class CommonStateException implements Exception {
  /// Crea el error.
  const CommonStateException(this.message);

  /// Qué ha pasado.
  final String message;

  @override
  String toString() => 'CommonStateException: $message';
}

/// Qué ha pasado con el común remoto en esta vuelta.
enum RemoteCommonStatus {
  /// No hay común en el servidor.
  empty,

  /// Formato 1 (la clave de la familia de siempre), solo mientras este móvil
  /// no ha abierto ni publicado ningún formato 2: se abre y se vuelve a
  /// sellar. Después un formato 1 es [forged].
  legacy,

  /// Formato 2, abierto y fusionado.
  opened,

  /// Falta la candidata con la que se selló (el escritor es un miembro
  /// activo con firma válida): se espera sin plazo.
  missingKey,

  /// El escritor no es un miembro activo con esa ficha. Si es un dispositivo
  /// conocido (pendiente, suelto o que fue miembro) se espera sin plazo; si
  /// el id no tiene ninguna presencia enlazada, es basura.
  unknownWriter,

  /// Escritor reconocido, firma válida y la candidata exacta en el llavero,
  /// pero no se puede leer: basura demostrable.
  unreadable,

  /// No es un sobre válido, la firma no vale o es un formato 1 después del
  /// formato 2: nadie de la familia lo ha escrito. Se sustituye ya.
  forged,

  /// Lo firma (de verdad) un móvil revocado: no se fusiona, se guarda aparte
  /// y se sustituye ya.
  revokedWriter,
}

/// Si con [status] se ha podido leer el común remoto.
bool commonReadable(RemoteCommonStatus status) =>
    status == RemoteCommonStatus.empty ||
    status == RemoteCommonStatus.legacy ||
    status == RemoteCommonStatus.opened;

/// Si con [status] el común remoto se respeta (no se sustituye) por ahora.
bool commonWaits(RemoteCommonStatus status) =>
    status == RemoteCommonStatus.missingKey ||
    status == RemoteCommonStatus.unknownWriter ||
    status == RemoteCommonStatus.unreadable;

/// Si [id] tiene alguna presencia enlazada en [view]: activo, pendiente,
/// suelto, revocado o ambiguo, o fue miembro alguna vez.
bool linkedPresence(RegistryView view, String id) =>
    view.device(id) != null ||
    view.everMembers.contains(id) ||
    view.revoked.contains(id) ||
    view.linkedSigningKey(id) != null ||
    view.detached.any((d) => d.deviceId == id);

/// La clave con la que este dispositivo conoce a [writer] aunque no sea un
/// miembro activo (N1 de la revisión de seguridad): la enlazada por avales desde [view] o, si
/// no la hay, la de la ficha [writerRecord] de [registry] cuando es de ese
/// id, el id tiene presencia enlazada y todas sus fichas llevan esa misma
/// clave (una ficha más con otra clave, p. ej. puesta por un atacante, lo
/// deja sin autenticar). Null si no hay ninguna.
List<int>? knownWriterKey(
  RegistryView view,
  DeviceRegistry registry,
  String writer,
  String writerRecord,
) {
  final linked = view.linkedSigningKey(writer);
  if (linked != null) return linked;
  final record = registry.recordByDigest(writerRecord);
  if (record == null ||
      record.deviceId != writer ||
      !linkedPresence(view, writer)) {
    return null;
  }
  final sameKey = registry.records
      .where((r) => r.deviceId == writer)
      .every((r) => constantTimeEquals(r.keys.signing, record.keys.signing));
  return sameKey ? record.keys.signing : null;
}

/// Un común remoto que este móvil no ha fusionado y guarda aparte. Es la
/// entrada del índice: los bytes, si se guardan ([hasBytes]), van en su
/// propio fichero y se leen solo para reintentar.
class RetainedCommon {
  /// Crea la entrada.
  const RetainedCommon({
    required this.hash,
    required this.reason,
    required this.seenAtMillis,
    required this.hasBytes,
    this.kid,
    this.writer,
    this.fromFile = false,
  });

  /// SHA-256 de los bytes.
  final String hash;

  /// Por qué no se fusionó.
  final RemoteCommonStatus reason;

  /// Cuándo se vio por primera vez.
  final int seenAtMillis;

  /// Si sus bytes están guardados (los falsos, no).
  final bool hasBytes;

  /// `kid` de la cabecera (sin autenticar), si se pudo leer.
  final String? kid;

  /// Escritor de la cabecera (sin autenticar), si se pudo leer.
  final String? writer;

  /// Si llegó en un fichero `.regalos` de intercambio (B6) y no del
  /// servidor: tiene su propio cupo ([kMaxRetainedFiles]).
  final bool fromFile;

  /// Si se vuelve a intentar abrir en cada vuelta (llega la clave o se
  /// aprueba al escritor). Los de un revocado o falsos, no.
  bool get retryable => commonWaits(reason);

  /// Copia con otro motivo (sin bytes si pasa a falso).
  RetainedCommon withReason(RemoteCommonStatus reason) => RetainedCommon(
    hash: hash,
    reason: reason,
    seenAtMillis: seenAtMillis,
    hasBytes: hasBytes && reason != RemoteCommonStatus.forged,
    kid: kid,
    writer: writer,
    fromFile: fromFile,
  );

  /// En JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'h': hash,
    'r': reason.name,
    't': seenAtMillis,
    if (hasBytes) 'b': true,
    'k': ?kid,
    'w': ?writer,
    if (fromFile) 'f': true,
  };

  /// Lee [toJson]. Lanza [CommonStateException] si no vale: un retenido no
  /// se descarta en silencio.
  factory RetainedCommon.fromJson(Object? json) {
    final reason = json is Map
        ? RemoteCommonStatus.values
              .where((r) => r.name == json['r'] && !commonReadable(r))
              .firstOrNull
        : null;
    if (json is! Map ||
        reason == null ||
        json['h'] is! String ||
        !isFamilyHash(json['h'] as String) ||
        json['t'] is! int ||
        (json['b'] != null && json['b'] != true) ||
        (json['k'] != null && json['k'] is! String) ||
        (json['w'] != null && json['w'] is! String) ||
        (json['f'] != null && json['f'] != true)) {
      throw const CommonStateException('común retenido no válido');
    }
    return RetainedCommon(
      hash: json['h'] as String,
      reason: reason,
      seenAtMillis: json['t'] as int,
      hasBytes: json['b'] == true,
      kid: json['k'] as String?,
      writer: json['w'] as String?,
      fromFile: json['f'] == true,
    );
  }
}

/// El común remoto [hash] lleva [rounds] vueltas sin poderse abrir; la
/// última, [lastRound]. [writer] es su escritor (sin autenticar) y
/// [autoExit], si es basura demostrable que se sustituye tras
/// [kCommonUnreadableRounds].
class CommonBlock {
  /// Crea el bloqueo.
  const CommonBlock({
    required this.hash,
    required this.rounds,
    required this.lastRound,
    required this.autoExit,
    this.writer,
  });

  /// SHA-256 del común bloqueado.
  final String hash;

  /// Vueltas de sincronización seguidas con ese mismo común.
  final int rounds;

  /// Identificador de la última vuelta contada.
  final String lastRound;

  /// Si se sustituye solo tras las vueltas.
  final bool autoExit;

  /// Escritor de la cabecera.
  final String? writer;

  /// Si ya se puede sustituir.
  bool get over => autoExit && rounds >= kCommonUnreadableRounds;

  Map<String, Object?> _toJson() => {
    'h': hash,
    'n': rounds,
    'l': lastRound,
    if (autoExit) 'x': true,
    'w': ?writer,
  };

  static CommonBlock? _fromJson(Object? b) =>
      b is Map && b['h'] is String && b['n'] is int && b['l'] is String
      ? CommonBlock(
          hash: b['h'] as String,
          rounds: b['n'] as int,
          lastRound: b['l'] as String,
          autoExit: b['x'] == true,
          writer: b['w'] is String ? b['w'] as String : null,
        )
      : null;
}

/// Lo que guarda este móvil de la clave común entre vueltas, en una sola
/// escritura atómica: el llavero, los paquetes v4 que aún no ha aceptado un
/// `PUT` (la intención de reparto), la revisión de sus publicaciones, la
/// candidata del último común abierto o publicado y el bloqueo de un común
/// remoto ilegible.
class CommonKeyState {
  /// Crea el estado.
  CommonKeyState({
    FamilyKeyring? keyring,
    this.outbox = const <Map<String, Object?>>[],
    this.revision = 0,
    this.lastKid,
    this.blocked,
  }) : keyring = keyring ?? FamilyKeyring.empty;

  /// El llavero común.
  final FamilyKeyring keyring;

  /// Paquetes v4 aún no aceptados por un `PUT`.
  final List<Map<String, Object?>> outbox;

  /// La última revisión de común que ha sellado este móvil.
  final int revision;

  /// `kid` del último común abierto o publicado. Con él, este móvil ya ha
  /// pasado al formato 2 y no vuelve a aceptar el formato 1.
  final String? lastKid;

  /// El común remoto que no se puede abrir.
  final CommonBlock? blocked;

  /// Copia con cambios.
  CommonKeyState copyWith({
    FamilyKeyring? keyring,
    List<Map<String, Object?>>? outbox,
    int? revision,
    String? lastKid,
  }) => CommonKeyState(
    keyring: keyring ?? this.keyring,
    outbox: outbox ?? this.outbox,
    revision: revision ?? this.revision,
    lastKid: lastKid ?? this.lastKid,
    blocked: blocked,
  );

  /// En JSON (contiene secretos).
  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'k': keyring.toJson(),
    if (outbox.isNotEmpty) 'o': outbox,
    'r': revision,
    'c': ?lastKid,
    if (blocked != null) 'b': blocked!._toJson(),
  };

  /// Lee [toJson]. El llavero tiene que valer: un llavero dañado lanza
  /// [FamilyKeyException] (no se olvidan claves en silencio).
  factory CommonKeyState.fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) {
      throw const FamilyKeyException('estado de la clave común no válido');
    }
    final r = json['r'];
    final c = json['c'];
    return CommonKeyState(
      keyring: FamilyKeyring.fromJson(json['k']),
      outbox: [
        if (json['o'] is List)
          for (final p in json['o'] as List)
            if (p is Map) Map<String, Object?>.from(p),
      ],
      revision: r is int && r >= 0 && r <= kMaxFamilyRevision ? r : 0,
      lastKid: c is String && isFamilyHash(c) ? c : null,
      blocked: CommonBlock._fromJson(json['b']),
    );
  }
}

/// Si [id] está revocado de verdad en [view]: hay una revocación firmada
/// que cuenta (`RegistryView.explicitlyRevoked`). Un id solo ambiguo puede
/// aclararse y no lo es; un revocado que después se hace ambiguo (otra ficha
/// con su clave) lo sigue siendo (B6, M1 de la revisión de seguridad): una revocación no se
/// deshace. Si es ambiguo no hay clave enlazada con la que comprobar su
/// firma, así que lo suyo cuenta como falso.
bool reallyRevoked(RegistryView view, String id) =>
    view.explicitlyRevoked.contains(id);

/// El resolvedor del escritor del común para un dispositivo con [view]
/// (sale de [registry]): solo un miembro activo, con su ficha actual o con
/// una ficha anterior del mismo dispositivo, del mismo tipo y con la misma
/// clave de firma (p. ej. selló antes de cambiar de persona). Un revocado,
/// un pendiente o un ambiguo no escriben. Vale igual para la web (B5).
FamilyWriterResolver commonWriterResolver(
  RegistryView view,
  DeviceRegistry registry,
) => (writer, writerRecord) {
  final member = view.member(writer);
  if (member == null) return null;
  if (writerRecord == member.recordDigest) return member.signingKey;
  final record = registry.recordByDigest(writerRecord);
  if (record != null &&
      record.deviceId == writer &&
      record.kind == member.kind &&
      constantTimeEquals(record.keys.signing, member.signingKey)) {
    return member.signingKey;
  }
  return null;
};

/// El `kid` de un paquete v4, o null.
String? familyPackageKid(Map<String, Object?> raw) {
  if (!FamilyKeyBundle.isV4(raw)) return null;
  final kid = raw['kid'];
  return kid is String ? kid : null;
}

/// Si en [packages] hay un paquete **propio** ([me]) de [kid] para [to] con
/// su ficha [toRecord] (M1): el de otro emisor no cuenta como entregado,
/// porque este móvil no puede saber si se abre.
bool hasOwnFamilyPackage(
  Iterable<Map<String, Object?>> packages, {
  required String me,
  required String kid,
  required String to,
  required String toRecord,
}) => packages.any(
  (p) =>
      p['from'] == me &&
      familyPackageKid(p) == kid &&
      p['to'] == to &&
      p['tr'] == toRecord,
);

/// Si se sube otra vez un paquete v4 propio del servidor: solo si es de una
/// candidata de [kids] y su destinatario sigue activo con esa ficha. Los
/// demás son material sustituido: el común que se sube no se selló con ellos.
bool keepOwnFamilyPackage(
  Map<String, Object?> raw,
  RegistryView view,
  Set<String> kids,
) {
  final to = raw['to'];
  return to is String &&
      kids.contains(familyPackageKid(raw)) &&
      view.member(to)?.recordDigest == raw['tr'];
}

/// Si un paquete v4 ajeno del servidor puede servir a alguien y se vuelve a
/// subir (A1): tiene que leerse, su emisor y su destinatario no pueden estar
/// revocados de verdad, sus fichas `fr` y `tr` tienen que estar en el
/// registro (la del emisor, de un móvil) y la firma del emisor tiene que
/// valer con ellas.
Future<bool> usefulFamilyPackage(
  Map<String, Object?> raw,
  RegistryView view,
  DeviceRegistry registry,
) async {
  final FamilyKeyBundle bundle;
  try {
    bundle = FamilyKeyBundle.fromJson(raw);
  } on KeyBundleException {
    return false;
  }
  if (reallyRevoked(view, bundle.fromDevice) ||
      reallyRevoked(view, bundle.toDevice) ||
      bundle.listId != view.listId) {
    return false;
  }
  final from = registry.recordByDigest(bundle.senderRecord);
  final to = registry.recordByDigest(bundle.recipientRecord);
  if (from == null ||
      from.deviceId != bundle.fromDevice ||
      from.kind != DeviceKind.mobile ||
      to == null ||
      to.deviceId != bundle.toDevice) {
    return false;
  }
  return bundle.verifySender(
    senderSigningKey: from.keys.signing,
    recipientAgreementKey: to.keys.agreement,
  );
}

/// El llavero con las referencias del común al día: [lastKid] (el último
/// común abierto o publicado), las candidatas de [outbox] y las de los
/// [retained] con bytes. Las demás referencias no se tocan.
FamilyKeyring withCommonReferences(
  FamilyKeyring keyring, {
  required String? lastKid,
  required Iterable<Map<String, Object?>> outbox,
  required Iterable<RetainedCommon> retained,
}) {
  var next = keyring;
  for (final e in keyring.entries) {
    for (final ref in e.references) {
      if (ref == kCommonRef ||
          ref == kOutboxRef ||
          ref.startsWith(_retainedRefPrefix)) {
        next = next.withoutReference(e.candidate.kid, ref);
      }
    }
  }
  void add(String? kid, String ref) {
    if (kid != null && next.entry(kid) != null) {
      next = next.withReference(kid, ref);
    }
  }

  add(lastKid, kCommonRef);
  for (final p in outbox) {
    add(familyPackageKid(p), kOutboxRef);
  }
  for (final r in retained) {
    if (r.hasBytes) add(r.kid, retainedRef(r.hash));
  }
  return next;
}

/// Olvida, por encima de [kCommonKeyringSoftLimit], las candidatas que ya
/// no sellan desde [view], sin referencias y que no están en [wanted]: las
/// de época más baja primero. Lo que se necesita nunca sale.
FamilyKeyring trimCommonKeyring(
  FamilyKeyring keyring,
  RegistryView view, {
  required String syncId,
  required Set<String> wanted,
}) {
  if (keyring.length <= kCommonKeyringSoftLimit) return keyring;
  final idle =
      [
        for (final e in keyring.entries)
          if (e.references.isEmpty &&
              !wanted.contains(e.candidate.kid) &&
              !e.candidate.sealableIn(view, syncId: syncId))
            e.candidate,
      ]..sort((a, b) {
        final byEpoch = a.epochNumber.compareTo(b.epochNumber);
        return byEpoch != 0 ? byEpoch : a.kid.compareTo(b.kid);
      });
  var next = keyring;
  for (final c in idle) {
    if (next.length <= kCommonKeyringSoftLimit) break;
    next = next.without(c.kid);
  }
  return next;
}

/// Si [packages] caben en los límites del Worker (número y bytes).
bool familyPackagesFit(List<Map<String, Object?>> packages) =>
    packages.length <= kV2MaxKeyPackages &&
    utf8.encode(jsonEncode(packages)).length <= kV2MaxKeyPackagesBytes;

/// Lo que cabe en los límites del Worker (número y bytes): todo
/// [mandatory] (el reparto propio del común), después los v4 ajenos de
/// [preferred] (los de la candidata en juego), después los v3 más nuevos y
/// después los v4 de [optional] (A1). Devuelve los v3 que van (en su orden) y los
/// v4 que van. Nunca repite una entrada: el Worker rechaza la lista entera
/// si lleva dos iguales.
(List<Map<String, Object?>>, List<Map<String, Object?>>) budgetPackages(
  List<Map<String, Object?>> mandatory,
  List<Map<String, Object?>> v3,
  List<Map<String, Object?>> optional, {
  List<Map<String, Object?>> preferred = const [],
}) {
  final seen = <String>{};
  mandatory = [
    for (final p in mandatory)
      if (seen.add(jsonEncode(p))) p,
  ];
  var count = mandatory.length;
  var size = utf8.encode(jsonEncode(mandatory)).length;
  bool take(Map<String, Object?> p) {
    if (seen.contains(jsonEncode(p))) return false;
    // Cada uno más suma sus bytes y una coma (si no es el primero).
    final more = utf8.encode(jsonEncode(p)).length + (count > 0 ? 1 : 0);
    if (count + 1 > kV2MaxKeyPackages || size + more > kV2MaxKeyPackagesBytes) {
      return false;
    }
    count++;
    size += more;
    seen.add(jsonEncode(p));
    return true;
  }

  final first = [
    for (final p in preferred)
      if (take(p)) p,
  ];
  final keep = <int>{};
  for (var i = v3.length - 1; i >= 0; i--) {
    if (take(v3[i])) keep.add(i);
  }
  final extra = [
    for (final p in optional)
      if (take(p)) p,
  ];
  return (
    [
      for (var i = 0; i < v3.length; i++)
        if (keep.contains(i)) v3[i],
    ],
    [...mandatory, ...first, ...extra],
  );
}

/// Lo retenido con los cupos de cada clase (M3): los reintentables nunca
/// salen por culpa de los falsos o de los revocados. De cada clase sale el
/// más antiguo.
List<RetainedCommon> capRetained(List<RetainedCommon> retained) {
  List<RetainedCommon> newest(bool Function(RetainedCommon) of, int max) {
    final list = retained.where(of).toList()
      ..sort((a, b) => a.seenAtMillis.compareTo(b.seenAtMillis));
    return list.length > max ? list.sublist(list.length - max) : list;
  }

  return [
    ...newest((r) => !r.fromFile && r.retryable, kMaxRetainedWaiting),
    ...newest(
      (r) => !r.fromFile && r.reason == RemoteCommonStatus.revokedWriter,
      kMaxRetainedRevoked,
    ),
    ...newest(
      (r) => !r.fromFile && r.reason == RemoteCommonStatus.forged,
      kMaxRetainedForged,
    ),
    // Los de ficheros, aparte (B6): nunca ocupan el sitio de los del
    // servidor.
    ...newest((r) => r.fromFile, kMaxRetainedFiles),
  ];
}

/// Lo que ha encontrado [CommonV2Cycle.receive].
class CommonReceived {
  /// Crea el resultado.
  const CommonReceived({
    required this.status,
    this.doc,
    this.kid,
    this.writer,
    this.keyringFull = false,
    this.block,
  });

  /// Qué pasó con el común remoto.
  final RemoteCommonStatus status;

  /// El documento remoto abierto, si se pudo.
  final FamilyDoc? doc;

  /// `kid` de la cabecera del común remoto (sin autenticar), si es formato 2.
  final String? kid;

  /// Escritor de la cabecera (sin autenticar), si es formato 2.
  final String? writer;

  /// Algún paquete no cupo en el llavero (tope duro).
  final bool keyringFull;

  /// El bloqueo, si el común remoto no se puede abrir.
  final CommonBlock? block;

  /// Si se pudo leer.
  bool get readable => commonReadable(status);
}

/// Lo que ha encontrado [CommonV2Cycle.receiveFile] en el común de un
/// fichero `.regalos` de intercambio (B6).
class FileCommonReceived {
  /// Crea el resultado.
  const FileCommonReceived({
    required this.status,
    this.doc,
    this.writer,
    this.retained = false,
  });

  /// Qué pasó: [RemoteCommonStatus.opened] si se abrió; si no, por qué no.
  final RemoteCommonStatus status;

  /// El documento abierto (sin fusionar), si se pudo.
  final FamilyDoc? doc;

  /// El escritor, si su firma está comprobada.
  final String? writer;

  /// Si el fichero se ha guardado aparte para volver a probarlo en cada
  /// sincronización (falta su clave o su escritor está por confirmar).
  final bool retained;
}

/// Lo que va en un fichero `.regalos` de intercambio (B6): el común firmado,
/// los paquetes v4 de su candidata para el resto de su audiencia y los
/// resúmenes de las fichas que hacen falta para abrirlos.
class FileCommonSealed {
  /// Crea el resultado.
  const FileCommonSealed({
    required this.common,
    required this.packages,
    required this.recordDigests,
  });

  /// El común firmado (formato 2).
  final Uint8List common;

  /// Los paquetes v4 de la candidata con la que se selló.
  final List<Map<String, Object?>> packages;

  /// Fichas del escritor, del creador y de la audiencia de la candidata.
  final Set<String> recordDigests;
}

/// Ejecuta una tarea fuera del hilo de la interfaz (`runTask`).
typedef CommonTaskRunner = Future<T> Function<T>(FutureOr<T> Function() task);

/// Lo que ha visto [inspectFileCommon], sin guardar nada.
class FileInspection {
  /// Crea el resultado.
  const FileInspection({
    required this.status,
    this.kid,
    this.writer,
    this.verified = false,
    this.doc,
    this.candidate,
    this.from,
    this.fromRecord,
  });

  /// Qué pasó con el común.
  final RemoteCommonStatus status;

  /// `kid` de la cabecera (sin autenticar).
  final String? kid;

  /// Escritor de la cabecera (sin autenticar).
  final String? writer;

  /// Si la firma del escritor está comprobada.
  final bool verified;

  /// El documento, si se abrió.
  final FamilyDoc? doc;

  /// La candidata que trajo un paquete del fichero, con su emisor.
  final FamilyCandidate? candidate;

  /// Emisor del paquete de [candidate].
  final String? from;

  /// Ficha del emisor del paquete de [candidate].
  final String? fromRecord;
}

/// Los paquetes v4 de [packages] para [me] y, si se da, de la candidata
/// [kid] (B5 de la revisión de seguridad: los demás ni se abren).
List<Map<String, Object?>> filePackagesFor(
  List<Map<String, Object?>> packages, {
  required String? kid,
  required String me,
}) => [
  for (final p in packages)
    if (FamilyKeyBundle.isV4(p) &&
        p['to'] == me &&
        (kid == null || p['kid'] == kid))
      p,
];

/// Las fichas de un fichero que valen para resolver resúmenes en memoria:
/// bien firmadas, de esta lista y de un id que [view] ya tiene enlazado con
/// esa misma clave de firma y del mismo tipo que ese id tiene aquí (en la
/// vista o, si no está en ella, en las fichas de [registry] con esa clave).
/// Nunca se guardan (revisión de seguridad, A1-A3).
Future<List<DeviceRecord>> linkedFileRecords(
  List<Map<String, Object?>> records,
  RegistryView view,
  DeviceRegistry registry,
) async {
  DeviceKind? kindOf(String id, List<int> key) {
    final known = view.device(id)?.kind;
    if (known != null) return known;
    final kinds = {
      for (final r in registry.records)
        if (r.deviceId == id && constantTimeEquals(r.keys.signing, key)) r.kind,
    };
    return kinds.length == 1 ? kinds.single : null;
  }

  final out = <DeviceRecord>[];
  for (final raw in records.take(kMaxExchangeRecords)) {
    final DeviceRecord record;
    try {
      record = DeviceRecord.fromJson(raw);
    } on RegistryException {
      continue;
    }
    final linked = view.linkedSigningKey(record.deviceId);
    if (record.listId != view.listId ||
        linked == null ||
        !constantTimeEquals(linked, record.keys.signing) ||
        kindOf(record.deviceId, linked) != record.kind ||
        !await record.verify()) {
      continue;
    }
    out.add(record);
  }
  return out;
}

/// La parte pura (sin guardar nada, para `runTask`) de abrir el común de un
/// fichero de intercambio con la vista **local** [view] de [registry] (B6,
/// tras la revisión de seguridad):
///
/// 1. Una sola verificación de la firma del común antes de nada. Un
///    revocado de verdad es [RemoteCommonStatus.revokedWriter] (si su firma
///    vale con su clave enlazada; si no, falso). Un escritor que no es
///    activo en este móvil es [RemoteCommonStatus.unknownWriter], con la
///    firma comprobada si se le conoce ([knownWriterKey]). Los miembros
///    nuevos y las revocaciones solo llegan por el servidor o al emparejar.
/// 2. Solo con un escritor activo y su firma válida se abren los paquetes de
///    esa candidata para este móvil. Las [records] del fichero sirven, en
///    memoria, para encontrar una ficha más nueva del escritor, de la
///    audiencia o del creador, solo si son de un id ya enlazado con la misma
///    clave ([linkedFileRecords]).
/// 3. Después se abre el común.
Future<FileInspection> inspectFileCommon({
  required Uint8List common,
  required List<Map<String, Object?>> packages,
  required List<Map<String, Object?>> records,
  required DeviceRegistry registry,
  required RegistryView view,
  required FamilyKeyring keyring,
  required DeviceKeys keys,
  required String syncId,
}) async {
  const forged = FileInspection(status: RemoteCommonStatus.forged);
  if (!isFamilyEnvelope(common)) return forged;
  final FamilyEnvelopeHeader h;
  try {
    h = peekFamilyEnvelope(common);
  } on EnvelopeException {
    return forged;
  }
  Future<bool> verifies(FamilyWriterResolver resolve) async {
    try {
      await verifyFamilyEnvelope(
        common,
        expectedListId: view.listId,
        expectedSyncId: syncId,
        resolveWriter: resolve,
      );
      return true;
    } on EnvelopeException {
      return false;
    }
  }

  if (reallyRevoked(view, h.writer)) {
    final ok = await verifies((w, _) => view.linkedSigningKey(w));
    return FileInspection(
      status: ok ? RemoteCommonStatus.revokedWriter : RemoteCommonStatus.forged,
      kid: h.kid,
      writer: h.writer,
      verified: ok,
    );
  }
  final member = view.member(h.writer);
  if (member == null) {
    final ok = await verifies((w, r) => knownWriterKey(view, registry, w, r));
    return FileInspection(
      status: RemoteCommonStatus.unknownWriter,
      kid: h.kid,
      writer: h.writer,
      verified: ok,
    );
  }
  final extra = await linkedFileRecords(records, view, registry);
  final byDigest = {for (final r in extra) r.digest: r};
  List<int>? resolve(String writer, String writerRecord) {
    if (writer != member.deviceId) return null;
    if (writerRecord == member.recordDigest) return member.signingKey;
    final record =
        registry.recordByDigest(writerRecord) ?? byDigest[writerRecord];
    if (record != null &&
        record.deviceId == writer &&
        record.kind == member.kind &&
        constantTimeEquals(record.keys.signing, member.signingKey)) {
      return member.signingKey;
    }
    return null;
  }

  if (!await verifies(resolve)) return forged;

  var ring = keyring;
  FamilyCandidate? got;
  String? from;
  String? fromRecord;
  if (keyring.entry(h.kid) == null) {
    var reg = registry;
    for (final r in extra) {
      if (reg.recordByDigest(r.digest) != null) continue;
      try {
        reg = await reg.withRecord(r);
      } on RegistryException {
        continue;
      }
    }
    for (final raw in filePackagesFor(packages, kid: h.kid, me: view.me)) {
      try {
        final bundle = FamilyKeyBundle.fromJson(raw);
        got = await bundle.open(
          mine: keys,
          view: view,
          registry: reg,
          syncId: syncId,
        );
        from = bundle.fromDevice;
        fromRecord = bundle.senderRecord;
        break;
      } on KeyBundleException {
        continue;
      } on FamilyKeyException {
        continue;
      }
    }
    if (got != null) {
      ring = FamilyKeyring.empty.withReceivedCandidate(
        got,
        from: from!,
        fromRecord: fromRecord!,
        sealable: (_) => false,
        wanted: {got.kid},
      );
    }
  }
  try {
    final opened = await openFamilyEnvelope(
      common,
      expectedListId: view.listId,
      expectedSyncId: syncId,
      resolveWriter: resolve,
      keyring: ring,
    );
    return FileInspection(
      status: RemoteCommonStatus.opened,
      kid: h.kid,
      writer: h.writer,
      verified: true,
      doc: opened.doc,
      candidate: got,
      from: from,
      fromRecord: fromRecord,
    );
  } on EnvelopeMissingKeyException {
    return FileInspection(
      status: RemoteCommonStatus.missingKey,
      kid: h.kid,
      writer: h.writer,
      verified: true,
    );
  } on EnvelopeException {
    return FileInspection(
      status: RemoteCommonStatus.unreadable,
      kid: h.kid,
      writer: h.writer,
      verified: true,
    );
  }
}

/// Lo que va en el `PUT` del común.
class CommonPlan {
  /// Crea el plan.
  const CommonPlan({
    required this.common,
    required this.mandatory,
    required this.preferred,
    required this.optional,
    required this.heldRequired,
    required this.heldPreferred,
    required this.heldOptional,
    required this.serverCommon,
    required this.resealed,
    required this.replaced,
    required this.uploadedKid,
    required this.remoteKid,
    required this.sealingKid,
    required this.keyringFull,
  });

  /// Los bytes del común que se suben.
  final Uint8List common;

  /// Los paquetes v4 que tienen que ir sí o sí: el reparto propio del común
  /// que se sube (y de la candidata de este móvil).
  final List<Map<String, Object?>> mandatory;

  /// Los v4 ajenos útiles de esas candidatas: van primero si caben.
  final List<Map<String, Object?>> preferred;

  /// Los paquetes v4 ajenos útiles de otras candidatas: van si caben.
  final List<Map<String, Object?>> optional;

  /// [mandatory], [preferred] y [optional] con la contrapresión ([held]).
  final List<Map<String, Object?>> heldRequired;

  /// Ver [heldRequired].
  final List<Map<String, Object?>> heldPreferred;

  /// Ver [heldRequired].
  final List<Map<String, Object?>> heldOptional;

  /// El común del servidor.
  final Uint8List serverCommon;

  /// Si se ha vuelto a sellar el común.
  final bool resealed;

  /// Si se sustituye un común remoto que no se pudo abrir.
  final bool replaced;

  /// `kid` del común que se sube (null si no es formato 2).
  final String? uploadedKid;

  /// `kid` del común remoto.
  final String? remoteKid;

  /// La candidata con la que sella este móvil, si tiene.
  final String? sealingKid;

  /// El llavero llegó a su tope duro.
  final bool keyringFull;

  /// El plan sin sustituir el común (contrapresión: no cabe el reparto).
  CommonPlan held() => CommonPlan(
    common: serverCommon,
    mandatory: heldRequired,
    preferred: heldPreferred,
    optional: heldOptional,
    heldRequired: heldRequired,
    heldPreferred: heldPreferred,
    heldOptional: heldOptional,
    serverCommon: serverCommon,
    resealed: false,
    replaced: false,
    uploadedKid: remoteKid,
    remoteKid: remoteKid,
    sealingKid: sealingKid,
    keyringFull: keyringFull,
  );
}

/// La parte del ciclo v2 que trata el común sellado con candidatas.
class CommonV2Cycle {
  /// Crea el ciclo sobre [local].
  CommonV2Cycle(this.local);

  /// Lo local.
  final SyncV2Local local;

  String get _syncId => local.identity.syncId;
  String get _listId => local.identity.listId;

  /// El estado guardado. Si falta pero ya se guardó alguna vez (la marca del
  /// almacén seguro), lanza [CommonStateException]: perder las claves no se
  /// arregla empezando de cero.
  Future<CommonKeyState> _read() async {
    final ks = await local.readCommonKeys();
    if (ks != null) return ks;
    if (await local.commonKeysMarked()) {
      throw const CommonStateException('falta el estado de la clave común');
    }
    return CommonKeyState();
  }

  Future<void> _save(CommonKeyState ks) async {
    await local.saveCommonKeys(ks);
    if (!await local.commonKeysMarked()) await local.markCommonKeys();
  }

  /// Pasos 5 y 6: abre y guarda los paquetes v4 dirigidos a este móvil
  /// (pasando en `wanted` los `kid` del común remoto, de los retenidos, del
  /// último común y de la intención de reparto), poda las de revocados,
  /// verifica, abre y fusiona el común remoto, vuelve a intentar los
  /// retenidos y apunta el bloqueo. Lo deja todo guardado.
  ///
  /// [view] es la vista de [registry] ya fusionado; [round] identifica la
  /// vuelta de `sync()` (los reintentos tras `412` comparten la misma).
  /// Lanza [EnvelopeFormatException] con un documento de otro protocolo o
  /// un sobre de un formato posterior (hay que actualizar la app), sin
  /// retenerlo ni sustituirlo.
  ///
  /// Un común en formato 1 solo se abre (con [legacyKey]) en la vuelta que
  /// activa el corte (B4) y mientras este móvil no haya abierto ni publicado
  /// un formato 2; en cualquier otro caso es falso: nunca se fusiona.
  Future<CommonReceived> receive({
    required Uint8List remote,
    required List<Map<String, Object?>> packages,
    required DeviceRegistry registry,
    required RegistryView view,
    required String round,
    required int nowMillis,
    FamilyKey? legacyKey,
  }) async {
    if (_laterFormat(remote)) {
      throw const EnvelopeFormatException(
        'el común es de una versión posterior: hay que actualizar la app',
      );
    }
    var ks = await _read();
    var retained = await local.readRetainedCommons();

    FamilyEnvelopeHeader? peeked;
    final format2 = remote.isNotEmpty && isFamilyEnvelope(remote);
    if (format2) {
      try {
        peeked = peekFamilyEnvelope(remote);
      } on EnvelopeException {
        peeked = null;
      }
    }
    final wanted = <String>{
      ?peeked?.kid,
      for (final r in retained)
        if (r.hasBytes) ?r.kid,
      ?ks.lastKid,
      for (final p in ks.outbox) ?familyPackageKid(p),
    };

    // 5. Los paquetes v4 para este móvil.
    var (keyring, keyringFull) = await _receivePackages(
      ks.keyring,
      packages,
      registry: registry,
      view: view,
      wanted: wanted,
    );
    ks = ks.copyWith(keyring: keyring);
    await _save(ks);

    // 6. El común remoto.
    final resolve = commonWriterResolver(view, registry);
    RemoteCommonStatus status;
    var writerVerified = false;
    FamilyDoc? doc;
    String? fromNode;
    if (remote.isEmpty) {
      status = RemoteCommonStatus.empty;
    } else if (!format2) {
      // Formato 1 con la clave de la familia de siempre: solo en la vuelta
      // que activa el corte (B4, [legacyKey]) y mientras este móvil no haya
      // pasado al formato 2 (M2). Fuera de eso, quien conserve la clave
      // vieja (un revocado) no puede inyectar nada por aquí.
      if (legacyKey == null || ks.lastKid != null) {
        status = RemoteCommonStatus.forged;
      } else {
        try {
          final opened = await open(
            remote,
            key: legacyKey,
            expectedListId: _listId,
          );
          doc = FamilyDoc.fromJson(opened.doc);
          fromNode = opened.header.fromNode;
          status = RemoteCommonStatus.legacy;
        } on EnvelopeException {
          status = RemoteCommonStatus.forged;
        } on FormatException {
          status = RemoteCommonStatus.forged;
        }
      }
    } else if (peeked == null) {
      status = RemoteCommonStatus.forged;
    } else if (reallyRevoked(view, peeked.writer)) {
      status = await _revokedOrForged(remote, view);
    } else {
      (status, doc, writerVerified) = await _open(
        remote,
        resolve,
        keyring,
        view,
        registry,
      );
      fromNode = peeked.writer == view.me ? local.node : peeked.writer;
    }
    if (doc != null) {
      // Una versión desconocida no entra nunca (como el formato 1).
      if (syncProtocolOf(doc) == null) {
        throw const EnvelopeFormatException('documento de otro protocolo');
      }
      await local.mergeCommon(doc, fromNode: fromNode!);
    }

    // Lo que no se fusiona se guarda aparte; lo retenido se vuelve a probar.
    final currentHash = remote.isEmpty ? null : sha256Hex(remote);
    final fresh = <String, Uint8List>{};
    if (!commonReadable(status) &&
        !retained.any((r) => r.hash == currentHash)) {
      final keepBytes = status != RemoteCommonStatus.forged;
      if (keepBytes) fresh[currentHash!] = remote;
      retained = [
        ...retained,
        RetainedCommon(
          hash: currentHash!,
          reason: status,
          seenAtMillis: nowMillis,
          hasBytes: keepBytes,
          kid: peeked?.kid,
          writer: peeked?.writer,
        ),
      ];
    }
    final kept = <RetainedCommon>[];
    for (final r in retained) {
      if (r.hash == currentHash) {
        // El remoto de ahora: si se ha podido abrir ya está fusionado.
        if (!commonReadable(status)) {
          kept.add(r.reason == status ? r : r.withReason(status));
        }
        continue;
      }
      if (!r.retryable || !r.hasBytes) {
        kept.add(r);
        continue;
      }
      final stored = fresh[r.hash] ?? await local.readRetainedBytes(r.hash);
      if (stored == null) {
        throw const CommonStateException('falta un común retenido');
      }
      // Un retenido de fichero (B6) guarda el fichero entero: su común y los
      // paquetes que trae, que se abren ahora con el registro de esta vuelta
      // (B1 de la revisión de seguridad).
      var bytes = stored;
      if (r.fromFile && isExchangeFile(stored)) {
        try {
          final file = ExchangeFile.parse(stored);
          bytes = file.common;
          (keyring, _) = await _receivePackages(
            keyring,
            filePackagesFor(file.packages, kid: r.kid, me: view.me),
            registry: registry,
            view: view,
            wanted: wanted,
          );
        } on EnvelopeException {
          kept.add(r.withReason(RemoteCommonStatus.forged));
          continue;
        }
      }
      if (r.writer != null && reallyRevoked(view, r.writer!)) {
        kept.add(r.withReason(await _revokedOrForged(bytes, view)));
        continue;
      }
      final (again, opened, _) = await _open(
        bytes,
        resolve,
        keyring,
        view,
        registry,
      );
      if (opened != null) {
        if (syncProtocolOf(opened) != null) {
          try {
            await local.mergeCommon(
              opened,
              fromNode: r.writer == view.me ? local.node : r.writer ?? '',
            );
          } on ImportClockDriftException {
            // El reloj de quien lo escribió va muy adelantado: se conserva y
            // se vuelve a probar en otra vuelta; los demás siguen (B3 de
            // la revisión de seguridad).
            kept.add(r);
            continue;
          }
          continue;
        }
        // Se abre pero es de otro protocolo (una versión posterior): se
        // conserva tal cual, nunca se descarta en silencio.
        kept.add(r);
        continue;
      }
      kept.add(again == r.reason ? r : r.withReason(again));
    }
    final before = await local.readRetainedCommons();
    retained = capRetained(kept);

    // El bloqueo, atado al común (su hash) y contado por vuelta de `sync()`.
    CommonBlock? block;
    if (commonWaits(status)) {
      final previous = ks.blocked;
      final same = previous != null && previous.hash == currentHash;
      block = CommonBlock(
        hash: currentHash!,
        rounds: !same
            ? 1
            : previous.lastRound == round
            ? previous.rounds
            : previous.rounds + 1,
        lastRound: round,
        // Basura demostrable: no abre con la candidata exacta, o nadie con
        // ese id (con presencia enlazada) firma el sobre. Lo demás espera a
        // una persona, y solo entonces se nombra al escritor (N1 de la revisión de seguridad).
        autoExit:
            status == RemoteCommonStatus.unreadable ||
            (status == RemoteCommonStatus.unknownWriter && !writerVerified),
        writer: writerVerified ? peeked?.writer : null,
      );
    }
    final lastKid = status == RemoteCommonStatus.opened
        ? peeked!.kid
        : ks.lastKid;

    // Primero los bytes, después el índice, después las referencias que lo
    // apuntan y por último se borra lo que sale: un cierre en medio deja
    // como mucho bytes de más, nunca una referencia sin su retenido.
    for (final r in retained) {
      final bytes = fresh[r.hash];
      if (bytes != null && r.hasBytes) {
        await local.saveRetainedBytes(r.hash, bytes);
      }
    }
    final changed =
        jsonEncode([for (final r in before) r.toJson()]) !=
        jsonEncode([for (final r in retained) r.toJson()]);
    if (changed) await local.saveRetainedCommons(retained);
    ks = CommonKeyState(
      keyring: withCommonReferences(
        keyring,
        lastKid: lastKid,
        outbox: ks.outbox,
        retained: retained,
      ),
      outbox: ks.outbox,
      revision:
          status == RemoteCommonStatus.opened &&
              peeked?.writer == view.me &&
              peeked!.revision > ks.revision
          ? peeked.revision
          : ks.revision,
      lastKid: lastKid,
      blocked: block,
    );
    await _save(ks);
    final stays = {
      for (final r in retained)
        if (r.hasBytes) r.hash,
    };
    for (final r in before) {
      if (r.hasBytes && !stays.contains(r.hash)) {
        await local.deleteRetainedBytes(r.hash);
      }
    }
    return CommonReceived(
      status: status,
      doc: doc,
      kid: peeked?.kid,
      writer: peeked?.writer,
      keyringFull: keyringFull,
      block: block,
    );
  }

  /// Abre los paquetes v4 de [packages] dirigidos a este móvil con
  /// `FamilyKeyBundle.open` (que verifica emisor, audiencia y creador) y los
  /// guarda en [keyring] como recibidos; después poda los de revocados y
  /// recorta, respetando [wanted]. Devuelve el llavero y si algún paquete no
  /// cupo (tope duro). No guarda nada.
  Future<(FamilyKeyring, bool)> _receivePackages(
    FamilyKeyring keyring,
    List<Map<String, Object?>> packages, {
    required DeviceRegistry registry,
    required RegistryView view,
    required Set<String> wanted,
  }) async {
    var keyringFull = false;
    bool sealable(FamilyCandidate c) => c.sealableIn(view, syncId: _syncId);
    for (final raw in packages) {
      if (!FamilyKeyBundle.isV4(raw) || raw['to'] != view.me) continue;
      final kid = raw['kid'];
      final known = kid is String ? keyring.entry(kid) : null;
      if (known != null &&
          (known.own ||
              known.senders.length >= kMaxCandidateSenders ||
              known.senders.any((s) => s.deviceId == raw['from']))) {
        continue;
      }
      try {
        final bundle = FamilyKeyBundle.fromJson(raw);
        final candidate = await bundle.open(
          mine: local.keys,
          view: view,
          registry: registry,
          syncId: _syncId,
        );
        keyring = keyring.withReceivedCandidate(
          candidate,
          from: bundle.fromDevice,
          fromRecord: bundle.senderRecord,
          sealable: sealable,
          wanted: wanted,
        );
      } on FamilyKeyringFullException {
        // Puede caber otra (una buscada, o una que ya estaba).
        keyringFull = true;
        continue;
      } on KeyBundleException {
        continue;
      } on FamilyKeyException {
        continue;
      }
    }
    keyring = trimCommonKeyring(
      keyring.pruneRevoked(view, wanted: wanted),
      view,
      syncId: _syncId,
      wanted: wanted,
    );
    return (keyring, keyringFull);
  }

  /// Importa [familyKey] (la clave de la familia de siempre) como candidata
  /// propia **histórica** del llavero común (B4): abre lo que se haya sellado
  /// con ella, nunca sella, y lleva la referencia [kLegacyRef] para que no
  /// se recorte. Idempotente. Devuelve si está en el llavero (false si no se
  /// puede crear o no cabe).
  Future<bool> importLegacyKey(RegistryView view, FamilyKey familyKey) async {
    final ks = await _read();
    // Idempotente: si ya hay una (de otra vuelta, con otra vista), vale esa.
    if (ks.keyring.entries.any((e) => e.references.contains(kLegacyRef))) {
      return true;
    }
    final FamilyCandidate legacy;
    try {
      legacy = await legacyFamilyCandidate(
        view,
        keys: local.keys,
        syncId: _syncId,
        familyKey: familyKey,
      );
    } on FamilyKeyException {
      return false;
    }
    final known = ks.keyring.entry(legacy.kid);
    if (known != null &&
        known.own &&
        known.historical &&
        known.references.contains(kLegacyRef)) {
      return true;
    }
    try {
      final keyring = ks.keyring
          .withOwnCandidate(legacy, historical: true)
          .withReference(legacy.kid, kLegacyRef);
      await _save(ks.copyWith(keyring: keyring));
      return true;
    } on FamilyKeyringFullException {
      return false;
    }
  }

  /// B6: abre el común de [file] (los bytes enteros, [bytes]) con la vista
  /// **local** [view] de [registry]: el registro del fichero nunca se guarda
  /// ni decide nada (revisión de seguridad, A1-A3). Todo lo criptográfico va con
  /// [run] (por defecto `runTask`, fuera del hilo de la interfaz): ver
  /// [inspectFileCommon].
  ///
  /// No fusiona: devuelve el documento a quien llama. No toca el bloqueo ni
  /// `lastKid`. Solo guarda la candidata que trajo un paquete del fichero si
  /// el común se abrió con ella. Si falta la clave, o el escritor tiene la
  /// firma comprobada pero no es activo en este móvil, guarda el **fichero
  /// entero** aparte (retenido de fichero, con sus paquetes) y cada vuelta de
  /// [receive] lo vuelve a probar: nunca se toma por un documento vacío. Lo
  /// de un revocado, lo falso y la basura no se guardan.
  ///
  /// Lanza [EnvelopeFormatException] con un formato posterior del común o un
  /// documento de otro protocolo.
  Future<FileCommonReceived> receiveFile({
    required Uint8List bytes,
    required ExchangeFile file,
    required DeviceRegistry registry,
    required RegistryView view,
    required int nowMillis,
    CommonTaskRunner run = runTask,
  }) async {
    if (_laterFormat(file.common)) {
      throw const EnvelopeFormatException(
        'el común es de una versión posterior: hay que actualizar la app',
      );
    }
    var ks = await _read();
    final got = await _inspectOff(
      run,
      file,
      registry,
      view,
      ks.keyring,
      local.keys,
      _syncId,
    );
    final writer = got.verified ? got.writer : null;
    if (got.doc != null) {
      if (syncProtocolOf(got.doc!) == null) {
        throw const EnvelopeFormatException('documento de otro protocolo');
      }
      final candidate = got.candidate;
      if (candidate != null) {
        final retained = await local.readRetainedCommons();
        final wanted = <String>{
          candidate.kid,
          for (final r in retained)
            if (r.hasBytes) ?r.kid,
          ?ks.lastKid,
          for (final p in ks.outbox) ?familyPackageKid(p),
        };
        var keyring = ks.keyring;
        try {
          keyring = keyring.withReceivedCandidate(
            candidate,
            from: got.from!,
            fromRecord: got.fromRecord!,
            sealable: (c) => c.sealableIn(view, syncId: _syncId),
            wanted: wanted,
          );
        } on FamilyKeyringFullException {
          // Ya se ha abierto: la clave no hace falta para nada más.
        }
        keyring = trimCommonKeyring(
          keyring.pruneRevoked(view, wanted: wanted),
          view,
          syncId: _syncId,
          wanted: wanted,
        );
        ks = ks.copyWith(keyring: keyring);
        await _save(ks);
      }
      return FileCommonReceived(
        status: got.status,
        doc: got.doc,
        writer: writer,
      );
    }
    final keep =
        got.status == RemoteCommonStatus.missingKey ||
        (got.status == RemoteCommonStatus.unknownWriter && got.verified);
    if (!keep) return FileCommonReceived(status: got.status, writer: writer);

    final retained = await local.readRetainedCommons();
    final hash = sha256Hex(file.common);
    if (retained.any((r) => r.hash == hash)) {
      // Ya estaba guardado. Si este trae un paquete para este móvil y el
      // guardado no, se quedan estos bytes: así el reintento tiene la clave.
      if (filePackagesFor(
        file.packages,
        kid: got.kid,
        me: view.me,
      ).isNotEmpty) {
        final stored = await local.readRetainedBytes(hash);
        var storedHas = false;
        if (stored != null && isExchangeFile(stored)) {
          try {
            storedHas = filePackagesFor(
              ExchangeFile.parse(stored).packages,
              kid: got.kid,
              me: view.me,
            ).isNotEmpty;
          } on EnvelopeException {
            storedHas = false;
          }
        }
        if (!storedHas) await local.saveRetainedBytes(hash, bytes);
      }
      return FileCommonReceived(
        status: got.status,
        writer: writer,
        retained: true,
      );
    }
    final next = capRetained([
      ...retained,
      RetainedCommon(
        hash: hash,
        reason: got.status,
        seenAtMillis: nowMillis,
        hasBytes: true,
        kid: got.kid,
        writer: got.writer,
        fromFile: true,
      ),
    ]);
    // Como en [receive]: bytes, índice, referencias y, al final, el borrado
    // de lo que sale (el propio, si no cupo, ni se escribe).
    final kept = next.any((r) => r.hash == hash);
    if (kept) await local.saveRetainedBytes(hash, bytes);
    await local.saveRetainedCommons(next);
    await _save(
      ks.copyWith(
        keyring: withCommonReferences(
          ks.keyring,
          lastKid: ks.lastKid,
          outbox: ks.outbox,
          retained: next,
        ),
      ),
    );
    final stays = {
      for (final r in next)
        if (r.hasBytes) r.hash,
    };
    for (final r in retained) {
      if (r.hasBytes && !stays.contains(r.hash)) {
        await local.deleteRetainedBytes(r.hash);
      }
    }
    return FileCommonReceived(
      status: got.status,
      writer: writer,
      retained: kept,
    );
  }

  // Estático: el cierre que va a otro aislado no lleva `this` (ni `local`).
  static Future<FileInspection> _inspectOff(
    CommonTaskRunner run,
    ExchangeFile file,
    DeviceRegistry registry,
    RegistryView view,
    FamilyKeyring keyring,
    DeviceKeys keys,
    String syncId,
  ) {
    final common = file.common;
    final packages = file.packages;
    final records = file.records;
    return run(
      () => inspectFileCommon(
        common: common,
        packages: packages,
        records: records,
        registry: registry,
        view: view,
        keyring: keyring,
        keys: keys,
        syncId: syncId,
      ),
    );
  }

  /// B6: sella [common] para un fichero `.regalos` de intercambio con la
  /// candidata sellable de `kid` menor (o una nueva, guardada **antes** de
  /// sellar, como en [prepare]) y prepara sus paquetes v4 para el resto de
  /// su audiencia que sigue activa con su ficha. Ninguna clave va en claro
  /// ni con la `familyKey`. El sellado va con [run] (fuera del hilo de la
  /// interfaz).
  ///
  /// Solo un móvil activo y aprobado (el que puede repartir); si no, lanza
  /// [ExchangeNotAllowedException].
  Future<FileCommonSealed> sealForFile({
    required FamilyDoc common,
    required RegistryView view,
    CommonTaskRunner run = runTask,
  }) async {
    if (view.self.kind != DeviceKind.mobile ||
        view.revokedByOthers ||
        !view.selfApproved) {
      throw const ExchangeNotAllowedException(
        'este móvil aún no puede repartir la clave común',
      );
    }
    final ks = await _read();
    var keyring = ks.keyring;
    var sealing = keyring.forSealingIn(view, syncId: _syncId);
    if (sealing == null) {
      final fresh = await FamilyCandidate.generate(
        view,
        keys: local.keys,
        syncId: _syncId,
      );
      try {
        keyring = keyring.withOwnCandidate(fresh);
      } on FamilyKeyringFullException {
        throw const ExchangeNotAllowedException('el llavero común está lleno');
      }
      sealing = fresh;
    }
    final revision = _nextCommonRevision(ks.revision);
    // La candidata y la revisión, guardadas antes de sellar.
    await _save(ks.copyWith(keyring: keyring, revision: revision));
    final (bytes, packages) = await _sealOff(
      run,
      common,
      sealing,
      view,
      revision,
      local.keys,
      _syncId,
    );
    return FileCommonSealed(
      common: bytes,
      packages: packages,
      recordDigests: {
        view.self.recordDigest,
        sealing.creatorRecord,
        for (final m in sealing.audience) m.recordDigest,
      },
    );
  }

  // Estático: el cierre que va a otro aislado no lleva `this` (ni `local`).
  static Future<(Uint8List, List<Map<String, Object?>>)> _sealOff(
    CommonTaskRunner run,
    FamilyDoc common,
    FamilyCandidate candidate,
    RegistryView view,
    int revision,
    DeviceKeys keys,
    String syncId,
  ) => run(() async {
    final bytes = await sealFamilyEnvelope(
      doc: common,
      candidate: candidate,
      writer: view.self,
      revision: revision,
      signer: keys,
    );
    final bundles = await FamilyKeyBundle.sealForAudience(
      sender: keys,
      view: view,
      syncId: syncId,
      candidate: candidate,
    );
    return (bytes, [for (final b in bundles) b.toJson()]);
  });

  /// Si [bytes] dicen ser un sobre "RG" de un formato posterior al 2 (M4).
  static bool _laterFormat(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x47 &&
      bytes[2] > kFamilyEnvelopeVersion;

  /// Un sobre que dice ser de un revocado: solo lo es si su firma vale con
  /// la clave enlazada de ese id (B2 de la revisión de seguridad); si no, es falso.
  Future<RemoteCommonStatus> _revokedOrForged(
    Uint8List bytes,
    RegistryView view,
  ) async {
    try {
      await verifyFamilyEnvelope(
        bytes,
        expectedListId: _listId,
        expectedSyncId: _syncId,
        resolveWriter: (writer, _) => view.linkedSigningKey(writer),
      );
      return RemoteCommonStatus.revokedWriter;
    } on EnvelopeException {
      return RemoteCommonStatus.forged;
    }
  }

  /// Abre [bytes]. Si el escritor no es un miembro activo, antes de esperar
  /// se comprueba la firma con la clave con la que este móvil conoce ese id
  /// ([knownWriterKey], N1 de la revisión de seguridad): si no vale, es [RemoteCommonStatus.forged]
  /// (cualquier credencial, o el servidor, podría haber puesto un id ajeno
  /// en la cabecera). El tercer valor dice si el escritor de un
  /// `unknownWriter` está autenticado (entonces se espera sin plazo).
  Future<(RemoteCommonStatus, FamilyDoc?, bool)> _open(
    Uint8List bytes,
    FamilyWriterResolver resolve,
    FamilyKeyring keyring,
    RegistryView view,
    DeviceRegistry registry,
  ) async {
    try {
      await verifyFamilyEnvelope(
        bytes,
        expectedListId: _listId,
        expectedSyncId: _syncId,
        resolveWriter: resolve,
      );
    } on EnvelopeUnknownWriterException {
      try {
        await verifyFamilyEnvelope(
          bytes,
          expectedListId: _listId,
          expectedSyncId: _syncId,
          resolveWriter: (writer, record) =>
              knownWriterKey(view, registry, writer, record),
        );
        return (RemoteCommonStatus.unknownWriter, null, true);
      } on EnvelopeUnknownWriterException {
        // Ningún dispositivo con ese id que se pueda autenticar.
        return (RemoteCommonStatus.unknownWriter, null, false);
      } on EnvelopeException {
        return (RemoteCommonStatus.forged, null, false);
      }
    } on EnvelopeException {
      // Firma que no vale, otra lista o bytes rotos: nadie lo ha escrito.
      return (RemoteCommonStatus.forged, null, false);
    }
    try {
      final opened = await openFamilyEnvelope(
        bytes,
        expectedListId: _listId,
        expectedSyncId: _syncId,
        resolveWriter: resolve,
        keyring: keyring,
      );
      return (RemoteCommonStatus.opened, opened.doc, true);
    } on EnvelopeMissingKeyException {
      return (RemoteCommonStatus.missingKey, null, true);
    } on EnvelopeException {
      return (RemoteCommonStatus.unreadable, null, true);
    }
  }

  /// Pasos 8 y 9: elige la candidata (`kid` menor de las sellables) o crea
  /// una si no hay, reparte la candidata con la que se sube el común a toda
  /// su audiencia activa que aún no tenga un paquete propio (también a los
  /// desconectados), guarda candidata, reparto y revisión **antes** de
  /// sellar y sella [common] si toca.
  ///
  /// Quien no ha podido abrir el común remoto no lo sustituye: sube los
  /// mismos bytes. Salvo si es falso o de un revocado, o si es basura
  /// demostrable que lleva [kCommonUnreadableRounds] vueltas. Quien no puede
  /// repartir (pendiente, web) nunca sella (B6 de la revisión de seguridad).
  ///
  /// Los paquetes v4 ajenos del servidor solo se vuelven a subir si sirven
  /// ([usefulFamilyPackage]) y, de cada emisor, como mucho
  /// [kMaxFamilyPackagesPerSender] (A1).
  Future<CommonPlan> prepare(
    CommonReceived got, {
    required Uint8List serverCommon,
    required List<Map<String, Object?>> serverPackages,
    required FamilyDoc common,
    required RegistryView view,
    required DeviceRegistry registry,
  }) async {
    var ks = await _read();
    final me = view.me;
    final canReplace = !commonWaits(got.status) || (got.block?.over ?? false);
    final canShare =
        view.self.kind == DeviceKind.mobile &&
        !view.revokedByOthers &&
        view.selfApproved;
    var keyring = ks.keyring;
    var keyringFull = got.keyringFull;
    var sealing = keyring.forSealingIn(view, syncId: _syncId);
    if (canReplace && sealing == null && canShare) {
      try {
        final fresh = await FamilyCandidate.generate(
          view,
          keys: local.keys,
          syncId: _syncId,
        );
        keyring = keyring.withOwnCandidate(fresh);
        sealing = fresh;
      } on FamilyKeyringFullException {
        keyringFull = true;
      }
    }
    final docChanged =
        got.doc == null || common.canonicalJson() != got.doc!.canonicalJson();
    final reseal =
        canReplace &&
        canShare &&
        sealing != null &&
        (got.status != RemoteCommonStatus.opened ||
            got.kid != sealing.kid ||
            docChanged);
    final remoteKid =
        got.status == RemoteCommonStatus.empty ||
            got.status == RemoteCommonStatus.legacy ||
            got.status == RemoteCommonStatus.forged
        ? null
        : got.kid;
    final uploadedKid = reseal ? sealing.kid : remoteKid;
    final kids = {?uploadedKid, ?sealing?.kid};

    // El reparto: la candidata del común que se sube, a todos los de su
    // audiencia que siguen activos con su ficha y no tienen paquete propio
    // de este móvil (M1: cada uno que sella reparte el suyo).
    final serverFamily = [
      for (final p in serverPackages)
        if (FamilyKeyBundle.isV4(p)) p,
    ];
    var outbox = [
      for (final p in ks.outbox)
        if (kids.contains(familyPackageKid(p)) &&
            view.member('${p['to']}')?.recordDigest == p['tr'])
          p,
    ];
    if (sealing != null && canShare && uploadedKid == sealing.kid) {
      for (final m in sealing.audience) {
        if (m.deviceId == me ||
            view.member(m.deviceId)?.recordDigest != m.recordDigest ||
            hasOwnFamilyPackage(
              [...serverFamily, ...outbox],
              me: me,
              kid: sealing.kid,
              to: m.deviceId,
              toRecord: m.recordDigest,
            )) {
          continue;
        }
        final bundle = await FamilyKeyBundle.seal(
          sender: local.keys,
          view: view,
          syncId: _syncId,
          toDevice: m.deviceId,
          candidate: sealing,
        );
        outbox = [...outbox, bundle.toJson()];
      }
    }
    final revision = reseal ? _nextCommonRevision(ks.revision) : ks.revision;
    final retained = await local.readRetainedCommons();
    // Antes de sellar: candidata, reparto y revisión en una sola escritura.
    // Un cierre después deja una clave guardada que se vuelve a usar; nunca
    // un común publicado sin su clave.
    ks = ks.copyWith(
      keyring: withCommonReferences(
        keyring,
        lastKid: ks.lastKid,
        outbox: outbox,
        retained: retained,
      ),
      outbox: outbox,
      revision: revision,
    );
    await _save(ks);

    final bytes = reseal
        ? await sealFamilyEnvelope(
            doc: common,
            candidate: sealing,
            writer: view.self,
            revision: revision,
            signer: local.keys,
          )
        : serverCommon;

    // Los del servidor: los propios, solo los del común que se sube o de la
    // candidata de este móvil; los ajenos, solo si sirven, con cupo por
    // emisor (primero los de esas candidatas).
    final ownKept = <Map<String, Object?>>[];
    final ownHeld = <Map<String, Object?>>[];
    final others = <Map<String, Object?>>[];
    for (final p in serverFamily) {
      if (p['from'] == me) {
        if (keepOwnFamilyPackage(p, view, kids)) ownKept.add(p);
        if (keepOwnFamilyPackage(p, view, {?remoteKid, ?sealing?.kid})) {
          ownHeld.add(p);
        }
      } else if (await usefulFamilyPackage(p, view, registry)) {
        others.add(p);
      }
    }
    (List<Map<String, Object?>>, List<Map<String, Object?>>) split(
      Set<String> important,
    ) {
      final bySender = <Object?, int>{};
      final first = <Map<String, Object?>>[];
      final rest = <Map<String, Object?>>[];
      for (final pass in [true, false]) {
        for (final p in others) {
          if (important.contains(familyPackageKid(p)) != pass) continue;
          final n = bySender[p['from']] ?? 0;
          if (n >= kMaxFamilyPackagesPerSender) continue;
          bySender[p['from']] = n + 1;
          (pass ? first : rest).add(p);
        }
      }
      return (first, rest);
    }

    List<Map<String, Object?>> unique(Iterable<Map<String, Object?>> all) {
      final seen = <String>{};
      return [
        for (final p in all)
          if (seen.add(jsonEncode(p))) p,
      ];
    }

    final (othersFirst, othersRest) = split(kids);
    final (heldFirst, heldRest) = split({?remoteKid, ?sealing?.kid});
    return CommonPlan(
      common: bytes,
      // Primero el reparto propio; los ajenos de la candidata en juego,
      // como primera tanda de lo que va si cabe.
      mandatory: unique([...ownKept, ...outbox]),
      preferred: unique(othersFirst),
      optional: unique(othersRest),
      heldRequired: unique(ownHeld),
      heldPreferred: unique(heldFirst),
      heldOptional: unique(heldRest),
      serverCommon: serverCommon,
      resealed: reseal,
      replaced: reseal && !got.readable,
      uploadedKid: uploadedKid,
      remoteKid: remoteKid,
      sealingKid: sealing?.kid,
      keyringFull: keyringFull,
    );
  }

  /// El `PUT` con [plan] ha entrado con los paquetes v4 [uploaded]: salen
  /// de la intención y la candidata del común subido pasa a ser la del
  /// último.
  Future<void> accepted(
    CommonPlan plan,
    List<Map<String, Object?>> uploaded,
  ) async {
    final ks = await _read();
    final sent = {for (final p in uploaded) jsonEncode(p)};
    final outbox = [
      for (final p in ks.outbox)
        if (!sent.contains(jsonEncode(p))) p,
    ];
    final lastKid = plan.uploadedKid ?? ks.lastKid;
    await _save(
      CommonKeyState(
        keyring: withCommonReferences(
          ks.keyring,
          lastKid: lastKid,
          outbox: outbox,
          retained: await local.readRetainedCommons(),
        ),
        outbox: outbox,
        revision: ks.revision,
        lastKid: lastKid,
        blocked: plan.resealed ? null : ks.blocked,
      ),
    );
  }
}

int _nextCommonRevision(int previous) {
  if (previous >= kMaxFamilyRevision) {
    throw const CommonStateException('writer revision exhausted');
  }
  return previous + 1;
}
