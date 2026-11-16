import 'package:flutter/widgets.dart';

import '../theme/regalos_motion.dart';
import '../theme/regalos_tokens.dart';
import 'pane_scope.dart';
import 'window_class.dart';

/// Los paneles de una pestaña (la guía de diseño para tablet, §3.2, y
/// la guía de diseño de escritorio): la lista a la izquierda, el detalle
/// a la derecha y, en escritorio ancho, una tercera columna.
///
/// Con [panes] los tres van a la vez, cada uno en su [PaneScope], separados por
/// un filete de 1 px; la lista mide `RegalosLayout.listPaneWidth`, la columna
/// de [aside] `RegalosLayout.asideWidth` y el detalle se queda con el resto.
/// Sin [panes] (móvil, tablet en vertical, ventana estrecha) solo se ve el que
/// exista: quien la use pasa [list] o [detail], no los dos, y ese ocupa todo el
/// sitio con `PaneRole.single`, como si no hubiera paneles.
///
/// El árbol tiene siempre la misma forma (cinco huecos en una fila, los que no
/// se usan miden cero): cruzar el corte de 840 no desmonta el detalle, que
/// conserva su estado. Tampoco anima nada.
///
/// Con paneles, los `Hero` se apagan: la lista sigue a la vista y un avatar
/// que la abandona confunde (§4.1 del plan de tablet).
///
/// **Entrada escalonada** (plan de escritorio, §2.4, y
/// la guía de diseño de escritorio, §3.6): si [entrance] dice
/// que sí la primera vez que se monta con paneles, la lista entra primero, el
/// detalle 40 ms después y la tercera columna 40 ms más tarde (cada uno en
/// 240 ms con `easeOut`: opacidad y 8 px de abajo arriba). Con «Reducir
/// movimiento», un fundido de 150 ms para todos a la vez. Cambiar el tamaño de
/// la ventana no anima nada.
///
/// Cada panel va en su propio `RepaintBoundary`: pasar el ratón por una fila de
/// la lista no repinta el detalle ni la tercera columna.
///
/// **Bandas** (web de escritorio, `DesktopBands`): dentro de `WebDesktopFrame`
/// las medidas salen de [DesktopBands] (lista 320/340/380, tercera columna
/// 340/400) y cada panel pinta su banda de tono a toda altura: lista y tercera
/// columna en `t.surface`, detalle en `t.bg`. Si la pestaña no tiene tercera
/// columna ([aside] es `null`), no queda banda vacía: el detalle se queda ese
/// ancho (su contenido mantiene el suyo y el fondo llega al borde). Fuera de
/// la web nada de esto cambia.
class TwoPane extends StatefulWidget {
  /// Crea los paneles.
  const TwoPane({
    super.key,
    required this.panes,
    this.list,
    this.detail,
    this.aside,
    this.entrance,
  });

  /// Si hay varios paneles a la vez.
  final bool panes;

  /// El panel de lista.
  final Widget? list;

  /// El panel de detalle.
  final Widget? detail;

  /// La tercera columna; solo se ve con [panes].
  final Widget? aside;

  /// Si toca hacer la entrada escalonada. Se pregunta una vez, al montarse con
  /// [panes]; devolver `true` la gasta (`PaneSelection.takeEntrance`).
  final bool Function()? entrance;

  /// Lo que se retrasa cada panel respecto al anterior en la entrada.
  static const Duration entranceStep = Duration(milliseconds: 40);

  /// Lo que dura la entrada de cada panel.
  static const Duration entranceDuration = Duration(milliseconds: 240);

  /// El rectángulo (en coordenadas de la ventana) del panel de detalle del
  /// [TwoPane] que rodea a [context], o `null` si no hay dos paneles a la vez
  /// o el panel aún no está maquetado. Lo usa el vuelo de la cuenta atrás para
  /// terminar exactamente en el panel (T11).
  static Rect? detailRectOf(BuildContext context) {
    final probe = context.getInheritedWidgetOfExactType<_TwoPaneProbe>();
    if (probe == null || !probe.panes) {
      return null;
    }
    final box = probe.detailKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  State<TwoPane> createState() => _TwoPaneState();
}

/// Deja medir el panel de detalle desde cualquier panel ([TwoPane.detailRectOf]).
class _TwoPaneProbe extends InheritedWidget {
  const _TwoPaneProbe({
    required this.panes,
    required this.detailKey,
    required super.child,
  });

  final bool panes;
  final GlobalKey detailKey;

