// Migración de v1 a v2 en la aplicación (ADR 0004, «Migración y retirada de
// v1»). Dart puro.
//
// - Un móvil con lista v1 sigue en v1 hasta que alguien vuelve a conectar los
//   móviles. El que invita entonces pasa su documento a v2 (`migrateToV2`:
//   clave de la familia nueva, `syncId` aleatorio y solo su ficha) y su id de
//   móvil es su nodo del reloj, el mismo que firma sus cambios en v1.
// - El que entra con la misma lista fusiona su copia local de v1
//   (`mergeLocalV1IntoV2`); conserva su nodo, que pasa a ser su id de móvil.
// - La copia v1 del servidor se borra cuando todos los que habían escrito en
//   ella al migrar están en el registro v2 ([v1WritersMigrated]), a los
//   [kLegacyV1MaxAge] de migrar (se dan por perdidos los que falten) o con
//   «Dejar de sincronizar». Hasta entonces, los móviles v2 que guardan la
//   clave v1 la leen de vez en cuando y fusionan lo que hayan escrito los que
//   aún no han migrado, sin su marca del protocolo: nada se pierde, y quien
//   tenga la clave v1 no puede bajar la marca de la familia v2 (hallazgo 1).
//   Un móvil v1 que quede fuera no pierde nada: al volver a conectarse fusiona
//   su copia local (`mergeLocalV1IntoV2`).
library;

import 'package:clock/clock.dart';

import '../../../core/sync/device_registry.dart';
import '../../../core/sync/envelope.dart';
import '../../../core/sync/family_doc.dart';
import '../../../core/sync/pairing_v2.dart';
import '../data/sync_transport.dart';
import '../domain/sync_keys.dart';

/// Los nodos que han escrito algo en [doc] (las marcas de sus campos).
Set<String> writerNodesOf(FamilyDoc doc) => {
  for (final collection in doc.collections.values)
    for (final record in collection.values)
      for (final field in record.fields.values) field.stamp.node,
};

/// Lo que dura como mucho la copia v1 tras migrar: después se borra aunque
/// falte alguno por volver a conectarse (hallazgo 1).
const Duration kLegacyV1MaxAge = Duration(days: 30);

/// Si todos los que habían escrito en la copia v1 cuando este móvil migró
/// ([known], sus nodos) tienen ya ficha en el registro v2 (su id de móvil es
/// su nodo de v1). Los nodos que aparecen después no cuentan: quien tenga la
/// clave v1 no puede retener la copia escribiendo con nodos nuevos.
bool v1WritersMigrated({
  required Set<String> known,
  required DeviceRegistry registry,
}) {
  final devices = {for (final r in registry.records) r.deviceId};
  return devices.containsAll(known);
}

/// Lo que se recuerda de la lista v1 mientras no se borra del servidor.
class LegacyV1 {
  /// Crea el recuerdo.
  const LegacyV1({
    required this.listId,
    required this.key,
    required this.since,
    required this.nodes,
  });

  /// La lista (la misma que en v2).
  final String listId;

  /// La clave de la familia de v1.
  final FamilyKey key;

  /// Cuándo migró este móvil.
  final DateTime since;

  /// Los nodos que habían escrito en v1 al migrar: los que se esperan.
  final Set<String> nodes;

  /// Si ya ha pasado [kLegacyV1MaxAge] desde [since].
  bool expiredAt(DateTime now) => now.difference(since) >= kLegacyV1MaxAge;

  /// En JSON (va al almacén seguro).
  Map<String, Object?> toJson() => {
    'l': listId,
    'k': key.toBase64Url(),
    's': since.millisecondsSinceEpoch,
    'n': nodes.toList()..sort(),
  };

  /// Lee [toJson]. Lanza [FormatException] si no vale. Un recuerdo sin fecha
  /// o sin nodos (de antes de este formato) se da por caducado: la copia v1
  /// se borra en la siguiente vuelta.
  factory LegacyV1.fromJson(Object? json) {
    if (json is! Map || json['l'] is! String || json['k'] is! String) {
      throw const FormatException('v1 no válida');
    }
    final s = json['s'];
    final n = json['n'];
    return LegacyV1(
      listId: json['l'] as String,
      key: FamilyKey.fromBase64Url(json['k'] as String),
      since: DateTime.fromMillisecondsSinceEpoch(s is int ? s : 0, isUtc: true),
      nodes: {
        if (n is List)
          for (final x in n)
            if (x is String) x,
      },
    );
  }
}

/// Resultado de mirar la copia v1 del servidor.
enum V1Retirement {
  /// Ya no está (o se acaba de borrar): la clave v1 sobra.
  retired,

  /// Sigue, porque algún móvil que escribió en v1 aún no ha migrado.
  kept,
}

