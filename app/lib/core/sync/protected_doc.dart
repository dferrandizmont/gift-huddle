// Bloque de sorpresas: conjunto de slots, apertura de un ámbito, proyección
// autorizada, publicación y transiciones de la protección. Dart puro.
// Decisión: docs/adr/0004-yo-sorpresas-revocar.md (fases 1 y 2a) y las
// dos revisiones de seguridad de la fase 1.
//
// - Un slot por (persona protegida, móvil escritor). Cada escritor publica la
//   instantánea acumulativa del ámbito. Hay uno por móvil con derecho, tenga
//   o no algo que decir, así que su número es público y fijo (M5).
// - Quién cuenta lo decide el registro de móviles (`RegistryView.entitled`):
//   el mismo predicado para recibir la clave y para escribir slots. Un slot
//   de un móvil revocado, pendiente, sin persona o de la persona protegida se
//   ignora: ni se lee ni bloquea nada (requisito 10).
// - Fusión del conjunto: de cada escritor se queda el último slot por
//   (época, revisión) y, en empate, el de bytes mayores; nunca se descarta
//   el slot de otro escritor. Es conmutativa, asociativa e idempotente, y la
//   puede hacer sin clave el móvil de la persona protegida (relevo). Todo lo
//   que entra se verifica con la firma (M3).
// - La política autenticada sale de las cabeceras firmadas de los slots que
//   cuentan, así que la conoce también quien no tiene la clave (N1).
// - Al abrir un ámbito se descifran todos los slots y se fusionan sus
//   `FamilyDoc` con la fusión por campo de siempre.
// - Un regalo que pasa al bloque secreto conserva su id (en el común queda su
//   lápida y en la vista manda el secreto), así que dos móviles que lo mueven
//   a la vez, aunque sea con claves candidatas distintas, escriben lo mismo.
//   Al publicarse recibe un id nuevo que no se puede adivinar sin haber
//   abierto el bloque (B2).
// - Relojes (B5): el ámbito secreto usa su propio reloj, que recibe las
//   marcas del documento común; el común solo recibe las del secreto cuando
//   se publica (entonces dejan de ser secretas).
library;

import 'dart:convert';
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:cryptography/dart.dart';
import 'package:meta/meta.dart';

import 'access_policy.dart';
import 'device_keys.dart';
import 'device_registry.dart';
import 'envelope.dart' show decodeBase64Url, encodeBase64Url;
import 'family_doc.dart';
import 'hlc.dart';
import 'hmac.dart';
import 'key_bundle.dart';
import 'model.dart';
import 'protected_envelope.dart';

/// Regalos públicos de una persona protegida que la reconciliación mueve
/// en cada pasada como mucho. Es público y no depende de cuántos secretos
/// haya (revisión de seguridad, A2).
const int kMaxReconcileMoves = 8;

/// Slots que se aceptan de una vez (de la red, de un fichero o de una
/// copia). El tope se comprueba antes de leer o verificar ninguno. Es
/// `V2_MAX_SLOTS` del Worker: una familia de 10 personas con móvil y todas
/// protegidas tiene 10 · 9 = 90, y caben los de un móvil revocado en su
/// plazo de gracia.
const int kMaxSlotsPerList = 128;

/// Cada cuánto vuelve a sellar su slot un móvil aunque no haya cambiado nada
/// en público (M5): lo que se edita en secreto sale, como muy tarde, con la
/// siguiente publicación.
const Duration kSlotCadence = Duration(hours: 1);

/// Cuánto por delante de este reloj puede ir la revisión de un slot que
/// llega (la misma holgura que las marcas HLC). Un slot con una revisión más
/// adelantada no entra: si entrara, dejaría a su escritor sin poder publicar
/// uno más nuevo y sin cadencia (hallazgo 12).
const Duration kMaxSlotClockSkew = kMaxHlcDrift;

/// Campo de un regalo del bloque secreto que vino del documento común: una
/// sal que solo conocen quienes abren el bloque, para su id al publicarse.
const String kPublishSaltField = 'publishSalt';

/// Qué pasó al recibir un slot.
enum SlotAcceptance {
  /// Primer slot de ese escritor para esa persona.
  added,

  /// Más nuevo que el que había: lo reemplaza.
  replaced,

  /// Exactamente el mismo que ya había.
  duplicate,

  /// Revisión (o época) más vieja que la que ya había: rechazado.
  stale,

  /// Misma revisión con otro contenido: se queda el de bytes mayores, para
  /// que todos los móviles acaben igual.
  conflict,
}

/// Los slots de sorpresas de la lista, por persona y escritor. Inmutable.
///
/// Solo entra lo verificado: [acceptVerified], [verified], [merge] y
/// [fromJsonVerified] comprueban, con el registro de móviles, que el
/// escritor tiene derecho a ese ámbito y su firma. [fromLocalStoreJson] es
/// solo para el almacén local de este móvil, que ya guardó slots
/// verificados.
class SlotSet {
  SlotSet._(this._slots);

  /// Sin slots.
  static final SlotSet empty = SlotSet._(const {});

  final Map<String, Map<String, SealedSlot>> _slots;

  /// Crea el conjunto con los [slots] que pasan la verificación; los demás
  /// se descartan (cuántos, en el segundo valor).
  static Future<(SlotSet, int)> verified(
    Iterable<SealedSlot> slots, {
    required RegistryView view,
  }) => empty.merge(slots, view: view);

  /// Personas con algún slot.
  Set<String> get people => _slots.keys.toSet();

  /// Los slots de [personId], ordenados por escritor.
  List<SealedSlot> slotsFor(String personId) {
    final byWriter = _slots[personId] ?? const <String, SealedSlot>{};
    final writers = byWriter.keys.toList()..sort();
    return [for (final w in writers) byWriter[w]!];
  }

  /// Todos los slots, ordenados por persona y escritor.
  List<SealedSlot> get all => [
    for (final person in _slots.keys.toList()..sort()) ...slotsFor(person),
  ];

  /// El slot de [writer] para [personId], o null.
  SealedSlot? slotOf(String personId, String writer) =>
      _slots[personId]?[writer];

  /// La revisión que debe usar [writer] en su próxima publicación: el
  /// momento [nowMillis], o la suya anterior más uno si el reloj no ha
  /// avanzado. No cuenta ediciones (M5).
  int nextRevision(String personId, String writer, {required int nowMillis}) {
    final previous = slotOf(personId, writer)?.header.revision ?? 0;
    final next = nowMillis > previous ? nowMillis : previous + 1;
    return next > kMaxSlotRevision ? kMaxSlotRevision : next;
  }

  /// La política autenticada de [personId]: la mayor de las cabeceras de los
  /// slots de escritores con derecho según [view], o null si no hay ninguno.
  /// No necesita la clave de sorpresas.
  PolicyState? authenticatedPolicy(String personId, RegistryView view) {
    PolicyState? policy;
    for (final slot in slotsFor(personId)) {
      if (view.entitled(slot.header.writer, personId) == null) continue;
      policy = policy == null
          ? slot.header.policy
          : policy.max(slot.header.policy);
    }
    return policy;
  }

  /// El conjunto sin los slots de escritores revocados (o desconocidos) y de
  /// los que han pasado a ser de la persona protegida: no se leen, no
  /// bloquean y no hay por qué seguir reenviándolos.
  ///
  /// Los de un escritor congelado (pendiente de aprobación, o con la persona
  /// borrada) se conservan: se ignoran al leer, pero mientras exista ese
  /// slot no se compactan lápidas, porque ese móvil puede guardar todavía
  /// una copia viva (hallazgo 2). Los de un escritor que solo cuelga de un
  /// revocado no (segunda revisión, N1 y N3): para el registro ya no es de
  /// la familia, y si no se podaran, un ladrón revocado que avaló móviles
  /// falsos llenaría el conjunto con sus slots.
  SlotSet pruned(RegistryView view) {
    bool keep(String writer, String person) {
      final device = view.device(writer);
      return device != null && device.personId != person;
    }

    return SlotSet._(
      Map.unmodifiable({
        for (final person in _slots.entries)
          if (person.value.keys.any((w) => keep(w, person.key)))
            person.key: Map<String, SealedSlot>.unmodifiable({
              for (final e in person.value.entries)
                if (keep(e.key, person.key)) e.key: e.value,
            }),
      }),
    );
  }

  int get _count => _slots.values.fold(0, (n, w) => n + w.length);

  /// Recibe [slot] ya verificado. Nunca hay más de [kMaxSlotsPerList] en el
  /// conjunto (segunda revisión, N3): si está lleno, un slot nuevo de un
  /// escritor con derecho según [view] desaloja el de uno que no lo tiene
  /// (de los que solo se guardan para reenviar, el último por persona y
  /// escritor); si no hay ninguno que desalojar, o el nuevo no tiene derecho
  /// (o no hay [view]), lanza [SlotFormatException] y no cambia nada.
  (SlotSet, SlotAcceptance) _accept(SealedSlot slot, {RegistryView? view}) {
    final h = slot.header;
    final current = slotOf(h.personId, h.writer);
    if (current == null) {
      if (_count < kMaxSlotsPerList) {
        return (_with(slot), SlotAcceptance.added);
      }
      if (view == null || view.entitled(h.writer, h.personId) == null) {
        throw const SlotFormatException('no caben más slots');
      }
      SealedSlot? victim;
      for (final s in all.reversed) {
        if (view.entitled(s.header.writer, s.header.personId) == null) {
          victim = s;
          break;
        }
      }
      if (victim == null) {
        throw const SlotFormatException('no caben más slots');
      }
      return (
        _without(victim.header.personId, victim.header.writer)._with(slot),
        SlotAcceptance.added,
      );
    }
    final order = _compareSlots(slot, current);
    if (order == 0) return (this, SlotAcceptance.duplicate);
    final sameRevision = slot.header.version == current.header.version;
    if (order < 0) {
      return (
        this,
        sameRevision ? SlotAcceptance.conflict : SlotAcceptance.stale,
      );
    }
    return (
      _with(slot),
      sameRevision ? SlotAcceptance.conflict : SlotAcceptance.replaced,
    );
  }

