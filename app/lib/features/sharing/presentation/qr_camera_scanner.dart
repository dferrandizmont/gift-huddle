import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import '../../../core/platform/camera_permission.dart';
import '../../../core/platform/camera_permission_gate.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../l10n/app_localizations.dart';

export '../../../core/platform/camera_permission_gate.dart' show CameraIssue;

/// Lo que se enseña cuando no hay cámara: [retry] vuelve a pedir el permiso y
/// [openSettings] abre los ajustes de la app (para [CameraIssue.permanentlyDenied]).
typedef CameraIssueBuilder = Widget Function(
  BuildContext context,
  CameraIssue issue,
  VoidCallback retry,
  VoidCallback openSettings,
);

/// Deja pasar un código leído y calla sus repeticiones.
///
/// El lector avisa del mismo código en cada fotograma mientras siga delante de
/// la cámara. Un código se vuelve a dar solo si lleva [quiet] sin verse: así un
/// QR que no vale no repite su aviso sin parar, y apartar el móvil y volver a
/// apuntar lo lee otra vez.
class RepeatedCodeFilter {
  /// Crea el filtro.
  RepeatedCodeFilter({this.quiet = const Duration(seconds: 3)});

  /// Cuánto tiene que pasar sin ver un código para volver a darlo.
  final Duration quiet;

  String? _last;
  DateTime? _seenAt;

  /// Si [code], visto ahora, hay que darlo.
  bool accept(String code) {
    final now = clock.now();
    final seenAt = _seenAt;
    final repeated =
        code == _last && seenAt != null && now.difference(seenAt) < quiet;
    _last = code;
    _seenAt = now;
    return !repeated;
  }
}

/// La cámara que lee el código QR de emparejar.
///
/// Lee con ZXing dentro de la app (`qr_code_scanner_plus`): en Android, ZXing
/// con la cámara del sistema; en iPhone, AVFoundation. No lleva ML Kit ni
/// ningún servicio de Google, y no hace ninguna petición de red.
///
/// Solo da el texto leído: este lector no dice dónde está el código en la
/// imagen, así que las esquinas del visor se cierran hacia el centro en vez de
/// viajar hasta el código (`ScanViewfinderState.lock(null)`).
class QrCameraScanner extends StatefulWidget {
  /// Crea el lector.
  const QrCameraScanner({
    super.key,
    required this.onCode,
    this.errorBuilder,
    this.onReady,
    this.onDeniedChanged,
    this.requestPermission = requestCameraPermission,
    this.checkPermission = hasCameraPermission,
    this.requestPermissionStatus,
    this.openSettings = openCameraSettings,
    this.waitingBuilder,
    this.issueBuilder,
    this.answerTimeout = const Duration(seconds: 4),
  });

  /// Pide el permiso de cámara, una sola vez, antes de crear el lector. Si se
  /// da uno propio (pruebas, otras pantallas), su sí o no manda; con el de
  /// siempre se usa [requestCameraPermissionStatus], que distingue más casos.
  final CameraPermissionRequest requestPermission;

  /// Pide el permiso y dice qué contestó el sistema. Si se da, manda sobre
  /// [requestPermission].
  final CameraPermissionStatusRequest? requestPermissionStatus;

  /// Abre los ajustes de la app.
  final Future<bool> Function() openSettings;

  /// Lo que se enseña mientras se espera la respuesta del permiso. Sin él,
  /// un texto corto con un indicador de progreso (nunca una caja negra vacía).
  final WidgetBuilder? waitingBuilder;

  /// Lo que se enseña si no hay cámara (denegado, denegado para siempre o sin
  /// respuesta). Sin él, [errorBuilder] y, sin ninguno, el aviso de siempre.
  final CameraIssueBuilder? issueBuilder;

  /// Cuánto se espera la respuesta del permiso antes de mirarlo sin preguntar.
  final Duration answerTimeout;

  /// Mira si el permiso ya está dado, sin preguntar (al volver de Ajustes).
  final CameraPermissionRequest checkPermission;

