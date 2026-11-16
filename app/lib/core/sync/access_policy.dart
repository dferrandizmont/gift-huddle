// Política de sorpresas por persona y claves de sorpresa. Dart puro.
// Decisión: docs/adr/0004-yo-sorpresas-revocar.md (fase 1).
//
// - La política pública va en el documento común, colección `policies`, un
//   registro por persona protegida (id = id de la persona):
//     hideOwnGifts: bool, rev: int
//   Los dos campos se escriben siempre juntos, con la misma marca HLC, así
//   que la fusión por campo los mantiene emparejados.
// - Cada slot de sorpresas lleva además, en su cabecera firmada (que es el
//   AAD del cifrado), la política con la que se escribió. Esa es la política
//   autenticada: la firma un móvil con derecho a esas sorpresas según el
//   registro de móviles, y la puede comprobar cualquiera sin la clave, así
//   que un móvil autorizado que todavía no la tiene no se cree la publicada
//   (revisión de seguridad, N1).
// - Activar no necesita autenticación (ocultar más nunca filtra nada).
//   Desactivar, sí: solo cuenta la de la cabecera de un slot. Así, ni la
//   persona protegida ni un sobre antiguo pueden publicar las sorpresas.
// - `surpriseKey(personId, epoch)` son 32 bytes aleatorios; nunca se derivan
//   de la `familyKey`.
library;

import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import 'device_keys.dart';
import 'envelope.dart' show decodeBase64Url, encodeBase64Url;
import 'family_doc.dart';
import 'hlc.dart';
import 'model.dart' show Collections;

/// Campo de la política: si los regalos de la persona se le ocultan.
const String kHideOwnGiftsField = 'hideOwnGifts';

/// Campo de la política: revisión, que sube en cada activación o
/// desactivación.
const String kPolicyRevField = 'rev';

/// Revisión más alta admitida (cabe en un entero de JavaScript).
const int kMaxPolicyRev = 0x1FFFFFFFFFFFFF;

/// Estado de la protección de una persona en una revisión.
class PolicyState implements Comparable<PolicyState> {
  /// Crea el estado. La revisión va de 0 a [kMaxPolicyRev].
  const PolicyState({required this.hideOwnGifts, required this.rev})
    : assert(rev >= 0 && rev <= kMaxPolicyRev);

  /// Sin protección y sin ninguna transición todavía.
  static const PolicyState initial = PolicyState(hideOwnGifts: false, rev: 0);

  /// Si los regalos de la persona se le ocultan.
  final bool hideOwnGifts;

  /// Revisión de la política.
  final int rev;

  /// Orden total: revisión mayor primero; con la misma revisión, ocultar
  /// gana a publicar (lo prudente).
  @override
  int compareTo(PolicyState other) {
    if (rev != other.rev) return rev.compareTo(other.rev);
    if (hideOwnGifts == other.hideOwnGifts) return 0;
    return hideOwnGifts ? 1 : -1;
  }

  /// El mayor de los dos según [compareTo].
  PolicyState max(PolicyState other) => compareTo(other) >= 0 ? this : other;

  /// `{"h": bool, "r": int}`, como va dentro de un slot.
  Map<String, Object?> toJson() => <String, Object?>{
    'h': hideOwnGifts,
    'r': rev,
  };

  /// Lee [toJson]. Lanza [FormatException] si no vale.
  factory PolicyState.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('política no válida');
    final h = json['h'];
    final r = json['r'];
    if (h is! bool || r is! int || r < 0 || r > kMaxPolicyRev) {
      throw const FormatException('política no válida');
    }
    return PolicyState(hideOwnGifts: h, rev: r);
  }

  @override
  bool operator ==(Object other) =>
      other is PolicyState &&
      other.hideOwnGifts == hideOwnGifts &&
      other.rev == rev;

  @override
  int get hashCode => Object.hash(hideOwnGifts, rev);

  @override
  String toString() => 'PolicyState(hide: $hideOwnGifts, rev: $rev)';
}

/// La política publicada de [personId] en el documento común, o null si no
/// hay registro.
///
/// Un registro borrado o roto se lee como «ocultar» (falla en cerrado): una
/// lápida en `policies/<persona>` no puede apagar la protección.
PolicyState? publishedPolicy(FamilyDoc common, String personId) {
  final record = common.record(Collections.policies, personId);
  if (record == null) return null;
  if (record.isDeleted) return _brokenPolicy;
  final hide = record[kHideOwnGiftsField];
  final rev = record[kPolicyRevField];
  if (hide is! bool || rev is! int || rev < 0 || rev > kMaxPolicyRev) {
    return _brokenPolicy;
  }
  return PolicyState(hideOwnGifts: hide, rev: rev);
}

