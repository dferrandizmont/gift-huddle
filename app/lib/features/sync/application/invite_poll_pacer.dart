// Cadencia de los sondeos de una invitación v2 (web y móviles). Dart puro.
//
// El Worker admite 30 peticiones públicas por minuto e invitación
// (`V2_INVITE_REQUESTS_PER_INVITE`, ventana fija) y 120 por minuto e IP en las
// rutas de invitación (`INVITE_IP_LIMITER`). Con la pantalla abierta se
// pregunta cada 1-2 s, pero nunca más de [kInvitePollBudget] peticiones a la
// misma invitación en 60 s seguidos: si se llega, se espera a que la más
// vieja salga de la ventana. Tras un 429 se obedece `Retry-After` o se espera
// cada vez el doble (2, 4, 8… hasta 30 s), con algo de azar, y nunca más de
// [kInvitePollMaxWait]; ninguna espera programada después se la salta.
//
// Las ventanas y los plazos se miden con un reloj monótono (un `Stopwatch`):
// cambiar la hora del sistema no alarga ni acorta nada. La hora de pared solo
// sirve para la caducidad que da el servidor.
import 'dart:collection';
import 'dart:math';

/// Peticiones a una misma invitación en cualquier ventana de 60 s. Por debajo
/// de las 30 del Worker para dejar margen a las sueltas (responder, el
/// checkpoint).
const int kInvitePollBudget = 25;

/// Peticiones por minuto del móvil que invita mientras espera la respuesta:
/// la cuarta parte de las 120 por IP de las rutas de invitación.
const int kInviteHostPollBudget = 30;

/// La ventana del presupuesto: la misma del Worker.
const Duration kInvitePollWindow = Duration(seconds: 60);

/// La espera más larga tras varios 429 seguidos sin `Retry-After`.
const Duration kInvitePollMaxBackoff = Duration(seconds: 30);

/// La espera más larga tras un 429, aunque `Retry-After` pida más.
const Duration kInvitePollMaxWait = Duration(seconds: 60);

/// Un reloj monótono: el tiempo transcurrido desde que se creó.
Duration Function() monotonicElapsed() {
  final watch = Stopwatch()..start();
  return () => watch.elapsed;
}

/// Decide cuánto esperar antes del siguiente sondeo de una invitación.
class InvitePollPacer {
  /// Crea la cadencia: cada sondeo espera entre [base] y [base] más [spread]
  /// (por defecto, el doble de [base]). [elapsed] es el reloj monótono.
  InvitePollPacer({
    this.base = const Duration(seconds: 1),
    Duration? spread,
    this.budget = kInvitePollBudget,
    this.window = kInvitePollWindow,
    this.maxBackoff = kInvitePollMaxBackoff,
    this.maxWait = kInvitePollMaxWait,
    this.perPoll = 2,
    Random? random,
    Duration Function()? elapsed,
  }) : spread = spread ?? base,
       _random = random ?? Random(),
       _elapsed = elapsed ?? monotonicElapsed();

  /// La espera mínima entre sondeos.
  final Duration base;

  /// Lo que se suma al azar a [base] (de 0 a esto).
  final Duration spread;

  /// Peticiones como mucho en [window] (null: sin presupuesto).
  final int? budget;

  /// La ventana del presupuesto.
  final Duration window;

  /// El tope de la espera tras varios 429 seguidos sin `Retry-After`.
  final Duration maxBackoff;

  /// El tope de cualquier espera por un 429.
  final Duration maxWait;

  /// Peticiones que puede hacer un sondeo (la respuesta y el checkpoint):
  /// antes de empezarlo tiene que caber entero en el presupuesto.
  final int perPoll;

  final Random _random;
  final Duration Function() _elapsed;
  final _sent = ListQueue<Duration>();
  int _limited = 0;

  /// Hasta cuándo (en el reloj monótono) no se puede volver a preguntar por
  /// un 429.
  Duration? _retryAt;

  /// Peticiones hechas dentro de la ventana actual.
  int get inWindow {
    _trim(_elapsed());
    return _sent.length;
  }