  /// Recibe un slot comprobando antes la lista, que la época no es mayor que
  /// la del registro, que la revisión no va más de [kMaxSlotClockSkew] por
  /// delante de este reloj, que el escritor puede escribir ese ámbito según
  /// [view] ([RegistryView.relayable]: para quien puede tener la clave es lo
  /// mismo que tener derecho) y su firma. Lanza [SlotWrongScopeException] o
  /// [SlotAuthException] si no.
  Future<(SlotSet, SlotAcceptance)> acceptVerified(
    SealedSlot slot, {
    required RegistryView view,
  }) async {
    if (slot.header.listId != view.listId) {
      throw const SlotWrongScopeException('el slot es de otra lista');
    }
    if (slot.header.epoch > view.epoch) {
      throw const SlotWrongScopeException(
        'el slot es de una época que el registro no ha abierto',
      );
    }
    if (slot.header.revision >
        clock.now().millisecondsSinceEpoch + kMaxSlotClockSkew.inMilliseconds) {
      throw const SlotWrongScopeException(
        'el slot tiene una revisión del futuro',
      );
    }
    final writer = view.relayable(slot.header.writer, slot.header.personId);
    if (writer == null) {
      throw const SlotAuthException('ese móvil no puede escribir este ámbito');
    }
    if (!await slot.verifySignature(writer.signingKey)) {
      throw const SlotAuthException('firma no válida');
    }
    return _accept(slot, view: view);
  }

  /// La fusión con [slots]: de cada escritor, su último slot. Cada slot que
  /// entra se verifica; los que no pasan se descartan (cuántos, en el
  /// segundo valor). Con más de [kMaxSlotsPerList] no se mira ninguno y se
  /// lanza [SlotFormatException].
  Future<(SlotSet, int)> merge(
    Iterable<SealedSlot> slots, {
    required RegistryView view,
  }) async {
    final incoming = slots.take(kMaxSlotsPerList + 1).toList();
    if (incoming.length > kMaxSlotsPerList) {
      throw const SlotFormatException('demasiados slots');
    }
    var out = this;
    var rejected = 0;
    for (final slot in incoming) {
      try {
        out = (await out.acceptVerified(slot, view: view)).$1;
      } on ProtectedEnvelopeException {
        rejected++;
      }
    }
    return (out, rejected);
  }

  SlotSet _without(String personId, String writer) => SlotSet._(
    Map.unmodifiable({
      for (final e in _slots.entries)
        if (e.key != personId)
          e.key: e.value
        else if (e.value.length > 1)
          e.key: Map<String, SealedSlot>.unmodifiable({
            for (final w in e.value.entries)
              if (w.key != writer) w.key: w.value,
          }),
    }),
  );

  SlotSet _with(SealedSlot slot) {
    final next = <String, Map<String, SealedSlot>>{
      for (final e in _slots.entries) e.key: e.value,
    };
    next[slot.header.personId] = Map<String, SealedSlot>.unmodifiable({
      ...?_slots[slot.header.personId],
      slot.header.writer: slot,
    });
    return SlotSet._(Map.unmodifiable(next));
  }

  /// Los slots en base64url, para guardarlos o enviarlos.
  List<String> toJson() => [for (final s in all) encodeBase64Url(s.bytes)];

  /// Lee [toJson] verificando cada slot (red, fichero, copia). Los que no
  /// pasan se descartan. Lanza [FormatException] si no es una lista o trae
  /// más de [kMaxSlotsPerList].
  static Future<(SlotSet, int)> fromJsonVerified(
    Object? json, {
    required RegistryView view,
  }) => verified(parseSlotList(json), view: view);

  /// Lee [toJson] del almacén local de este móvil, **sin** verificar: solo
  /// para lo que este móvil guardó después de verificarlo.
  factory SlotSet.fromLocalStoreJson(Object? json) {
    var set = empty;
    for (final slot in parseSlotList(json)) {
      try {
        set = set._accept(slot).$1;
      } on SlotFormatException {
        // No cabe (no puede pasar con lo que guardó [toJson]): se salta.
      }
    }
    return set;
  }

  /// Igualdad por contenido (mismos bytes en cada posición).
  bool sameAs(SlotSet other) {
    final a = all;
    final b = other.all;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!constantTimeEquals(a[i].bytes, b[i].bytes)) return false;
    }
    return true;
  }
}

/// Lee una lista de slots en base64url sin verificar nada más que su
/// estructura. El tope [kMaxSlotsPerList] se comprueba antes de leer
/// ninguno. Lanza [FormatException] o [ProtectedEnvelopeException].
List<SealedSlot> parseSlotList(Object? json) {
  if (json is! List) throw const FormatException('slots no válidos');
  if (json.length > kMaxSlotsPerList) {
    throw const FormatException('demasiados slots');
  }
  return [
    for (final item in json)
      if (item is String)
        SealedSlot.parse(decodeBase64Url(item))
      else
        throw const FormatException('slot no válido'),
  ];
}

int _compareSlots(SealedSlot a, SealedSlot b) {
  final byVersion = a.header.version.compareTo(b.header.version);
  if (byVersion != 0) return byVersion;
  final x = a.bytes;
  final y = b.bytes;
  final n = x.length < y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return x.length.compareTo(y.length);
}

// --------------------------------------------------------- abrir un ámbito

/// Las sorpresas de una persona, abiertas y fusionadas.
class OpenedScope {
  /// Crea el ámbito abierto.
  const OpenedScope({
    required this.personId,
    required this.doc,
    required this.authenticatedPolicy,
    required this.parts,
    required this.unreadableWriters,
    required this.ignoredWriters,
    this.frozenWriters = const <String>[],
  });

  /// Persona protegida.
  final String personId;

  /// Fusión por campo de los documentos de todos los slots abiertos.
  final FamilyDoc doc;

  /// La mayor de las políticas de las cabeceras de los slots que cuentan
  /// (también los que no se pudieron descifrar), o null si no hay ninguno.
  final PolicyState? authenticatedPolicy;

  /// Lo abierto de cada escritor.
  final Map<String, OpenedSlot> parts;

  /// Escritores con derecho cuyo slot no se pudo descifrar (falta la clave
  /// de esa época, o el GCM no vale). Es pasajero: lo arregla que llegue la
  /// clave o que ese móvil vuelva a sellar; si no, revocarlo. Mientras
  /// tanto, lo que haya dentro no se ve ni se publica, y no se compactan
  /// lápidas.
  final List<String> unreadableWriters;

  /// Escritores sin derecho según el registro (revocados, pendientes, sin
  /// persona o de la persona protegida): su slot se ignora.
  final List<String> ignoredWriters;

  /// Los de [ignoredWriters] que no están revocados ni son de la persona
  /// protegida (pendientes de aprobación, o con la persona borrada): están
  /// congelados y pueden guardar todavía una copia viva, así que mientras
  /// los haya no se compactan lápidas (hallazgo 2).
  final List<String> frozenWriters;

  /// La política que vale para este móvil, que tiene la clave: falla en
  /// cerrado (M1).
  PolicyState effective(PolicyState? published) => effectivePolicy(
    published: published,
    authenticated: authenticatedPolicy,
    failClosed: true,
  );

  /// La marca más nueva, para el reloj del ámbito (nunca para el común).
  Hlc? get maxStamp => doc.maxStamp;
}

/// Abre las sorpresas de [personId].
///
/// Devuelve null si este móvil no puede abrirlas: no tiene derecho según
/// [view] (es de la persona protegida, no tiene persona, lo han revocado) o
/// no tiene ninguna clave de ese ámbito. Los slots de escritores sin derecho
/// se ignoran (A1, M6).
Future<OpenedScope?> openScope({
  required String personId,
  required SlotSet slots,
  required SurpriseKeyring keyring,
  required RegistryView view,
}) async {
  if (!view.selfEntitled(personId)) return null;
  if (keyring.latestFor(personId) == null) return null;
  var doc = FamilyDoc.empty(view.listId);
  PolicyState? policy;
  final parts = <String, OpenedSlot>{};
  final unreadable = <String>[];
  final ignored = <String>[];
  final frozen = <String>[];
  for (final slot in slots.slotsFor(personId)) {
    final header = slot.header;
    final writer = view.entitled(header.writer, personId);
    if (writer == null || header.epoch > view.epoch) {
      ignored.add(header.writer);
      final device = view.device(header.writer);
      if (device != null && device.personId != personId) {
        frozen.add(header.writer);
      }
      continue;
    }
    // Con la firma mal no cuenta ni su política (solo puede pasar con algo
    // que no entró por [SlotSet.merge]).
    if (!await slot.verifySignature(writer.signingKey)) {
      ignored.add(header.writer);
      continue;
    }
    // La cabecera ya está autenticada, se pueda descifrar o no el resto.
    policy = policy == null ? header.policy : policy.max(header.policy);
    final key = keyring.keyFor(personId, header.epoch, header.kid);
    if (key == null) {
      unreadable.add(header.writer);
      continue;
    }
    try {
      final opened = await slot.open(
        expectedListId: view.listId,
        key: key,
        signingKey: writer.signingKey,
      );
      doc = doc.merge(opened.doc);
      parts[header.writer] = opened;
    } on ProtectedEnvelopeException {
      unreadable.add(header.writer);
    }
  }
  return OpenedScope(
    personId: personId,
    doc: doc,
    authenticatedPolicy: policy,
    parts: Map.unmodifiable(parts),
    unreadableWriters: List.unmodifiable(unreadable),
    ignoredWriters: List.unmodifiable(ignored),
    frozenWriters: List.unmodifiable(frozen),
  );
}

// ------------------------------------------------------------- publicar

/// Este móvil no puede publicar su slot ahora.
class SlotPublishBlockedException extends ProtectedEnvelopeException {
  /// Crea el error.
  const SlotPublishBlockedException(super.message);
}

/// Un slot recién sellado.
class PublishedSlot {
  /// Crea el resultado.
  const PublishedSlot({
    required this.slot,
    required this.scope,
    required this.sealed,
    required this.leftOut,
  });

  /// El slot.
  final SealedSlot slot;

  /// El ámbito ya compactado: lo que este móvil debe guardar como su copia
  /// local a partir de ahora (si conservara las lápidas que acaba de quitar,
  /// las volvería a publicar la próxima vez).
  final FamilyDoc scope;

