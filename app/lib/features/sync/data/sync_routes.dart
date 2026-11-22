// Rutas al servidor de sincronización (1.0.6, plan B contra el bloqueo).
//
// - La lista de hosts es fija y va compilada en la app (`kSyncHosts`): los
//   dos nombres llegan al mismo Worker y a los mismos objetos, y todo lo que
//   escribe va con `If-Match`, así que repetir una petición en el otro es
//   seguro. Nada de la lista llega del servidor, de un QR, de un enlace ni de
//   un fichero.
// - Se pasa al siguiente host solo si no se puede conectar con uno (tiempo
//   de conexión agotado, conexión cortada o rechazada, fallo de TLS o un
//   certificado ajeno, como la página de bloqueo de un operador). Nunca por
//   un estado HTTP: un 4xx o un 5xx ya es el servidor contestando.
// - El host que funcionó, si no es el primero, se recuerda 30 minutos (en
//   memoria y como índice guardado, que se valida contra la lista al
//   leerlo). Después se vuelve a probar el primero.
// - Tras [kSyncBlockedHintAfter] fallos seguidos en todas las rutas se avisa
//   de que quizá el operador está bloqueando el servicio.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_transport.dart';

/// Tiempo para conectar con un host (TCP y TLS) en los móviles.
const Duration kSyncConnectTimeout = Duration(seconds: 5);

/// En el navegador no hay tiempo de conexión: es lo que se espera a la
/// cabecera de la respuesta antes de probar el siguiente host.
const Duration kWebConnectTimeout = Duration(seconds: 6);

/// Cuánto se recuerda un host que no es el primero.
const Duration kSyncRouteMemory = Duration(minutes: 30);

/// Fallos seguidos en todas las rutas tras los que se sugiere que el
/// operador puede estar bloqueando el servicio.
const int kSyncBlockedHintAfter = 3;

/// Cuánto vale una conexión hecha para mandar una mutación de la web sin
/// volver a comprobar la ruta ([SyncRoutes.runOnce]).
const Duration kSyncRouteConfirmed = Duration(seconds: 60);

/// Ruta que se lee para elegir host antes de una mutación de la web: el
/// Worker contesta `404` (con CORS) sin tocar ningún objeto ni leer nada.
const String kSyncRouteProbePath = '/v2/route-probe';

/// No se pudo conectar con un host: se prueba el siguiente. Solo lo lanzan
/// los transportes en la fase de conexión, antes de enviar nada.
class SyncRouteConnectFailure implements Exception {
  /// Crea el fallo.
  const SyncRouteConnectFailure(this.message);

  /// Detalle para el registro.
  final String message;

  @override
  String toString() => 'SyncRouteConnectFailure: $message';
}

/// El host recordado: su índice en la lista y hasta cuándo vale.
typedef SyncRouteMemo = ({int index, int untilMillis});

/// Dónde se guarda el host recordado.
abstract interface class SyncRouteStore {
  /// Lo guardado, o null.
  SyncRouteMemo? read();

  /// Guarda [memo], o lo borra con null.
  void write(SyncRouteMemo? memo);
}

/// [SyncRouteStore] en `SharedPreferences`: solo un índice y una hora.
class PrefsSyncRouteStore implements SyncRouteStore {
  /// Crea el almacén.
  PrefsSyncRouteStore(this._prefs);

  final SharedPreferences _prefs;

  static const _indexKey = 'sync.route.index';
  static const _untilKey = 'sync.route.until';

  @override
  SyncRouteMemo? read() {
    final index = _prefs.get(_indexKey);
    final until = _prefs.get(_untilKey);
    if (index is! int || until is! int) return null;
    return (index: index, untilMillis: until);
  }

  @override
  void write(SyncRouteMemo? memo) {
    if (memo == null) {
      unawaited(_prefs.remove(_indexKey));
      unawaited(_prefs.remove(_untilKey));
      return;
    }
    unawaited(_prefs.setInt(_indexKey, memo.index));
    unawaited(_prefs.setInt(_untilKey, memo.untilMillis));
  }
}