const _brokenPolicy = PolicyState(hideOwnGifts: true, rev: 0);

/// Todas las políticas publicadas, por persona.
Map<String, PolicyState> publishedPolicies(FamilyDoc common) {
  final out = <String, PolicyState>{};
  for (final id
      in common.collections[Collections.policies]?.keys ?? const <String>[]) {
    final policy = publishedPolicy(common, id);
    if (policy != null) out[id] = policy;
  }
  return out;
}

/// Escribe la política publicada de [personId] (los dos campos con la misma
/// marca). Si el registro es una lápida no se puede escribir y devuelve el
/// mismo documento, así que reconciliar sigue siendo idempotente.
FamilyDoc writePublishedPolicy(
  FamilyDoc common,
  HlcClock clock,
  String personId,
  PolicyState policy,
) {
  if (common.record(Collections.policies, personId)?.isDeleted ?? false) {
    return common;
  }
  return common.set(clock, Collections.policies, personId, <String, Object?>{
    kHideOwnGiftsField: policy.hideOwnGifts,
    kPolicyRevField: policy.rev,
  });
}

int _bump(int rev) => rev >= kMaxPolicyRev ? kMaxPolicyRev : rev + 1;

/// La política que vale para un móvil.
///
/// [authenticated] es la mayor de las políticas de los slots abiertos, o
/// null si no hay ninguno. La publicada solo sirve para pedir **activar**:
/// con una revisión mayor que la autenticada vale como «autenticada + 1»
/// (nunca con su número, que cualquiera puede inflar). Desactivar exige una
/// política autenticada.
///
/// Sin política autenticada, la respuesta es «ocultar» con [failClosed] (el
/// móvil tiene la clave de la persona, o hay slots suyos) y también si hay
/// cualquier registro `policies/<persona>`, diga lo que diga: un «publicar»
/// solo vale firmado, y sin slots que cuenten (podados, o de escritores que
/// este móvil no acepta) no hay quien lo firme (hallazgo 3a). Solo sin
/// registro, ni slots, ni clave, no hay protección.
PolicyState effectivePolicy({
  PolicyState? published,
  PolicyState? authenticated,
  bool failClosed = false,
}) {
  if (authenticated == null) {
    if (failClosed || published != null) {
      return const PolicyState(hideOwnGifts: true, rev: 1);
    }
    return PolicyState.initial;
  }
  if (published != null &&
      published.hideOwnGifts &&
      published.rev > authenticated.rev) {
    return PolicyState(hideOwnGifts: true, rev: _bump(authenticated.rev));
  }
  return authenticated;
}

/// La revisión de la siguiente transición de un móvil con la clave: una más
/// que la autenticada, o 1 si todavía no hay ninguna. Nunca se agota: se
/// queda en [kMaxPolicyRev].
int nextPolicyRev({PolicyState? authenticated}) =>
    authenticated == null ? 1 : _bump(authenticated.rev);

/// Pide activar la protección de [personId] desde un móvil sin la clave
/// (o antes de que exista): publica «ocultar» con una revisión mayor que la
/// publicada y que la autenticada de los slots ([authenticated]), si la hay.
/// Si ya está pedida, devuelve el mismo documento.
FamilyDoc requestProtection(
  FamilyDoc common,
  HlcClock clock,
  String personId, {
  PolicyState? authenticated,
}) {
  final current = publishedPolicy(common, personId);
  if (current != null && current.hideOwnGifts) return common;
  final base = [
    current?.rev ?? 0,
    authenticated?.rev ?? 0,
  ].reduce((a, b) => a > b ? a : b);
  return writePublishedPolicy(
    common,
    clock,
    personId,
    PolicyState(hideOwnGifts: true, rev: _bump(base)),
  );
}

/// Las personas que existen (no son lápidas) en el documento común.
Set<String> livePeopleOf(FamilyDoc common) => {
  for (final record
      in common.collections[Collections.recipients]?.values ??
          const <SyncRecord>[])
    if (!record.isDeleted) record.id,
};

// Quién puede recibir una clave de sorpresas o escribir slots lo decide un
// solo predicado, `RegistryView.entitled` (device_registry.dart).

// -------------------------------------------------------- claves sorpresa

/// Ámbito de una clave simétrica: la de la familia o la de sorpresas de una
/// persona.
abstract final class KeyScope {
  /// Ámbito de la `familyKey`.
  static const String family = 'family';

