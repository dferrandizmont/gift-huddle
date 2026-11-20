import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:cryptography/dart.dart';
import 'package:regalos/core/sync/access_policy.dart';
import 'package:regalos/core/sync/renewal_protocol.dart';
import 'package:regalos/core/sync/envelope.dart';
import 'package:regalos/core/sync/pairing_v2.dart'
    show canonicalJsonText, pairingCheckpointHash;
import 'package:regalos/core/sync/protected_envelope.dart';
import 'package:regalos/features/sync/data/sync_transport.dart';
import 'package:regalos/features/sync/data/sync_transport_common.dart';
import 'package:regalos/features/sync/data/sync_transport_v2.dart';

import '../web_device/fake_guard_server.dart';

/// El Worker v2 falso, en memoria y al nivel de HTTP: imita las rutas, los
/// códigos y el orden total de `server/src/list-v2-object.ts` (credencial por
/// móvil guardada como SHA-256, ETag fuerte, `428`/`412`, slots como recursos
/// con delta, `403` de slot ajeno, `413`, `429`, revocación que gana e
/// invitaciones con oferta, respuesta, revelación y aprobación, `410 retired`
/// al volver a crear un `syncId` borrado, `capacity`, `409 generation_full`
/// y los cupos de 24 h de fichas y altas). Así las pruebas pasan por el
/// cliente de verdad ([SyncV2Client]) y su lectura de cabeceras y códigos.
class FakeWorkerV2 {
  final guard = FakeGuardServer(now: clock.now);
  final Map<String, _List> _lists = {};
  final Map<String, String> _invites = {}; // inviteId → syncId
  final Random _random = Random(7);
  final _recoveryRetiredVerifiers = <String>{};

  /// Atomic service side of a successful recovery claim (the locator fake
  /// owns the receipt/CAS). Old credentials stay distinguishably retired.
  void replaceRecoveryCredential(String sid, String deviceId, String verifier) {
    final credential = _lists[sid]!.credentials.firstWhere(
      (c) => c.deviceId == deviceId,
    );
    if (credential.verifier == verifier) return;
    _recoveryRetiredVerifiers.add(credential.verifier!);
    credential.verifier = verifier;
    final list = _lists[sid]!;
    // Claim advances the ordinary snapshot version in the same transaction.
    // A replay with the same verifier returned above must not advance it again.
    list.version++;
    for (final entry in list.sockets.entries.toList()) {
      if (entry.value != deviceId) continue;
      entry.key.add(const SyncTransferredEvent());
      unawaited(entry.key.close());
      list.sockets.remove(entry.key);
    }
  }

  /// Peticiones recibidas por clave `MÉTODO recurso`.
  final Map<String, int> calls = {};

  /// Sin red: todas las peticiones fallan como un corte.
  bool offline = false;

  /// Si no es null, la próxima petición contesta `429` con ese
  /// `Retry-After` (segundos).
  int? rateLimitNext;

  /// Un servidor que manipula: puede cambiar cualquier respuesta.
  SyncResponse Function(String method, Uri uri, SyncResponse response)? tamper;

  /// Se llama antes de cada `PUT` de una lista que ya existe: sirve para que
  /// otro móvil escriba «a la vez».
  Future<void> Function(String syncId)? beforePut;

  /// Un cliente conectado a este servidor.
  SyncV2Client client() => SyncV2Client(
    base: Uri.parse('https://sync.test'),
    sendRequest: send,
    openSocket: socket,
  );

  /// La versión de una lista, o null.
  int? versionOf(String syncId) => _lists[syncId]?.version;

  /// El formato mínimo del común de una lista (B4).
  int minCommonFormatOf(String syncId) => _lists[syncId]!.minCommonFormat;

  /// El formato del común que anunció una credencial (B4).
  int commonFormatOf(String syncId, String deviceId) => _lists[syncId]!
      .credentials
      .firstWhere((c) => c.deviceId == deviceId)
      .commonFormat;

  /// Un servidor que manipula (B4): pone [common] y, si se da, el mínimo
  /// [minCommonFormat] sin ninguna comprobación, y sube la versión.
  void setCommonForTesting(
    String syncId,
    Uint8List common, {
    int? minCommonFormat,
  }) {
    final list = _lists[syncId]!;
    list.common = encodeBase64Url(common);
    if (minCommonFormat != null) list.minCommonFormat = minCommonFormat;
    list.version++;
  }

  /// Si la lista existe y no se ha borrado.
  bool hasList(String syncId) => !(_lists[syncId]?.deleted ?? true);

  /// Los slots guardados de una lista (`persona/móvil` → versión).
  Map<String, int> slotVersions(String syncId) => {
    for (final e in (_lists[syncId]?.slots ?? const <String, _Slot>{}).entries)
      e.key: e.value.ver,
  };

  /// El registro guardado de una lista.
  Object? registryOf(String syncId) => _lists[syncId]?.registry;

  /// Las credenciales de una lista: `deviceId` → revocada.
  Map<String, bool> devicesOf(String syncId) => {
    for (final c in _lists[syncId]?.credentials ?? const <_Credential>[])
      c.deviceId: c.revoked,
  };

  /// Registra a mano una credencial (un móvil que aprobó un revocado y nunca
  /// se publicó en el registro).
  void addCredentialForTesting(
    String syncId,
    String deviceId,
    Uint8List credential, {
    String? approvedBy,
    String role = 'device',
  }) {
    _lists[syncId]!.credentials.add(
      _Credential(
        deviceId,
        _verifier(credential),
        approvedBy: approvedBy,
        role: role,
      ),
    );
  }

  /// Llena la generación de una lista hasta [credentials] credenciales y
  /// [records] fichas conocidas (para probar `capacity` y los topes).
  void fillGenerationForTesting(
    String syncId, {
    int? credentials,
    int? records,
  }) {
    final list = _lists[syncId]!;
    var n = 0;
    while (credentials != null && list.credentials.length < credentials) {
      list.credentials.add(_Credential('filler${n++}', null)..revoked = true);
    }
    while (records != null && list.knownRecords.length < records) {
      list.knownRecords.add('filler${n++}');
    }
  }