/// La función que intenta una petición en un host: llama a `connected` en
/// cuanto la conexión está hecha y lanza [SyncRouteConnectFailure] si no se
/// pudo hacer.
typedef SyncRouteAttempt<T> = Future<T> Function(
  Uri target,
  void Function() connected,
);

/// El orden de los hosts y lo que se recuerda de ellos.
class SyncRoutes {
  /// Crea las rutas de [bases] (la primera es la principal).
  SyncRoutes(
    List<Uri> bases, {
    SyncRouteStore? store,
    this.memory = kSyncRouteMemory,
    this.blockedAfter = kSyncBlockedHintAfter,
  }) : bases = List.unmodifiable(bases) {
    if (bases.isEmpty) {
      throw ArgumentError.value(bases, 'bases', 'hace falta un host');
    }
    if (store != null) attachStore(store);
  }

  static final _shared = <String, SyncRoutes>{};
  static SyncRouteStore? _defaultStore;

  /// Las rutas compartidas de [bases] en todo el proceso: los transportes
  /// que se crean y se cierran (la web crea varios) recuerdan lo mismo.
  static SyncRoutes shared(List<Uri> bases) => _shared.putIfAbsent(
    bases.join(' '),
    () => SyncRoutes(bases, store: _defaultStore),
  );

  /// Guarda en [store] lo que recuerdan las rutas compartidas (y las que se
  /// creen después). Lo llama `main` con las preferencias.
  static void useStore(SyncRouteStore store) {
    _defaultStore = store;
    for (final routes in _shared.values) {
      routes.attachStore(store);
    }
  }

  /// Olvida las rutas compartidas: SOLO para pruebas.
  @visibleForTesting
  static void resetShared() {
    _shared.clear();
    _defaultStore = null;
  }

  /// Los hosts, en el orden de la lista compilada.
  final List<Uri> bases;

  /// Cuánto se recuerda un host que no es el primero.
  final Duration memory;

  /// Fallos seguidos en todas las rutas para [likelyBlocked].
  final int blockedAfter;

  SyncRouteStore? _store;
  int _remembered = 0;
  int? _untilMillis;
  int _failures = 0;
  int? _confirmedIndex;
  int? _confirmedAtMillis;
  final _blocked = StreamController<bool>.broadcast();

  /// Lee lo guardado en [store] y guarda ahí a partir de ahora. Un índice
  /// fuera de la lista, o una hora que ya pasó o que va más allá de
  /// [memory] (el reloj ha cambiado), no vale y se borra.
  void attachStore(SyncRouteStore store) {
    _store = store;
    if (bases.length < 2) return;
    final memo = store.read();
    if (memo == null) return;
    final now = clock.now().millisecondsSinceEpoch;
    final valid =
        memo.index >= 1 &&
        memo.index < bases.length &&
        memo.untilMillis > now &&
        memo.untilMillis <= now + memory.inMilliseconds;
    if (valid) {
      _remembered = memo.index;
      _untilMillis = memo.untilMillis;
    } else {
      store.write(null);
    }
  }

  /// El host con el que se empieza ahora (índice en [bases]).
  int get current {
    final until = _untilMillis;
    if (_remembered == 0 || until == null) return 0;
    if (clock.now().millisecondsSinceEpoch < until) return _remembered;
    _remembered = 0;
    _untilMillis = null;
    _store?.write(null);
    return 0;
  }

  /// Si conviene sugerir que el operador bloquea el servicio.
  bool get likelyBlocked => _failures >= blockedAfter;

  /// [likelyBlocked] ahora y cada vez que cambia.
  Stream<bool> watchBlocked() async* {
    yield likelyBlocked;
    yield* _blocked.stream;
  }

  /// Si [uri] va al host principal: solo eso se reparte entre las rutas.
  bool routes(Uri uri) {
    final main = bases.first;
    final secure = uri.scheme == 'https' || uri.scheme == 'wss';
    final plain = uri.scheme == 'http' || uri.scheme == 'ws';
    if (!(main.scheme == 'https' ? secure : plain)) return false;
    return uri.host == main.host && _portOf(uri) == _portOf(main);
  }

  // `Uri.port` solo conoce el puerto por defecto de http y https.
  static int _portOf(Uri uri) => uri.hasPort
      ? uri.port
      : (uri.scheme == 'https' || uri.scheme == 'wss' ? 443 : 80);

