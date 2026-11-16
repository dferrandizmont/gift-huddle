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

  /// Si va en una fila (el pie del panel del editor): del ancho de su texto y
  /// de 40 de alto, en vez de a todo el ancho.
  final bool compact;

  /// El texto.
  final String label;

  /// Se llama al pulsarlo; `null` lo desactiva.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final button = OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.danger,
        minimumSize: Size(44, compact ? 40 : 48),
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
    return compact ? button : SizedBox(width: double.infinity, child: button);
  }
}