  /// Deja [count] slots de escritores que ya no están (`gone<n>`), como los
  /// abandonados que nadie puede borrar (B2). Son slots con la forma y el
  /// tamaño de verdad (`SealedSlot.parse` los acepta), aunque su firma no
  /// valga. Devuelve `persona/móvil` → versión.
  /// Con [writer], todos son de ese escritor (`gone<n>/writer`).
  Map<String, int> plantSlotsForTesting(
    String syncId,
    int count, {
    String? writer,
  }) {
    final list = _lists[syncId]!;
    final planted = <String, int>{};
    for (var n = 0; planted.length < count; n++) {
      final w = writer ?? 'gone$n';
      final key = 'gone$n/$w';
      if (list.slots.containsKey(key)) continue;
      list.slots[key] = _Slot(list.version, fabricatedSlot('gone$n', w));
      planted[key] = list.version;
    }
    return planted;
  }

  /// Deja un slot con [data] tal cual (p. ej. uno que nadie puede leer).
  void plantRawSlotForTesting(
    String syncId,
    String personId,
    String deviceId,
    String data,
  ) {
    final list = _lists[syncId]!;
    list.slots['$personId/$deviceId'] = _Slot(list.version, data);
  }

  /// Un slot con la cabecera y el tamaño de verdad y el resto a ceros.
  static String fabricatedSlot(
    String personId,
    String writer, {
    String listId = 'gone',
  }) {
    final header = SlotHeader(
      listId: listId,
      personId: personId,
      epoch: 1,
      writer: writer,
      revision: 1,
      policy: PolicyState.initial,
      kid: '0000000000000000',
    ).toBytes();
    final bytes = Uint8List(header.length + 12 + kSlotPlainBytes + 16 + 64)
      ..setAll(0, header);
    SealedSlot.parse(bytes);
    return encodeBase64Url(bytes);
  }

  /// Hace caducar las invitaciones.
  void expireInvites() {
    for (final list in _lists.values) {
      list.invites.clear();
    }
    _invites.clear();
  }

  /// WebSocket abiertos de una lista.
  int watchers(String syncId) => _lists[syncId]?.sockets.length ?? 0;

  static String _verifier(List<int> credential) =>
      encodeBase64Url(const DartSha256().hashSync(credential).bytes);

  void _count(String what) => calls[what] = (calls[what] ?? 0) + 1;

  /// Cupo de paquetes (v3 y v4 juntos) por escritor
  /// (`V2_MAX_PACKAGES_PER_WRITER`).
  static const maxPackagesPerWriter = 128;

  /// Cupo de bytes de los paquetes de un escritor
  /// (`V2_MAX_PACKAGE_BYTES_PER_WRITER`).
  static const maxPackageBytesPerWriter = 64 * 1024;

  /// B3, como `packageOwnership` del Worker: una entrada de `keyPackages`
  /// que no estaba guardada solo entra si su `from` es quien llama; las
  /// guardadas que se reenvían tal cual se conservan y quitar siempre vale.
  static SyncResponse? _packageOwnership(
    List<Object?> fresh,
    List<Object?> stored,
    String deviceId,
    String role,
  ) {
    // Copias de una entrada guardada se saltarían las dos reglas.
    if ({for (final p in fresh) jsonEncode(p)}.length != fresh.length) {
      return _err(400, 'duplicate_package');
    }
    final known = {for (final p in stored) jsonEncode(p)};
    final added = fresh.where((p) => !known.contains(jsonEncode(p))).toList();
    if (added.isEmpty) return null;
    if (role != 'device') return _err(403, 'forbidden_role');
    if (added.any((p) => p is! Map || p['from'] != deviceId)) {
      return _err(403, 'forbidden_package');
    }
    if (added.any((p) => (p as Map)['v'] != 3 && p['v'] != 4)) {
      return _err(400, 'bad_package');
    }
    // Un solo tope por escritor, v3 y v4 juntos, en número y en bytes.
    List<Object?> own(List<Object?> l) =>
        l.where((p) => p is Map && p['from'] == deviceId).toList();
    int size(List<Object?> l) =>
        l.fold(0, (n, p) => n + utf8.encode(jsonEncode(p)).length);
    final after = own(fresh);
    final before = own(stored);
    if ((after.length > maxPackagesPerWriter && after.length > before.length) ||
        (size(after) > maxPackageBytesPerWriter &&
            size(after) > size(before))) {
      return _err(413, 'too_many_writer_packages');
    }
    return null;
  }

  /// Deja [packages] tal cual en la lista, como los dejó un servidor anterior
  /// (sin la regla de B3) o un escritor que ya no está.
  void plantPackagesForTesting(
    String syncId,
    List<Map<String, Object?>> packages,
  ) {
    final list = _lists[syncId]!;
    list.packages = [...list.packages, ...packages];
    list.version++;
  }

  static SyncResponse _r(
    int status, [
    Object? body,
    Map<String, String> headers = const {},
  ]) => SyncResponse(
    status,
    {for (final e in headers.entries) e.key.toLowerCase(): e.value},
    body == null
        ? Uint8List(0)
        : Uint8List.fromList(utf8.encode(jsonEncode(body))),
  );

  static SyncResponse _err(
    int status,
    String code, [
    Map<String, String> headers = const {},
  ]) => _r(status, {'error': code}, headers);

  static String _etag(int v) => '"$v"';