  /// Prefijo de los ámbitos de sorpresas.
  static const String surprisePrefix = 'surprise:';

  /// Ámbito de las sorpresas de [personId].
  static String surprise(String personId) => '$surprisePrefix$personId';

  /// La persona de un ámbito de sorpresas, o null si es otro ámbito.
  static String? personOf(String scope) => scope.startsWith(surprisePrefix)
      ? scope.substring(surprisePrefix.length)
      : null;

  /// Si [scope] es un ámbito válido.
  static bool isValid(String scope) {
    if (scope == family) return true;
    final person = personOf(scope);
    return person != null && kSyncIdPattern.hasMatch(person);
  }
}

/// Destinatarios que admite una clave (móviles que la conocen).
const int kMaxKeyAudience = 64;

/// Clave de las sorpresas de una persona en una época: 32 bytes aleatorios,
/// nunca derivados de la `familyKey`. Nunca aparece en `toString()`.
///
/// Lleva su **audiencia**: los móviles que la conocen (quien la creó y a
/// quienes se repartió), firmada en cada paquete. Solo se sella con una
/// clave cuya audiencia sigue entera con derecho a ojos de este móvil: dos
/// registros distintos con la misma época no pueden colar una candidata que
/// conoce un revocado (hallazgo 7). Una clave sin audiencia no sirve para
/// sellar.
class SurpriseKey {
  /// Crea la clave. Lanza [ArgumentError] si algo no vale.
  SurpriseKey({
    required this.personId,
    required this.epoch,
    required List<int> bytes,
    Iterable<String> audience = const <String>[],
  }) : _bytes = Uint8List.fromList(bytes),
       audience = List.unmodifiable(audience.toSet().toList()..sort()) {
    if (_bytes.length != 32) {
      throw ArgumentError.value(_bytes.length, 'bytes', 'debe tener 32 bytes');
    }
    if (!kSyncIdPattern.hasMatch(personId)) {
      throw ArgumentError.value(personId, 'personId', 'id no válido');
    }
    if (epoch < 1 || epoch > 0xFFFFFFFF) {
      throw ArgumentError.value(epoch, 'epoch', 'época fuera de rango');
    }
    if (this.audience.length > kMaxKeyAudience ||
        !this.audience.every(kSyncIdPattern.hasMatch)) {
      throw ArgumentError.value(audience, 'audience', 'no válida');
    }
  }

  /// Una clave nueva y aleatoria, que conocen los móviles de [audience].
  factory SurpriseKey.generate(
    String personId,
    int epoch, {
    Iterable<String> audience = const <String>[],
  }) => SurpriseKey(
    personId: personId,
    epoch: epoch,
    bytes: secureRandomBytes(32),
    audience: audience,
  );

  /// Los móviles que conocen la clave, ordenados.
  final List<String> audience;

  /// La misma clave, que además conocen los de [more].
  SurpriseKey withAudience(Iterable<String> more) => SurpriseKey(
    personId: personId,
    epoch: epoch,
    bytes: _bytes,
    audience: [...audience, ...more],
  );

  /// Si se puede sellar con ella cuando tienen derecho los de [allowed]:
  /// toda su audiencia sigue teniéndolo.
  bool sealableFor(Set<String> allowed) =>
      audience.isNotEmpty && audience.every(allowed.contains);

  /// Persona protegida.
  final String personId;

  /// Época de la clave (sube al revocar un móvil, en la fase 2).
  final int epoch;

  final Uint8List _bytes;

  /// Copia de los bytes.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// Identificador público de la clave (16 caracteres hexadecimales): los 8
  /// primeros bytes de SHA-256("gift-huddle-kid-v1" ‖ 0 ‖ persona ‖ 0 ‖
  /// época ‖ clave). Va en la cabecera de los slots para saber con cuál de
  /// las candidatas de una época se selló; no revela la clave.
  late final String kid = _kidOf(personId, epoch, _bytes);

  static String _kidOf(String personId, int epoch, List<int> bytes) {
    final hash = const DartSha256().hashSync([
      ...'gift-huddle-kid-v1'.codeUnits,
      0,
      ...personId.codeUnits,
      0,
      (epoch >> 24) & 0xFF,
      (epoch >> 16) & 0xFF,
      (epoch >> 8) & 0xFF,
      epoch & 0xFF,
      ...bytes,
    ]).bytes;
    return [for (final b in hash.take(8)) b.toRadixString(16).padLeft(2, '0')]
        .join();
  }

