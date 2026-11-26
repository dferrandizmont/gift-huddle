/// Quién escribe un deseo (ADR 0010, 1.0.7).
///
/// La persona que actúa sale **solo de este dispositivo**: de su ficha en el
/// registro de móviles de la lista en la que se escribe, o, en un teléfono
/// que aún no se ha emparejado, de su identidad local. Quien llama nunca
/// elige otro dispositivo, otra persona ni otra lista: no hay parámetro para
/// ello, y cada operación de `wish.dart` vuelve a resolver el autor con el
/// [WishContext] que recibe (así un autor guardado de antes no se reutiliza
/// tras una revocación, un cambio de persona o en otra lista). Hay que
/// construir el contexto de nuevo desde el registro actual en cada escritura.
library;

import 'device_keys.dart';
import 'device_registry.dart';

/// Por qué este dispositivo no puede escribir deseos.
enum WishAuthorError {
  /// Este dispositivo no está en el registro, o las claves locales no son las
  /// de su ficha.
  unknownDevice,

  /// Su ficha actual no la ha avalado ningún dispositivo activo (recién
  /// llegado, cambió de persona), o, en una web, no la avaló un móvil de su
  /// misma persona.
  devicePending,

  /// Lo han revocado.
  deviceRevoked,

  /// Su id o su clave son ambiguos en el registro.
  deviceAmbiguous,

  /// Su ficha no tiene persona.
  noPerson,

  /// Su persona no existe (o ya no).
  personUnavailable,

  /// El registro o la identidad son de otra lista.
  wrongList,

  /// La atajo de un solo teléfono no vale: ya hay registro v2 o emparejamiento.
  singlePhoneNotAllowed,
}

/// Lo que guarda este móvil de sí mismo y la app lee de su `FamilyIdentity`
/// (`core/` no puede importar la capa de funciones). Solo sirve para un
/// teléfono sin registro v2.
final class LocalWishIdentity {
  /// Crea la identidad local.
  const LocalWishIdentity({
    required this.listId,
    required this.selfRecipientId,
    required this.paired,
  });

  /// Lista de este móvil.
  final String listId;

  /// «Este móvil es de» (`FamilyIdentity.selfRecipientId`), o null.
  final String? selfRecipientId;

  /// Si ya se emparejó alguna vez (`FamilyIdentity.paired`).
  final bool paired;
}

/// La persona que escribe, ya comprobada. Solo la crea [WishContext].
final class WishAuthor {
  const WishAuthor._(this.personId, this.listId, this.deviceId, this.digest);

  /// La persona dueña de este dispositivo aprobado.
  final String personId;

  /// La lista en la que vale.
  final String listId;

  /// El dispositivo, o null en un teléfono sin registro.
  final String? deviceId;

  /// Resumen de la ficha con la que se resolvió, o null sin registro.
  final String? digest;

  @override
  String toString() => 'WishAuthor($personId@$listId)';
}

/// El resultado de resolver al autor.
final class WishAuthorResult {
  const WishAuthorResult._(this.author, this.error);

  /// El autor, si este dispositivo puede escribir deseos.
  final WishAuthor? author;

  /// Por qué no puede, si no puede.
  final WishAuthorError? error;

  /// Si hay autor.
  bool get ok => author != null;
}

/// Con qué se resuelve el autor: este dispositivo y su registro **actual**.
///
/// El contexto no guarda una foto: guarda funciones que dan el estado vigente
/// (el registro de la lista, la identidad local) y las llama en cada
/// operación, al escribir. Así un contexto que se conserva deja de valer en
/// cuanto el registro conoce una revocación, un cambio de persona o un
/// emparejamiento.
///
/// Sobre la identidad del teléfono sin registro: la construye la propia app a
/// partir de su `FamilyIdentity`. Una app modificada por un familiar queda
/// fuera del modelo de amenazas (ADR 0010).
final class WishContext {
  const WishContext._({
    RegistryView Function()? view,
    this.keys,
    LocalWishIdentity? Function()? identity,
    DeviceRegistry? Function()? registry,
    Set<String> Function()? people,
    this.webId,
    // ignore: prefer_initializing_formals
  }) : _view = view,
       // ignore: prefer_initializing_formals
       _identity = identity,
       // ignore: prefer_initializing_formals
       _registry = registry,
       // ignore: prefer_initializing_formals
       _people = people;

  /// Contexto de un dispositivo con registro v2: [view] da el registro de la
  /// lista visto desde este dispositivo, **vigente en cada llamada**, y
  /// [localKeys] son sus claves locales (las de `view().self`), con las que se
  /// comprueba que la vista es la suya.
  factory WishContext.device({
    required RegistryView Function() view,
    required DeviceKeys localKeys,
  }) => WishContext._(view: view, keys: localKeys);

  /// Contexto de una web: el navegador ve la lista desde la raíz móvil que
  /// fijó al emparejarse ([rootView], vigente en cada llamada) y [webKeys] son
  /// sus claves locales. Solo vale si [webDeviceId] es una de las webs propias
  /// de esa raíz (`RegistryView.ownWebs`, ADR 0009): activa, de la misma
  /// persona y avalada por ese móvil siendo ya de esa persona. Una web que
  /// avaló el móvil de otra persona queda pendiente.
  factory WishContext.web({
    required RegistryView Function() rootView,
    required String webDeviceId,
    required DeviceKeys webKeys,
  }) => WishContext._(view: rootView, keys: webKeys, webId: webDeviceId);

