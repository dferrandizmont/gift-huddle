import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../core/layout/content_width.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/shake.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tabler_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../data/pin_vault.dart';

/// Máximo de dígitos del PIN.
const int kPinMaxLength = kPinMaxDigits;

/// Mínimo de dígitos del PIN.
const int kPinMinLength = kPinMinDigits;

/// Cuánto tarda en vaciarse un punto al borrar.
const Duration _kDotClear = Duration(milliseconds: 120);

/// Cuánto tarda en vaciarse la fila entera tras un error.
const Duration _kDotClearAfterError = Duration(milliseconds: 180);

/// Cuánto dura el aviso en rojo del anillo con «Reducir movimiento».
const Duration _kReduceErrorTint = Duration(milliseconds: 600);

/// Lo que dura el latido de un punto cuando el PIN es correcto, y lo que se
/// retrasa cada punto respecto al anterior (§1+.4).
const Duration _kWavePulse = Duration(milliseconds: 260);
const Duration _kWaveStep = Duration(milliseconds: 40);

/// Cuánto crece un punto en lo más alto de su latido (1 a 1,35).
const double _kWavePeak = 0.35;

/// Puntos que muestran cuántos dígitos hay escritos.
///
/// Cada punto es un anillo fijo con un relleno interior: al escribir un dígito
/// el relleno crece de 0,4 a 1 con `bounce`; al borrar se encoge a 0 con `fold`
/// en [clearDuration]. Los puntos son círculos (permitido). Con «Reducir
/// movimiento» el relleno solo se funde en 150 ms.
class PinDots extends StatelessWidget {
  /// Crea los puntos.
  const PinDots({
    super.key,
    required this.count,
    this.total = kPinMaxLength,
    this.clearDuration = _kDotClear,
    this.error = false,
    this.wave,
  });

  /// Dígitos escritos.
  final int count;

  /// Cuántos puntos se dibujan: la longitud del PIN, si se conoce.
  final int total;

  /// El avance (0 a 1) de la ola del PIN correcto: cada punto late 260 ms, con
  /// 40 ms de desfase entre uno y otro. Sin ola, `null`.
  final Animation<double>? wave;

  /// Lo que tarda en vaciarse un punto.
  final Duration clearDuration;

  /// Si los anillos van teñidos de error (con «Reducir movimiento» el
  /// temblor se sustituye por esto).
  final bool error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Un solo nodo para toda la fila: los seis puntos son solo dibujo y no se
    // anuncian uno a uno.
    return Semantics(
      container: true,
      label: l10n.lockPinProgress(count, total),
      excludeSemantics: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < total; i++)
              _PinDot(
                index: i,
                total: total,
                filled: i < count,
                clearDuration: clearDuration,
                error: error,
                wave: wave,
              ),
          ],
        ),
      ),
    );
  }
}

class _PinDot extends StatefulWidget {
  const _PinDot({
    required this.index,
    required this.total,
    required this.filled,
    required this.clearDuration,
    required this.error,
    required this.wave,
  });

  final int index;
  final int total;
  final Animation<double>? wave;
  final bool filled;
  final Duration clearDuration;
  final bool error;

  @override
  State<_PinDot> createState() => _PinDotState();
}

