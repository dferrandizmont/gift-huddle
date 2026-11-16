import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import '../../../core/platform/camera_permission.dart';

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
    required this.errorBuilder,
    this.onReady,
    this.onDeniedChanged,
    this.requestPermission = requestCameraPermission,
    this.checkPermission = hasCameraPermission,
  });

  /// Pide el permiso de cámara, una sola vez, antes de crear el lector.
  final CameraPermissionRequest requestPermission;

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

  /// Lo que se enseña si no hay permiso de cámara.
  final WidgetBuilder errorBuilder;

  @override
  State<QrCameraScanner> createState() => _QrCameraScannerState();
}

class _QrCameraScannerState extends State<QrCameraScanner>
    with WidgetsBindingObserver {
  final GlobalKey _viewKey = GlobalKey(debugLabel: 'qr-camera');
  final RepeatedCodeFilter _filter = RepeatedCodeFilter();
  QRViewController? _controller;
  StreamSubscription<Barcode>? _codes;

  /// `null` mientras se espera la respuesta del permiso; el lector no existe
  /// hasta que es `true`, así que nunca vuelve a pedirlo por su cuenta.
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_ask());
  }

  Future<void> _ask() async {
    final granted = await widget.requestPermission();
    _apply(granted);
  }

  void _apply(bool granted) {
    if (!mounted || _granted == granted) {
      return;
    }
    setState(() {
      _granted = granted;
    });
    widget.onDeniedChanged?.call(!granted);
  }

  // Si la persona da el permiso en los ajustes y vuelve, el lector aparece y
  // el aviso se quita. Aquí no se pide nada: solo se mira.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _granted == false &&
        defaultTargetPlatform == TargetPlatform.android) {
      unawaited(widget.checkPermission().then(_apply));
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
  }

  // iPhone: el permiso lo pide el lector y avisa aquí; en Android ya llega
  // resuelto y este aviso no cambia nada.
  void _onPermission(QRViewController controller, bool granted) =>
      _apply(granted);

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
    unawaited(_codes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final granted = _granted;
    if (granted == null) {
      // Esperando al diálogo del sistema.
      return const ColoredBox(color: Colors.black);
    }
    if (!granted) {
      return ColoredBox(
        color: Colors.black,
        child: widget.errorBuilder(context),
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