  /// Contexto de un teléfono sin registro v2 ni emparejamiento: usa la misma
  /// fuente que la app para «Este móvil es de». Cada llamada lee [identity],
  /// [registry] y [livePeople] de nuevo. Se rechaza si hay algún registro con
  /// fichas o la identidad dice que ya se emparejó (entonces hay que usar
  /// [WishContext.device]).
  factory WishContext.singlePhone({
    required LocalWishIdentity? Function() identity,
    required DeviceRegistry? Function() registry,
    required Set<String> Function() livePeople,
  }) =>
      WishContext._(identity: identity, registry: registry, people: livePeople);

  final RegistryView Function()? _view;

  /// Claves locales (dispositivo o web).
  final DeviceKeys? keys;
  final LocalWishIdentity? Function()? _identity;
  final DeviceRegistry? Function()? _registry;
  final Set<String> Function()? _people;

  /// Id de la web, si es un contexto de web.
  final String? webId;

  /// Si [personId] tiene ahora un dispositivo **activo** (aprobado, ni
  /// pendiente ni revocado) en el registro: solo entonces se le puede
  /// sugerir un deseo visible. Un cambio de persona que nadie ha aprobado no
  /// cuenta.
  bool hasDevice(String personId) {
    final view = _view?.call();
    if (view == null) return false;
    return view.members.any((id) => view.member(id)?.personId == personId);
  }

  /// Resuelve el autor para escribir en la lista [listId], con el estado de
  /// este instante.
  WishAuthorResult resolve(String listId) {
    final source = _view;
    if (source != null) {
      final view = source();
      return webId != null ? _fromWeb(view, listId) : _fromView(view, listId);
    }
    final identity = _identity!();
    if (identity == null) return _no(WishAuthorError.singlePhoneNotAllowed);
    if (identity.listId != listId) return _no(WishAuthorError.wrongList);
    final registry = _registry!();
    if (registry != null && registry.listId != listId) {
      return _no(WishAuthorError.wrongList);
    }
    if (identity.paired || (registry != null && registry.records.isNotEmpty)) {
      return _no(WishAuthorError.singlePhoneNotAllowed);
    }
    final person = identity.selfRecipientId;
    if (person == null) return _no(WishAuthorError.noPerson);
    if (!kSyncIdPattern.hasMatch(person) || !_people!().contains(person)) {
      return _no(WishAuthorError.personUnavailable);
    }
    return WishAuthorResult._(WishAuthor._(person, listId, null, null), null);
  }

  WishAuthorResult _fromView(RegistryView view, String listId) {
    if (view.listId != listId) return _no(WishAuthorError.wrongList);
    final self = view.self;
    final mine = keys!.publicKeys.signing;
    if (self.deviceId != view.me ||
        self.signingKey.length != mine.length ||
        !_same(self.signingKey, mine)) {
      return _no(WishAuthorError.unknownDevice);
    }
    if (view.selfRevoked) return _no(WishAuthorError.deviceRevoked);
    if (view.revokedByOthers) return _no(WishAuthorError.deviceAmbiguous);
    // Una ficha que ningún móvil activo ha avalado no vale, salvo la del
    // fundador: el único móvil vivo (las webs y los revocados no cuentan).
    // Una web exige un móvil de su persona.
    final approved = self.kind == DeviceKind.web
        ? view.approvedBySamePersonMobile
        : view.aloneAmongLiveMobiles || view.approvedByActive;
    if (!approved) return _no(WishAuthorError.devicePending);
    final person = self.personId;
    if (person == null) return _no(WishAuthorError.noPerson);
    if (!kSyncIdPattern.hasMatch(person) || !view.livePeople.contains(person)) {
      return _no(WishAuthorError.personUnavailable);
    }
    return WishAuthorResult._(
      WishAuthor._(person, listId, view.me, self.recordDigest),
      null,
    );
  }

  WishAuthorResult _fromWeb(RegistryView root, String listId) {
    if (root.listId != listId) return _no(WishAuthorError.wrongList);
    final id = webId!;
    final web = root.member(id);
    if (web == null) {
      if (root.device(id) != null) return _no(WishAuthorError.devicePending);
      if (root.explicitlyRevoked.contains(id)) {
        return _no(WishAuthorError.deviceRevoked);
      }
      if (root.revoked.contains(id)) {
        return _no(WishAuthorError.deviceAmbiguous);
      }
      return _no(WishAuthorError.unknownDevice);
    }
    if (web.kind != DeviceKind.web ||
        web.signingKey.length != keys!.publicKeys.signing.length ||
        !_same(web.signingKey, keys!.publicKeys.signing)) {
      return _no(WishAuthorError.unknownDevice);
    }
    // La raíz móvil debe poder escribir ella misma (no revocada, aprobada)...
    if (root.selfRevoked) return _no(WishAuthorError.deviceRevoked);
    if (root.revokedByOthers) return _no(WishAuthorError.deviceAmbiguous);
    if (!(root.aloneAmongLiveMobiles || root.approvedByActive)) {
      return _no(WishAuthorError.devicePending);
    }
    // ... y la ficha de la web, avalada por ella siendo de la misma persona.
    if (!root.ownWebs().any((d) => d.deviceId == id)) {
      return _no(WishAuthorError.devicePending);
    }
    final person = web.personId;
    if (person == null) return _no(WishAuthorError.noPerson);
    if (!kSyncIdPattern.hasMatch(person) || !root.livePeople.contains(person)) {
      return _no(WishAuthorError.personUnavailable);
    }
    return WishAuthorResult._(
      WishAuthor._(person, listId, id, web.recordDigest),
      null,
    );
  }

  static bool _same(List<int> a, List<int> b) {
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static WishAuthorResult _no(WishAuthorError error) =>
      WishAuthorResult._(null, error);
}