  /// Lo que hace `send` del transporte.
  Future<SyncResponse> send(
    String method,
    Uri uri, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    await Future<void>.delayed(Duration.zero);
    if (offline) {
      throw const SyncTransportException(SyncFailure.network, 'sin red');
    }
    // Ida y vuelta por JSON, como en la red.
    final json = body == null
        ? <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(jsonEncode(body)) as Map);
    final h = {for (final e in headers.entries) e.key.toLowerCase(): e.value};
    var response = await _handle(method, uri, h, json);
    final t = tamper;
    if (t != null) response = t(method, uri, response);
    return response;
  }

  Future<SyncResponse> _handle(
    String method,
    Uri uri,
    Map<String, String> h,
    Map<String, Object?> body,
  ) async {
    final limit = rateLimitNext;
    if (limit != null) {
      rateLimitNext = null;
      return _err(429, 'rate_limited', {'Retry-After': '$limit'});
    }
    final p = uri.path.split('/');
    if (p.length < 4 || p[1] != 'v2') return _err(404, 'not_found');
    final bearer = RegExp(r'^Bearer ([A-Za-z0-9_-]{43})$')
        .firstMatch(h['authorization'] ?? '')
        ?.group(1);
    final verifier = bearer == null ? null : _verifier(decodeBase64Url(bearer));
    if (_recoveryRetiredVerifiers.contains(verifier)) {
      return _err(403, 'credential_replaced');
    }
    if (p[2] == 'invites') {
      final syncId = _invites[p[3]];
      final list = syncId == null ? null : _lists[syncId];
      if (p.length != 5) return _err(404, 'not_found');
      final pendingOffer =
          method == 'GET' &&
          p[4] == 'offer' &&
          uri.queryParameters['pending'] == '204';
      if (list == null) {
        return pendingOffer ? _r(204) : _err(404, 'not_found');
      }
      _count('$method ${p[4]}');
      final response = list.publicInvite(
        p[3],
        p[4],
        verifier,
        body,
        method: method,
      );
      return pendingOffer &&
              response.status == 404 &&
              response.json()['error'] == 'not_found'
          ? _r(204, null, response.headers)
          : response;
    }
    if (p[2] != 'lists') return _err(404, 'not_found');
    final syncId = p[3];
    if (p.length == 7 && p[4] == 'guards') {
      final list = _lists[syncId];
      final c = verifier == null ? null : list?.active(verifier);
      if (c != null) {
        guard.credentials['Bearer $bearer'] = FakeGuardCredential(
          syncId,
          c.deviceId,
          c.role,
        );
      }
      return guard.send(
        method,
        uri,
        body: body,
        headers: {if (bearer != null) 'Authorization': 'Bearer $bearer'},
      );
    }
    if (verifier == null) return _err(401, 'unauthorized');
    final resource = p.length == 4
        ? 'list'
        : p.length == 5
        ? p[4]
        : p[4] == 'renewal'
        ? 'renewal'
        : p[4] == 'slots'
        ? 'slot'
        : p.length == 7
        ? p[6]
        : 'invite';
    _count('$method $resource');
    var list = _lists[syncId];
    if (list != null && list.deleted) {
      // Un syncId retirado: crear es 410 para siempre; lo demás, 404.
      return resource == 'list' && method == 'PUT' ||
              resource == 'renewal' ||
              resource == 'common'
          ? _err(410, 'retired')
          : _err(404, 'not_found');
    }
    if (list == null) {
      if (resource != 'list' || method != 'PUT') return _err(404, 'not_found');
      final match = h['if-match'];
      if (match == null) return _err(428, 'precondition_required');
      if (match != _etag(0)) {
        return _err(412, 'precondition_failed', {'ETag': _etag(0)});
      }
      final deviceId = body['deviceId'];
      if (deviceId is! String) return _err(400, 'bad_request');
      final invalid = _validate(body);
      if (invalid != null) return invalid;
      // B4: puede nacer en formato 2 (renovación).
      final min = body['minCommonFormat'] ?? 1;
      if (min is! int || min < 1 || min > 2) return _err(400, 'bad_request');
      final format = _commonFormatError(body['common'] as String, min);
      if (format != null) return format;
      final slots = (body['slots'] as List).cast<Map>();
      // B2: ningún slot ajeno, ni con datos ni con data: null.
      if (slots.any((s) => s['deviceId'] != deviceId)) {
        return _err(403, 'forbidden_slot');
      }
      if (slots.where((s) => s['data'] != null).length > kV2MaxSlotsPerWriter) {
        return _err(413, 'too_many_writer_slots');
      }
      final planted = _packageOwnership(
        body['keyPackages'] as List,
        const [],
        deviceId,
        'device',
      );
      if (planted != null) return planted;
      if (utf8.encode(jsonEncode(body)).length > 256 * 1024) {
        return _err(413, 'too_large');
      }
      list = _lists[syncId] = _List(this, syncId);
      list.minCommonFormat = min;
      list.credentials.add(_Credential(deviceId, verifier)..commonFormat = min);
      list.version = 1;
      list.knownRecords.addAll(_List.recordHashes(body));
      list.write(body, 1);
      return _r(201, {'version': 1}, {'ETag': _etag(1)});
    }
    final auth = list.active(verifier);
    if (auth == null) return _err(401, 'unauthorized');
    if (auth.role == 'web' &&
        !(method == 'GET' &&
                (resource == 'list' ||
                    resource == 'slot' ||
                    resource == 'renewal' ||
                    resource == 'ws') ||
            resource == 'common' && method == 'PUT' ||
            resource == 'renewal' &&
                method == 'PUT' &&
                ['ack', 'resume', 'capability'].contains(body['action']) ||
            // B5: la web anuncia el formato del común.
            resource == 'capability' && method == 'POST' ||
            resource == 'revoke' && body['deviceId'] == auth.deviceId)) {
      return _err(403, 'forbidden_role');
    }
    if (list.renewal != null) {
      if (resource == 'invites' && method == 'POST' || resource == 'approve') {
        return _err(409, 'renewal_in_progress');
      }
      if (list.renewal!['barrierVersion'] != null &&
          method == 'PUT' &&
          (resource == 'list' || resource == 'common')) {
        return _err(409, 'renewal_frozen');
      }
    }
    switch (resource) {
      case 'renewal':
        if (p.length == 9 && p[5] == 'log' && method == 'GET') {
          return list.controlPage(p[6], p[7], int.parse(p[8]));
        }
        return list.control(auth, method, h['if-match'], body);
      case 'common':
        final hook = beforePut;
        if (hook != null) {
          beforePut = null;
          await hook(syncId);
        }
        return list.putCommon(h['if-match'], body);
      case 'list':
        if (method == 'GET') return list.read(h['if-none-match']);
        if (method == 'PUT') {
          final hook = beforePut;
          if (hook != null) {
            beforePut = null;
            await hook(syncId);
          }
          return list.put(auth, h['if-match'], body);
        }
        return list.remove(h['if-match'], auth);
      case 'slot':
        return list.readSlot(h['if-match'], p[5], p[6]);
      case 'revoke':
        return list.revoke(body['deviceId'], h['if-match']);
      case 'capability':
        return list.capability(auth, body);
      case 'ws':
        return _err(426, 'upgrade_required');
      default:
        return list.invitation(
          auth,
          method,
          resource,
          p.length > 5 ? p[5] : null,
          h['if-match'],
          body,
        );
    }
  }

  SyncResponse? _validate(Map<String, Object?> b) {
    final slots = b['slots'];
    final registry = b['registry'];
    if (slots is! List ||
        registry is! Map ||
        registry['records'] is! List ||
        registry['vouches'] is! List ||
        registry['revocations'] is! List ||
        b['keyPackages'] is! List ||
        b['common'] is! String) {
      return _err(400, 'bad_request');
    }
    if (slots.length > 64) return _err(413, 'too_large');
    // `V2_MAX_PACKAGES` y `V2_MAX_PACKAGES_BYTES` (server/src/limits.ts).
    final packages = b['keyPackages'] as List;
    if (packages.length > 512 ||
        utf8.encode(jsonEncode(packages)).length > 256 * 1024) {
      return _err(413, 'too_large');
    }
    final seen = <String>{};
    for (final raw in slots) {
      if (raw is! Map ||
          raw['personId'] is! String ||
          raw['deviceId'] is! String) {
        return _err(400, 'bad_request');
      }
      if (!seen.add('${raw['personId']}/${raw['deviceId']}')) {
        return _err(400, 'bad_request');
      }
      final data = raw['data'];
      if (data == null) continue;
      if (data is! String) return _err(400, 'bad_request');
      final ids = slotIdsForTesting(decodeBase64Url(data));
      if (ids == null ||
          ids.$1 != raw['personId'] ||
          ids.$2 != raw['deviceId']) {
        return _err(400, 'bad_request');
      }
    }
    return null;
  }

  /// Como `commonFormatError` del Worker (B4): un formato posterior es 400
  /// siempre; con el mínimo en 2, uno menor es 409 y lo que no es `RG`, 400.
  static SyncResponse? _commonFormatError(String common, int min) {
    int? format;
    try {
      final head = decodeBase64Url(
        common.length <= 4 ? common : common.substring(0, 4),
      );
      if (head.length >= 3 && head[0] == 0x52 && head[1] == 0x47) {
        format = head[2];
      }
    } on FormatException {
      format = null;
    }
    if (format != null && format > 2) {
      return _err(400, 'common_format_unknown');
    }
    if (min <= 1) return null;
    if (format == null) return _err(400, 'common_format_unknown');
    return format < min ? _err(409, 'common_format_too_old') : null;
  }

  /// El WebSocket falso.
  Stream<SyncEvent> socket(Uri uri, List<String> protocols) {
    final p = uri.path.split('/');
    final found = p.length == 5 ? _lists[p[3]] : null;
    final list = found == null || found.deleted ? null : found;
    final bearer = protocols
        .map((x) => RegExp(r'^bearer\.([A-Za-z0-9_-]{43})$').firstMatch(x))
        .whereType<RegExpMatch>()
        .firstOrNull
        ?.group(1);
    if (offline) {
      return Stream.error(
        const SyncTransportException(SyncFailure.network, 'sin red'),
      );
    }
    final auth = bearer == null || list == null
        ? null
        : list.active(_verifier(decodeBase64Url(bearer)));
    if (!protocols.contains(kWsProtocolV2) || list == null || auth == null) {
      return Stream.error(
        const SyncTransportException(SyncFailure.unauthorized, 'HTTP 401'),
      );
    }
    late final StreamController<SyncEvent> c;
    c = StreamController<SyncEvent>(
      onListen: () => c.add(const SyncOpenEvent()),
      onCancel: () => list.sockets.remove(c),
    );
    list.sockets[c] = auth.deviceId;
    return c.stream;
  }

  String _newId() => encodeBase64Url(
    Uint8List.fromList(List.generate(16, (_) => _random.nextInt(256))),
  );
}

