import 'package:flutter/widgets.dart';

/// Los puntos de corte de la ventana (la guía de diseño para tablet, §2.1).
abstract final class RegalosBreakpoints {
  /// Desde este ancho la ventana es «medio»: raíl y ancho máximo.
  static const double medium = 600;

  /// Desde este ancho la ventana es «expandido»: dos paneles.
  static const double expanded = 840;

  /// Desde este ancho es un escritorio (la guía de diseño de escritorio,
  /// §2.1): la app ocupa toda la ventana, el panel de lista mide al menos 360
  /// y el contenido del detalle llega a 880.
  static const double desktop = 1280;

  /// Desde este ancho es un escritorio ancho: Personas suma una tercera
  /// columna, «Resumen» (la guía de diseño de escritorio, §2).
  static const double desktopWide = 1600;

  /// Por debajo de este alto la ventana es compacta tenga el ancho que tenga
  /// (el móvil en horizontal).
  static const double minHeight = 480;
}

/// La clase de la ventana de la app. Sale del tamaño de la ventana, nunca del
/// aparato ni de la orientación: así vale igual para la tablet girada, la
/// pantalla partida de Android y Split View.
///
/// | Clase        | Regla                      | Navegación     | Paneles |
/// |--------------|----------------------------|----------------|---------|
/// | [compact]    | ancho < 600 o alto < 480   | barra inferior | uno     |
/// | [medium]     | 600 ≤ ancho < 840          | raíl           | uno     |
/// | [expanded]   | ancho ≥ 840                | raíl           | dos     |
///
/// Los dos paneles valen en cualquier plataforma (la tablet girada y el
/// navegador de escritorio). Dentro de [expanded] hay dos cortes más que no
/// son clases aparte: [RegalosLayout.isDesktop] (1280) y
/// [RegalosLayout.isDesktopWide] (1600).
enum WindowClass {
  /// El móvil de hoy. Nada cambia.
  compact,

  /// Tablet en vertical: raíl y un panel con ancho máximo.
  medium,

  /// Tablet en horizontal: raíl y dos paneles en Personas, Ocasiones y
  /// Ajustes.
  expanded;

  /// La clase de una ventana de [size] puntos lógicos.
  static WindowClass fromSize(Size size) {
    if (size.width < RegalosBreakpoints.medium ||
        size.height < RegalosBreakpoints.minHeight) {
      return compact;
    }
    if (size.width < RegalosBreakpoints.expanded) {
      return medium;
    }
    return expanded;
  }

  /// La clase de la ventana de la app. Mira siempre la ventana entera
  /// (`MediaQuery.sizeOf`), no el panel: para medirse dentro de un panel está
  /// `PaneScope.widthOf`.
  static WindowClass of(BuildContext context) =>
      fromSize(MediaQuery.sizeOf(context));

  /// Si la navegación va en el raíl lateral en vez de en la barra inferior.
  bool get usesRail => this != compact;

  /// Si Personas, Ocasiones y Ajustes enseñan lista y detalle a la vez.
  bool get usesTwoPanes => this == expanded;
}

/// Las medidas de la versión tablet (la guía de diseño para tablet, §2.2).
///
/// Son anchos máximos: por debajo de ellos nada cambia (norma 1, «compacto no
/// cambia»). «Área de contenido» es la ventana menos el raíl.
abstract final class RegalosLayout {
  /// Ancho del raíl lateral.
  static const double railWidth = 80;

  /// El panel de lista ocupa esta parte del área de contenido…
  static const double listPaneFraction = 0.34;

  /// …sin bajar de aquí…
  static const double listPaneMinWidth = 340;

  /// …ni pasar de aquí.
  static const double listPaneMaxWidth = 420;

  /// Ancho máximo del contenido del panel de detalle.
  static const double detailMaxWidth = 720;

  /// Lo mismo, desde [RegalosBreakpoints.desktop] de ventana.
  static const double desktopDetailMaxWidth = 880;

  /// En escritorio el panel de lista no baja de aquí…
  static const double desktopListPaneMinWidth = 360;

  /// La tercera columna del escritorio ancho (Personas) ocupa esta parte del
  /// área de contenido…
  static const double asideFraction = 0.2;

  /// …sin bajar de aquí…
  static const double asideMinWidth = 320;

  /// …ni pasar de aquí.
  static const double asideMaxWidth = 360;

  /// Columna de las listas a un panel (Personas, Ocasiones, lista de una
  /// persona, detalle de ocasión, Presupuesto).
  static const double listColumn = 640;

  /// Columna de Ajustes y de los formularios.
  static const double formColumn = 560;

  /// Ancho de las hojas.
  static const double sheetWidth = 560;

  /// Ancho de la tarjeta del editor de regalo.
  static const double editorWidth = 640;

  /// Ancho de la tarjeta del editor de regalo en una ventana de escritorio
  /// (desde 1280), con el formulario en dos columnas.
  static const double desktopEditorWidth = 880;

  /// Ancho de la hoja desde el que el editor pone el formulario en dos
  /// columnas.
  static const double editorTwoColumnsMinWidth = 720;

  /// Ancho de los diálogos de confirmación (el de hoy).
  static const double dialogWidth = 340;

  /// Ancho de los avisos (`SnackBar`).
  static const double snackBarWidth = 480;

  /// Columna del primer uso y de «Unirse con invitación».
  static const double onboardingColumn = 520;

  /// Lado del QR de emparejar en compacto (el de hoy).
  static const double pairingQrCompact = 260;

  /// Lado del QR de emparejar desde 600 dp.
  static const double pairingQr = 320;