  /// Lo que va dentro del slot: [scope] ajustado al tamaño.
  final FamilyDoc sealed;

  /// Regalos vivos que no cupieron (más de [kMaxSlotGifts] al fusionar
  /// varios escritores): siguen en la copia local y hay que avisar (N3).
  final List<String> leftOut;
}

/// Si a este móvil le toca volver a sellar su slot de una persona. Depende
/// solo de datos públicos (M5): no tiene slot en esta época o no es de la
/// clave con la que ahora se sella, está subiendo un cambio del documento
/// común ([commonChanged]), o ha pasado [cadence] desde su último slot.
/// Nunca depende de si ha editado algo en secreto.
bool slotPublishDue({
  required SlotHeader? mine,
  required int epoch,
  required String sealingKid,
  required int nowMillis,
  required bool commonChanged,
  Duration cadence = kSlotCadence,
}) =>
    mine == null ||
    mine.epoch != epoch ||
    mine.kid != sealingKid ||
    commonChanged ||
    nowMillis - mine.revision >= cadence.inMilliseconds;

/// [doc] sin las lápidas que ya conocen todos los móviles con derecho.
///
/// Una lápida se quita solo si este móvil ya la publicó en su slot y, de
/// cada uno de los demás con derecho, se ha abierto un slot que no tiene el
/// regalo vivo y que o bien tiene la lápida o bien dice que ya había
/// fusionado ese slot de este móvil (`seen`). Así nadie puede guardar
/// todavía una copia viva y nada resucita. Con un escritor sin slot o
/// ilegible no se quita nada; revocarlo (rotación) lo desbloquea
/// (requisito 17). Tampoco mientras haya un escritor congelado
/// ([OpenedScope.frozenWriters]): al volver a tener derecho publicaría su
/// copia, y lo borrado resucitaría (hallazgo 2).
FamilyDoc compactScope({
  required FamilyDoc doc,
  required OpenedScope opened,
  required RegistryView view,
}) {
  final mine = opened.parts[view.me];
  if (mine == null || opened.frozenWriters.isNotEmpty) return doc;
  final others = <OpenedSlot>[];
  for (final device in view.entitledDevices(opened.personId)) {
    if (device == view.me) continue;
    final part = opened.parts[device];
    if (part == null) return doc;
    others.add(part);
  }
  final gifts = doc.collections[Collections.gifts] ?? const {};
  final kept = <String, SyncRecord>{};
  for (final record in gifts.values) {
    final known =
        record.isDeleted &&
        (mine.doc.record(Collections.gifts, record.id)?.isDeleted ?? false) &&
        others.every((part) {
          final theirs = part.doc.record(Collections.gifts, record.id);
          if (theirs != null) return theirs.isDeleted;
          final seen = part.seen[view.me];
          return seen != null && seen.compareTo(mine.header.version) >= 0;
        });
    if (!known) kept[record.id] = record;
  }
  return FamilyDoc(listId: doc.listId, collections: {Collections.gifts: kept});
}

/// Publica la instantánea acumulativa de este escritor para el ámbito de
/// [opened]: sella [doc] (lo abierto más los cambios locales) con la clave
/// de la época del registro, compactando lápidas ([compactScope]) y
/// ajustando al tamaño ([fitScopeToSlot]).
///
/// Lanza [SlotPublishBlockedException] si este móvil no puede publicar: no
/// tiene derecho según [view], lo han revocado, le falta la clave de la
/// época actual, no pudo leer su propio slot anterior (su instantánea no lo
/// recogería: pasa al restaurar una copia) o [policy] es más vieja que la
/// autenticada.
Future<PublishedSlot> publishScope({
  required SlotSet slots,
  required OpenedScope opened,
  required RegistryView view,
  required DeviceKeys writerKeys,
  required SurpriseKeyring keyring,
  required PolicyState policy,
  required FamilyDoc doc,
  required int nowMillis,
  int revisionFloor = 0,
  Map<String, SlotVersion> extraSeen = const <String, SlotVersion>{},
}) async {
  final personId = opened.personId;
  if (!view.selfEntitled(personId)) {
    throw const SlotPublishBlockedException(
      'este móvil no puede escribir este ámbito',
    );
  }
  final key = keyring.sealingKeyFor(
    personId,
    view.epoch,
    allowed: view.entitledDevices(personId),
  );
  if (key == null) {
    throw const SlotPublishBlockedException(
      'falta la clave de sorpresas de la época actual',
    );
  }
  if (slots.slotOf(personId, view.me) != null &&
      !opened.parts.containsKey(view.me)) {
    throw const SlotPublishBlockedException(
      'no se ha podido leer el slot anterior de este móvil',
    );
  }
  final authenticated = opened.authenticatedPolicy;
  if (authenticated != null && policy.compareTo(authenticated) < 0) {
    throw const SlotPublishBlockedException(
      'la política es más vieja que la autenticada',
    );
  }
  final seen = <String, SlotVersion>{
    // Los buzones de webs propias ya recogidos (1.0.6, ADR 0009): los demás
    // móviles de la misma persona saben así que ya están dentro.
    for (final e in extraSeen.entries)
      if (e.key != view.me) e.key: e.value,
    for (final e in opened.parts.entries)
      if (e.key != view.me) e.key: e.value.header.version,
  };
  final scope = compactScope(doc: doc, opened: opened, view: view);
  final (sealed, leftOut) = fitScopeToSlot(
    scope,
    personId,
    seen: seen,
    maxLive: slotGiftLimitFor([
      for (final device in view.entitledDevices(personId))
        if (device != view.me) opened.parts[device],
    ]),
  );
  return PublishedSlot(
    scope: scope,
    slot: await SealedSlot.seal(
      writerKeys: writerKeys,
      writer: view.me,
      revision: max(
        slots.nextRevision(personId, view.me, nowMillis: nowMillis),
        revisionFloor + 1,
      ),
      key: key,
      policy: policy,
      doc: sealed,
      seen: seen,
    ),
    sealed: sealed,
    leftOut: leftOut,
  );
}

// ----------------------------------------------------- claves y rotación

/// Una clave de sorpresas nueva y los paquetes para repartirla.
class SurpriseKeyShare {
  /// Crea el reparto.
  const SurpriseKeyShare({
    required this.keyring,
    required this.key,
    required this.bundles,
  });

  /// El llavero con la clave nueva.
  final SurpriseKeyring keyring;

  /// La clave nueva (candidata de su época).
  final SurpriseKey key;

  /// Un paquete por cada otro móvil con derecho.
  final List<KeyBundle> bundles;
}

/// Un móvil con derecho confirma la protección de [personId]: crea una clave
/// candidata de la época del registro y los paquetes para los demás. Es el
/// único sitio donde nace una clave de sorpresas: pedir la protección
/// ([requestProtection]) nunca crea clave ni mueve regalos (requisito 15).
///
/// Si dos móviles lo hacen a la vez no chocan: hay dos candidatas, los dos
/// las reparten, y todos acaban sellando con la de `kid` más bajo.
/// Lanza [StateError] si este móvil no tiene derecho a esas sorpresas.
Future<SurpriseKeyShare> createSurpriseKey({
  required String personId,
  required SurpriseKeyring keyring,
  required RegistryView view,
  required DeviceKeys keys,
}) async {
  if (!view.selfEntitled(personId)) {
    throw StateError('este móvil no tiene derecho a esas sorpresas');
  }
  final key = SurpriseKey.generate(
    personId,
    view.epoch,
    audience: view.entitledDevices(personId),
  );
  return SurpriseKeyShare(
    keyring: keyring.withKey(
      key,
      registryEpoch: view.epoch,
      allowed: view.entitledDevices(personId),
    ),
    key: key,
    bundles: await KeyBundle.sealSurpriseKeyForAll(
      sender: keys,
      view: view,
      key: key,
    ),
  );
}

/// Las claves de sorpresa de la época actual que este móvil puede darle a
/// [deviceId]: una por cada persona a cuyas sorpresas tienen derecho los dos.
/// Se usa cuando un móvil pasa a tener derecho después de que se repartieran
/// las claves (se emparejó o lo aprobaron más tarde). Nunca van claves de
/// épocas anteriores: lo sellado con ellas lo verá cuando sus escritores
/// vuelvan a sellar.
///
/// La audiencia de cada clave pasa a incluir a [deviceId] (en el paquete y en
/// el llavero que devuelve, que hay que guardar).
Future<({SurpriseKeyring keyring, List<KeyBundle> bundles})>
shareSurpriseKeysWith({
  required String deviceId,
  required SurpriseKeyring keyring,
  required RegistryView view,
  required DeviceKeys keys,
}) async {
  var next = keyring;
  final bundles = <KeyBundle>[];
  for (final person in keyring.people.toList()..sort()) {
    final key = keyring.sealingKeyFor(
      person,
      view.epoch,
      allowed: view.entitledDevices(person),
    );
    if (key == null ||
        deviceId == view.me ||
        !view.selfEntitled(person) ||
        view.entitled(deviceId, person) == null) {
      continue;
    }
    final wider = key.withAudience([deviceId]);
    next = next.withKey(
      wider,
      registryEpoch: view.epoch,
      allowed: view.entitledDevices(person),
    );
    bundles.add(
      await KeyBundle.sealSurpriseKey(
        sender: keys,
        view: view,
        toDevice: deviceId,
        key: wider,
      ),
    );
  }
  return (keyring: next, bundles: List<KeyBundle>.unmodifiable(bundles));
}

/// Lo que hace este móvil con sus claves de sorpresa cuando el registro abre
/// una época (revocación o cambio de persona).
class SurpriseRotation {
  /// Crea el resultado.
  const SurpriseRotation({
    required this.keyring,
    required this.bundles,
    required this.purgedPeople,
    this.frozenPeople = const <String>[],
  });

  /// El llavero nuevo.
  final SurpriseKeyring keyring;

  /// Los paquetes de las claves nuevas, para los móviles con derecho.
  final List<KeyBundle> bundles;