/// Lo que sigue a la cabecera de un slot (`SLOT_BODY_BYTES` del Worker).
const int kSlotBodyBytesForTesting = 12 + kSlotPlainBytes + 16 + 64;

/// Lee los ids de la cabecera de un slot como `slotIds` del Worker, con las
/// mismas comprobaciones: flags 0 o 1, revisiones < 2^53 y el tamaño exacto
/// (cabecera + nonce, 128 KiB, etiqueta y firma).
(String, String)? slotIdsForTesting(List<int> slot) {
  const magic = [0x47, 0x48, 0x53, 0x02];
  const fixed = 4 + 4 + 8 + 1 + 8 + 8;
  if (slot.length < fixed + 3) return null;
  for (var i = 0; i < 4; i++) {
    if (slot[i] != magic[i]) return null;
  }
  final data = ByteData.sublistView(Uint8List.fromList(slot));
  if (data.getUint32(8) > 0x1FFFFF ||
      slot[16] > 1 ||
      data.getUint32(17) > 0x1FFFFF) {
    return null;
  }
  final ids = <String>[];
  var at = fixed;
  for (var k = 0; k < 3; k++) {
    final n = slot[at++];
    if (n == 0 || at + n > slot.length) return null;
    ids.add(String.fromCharCodes(slot.sublist(at, at + n)));
    at += n;
  }
  if (slot.length != at + kSlotBodyBytesForTesting) return null;
  return (ids[1], ids[2]);
}

class _Credential {
  _Credential(
    this.deviceId,
    this.verifier, {
    this.approvedBy,
    this.role = 'device',
  });
  final String role;
  final String deviceId;
  final String? approvedBy;
  String? verifier;
  bool revoked = false;