  /// Se llama cuando la cámara ya está creada o se da el permiso: el visor
  /// empieza ahí su entrada, no antes.
  final VoidCallback? onReady;

  /// Se llama cuando el permiso de cámara pasa a denegado (`true`) o a
  /// concedido (`false`).
  final ValueChanged<bool>? onDeniedChanged;

  /// Recibe el texto de cada código QR leído (sin sus repeticiones).
  final ValueChanged<String> onCode;

  /// Aviso propio y sin botones si no hay permiso de cámara (pantallas con su
  /// propio diseño). Si no se da ni él ni [issueBuilder], se enseña el aviso de
  /// siempre, con «Reintentar» o «Abrir ajustes».
  final WidgetBuilder? errorBuilder;

  @override
  State<QrCameraScanner> createState() => _QrCameraScannerState();
}

class _QrCameraScannerState extends State<QrCameraScanner>
    with WidgetsBindingObserver {
  final GlobalKey _viewKey = GlobalKey(debugLabel: 'qr-camera');
  final RepeatedCodeFilter _filter = RepeatedCodeFilter();
  QRViewController? _controller;
  StreamSubscription<Barcode>? _codes;
  late final CameraPermissionGate _gate;

  /// Lo último que se avisó por `onDeniedChanged` (null: nada todavía).
  bool? _deniedReported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gate = CameraPermissionGate(
      request: _requestStatus,
      check: () => widget.checkPermission(),
      openSettings: () => widget.openSettings(),
      answerTimeout: widget.answerTimeout,
    )..addListener(_changed);
    unawaited(_gate.start());
  }

  Future<CameraPermissionOutcome> _requestStatus() async {
    final status = widget.requestPermissionStatus;
    if (status != null) return status();
    // Con el de siempre, la versión que distingue «para siempre».
    if (identical(widget.requestPermission, requestCameraPermission)) {
      return requestCameraPermissionStatus();
    }
    return await widget.requestPermission()
        ? CameraPermissionOutcome.granted
        : CameraPermissionOutcome.denied;
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final state = _gate.state;
    if (state == CameraPermissionState.waiting) return;
    final denied = state != CameraPermissionState.granted;
    if (_deniedReported != denied) {
      _deniedReported = denied;
      widget.onDeniedChanged?.call(denied);
    }
  }

  // Si la persona da el permiso en los ajustes y vuelve, el lector aparece y
  // el aviso se quita; si el diálogo no llegó a contestar, también. Aquí no
  // se pide nada: solo se mira.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _gate.state != CameraPermissionState.granted &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      unawaited(_gate.resumed());
    }
  }

  void _onCreated(QRViewController controller) {
    unawaited(_codes?.cancel());
    _controller = controller;
    widget.onReady?.call();
    _codes = controller.scannedDataStream.listen((barcode) {
      final code = barcode.code;
      if (code != null && code.isNotEmpty && _filter.accept(code)) {
        widget.onCode(code);
      }
    });
    // Android: la vista nativa solo arranca la vista previa en `resume()`, que
    // llega con el ciclo de vida de la actividad o si Flutter vuelve a pedir
    // la vista. Recién dado el permiso no pasa ninguna de las dos y se queda
    // en negro: se arranca aquí (si ya está en marcha no hace nada).
    if (defaultTargetPlatform == TargetPlatform.android) {
      unawaited(controller.resumeCamera().catchError((Object _) {}));
    }
  }

  // El lector se crea con permiso concedido. Este aviso cubre cambios
  // posteriores y plataformas sin canal nativo.
  void _onPermission(QRViewController controller, bool granted) {
    if (granted == (_gate.state == CameraPermissionState.granted)) return;
    _gate.report(granted: granted);
  }

  // En Android la recarga en caliente deja la vista previa en negro si no se
  // para y se reanuda la cámara (solo afecta a depuración).
  @override
  void reassemble() {
    super.reassemble();
    final controller = _controller;
    if (controller != null && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(
        controller
            .pauseCamera()
            .then((_) => controller.resumeCamera())
            .catchError((Object _) {}),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gate.dispose();
    unawaited(_codes?.cancel());
    super.dispose();
  }

  void _retry() => unawaited(_gate.retry());

  void _openSettings() => unawaited(_gate.openSettings());

  @override
  Widget build(BuildContext context) {
    final issue = _gate.issue;
    if (_gate.state == CameraPermissionState.waiting) {
      // Esperando al diálogo del sistema: nunca una caja negra sin nada.
      return ColoredBox(
        color: Colors.black,
        child: widget.waitingBuilder?.call(context) ?? _defaultWaiting(context),
      );
    }
    if (issue != null) {
      final builder = widget.issueBuilder;
      return ColoredBox(
        color: Colors.black,
        child: builder != null
            ? builder(context, issue, _retry, _openSettings)
            : widget.errorBuilder?.call(context) ??
                  _DefaultIssue(
                    issue: issue,
                    retry: _retry,
                    openSettings: _openSettings,
                  ),
      );
    }
    return QRView(
      key: _viewKey,
      onQRViewCreated: _onCreated,
      onPermissionSet: _onPermission,
      formatsAllowed: const [BarcodeFormat.qrcode],
    );
  }
}

/// Colores de los avisos: la cámara siempre se ve sobre negro.
abstract final class _OnCamera {
  static const Color text = Colors.white;
  static const Color secondary = Colors.white70;
  static const Color track = Colors.white24;
  static const Color button = Colors.white;
  static const Color onButton = Colors.black;
}

/// Un aviso sobre la cámara negra: aparece con un fundido corto.
class _ScannerNotice extends StatelessWidget {
  const _ScannerNotice({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = RegalosMotion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: motion.duration(RegalosCurves.foldDuration),
      curve: motion.curve(RegalosCurves.fold),
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: child,
        ),
      ),
    );
  }
}