  /// Personas cuyas claves se han quitado porque este móvil ha pasado a ser
  /// suyo: quien llama debe borrar también la copia local de ese ámbito y lo
  /// que tenga en memoria.
  final List<String> purgedPeople;

  /// Personas a cuyas sorpresas este móvil ha perdido el derecho sin pasar
  /// a ser suyo (lo han revocado, espera aprobación tras cambiar entre dos
  /// personas que no son esa, o su persona se ha borrado). Sus claves y su
  /// copia se conservan, pero no se abre, no se sella ni se publica nada
  /// hasta que vuelva a tenerlo; la interfaz debe avisar (hallazgo 2).
  final List<String> frozenPeople;
}

/// Pone el llavero al día con la época de [view]: de cada persona de la que
/// este móvil tenía clave, si este móvil es ahora suyo la purga; si ha
/// perdido el derecho por otra cosa, la congela (conserva claves y copia:
/// un móvil robado que revoca a los demás, corregir el propio «Yo» o borrar
/// la persona no hacen perder las sorpresas; hallazgo 2); y si le falta la
/// clave de la época actual crea una candidata y la reparte. Es idempotente:
/// con la clave de la época ya en el llavero no hace nada.
Future<SurpriseRotation> rotateSurpriseKeys({
  required SurpriseKeyring keyring,
  required RegistryView view,
  required DeviceKeys keys,
}) async {
  var next = keyring;
  final bundles = <KeyBundle>[];
  final purged = <String>[];
  final frozen = <String>[];
  for (final person in keyring.people.toList()..sort()) {
    if (view.myPerson == person) {
      next = next.without(person);
      purged.add(person);
      continue;
    }
    if (!view.selfEntitled(person)) {
      frozen.add(person);
      continue;
    }
    // Sin una candidata de esta época cuya audiencia siga entera con
    // derecho (no hay ninguna, o la conoce alguien que ya no lo tiene), se
    // crea otra (hallazgo 7).
    if (next.sealingKeyFor(
          person,
          view.epoch,
          allowed: view.entitledDevices(person),
        ) !=
        null) {
      continue;
    }
    final share = await createSurpriseKey(
      personId: person,
      keyring: next,
      view: view,
      keys: keys,
    );
    next = share.keyring;
    bundles.addAll(share.bundles);
  }
  return SurpriseRotation(
    keyring: next,
    bundles: List.unmodifiable(bundles),
    purgedPeople: List.unmodifiable(purged),
    frozenPeople: List.unmodifiable(frozen),
  );
}

// ----------------------------------------------------- proyección

/// «Hay bloque secreto para esta persona»: lo único que ve quien no puede
/// abrirlo. No dice cuántos regalos hay, ni siquiera si hay alguno.
class SecretBlock {
  /// Crea el bloque.
  const SecretBlock(this.personId);

  /// Persona protegida.
  final String personId;

  @override
  bool operator ==(Object other) =>
      other is SecretBlock && other.personId == personId;

  @override
  int get hashCode => personId.hashCode;

  @override
  String toString() => 'SecretBlock($personId)';
}

/// Lo que ve este móvil: el documento común más las sorpresas que puede
/// abrir.
class AuthorizedProjection {
  /// Crea la proyección.
  AuthorizedProjection({
    required this.secretGiftIds,
    required this.lockedBlocks,
    required this.openedScopes,
    required this.policies,
    required this.doc,
    this._year,
    this._includeArchived = false,
    Set<String> hiddenGiftIds = const {},
  }) : _hiddenGiftIds = Set.unmodifiable(hiddenGiftIds);

  /// Authorized records only; also suitable as the input to readable exports.
  final FamilyDoc doc;

  /// La vista: búsqueda, presupuesto, Reparto y duplicados salen de aquí, así
  /// que solo cuentan las sorpresas que este móvil puede abrir.
  ///
  /// Para exportar o compartir algo legible se usa siempre el documento
  /// común, nunca esta vista: lo secreto no sale del bloque secreto.
  late final FamilyView view = FamilyView.fromDoc(
    doc,
    year: _year,
    includeArchived: _includeArchived,
    hiddenGiftIds: _hiddenGiftIds,
  );
  final int? _year;
  final bool _includeArchived;
  final Set<String> _hiddenGiftIds;

  /// Regalos de [view] que vienen del bloque secreto.
  final Set<String> secretGiftIds;

  /// Bloques que este móvil no puede abrir, ordenados por persona.
  final List<SecretBlock> lockedBlocks;

  /// Ámbitos abiertos, por persona.
  final Map<String, OpenedScope> openedScopes;

  /// La política que vale para cada persona con política, por persona.
  final Map<String, PolicyState> policies;
}

/// La política que vale para un móvil que no puede abrir las sorpresas de
/// [personId] (el de la persona protegida, o uno autorizado que aún no tiene
/// la clave): la autenticada de las cabeceras de los slots, y si no hay
/// ninguna y hay slots, alguna clave o un registro `policies/<persona>`,
/// «ocultar» (N1 y hallazgo 3a).
///
/// Excepción del móvil solo (1.0.6): con [alone], si [personId] es la
/// persona de este móvil y en su registro no hay ninguna ficha de otro
/// dispositivo ([RegistryView.alone]), vale «sin protección». Es solo local:
/// no publica ni autentica nada, y deja de valer en cuanto entra otro
/// dispositivo. Lo que estaba en secreto no vuelve: nunca estuvo en este
/// móvil. La aplicación solo la pide ([ownProtectionLifted]) en una
/// generación que este móvil ha estrenado sin nadie y después de purgar lo
/// que quedaba en el común ([purgeOwnPublicGifts]).
PolicyState lockedPolicy({
  required FamilyDoc common,
  required SlotSet slots,
  required RegistryView view,
  required String personId,
  bool hasKey = false,
  bool alone = false,
}) => alone && view.alone && personId == view.myPerson
    ? PolicyState.initial
    : effectivePolicy(
        published: publishedPolicy(common, personId),
        authenticated: slots.authenticatedPolicy(personId, view),
        failClosed: hasKey || slots.slotsFor(personId).isNotEmpty,
      );

/// Las personas cuyos regalos este móvil no pinta (capa de pantalla, 1.0.6):
/// la suya ([selfRecipientId] y la de su ficha) mientras esté acompañado. No
/// depende de la política ni de la versión de los demás, y no tiene
/// interruptor en este móvil.
///
/// - Con registro: si hay una ficha de otro dispositivo de otra persona
///   ([RegistryView.accompanied]), o si este móvil ya se ha emparejado
///   ([paired]) aunque su registro todavía no tenga a nadie (una familia v1
///   que pasa a v2).
/// - Sin registro (v1, o mientras carga): si está emparejado.
///
/// Mientras un cambio de persona no está aprobado (en v1, siempre), también
/// las personas de antes ([formerSelf] y las de las fichas anteriores de
/// este móvil): un regalo público tardío para ellas no vuelve a verse.
Set<String> ownHiddenPeople({
  required RegistryView? view,
  required String? selfRecipientId,
  required bool paired,
  Set<String> formerSelf = const <String>{},
}) {
  final pendingChange = view == null || !view.selfApproved;
  final own = <String>{
    ?selfRecipientId,
    ?view?.myPerson,
    if (pendingChange) ...formerSelf,
    if (view != null && pendingChange)
      for (final r in view.registry.records)
        if (r.deviceId == view.me) ?r.personId,
  };
  if (view == null) return paired ? own : const <String>{};
  return {
    for (final person in own)
      if (view.accompanied(person) || (paired && view.alone)) person,
  };
}

/// Si a este móvil le vale la excepción del móvil solo ([lockedPolicy]): su
/// registro no tiene a nadie más ([RegistryView.alone]) y no se ha
/// emparejado en esta generación ([paired]).
bool ownProtectionLifted({required RegistryView? view, required bool paired}) =>
    view != null && view.alone && !paired;

/// Lo que un móvil puede volver a sellar para sí al quedarse solo (QA 1.0.6,
/// M1), decidido con la vista de la generación que deja, ANTES de estrenar la
/// otra ([planAloneRestore]; revisión de seguridad de la revisión, B1 y B2).
class AloneRestorePlan {
  /// Crea el plan.
  const AloneRestorePlan({
    this.people = const <String>{},
    this.own = const <String>{},
  });

  /// Nada que restaurar.
  static const none = AloneRestorePlan();

  /// Personas a cuyas sorpresas este móvil tenía derecho en la generación que
  /// deja ([RegistryView.selfEntitled]): sin revocar, con la ficha aprobada,
  /// con su persona y la de cada una vivas y sin congelar.
  final Set<String> people;

  /// Personas que son o fueron de este móvil: la suya, las de antes
  /// (`formerSelf`) y las de todas sus fichas. Nunca se restauran.
  final Set<String> own;
}

/// El plan de [othersToRestoreWhenAlone], con la vista [view] de la
/// generación que se deja y antes de tocar nada (ni el llavero, ni el
/// registro, ni `formerSelf`). [held] son las personas de las que este móvil
/// tiene clave o copia local.
///
/// Una persona entra solo si este móvil tiene derecho a sus sorpresas en esa
/// vista ([RegistryView.selfEntitled]): un móvil revocado por otro, con un
/// cambio de persona sin aprobar, o con su persona borrada no recupera nada,
/// y tampoco una persona borrada o congelada (`SurpriseRotation.frozenPeople`
/// son justo las del llavero sin ese derecho).
AloneRestorePlan planAloneRestore({
  required RegistryView view,
  required Iterable<String> held,
  String? selfRecipientId,
  Set<String> formerSelf = const <String>{},
}) {
  final own = <String>{
    ?selfRecipientId,
    ...formerSelf,
    ?view.myPerson,
    for (final r in view.registry.records)
      if (r.deviceId == view.me) ?r.personId,
  };
  if (view.self.kind != DeviceKind.mobile) {
    return AloneRestorePlan(own: Set.unmodifiable(own));
  }
  return AloneRestorePlan(
    people: Set.unmodifiable({
      for (final person in held)
        if (!own.contains(person) && view.selfEntitled(person)) person,
    }),
    own: Set.unmodifiable(own),
  );
}