  /// El formato del común anunciado (B4).
  int commonFormat = 1;

  /// Cuándo añadió fichas nuevas (ventana de 24 h).
  final List<DateTime> records = [];
}

/// Las marcas de [times] de las últimas 24 h.
List<DateTime> _recent(List<DateTime> times) {
  final now = clock.now();
  return [
    for (final t in times)
      if (now.difference(t) < const Duration(hours: 24)) t,
  ];
}

class _Slot {
  _Slot(this.ver, this.data);
  final int ver;
  final String data;
}

class _Invite {
  _Invite(this.id, this.owner, this.offer, {this.guestPerson});
  final String? guestPerson;
  final String id;
  final String owner;
  final Object? offer;
  Object? answer;
  String? guest;
  String? verifier;
  Object? reveal;
  Object? package;
  int? minVersion;

  /// El checkpoint copiado al aprobar (B7): el texto del común y el del
  /// registro canónico.
  ({String common, String registry})? checkpoint;
}

class _List {
  _List(this.server, this.syncId);

  final FakeWorkerV2 server;
  final String syncId;
  int version = 0;
  bool deleted = false;
  final List<_Credential> credentials = [];
  final List<String> denied = [];
  String common = '';

  /// El formato mínimo del común (B4).
  int minCommonFormat = 1;
  Object? registry;
  Map<String, Object?>? renewal;
  List<Object?> packages = const [];
  final Map<String, _Slot> slots = {};
  final Map<String, _Invite> invites = {};
  final Map<StreamController<SyncEvent>, String> sockets = {};

  /// Fichas que ha visto esta generación (su JSON canónico).
  final Set<String> knownRecords = {};
  List<DateTime> recordTimes = [];
  List<DateTime> approvals = [];

  static Set<String> recordHashes(Map<String, Object?> body) => {
    for (final r in ((body['registry'] as Map)['records'] as List))
      jsonEncode(r),
  };

  _Credential? active(String verifier) {
    for (final c in credentials) {
      if (!c.revoked && c.verifier == verifier) return c;
    }
    return null;
  }

  void write(Map<String, Object?> s, int ver) {
    common = s['common'] as String;
    registry = s['registry'];
    packages = List.of(s['keyPackages'] as List);
    for (final raw in (s['slots'] as List).cast<Map>()) {
      final key = '${raw['personId']}/${raw['deviceId']}';
      final data = raw['data'];
      if (data == null) {
        slots.remove(key);
      } else {
        slots[key] = _Slot(ver, data as String);
      }
    }
  }

  SyncResponse? _pre(String? match) {
    if (match == null) {
      return FakeWorkerV2._err(428, 'precondition_required');
    }
    return match == FakeWorkerV2._etag(version)
        ? null
        : FakeWorkerV2._err(412, 'precondition_failed', {
            'ETag': FakeWorkerV2._etag(version),
          });
  }

  void _notify() {
    for (final c in sockets.keys.toList()) {
      c.add(SyncVersionEvent(version));
    }
  }

  /// HTTP-level renewal double. Cryptographic trust is deliberately left to
  /// the caller, just as in the Worker; server/test/renewal.test.ts checks the
  /// authoritative transition validator and request budgets.
  final List<RenewalCommand> renewalCommands = [];
  final renewalIndex = RenewalReplayIndex();
  SyncResponse controlPage(String operation, String head, int after) {
    final at = renewalCommands.indexWhere(
      (c) => c.hash == head && c.operationId == operation,
    );
    if (at < 0 || after > at + 1) return FakeWorkerV2._err(404, 'not_found');
    var end = after + kRenewalLogPageCommands < at + 1
        ? after + kRenewalLogPageCommands
        : at + 1;
    while (utf8
            .encode(
              jsonEncode(
                renewalCommands
                    .sublist(after, end)
                    .map((c) => c.toJson())
                    .toList(),
              ),
            )
            .length >
        kRenewalLogPageBytes) {
      end--;
    }
    return FakeWorkerV2._r(200, {
      'operationId': operation,
      'sourceSyncId': syncId,
      'head': head,
      'height': at + 1,
      'after': after,
      'next': end == at + 1 ? null : end,
      'commands': renewalCommands
          .sublist(after, end)
          .map((c) => c.toJson())
          .toList(),
    });
  }

  SyncResponse control(
    _Credential auth,
    String method,
    String? match,
    Map<String, Object?> json,
  ) {
    SyncResponse answer() => FakeWorkerV2._r(
      200,
      {'version': version, 'renewal': renewal},
      {'ETag': FakeWorkerV2._etag(version)},
    );
    if (method == 'GET') return answer();
    if (match == null) return FakeWorkerV2._err(428, 'precondition_required');
    final c = RenewalCommand.fromJson(json);
    if (c.sourceSyncId != syncId || c.signerDeviceId != auth.deviceId) {
      return FakeWorkerV2._err(403, 'renewal_context_mismatch');
    }
    if (renewalCommands.any((old) => old.hash == c.hash)) return answer();
    final failed = _pre(match);
    if (failed != null) return failed;
    if (renewal != null && renewal!['operationId'] != c.operationId) {
      return FakeWorkerV2._err(409, 'renewal_exists');
    }
    if (c.action == RenewalAction.reserve ||
        c.action == RenewalAction.replace ||
        c.action == RenewalAction.recover ||
        c.action == RenewalAction.revise) {
      if (credentials.any(
        (d) =>
            !d.revoked && !(json['participants'] as List).contains(d.deviceId),
      )) {
        return FakeWorkerV2._err(409, 'renewal_participants_missing');
      }
    }
    try {
      renewal = replayRenewalCommand(
        renewal,
        c,
        credentials.where((d) => d.revoked).map((d) => d.deviceId).toSet(),
        index: renewalIndex,
      );
    } on RenewalProtocolException catch (e) {
      return FakeWorkerV2._err(409, 'renewal_${e.code}');
    }
    if (c.action == RenewalAction.revoke) {
      final target = credentials.firstWhere(
        (d) => d.deviceId == json['participantDeviceId'],
      );
      target.revoked = true;
      target.verifier = null;
    }
    if (c.action == RenewalAction.capability) auth.commonFormat = 2;
    renewalCommands.add(c);
    renewalIndex.add(c);
    version++;
    _notify();
    return answer();
  }