  /// Si una ventana de [windowWidth] es de escritorio (desde 1280).
  static bool isDesktop(double windowWidth) =>
      windowWidth >= RegalosBreakpoints.desktop;

  /// Si una ventana de [windowWidth] es de escritorio ancho (desde 1600).
  static bool isDesktopWide(double windowWidth) =>
      windowWidth >= RegalosBreakpoints.desktopWide;

  /// Ancho del panel de lista para un área de contenido de
  /// [contentAreaWidth]: el 34 %, entre 340 y 420 (entre 360 y 420 en
  /// [desktop]).
  static double listPaneWidth(
    double contentAreaWidth, {
    bool desktop = false,
  }) => (contentAreaWidth * listPaneFraction)
      .clamp(
        desktop ? desktopListPaneMinWidth : listPaneMinWidth,
        listPaneMaxWidth,
      )
      .toDouble();

  /// Ancho de la tercera columna para un área de contenido de
  /// [contentAreaWidth]: el 20 %, entre 320 y 360.
  static double asideWidth(double contentAreaWidth) =>
      (contentAreaWidth * asideFraction)
          .clamp(asideMinWidth, asideMaxWidth)
          .toDouble();

  /// Ancho máximo del contenido del panel de detalle en una ventana de
  /// [windowWidth]: 880 en escritorio y 720 por debajo. En la web, dentro de
  /// [DesktopBandsScope], manda [DesktopBands.contentWidth].
  static double detailMaxWidthFor(double windowWidth) =>
      isDesktop(windowWidth) ? desktopDetailMaxWidth : detailMaxWidth;

  /// Ancho máximo de la tarjeta del editor de regalo en una ventana de
  /// [windowWidth]: 880 en escritorio y 640 por debajo.
  static double editorWidthFor(double windowWidth) =>
      isDesktop(windowWidth) ? desktopEditorWidth : editorWidth;

  /// Lado del QR de emparejar según la clase de la ventana.
  static double pairingQrSize(WindowClass window) =>
      window == WindowClass.compact ? pairingQrCompact : pairingQr;
}

/// Las medidas de la web de escritorio por bandas
/// (la guía de diseño de escritorio, §2), sobre el ancho
/// **lógico** de la ventana, es decir, ya dividido por la escala de interfaz.
///
/// Son tres bandas de tono a toda altura: raíl y lista en `t.surface`, detalle
/// en `t.bg` y «Resumen» (la tercera columna) en `t.surface`. La composición
/// ([maxWidth]) no pasa de 2060: lo que sobra queda fuera, a los lados, como
/// prolongación de las bandas laterales.
///
/// | Ancho lógico | Lista | Detalle (contenido) | Derecha |
/// |--------------|-------|---------------------|---------|
/// | 1280 a 1599  | 320   | el resto (880)      | nada    |
/// | 1600 a 2199  | 340   | hasta 1120 (960)    | 340     |
/// | desde 2200   | 380   | hasta 1200 (1040)   | 400     |
///
/// Por debajo de 1280 no hay bandas ([forWindow] devuelve `null`).
@immutable
class DesktopBands {
  const DesktopBands._({
    required this.listWidth,
    required this.contentWidth,
    required this.asideWidth,
    this.detailMaxWidth,
  });

  /// Ancho de la lista.
  final double listWidth;

  /// Ancho máximo del contenido del detalle.
  final double contentWidth;

  /// Ancho de la tercera columna; 0 si no la hay.
  final double asideWidth;

  /// Ancho máximo de la banda del detalle; `null` si ocupa lo que quede.
  final double? detailMaxWidth;

  /// Si hay tercera columna.
  bool get hasAside => asideWidth > 0;

  /// El ancho máximo de la composición entera (raíl incluido), o `null` si no
  /// tiene tope.
  double? get maxWidth => detailMaxWidth == null
      ? null
      : RegalosLayout.railWidth + listWidth + detailMaxWidth! + asideWidth;

  static const DesktopBands _small = DesktopBands._(
    listWidth: 320,
    contentWidth: 880,
    asideWidth: 0,
  );
  static const DesktopBands _wide = DesktopBands._(
    listWidth: 340,
    contentWidth: 960,
    asideWidth: 340,
    detailMaxWidth: 1120,
  );
  static const DesktopBands _ultra = DesktopBands._(
    listWidth: 380,
    contentWidth: 1040,
    asideWidth: 400,
    detailMaxWidth: 1200,
  );

  /// Las medidas de una ventana de [logicalWidth], o `null` por debajo de 1280.
  static DesktopBands? forWindow(double logicalWidth) {
    if (logicalWidth < RegalosBreakpoints.desktop) return null;
    if (logicalWidth < RegalosBreakpoints.desktopWide) return _small;
    if (logicalWidth < 2200) return _wide;
    return _ultra;
  }

  /// Las del árbol donde está [context], o `null` fuera de la web de
  /// escritorio por bandas (móvil, tablet, ventana estrecha).
  static DesktopBands? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopBandsScope>()?.bands;
}

/// Reparte las medidas de [DesktopBands] por el árbol. Lo pone
/// `WebDesktopFrame`.
class DesktopBandsScope extends InheritedWidget {
  /// Crea el ámbito; [bands] es `null` por debajo de 1280.
  const DesktopBandsScope({
    super.key,
    required this.bands,
    required super.child,
  });

  /// Las medidas, si hay bandas.
  final DesktopBands? bands;

  @override
  bool updateShouldNotify(DesktopBandsScope old) => old.bands != bands;
}
