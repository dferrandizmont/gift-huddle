// La web como extensión del móvil de su persona (1.0.6, ADR 0009): lee y
// escribe los regalos en secreto de los demás, nunca los de su persona.
//
// - Lectura (A.1-A.7): un móvil de la misma persona que la web, con derecho a
//   P y que avaló su ficha, le entrega la clave de cada P distinta de la suya
//   en un paquete v3 dirigido a la web (sin añadirla a la audiencia de la
//   candidata). La web abre esos paquetes con la vista de una raíz móvil de
//   su misma persona y baja los slots de los móviles con derecho. Las claves
//   y lo abierto viven solo en memoria de la sesión: al bloquear o cerrar la
//   pestaña se pierden y se rehacen al desbloquear.
// - Escritura (A.8): la web sella sus cambios pendientes de P en un slot
//   suyo (el buzón) que solo recogen los móviles de su persona. Ver
//   `absorbWebInbox` y `buildWebInbox` en `protected_doc.dart`.
library;

import '../../../core/sync/access_policy.dart';
import '../../../core/sync/device_keys.dart';
import '../../../core/sync/device_registry.dart';
import '../../../core/sync/key_bundle.dart';
import '../../../core/sync/protected_doc.dart';
import '../../../core/sync/protected_envelope.dart';
import '../../sync/data/sync_transport_v2.dart';

/// Qué puede hacer la web con los regalos en secreto ahora.
enum WebSecretsState {
  /// Todavía no se ha leído nada, o la web no está confirmada.
  off,

  /// La web no tiene persona: no ve ningún regalo en secreto.
  noPerson,

  /// Ningún móvil activo de su persona la verifica (lo han revocado o ha
  /// cambiado de persona): «vuelve a conectar este ordenador desde tu
  /// móvil».
  reconnect,

  /// Hay un móvil de su persona, pero todavía no le ha dado ninguna clave
  /// (aún no ha sincronizado, o sigue en la 1.0.5: «actualiza tu móvil»).
  waitingKeys,

  /// Ve los regalos en secreto de los demás.
  open,
}

/// Lo que la web sabe de los regalos en secreto durante una sesión. Nada de
/// esto se guarda: [clear] lo borra al bloquear, y al desbloquear se rehace.
class WebSecrets {
  /// La vista de la raíz móvil de la misma persona que la web.
  RegistryView? view;

  /// La persona de la web según su ficha.
  String? person;

  /// Las claves de las sorpresas de los demás, por persona y `kid`.
  SurpriseKeyring keyring = SurpriseKeyring.empty;

  /// Los slots de los móviles con derecho, verificados con [view].
  SlotSet slots = SlotSet.empty;

  /// Los ámbitos abiertos, por persona (nunca la de la web).
  Map<String, OpenedScope> opened = const {};

  /// Los buzones de esta web que hay en el servidor: persona -> versión.
  Map<String, int> ownInbox = const {};

  /// El estado para la interfaz.
  WebSecretsState state = WebSecretsState.off;

  final Map<String, (int, SealedSlot)> _cache = {};

  /// Borra todo lo de la sesión.
  void clear() {
    view = null;
    person = null;
    keyring = SurpriseKeyring.empty;
    slots = SlotSet.empty;
    opened = const {};
    ownInbox = const {};
    state = WebSecretsState.off;
    _cache.clear();
  }

  /// Si hay algún regalo en secreto abierto (bloqueo a los 5 minutos).
  bool get isOpen => opened.isNotEmpty;

  /// Las personas cuyos regalos en secreto ve la web.
  Set<String> get openedPeople => opened.keys.toSet();

  /// Si [writer] es un móvil activo de la persona de la web.
  bool ownPhone(String writer) {
    final device = view?.member(writer);
    return device != null &&
        device.kind == DeviceKind.mobile &&
        person != null &&
        device.personId == person;
  }

  /// La clave con la que la web sella el buzón de [personId]: la de un slot
  /// de un móvil de su persona en la época de ahora, si la tiene; si no, la
  /// que elegiría su móvil ([SurpriseKeyring.sealingKeyFor]).
  SurpriseKey? sealingKeyFor(String personId) {
    final v = view;
    if (v == null) return null;
    for (final slot in slots.slotsFor(personId)) {
      final h = slot.header;
      if (h.epoch != v.epoch || !ownPhone(h.writer)) continue;
      final key = keyring.keyFor(personId, h.epoch, h.kid);
      if (key != null) return key;
    }
    return keyring.sealingKeyFor(
      personId,
      v.epoch,
      allowed: v.entitledDevices(personId),
    );
  }

  /// Las personas cuyos regalos en secreto puede cambiar la web: abiertas,
  /// con «ocultar» autenticado y con clave para sellar.
  Set<String> get writablePeople => {
    for (final e in opened.entries)
      if (e.key != person &&
          e.value.authenticatedPolicy?.hideOwnGifts == true &&
          sealingKeyFor(e.key) != null)
        e.key,
  };