/// Las personas cuyas sorpresas vuelve a sellar para sí un móvil que se ha
/// quedado solo (QA 1.0.6, M1). Al estrenar una generación sin nadie
/// ([ownProtectionLifted]) el llavero y los slots de la anterior se tiran,
/// pero la copia local de cada ámbito que este móvil podía abrir
/// ([localScopes]) se queda: sin una clave de la generación nueva, esos
/// regalos quedaban cerrados para él aunque los tuviera.
///
/// Quién puede volver lo decide [plan], con la generación que se deja: solo
/// las personas de [AloneRestorePlan.people] y nunca las de
/// [AloneRestorePlan.own]. En la generación nueva hace falta, además:
/// - el registro verificado sin ninguna ficha de otro dispositivo, ni
///   siquiera revocada ([RegistryView.alone]), sin haberse emparejado en ella
///   ([paired]) y en un móvil;
/// - la copia local de esa persona;
/// - que no sea la suya y tenga derecho también aquí
///   ([RegistryView.selfEntitled]);
/// - la protección puesta en el común (`policies/<persona>` dice «ocultar»);
/// - y que aún no haya clave ni slot suyos (es idempotente).
///
/// La clave nueva nace en [createSurpriseKey] con la audiencia de siempre,
/// que aquí es solo este móvil; no se publica nada hasta volver a conectar
/// otro móvil, y entonces el reparto sigue a [RegistryView.entitled].
Set<String> othersToRestoreWhenAlone({
  required FamilyDoc common,
  required RegistryView view,
  required SlotSet slots,
  required SurpriseKeyring keyring,
  required Iterable<String> localScopes,
  required bool paired,
  required AloneRestorePlan plan,
}) {
  if (paired || !view.alone || view.self.kind != DeviceKind.mobile) {
    return const <String>{};
  }
  return {
    for (final person in localScopes)
      if (plan.people.contains(person) &&
          !plan.own.contains(person) &&
          person != view.myPerson &&
          view.selfEntitled(person) &&
          publishedPolicy(common, person)?.hideOwnGifts == true &&
          !keyring.people.contains(person) &&
          slots.slotsFor(person).isEmpty)
        person,
  };
}

/// Si este móvil ocultaba algo de [people] en la generación que deja
/// (1.0.6, la misma regla que [ownHiddenPeople]): en [registry] hay una
/// ficha de otro dispositivo de otra persona, aunque esté revocado, o no hay
/// ninguna otra y se había emparejado ([paired]). Con solo dispositivos de
/// la misma persona no se ocultaba nada y no se purga. Sin poder leer el
/// registro ([unreadable]), se supone que sí.
bool ownGiftsWereHidden({
  required DeviceRegistry? registry,
  required String me,
  required Iterable<String?> people,
  required bool paired,
  bool unreadable = false,
}) {
  if (unreadable) return true;
  final others = [
    for (final r in registry?.records ?? const <DeviceRecord>[])
      if (r.deviceId != me) r,
  ];
  if (others.isEmpty) return paired;
  return people.whereType<String>().any(
    (p) => others.any((r) => r.personId != p),
  );
}

/// Borra (lápida vacía) los regalos vivos para [personId] del documento
/// común. Se usa al estrenar una generación sin nadie, antes de levantar la
/// capa de pantalla: lo único que puede quedar son regalos que la protección
/// aún no había pasado al bloque secreto y que este móvil no pintaba. Nunca
/// se llama sobre un común que vaya a subir a una lista compartida.
FamilyDoc purgeOwnPublicGifts(
  FamilyDoc common,
  String personId,
  HlcClock clock,
) {
  var next = common;
  for (final record
      in common.collections[Collections.gifts]?.values.toList() ??
          const <SyncRecord>[]) {
    if (record.isDeleted || record['recipientId'] != personId) continue;
    next = next.delete(clock, Collections.gifts, record.id);
  }
  return next;
}

/// El común de la generación que este móvil estrena sin nadie (salir de la
/// familia, dejar de sincronizar, la lista ya no está): si en la anterior
/// tuvo compañía ([hadCompany]), sin los regalos vivos para su persona
/// ([people]: la de «Yo» y la de su ficha), antes de que la excepción del
/// móvil solo levante la capa de pantalla ([purgeOwnPublicGifts]). Lo que
/// estaba en secreto no vuelve porque nunca estuvo aquí. Sin compañía no
/// borra nada: esos regalos los escribió este móvil y siempre los ha visto.
FamilyDoc purgeOwnGiftsOnLeaving(
  FamilyDoc doc, {
  required String node,
  required Iterable<String?> people,
  required bool hadCompany,
}) {
  if (!hadCompany) return doc;
  final clock = HlcClock(node: node, last: doc.maxStamp);
  var next = doc;
  for (final person in people.whereType<String>().toSet()) {
    next = purgeOwnPublicGifts(next, person, clock);
  }
  return next;
}

/// Si [personId] solo regala ([Recipient.noGifts]): no recibe regalos, así
/// que no hay nada que poner en secreto.
bool receivesNoGifts(FamilyDoc common, String personId) {
  final record = common.record(Collections.recipients, personId);
  return record != null && Recipient.fromRecord(record)?.noGifts == true;
}

/// Si la protección de [personId] se puede saltar porque no hay nada que
/// ocultar: solo regala ([receivesNoGifts]) y además en [common] no queda
/// ningún regalo vivo para ella. La marca `noGifts` es un campo del común sin
/// autenticar, y un 1.0.5 la trata como una persona normal y le apunta
/// regalos (revisión de seguridad, B5): con alguno vivo, se protege.
bool nothingToProtectFor(FamilyDoc common, String personId) =>
    receivesNoGifts(common, personId) &&
    !(common.collections[Collections.gifts]?.values.any(
          (r) => !r.isDeleted && r['recipientId'] == personId,
        ) ??
        false);

/// Si en el común [common] los regalos para [personId] están en secreto: hay
/// una política publicada que dice «ocultar» y ningún regalo vivo suyo. Es
/// lo que comprueba el anfitrión en el checkpoint exacto antes de aprobar el
/// móvil de esa persona (1.0.6).
bool commonHidesGiftsFor(FamilyDoc common, String personId) =>
    publishedPolicy(common, personId)?.hideOwnGifts == true &&
    !(common.collections[Collections.gifts]?.values.any(
          (r) => !r.isDeleted && r['recipientId'] == personId,
        ) ??
        false);

/// Las personas cuya protección activa este móvil por su cuenta (1.0.6):
/// tienen algún dispositivo en el registro ([RegistryView.devicePeople]), no
/// son la de este móvil ni solo regalan ([receivesNoGifts]), este móvil
/// tiene derecho a sus sorpresas ([RegistryView.selfEntitled]) y todavía no
/// hay registro `policies/<persona>` ni política autenticada en [slots]. Con
/// un registro publicado manda la política: una desactivación firmada desde
/// otro móvil se respeta.
Set<String> peopleToAutoProtect(
  FamilyDoc common,
  RegistryView view, {
  SlotSet? slots,
}) => {
  for (final person in view.devicePeople)
    if (person != view.myPerson &&
        !nothingToProtectFor(common, person) &&
        view.selfEntitled(person) &&
        common.record(Collections.policies, person) == null &&
        slots?.authenticatedPolicy(person, view) == null)
      person,
};

/// Construye la vista de este móvil.
///
/// Los regalos de los slots que puede abrir se añaden a la vista (un
/// registro secreto sustituye al común del mismo id); los de los que no
/// puede abrir no existen para él, y de cada persona protegida cuyo bloque no
/// puede abrir solo queda un [SecretBlock].
Future<AuthorizedProjection> projectAuthorized({
  required FamilyDoc common,
  required SlotSet slots,
  required SurpriseKeyring keyring,
  required RegistryView view,
  int? year,
  bool includeArchived = false,
  Set<String> hiddenGiftIds = const <String>{},
  Map<String, FamilyDoc> localScopes = const {},
  Set<String> ownPeople = const <String>{},
  bool alone = false,
}) async {
  final published = publishedPolicies(common);
  final people = <String>{
    ...published.keys,
    ...slots.people,
    ...keyring.people,
  }.toList()..sort();
  final gifts = <String, SyncRecord>{...?common.collections[Collections.gifts]};
  final secretIds = <String>{};
  final locked = <SecretBlock>[];
  final opened = <String, OpenedScope>{};
  final policies = <String, PolicyState>{};
  for (final person in people) {
    final scope = await openScope(
      personId: person,
      slots: slots,
      keyring: keyring,
      view: view,
    );
    if (scope == null) {
      final policy = lockedPolicy(
        common: common,
        slots: slots,
        view: view,
        personId: person,
        hasKey: keyring.people.contains(person),
        alone: alone,
      );
      if (published.containsKey(person) || policy != PolicyState.initial) {
        policies[person] = policy;
      }
      if (policy.hideOwnGifts) locked.add(SecretBlock(person));
      continue;
    }
    opened[person] = scope;
    policies[person] = scope.effective(published[person]);
    final local = localScopes[person];
    final visibleScope = scope.unreadableWriters.isEmpty && local != null
        ? scope.doc.merge(local)
        : scope.doc;
    for (final record
        in visibleScope.collections[Collections.gifts]?.values ??
            const <SyncRecord>[]) {
      gifts[record.id] = record;
      if (!record.isDeleted) secretIds.add(record.id);
    }
  }
  // A common snapshot can still contain gifts written before activation (or
  // by an older phone). Never expose those while protection is requested.
  gifts.removeWhere(
    (id, record) =>
        policies[record['recipientId']]?.hideOwnGifts == true &&
        !secretIds.contains(id),
  );
  // Capa de pantalla (1.0.6): en el móvil de una persona acompañada no se
  // pinta ningún regalo para ella ([ownHiddenPeople]), tenga o no política;
  // solo queda su bloque de tamaño fijo.
  if (ownPeople.isNotEmpty) {
    gifts.removeWhere(
      (id, record) => ownPeople.contains(record['recipientId']),
    );
    secretIds.removeWhere((id) => !gifts.containsKey(id));
    for (final person in ownPeople) {
      if (!locked.contains(SecretBlock(person))) {
        locked.add(SecretBlock(person));
      }
    }
    locked.sort((a, b) => a.personId.compareTo(b.personId));
  }
  final merged = FamilyDoc(
    listId: common.listId,
    collections: {...common.collections, Collections.gifts: gifts},
  );
  return AuthorizedProjection(
    doc: merged,
    year: year,
    includeArchived: includeArchived,
    hiddenGiftIds: hiddenGiftIds,
    secretGiftIds: Set.unmodifiable(secretIds),
    lockedBlocks: List.unmodifiable(locked),
    openedScopes: Map.unmodifiable(opened),
    policies: Map.unmodifiable(policies),
  );
}

