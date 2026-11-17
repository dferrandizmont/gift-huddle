import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/platform/secure_screen.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/sync/recovery.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../l10n/app_localizations.dart';
import '../../sharing/presentation/join_qr_screen.dart'
    show scannerBuilderProvider;
import '../../sharing/presentation/qr_camera_scanner.dart';
import '../../sharing/presentation/scan_viewfinder.dart';

/// La cámara que lee el QR del código de recuperación. Devuelve el texto leído
/// con `Navigator.pop`; un QR que no es de recuperación se avisa y se sigue
/// buscando. Reutiliza el lector del emparejamiento (ZXing, sin servicios de
/// Google).
class RecoveryScanScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const RecoveryScanScreen({super.key});

  /// Lado máximo del cuadro de la cámara en tablet.
  static const double cameraMaxSide = 480;

  @override
  ConsumerState<RecoveryScanScreen> createState() => _RecoveryScanScreenState();
}

class _RecoveryScanScreenState extends ConsumerState<RecoveryScanScreen> {
  final GlobalKey<ScanViewfinderState> _finder =
      GlobalKey<ScanViewfinderState>();
  bool _busy = false;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    // La cámara apunta a un QR que es el código: sin capturas mientras se ve.
    unawaited(enableSecureScreen());
  }

  @override
  void dispose() {
    unawaited(disableSecureScreen());
    super.dispose();
  }

  Future<void> _onCode(String text, [Rect? rect]) async {
    if (_busy) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    try {
      RecoveryCode.fromQrText(text);
    } on RecoveryException {
      showRegalosSnackBar(
        context,
        SnackBar(content: Text(l10n.recoverQrWrong)),
      );
      return;
    }
    _busy = true;
    final reduce = RegalosMotion.of(context).reduce;
    _finder.currentState?.lock(rect);
    await Future<void>.delayed(ScanViewfinder.followUp(reduce: reduce));
    if (mounted) {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final custom = ref.watch(scannerBuilderProvider);
    final compact = WindowClass.of(context) == WindowClass.compact;
    Widget scanner(BuildContext context) =>
        custom?.call(context, _onCode) ??
        QrCameraScanner(
          onCode: _onCode,
          onReady: () => WidgetsBinding.instance.addPostFrameCallback(
            (_) => _finder.currentState?.begin(),
          ),
          onDeniedChanged: (denied) {
            if (mounted) {
              setState(() => _denied = denied);
            }
          },
          // Sin errorBuilder: los avisos de siempre del lector, con
          // «Reintentar» o «Abrir ajustes» según el caso.
        );
    final camera = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: RegalosShape.card,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          scanner(context),
          if (!_denied)
            IgnorePointer(
              child: ScanViewfinder(key: _finder, autoStart: custom != null),
            ),
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ContentWidth(
              maxWidth: RegalosLayout.onboardingColumn,
              child: ScreenHeader(
                title: l10n.recoverScanTitle,
                subtitle: l10n.recoverScanBody,
                backLabel: l10n.actionBack,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: RecoveryScanScreen.cameraMaxSide,
                      maxHeight: compact
                          ? double.infinity
                          : RecoveryScanScreen.cameraMaxSide,
                    ),
                    child: camera,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