/// Lo que se ve mientras el sistema pregunta por la cámara: un texto corto y
/// un indicador pequeño, legibles sobre el fondo negro. Sin traducciones
/// montadas (pruebas sin app), solo el indicador.
Widget _defaultWaiting(BuildContext context) {
  final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
  if (l10n == null) {
    return const Center(
      child: CircularProgressIndicator(color: _OnCamera.text),
    );
  }
  final t = RegalosTokens.of(context);
  return _ScannerNotice(
    child: Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _OnCamera.text,
              backgroundColor: _OnCamera.track,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              l10n.scannerWaitingPermission,
              style: t.styles.body.copyWith(color: _OnCamera.text),
            ),
          ),
        ],
      ),
    ),
  );
}

/// El aviso de cada problema con su botón: «Reintentar» (denegado, sin
/// respuesta) o «Abrir ajustes» (denegado para siempre).
class _DefaultIssue extends StatelessWidget {
  const _DefaultIssue({
    required this.issue,
    required this.retry,
    required this.openSettings,
  });

  final CameraIssue issue;
  final VoidCallback retry;
  final VoidCallback openSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final (title, body) = switch (issue) {
      CameraIssue.denied => (l10n.scannerDeniedTitle, l10n.scannerDeniedBody),
      CameraIssue.permanentlyDenied => (
        l10n.scannerBlockedTitle,
        l10n.scannerBlockedBody,
      ),
      CameraIssue.restricted => (
        l10n.scannerBlockedTitle,
        l10n.cameraRestricted,
      ),
      CameraIssue.failed => (l10n.scannerFailedTitle, l10n.scannerFailedBody),
    };
    final settings = issue == CameraIssue.permanentlyDenied;
    return _ScannerNotice(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: t.styles.rowTitle.copyWith(color: _OnCamera.text),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: t.styles.body.copyWith(color: _OnCamera.secondary),
                ),
              ],
            ),
          ),
          if (issue != CameraIssue.restricted) ...[
            const SizedBox(height: 16),
            Center(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _OnCamera.button,
                  foregroundColor: _OnCamera.onButton,
                  minimumSize: const Size(44, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: const RoundedRectangleBorder(
                    borderRadius: RegalosShape.button,
                  ),
                ),
                onPressed: settings ? openSettings : retry,
                child: Text(
                  settings ? l10n.scannerOpenSettings : l10n.scannerRetry,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
