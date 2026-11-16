import 'package:flutter/material.dart';

import '../motion/rolling_number.dart';
import '../motion/sheen.dart';
import '../motion/value_switcher.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_tokens.dart';

/// Barra fina de progreso de las maquetas (4 px) con su etiqueta accesible.
///
/// Al cambiar [fraction] el relleno crece o mengua con `snap` (375 ms) y, si
/// se pasa del presupuesto (más de 1), el color pasa a aviso con `soft`.
/// Cuando crece, una banda de luz ([Sheen]) recorre la parte llena con 120 ms
/// de retardo. Con «Reducir movimiento» la barra salta con un fundido de
/// 150 ms, sin brillo.
class BudgetBar extends StatefulWidget {
  const BudgetBar({
    super.key,
    required this.fraction,
    required this.semanticLabel,
    this.height = 4,
  });

  /// De 0 a 1 (más de 1 si se pasó del presupuesto).
  final double fraction;
  final String semanticLabel;
  final double height;

  @override
  State<BudgetBar> createState() => _BudgetBarState();
}

class _BudgetBarState extends State<BudgetBar> {
  final GlobalKey<SheenState> _sheen = GlobalKey<SheenState>();

  static double _clean(double fraction) => fraction.isNaN ? 0.0 : fraction;

  @override
  void didUpdateWidget(BudgetBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_clean(widget.fraction).clamp(0.0, 1.0) >
        _clean(oldWidget.fraction).clamp(0.0, 1.0)) {
      // Tras el fotograma: el brillo se lanza con la barra ya creciendo.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sheen.currentState?.play(delay: const Duration(milliseconds: 120));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final raw = _clean(widget.fraction);
    final value = raw.clamp(0.0, 1.0);
    final over = raw > 1;
    final inkColor = over ? t.danger : t.ink;
    final reduce = RegalosMotion.of(context).reduce;
    final height = widget.height;

    Widget bar(double widthFactor, {Key? key, bool sheen = false}) {
      final fill = AnimatedContainer(
        duration: reduce ? Duration.zero : RegalosSprings.softDuration,
        curve: RegalosCurves.soft,
        height: height,
        color: inkColor,
      );
      return FractionallySizedBox(
        key: key,
        widthFactor: widthFactor,
        child: sheen ? Sheen(key: _sheen, child: fill) : fill,
      );
    }

    final Widget fill = reduce
        ? AnimatedSwitcher(
            duration: RegalosMotion.fade,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, ?current],
            ),
            child: bar(value, key: ValueKey(value)),
          )
        : TweenAnimationBuilder<double>(
            tween: Tween<double>(end: value),
            duration: RegalosSprings.snapDuration,
            curve: RegalosCurves.snap,
            builder: (context, v, _) => bar(v.clamp(0.0, 1.0), sheen: true),
          );

    return Semantics(
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: Container(
          height: height,
          color: t.track,
          alignment: Alignment.centerLeft,
          child: fill,
        ),
      ),
    );
  }
}

/// Importe gastado de un previsto, con su barra: «72,94 € de 145 €».
///
/// La cifra de lo gastado rueda ([RollingNumber]) cuando cambia; lo previsto
/// se cruza con un fundido corto.
class BudgetMeter extends StatelessWidget {
  const BudgetMeter({
    super.key,
    required this.label,
    required this.valueText,
    required this.fraction,
    required this.semanticLabel,
  });

  final String label;

  /// Ya escrito para el idioma, con el «de» dentro.
  final ({String spent, String planned, String ofWord}) valueText;
  final double fraction;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final spentStyle = t.styles.label.copyWith(
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
    );
    final plannedStyle = t.styles.meta.copyWith(fontSize: 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.styles.meta.copyWith(fontSize: 12.5)),
        Semantics(
          container: true,
          label: '${valueText.spent} ${valueText.ofWord} ${valueText.planned}',
          excludeSemantics: true,
          // Un `Wrap` y no un `Row`: si no cabe, «de 145 €» baja de línea como
          // lo haría un texto normal.
          child: Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              RollingNumber.text(text: valueText.spent, style: spentStyle),
              ValueSwitcher(
                dy: 0,
                child: Text(
                  // Sin espacio delante (lo pone el `spacing` del `Wrap`): si la
                  // línea se parte, la segunda no empieza con una sangría.
                  '${valueText.ofWord} ${valueText.planned}',
                  key: ValueKey(valueText.planned),
                  style: plannedStyle,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        BudgetBar(fraction: fraction, semanticLabel: semanticLabel),
      ],
    );
  }
}
