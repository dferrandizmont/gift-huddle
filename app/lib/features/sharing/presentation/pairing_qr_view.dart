import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/layout/window_class.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/sheet_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../sync/application/pairing_v2_controller.dart';
import '../../sync/presentation/pairing_v2_host_view.dart';
import '../application/pairing_service.dart';
import 'share_error_text.dart';

/// El texto del QR de conectar, solo mientras se enseña.
final pairingQrProvider = FutureProvider.autoDispose<String>(
  (ref) => ref.read(pairingServiceProvider).qrTextForPairing(),
);

/// El QR que lee el otro móvil para unirse a la familia, con el aviso de no
/// hacer captura: el código lleva la clave de la familia.
///
/// Es el paso «Está aquí» de la hoja «Conectar otro móvil».
class PairingQrView extends ConsumerWidget {
  /// Crea la vista.
  const PairingQrView({super.key});

  /// Lado máximo del código según la clase de la ventana: 260 en el móvil y
  /// 320 desde 600 dp, para leerlo de un lado a otro de la mesa
  /// (la guía de diseño para tablet, §2.2).
  static double maxSideOf(BuildContext context) =>
      RegalosLayout.pairingQrSize(WindowClass.of(context));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Con la sincronización v2 se empareja comparando un número: el QR lleva
    // un enlace sin clave (ADR 0004).
    if (ref.watch(pairingV2AvailableProvider)) {
      return const PairingV2HostView();
    }
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final qr = ref.watch(pairingQrProvider);
    final maxSide = maxSideOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: qr.when(
            data: (text) => LayoutBuilder(
              builder: (context, constraints) {
                final side = math.min(constraints.maxWidth, maxSide);
                return PairingQrFrame(data: text, side: side);
              },
            ),
            // Mismo hueco que el código: la hoja no cambia de alto al llegar.
            loading: () => SizedBox.square(
              dimension: maxSide,
              child: const Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(shareErrorMessage(l10n, error), style: t.styles.body),
            ),
          ),
        ),
        const SizedBox(height: 16),
        WarningBox(l10n.showQrWarning),
      ],
    );
  }
}

/// El código QR con su marco y la entrada animada: lo usan el QR con clave de
/// v1 y el enlace sin clave de v2.
class PairingQrFrame extends StatelessWidget {
  /// Crea el marco con el código de [data], de [side] de lado.
  const PairingQrFrame({super.key, required this.data, required this.side});

  /// Lo que codifica el QR.
  final String data;

  /// Lado del cuadro.
  final double side;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return _QrEntrance(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: RegalosShape.card,
          border: Border.all(color: t.separator),
        ),
        child: QrImageView(
          data: data,
          size: side,
          padding: const EdgeInsets.all(12),
          backgroundColor: Colors.white,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
          semanticsLabel: l10n.showQrLabel,
        ),
      ),
    );
  }
}

/// El QR entra con escala de 0,96 a 1 y fundido (`snap`), 120 ms después de
/// pintarse (§3.2 y «momento L»). No respira ni parpadea: se queda quieto.
/// Con «Reducir movimiento», solo un fundido de 150 ms.
class _QrEntrance extends StatefulWidget {
  const _QrEntrance({required this.child});

  final Widget child;

  @override
  State<_QrEntrance> createState() => _QrEntranceState();
}

class _QrEntranceState extends State<_QrEntrance>
    with SingleTickerProviderStateMixin {
  static const Duration _delay = Duration(milliseconds: 120);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );
  late Animation<double> _curve;
  bool _reduce = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    _reduce = RegalosMotion.of(context).reduce;
    final enter = _reduce ? RegalosMotion.fade : RegalosSprings.snapDuration;
    // El retardo va en la curva, no en un temporizador.
    final total = _reduce ? enter : _delay + enter;
    _controller.duration = total;
    _curve = CurvedAnimation(
      parent: _controller,
      curve: _reduce
          ? Curves.linear
          : Interval(
              _delay.inMicroseconds / total.inMicroseconds,
              1,
              curve: RegalosCurves.snap,
            ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    child: widget.child,
    builder: (context, child) {
      final v = _curve.value;
      return Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: _reduce
            ? child
            : Transform.scale(scale: 0.96 + 0.04 * v, child: child),
      );
    },
  );
}
