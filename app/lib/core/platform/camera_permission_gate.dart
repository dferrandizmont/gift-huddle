// El permiso de cámara del lector de QR como una máquina de estados pequeña,
// sin Flutter: se prueba sin dispositivo.
//
// Pide el permiso una vez. Si en [CameraPermissionGate.answerTimeout] no llega
// respuesta (el diálogo no salió o la respuesta se perdió), mira el permiso sin
// preguntar: si ya está dado, sigue; si no, queda [CameraPermissionState.failed]
// para reintentar. Una respuesta que llega tarde vale igual. Al volver a la app
// se mira otra vez (por si se dio en Ajustes). Nunca se queda esperando para
// siempre.
import 'dart:async';

/// Lo que contestó el sistema al pedir el permiso de cámara.
enum CameraPermissionOutcome {
  /// Dado.
  granted,

  /// Denegado; se puede volver a preguntar.
  denied,

  /// Denegado y el sistema ya no enseña el diálogo («no volver a preguntar»):
  /// solo se puede dar desde los ajustes de la app.
  permanentlyDenied,

  /// La petición se interrumpió sin respuesta (otro diálogo, la actividad se
  /// recreó…).
  cancelled,
}

/// Pide el permiso y dice qué contestó el sistema.
typedef CameraPermissionStatusRequest =
    Future<CameraPermissionOutcome> Function();

/// En qué punto está el permiso de cámara.
enum CameraPermissionState {
  /// Esperando la respuesta del sistema.
  waiting,

  /// Dado: se puede crear el lector.
  granted,

  /// Denegado; se puede volver a preguntar.
  denied,

  /// Denegado para siempre: solo desde los ajustes de la app.
  permanentlyDenied,

  /// No llegó respuesta (o se interrumpió) y el permiso no está dado: se
  /// puede reintentar.
  failed,
}

/// Lo que se enseña cuando no hay cámara.
enum CameraIssue {
  /// Denegado; «Reintentar» vuelve a preguntar.
  denied,

  /// Denegado para siempre; hay que ir a los ajustes.
  permanentlyDenied,

  /// No llegó respuesta; «Reintentar» vuelve a preguntar.
  failed,
}

/// El permiso de cámara del lector.
class CameraPermissionGate {
  /// Crea la máquina. No pregunta nada hasta [start].
  CameraPermissionGate({
    required this.request,
    required this.check,
    Future<bool> Function()? openSettings,
    this.answerTimeout = const Duration(seconds: 4),
  }) : _openSettings = openSettings ?? (() async => false);

  /// Pide el permiso (puede enseñar el diálogo).
  final CameraPermissionStatusRequest request;

  /// Mira si el permiso está dado, sin preguntar.
  final Future<bool> Function() check;

  /// Cuánto se espera la respuesta antes de mirar por su cuenta.
  final Duration answerTimeout;

  final Future<bool> Function() _openSettings;
  final _listeners = <void Function()>[];
  CameraPermissionState _state = CameraPermissionState.waiting;
  Timer? _timeout;
  int _attempt = 0;
  bool _disposed = false;

  /// El estado actual.
  CameraPermissionState get state => _state;

  /// El problema que enseñar, o null si se espera o ya hay cámara.
  CameraIssue? get issue => switch (_state) {
    CameraPermissionState.denied => CameraIssue.denied,
    CameraPermissionState.permanentlyDenied => CameraIssue.permanentlyDenied,
    CameraPermissionState.failed => CameraIssue.failed,
    _ => null,
  };

  /// Avisa de cada cambio de estado.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Deja de avisar a [listener].
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Sube con cada respuesta del sistema (y con cada intento): una
  /// comprobación que empezó antes de ella ya no vale.
  int _answers = 0;

  /// Sube con cada comprobación que empieza: solo vale la más nueva, aunque
  /// otra más vieja termine después (o antes) que ella.
  int _checks = 0;

  /// Lo que tiene que publicar una comprobación que diga «no dado» aunque la
  /// haya sustituido otra más nueva (por ejemplo, `failed` tras un
  /// `cancelled` o sin respuesta): la más nueva lo hereda. Se olvida con cada
  /// respuesta del sistema o intento.
  CameraPermissionState? _pendingFallback;

  void _set(CameraPermissionState next) {
    if (_disposed || _state == next) return;
    _state = next;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  /// Pide el permiso (la primera vez y con «Reintentar»).
  Future<void> start() async {
    if (_disposed) return;
    final attempt = ++_attempt;
    _answers++;
    _pendingFallback = null;
    _set(CameraPermissionState.waiting);
    _timeout?.cancel();
    _timeout = Timer(answerTimeout, () => unawaited(_noAnswer(attempt)));
    CameraPermissionOutcome outcome;
    try {
      outcome = await request();
    } on Object {
      outcome = CameraPermissionOutcome.cancelled;
    }
    if (_disposed || attempt != _attempt) return;
    _timeout?.cancel();
    _answers++;
    _pendingFallback = null;
    switch (outcome) {
      case CameraPermissionOutcome.granted:
        _set(CameraPermissionState.granted);
      case CameraPermissionOutcome.denied:
        _set(CameraPermissionState.denied);
      case CameraPermissionOutcome.permanentlyDenied:
        _set(CameraPermissionState.permanentlyDenied);
      case CameraPermissionOutcome.cancelled:
        await _recheck(attempt, otherwise: CameraPermissionState.failed);
    }
  }

  /// [start] otra vez.
  Future<void> retry() => start();

  /// Abre los ajustes de la app; al volver, [resumed] mira el permiso.
  Future<bool> openSettings() async {
    try {
      return await _openSettings();
    } on Object {
      return false;
    }
  }

  /// La app vuelve a primer plano: si no hay cámara, mira el permiso sin
  /// preguntar (por si se dio en Ajustes o el diálogo respondió sin avisar).
  Future<void> resumed() async {
    if (_disposed || _state == CameraPermissionState.granted) return;
    await _recheck(_attempt);
  }

  /// Lo que dice el lector de iPhone, que pide el permiso él mismo.
  void report({required bool granted}) {
    if (_disposed) return;
    _attempt++;
    _answers++;
    _pendingFallback = null;
    _timeout?.cancel();
    _set(
      granted ? CameraPermissionState.granted : CameraPermissionState.denied,
    );
  }

  Future<void> _noAnswer(int attempt) async {
    if (_disposed || attempt != _attempt) return;
    if (_state != CameraPermissionState.waiting) return;
    await _recheck(attempt, otherwise: CameraPermissionState.failed);
  }

  /// Mira el permiso: si está dado, [CameraPermissionState.granted]; si no,
  /// [otherwise] (o se queda como está).
  Future<void> _recheck(int attempt, {CameraPermissionState? otherwise}) async {
    final answers = _answers;
    final generation = ++_checks;
    if (otherwise != null) _pendingFallback = otherwise;
    bool granted;
    try {
      granted = await check();
    } on Object {
      granted = false;
    }
    // Mientras se miraba llegó algo más nuevo: esta lectura ya no vale.
    if (_disposed ||
        attempt != _attempt ||
        answers != _answers ||
        generation != _checks) {
      return;
    }
    final fallback = otherwise ?? _pendingFallback;
    _pendingFallback = null;
    if (granted) {
      _timeout?.cancel();
      _set(CameraPermissionState.granted);
    } else if (fallback != null) {
      _set(fallback);
    }
  }

  /// Deja de escuchar: una respuesta tardía ya no cambia nada.
  void dispose() {
    _disposed = true;
    _timeout?.cancel();
    _listeners.clear();
  }
}