  @override
  bool updateShouldNotify(_TwoPaneProbe old) => old.panes != panes;
}

class _TwoPaneState extends State<TwoPane> with SingleTickerProviderStateMixin {
  // La entrada: 0 a 1 en el tiempo de tres paneles (2 retardos más 240 ms).
  AnimationController? _enter;
  bool _reduce = false;

  // Cada panel lleva una clave global: al cruzar el corte de dos paneles el
  // panel gana o pierde su `PaneScope`, y con la clave su estado (los filtros,
  // la posición) pasa de un sitio a otro del árbol en vez de perderse.
  final GlobalKey _listKey = GlobalKey(debugLabel: 'pane-list');
  final GlobalKey _detailKey = GlobalKey(debugLabel: 'pane-detail');
  final GlobalKey _asideKey = GlobalKey(debugLabel: 'pane-aside');

  @override
  void initState() {
    super.initState();
    if (widget.panes && (widget.entrance?.call() ?? false)) {
      // En el primer fotograma, para que se vea desde el principio.
      _enter = AnimationController(
        vsync: this,
        duration: TwoPane.entranceStep * 2 + TwoPane.entranceDuration,
        animationBehavior: AnimationBehavior.preserve,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _enter
            ?..duration = _reduce
                ? RegalosMotion.fade
                : TwoPane.entranceStep * 2 + TwoPane.entranceDuration
            ..forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _enter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _reduce = RegalosMotion.of(context).reduce;
    final t = RegalosTokens.of(context);
    final window = MediaQuery.sizeOf(context).width;
    final desktop = RegalosLayout.isDesktop(window);
    final bands = DesktopBands.maybeOf(context);
    final panes = widget.panes;
    return _TwoPaneProbe(
      panes: panes,
      detailKey: _detailKey,
      child: HeroMode(
        enabled: !panes,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final area = constraints.maxWidth;
            final showAside = panes && widget.aside != null;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Slot(
                  panes: panes,
                  role: PaneRole.list,
                  width: !panes
                      ? null
                      : bands?.listWidth ??
                            RegalosLayout.listPaneWidth(area, desktop: desktop),
                  color: panes && bands != null ? t.surface : null,
                  slotKey: _listKey,
                  entrance: _enter,
                  order: 0,
                  reduce: _reduce,
                  child: widget.list,
                ),
                _Rule(
                  visible:
                      panes && widget.list != null && widget.detail != null,
                  color: t.separator,
                ),
                _Slot(
                  panes: panes,
                  role: PaneRole.detail,
                  color: panes && bands != null ? t.bg : null,
                  slotKey: _detailKey,
                  entrance: _enter,
                  order: 1,
                  reduce: _reduce,
                  child: widget.detail,
                ),
                _Rule(visible: showAside, color: t.separator),
                _Slot(
                  panes: panes,
                  role: PaneRole.aside,
                  width: showAside
                      ? bands?.asideWidth ?? RegalosLayout.asideWidth(area)
                      : null,
                  color: bands != null && showAside ? t.surface : null,
                  fixed: true,
                  slotKey: _asideKey,
                  entrance: _enter,
                  order: 2,
                  reduce: _reduce,
                  child: showAside ? widget.aside : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Un hueco de la fila: sin hijo no mide nada; con [width] mide eso; sin él,
/// ocupa lo que quede. Con [panes] el hijo es un panel con su `PaneScope`;
/// sin ellos va tal cual, dentro del único `PaneScope` de la pestaña.
class _Slot extends StatelessWidget {
  const _Slot({
    required this.panes,
    required this.role,
    required this.slotKey,
    required this.entrance,
    required this.order,
    required this.reduce,
    this.width,
    this.color,
    this.fixed = false,
    this.child,
  });

  final bool panes;
  final PaneRole role;
  final GlobalKey slotKey;
  final double? width;

  /// La banda de tono del panel (solo en la web de escritorio).
  final Color? color;
  final bool fixed;
  final Widget? child;

  /// La entrada escalonada, si la hay, y el lugar de este panel en ella.
  final Animation<double>? entrance;
  final int order;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    if (child == null) {
      // Una banda vacía (tercera columna sin contenido en esta pestaña).
      if (color != null && width != null) {
        return Flexible(
          flex: 0,
          child: SizedBox(
            width: width,
            child: ColoredBox(color: color!),
          ),
        );
      }
      return const Flexible(flex: 0, child: SizedBox.shrink());
    }
    final sized = fixed || width != null;
    final keyed = KeyedSubtree(key: slotKey, child: child);
    final scoped = panes ? PaneScope(role: role, child: keyed) : keyed;
    // Cada panel pinta en su propia capa: el hover o un fundido en uno no
    // repinta a los otros.
    final pane = RepaintBoundary(child: scoped);
    final content = entrance == null
        ? pane
        : PaneEntranceScope(
            animation: entrance!,
            child: PaneEntrance(
              animation: entrance!,
              order: order,
              reduce: reduce,
              child: pane,
            ),
          );
    return Flexible(
      flex: sized ? 0 : 1,
      fit: sized ? FlexFit.loose : FlexFit.tight,
      // La banda de tono queda fuera de la entrada: lo que se funde es el
      // contenido, no el fondo.
      child: SizedBox(
        width: width,
        child: color == null
            ? content
            : ColoredBox(color: color!, child: content),
      ),
    );
  }
}

/// Avisa a lo que hay dentro de un panel de que se está montando con la
/// entrada escalonada de los paneles (la primera vez que se ve la pestaña con
/// dos paneles): [animation] es la entrada, y si ya acabó (el panel aparece
/// más tarde, al ensanchar la ventana) no hay nada que animar.
class PaneEntranceScope extends InheritedWidget {
  /// Crea el aviso.
  const PaneEntranceScope({
    super.key,
    required this.animation,
    required super.child,
  });

  /// La entrada de los paneles.
  final Animation<double> animation;

  /// La entrada en curso del panel donde está [context], si la hay.
  static Animation<double>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PaneEntranceScope>()?.animation;

  @override
  bool updateShouldNotify(PaneEntranceScope old) => animation != old.animation;
}

/// La entrada de un panel: opacidad de 0 a 1 y 8 px de abajo arriba, con
/// `easeOut`, en [TwoPane.entranceDuration] y [order] por 40 ms después del
/// comienzo. Con [reduce], un fundido de 150 ms sin retardo ni
/// desplazamiento.
///
/// La opacidad va con `FadeTransition` (no reconstruye el panel); solo la
/// traslación, que no crea capas, se recalcula en cada fotograma.
@visibleForTesting
class PaneEntrance extends StatelessWidget {
  /// Crea la entrada de un panel.
  const PaneEntrance({
    required this.animation,
    required this.order,
    required this.reduce,
    required this.child,
  });

  final Animation<double> animation;
  final int order;
  final bool reduce;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final total = (animation as AnimationController).duration!;
    // La parte de la entrada total que le toca a este panel.
    final Interval span;
    if (reduce) {
      span = const Interval(0, 1, curve: Curves.linear);
    } else {
      final start = (TwoPane.entranceStep * order).inMicroseconds;
      final end = start + TwoPane.entranceDuration.inMicroseconds;
      span = Interval(
        (start / total.inMicroseconds).clamp(0.0, 1.0),
        (end / total.inMicroseconds).clamp(0.0, 1.0),
        curve: Curves.easeOut,
      );
    }
    final progress = animation.drive(CurveTween(curve: span));
    return FadeTransition(
      opacity: progress,
      child: reduce
          ? child
          : AnimatedBuilder(
              animation: progress,
              child: child,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, 8 * (1 - progress.value)),
                child: child,
              ),
            ),
    );
  }
}

/// El filete de 1 px entre dos paneles.
class _Rule extends StatelessWidget {
  const _Rule({required this.visible, required this.color});

  final bool visible;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: visible ? 1 : 0,
    child: visible ? ColoredBox(color: color) : null,
  );
}

/// El ancho que puede ocupar el contenido de un panel de detalle (la lista de
/// una persona, una ocasión…): 720 por debajo de 1280 de ventana y 880 desde
/// ahí (`RegalosLayout.detailMaxWidthFor`); en la web de escritorio, el de
/// [DesktopBands.contentWidth] (880, 960 o 1040).
///
/// En un panel de detalle ([PaneRole.detail]) es esa medida; en cualquier otro
/// sitio, [single], la columna de las pantallas a un panel (640, la de
/// siempre).
double detailColumnWidth(
  BuildContext context, {
  double single = RegalosLayout.listColumn,
}) => PaneScope.roleOf(context) == PaneRole.detail
    ? DesktopBands.maybeOf(context)?.contentWidth ??
          RegalosLayout.detailMaxWidthFor(MediaQuery.sizeOf(context).width)
    : single;