class _PinDotState extends State<_PinDot> with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController.unbounded(
    vsync: this,
    value: widget.filled ? 1 : 0,
  );

  /// Si el último cambio fue rellenar (la opacidad sube con la escala) o
  /// vaciar (la opacidad baja con ella).
  bool _filling = true;
  bool _fade = false;

  @override
  void didUpdateWidget(_PinDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filled == widget.filled) {
      return;
    }
    _filling = widget.filled;
    _fade = RegalosMotion.of(context).reduce;
    _fill.stop();
    if (widget.filled) {
      if (_fade) {
        _fill
          ..value = 0
          ..animateTo(1, duration: RegalosMotion.fade, curve: Curves.linear);
      } else {
        _fill
          ..value = 0.4
          ..animateWith(
            SpringSimulation(RegalosSprings.bounce, 0.4, 1, 0, snapToEnd: true),
          );
      }
    } else if (widget.clearDuration == Duration.zero) {
      _fill.value = 0;
    } else {
      _fill.animateTo(
        0,
        duration: _fade ? RegalosMotion.fade : widget.clearDuration,
        curve: _fade ? Curves.linear : RegalosCurves.fold,
      );
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  /// El latido de este punto en la ola: de 1 a 1,35 y a 1 con `easeInOut`.
  double _pulse() {
    final wave = widget.wave;
    if (wave == null) {
      return 1;
    }
    final total = _waveDuration(widget.total).inMicroseconds;
    final local =
        (wave.value * total - (_kWaveStep * widget.index).inMicroseconds) /
        _kWavePulse.inMicroseconds;
    if (local <= 0 || local >= 1) {
      return 1;
    }
    final half = local < 0.5 ? local * 2 : (1 - local) * 2;
    return 1 + _kWavePeak * Curves.easeInOut.transform(half);
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final errorColor = t.danger;
    return AnimatedContainer(
      // Con «Reducir movimiento» el error tiñe el anillo en 150 ms.
      duration: RegalosMotion.fade,
      width: 14,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.error ? errorColor : t.chipBorder,
          width: 1.5,
        ),
      ),
      child: AnimatedBuilder(
        animation: widget.wave == null
            ? _fill
            : Listenable.merge([_fill, widget.wave]),
        builder: (context, _) {
          final v = _fill.value;
          if (v <= 0.001) {
            return const SizedBox.shrink();
          }
          final fillCircle = AnimatedContainer(
            duration: RegalosMotion.fade,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.error ? errorColor : t.ink,
            ),
          );
          // Con «Reducir movimiento» solo se funde: nada escala.
          if (RegalosMotion.of(context).reduce) {
            return Opacity(opacity: v.clamp(0.0, 1.0), child: fillCircle);
          }
          final opacity = (_filling ? (v - 0.4) / 0.6 : v).clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: Transform.scale(scale: v * _pulse(), child: fillCircle),
          );
        },
      ),
    );
  }
}

/// Lo que dura la ola de [total] puntos.
Duration _waveDuration(int total) => _kWaveStep * (total - 1) + _kWavePulse;

/// Los puntos del PIN con su respuesta al error: [ShakeX] y, con «Reducir
/// movimiento», el anillo teñido de error (§1.4 de
/// la guía de movimiento).
///
/// Con una `GlobalKey<PinDisplayState>`, [PinDisplayState.fail] lanza el
/// temblor y la háptica fuerte, mantiene los puntos llenos mientras tiembla y
/// los vacía a la vez en 180 ms con `fold` al acabar (560 ms). El primer
/// dígito nuevo corta el temblor y vacía los puntos al momento.
class PinDisplay extends StatefulWidget {
  /// Crea los puntos con su temblor.
  const PinDisplay({
    super.key,
    required this.count,
    this.total = kPinMaxLength,
  });

  /// Dígitos escritos.
  final int count;

  /// Longitud del PIN.
  final int total;

  @override
  State<PinDisplay> createState() => PinDisplayState();
}