  SyncResponse read(String? none) {
    final tag = FakeWorkerV2._etag(version);
    if (none == tag) return FakeWorkerV2._r(304, null, {'ETag': tag});
    return FakeWorkerV2._r(
      200,
      {
        'version': version,
        'common': common,
        'registry': registry,
        'keyPackages': packages,
        'slots': [
          for (final e in slots.entries)
            {
              'personId': e.key.split('/')[0],
              'deviceId': e.key.split('/')[1],
              'version': e.value.ver,
            },
        ],
        'devices': [
          for (final c in credentials)
            {
              'deviceId': c.deviceId,
              'revoked': c.revoked,
              'role': c.role,
              if (c.approvedBy != null) 'approvedBy': c.approvedBy,
              if (c.commonFormat > 1) 'commonFormat': c.commonFormat,
            },
        ],
        if (minCommonFormat > 1) 'minCommonFormat': minCommonFormat,
        'capacity': {
          'credentials': {'used': credentials.length, 'warn': 48, 'max': 64},
          'records': {'used': knownRecords.length, 'warn': 384, 'max': 512},
          'slots': {'used': slots.length, 'warn': 48, 'max': 64},
          'renew':
              credentials.length >= 48 ||
              knownRecords.length >= 384 ||
              slots.length >= 48,
        },
      },
      {'ETag': tag},
    );
  }

  SyncResponse readSlot(String? match, String person, String device) {
    final failed = _pre(match);
    if (failed != null) return failed;
    final slot = slots['$person/$device'];
    if (slot == null) return FakeWorkerV2._err(404, 'not_found');
    return FakeWorkerV2._r(
      200,
      {'version': version, 'slotVersion': slot.ver, 'data': slot.data},
      {'ETag': FakeWorkerV2._etag(version)},
    );
  }

  SyncResponse put(_Credential auth, String? match, Map<String, Object?> b) {
    final failed = _pre(match);
    if (failed != null) return failed;
    final invalid = server._validate(b);
    if (invalid != null) return invalid;
    // B4: el mínimo sube con el primer común de ese formato, solo desde un
    // móvil que lo anunció; nunca baja.
    final raise = b['minCommonFormat'];
    if (raise != null) {
      if (raise is! int || raise < 1 || raise > 2) {
        return FakeWorkerV2._err(400, 'bad_request');
      }
      if (auth.role != 'device') {
        return FakeWorkerV2._err(403, 'forbidden_role');
      }
      // M1: toda credencial viva, de cualquier rol, tiene que haberlo
      // anunciado.
      if (raise > minCommonFormat &&
          credentials.any((c) => !c.revoked && c.commonFormat < raise)) {
        return FakeWorkerV2._err(409, 'common_format_unannounced');
      }
    }
    final min = raise is int && raise > minCommonFormat
        ? raise
        : minCommonFormat;
    final format = FakeWorkerV2._commonFormatError(b['common'] as String, min);
    if (format != null) return format;
    final changes = (b['slots'] as List).cast<Map>();
    // B2: solo los slots propios, con datos o con data: null; la delta
    // entera se rechaza antes de tocar nada.
    if (changes.isNotEmpty && auth.role == 'web') {
      return FakeWorkerV2._err(403, 'forbidden_role');
    }
    if (changes.any((s) => s['deviceId'] != auth.deviceId)) {
      return FakeWorkerV2._err(403, 'forbidden_slot');
    }
    final planted = FakeWorkerV2._packageOwnership(
      b['keyPackages'] as List,
      packages,
      auth.deviceId,
      auth.role,
    );
    if (planted != null) return planted;
    final keys = slots.keys.toSet();
    for (final s in changes) {
      final key = '${s['personId']}/${s['deviceId']}';
      s['data'] == null ? keys.remove(key) : keys.add(key);
    }
    if (keys.length > 64) return FakeWorkerV2._err(413, 'too_many_slots');
    // Tope por escritor (`V2_MAX_SLOTS_PER_WRITER`): por encima solo se
    // sustituye o se retira.
    int own(Iterable<String> k) =>
        k.where((x) => x.endsWith('/${auth.deviceId}')).length;
    final after = own(keys);
    if (after > kV2MaxSlotsPerWriter && after > own(slots.keys)) {
      return FakeWorkerV2._err(413, 'too_many_writer_slots');
    }
    final fresh = recordHashes(b).difference(knownRecords);
    if (fresh.isNotEmpty) {
      if (knownRecords.length + fresh.length > 512) {
        return FakeWorkerV2._err(409, 'generation_full');
      }
      final own = _recent(auth.records);
      final all = _recent(recordTimes);
      if (own.length + fresh.length > 8 || all.length + fresh.length > 16) {
        return FakeWorkerV2._err(429, 'too_many_records', {
          'Retry-After': '3600',
        });
      }
      final now = clock.now();
      auth.records
        ..clear()
        ..addAll([...own, for (final _ in fresh) now]);
      recordTimes = [...all, for (final _ in fresh) now];
      knownRecords.addAll(fresh);
    }
    version++;
    minCommonFormat = min;
    write(b, version);
    _notify();
    return FakeWorkerV2._r(
      200,
      {'version': version},
      {'ETag': FakeWorkerV2._etag(version)},
    );
  }

  SyncResponse putCommon(String? match, Map<String, Object?> b) {
    final failed = _pre(match);
    if (failed != null) return failed;
    if (b.length != 1 || b['common'] is! String) {
      return FakeWorkerV2._err(400, 'bad_request');
    }
    try {
      decodeBase64Url(b['common'] as String);
    } on FormatException {
      return FakeWorkerV2._err(400, 'bad_request');
    }
    final format = FakeWorkerV2._commonFormatError(
      b['common'] as String,
      minCommonFormat,
    );
    if (format != null) return format;
    common = b['common'] as String;
    version++;
    _notify();
    return FakeWorkerV2._r(
      200,
      {'version': version},
      {'ETag': FakeWorkerV2._etag(version)},
    );
  }