  Uri _on(Uri uri, int index) {
    if (index == 0) return uri;
    final base = bases[index];
    return uri.replace(host: base.host, port: base.hasPort ? base.port : null);
  }

  /// Las direcciones que se prueban para [uri], en orden, con el índice de
  /// su host (null si [uri] no va al principal y se usa tal cual).
  List<(int?, Uri)> targets(Uri uri) {
    if (!routes(uri)) return [(null, uri)];
    final first = current;
    return [
      for (final i in [
        first,
        for (var i = 0; i < bases.length; i++)
          if (i != first) i,
      ])
        (i, _on(uri, i)),
    ];
  }

  /// Se conectó con el host [index]: si no es el que tocaba, se recuerda
  /// durante [memory] (sin alargar el plazo de uno ya recordado).
  void markConnected(int? index) {
    _setFailures(0);
    if (index == null || bases.length < 2) return;
    _confirmedIndex = index;
    _confirmedAtMillis = clock.now().millisecondsSinceEpoch;
    if (index == 0) {
      if (_remembered != 0) {
        _remembered = 0;
        _untilMillis = null;
        _store?.write(null);
      }
      return;
    }
    if (index == current) return;
    _remembered = index;
    _untilMillis = clock.now().add(memory).millisecondsSinceEpoch;
    _store?.write((index: index, untilMillis: _untilMillis!));
  }

  /// No se pudo conectar con ninguno.
  void markAllFailed() {
    _confirmedAtMillis = null;
    _setFailures(_failures + 1);
  }

  /// Si la ruta que toca se ha conectado hace menos de [kSyncRouteConfirmed].
  bool get _confirmed {
    final at = _confirmedAtMillis;
    return at != null &&
        _confirmedIndex == current &&
        clock.now().millisecondsSinceEpoch - at <
            kSyncRouteConfirmed.inMilliseconds;
  }

  void _setFailures(int value) {
    final before = likelyBlocked;
    _failures = value;
    if (likelyBlocked != before) _blocked.add(likelyBlocked);
  }

  /// Para lo que no se puede repetir: una mutación de la web, que puede
  /// agotar el plazo después de que el Worker la aplicara (un `POST` de PIN
  /// contaría dos intentos). Si la ruta que toca no se ha conectado hace
  /// poco, se elige primero con [probe], una lectura segura de
  /// [kSyncRouteProbePath] que sí puede cambiar de host; después [attempt] se
  /// manda **una sola vez**, a esa ruta. Si no conecta, error de red: nunca se
  /// repite en el otro host.
  Future<T> runOnce<T>(
    Uri uri, {
    required SyncRouteAttempt<void> probe,
    required SyncRouteAttempt<T> attempt,
  }) async {
    if (targets(uri).length > 1 && !_confirmed) {
      await run(
        Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.hasPort ? uri.port : null,
          path: kSyncRouteProbePath,
        ),
        probe,
      );
    }
    final (index, target) = targets(uri).first;
    var connected = false;
    try {
      return await attempt(target, () {
        if (connected) return;
        connected = true;
        markConnected(index);
      });
    } on SyncRouteConnectFailure catch (e) {
      _confirmedAtMillis = null;
      throw SyncTransportException(SyncFailure.network, e.message);
    }
  }

  /// Hace [attempt] en el host que toca y, si no se puede conectar, en el
  /// siguiente. Si no se conecta con ninguno lanza [SyncTransportException]
  /// de red. Cualquier otro error (también un estado HTTP) sale tal cual y
  /// no cambia de host.
  Future<T> run<T>(Uri uri, SyncRouteAttempt<T> attempt) async {
    var last = 'sin conexión';
    for (final (index, target) in targets(uri)) {
      var connected = false;
      try {
        return await attempt(target, () {
          if (connected) return;
          connected = true;
          markConnected(index);
        });
      } on SyncRouteConnectFailure catch (e) {
        if (connected) {
          throw SyncTransportException(SyncFailure.network, e.message);
        }
        last = e.message;
      }
    }
    markAllFailed();
    throw SyncTransportException(SyncFailure.network, last);
  }
}
