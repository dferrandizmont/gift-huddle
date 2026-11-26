import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';
import 'content_width.dart';

/// Da a [builder] el margen que queda a cada lado de una columna de
/// [maxWidth] centrada en el sitio que le dan a este widget
/// (`ContentWidth.gutter`). Cero si la columna cabe entera: en el móvil.
///
/// Es para lo que no se puede envolver en `ContentWidth`: una lista que debe
/// seguir desplazándose al arrastrar por los márgenes (el margen va como
/// `padding`) o el «+» de un `Scaffold`, que se alinea con la columna.
///
/// Mide con las restricciones de la maquetación, no con
/// `PaneScope.widthOf`: una pantalla que sigue montada debajo de otra (la
/// lista bajo su detalle) se reconstruye cuando cambia el panel, pero se
/// maqueta con las restricciones de la última vez que estuvo a la vista. Con
/// el ancho heredado, al pasar de móvil a tablet el margen nuevo no cabe en
/// el ancho viejo y el contenido se queda sin sitio; así, margen y ancho
/// salen siempre de la misma medida.
class ContentGutter extends StatelessWidget {
  const ContentGutter({
    super.key,
    required this.maxWidth,
    required this.builder,
  });

  /// Ancho máximo de la columna. Las medidas están en `RegalosLayout`.
  final double maxWidth;

  /// Construye el hijo con el margen de cada lado.
  final Widget Function(BuildContext context, double gutter) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        builder(context, ContentWidth.gutter(constraints.maxWidth, maxWidth)),
  );
}

/// Un `ListView` cuyo contenido va en una columna de [maxWidth] centrada: el
/// margen de [ContentGutter] se suma a [padding] por los dos lados, así que
/// la lista ocupa todo el sitio y se desplaza también arrastrando por los
/// márgenes. Por debajo de [maxWidth] es un `ListView` con [padding], sin más.
class ContentListView extends StatelessWidget {
  const ContentListView({
    super.key,
    required this.maxWidth,
    this.padding = EdgeInsets.zero,
    this.storageKey,
    this.controller,
    required this.children,
  });

  /// Ancho máximo de la columna. Las medidas están en `RegalosLayout`.
  final double maxWidth;

  /// Quien sigue o gobierna el desplazamiento de la lista, o `null`.
  final ScrollController? controller;

  /// El relleno de la lista sin contar el margen de la columna.
  final EdgeInsets padding;

  /// Si la posición de la lista se guarda en el `PageStorage` que haya por
  /// encima (y se recupera al volver a montarla). Con dos paneles, Personas
  /// la monta en una página u otra según la ventana.
  final PageStorageKey<String>? storageKey;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ContentGutter(
    maxWidth: maxWidth,
    builder: (context, gutter) => ListView(
      key: storageKey,
      controller: controller,
      padding: padding + EdgeInsets.symmetric(horizontal: gutter),
      children: children,
    ),
  );
}

/// El «+» de un `Scaffold` (u otro botón flotante), a su distancia de siempre
/// del borde de una columna de [maxWidth] centrada, y no del borde del panel.
/// Por debajo de [maxWidth] no hace nada.
///
/// Con el teclado abierto (o con [hidden]: la búsqueda) se esconde: el
/// `Scaffold` lo sube encima del teclado y taparía justo lo que se está
/// escribiendo o buscando. Vuelve al cerrarse el teclado.
class ContentFloatingButton extends StatefulWidget {
  const ContentFloatingButton({
    super.key,
    required this.maxWidth,
    required this.child,
    this.hidden = false,
  });

  /// Ancho máximo de la columna. Las medidas están en `RegalosLayout`.
  final double maxWidth;

  final Widget child;

  /// Si se esconde aunque no haya teclado.
  final bool hidden;

  @override
  State<ContentFloatingButton> createState() => _ContentFloatingButtonState();
}

class _ContentFloatingButtonState extends State<ContentFloatingButton>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // El teclado se lee de la vista y no de `MediaQuery`: el `Scaffold` de
  // abajo ya se lo ha quitado a lo que lleva dentro.
  bool _keyboard = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboard = View.of(context).viewInsets.bottom > 0;
  }

  // Solo se repinta si el teclado se abre o se cierra (no con cada cambio
  // de métricas: giros, barras...).
  @override
  void didChangeMetrics() {
    if (!mounted) {
      return;
    }
    final keyboard = View.of(context).viewInsets.bottom > 0;
    if (keyboard != _keyboard) {
      setState(() => _keyboard = keyboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hide = widget.hidden || _keyboard;
    final reduce = RegalosMotion.of(context).reduce;
    return ContentGutter(
      maxWidth: widget.maxWidth,
      builder: (context, gutter) => Padding(
        padding: EdgeInsetsDirectional.only(end: gutter),
        child: ExcludeFocus(
          excluding: hide,
          child: ExcludeSemantics(
            excluding: hide,
            child: IgnorePointer(
              ignoring: hide,
              child: AnimatedOpacity(
                opacity: hide ? 0 : 1,
                duration: RegalosMotion.fade,
                child: AnimatedScale(
                  scale: hide && !reduce ? 0.85 : 1,
                  duration: RegalosCurves.foldDuration,
                  curve: RegalosCurves.fold,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