  SyncResponse remove(String? match, _Credential auth) {
    final failed = _pre(match);
    if (failed != null) return failed;
    final control = renewal;
    if (control != null &&
        (control['confirmation'] == null ||
            control['confirmedVersion'] != version ||
            control['needsRevalidation'] == true ||
            !(control['acknowledgements'] as Map).containsKey(auth.deviceId) ||
            (control['exclusions'] as Map).containsKey(auth.deviceId))) {
      return FakeWorkerV2._err(409, 'renewal_close_pending');
    }
    deleted = true;
    version++;
    common = '';
    registry = null;
    packages = const [];
    slots.clear();
    invites.clear();
    renewal = null;
    for (final c in sockets.keys.toList()) {
      c
        ..add(const SyncGoneEvent())
        ..close();
    }
    sockets.clear();
    return FakeWorkerV2._r(204);
  }

  /// `POST S/capability` (B4): monótono; si cambia, sube la versión.
  SyncResponse capability(_Credential auth, Map<String, Object?> b) {
    final format = b['commonFormat'];
    if (b.length != 1 || format is! int || format < 2 || format > 2) {
      return FakeWorkerV2._err(400, 'bad_request');
    }
    if (auth.role != 'device' && auth.role != 'web') {
      return FakeWorkerV2._err(403, 'forbidden_role');
    }
    if (auth.commonFormat < format) {
      auth.commonFormat = format;
      version++;
      _notify();
    }
    return FakeWorkerV2._r(
      200,
      {'version': version},
      {'ETag': FakeWorkerV2._etag(version)},
    );
  }

  /// Sin [match], incondicional; con él, `412` si no es la versión exacta
  /// (B2).
  SyncResponse revoke(Object? deviceId, [String? match]) {
    if (match != null) {
      final failed = _pre(match);
      if (failed != null) return failed;
    }
    final target = credentials.where((c) => c.deviceId == deviceId).firstOrNull;
    if (target == null) return FakeWorkerV2._err(404, 'not_found');
    if (!target.revoked) {
      server.guard.guards.remove('$syncId/$deviceId');
      for (final c in server.guard.credentials.values) {
        if (c.syncId == syncId && c.deviceId == deviceId) c.revoked = true;
      }
      denied.add(target.verifier!);
      target
        ..verifier = null
        ..revoked = true;
      version++;
      if (renewal != null) {
        renewal!['needsRevalidation'] = true;
        renewal!['preparation'] = null;
        renewal!['confirmation'] = null;
        renewal!['confirmedVersion'] = null;
      }
      invites.removeWhere((_, i) => i.owner == deviceId || i.guest == deviceId);
      for (final e in sockets.entries.toList()) {
        if (e.value == deviceId) {
          e.key
            ..add(const SyncRevokedEvent())
            ..close();
          sockets.remove(e.key);
        }
      }
      _notify();
    }
    return FakeWorkerV2._r(
      200,
      {'version': version},
      {'ETag': FakeWorkerV2._etag(version)},
    );
  }

  _Invite? _live(String? id) {
    final i = id == null ? null : invites[id];
    if (i == null || deleted) return null;
    return credentials.any((c) => c.deviceId == i.owner && !c.revoked)
        ? i
        : null;
  }

