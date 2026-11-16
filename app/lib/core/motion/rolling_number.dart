import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';

/// Una cifra que rueda como un cuentakilómetros (§2.4 y «Recursos nuevos» de
/// la guía de movimiento): una columna por cifra; la nueva sube
/// desde +60 % y la vieja se va hacia −60 % con `snap`, desfasadas 30 ms de
/// derecha a izquierda. Solo ruedan las cifras que cambian: de 43 a 44, solo
/// la última.
///
/// - Sin [rollFromEmpty] ni [cue], la primera vez se pinta quieta.
/// - Con [rollFromEmpty], la primera vez rueda desde un valor vacío, tras
///   [delay] (la primera vista del carrusel, con 60 ms entre tarjetas).
/// - Cuando cambia [cue], rueda desde [cueFrom] (o desde vacío) hasta [value]
///   sin que [value] haya cambiado: el carrusel lo usa al llegar a una tarjeta.
/// - Cuando cambia [value], rueda del valor anterior al nuevo; si sube o baja
///   decide hacia dónde se va.
///
/// Un `ShaderMask` vertical funde 0,13 em arriba y abajo mientras ruedan, para
/// que las cifras entren y salgan sin corte duro. Lleva cifras tabulares.
/// Con «Reducir movimiento» las cifras se cruzan con un fundido de 150 ms, sin
/// desplazarse.
class RollingNumber extends StatefulWidget {
  /// Crea la cifra.
  const RollingNumber({
    super.key,
    required this.value,
    required this.style,
    this.rollFromEmpty = false,
    this.delay = Duration.zero,
    this.cue,
    this.cueFrom,
  }) : text = null,
       leftToRight = false;

  /// Como [RollingNumber], pero con un texto cualquiera («72,94 €»): ruedan
  /// las columnas (alineadas por la derecha) cuyo carácter cambia y el resto
  /// se queda quieto.
  const RollingNumber.text({
    super.key,
    required String this.text,
    required this.style,
    this.rollFromEmpty = false,
    this.delay = Duration.zero,
    this.cue,
    this.cueFrom,
    this.leftToRight = false,
  }) : value = 0;

  /// El número que se muestra.
  final int value;

  /// Solo en [RollingNumber.text]: las cifras ruedan de izquierda a derecha y
  /// por grupos (los separados por un espacio, como «123 456»): el grupo de la
  /// izquierda sale primero y el siguiente 60 ms después. Sin él, ruedan de
  /// derecha a izquierda, desfasadas 30 ms cada una.
  final bool leftToRight;

  /// El texto que se muestra, si no es un número entero.
  final String? text;

  /// El estilo del texto.
  final TextStyle style;

  /// Si la primera vez rueda desde vacío.
  final bool rollFromEmpty;

  /// Retardo de la rodadura inicial o de la de [cue].
  final Duration delay;

  /// Cuando cambia, vuelve a rodar hasta [value].
  final Object? cue;

  /// Desde qué número rueda al cambiar [cue]; `null` es desde vacío.
  final int? cueFrom;

  @override
  State<RollingNumber> createState() => _RollingNumberState();
}

