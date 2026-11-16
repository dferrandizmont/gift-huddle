import 'package:flutter/material.dart';

import '../layout/pane_scope.dart';
import '../layout/window_class.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_shape.dart';
import '../theme/regalos_tokens.dart';

/// El velo de las hojas en claro. En oscuro es el token `scrim` (negro puro
/// al 52 %): las rutas lo reciben ya resuelto con `RegalosTokens.of(context)`.
const Color kSheetBarrierColor = Color(0x5217171C);

/// El panel al que pertenece lo que se abre en la capa raíz (una hoja, el
/// editor): lo pone la ruta alrededor de su contenido.
///
/// Las hojas viven fuera de su panel, así que dentro de una ya no hay
/// `PaneScope` por encima. Con esto, lo que se abre desde dentro de una hoja
/// (un selector desde el editor) se centra en el mismo panel que ella.
class SheetPane extends InheritedWidget {
  /// Guarda [anchor] para lo que se abra desde [child].
  const SheetPane({super.key, required this.anchor, required super.child});

  /// El ancla del panel desde el que se abrió la hoja; `null`, la ventana.
  final PaneAnchor? anchor;

  /// El ancla del panel de [context]: el de la hoja en la que está o, si no
  /// está en ninguna, el de su `PaneScope`. `null` si no hay panel (una ruta
  /// del navegador raíz): entonces se centra en la ventana.
  ///
  /// Se llama al abrir la hoja, desde el manejador del toque.
  static PaneAnchor? anchorOf(BuildContext context) {
    final sheet = context.getInheritedWidgetOfExactType<SheetPane>();
    return sheet == null ? PaneScope.anchorOf(context) : sheet.anchor;
  }

  @override
  bool updateShouldNotify(SheetPane oldWidget) => anchor != oldWidget.anchor;
}

/// Abre una hoja inferior con el movimiento de la app: sube como una tarjeta
/// con `snap` y se va con `sheetExit`; el velo es el de Reparto.
///
/// Mide [maxWidth] como mucho (560) y se centra en el panel desde el que se
/// abre: con un panel, el área de contenido (la ventana menos el raíl). El
/// velo cubre la ventana entera. En el móvil el panel es la pantalla y la
/// hoja va de lado a lado, como siempre.
///
/// Con «Reducir movimiento» la hoja no se desliza: aparece con un fundido de
/// 150 ms. Es el único sitio que pone `sheetAnimationStyle`, así que toda hoja
/// (selectores, edición, filtros) pasa por aquí.
Future<T?> showRegalosSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  BoxConstraints? constraints,
  bool flat = false,
  double maxWidth = RegalosLayout.sheetWidth,
}) {
  final motion = RegalosMotion.of(context);
  final tokens = RegalosTokens.of(context);
  final anchor = SheetPane.anchorOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final localizations = MaterialLocalizations.of(context);
  final WidgetBuilder content = motion.reduce
      ? (sheetContext) => TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: RegalosMotion.fade,
          builder: (_, opacity, child) =>
              Opacity(opacity: opacity, child: child),
          child: Builder(builder: builder),
        )
      : builder;
  // Lo mismo que hace `showModalBottomSheet`, con una ruta que sabe centrarse
  // en un panel: la de Material solo se centra en la ventana.
  return navigator.push<T>(
    _RegalosSheetRoute<T>(
      anchor: anchor,
      maxWidth: maxWidth,
      builder: (sheetContext) => SheetPane(
        anchor: anchor,
        child: Builder(builder: content),
      ),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      // Las hojas de Ajustes y Compartir llevan esquinas de 8, como todo lo
      // demás; el resto usa el radio del tema, que también es 8.
      shape: flat
          ? RoundedRectangleBorder(
              side: BorderSide(color: tokens.sheetEdge),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(RegalosShape.flatSheetRadius),
              ),
            )
          : null,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      constraints: constraints,
      modalBarrierColor: tokens.scrim,
      sheetAnimationStyle: motion.sheetStyle,
    ),
  );
}

/// La ruta de [showRegalosSheet]: la hoja modal de Material, puesta en una
/// columna de [maxWidth] centrada en el panel de [anchor]. El velo es de la
/// ruta y sigue cubriendo la ventana, raíl incluido.
class _RegalosSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _RegalosSheetRoute({
    required this.anchor,
    required this.maxWidth,
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.shape,
    super.constraints,
    super.modalBarrierColor,
    super.useSafeArea,
    super.sheetAnimationStyle,
  });

  final PaneAnchor? anchor;
  final double maxWidth;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => PaneAligned(
    anchor: anchor,
    maxWidth: maxWidth,
    child: super.buildPage(context, animation, secondaryAnimation),
  );
}