/// El estado de [PinDisplay]: [fail].
class PinDisplayState extends State<PinDisplay>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ShakeXState> _shake = GlobalKey<ShakeXState>();
  late final AnimationController _wave = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );
  Timer? _timer;

  /// Cuántos puntos se siguen viendo llenos mientras dura el error.
  int? _held;
  bool _tint = false;
  Duration _clear = _kDotClear;

  /// El PIN era erróneo: tiembla, vibra fuerte y, al acabar, se vacía. [filled]
  /// es cuántos puntos estaban llenos. La vibración de
  /// error sale con el temblor.
  void fail(int filled) {
    _timer?.cancel();
    context.haptics.error();
    final reduce = RegalosMotion.of(context).reduce;
    setState(() {
      _held = filled;
      _tint = reduce;
      _clear = _kDotClearAfterError;
    });
    if (!reduce) {
      _shake.currentState?.shake();
    }
    _timer = Timer(reduce ? _kReduceErrorTint : RegalosShake.duration, () {
      _timer = null;
      if (mounted) {
        setState(() {
          _held = null;
          _tint = false;
        });
      }
    });
  }

  /// El PIN era correcto: los puntos se quedan llenos y laten uno tras otro
  /// (1 a 1,35 a 1 en 260 ms, 40 ms de desfase), como una ola de izquierda a
  /// derecha mientras el candado se va. [filled] es cuántos puntos estaban
  /// llenos. Con «Reducir movimiento» no hace nada.
  void succeed(int filled) {
    if (!mounted || RegalosMotion.of(context).reduce) {
      return;
    }
    _timer?.cancel();
    final total = _waveDuration(widget.total);
    setState(() {
      _held = filled;
      _tint = false;
      _clear = _kDotClearAfterError;
    });
    _wave.duration = total;
    unawaited(
      _wave.forward(from: 0).whenComplete(() {
        if (mounted) {
          setState(() => _held = null);
        }
      }),
    );
  }

  @override
  void didUpdateWidget(PinDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count == widget.count) {
      return;
    }
    if (_held == null) {
      // Escribir o borrar a mano vuelve al ritmo normal de 120 ms.
      _clear = _kDotClear;
    } else if (widget.count > 0) {
      // Se escribió otro dígito durante el error: corta el temblor y vacía los
      // puntos al momento.
      _timer?.cancel();
      _timer = null;
      _shake.currentState?.cancel();
      _held = null;
      _tint = false;
      _clear = Duration.zero;
    }
    // Con el error en curso y `count == 0` (quien llama ya vació su PIN), los
    // puntos siguen llenos hasta que acabe el temblor.
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShakeX(
    key: _shake,
    child: PinDots(
      count: _held ?? widget.count,
      total: widget.total,
      clearDuration: _clear,
      error: _tint,
      wave: _wave.isAnimating ? _wave : null,
    ),
  );
}

/// Coloca el bloque del PIN (título, puntos y teclado) en su pantalla
/// (la guía de diseño para tablet, §3 «Bloqueo y PIN»).
///
/// - **En el móvil** (ventana compacta) no cambia nada: el bloque va donde
///   dice [compactAlignment], con [compactPadding].
/// - **Desde 600 dp**, centrado y un poco por encima del centro, con el ancho
///   que tiene en el móvil ([maxWidth]): ni las teclas ni los textos se
///   estiran.
/// - Con la ventana ancha pero de menos de [minHeight] de alto se queda como
///   en el móvil, arriba y con desplazamiento.
///
/// El árbol es el mismo en los tres casos (solo cambian la alineación, el
/// margen y el ancho máximo), así que girar la tablet no pierde lo escrito ni
/// corta el temblor o la ola de los puntos. Cruzar el corte no se anima.
class PinBlock extends StatelessWidget {
  /// Crea el bloque.
  const PinBlock({
    super.key,
    required this.child,
    this.compactAlignment = Alignment.center,
    this.compactPadding = const EdgeInsets.symmetric(
      horizontal: 24,
      vertical: 16,
    ),
  });

  /// Alto de ventana desde el que el bloque se centra.
  static const double minHeight = 560;

  /// Ancho máximo del bloque, con sus márgenes: el del móvil de las maquetas.
  static const double maxWidth = 390;

  /// Dónde queda el bloque desde 600 dp: centrado, un 6 % del alto por encima
  /// del centro en la tablet en vertical (maqueta B).
  static const Alignment wideAlignment = Alignment(0, -0.2);