// ------------------------------------------- regalos públicos de protegidos

/// Se intentó añadir al documento común un regalo para una persona
/// protegida.
class ProtectedPersonException implements Exception {
  /// Crea el error.
  const ProtectedPersonException(
    this.personId, {
    this.reason = ProtectedPersonReason.protectedPerson,
    this.savedLocally = false,
  });

  /// La persona protegida.
  final String personId;

  final ProtectedPersonReason reason;

  /// The editor may close: the gift is encrypted locally and can be retried.
  final bool savedLocally;

  @override
  String toString() => 'ProtectedPersonException($personId, ${reason.name})';
}

enum ProtectedPersonReason {
  protectedPerson,
  noEntitlement,
  noConfirmer,
  recipientUnavailable,
  requesterRevoked,
  requesterAmbiguous,
  requesterPending,
  registryUnavailable,
  ownRequestsRestricted,
  missingEpochKey,
  protectionPending,
  unreadableSlot,
  blockFull,
  giftTooLarge,
  writerSlotsFull,
  slotsFull,
  requiresV2,

  /// Capa de pantalla (1.0.6): este móvil es de esa persona y está
  /// acompañado, así que no ve ni escribe regalos para ella.
  ownGiftsHidden,

  /// La web (1.0.6, ADR 0009) ve los regalos en secreto de esa persona pero
  /// no puede cambiarlos ahora (le falta la clave con que sella su móvil, o
  /// el cambio pasa un regalo de una persona a otra): «hazlo desde el
  /// móvil».
  webUseMobile,
}

/// Si este móvil no debe escribir en el documento común regalos para
/// [personId]: tiene la protección pedida o puesta, o tiene su clave, slots
/// suyos o un registro de su política sin una política autenticada que diga
/// «publicar» (requisito 14 y hallazgo 3a). Un regalo así acabaría en el
/// bloque secreto, o a la vista de quien no debe. Con [alone] vale la
/// excepción del móvil solo ([lockedPolicy]).
bool publicGiftsBlockedFor({
  required FamilyDoc common,
  required SlotSet slots,
  required SurpriseKeyring keyring,
  required RegistryView view,
  required String personId,
  bool alone = false,
}) => lockedPolicy(
  common: common,
  slots: slots,
  view: view,
  personId: personId,
  hasKey: keyring.people.contains(personId),
  alone: alone,
).hideOwnGifts;

/// El único «común publicable»: lo que puede salir de este móvil (subida al
/// servidor, sobre de siempre o fichero de intercambio).
///
/// Parte siempre de [common] y solo quita los regalos **vivos** de las
/// personas con [publicGiftsBlockedFor]: un regalo público tardío que este
/// móvil no ha podido pasar aún al bloque secreto (no tiene la clave de la
/// época, hay un slot ajeno ilegible o no tiene derecho) no se publica. No
/// toca el común local: nada se pierde y se reconcilia cuando llegue la clave.
///
/// [remote] es el común que ya hay publicado: lo que ya está ahí, vivo, no se
/// quita (no se puede retirar y quitarlo solo crearía diferencias falsas).
/// Nunca parte de [AuthorizedProjection.doc], que arrastraría lápidas del
/// ámbito secreto.
FamilyDoc publishableCommon({
  required FamilyDoc common,
  required SlotSet slots,
  required SurpriseKeyring keyring,
  required RegistryView view,
  FamilyDoc? remote,
}) {
  final gifts = common.collections[Collections.gifts];
  if (gifts == null || gifts.isEmpty) return common;
  final remoteGifts = remote?.collections[Collections.gifts];
  final blocked = <String, bool>{};
  bool isBlocked(String person) => blocked.putIfAbsent(
    person,
    () => publicGiftsBlockedFor(
      common: common,
      slots: slots,
      keyring: keyring,
      view: view,
      personId: person,
    ),
  );
  final kept = <String, SyncRecord>{...gifts};
  var removed = false;
  for (final entry in gifts.entries) {
    final record = entry.value;
    if (record.isDeleted) continue;
    final person = record['recipientId'];
    if (person is! String) continue;
    // Los regalos que el móvil de la propia persona escribió para sí sin
    // conexión ya están en ese móvil: no se filtra nada y no quedan en el
    // limbo (N2).
    if (view.myPerson == person) continue;
    if (!isBlocked(person)) continue;
    final already = remoteGifts?[entry.key];
    if (already != null && !already.isDeleted) continue;
    kept.remove(entry.key);
    removed = true;
  }
  if (!removed) return common;
  return FamilyDoc(
    listId: common.listId,
    collections: {...common.collections, Collections.gifts: kept},
  );
}

/// Añade (o edita) un regalo en el documento común. Lanza
/// [ProtectedPersonException] si es para una persona protegida
/// ([publicGiftsBlockedFor]): quien tiene la clave lo añade al bloque
/// secreto con `addSurpriseGift`, y quien no la tiene no puede añadirlo.
FamilyDoc addPublicGift({
  required FamilyDoc common,
  required HlcClock clock,
  required SlotSet slots,
  required SurpriseKeyring keyring,
  required RegistryView view,
  required String giftId,
  required Map<String, Object?> fields,
  bool alone = false,
}) {
  final previous = common.record(Collections.gifts, giftId);
  for (final person in {fields['recipientId'], previous?['recipientId']}) {
    if (person is String &&
        publicGiftsBlockedFor(
          common: common,
          slots: slots,
          keyring: keyring,
          view: view,
          personId: person,
          alone: alone,
        )) {
      throw ProtectedPersonException(person);
    }
  }
  return common.setChanged(clock, Collections.gifts, giftId, fields);
}

// ------------------------------------------------------------- transiciones

/// El resultado de una transición: el documento común nuevo, la instantánea
/// nueva del ámbito (para el slot de este escritor) y la política que va en
/// los dos.
class ProtectionTransition {
  /// Crea el resultado.
  const ProtectionTransition({
    required this.common,
    required this.scope,
    required this.policy,
    this.overflow = const <SyncRecord>[],
  });

  /// Documento común nuevo.
  final FamilyDoc common;

  /// Documento del ámbito nuevo (se sella en el slot de este escritor).
  final FamilyDoc scope;

  /// Política que va en el slot y en el documento común.
  final PolicyState policy;

  /// Regalos públicos de la persona protegida que se quitaron del documento
  /// común pero no entraron en el bloque secreto (demasiado texto, o el cupo
  /// lleno), con su contenido. Quien llama los guarda en local, cifrados
  /// (`FamilyStore.saveOverflow`), y avisa: quitarlos del común nunca
  /// depende de cuántos secretos haya (A2) y su contenido no se pierde
  /// (N2, N4).
  final List<SyncRecord> overflow;

  /// Los ids de [overflow].
  List<String> get droppedGiftIds => [for (final r in overflow) r.id];
}

