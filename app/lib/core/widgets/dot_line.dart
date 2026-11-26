import 'package:flutter/widgets.dart';

import '../motion/rolling_number.dart';

/// Un trozo de una [DotLine]: un texto y, si lleva una cifra que rueda, esa
/// cifra.
class DotPart {
  /// Crea el trozo.
  const DotPart(this.text, {this.rollValue, this.rollSearchFrom = 0});

  /// El texto ya traducido.
  final String text;

  /// La cifra de [text] que rueda, o `null` si no hay.
  final int? rollValue;

  /// Desde dónde buscar la cifra en [text].
  final int rollSearchFrom;
}

/// Una línea de trozos separados por « · » («3 años · 10 regalos · 5
/// deseos») que, si no cabe, sigue en la de abajo cortando solo entre trozos y
/// con el separador **al final** del trozo anterior: nunca empieza una línea
/// con «·» ni deja un trozo con sangría.
///
/// El separador va pegado al trozo con un espacio duro, así que tampoco se
/// queda solo si un trozo largo (el nombre de una ocasión) se parte por dentro.
class DotLine extends StatelessWidget {
  /// Crea la línea.
  const DotLine({super.key, required this.parts, required this.style});

  /// Los trozos, en orden.
  final List<DotPart> parts;

  /// El estilo de todo el texto.
  final TextStyle style;

  /// El espacio duro que pega el separador al trozo anterior.
  static const String glue = '\u00A0·';

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final space = scaler.scale(style.fontSize ?? 14) * 0.28;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: space,
      children: [
        for (var i = 0; i < parts.length; i++)
          _piece(parts[i], i < parts.length - 1),
      ],
    );
  }

  Widget _piece(DotPart part, bool more) {
    final text = more ? '${part.text}$glue' : part.text;
    final value = part.rollValue;
    // El lector de pantalla lee el trozo sin el separador.
    return Semantics(
      label: part.text,
      excludeSemantics: true,
      child: value == null
          ? Text(text, style: style)
          : RollingCount(
              text: text,
              value: value,
              style: style,
              searchFrom: part.rollSearchFrom,
              breakable: false,
            ),
    );
  }
}