  SyncResponse invitation(
    _Credential auth,
    String method,
    String resource,
    String? inviteId,
    String? match,
    Map<String, Object?> b,
  ) {
    const expires = 4102444800000; // 2100
    if (resource == 'invites') {
      final offer = b['offer'];
      if (offer is! Map || offer['v'] != 2 || offer['host'] is! Map) {
        return FakeWorkerV2._err(400, 'bad_offer');
      }
      if ((offer['host'] as Map)['d'] != auth.deviceId) {
        return FakeWorkerV2._err(400, 'bad_offer');
      }
      if (invites.values.where((i) => i.package == null).length >= 10) {
        return FakeWorkerV2._err(429, 'too_many_invites');
      }
      final requested = b['inviteId'] as String?;
      if (requested != null && server._invites.containsKey(requested)) {
        final otherList = server._lists[server._invites[requested]];
        final old = otherList?.invites[requested];
        if (otherList != this ||
            old == null ||
            old.owner != auth.deviceId ||
            jsonEncode(old.offer) != jsonEncode(offer) ||
            old.guestPerson != b['guestPerson']) {
          return FakeWorkerV2._err(409, 'invite_exists');
        }
        return FakeWorkerV2._r(200, {
          'inviteId': requested,
          'expiresAt': expires,
        });
      }
      final i = _Invite(
        requested ?? server._newId(),
        auth.deviceId,
        offer,
        guestPerson: b['guestPerson'] as String?,
      );
      invites[i.id] = i;
      server._invites[i.id] = syncId;
      return FakeWorkerV2._r(201, {'inviteId': i.id, 'expiresAt': expires});
    }
    final i = _live(inviteId);
    if (i == null) return FakeWorkerV2._err(404, 'not_found');
    if (i.owner != auth.deviceId) return FakeWorkerV2._err(403, 'forbidden');
    if (method == 'DELETE') {
      invites.remove(i.id);
      return FakeWorkerV2._r(204);
    }
    if (resource == 'invite') {
      return FakeWorkerV2._r(200, {
        'offer': i.offer,
        'answer': i.answer,
        'revealed': i.reveal != null,
        'approved': i.package != null,
        'canApprove':
            renewal == null &&
            _recent(approvals).length < 8 &&
            invites.values.where((x) => x.checkpoint != null).length < 8 &&
            credentials.length < 64,
        'expiresAt': expires,
      });
    }
    if (resource == 'reveal') {
      if (i.answer == null || i.reveal != null) {
        return FakeWorkerV2._err(409, 'invalid_state');
      }
      final reveal = b['reveal'];
      if (reveal is! Map || reveal['v'] != 2) {
        return FakeWorkerV2._err(400, 'bad_reveal');
      }
      i.reveal = reveal;
      return FakeWorkerV2._r(200, {'expiresAt': expires});
    }
    // approve
    final failed = _pre(match);
    if (failed != null) return failed;
    if (i.reveal == null || i.guest == null || i.package != null) {
      return FakeWorkerV2._err(409, 'invalid_state');
    }
    if (b['package'] is! Map) return FakeWorkerV2._err(400, 'bad_package');
    final guestRecord = (i.answer as Map)['guest'] as Map;
    final role = b['role'] ?? 'device';
    if (role != (guestRecord['k'] == 'web' ? 'web' : 'device')) {
      return FakeWorkerV2._err(400, 'role_mismatch');
    }
    if (denied.contains(i.verifier) ||
        credentials.any(
          (c) => c.deviceId == i.guest || c.verifier == i.verifier,
        )) {
      return FakeWorkerV2._err(409, 'credential_exists');
    }
    // B7: el checkpoint de la versión del `If-Match`, si el anfitrión lo
    // pide, con sus hashes contrastados.
    ({String common, String registry})? checkpoint;
    final claim = b['checkpoint'];
    if (claim != null) {
      final hash = RegExp(r'^[A-Za-z0-9_-]{43}$');
      if (claim is! Map ||
          claim.length != 2 ||
          claim['common'] is! String ||
          claim['registry'] is! String ||
          !hash.hasMatch(claim['common'] as String) ||
          !hash.hasMatch(claim['registry'] as String)) {
        return FakeWorkerV2._err(400, 'bad_checkpoint');
      }
      final live = invites.values
          .where((x) => x.checkpoint != null && x.id != i.id)
          .length;
      if (live >= 8) {
        return FakeWorkerV2._err(429, 'too_many_checkpoints', {
          'Retry-After': '3600',
        });
      }
      final copy = (common: common, registry: canonicalJsonText(registry));
      if (pairingCheckpointHash('common', copy.common) != claim['common'] ||
          pairingCheckpointHash('registry', copy.registry) !=
              claim['registry']) {
        return FakeWorkerV2._err(409, 'checkpoint_mismatch');
      }
      checkpoint = copy;
    }
    if (credentials.length >= 64) {
      return FakeWorkerV2._err(409, 'generation_full');
    }
    final recentApprovals = _recent(approvals);
    if (recentApprovals.length >= 8) {
      return FakeWorkerV2._err(429, 'too_many_approvals', {
        'Retry-After': '3600',
      });
    }
    approvals = [...recentApprovals, clock.now()];
    credentials.add(
      _Credential(
        i.guest!,
        i.verifier,
        approvedBy: auth.deviceId,
        role: role as String,
      ),
    );
    version++;
    i
      ..package = b['package']
      ..minVersion = version
      ..checkpoint = checkpoint;
    _notify();
    return FakeWorkerV2._r(
      200,
      {'version': version},
      {'ETag': FakeWorkerV2._etag(version)},
    );
  }

  SyncResponse publicInvite(
    String inviteId,
    String resource,
    String? verifier,
    Map<String, Object?> b, {
    String method = 'GET',
  }) {
    if (verifier != null && denied.contains(verifier)) {
      return FakeWorkerV2._err(401, 'unauthorized');
    }
    final i = _live(inviteId);
    if (i == null) return FakeWorkerV2._err(404, 'not_found');
    const expires = 4102444800000;
    if (resource == 'offer') {
      return FakeWorkerV2._r(200, {
        'offer': i.offer,
        'guestPerson': i.guestPerson,
        'expiresAt': expires,
      });
    }
    if (resource == 'answer') {
      final answer = b['answer'];
      final v = b['serviceCredentialVerifier'];
      if (answer is! Map || answer['guest'] is! Map || v is! String) {
        return FakeWorkerV2._err(400, 'bad_answer');
      }
      final guestRecord = answer['guest'] as Map;
      if (i.guestPerson != null && guestRecord['p'] != i.guestPerson) {
        return FakeWorkerV2._err(400, 'person_mismatch');
      }
      if (i.guestPerson != null && guestRecord['k'] != 'web') {
        return FakeWorkerV2._err(400, 'role_mismatch');
      }
      if (denied.contains(v)) return FakeWorkerV2._err(401, 'unauthorized');
      final guest = (answer['guest'] as Map)['d'];
      if (credentials.any((c) => c.deviceId == guest || c.verifier == v)) {
        return FakeWorkerV2._err(409, 'credential_exists');
      }
      if (i.answer != null) return FakeWorkerV2._err(409, 'already_answered');
      i
        ..answer = answer
        ..guest = guest as String
        ..verifier = v;
      return FakeWorkerV2._r(201, {'expiresAt': expires});
    }
    if (verifier == null || verifier != i.verifier) {
      return FakeWorkerV2._err(404, 'not_found');
    }
    if (resource == 'withdraw') {
      if (b.isNotEmpty) return FakeWorkerV2._err(400, 'bad_request');
      if (i.package != null) return FakeWorkerV2._err(409, 'already_approved');
      invites.remove(i.id);
      server._invites.remove(i.id);
      return FakeWorkerV2._r(204);
    }
    if (resource == 'checkpoint') {
      final copy = i.checkpoint;
      if (i.package == null) {
        return FakeWorkerV2._err(404, 'not_found');
      }
      if (method == 'DELETE') {
        invites.remove(i.id);
        server._invites.remove(i.id);
        return FakeWorkerV2._r(204);
      }
      if (copy == null) return FakeWorkerV2._err(404, 'not_found');
      return FakeWorkerV2._r(200, {
        'common': copy.common,
        'registry': copy.registry,
      });
    }
    if (i.package == null) {
      return FakeWorkerV2._r(
        202,
        {'status': 'pending', 'reveal': i.reveal},
        {'Retry-After': '4'},
      );
    }
    return FakeWorkerV2._r(200, {
      'reveal': i.reveal,
      'package': i.package,
      'minVersion': i.minVersion,
      'syncId': syncId,
    });
  }
}
