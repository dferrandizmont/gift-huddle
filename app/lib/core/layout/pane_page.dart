import 'package:flutter/material.dart';

import 'window_class.dart';

/// Una página de una rama con dos paneles: como `MaterialPage` (la transición
/// del tema, el gesto de volver de iOS, los `Hero`), pero sin ninguna
/// transición cuando la ventana tiene dos paneles.
///
/// Con dos paneles, cada página pinta la lista y el detalle enteros. Que la
/// de encima entre deslizándose enseñaría la lista corriéndose de sitio, y la
/// lista no se mueve nunca (§4.2 del plan de tablet): la página nueva
/// sustituye a la vieja en el acto y lo único que se anima es lo que cambia
/// dentro del detalle.
///
/// Quien cambia de persona con la misma ruta (`/people/a` a `/people/b`)
/// reutiliza la página y no pasa por aquí: la ruta es la misma.
class PanePage extends Page<void> {
  /// Crea la página.
  const PanePage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// El contenido de la ruta.
  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => _PaneRoute(page: this);
}

class _PaneRoute extends PageRoute<void>
    with MaterialRouteTransitionMixin<void> {
  _PaneRoute({required PanePage page}) : super(settings: page);

  PanePage get _page => settings as PanePage;

  /// Si la ventana tiene dos paneles ahora mismo.
  bool _twoPanes(BuildContext? context) {
    if (context == null || !context.mounted) {
      return false;
    }
    final size = MediaQuery.maybeSizeOf(context);
    return size != null && WindowClass.fromSize(size).usesTwoPanes;
  }

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => true;

  @override
  bool get fullscreenDialog => false;

  @override
  Duration get transitionDuration =>
      _twoPanes(navigator?.context) ? Duration.zero : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _twoPanes(navigator?.context)
      ? Duration.zero
      : super.reverseTransitionDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _twoPanes(context)
      ? child
      : super.buildTransitions(context, animation, secondaryAnimation, child);

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';
}