  /// `{"p":..., "e":..., "k":..., "a":[...]}` (contiene el secreto).
  Map<String, Object?> toJson() => <String, Object?>{
    'p': personId,
    'e': epoch,
    'k': encodeBase64Url(_bytes),
    'a': audience,
  };

  /// Lee [toJson]. Lanza [FormatException] si no vale.
  factory SurpriseKey.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('clave no válida');
    final p = json['p'];
    final e = json['e'];
    final k = json['k'];
    final a = json['a'];
    if (p is! String ||
        e is! int ||
        k is! String ||
        a is! List ||
        !a.every((x) => x is String)) {
      throw const FormatException('clave no válida');
    }
    try {
      return SurpriseKey(
        personId: p,
        epoch: e,
        bytes: decodeBase64Url(k),
        audience: a.cast<String>(),
      );
    } on ArgumentError {
      throw const FormatException('clave no válida');
    }
  }

  @override
  String toString() => 'SurpriseKey($personId, $epoch, …)';
}

/// Claves candidatas que caben por persona y época: como mucho una por móvil
/// con derecho. Con qué móviles tienen derecho, solo cuentan las que todavía
/// sirven para sellar (segunda revisión, 7).
const int kMaxKeyCandidates = 16;

/// Candidatas que se guardan como mucho por persona y época, contando las
/// que ya no sirven para sellar (solo para abrir slots viejos).
const int kMaxStoredKeyCandidates = 2 * kMaxKeyCandidates;

/// Se intentó meter en el llavero una clave de una época que el registro
/// todavía no ha abierto, o demasiadas candidatas.
class KeyringConflictException implements Exception {
  /// Crea el error.
  const KeyringConflictException(this.message);

  /// Qué pasó (sin claves).
  final String message;

  @override
  String toString() => 'KeyringConflictException: $message';
}

/// Las claves de sorpresa que tiene este móvil, por persona y época.
///
/// Para una misma persona y época puede haber varias **candidatas**: dos
/// móviles con derecho pueden crear clave a la vez (al activar la protección
/// o al rotar) sin saber uno del otro. No chocan: el llavero las guarda
/// todas, cada slot dice en su cabecera con cuál se selló ([SurpriseKey.kid])
/// y para sellar todos usan la de `kid` más bajo de las que tienen, así que
/// en cuanto se cruzan los paquetes todos sellan con la misma.
class SurpriseKeyring {
  /// Crea el llavero.
  SurpriseKeyring([Iterable<SurpriseKey> keys = const <SurpriseKey>[]])
    : _keys = Map<String, Map<int, Map<String, SurpriseKey>>>.unmodifiable({
        for (final person in {for (final k in keys) k.personId})
          person: Map<int, Map<String, SurpriseKey>>.unmodifiable({
            for (final epoch in {
              for (final k in keys)
                if (k.personId == person) k.epoch,
            })
              epoch: Map<String, SurpriseKey>.unmodifiable({
                for (final k in keys)
                  if (k.personId == person && k.epoch == epoch) k.kid: k,
              }),
          }),
      });

  /// El llavero vacío.
  static final SurpriseKeyring empty = SurpriseKeyring();

  final Map<String, Map<int, Map<String, SurpriseKey>>> _keys;

  /// La clave de [personId] en [epoch] con ese [kid], o null.
  SurpriseKey? keyFor(String personId, int epoch, String kid) =>
      _keys[personId]?[epoch]?[kid];

  /// La clave con la que se sella en [epoch] cuando tienen derecho los de
  /// [allowed]: de las candidatas cuya audiencia está entera en [allowed]
  /// ([SurpriseKey.sealableFor]), la de `kid` más bajo; o null si no hay
  /// ninguna (entonces toca crear otra: [rotateSurpriseKeys] lo hace).
  SurpriseKey? sealingKeyFor(
    String personId,
    int epoch, {
    required Iterable<String> allowed,
  }) {
    final candidates = _keys[personId]?[epoch];
    if (candidates == null) return null;
    final ok = allowed.toSet();
    final kids = [
      for (final e in candidates.entries)
        if (e.value.sealableFor(ok)) e.key,
    ]..sort();
    return kids.isEmpty ? null : candidates[kids.first];
  }

  /// Una clave de la época más alta de [personId] (la de `kid` más bajo), o
  /// null. Solo para saber si hay alguna: para sellar, [sealingKeyFor].
  SurpriseKey? latestFor(String personId) {
    final byEpoch = _keys[personId];
    if (byEpoch == null || byEpoch.isEmpty) return null;
    final candidates = byEpoch[byEpoch.keys.reduce((a, b) => a > b ? a : b)]!;
    return candidates[(candidates.keys.toList()..sort()).first];
  }

