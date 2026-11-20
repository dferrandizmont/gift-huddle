import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'regalos_tokens.dart';

/// Las barras de desplazamiento de la app: finas, de tinta suave y sin flechas.
///
/// - Reposo: 6 de grosor y tinta al 28 % (40 % en oscuro); al pasar el ratón,
///   9 y 20 puntos más; al arrastrar el pulgar, 34 más. Aparecen al desplazar o al pasar el ratón y
///   se desvanecen solas (el ritmo es el de Material).
/// - Radio de 4 como mucho y un hueco de 2 contra el borde.
/// - Sin pista de fondo: el contenido no se tapa con una banda.
/// - En el móvil no hay barras: el sistema se encarga y la app no pinta nada.
///
/// Material envuelve solo cada lista vertical con una `Scrollbar` en
/// escritorio y en la web: ponerle otra encima pinta dos pulgares (más gruesos
/// y oscuros). Solo las listas horizontales llevan la suya.
///
/// La barra se dibuja **encima** del borde de lo que se desplaza, así que
/// quien lo coloca deja [gutter] de relleno en ese lado para que no pise el
/// contenido.
abstract final class AppScrollbar {
  /// El grosor de reposo.
  static const double thickness = 6;

  /// El grosor con el ratón encima o al arrastrar.
  static const double hoverThickness = 9;

  /// El radio del pulgar.
  static const Radius radius = Radius.circular(4);

  /// El hueco entre el pulgar y el borde del visor.
  static const double margin = 2;

  /// Lo que hay que dejar de relleno en el lado de la barra para que el
  /// contenido no la pise: el grosor al máximo, su hueco y un respiro de 1.
  static const double gutter = 12;

  /// Los dispositivos con los que se arrastra una lista: los del sistema y el
  /// ratón. Solo para las listas horizontales sueltas (ver [MouseDragScroll]);
  /// donde hay tarjetas que se arrastran con el ratón, no se usa.
  static const Set<PointerDeviceKind> dragWithMouse = <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.mouse,
  };

  /// El tema de las barras para [t]: la tinta del texto, que cambia sola entre
  /// claro y oscuro.
  static ScrollbarThemeData theme(RegalosTokens t) {
    // En oscuro, el pulgar al 28 % sobre el fondo (#1C1C1C) y la columna
    // (#2B2B2B) daba 2,5:1 y 2,4:1: por debajo del 3:1 que pide WCAG 1.4.11
    // para un control. Al 40 % da 3,4:1 sobre la columna. En claro, tinta
    // sobre gris suave no llega al 3:1 sin volverse pesada (haría falta un
    // 48 %); se queda suave, al nivel del filete de control anterior.
    final rest = t.isDark ? 0.40 : 0.28;
    Color thumb(Set<WidgetState> states) {
      final double alpha;
      if (states.contains(WidgetState.dragged)) {
        alpha = rest + 0.34;
      } else if (states.contains(WidgetState.hovered)) {
        alpha = rest + 0.20;
      } else {
        alpha = rest;
      }
      return t.text.withValues(alpha: alpha);
    }

    return ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith<double>(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged)
            ? hoverThickness
            : thickness,
      ),
      radius: radius,
      thumbColor: WidgetStateProperty.resolveWith<Color>(thumb),
      interactive: true,
      crossAxisMargin: margin,
      mainAxisMargin: margin,
    );
  }
}

/// Deja arrastrar con el ratón la lista de dentro (por defecto solo se
/// arrastra con el dedo, el lápiz o el trackpad; con el ratón se usa la
/// rueda o la barra).
///
/// Para una tira de tarjetas o un carrusel de escritorio. No se pone sobre
/// listas con elementos que se arrastran con el ratón (los carriles): los dos
/// gestos competirían.
class MouseDragScroll extends StatelessWidget {
  /// Envuelve [child].
  const MouseDragScroll({super.key, required this.child});

  /// La lista o el carrusel.
  final Widget child;

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context)
        .copyWith(dragDevices: AppScrollbar.dragWithMouse),
    child: child,
  );
}
