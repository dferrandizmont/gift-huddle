import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';

/// El botón de borrar de un editor: a todo el ancho, con el contorno y el
/// texto en el rojo de peligro del tema.
///
/// Va sin relleno para no competir con «Guardar», que es la acción principal;
/// el relleno suave (`dangerSoft`) queda para el botón que confirma en el
/// diálogo. Quien lo usa pregunta antes de borrar (`showRegalosConfirm`).
class DangerButton extends StatelessWidget {
  /// Crea el botón.
  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

  /// Si va en una fila junto a «Cancelar» y «Guardar» (el pie del panel o del
  /// diálogo del editor): un botón de texto en rojo, sin borde ni relleno y del
  /// ancho de su texto, para que no compita con «Guardar». Si no, va a todo el
  /// ancho con el contorno rojo.
  final bool compact;

  /// El texto.
  final String label;

  /// Se llama al pulsarlo; `null` lo desactiva.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    if (compact) {
      return TextButton(
        style: TextButton.styleFrom(
          foregroundColor: t.danger,
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: const RoundedRectangleBorder(
            borderRadius: RegalosShape.button,
          ),
          textStyle: t.styles.label.copyWith(
            fontSize: 15,
            fontFamily: kAppFontFamily,
          ),
        ),
        onPressed: onPressed,
        child: Text(label, maxLines: 1, softWrap: false),
      );
    }
    final button = OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.danger,
        minimumSize: const Size(44, 48),
        side: BorderSide(color: t.danger),
        shape: const RoundedRectangleBorder(borderRadius: RegalosShape.button),
        textStyle: t.styles.label.copyWith(
          fontSize: 15,
          fontFamily: kAppFontFamily,
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
    return SizedBox(width: double.infinity, child: button);
  }
}