/// El id con el que se publica un regalo que sale del bloque secreto.
///
/// Es un UUID de la versión 8 (RFC 9562) hecho con los 16 primeros bytes de
/// SHA-256("gift-huddle-publish-v1" ‖ 0 ‖ lista ‖ 0 ‖ persona ‖ 0 ‖ id ‖ 0 ‖
/// sal ‖ 0 ‖ revisión). No lleva clave, así que no cambia con las épocas ni
/// con la candidata con la que selle cada móvil; no se puede adivinar sin
/// abrir el bloque porque el id de un regalo creado en secreto no se conoce
/// fuera, y el de uno que vino del común lleva una sal ([kPublishSaltField])
/// que solo está dentro (B2).
String publishedGiftId({
  required String listId,
  required String personId,
  required String giftId,
  required String salt,
  required int rev,
}) {
  final input = utf8.encode(
    [
      'gift-huddle-publish-v1',
      listId,
      personId,
      giftId,
      salt,
      '$rev',
    ].join('\u0000'),
  );
  final b = Uint8List.fromList(
    const DartSha256().hashSync(input).bytes.sublist(0, 16),
  );
  b[6] = (b[6] & 0x0F) | 0x80;
  b[8] = (b[8] & 0x3F) | 0x80;
  final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// La sal de un regalo que entra en el bloque secreto desde el común:
/// HMAC-SHA256(subclave, "gift-huddle-salt-v1" ‖ 0 ‖ lista ‖ 0 ‖ id ‖ 0 ‖
/// revisión) en base64url (16 bytes), con
/// subclave = HMAC-SHA256(surpriseKey, "gift-huddle-move-id-v1").
String _publishSalt(SurpriseKey key, String listId, String giftId, int rev) {
  final subkey = _hmacSha256(key.bytes, utf8.encode('gift-huddle-move-id-v1'));
  return encodeBase64Url(
    _hmacSha256(
      subkey,
      utf8.encode(
        ['gift-huddle-salt-v1', listId, giftId, '$rev'].join('\u0000'),
      ),
    ).sublist(0, 16),
  );
}

/// HMAC-SHA256 compartido (`hmac.dart`).
List<int> _hmacSha256(List<int> key, List<int> message) =>
    hmacSha256(key, message);

/// [_hmacSha256], para comprobarlo con los vectores del RFC 4231.
@visibleForTesting
List<int> hmacSha256ForTesting(List<int> key, List<int> message) =>
    _hmacSha256(key, message);

/// Pone [clock] por delante de todo lo que hay en [doc]. Una marca
/// demasiado adelantada se ignora, como en `HlcClock.receive`.
void _receiveMax(HlcClock clock, FamilyDoc doc) {
  final stamp = doc.maxStamp;
  if (stamp == null) return;
  try {
    clock.receive(stamp);
  } on HlcDriftException {
    // El reloj no se mueve: la marca se ignora.
  }
}

/// Quita del común un regalo público de la persona protegida y lo mete en
/// el bloque secreto si cabe; si no, lo deja en [overflow].
({FamilyDoc common, FamilyDoc scope}) _moveIn({
  required FamilyDoc common,
  required FamilyDoc scope,
  required SyncRecord record,
  required SurpriseKey key,
  required int rev,
  required HlcClock publicClock,
  required bool reconciled,
  required List<SyncRecord> overflow,
}) {
  final nextCommon = common.delete(publicClock, Collections.gifts, record.id);
  final hasRoom = reconciled
      ? liveMovedInGifts(scope) < kMaxReconcileGifts
      : liveOwnSurpriseGifts(scope) < kMaxSurpriseGifts ||
            liveMovedInGifts(scope) < kMaxReconcileGifts;
  final asReconciled =
      reconciled || liveOwnSurpriseGifts(scope) >= kMaxSurpriseGifts;
  // Un id que ya fue del bloque secreto y se borró allí no puede volver; si
  // ya está dentro (lo movió otro móvil a la vez) no gasta cupo.
  final existing = scope.record(Collections.gifts, record.id);
  final clash = existing?.isDeleted ?? false;
  if ((hasRoom || existing != null) && !clash) {
    var stamp = record.fields.values.first.stamp;
    for (final field in record.fields.values) {
      if (field.stamp.compareTo(stamp) > 0) stamp = field.stamp;
    }
    final moved = SyncRecord(
      id: record.id,
      fields: {
        ...record.fields,
        kPublishSaltField: FieldValue(
          value: _publishSalt(key, common.listId, record.id, rev),
          stamp: stamp,
        ),
        if (asReconciled) kMovedInField: FieldValue(value: true, stamp: stamp),
      },
    );
    final candidate = scope.merge(
      FamilyDoc(
        listId: common.listId,
        collections: {
          Collections.gifts: {record.id: moved},
        },
      ),
    );
    final merged = candidate.record(Collections.gifts, record.id)!;
    if (surpriseRecordBytes(merged) <= kMaxSurpriseGiftBytes &&
        scopeFitsInSlot(candidate, key.personId)) {
      return (common: nextCommon, scope: candidate);
    }
  }
  overflow.add(record);
  return (common: nextCommon, scope: scope);
}

/// Activa la protección de la persona de [key] (lo hace un móvil con
/// derecho, que la creó o ya la tiene): mueve sus regalos públicos vivos al
/// bloque secreto, con sus marcas HLC y su mismo id, y borra los registros
/// públicos con el borrado que vacía el contenido. Publica la política nueva
/// con una revisión mayor que la autenticada.
///
/// Nunca falla por lo que haya escrito la persona protegida (N4): los
/// primeros [kMaxSurpriseGifts] por id entran en el cupo de la interfaz, los
/// siguientes en el de la reconciliación, y los que no caben o tienen
/// demasiado texto salen del común igualmente y se devuelven en `overflow`
/// para guardarlos en este móvil y avisar. Como es una función pura, la
/// interfaz puede mirar el resultado antes de aplicarlo.
ProtectionTransition activateProtection({
  required FamilyDoc common,
  required FamilyDoc scope,
  required SurpriseKey key,
  required HlcClock publicClock,
  required HlcClock scopeClock,
  PolicyState? authenticated,
}) {
  final personId = key.personId;
  _receiveMax(scopeClock, common);
  final policy = PolicyState(
    hideOwnGifts: true,
    rev: nextPolicyRev(authenticated: authenticated),
  );
  var nextCommon = common;
  var nextScope = scope;
  final overflow = <SyncRecord>[];
  for (final record in _publicGiftsOf(common, personId)) {
    final moved = _moveIn(
      common: nextCommon,
      scope: nextScope,
      record: record,
      key: key,
      rev: policy.rev,
      publicClock: publicClock,
      reconciled: false,
      overflow: overflow,
    );
    nextCommon = moved.common;
    nextScope = moved.scope;
  }
  return ProtectionTransition(
    common: writePublishedPolicy(nextCommon, publicClock, personId, policy),
    scope: nextScope,
    policy: policy,
    overflow: List.unmodifiable(overflow),
  );
}

/// Quita la protección de la persona de [key]: publica todos sus regalos
/// secretos (también los de años anteriores) y los borra del bloque secreto.
///
/// Solo la puede hacer un móvil que haya abierto el ámbito y tenga su
/// política autenticada: la revisión nueva va firmada en la cabecera de su
/// slot. Lanza [StateError] sin política autenticada.
ProtectionTransition deactivateProtection({
  required FamilyDoc common,
  required FamilyDoc scope,
  required SurpriseKey key,
  required HlcClock publicClock,
  required HlcClock scopeClock,
  required PolicyState? authenticated,
}) {
  if (authenticated == null) {
    throw StateError('quitar la protección exige la política autenticada');
  }
  _receiveMax(scopeClock, common);
  final policy = PolicyState(
    hideOwnGifts: false,
    rev: nextPolicyRev(authenticated: authenticated),
  );
  final moved = _publish(common, scope, key.personId, policy.rev, scopeClock);
  // Lo publicado trae marcas del reloj secreto: el reloj público las recibe,
  // para que lo que se edite después en público quede por delante (req. 24).
  _receiveMax(publicClock, moved.common);
  return ProtectionTransition(
    common: writePublishedPolicy(
      moved.common,
      publicClock,
      key.personId,
      policy,
    ),
    scope: moved.scope,
    policy: policy,
  );
}

/// Deja el documento común y el ámbito de acuerdo con la política después de
/// fusionar lo que llegó. [opened] es el ámbito abierto por este móvil y
/// [scope] su instantánea acumulativa (normalmente `opened.doc`).
/// - Con la protección puesta, quita del común como mucho
///   [kMaxReconcileMoves] regalos públicos de la persona, por orden de id, y
///   los mete en el bloque secreto en el cupo de la reconciliación
///   ([kMaxReconcileGifts]). Los que no caben (cupo lleno o demasiado texto)
///   se quitan igualmente y se devuelven en `overflow`: lo que cambia en el
///   común depende solo del común (A2) y nada se pierde (N2).
/// - Sin la protección, publica lo que quede vivo en lo que se pudo abrir del
///   bloque secreto, pero solo si eso lo dice una política autenticada (M1).
///   Lo de un slot que aún no se puede descifrar se publicará cuando se
///   pueda.
/// - Vuelve a publicar la política si la publicada no coincide.
///
/// Es idempotente: con lo mismo de entrada devuelve los mismos documentos.
ProtectionTransition reconcileProtection({
  required FamilyDoc common,
  required FamilyDoc scope,
  required OpenedScope opened,
  required SurpriseKey key,
  required HlcClock publicClock,
  required HlcClock scopeClock,
}) {
  final personId = key.personId;
  final published = publishedPolicy(common, personId);
  final effective = opened.effective(published);
  _receiveMax(scopeClock, common);
  var nextCommon = common;
  var nextScope = scope;
  final overflow = <SyncRecord>[];
  if (effective.hideOwnGifts) {
    final candidates = _publicGiftsOf(common, personId);
    for (final record in candidates.take(kMaxReconcileMoves)) {
      final moved = _moveIn(
        common: nextCommon,
        scope: nextScope,
        record: record,
        key: key,
        rev: effective.rev,
        publicClock: publicClock,
        reconciled: true,
        overflow: overflow,
      );
      nextCommon = moved.common;
      nextScope = moved.scope;
    }
  } else if (effective == opened.authenticatedPolicy) {
    final moved = _publish(
      nextCommon,
      nextScope,
      personId,
      effective.rev,
      scopeClock,
    );
    if (!identical(moved.common, nextCommon)) {
      _receiveMax(publicClock, moved.common);
    }
    nextCommon = moved.common;
    nextScope = moved.scope;
  }
  final current = publishedPolicy(nextCommon, personId) ?? PolicyState.initial;
  if (current != effective) {
    nextCommon = writePublishedPolicy(
      nextCommon,
      publicClock,
      personId,
      effective,
    );
  }
  return ProtectionTransition(
    common: nextCommon,
    scope: nextScope,
    policy: effective,
    overflow: List.unmodifiable(overflow),
  );
}

/// Los regalos públicos vivos de [personId], por orden de id.
List<SyncRecord> _publicGiftsOf(FamilyDoc common, String personId) => [
  for (final record
      in common.collections[Collections.gifts]?.values ?? const <SyncRecord>[])
    if (!record.isDeleted && record['recipientId'] == personId) record,
]..sort((a, b) => a.id.compareTo(b.id));

({FamilyDoc common, FamilyDoc scope}) _publish(
  FamilyDoc common,
  FamilyDoc scope,
  String personId,
  int rev,
  HlcClock scopeClock,
) {
  var nextCommon = common;
  var nextScope = scope;
  final records =
      scope.collections[Collections.gifts]?.values ?? const <SyncRecord>[];
  for (final record in records.toList()) {
    if (record.isDeleted) continue;
    final salt = record[kPublishSaltField];
    final id = publishedGiftId(
      listId: common.listId,
      personId: personId,
      giftId: record.id,
      salt: salt is String ? salt : '',
      rev: rev,
    );
    nextCommon = nextCommon.merge(
      FamilyDoc(
        listId: common.listId,
        collections: {
          Collections.gifts: {
            id: SyncRecord(
              id: id,
              fields: {
                for (final e in record.fields.entries)
                  if (e.key != kPublishSaltField && e.key != kMovedInField)
                    e.key: e.value,
              },
            ),
          },
        },
      ),
    );
    nextScope = nextScope.delete(scopeClock, Collections.gifts, record.id);
  }
  return (common: nextCommon, scope: nextScope);
}

// ------------------------------------------------------- buzón de una web

/// Por qué se rechaza entero el buzón de una web (1.0.6, ADR 0009).
enum WebInboxRejection {
  /// Más de [kMaxWebInboxRecords] registros.
  tooManyRecords,

  /// Más de [kMaxWebInboxTombstones] lápidas.
  tooManyTombstones,

  /// Registros de otra persona u otra colección.
  foreignRecords,

  /// Alguna marca va más de [kMaxHlcDrift] por delante de este reloj: si
  /// entrara, ganaría todas las fusiones futuras.
  futureStamp,
}

/// Lo que pasa al recoger el buzón de una web en el móvil de su persona.
class WebInboxAbsorption {
  /// Crea el resultado.
  const WebInboxAbsorption({
    required this.scope,
    this.applied = 0,
    this.discarded = 0,
    this.tombstones = 0,
    this.rejected,
    this.waiting = false,
  });

  /// El ámbito con lo recogido (el de entrada si no se recoge nada).
  final FamilyDoc scope;

  /// Registros aplicados: altas, ediciones y borrados.
  final int applied;

  /// Registros descartados: ediciones o borrados de un regalo que no existe
  /// o que ya es una lápida, y altas de un regalo borrado.
  final int discarded;

  /// Lápidas aplicadas (cuentan para [kMaxWebTombstonesPerDay]).
  final int tombstones;

  /// Si se rechaza entero, por qué; entonces no se recoge nunca.
  final WebInboxRejection? rejected;

  /// Si no se puede recoger todavía (no caben más lápidas hoy o el ámbito
  /// pasaría de [kMaxSurpriseGifts]): el buzón espera.
  final bool waiting;

  /// Si se recogió (aunque fuera para descartarlo todo).
  bool get absorbed => rejected == null && !waiting;
}

/// Campos que una web no escribe nunca (revisión de seguridad, B6): la marca
/// del alta, la del cupo de la reconciliación y la sal de publicación. Un
/// buzón los trae, como mucho, copiados del ámbito; al recoger se ignoran.
const _webReservedFields = {kWebNewField, kMovedInField, kPublishSaltField};

SyncRecord _withoutWebNew(SyncRecord record) =>
    record.fields.keys.any(_webReservedFields.contains)
    ? SyncRecord(
        id: record.id,
        fields: {
          for (final e in record.fields.entries)
            if (!_webReservedFields.contains(e.key)) e.key: e.value,
        },
      )
    : record;

/// Aplica el buzón abierto [inbox] de una web sobre [scope], el ámbito ya
/// fusionado de su persona protegida (1.0.6, ADR 0009). Función pura.
///
/// Se valida entero o se rechaza entero ([WebInboxRejection]). Después,
/// registro a registro: un alta (`webNew`) de un id que no existe entra; un
/// registro de un id vivo se fusiona por campo; una lápida de un id vivo lo
/// borra; todo lo demás (un id que no existe y no es alta, o que ya es una
/// lápida) se descarta. Así no resucita un regalo cuya lápida ya se
/// compactó, sin tocar la compactación. [tombstoneBudget] son las lápidas de
/// webs que este móvil aún puede recoger hoy.
WebInboxAbsorption absorbWebInbox({
  required FamilyDoc scope,
  required OpenedSlot inbox,
  required int nowMillis,
  int tombstoneBudget = kMaxWebTombstonesPerDay,
}) {
  if (inbox.foreignRecords > 0) {
    return WebInboxAbsorption(
      scope: scope,
      rejected: WebInboxRejection.foreignRecords,
    );
  }
  final records = [
    ...?inbox.doc.collections[Collections.gifts]?.values,
  ]..sort((a, b) => a.id.compareTo(b.id));
  if (records.length > kMaxWebInboxRecords) {
    return WebInboxAbsorption(
      scope: scope,
      rejected: WebInboxRejection.tooManyRecords,
    );
  }
  if (records.where((r) => r.isDeleted).length > kMaxWebInboxTombstones) {
    return WebInboxAbsorption(
      scope: scope,
      rejected: WebInboxRejection.tooManyTombstones,
    );
  }
  final limit = nowMillis + kMaxHlcDrift.inMilliseconds;
  for (final record in records) {
    if (record.fields.values.any((f) => f.stamp.millis > limit)) {
      return WebInboxAbsorption(
        scope: scope,
        rejected: WebInboxRejection.futureStamp,
      );
    }
  }
  var next = scope;
  var applied = 0;
  var discarded = 0;
  var tombstones = 0;
  for (final record in records) {
    final existing = scope.record(Collections.gifts, record.id);
    final apply = existing == null
        ? !record.isDeleted && record[kWebNewField] == true
        : !existing.isDeleted;
    if (!apply) {
      discarded++;
      continue;
    }
    final clean = _withoutWebNew(record);
    final merged = next.merge(
      FamilyDoc(
        listId: scope.listId,
        collections: {
          Collections.gifts: {clean.id: clean},
        },
      ),
    );
    // Lo fusionado tiene que seguir cabiendo en un regalo (revisión final,
    // B7): campos nuevos de la web podrían hacerlo crecer y dejarlo fuera
    // del slot, a él y a los que van detrás.
    final result = merged.record(Collections.gifts, record.id)!;
    if (!result.isDeleted &&
        surpriseRecordBytes(result) > kMaxSurpriseGiftBytes) {
      discarded++;
      continue;
    }
    if (record.isDeleted) tombstones++;
    next = merged;
    applied++;
  }
  if (tombstones > tombstoneBudget ||
      (liveOwnSurpriseGifts(next) > kMaxSurpriseGifts &&
          liveOwnSurpriseGifts(next) > liveOwnSurpriseGifts(scope))) {
    return WebInboxAbsorption(scope: scope, waiting: true);
  }
  return WebInboxAbsorption(
    scope: next,
    applied: applied,
    discarded: discarded,
    tombstones: tombstones,
  );
}

/// Una acción de la web pendiente para el buzón de una persona.
class WebInboxEntry {
  /// Crea la entrada.
  const WebInboxEntry({
    required this.id,
    required this.delta,
    this.newGifts = const <String>{},
  });

  /// Id de la entrada en la cola de la web.
  final String id;

  /// Lo que escribió la acción (solo regalos de una persona).
  final FamilyDoc delta;

  /// Regalos que la acción creó (no existían antes en la web).
  final Set<String> newGifts;
}

/// El contenido del buzón de una web para una persona y qué entradas van
/// dentro (1.0.6, ADR 0009).
class WebInboxBuild {
  /// Crea el resultado.
  const WebInboxBuild({
    required this.doc,
    required this.included,
    required this.moot,
    required this.discarded,
    required this.deferred,
  });

  /// Los registros del buzón: los regalos tocados, completos como los ve la
  /// web, con `webNew` en las altas.
  final FamilyDoc doc;

  /// Entradas que van en el buzón.
  final List<String> included;

  /// Entradas que ya no hacen nada: solo tocan regalos que ya son lápidas.
  final List<String> moot;

  /// Entradas que no se pueden aplicar (editan un regalo que ya no existe,
  /// lo pasan a otra persona o no cabe en un regalo): se descartan con
  /// aviso.
  final List<String> discarded;

  /// Entradas que esperan al siguiente buzón (topes de registros y
  /// lápidas).
  final List<String> deferred;

  /// Si el buzón no lleva nada.
  bool get isEmpty => included.isEmpty;
}

/// Construye el buzón de [personId] desde [scope] (el ámbito fusionado de
/// los slots de los móviles, tal como lo abre la web) y las [entries]
/// pendientes, en orden. Función pura: no cifra nada.
WebInboxBuild buildWebInbox({
  required String personId,
  required FamilyDoc scope,
  required List<WebInboxEntry> entries,
}) {
  var work = scope;
  final touched = <String>{};
  final created = <String>{};
  final included = <String>[];
  final moot = <String>[];
  final discarded = <String>[];
  final deferred = <String>[];
  var full = false;
  for (final entry in entries) {
    if (full) {
      deferred.add(entry.id);
      continue;
    }
    final gifts =
        entry.delta.collections[Collections.gifts] ??
        const <String, SyncRecord>{};
    var dead = 0;
    var unknown = false;
    for (final record in gifts.values) {
      final existing = work.record(Collections.gifts, record.id);
      if (existing?.isDeleted ?? false) {
        dead++;
      } else if (existing == null && !entry.newGifts.contains(record.id)) {
        unknown = true;
      }
    }
    if (gifts.isEmpty || dead == gifts.length) {
      moot.add(entry.id);
      continue;
    }
    if (unknown) {
      discarded.add(entry.id);
      continue;
    }
    final next = work.merge(
      FamilyDoc(listId: work.listId, collections: {Collections.gifts: gifts}),
    );
    final ids = {...touched, ...gifts.keys};
    var tombstones = 0;
    var bad = false;
    for (final id in ids) {
      final record = next.record(Collections.gifts, id)!;
      // Un alta lleva además `webNew` (B7): se mide con él.
      final creates =
          (created.contains(id) || entry.newGifts.contains(id)) &&
          scope.record(Collections.gifts, id) == null;
      if (record.isDeleted) {
        tombstones++;
      } else if (record['recipientId'] != personId ||
          surpriseRecordBytes(creates ? _withWebNew(record) : record) >
              kMaxSurpriseGiftBytes) {
        bad = true;
      }
    }
    if (bad) {
      discarded.add(entry.id);
      continue;
    }
    if (ids.length > kMaxWebInboxRecords ||
        tombstones > kMaxWebInboxTombstones) {
      full = true;
      deferred.add(entry.id);
      continue;
    }
    work = next;
    touched.addAll(gifts.keys);
    for (final id in gifts.keys) {
      if (entry.newGifts.contains(id) &&
          scope.record(Collections.gifts, id) == null) {
        created.add(id);
      }
    }
    included.add(entry.id);
  }
  final out = <String, SyncRecord>{};
  for (final id in touched) {
    final record = work.record(Collections.gifts, id)!;
    out[id] = created.contains(id) && !record.isDeleted
        ? _withWebNew(record)
        : record;
  }
  return WebInboxBuild(
    doc: FamilyDoc(
      listId: scope.listId,
      collections: {Collections.gifts: out},
    ),
    included: included,
    moot: moot,
    discarded: discarded,
    deferred: deferred,
  );
}

SyncRecord _withWebNew(SyncRecord record) {
  Hlc? newest;
  for (final f in record.fields.values) {
    if (newest == null || f.stamp > newest) newest = f.stamp;
  }
  return SyncRecord(
    id: record.id,
    fields: {
      ...record.fields,
      kWebNewField: FieldValue(value: true, stamp: newest!),
    },
  );
}