/// Lee la copia v1 del servidor, le pasa a [absorb] su documento sin la
/// marca del protocolo (para fusionarlo en v2) y la borra si todos los que
/// se esperaban ya están en [registry], si ha caducado ([kLegacyV1MaxAge]) o
/// si [force] («Dejar de sincronizar»). Los fallos de red se lanzan: se
/// vuelve a mirar después.
///
/// Con [closed] (la familia ya pasó al formato 2 del común: la marca
/// irreversible de ADR 0005, B4) el puente está cerrado: no se lee ni se
/// fusiona nada de la copia v1, que se borra. Quien escribió en ella y no ha
/// migrado conserva su copia local y la fusiona al volver a emparejarse.
Future<V1Retirement> retireV1({
  required SyncTransport transport,
  required LegacyV1 legacy,
  required DeviceRegistry registry,
  required Future<void> Function(FamilyDoc v1Doc) absorb,
  bool force = false,
  bool closed = false,
}) async {
  final auth = SyncCredentials(
    listId: legacy.listId,
    syncId: await SyncKeys.syncId(legacy.key),
    authKey: await SyncKeys.authKey(legacy.key),
  );
  if (closed) {
    await transport.deleteList(auth);
    return V1Retirement.retired;
  }
  final got = await transport.getList(auth);
  switch (got) {
    case SyncGetNotFound():
      return V1Retirement.retired;
    case SyncGetNotModified():
      throw const SyncTransportException(SyncFailure.protocol, '304');
    case SyncGetOk():
      final opened = await open(
        got.envelope,
        key: legacy.key,
        expectedListId: legacy.listId,
      );
      final FamilyDoc doc;
      try {
        doc = FamilyDoc.fromJson(opened.doc);
      } on FormatException {
        throw const EnvelopeFormatException('documento no válido');
      }
      if (syncProtocolOf(doc) == 1) await absorb(withoutProtocolMark(doc));
      final done =
          force ||
          legacy.expiredAt(clock.now()) ||
          v1WritersMigrated(known: legacy.nodes, registry: registry);
      if (!done) return V1Retirement.kept;
      await transport.deleteList(auth);
      return V1Retirement.retired;
  }
}

/// Una generación v2 a medio instalar en este móvil (hallazgos 7 y 2): la
/// clave de la familia y el `syncId` que va a usar, escritos antes de tocar
/// el documento o la clave. Si se corta, se termina con estos mismos; nunca
/// se usa como clave v2 la que ya tenía el móvil (la de v1 o la de una
/// generación anterior).
class PendingV2 {
  /// Crea el pendiente.
  const PendingV2({
    required this.key,
    required this.syncId,
    this.fromV1 = false,
    this.reset = false,
    this.commonFormat = 1,
    this.pairing = false,
  });

  /// Si es la instalación de un invitado (B7): si se descarta, se deshace lo
  /// escrito y se abandona la credencial de servicio, que ya está registrada
  /// en la lista (M3).
  final bool pairing;

  /// El formato mínimo del común con el que nace (ADR 0005, B7): un
  /// invitado que entra tras el corte lo trae firmado en la aprobación, y
  /// [finishPendingV2] pone la marca irreversible antes de la identidad si
  /// la instalación se cortó.
  final int commonFormat;

  /// La clave de la familia de la generación nueva.
  final FamilyKey key;

  /// Su `syncId`.
  final String syncId;

  /// Si viene de una migración desde v1.
  final bool fromV1;

  /// Si hay que empezar de cero el registro, los slots, el llavero y el
  /// estado (una generación nueva tras borrar la lista o salir de ella).
  final bool reset;

  /// Una generación nueva con clave y `syncId` aleatorios.
  static Future<PendingV2> fresh({
    bool fromV1 = false,
    bool reset = false,
  }) async => PendingV2(
    key: await FamilyKey.generate(),
    syncId: SyncIdentityV2.newSyncId(),
    fromV1: fromV1,
    reset: reset,
  );

  /// En JSON (va al almacén seguro).
  Map<String, Object?> toJson() => {
    'k': key.toBase64Url(),
    'sid': syncId,
    if (fromV1) 'from': 1,
    if (reset) 'reset': true,
    if (commonFormat > 1) 'cf': commonFormat,
    if (pairing) 'pair': true,
  };

  /// Lee [toJson], o null si no vale.
  static PendingV2? fromJson(Object? json) {
    if (json is! Map || json['k'] is! String || json['sid'] is! String) {
      return null;
    }
    final sid = json['sid'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(sid)) return null;
    // Un formato que no se entiende cuenta como el más alto conocido: la
    // marca nunca se rebaja por un pendiente dañado.
    final cf = json['cf'];
    final commonFormat = cf == null ? 1 : (cf is int && cf >= 1 ? cf : 2);
    try {
      return PendingV2(
        key: FamilyKey.fromBase64Url(json['k'] as String),
        syncId: sid,
        fromV1: json['from'] == 1,
        reset: json['reset'] == true,
        commonFormat: commonFormat,
        pairing: json['pair'] == true,
      );
    } on Object {
      return null;
    }
  }
}
