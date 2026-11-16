import 'package:flutter/material.dart';

import '../layout/pane_selection.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';
import 'pointer_surface.dart';

/// La fila del panel de lista de los dos paneles de escritorio: la misma en
/// Personas y en Ocasiones (y la de Ajustes, con sus medidas), para que las
/// tres listas se lean igual.
///
/// Plana: sin tarjeta, sin borde y sin filete de debajo. Con un margen de
/// [kPaneRowInset] a cada lado y 2 de aire arriba y abajo; la elegida la pinta
/// el recuadro que viaja por detrás (`SelectionScope`, de 1 px de borde y
/// radio 8), y al pasar el ratón se tiñe como en el resto.
///
/// [child] es el contenido con el relleno de [kPaneRowPadding] ya puesto: el
/// nombre con [nameStyle] y los datos con `meta` (13).
class PaneListRow extends StatelessWidget {
  /// Crea la fila.
  const PaneListRow({
    super.key,
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
    this.minHeight = kPaneRowHeight,
  });

  /// El id con el que el recuadro de selección la busca.
  final Object id;

  /// La frase que lee un lector de pantalla.
  final String label;

  /// Si es la fila elegida.
  final bool selected;

  /// Lo que hace al tocarla.
  final VoidCallback onTap;

  /// Lo que lleva dentro.
  final Widget child;

  /// El alto mínimo de la fila, sin el aire de arriba y abajo.
  final double minHeight;

  /// El estilo del nombre en una fila de lista: 15, peso 600.
  static TextStyle nameStyle(RegalosTokens t) => t.styles.rowTitle.copyWith(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kPaneRowInset,
          vertical: 2,
        ),
        child: SelectionRow(
          id: id,
          // Cada fila en su capa: el hover de una no repinta la lista.
          child: RepaintBoundary(
            child: PointerSurface(
              child: Material(
                color: Colors.transparent,
                shape: const RoundedRectangleBorder(
                  borderRadius: RegalosShape.card,
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minHeight),
                    child: Padding(padding: kPaneRowPadding, child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El margen horizontal de las filas de un panel de lista de escritorio.
const double kPaneRowInset = 8;

/// El alto de las filas de un panel de lista sin el aire de 2 de arriba y
/// abajo (la fila entera mide 64).
const double kPaneRowHeight = 60;

/// El relleno de dentro de una fila de panel de lista.
const EdgeInsets kPaneRowPadding = EdgeInsets.symmetric(
  horizontal: 12,
  vertical: 6,
);