  /// Apunta una petición que el Worker cuenta para esta invitación.
  void sent() {
    final now = _elapsed();
    _trim(now);
    _sent.addLast(now);
  }

  /// La respuesta no fue un 429: la siguiente espera tras otro 429 vuelve a
  /// empezar en 2 s.
  void succeeded() => _limited = 0;

  /// La espera antes del siguiente sondeo normal; [base] y [spread] cambian
  /// la cadencia de este (la web, tras 2 minutos sin oferta, va a 3-4 s).
  Duration next({Duration? base, Duration? spread}) =>
      _schedule(_jitter(base ?? this.base, spread ?? this.spread));

  /// La espera para sondear ya (tras una acción de la persona): sin azar,
  /// pero dentro del presupuesto y sin saltarse una espera por 429.
  Duration soon() => _schedule(Duration.zero);

  /// La espera tras un 429: [retryAfter] si el Worker la dio; si no, el doble
  /// que la vez anterior (2, 4, 8… hasta [maxBackoff]), con hasta un 25 % más
  /// de azar; nunca más de [maxWait]. Queda como plazo que respetan también
  /// [next] y [soon].
  Duration limited([Duration? retryAfter]) {
    _limited++;
    Duration wait;
    if (retryAfter != null && retryAfter > Duration.zero) {
      wait = retryAfter;
    } else {
      final seconds = min(maxBackoff.inSeconds, 1 << min(_limited, 5));
      final exp = Duration(seconds: seconds);
      final extra = Duration(
        milliseconds: _random.nextInt(exp.inMilliseconds ~/ 4 + 1),
      );
      wait = exp + extra;
      if (wait > maxBackoff) wait = maxBackoff;
    }
    if (wait > maxWait) wait = maxWait;
    final now = _elapsed();
    final until = now + wait;
    final current = _retryAt;
    if (current == null || until > current) _retryAt = until;
    return _schedule(_jitter(base, spread), now);
  }

  /// Lo que falta del plazo de un 429 (cero si no hay).
  Duration get retryRemaining => _retryLeft(_elapsed());

  Duration _retryLeft(Duration now) {
    final at = _retryAt;
    if (at == null) return Duration.zero;
    final left = at - now;
    return left.isNegative ? Duration.zero : left;
  }

  Duration _jitter(Duration base, Duration spread) {
    final ms = spread.inMilliseconds;
    return base + Duration(milliseconds: ms <= 0 ? 0 : _random.nextInt(ms + 1));
  }

  /// [wait], pero nunca antes del plazo de un 429 ni fuera del presupuesto;
  /// todo medido en el mismo instante [now].
  Duration _schedule(Duration wait, [Duration? now]) {
    final at = now ?? _elapsed();
    final retry = _retryLeft(at);
    if (retry > wait) wait = retry;
    return _withinBudget(wait, at);
  }

  /// Alarga [wait] lo justo para que el próximo sondeo, con sus [perPoll]
  /// peticiones, no pase de [budget] en ninguna ventana de [window].
  Duration _withinBudget(Duration wait, Duration now) {
    final max = budget;
    if (max == null || max <= 0) return wait;
    // Las que puede haber antes de empezar un sondeo de hasta [perPoll].
    final room = max - perPoll < 0 ? 0 : max - perPoll;
    _trim(now);
    if (_sent.length <= room) return wait;
    // Tienen que haber salido de la ventana todas menos las `room` últimas.
    final oldest = _sent.elementAt(_sent.length - room - 1);
    // Un milisegundo más para no caer justo en el borde.
    final needed = oldest + window - now + const Duration(milliseconds: 1);
    return needed > wait ? needed : wait;
  }

  void _trim(Duration now) {
    while (_sent.isNotEmpty && now - _sent.first >= window) {
      _sent.removeFirst();
    }
  }

  /// Olvida todo (otra invitación).
  void reset() {
    _sent.clear();
    _limited = 0;
    _retryAt = null;
  }
}