  /// El margen del bloque desde 600 dp.
  static const EdgeInsets widePadding = EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 16,
  );

  /// Si en esta ventana el bloque va centrado (ni compacta ni baja).
  static bool isCentered(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return WindowClass.fromSize(size) != WindowClass.compact &&
        size.height >= minHeight;
  }

  /// Dónde va el bloque en el móvil.
  final AlignmentGeometry compactAlignment;

  /// El margen del bloque en el móvil.
  final EdgeInsetsGeometry compactPadding;

  /// El bloque: una columna con el título, los puntos y el teclado.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final centered = isCentered(context);
    return Align(
      alignment: centered ? wideAlignment : compactAlignment,
      child: ContentWidth(
        maxWidth: centered ? maxWidth : double.infinity,
        child: SingleChildScrollView(
          padding: centered ? widePadding : compactPadding,
          child: child,
        ),
      ),
    );
  }
}

/// Teclado numérico de 3 por 4. Con [onBiometric] la tecla de abajo a la
/// izquierda lanza la huella o el rostro.
class PinPad extends StatelessWidget {
  /// Crea el teclado.
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
    this.enabled = true,
  });

  /// Se pulsa un dígito (`'0'` a `'9'`).
  final ValueChanged<String> onDigit;

  /// Se pulsa borrar.
  final VoidCallback onBackspace;

  /// Se pulsa el botón biométrico; sin él no hay botón.
  final VoidCallback? onBiometric;

  /// Si las teclas responden.
  final bool enabled;

  /// Lo que mide el teclado de ancho (tres teclas con su hueco): el botón de
  /// debajo puede ocupar lo mismo para no cambiar de ancho al cambiar su texto.
  static const double width = 3 * (_keyWidth + 2 * _keyGap);

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);
    Widget digit(String d) => _Key(
      label: d,
      onTap: enabled ? () => onDigit(d) : null,
      child: Text(
        d,
        style: t.styles.screenTitle.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final d in row) digit(d)],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onBiometric != null)
              _Key(
                label: l10n.lockBiometric,
                onTap: enabled ? onBiometric : null,
                filled: true,
                child: StrokeIcon(
                  tablerFingerprint,
                  size: 30,
                  color: t.ink,
                  strokeWidth: 1.5,
                ),
              )
            else
              const SizedBox(width: _keyWidth + 2 * _keyGap),
            digit('0'),
            _Key(
              label: l10n.lockBackspace,
              onTap: enabled ? onBackspace : null,
              child: StrokeIcon(
                tablerBackspace,
                size: 28,
                color: t.text,
                strokeWidth: 1.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

const double _keyWidth = 84;
const double _keyHeight = 66;
const double _keyGap = 6;

class _Key extends StatefulWidget {
  const _Key({
    required this.label,
    required this.onTap,
    required this.child,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  /// La tecla de la huella: relleno del acento y borde a juego.
  final bool filled;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    // Respuesta inmediata, sin escala: el fondo se tiñe en 80 ms al pulsar y
    // vuelve con `soft`. Con «Reducir movimiento» el regreso es de 150 ms.
    final reduce = RegalosMotion.of(context).reduce;
    return Padding(
      padding: const EdgeInsets.all(_keyGap),
      child: Semantics(
        button: true,
        enabled: widget.onTap != null,
        label: widget.label,
        excludeSemantics: true,
        onTap: widget.onTap,
        // El `Material` recorta con la forma de la tecla (rectángulo de
        // radio 8); el tinte de pulsación va dentro, sobre su fondo.
        child: Material(
          color: widget.filled ? t.fill : t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: RegalosShape.key,
            side: BorderSide(
              color: widget.filled ? t.swatchBorder : t.separator,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            onHighlightChanged: (down) {
              if (_pressed != down) {
                setState(() => _pressed = down);
              }
            },
            customBorder: const RoundedRectangleBorder(
              borderRadius: RegalosShape.key,
            ),
            child: AnimatedContainer(
              duration: _pressed
                  ? const Duration(milliseconds: 80)
                  : (reduce ? RegalosMotion.fade : RegalosSprings.softDuration),
              curve: _pressed || reduce ? Curves.linear : RegalosCurves.soft,
              color: _pressed ? t.soft : t.soft.withValues(alpha: 0),
              width: _keyWidth,
              height: _keyHeight,
              alignment: Alignment.center,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