  /// Personas de las que hay alguna clave.
  Set<String> get people => _keys.keys.toSet();

  /// Todas las claves, ordenadas por persona, época y `kid`.
  List<SurpriseKey> get keys => [
    for (final person in _keys.keys.toList()..sort())
      for (final epoch in _keys[person]!.keys.toList()..sort())
        for (final kid in _keys[person]![epoch]!.keys.toList()..sort())
          _keys[person]![epoch]![kid]!,
  ];

  /// El llavero con [key] añadida como candidata de su época.
  ///
  /// Nunca reemplaza una clave: si ya la tiene, solo suma la audiencia de
  /// [key] a la suya (saber que más móviles la conocen es más prudente).
  /// [registryEpoch] es la época del registro de
  /// móviles: una clave de una época mayor no entra, porque una época nueva
  /// solo la abre una revocación o un cambio de persona firmados en el
  /// registro. Lanza [KeyringConflictException] en ese caso, o si ya hay
  /// [kMaxKeyCandidates] candidatas de esa persona y época.
  ///
  /// Con [allowed] (los móviles que ahora tienen derecho a esas sorpresas)
  /// solo cuentan para ese tope las candidatas que todavía sirven para sellar
  /// ([SurpriseKey.sealableFor]; segunda revisión, 7): las que conoce alguien
  /// que ya no tiene derecho no impiden crear otra al rotar. Para no crecer
  /// sin límite se guardan como mucho [kMaxStoredKeyCandidates]; si no cabe,
  /// se quita la que ya no sirve para sellar de `kid` más alto (solo servía
  /// para abrir slots viejos, que su escritor volverá a sellar).
  SurpriseKeyring withKey(
    SurpriseKey key, {
    required int registryEpoch,
    Iterable<String>? allowed,
  }) {
    if (key.epoch > registryEpoch) {
      throw const KeyringConflictException(
        'una época nueva solo llega con el registro de móviles',
      );
    }
    final candidates = _keys[key.personId]?[key.epoch];
    if (candidates != null) {
      final known = candidates[key.kid];
      if (known != null) {
        if (key.audience.every(known.audience.contains)) return this;
        final wider = known.withAudience(key.audience);
        return SurpriseKeyring([
          for (final k in keys)
            if (k.personId == key.personId &&
                k.epoch == key.epoch &&
                k.kid == key.kid)
              wider
            else
              k,
        ]);
      }
      if (allowed == null) {
        if (candidates.length >= kMaxKeyCandidates) {
          throw const KeyringConflictException(
            'demasiadas claves para esa persona y época',
          );
        }
      } else {
        final ok = allowed.toSet();
        final sealable = candidates.values.where((k) => k.sealableFor(ok));
        if (key.sealableFor(ok) && sealable.length >= kMaxKeyCandidates) {
          throw const KeyringConflictException(
            'demasiadas claves para esa persona y época',
          );
        }
        if (candidates.length >= kMaxStoredKeyCandidates) {
          final stale = [
            for (final e in candidates.entries)
              if (!e.value.sealableFor(ok)) e.key,
          ]..sort();
          if (stale.isEmpty) {
            throw const KeyringConflictException(
              'demasiadas claves para esa persona y época',
            );
          }
          return SurpriseKeyring([
            for (final k in keys)
              if (k.personId != key.personId ||
                  k.epoch != key.epoch ||
                  k.kid != stale.last)
                k,
            key,
          ]);
        }
      }
    }
    return SurpriseKeyring([...keys, key]);
  }

  /// El llavero sin ninguna clave de [personId].
  SurpriseKeyring without(String personId) => SurpriseKeyring([
    for (final k in keys)
      if (k.personId != personId) k,
  ]);

  /// `{"v":1,"keys":[...]}` (contiene secretos).
  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'keys': [for (final k in keys) k.toJson()],
  };

  /// Lee [toJson]. Lanza [FormatException] si no vale.
  factory SurpriseKeyring.fromJson(Object? json) {
    if (json is! Map || json['v'] != 1 || json['keys'] is! List) {
      throw const FormatException('llavero no válido');
    }
    return SurpriseKeyring([
      for (final k in json['keys'] as List) SurpriseKey.fromJson(k),
    ]);
  }

  @override
  String toString() => 'SurpriseKeyring(${_keys.length} personas)';
}