  /// Rehace lo de esta instantánea [snap]: elige la raíz de la persona de la
  /// web (desde [root], la raíz que verificó el registro), abre los paquetes
  /// dirigidos a la web y baja los slots que han cambiado. [webDeviceId] y
  /// [keys] son los de la web. [check] se llama tras cada espera: lanza si
  /// la sesión ya no vale.
  Future<void> refresh({
    required V2Snapshot snap,
    required DeviceRegistry registry,
    required RegistryView root,
    required String webDeviceId,
    required DeviceKeys keys,
    required SyncV2Transport transport,
    required V2Auth auth,
    required void Function() check,
  }) async {
    final web = root.member(webDeviceId);
    final mine = web != null && web.kind == DeviceKind.web
        ? web.personId
        : null;
    ownInbox = {
      for (final ref in snap.slots)
        if (ref.deviceId == webDeviceId) ref.personId: ref.version,
    };
    if (mine == null || !root.livePeople.contains(mine)) {
      _drop(WebSecretsState.noPerson);
      return;
    }
    RegistryView? chosen;
    if (root.self.kind == DeviceKind.mobile &&
        root.myPerson == mine &&
        !root.revokedByOthers) {
      chosen = root;
    } else {
      for (final id in root.members) {
        final device = root.member(id)!;
        if (device.kind != DeviceKind.mobile || device.personId != mine) {
          continue;
        }
        try {
          final v = await registry.viewFor(
            me: id,
            mySigningKey: device.signingKey,
            livePeople: root.livePeople,
          );
          check();
          if (!v.revokedByOthers && v.member(webDeviceId) != null) {
            chosen = v;
            break;
          }
        } on RegistryException {
          continue;
        }
      }
    }
    if (chosen == null) {
      _drop(WebSecretsState.reconnect);
      return;
    }
    var ring = SurpriseKeyring.empty;
    for (final raw in snap.keyPackages) {
      if (raw['v'] != 3 || raw['to'] != webDeviceId) continue;
      try {
        final bundle = KeyBundle.fromJson(raw);
        if (KeyScope.personOf(bundle.scope) == null) continue;
        final key = await bundle.openSurpriseKeyAsWeb(
          mine: keys,
          view: chosen,
          webDeviceId: webDeviceId,
        );
        check();
        ring = ring.withKey(
          key,
          registryEpoch: chosen.epoch,
          allowed: chosen.entitledDevices(key.personId),
        );
      } on KeyBundleException {
        continue;
      } on KeyringConflictException {
        continue;
      }
    }
    final wanted = <SealedSlot>[];
    final live = <String>{};
    for (final ref in snap.slots) {
      if (ref.personId == mine ||
          !ring.people.contains(ref.personId) ||
          chosen.entitled(ref.deviceId, ref.personId) == null) {
        continue;
      }
      live.add(ref.key);
      final cached = _cache[ref.key];
      if (cached != null && cached.$1 == ref.version) {
        wanted.add(cached.$2);
        continue;
      }
      final got = await transport.getSlot(
        auth,
        version: snap.version,
        personId: ref.personId,
        deviceId: ref.deviceId,
      );
      check();
      if (got is! V2SlotOk || got.slotVersion != ref.version) {
        // La instantánea se ha movido: se queda lo de antes, si lo había.
        if (cached != null) wanted.add(cached.$2);
        continue;
      }
      try {
        final slot = SealedSlot.parse(got.data);
        if (slot.header.personId != ref.personId ||
            slot.header.writer != ref.deviceId) {
          continue;
        }
        _cache[ref.key] = (ref.version, slot);
        wanted.add(slot);
      } on ProtectedEnvelopeException {
        continue;
      }
    }
    _cache.removeWhere((key, _) => !live.contains(key));
    final (verified, _) = await SlotSet.empty.merge(wanted, view: chosen);
    check();
    final scopes = <String, OpenedScope>{};
    for (final p in ring.people) {
      if (p == mine) continue;
      final scope = await openScope(
        personId: p,
        slots: verified,
        keyring: ring,
        view: chosen,
      );
      check();
      // Sin ningún slot legible (falta la clave con que sellan todos) la
      // persona no está abierta: se ve su bloque, no una lista vacía que
      // invitaría a duplicar sus regalos (revisión de seguridad, M2).
      if (scope != null && scope.parts.isNotEmpty) scopes[p] = scope;
    }
    view = chosen;
    person = mine;
    keyring = ring;
    slots = verified;
    opened = Map.unmodifiable(scopes);
    // Sin nada abierto: si hay sorpresas de alguien más, faltan sus claves.
    state =
        scopes.isEmpty &&
            snap.slots.any(
              (r) => r.personId != mine && r.deviceId != webDeviceId,
            )
        ? WebSecretsState.waitingKeys
        : WebSecretsState.open;
  }

  void _drop(WebSecretsState next) {
    final inbox = ownInbox;
    clear();
    ownInbox = inbox;
    state = next;
  }
}