class _RollingNumberState extends State<RollingNumber>
    with SingleTickerProviderStateMixin {
  static const Duration _stagger = Duration(milliseconds: 30);
  static const Duration _groupStep = Duration(milliseconds: 60);

  // Con «Quitar animaciones» el controlador normal se acortaría a casi 0 y el
  // fundido de 150 ms sería un corte: se conserva su duración.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );

  String _old = '';
  late String _new = _shown(widget);
  Duration _delay = Duration.zero;
  bool _up = true;
  bool _reduce = false;

  static String _shown(RollingNumber w) => w.text ?? '${w.value}';

  @override
  void didUpdateWidget(RollingNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _shown(widget);
    if (widget.cue != oldWidget.cue) {
      _begin(
        widget.cueFrom == null ? '' : '${widget.cueFrom}',
        next,
        widget.delay,
      );
    } else if (next != _shown(oldWidget)) {
      // Lo que se veía ahora mismo (si ya estaba rodando, lo nuevo).
      _begin(_shown(oldWidget), next, Duration.zero);
    }
  }

  void _begin(String from, String to, Duration delay) {
    final columns = from.length > to.length ? from.length : to.length;
    final spread = widget.leftToRight
        ? _groupStep * ' '.allMatches(to).length
        : _stagger * (columns - 1);
    final total =
        delay +
        spread +
        (_reduce ? RegalosMotion.fade : RegalosSprings.snapDuration);
    _old = from;
    _new = to;
    _delay = delay;
    // Solo las cifras: «72,94 €» vale 7294.
    final oldValue = int.tryParse(from.replaceAll(RegExp(r'\D'), ''));
    final newValue = int.tryParse(to.replaceAll(RegExp(r'\D'), '')) ?? 0;
    _up = oldValue == null || newValue >= oldValue;
    _controller
      ..duration = total
      ..forward(from: 0);
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = RegalosMotion.of(context).reduce;
    if (!_started) {
      _started = true;
      if (widget.rollFromEmpty) {
        _begin('', _shown(widget), widget.delay);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Cuánto se retrasa la columna [fromRight] (0 es la de las unidades).
  Duration _offsetOf(int fromRight) {
    if (!widget.leftToRight) {
      return _stagger * fromRight;
    }
    // Por grupos: cuántos espacios hay a su izquierda en el texto nuevo.
    final index = _new.length - 1 - fromRight;
    if (index <= 0) {
      return Duration.zero;
    }
    return _groupStep * ' '.allMatches(_new.substring(0, index)).length;
  }

  /// El avance (0 a 1) de la columna [fromRight] (0 es la de las unidades).
  double _progress(int fromRight) {
    final total = _controller.duration!.inMicroseconds;
    final start = (_delay + _offsetOf(fromRight)).inMicroseconds;
    final length = (_reduce ? RegalosMotion.fade : RegalosSprings.snapDuration)
        .inMicroseconds;
    final raw = ((_controller.value * total - start) / length).clamp(0.0, 1.0);
    return _reduce ? raw : RegalosCurves.snap.transform(raw);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final text = _shown(widget);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final rolling =
              _controller.isAnimating ||
              (_controller.value > 0 && _controller.value < 1);
          if (!rolling) {
            return Text(text, style: style, maxLines: 1);
          }
          final newText = _new;
          final oldText = _old;
          final columns = newText.length > oldText.length
              ? newText.length
              : oldText.length;
          final fontSize = style.fontSize ?? 14;
          final fade =
              (0.13 * fontSize) /
              ((style.height ?? 1.2) * fontSize).clamp(1, double.infinity);
          final row = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < columns; i++)
                _Column(
                  oldChar: _charAt(oldText, columns - 1 - i),
                  newChar: _charAt(newText, columns - 1 - i),
                  progress: _progress(columns - 1 - i),
                  up: _up,
                  reduce: _reduce,
                  style: style,
                ),
            ],
          );
          if (_reduce) {
            return row;
          }
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [
                Color(0x00000000),
                Color(0xFF000000),
                Color(0xFF000000),
                Color(0x00000000),
              ],
              stops: [0, fade, 1 - fade, 1],
            ).createShader(rect),
            child: row,
          );
        },
      ),
    );
  }

  /// La cifra de [text] que cae en la columna [fromRight], o `null`.
  String? _charAt(String text, int fromRight) {
    final index = text.length - 1 - fromRight;
    return index < 0 || index >= text.length ? null : text[index];
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.oldChar,
    required this.newChar,
    required this.progress,
    required this.up,
    required this.reduce,
    required this.style,
  });

  final String? oldChar;
  final String? newChar;
  final double progress;
  final bool up;
  final bool reduce;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // La columna mide lo que la cifra más ancha de las dos.
    final sizing = newChar ?? oldChar ?? '';
    if (oldChar == newChar) {
      return Text(newChar ?? '', style: style, maxLines: 1);
    }
    final direction = up ? 1.0 : -1.0;
    Widget glyph(String? char, double dy, double opacity) {
      if (char == null) {
        return const SizedBox.shrink();
      }
      Widget w = Text(char, style: style, maxLines: 1);
      if (!reduce && dy != 0) {
        w = FractionalTranslation(translation: Offset(0, dy), child: w);
      }
      return Opacity(opacity: opacity.clamp(0.0, 1.0), child: w);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // Reserva el ancho sin pintar.
        Opacity(opacity: 0, child: Text(sizing, style: style, maxLines: 1)),
        glyph(oldChar, -0.6 * direction * progress, 1 - progress),
        glyph(newChar, 0.6 * direction * (1 - progress), progress),
      ],
    );
  }
}

/// Un texto con un número dentro («7 regalos», «3 de 5 comprados») donde ese
/// número rueda con [RollingNumber]. Si [text] no contiene [value], se pinta
/// tal cual.
class RollingCount extends StatelessWidget {
  /// Crea el texto.
  const RollingCount({
    super.key,
    required this.text,
    required this.value,
    required this.style,
    this.rollFromEmpty = false,
    this.searchFrom = 0,
  });

  /// El texto ya traducido, con [value] escrito dentro.
  final String text;

  /// El número que rueda.
  final int value;

  /// El estilo de todo el texto.
  final TextStyle style;

  /// Si la primera vez rueda desde vacío.
  final bool rollFromEmpty;

  /// Desde dónde buscar el número en [text] (para saltarse un nombre que
  /// pudiera llevar cifras).
  final int searchFrom;

  @override
  Widget build(BuildContext context) {
    final digits = '$value';
    final at = text.indexOf(digits, searchFrom.clamp(0, text.length));
    if (at < 0) {
      return Text(text, style: style);
    }
    return Semantics(
      label: text,
      excludeSemantics: true,
      // Un `Wrap` y no un `Row`: si el texto no cabe, sigue en la línea de
      // abajo como lo haría un texto normal.
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (at > 0) Text(text.substring(0, at), style: style),
          RollingNumber(
            value: value,
            style: style,
            rollFromEmpty: rollFromEmpty,
          ),
          if (at + digits.length < text.length)
            Text(text.substring(at + digits.length), style: style),
        ],
      ),
    );
  }
}
