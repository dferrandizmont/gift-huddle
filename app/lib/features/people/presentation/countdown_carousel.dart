import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/dates.dart';
import '../../../core/format/money.dart';
import '../../../core/layout/pane_scope.dart';
import '../../../core/layout/two_pane.dart' show PaneEntranceScope;
import '../../../core/layout/window_class.dart';
import '../../../core/motion/page_physics.dart';
import '../../../core/motion/unlock_cascade.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/app_scrollbar.dart';
import '../../../core/theme/occasion_theme.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/budget_meter.dart';
import '../../../core/widgets/occasion_countdown_card.dart';
import '../../../core/widgets/occasion_icons.dart';
import '../../../core/widgets/pointer_surface.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/spring_pulse.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/gift_logic.dart';
import '../../family/domain/next_occasion.dart';
import '../../family/presentation/family_texts.dart';
import '../../occasions/presentation/occasion_detail_screen.dart';
import '../../occasions/presentation/occasion_expand_route.dart';
import '../../occasions/presentation/occasion_garland.dart';
import '../../settings/application/appearance_provider.dart';

/// La cuenta atrás de Personas: una tarjeta por ocasión próxima, de la más
/// cercana a la más lejana.
///
/// Con una sola ocasión es una tarjeta sin más. Con varias es un carrusel
/// que se desliza en horizontal (el vertical es de la lista), con la
/// siguiente tarjeta asomando por el borde y unos indicadores de página
/// debajo. Tocar una tarjeta abre su ocasión.
///
/// En la columna de tablet (desde [twoUpWidth] de ancho) enseña dos tarjetas
/// a la vez, de 300 cada una, y se desliza de una en una; ya no asoma ninguna
/// y los indicadores marcan las dos que se ven. Con una sola ocasión, la
/// tarjeta mide lo mismo y queda al principio.
class CountdownCarousel extends ConsumerStatefulWidget {
  const CountdownCarousel({super.key, required this.items, required this.now});

  final List<NextOccasion> items;
  final DateTime now;

  /// Desde este ancho del carrusel caben dos tarjetas a la vez: la columna de
  /// las listas en tablet (la guía de diseño para tablet, §3).
  static const double twoUpWidth = RegalosLayout.listColumn;

  /// Hueco entre las dos tarjetas: con él miden 300 justos en la columna.
  static const double twoUpGap = 8;

  /// Cuántas tarjetas se ven a la vez en un carrusel de [width].
  static int perViewFor(double width) => width >= twoUpWidth ? 2 : 1;

  /// El ancho de cada tarjeta de un carrusel de [width] con varias ocasiones.
  ///
  /// Con una a la vista, el visor empieza a 11 del borde y cada página deja 5
  /// por cada lado: la tarjeta arranca a 16, entre tarjetas hay 10 y la
  /// siguiente asoma por el borde. Con dos, las dos caben enteras entre los
  /// márgenes de 16.
  static double cardWidthFor(double width) => perViewFor(width) == 1
      ? (width - _inset(RegalosSizes.carouselGap)) *
                RegalosSizes.carouselViewportFraction -
            RegalosSizes.carouselGap
      : (width - 2 * _inset(twoUpGap)) / 2 - twoUpGap;

  /// Lo que se mete el visor para que la primera tarjeta arranque a 16.
  static double _inset(double gap) => RegalosSizes.carouselEdge - gap / 2;

  @override
  ConsumerState<CountdownCarousel> createState() => _CountdownCarouselState();
}

class _CountdownCarouselState extends ConsumerState<CountdownCarousel> {
  // El controlador del carrusel, para las tarjetas que caben a la vez: con
  // una, la siguiente asoma un poco por el borde derecho.
  PageController? _controller;
  int _perView = 1;

  // La primera tarjeta a la vista.
  int _page = 0;

  // Al soltar sobre una tarjeta, su número rueda desde el de la anterior: un
  // contador por tarjeta y el número del que viene.
  final Map<int, int> _arrivals = <int, int>{};
  final Map<int, int> _arrivedFrom = <int, int>{};
  final Map<int, GlobalKey<SpringPulseState>> _pulses =
      <int, GlobalKey<SpringPulseState>>{};
  Timer? _pulseTimer;

  // Las claves con las que el vuelo hasta el detalle mide la tarjeta y su
  // número.
  final Map<int, GlobalKey> _cardKeys = <int, GlobalKey>{};
  final Map<int, GlobalKey> _numberKeys = <int, GlobalKey>{};

  // Tras desbloquear la app, la cuenta atrás rueda desde vacío a los 200 ms.
  bool _cascade = false;

  @override
  void initState() {
    super.initState();
    UnlockCascade.epoch.addListener(_onUnlockCascade);
    // «Hoy»: el dibujo hace un rebote al verse por primera vez.
    if (widget.items.isNotEmpty && widget.items.first.days == 0) {
      _pulseSoon(0);
    }
  }

  @override
  void dispose() {
    UnlockCascade.epoch.removeListener(_onUnlockCascade);
    _pulseTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// El controlador para [perView] tarjetas a la vista. Cruzar el corte (girar
  /// la tablet, partir la pantalla) cambia la fracción del visor: se estrena
  /// controlador en la misma tarjeta y el viejo se suelta al acabar el
  /// fotograma, cuando ya nadie lo escucha.
  PageController _controllerFor(int perView) {
    final current = _controller;
    if (current != null && perView == _perView) {
      return current;
    }
    if (current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    _perView = perView;
    // `keepPage` apagado: la lista de Personas guarda su posición en el
    // `PageStorage`, y el carrusel, que va dentro, escribiría en el mismo
    // sitio.
    return _controller = PageController(
      keepPage: false,
      initialPage: _page,
      viewportFraction: perView == 1
          ? RegalosSizes.carouselViewportFraction
          : 1 / perView,
    );
  }

  /// Cuánto le falta a la tarjeta [i] para estar entre las que se ven: 0 si
  /// está a la vista, positivo si ha salido por el principio y negativo si
  /// aún no ha entrado por el final. Con una tarjeta a la vista es la
  /// distancia a la página.
  double _outside(int i) {
    final page = _pageValue;
    if (page > i) {
      return page - i;
    }
    final last = page + _perView - 1;
    return i > last ? last - i : 0;
  }

  /// El desbloqueo en cascada (§1+.4): si esta pantalla se ve, las cifras
  /// ruedan otra vez desde vacío a los 200 ms.
  void _onUnlockCascade() {
    if (!mounted ||
        RegalosMotion.of(context).reduce ||
        !TickerMode.getValuesNotifier(context).value.enabled) {
      return;
    }
    setState(() {
      _cascade = true;
      for (var i = 0; i < widget.items.length; i++) {
        _arrivals[i] = (_arrivals[i] ?? 0) + 1;
        _arrivedFrom.remove(i);
      }
    });
  }

  GlobalKey _cardKey(int i) => _cardKeys.putIfAbsent(i, GlobalKey.new);
  GlobalKey _numberKey(int i) => _numberKeys.putIfAbsent(i, GlobalKey.new);

  /// El retardo con el que ruedan las cifras de la tarjeta [i].
  Duration _rollDelay(int i) =>
      _cascade ? UnlockCascade.countdownDelay : Duration(milliseconds: 60 * i);

  /// El número de página, también mientras se arrastra (entre dos tarjetas).
  ///
  /// Durante el fotograma en que el visor se monta en otro sitio (al cruzar
  /// el corte de los dos paneles, cuando cambia lo que lo envuelve) el
  /// controlador tiene dos visores un instante: entonces vale la última
  /// página conocida.
  double get _pageValue {
    final controller = _controller;
    if (controller == null || controller.positions.length != 1) {
      return _page.toDouble();
    }
    final position = controller.position;
    return position.haveDimensions
        ? (controller.page ?? _page.toDouble())
        : _page.toDouble();
  }

  /// El rebote del dibujo de «hoy», a los 120 ms de llegar.
  void _pulseSoon(int index) {
    _pulseTimer?.cancel();
    _pulseTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) {
        _pulses[index]?.currentState?.play(from: 0.92);
      }
    });
  }

  void _arrive(int index) {
    final items = widget.items;
    // La tarjeta que llega es la que entra por el lado hacia el que se
    // avanza, y su número rueda desde el de la que estaba en ese borde. Con
    // una tarjeta a la vista son la página nueva y la anterior.
    final edge = index >= _page ? _perView - 1 : 0;
    final arrived = index + edge;
    final from = _page + edge;
    setState(() {
      _cascade = false;
      _page = index;
      if (arrived < items.length) {
        _arrivals[arrived] = (_arrivals[arrived] ?? 0) + 1;
        if (from < items.length) {
          _arrivedFrom[arrived] = items[from].days;
        }
      }
    });
    if (arrived < items.length && items[arrived].days == 0) {
      _pulseSoon(arrived);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final full = ref.watch(familyFullViewProvider).recipientsById;
    final gifts = ref.watch(familyViewProvider).gifts;
    final wishes = ref.watch(freeWishCountsProvider);
    // Todas las tarjetas miden lo mismo: lo de la que más ocupa.
    double heightFor(double width) =>
        _cardsHeight(context, l10n, items, full, gifts, wishes, width);

    if (items.length == 1) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // De lado a lado en el móvil; en la columna de tablet, del ancho de
          // una de las dos del carrusel y al principio.
          const edge = RegalosSizes.carouselEdge;
          final width = CountdownCarousel.perViewFor(constraints.maxWidth) == 1
              ? constraints.maxWidth - 2 * edge
              : CountdownCarousel.cardWidthFor(constraints.maxWidth);
          return Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              edge,
              4,
              constraints.maxWidth - edge - width,
              8,
            ),
            child: _OccasionCard(
              next: items.first,
              height: heightFor(width),
              rollFromEmpty: true,
              rollDelay: _cascade
                  ? UnlockCascade.countdownDelay
                  : Duration.zero,
              rollCue: _arrivals[0],
              pulseKey: _pulses.putIfAbsent(0, GlobalKey.new),
              cardKey: _cardKey(0),
              numberKey: _numberKey(0),
            ),
          );
        },
      );
    }
    final reduce = RegalosMotion.of(context).reduce;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Con una tarjeta a la vista, el visor empieza a 11 del borde y cada
        // página deja 5 por cada lado: la tarjeta arranca a 16 en todas las
        // páginas, entre tarjetas hay 10 y la siguiente asoma por el borde
        // derecho. Con dos (la columna de tablet), el visor se mete lo mismo
        // por los dos lados y cada página es media: caben las dos enteras.
        final perView = CountdownCarousel.perViewFor(constraints.maxWidth);
        final wide = perView > 1;
        final gap = wide
            ? CountdownCarousel.twoUpGap
            : RegalosSizes.carouselGap;
        final inset = RegalosSizes.carouselEdge - gap / 2;
        final cardWidth = CountdownCarousel.cardWidthFor(constraints.maxWidth);
        final height = heightFor(cardWidth);
        final controller = _controllerFor(perView);
        // Las posiciones del carrusel: con dos a la vista hay una menos que
        // tarjetas, y con solo dos ocasiones no hay nada que deslizar.
        final stops = math.max(1, items.length - perView + 1);
        final current = math.min(_page, stops - 1);
        final lastShown = math.min(current + perView, items.length);
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 0),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.only(left: inset, right: wide ? inset : 0),
                child: _EdgeFade(
                  // En el panel de lista de escritorio el visor acaba en el
                  // filete: la tarjeta que asoma se funde hacia el fondo en
                  // vez de quedar cortada.
                  enabled: !wide && PaneScope.roleOf(context) == PaneRole.list,
                  // Con el ratón, el carrusel también se arrastra.
                  child: MouseDragScroll(
                    child: SizedBox(
                      height: height,
                      child: PageView.builder(
                        // Otro controlador, otro carrusel: no se le cambia la
                        // fracción del visor a uno en marcha.
                        key: ValueKey<int>(perView),
                        controller: controller,
                        padEnds: false,
                        // Con una tarjeta a la vista hay una página vacía de más:
                        // sin ella la última no llegaría al margen izquierdo (el
                        // visor se acaba antes) y se quedaría pegada a la derecha.
                        physics: wide
                            ? RegalosPagePhysics(reduce: reduce)
                            : LeftAlignedPagePhysics(
                                reduce: reduce,
                                count: items.length,
                                viewportFraction:
                                    RegalosSizes.carouselViewportFraction,
                              ),
                        itemCount: wide ? items.length : items.length + 1,
                        onPageChanged: _arrive,
                        itemBuilder: (context, i) {
                          if (i >= items.length) {
                            return const ExcludeSemantics(child: SizedBox());
                          }
                          final card = _OccasionCard(
                            next: items[i],
                            height: height,
                            // La primera vista: ruedan desde vacío, con 60 ms
                            // entre tarjetas.
                            rollFromEmpty: i < perView + 1,
                            rollDelay: _rollDelay(i),
                            rollCue: _arrivals[i],
                            rollFrom: _arrivedFrom[i],
                            pulseKey: _pulses.putIfAbsent(i, GlobalKey.new),
                            cardKey: _cardKey(i),
                            numberKey: _numberKey(i),
                            parallax: reduce
                                ? null
                                // El dibujo se retrasa mientras la tarjeta entra
                                // o sale; a la vista está en su sitio.
                                : (icon) => AnimatedBuilder(
                                    animation: controller,
                                    child: icon,
                                    builder: (context, child) =>
                                        Transform.translate(
                                          offset: Offset(24 * _outside(i), 0),
                                          child: child,
                                        ),
                                  ),
                          );
                          return Padding(
                            padding: EdgeInsets.symmetric(horizontal: gap / 2),
                            // Las que no están a la vista se ven un poco más
                            // pequeñas y tenues; sigue al dedo, no es un muelle.
                            child: reduce
                                ? card
                                : AnimatedBuilder(
                                    animation: controller,
                                    child: card,
                                    builder: (context, child) {
                                      final d = _outside(i)
                                          .abs()
                                          .clamp(0.0, 1.0);
                                      return Opacity(
                                        opacity: 1 - 0.35 * d,
                                        child: Transform.scale(
                                          scale: 1 - 0.05 * d,
                                          child: child,
                                        ),
                                      );
                                    },
                                  ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (stops > 1) ...[
                const SizedBox(height: 12),
                Semantics(
                  container: true,
                  label: wide
                      ? l10n.peopleCarouselRange(
                          current + 1,
                          lastShown,
                          items.length,
                        )
                      : l10n.peopleCarouselPage(current + 1, items.length),
                  excludeSemantics: true,
                  child: _PageDots(
                    count: items.length,
                    first: current,
                    shown: perView,
                    // Los puntos siguen al dedo: el valor de la página, no la
                    // página a la que se llegó.
                    page: controller,
                    pageValue: () => _pageValue,
                  ),
                ),
                const SizedBox(height: 4),
              ] else
                // Las dos caben enteras: sin indicadores, como con una sola.
                const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// Las alturas ya medidas de las tarjetas, por ancho, textos y tamaño de
/// letra: medir el texto de todas las tarjetas en cada reconstrucción (un clic
/// en la lista de personas basta) era lo más caro de la columna de ocasiones
/// (la guía de diseño de escritorio, §4.6). Se vacía al pasar
/// de [_heightCacheLimit] medidas, que es mucho más que las ocasiones de una
/// familia.
final Map<String, double> _heightCache = <String, double>{};

/// Cuántas medidas guarda [_heightCache] antes de vaciarse.
const int _heightCacheLimit = 128;

/// Lo que mide cada tarjeta de [items] a [width] de ancho: lo de la que más
/// ocupa, para que todas midan lo mismo.
double _cardsHeight(
  BuildContext context,
  AppLocalizations l10n,
  List<NextOccasion> items,
  Map<String, Recipient> people,
  List<Gift> gifts,
  FreeWishCounts wishes,
  double width,
) {
  final scale = MediaQuery.textScalerOf(context).scale(14);
  var height = 0.0;
  for (final next in items) {
    final texts = _CardTexts(l10n, next, people, gifts, wishes);
    final key =
        '$width|$scale|${next.days}|${texts.title}|${texts.date}|${texts.meta}';
    var measured = _heightCache[key];
    if (measured == null) {
      if (_heightCache.length >= _heightCacheLimit) {
        _heightCache.clear();
      }
      measured = _heightCache[key] = OccasionCountdownCard.heightFor(
        context,
        width: width,
        days: next.days,
        title: texts.title,
        date: texts.date,
        meta: texts.meta,
      );
    }
    height = math.max(height, measured);
  }
  return height;
}

/// «Resumen», la columna derecha de Personas en escritorio ancho: la próxima
/// ocasión como tarjeta (cifra de 44, 112 de alto), las demás en filas de 56 y,
/// abajo, el presupuesto de la casa. Tocar una abre su ocasión.
///
/// La tarjeta y las filas miden siempre lo mismo: al reconstruirla no hay que
/// medir ningún texto.
class SummaryColumn extends ConsumerStatefulWidget {
  const SummaryColumn({super.key, required this.items});

  final List<NextOccasion> items;

  @override
  ConsumerState<SummaryColumn> createState() => _SummaryColumnState();
}

class _SummaryColumnState extends ConsumerState<SummaryColumn> {
  // Si la columna entra con la entrada de los paneles (la primera vez que se
  // ve): solo rueda la cifra de la próxima ocasión; nada más se escalona.
  // Aparecer al ensanchar la ventana no anima nada.
  bool _decided = false;
  bool _roll = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) {
      return;
    }
    _decided = true;
    final entrance = PaneEntranceScope.maybeOf(context);
    _roll =
        entrance != null &&
        !entrance.isCompleted &&
        !RegalosMotion.of(context).reduce;
  }

  // Las claves con las que el vuelo hasta el detalle mide la tarjeta.
  final GlobalKey _cardKey = GlobalKey();
  final GlobalKey _numberKey = GlobalKey();
  final GlobalKey<SpringPulseState> _pulse = GlobalKey<SpringPulseState>();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final items = widget.items;
    final budget = ref.watch(budgetProvider).total;
    String money(int cents) => formatCents(cents, l10n.localeName);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          ScreenHeader(title: l10n.peopleSummaryTitle),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: _OccasionCard(
                      next: items.first,
                      height: OccasionCountdownCard.compactHeight,
                      compact: true,
                      // Solo la próxima ocasión rueda su cifra al entrar.
                      rollFromEmpty: _roll,
                      pulseKey: _pulse,
                      cardKey: _cardKey,
                      numberKey: _numberKey,
                    ),
                  ),
                for (final next in items.skip(1))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: UpcomingOccasionRow(
                      key: ValueKey<String>('summary-${next.occasion.id}'),
                      next: next,
                    ),
                  ),
              ],
            ),
          ),
          // El filete y el bloque, del mismo ancho que lo de arriba (16 de
          // cada borde de la columna).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.separator)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 14, 0, 16),
                child: BudgetMeter(
                  label: l10n.budgetHouseTotal,
                  valueText: (
                    spent: money(budget.spentCents),
                    planned: money(budget.plannedCents),
                    ofWord: l10n.budgetOf,
                  ),
                  spentOnlyLabel: budget.plannedCents > 0
                      ? null
                      : l10n.budgetSpent,
                  fraction: budget.plannedCents > 0
                      ? budget.spentCents / budget.plannedCents
                      : 0,
                  semanticLabel: l10n.budgetBarLabel(
                    money(budget.spentCents),
                    money(budget.plannedCents),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una ocasión próxima en una fila de 56 (la columna «Resumen» y, sin
/// columna, la fila de encima de la lista de Personas): tocarla abre la
/// ocasión.
class UpcomingOccasionRow extends ConsumerWidget {
  const UpcomingOccasionRow({super.key, required this.next});

  final NextOccasion next;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final themed = ref.watch(
      appearanceProvider.select((a) => a.occasionThemes),
    );
    final texts = _CardTexts(
      l10n,
      next,
      ref.watch(familyFullViewProvider).recipientsById,
      ref.watch(familyViewProvider).gifts,
      ref.watch(freeWishCountsProvider),
    );
    return PointerSurface(
      child: OccasionSummaryRow(
        days: next.days,
        unit: texts.unit,
        title: texts.title,
        date: texts.shortDate,
        meta: texts.shortMeta,
        occasion: themed ? OccasionTheme.forOccasion(next.occasion) : null,
        onTap: () => context.push('/occasions/${next.occasion.id}?from=people'),
      ),
    );
  }
}

/// Funde hacia el fondo los últimos píxeles de la derecha de [child] (la
/// tarjeta que asoma por el borde del visor). Sin [enabled] no hace nada.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  /// Lo que dura el fundido, desde el borde.
  static const double width = 28;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }
    final bg = RegalosTokens.of(context).bg;
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: width,
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey<String>('carousel-edge-fade'),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [bg.withValues(alpha: 0), bg]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cuánto del punto [i] cubre la ventana de [shown] tarjetas que empieza en
/// [from] (la página, también entre dos): de 0 a 1.
@visibleForTesting
double carouselDotCoverage(int i, double from, int shown) {
  final lo = math.max(from, i.toDouble());
  final hi = math.min(from + shown, i + 1.0);
  return (hi - lo).clamp(0.0, 1.0);
}

/// Los indicadores de página (§1.7 y momento H): siguen al dedo, no saltan.
///
/// Cada punto se enciende según cuánto de él cubre la ventana de tarjetas a la
/// vista, que sale del valor continuo de la página ([pageValue]): al arrastrar,
/// el punto que se va se apaga a la vez que el que llega se enciende, y al
/// soltar los lleva el muelle del propio carrusel. Siguen siendo círculos (el
/// encendido crece de escala 1 a 1,3); nunca se ensanchan a píldora. Con
/// «Reducir movimiento» solo cambia el color, en 150 ms, al llegar a la página.
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.first,
    this.shown = 1,
    this.page,
    this.pageValue,
  });

  final int count;

  /// La primera tarjeta a la vista y cuántas se ven: esas son las activas.
  final int first;
  final int shown;

  /// Lo que avisa de que la página cambia (el controlador del carrusel).
  final Listenable? page;

  /// La página ahora mismo, también entre dos tarjetas.
  final double Function()? pageValue;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    if (motion.reduce || page == null || pageValue == null) {
      bool active(int i) => i >= first && i < first + shown;
      return _row(
        t,
        (i) => AnimatedContainer(
          key: ValueKey<String>('carousel-dot-$i'),
          duration: motion.duration(RegalosSprings.softDuration),
          curve: motion.curve(RegalosCurves.soft),
          width: RegalosSizes.dot,
          height: RegalosSizes.dot,
          decoration: BoxDecoration(
            color: active(i) ? t.ink : t.track,
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: page!,
      builder: (context, _) {
        final p = pageValue!().clamp(
          0.0,
          math.max(0, count - shown).toDouble(),
        );
        return _row(t, (i) {
          final c = carouselDotCoverage(i, p, shown);
          return Transform.scale(
            scale: 1 + 0.3 * c,
            child: DecoratedBox(
              key: ValueKey<String>('carousel-dot-$i'),
              decoration: BoxDecoration(
                color: Color.lerp(t.track, t.ink, c),
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: RegalosSizes.dot),
            ),
          );
        });
      },
    );
  }

  Widget _row(RegalosTokens t, Widget Function(int i) dot) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: dot(i),
        ),
    ],
  );
}

/// Los textos de una tarjeta del carrusel: título, fecha, regalos comprados y
/// días con su unidad.
class _CardTexts {
  _CardTexts(
    AppLocalizations l10n,
    NextOccasion next,
    Map<String, Recipient> people,
    List<Gift> gifts,
    FreeWishCounts wishes,
  ) : title = occasionTitle(
        l10n,
        next.occasion,
        personName: people[next.occasion.recipientId]?.name,
      ),
      unit = l10n.daysUnit(next.days),
      date = longDayMonth(next.date.month, next.date.day, l10n.localeName) {
    final mine = gifts.where((g) => g.occasionId == next.occasion.id).toList();
    final bought = mine.where((g) => !needsBuying(g)).length;
    // Una ocasión que solo tiene deseos dice cuántos, no «Sin regalos todavía»
    // (QA 1.0.7, m1).
    final free = wishes.ofOccasion(next.occasion.id);
    final none = free > 0 ? l10n.wishCount(free) : l10n.occasionNoGiftsYet;
    meta = mine.isEmpty
        ? none
        : l10n.occasionGiftsBought(bought, mine.length);
    shortMeta = mine.isEmpty
        ? none
        : l10n.occasionGiftsBoughtShort(bought, mine.length);
    shortDate = shortDayMonth(next.date.month, next.date.day, l10n.localeName);
  }

  final String title;
  final String unit;
  final String date;
  late final String meta;

  /// Lo mismo, abreviado, para las filas de 56 px («24 dic», «1 de 2
  /// comprados»).
  late final String shortMeta;
  late final String shortDate;
}

/// Una tarjeta de cuenta atrás con el tema de su ocasión (si el interruptor
/// «Temas de ocasión» está encendido) y su icono.
class _OccasionCard extends ConsumerWidget {
  const _OccasionCard({
    required this.next,
    required this.height,
    this.rollFromEmpty = false,
    this.rollDelay = Duration.zero,
    this.rollCue,
    this.rollFrom,
    this.pulseKey,
    this.parallax,
    this.cardKey,
    this.numberKey,
    this.compact = false,
  });

  final NextOccasion next;
  final double height;

  /// La tarjeta de la columna «Resumen».
  final bool compact;

  /// Para medir la tarjeta y su número: de ahí parte el vuelo hasta el detalle.
  final GlobalKey? cardKey;
  final GlobalKey? numberKey;
  final bool rollFromEmpty;
  final Duration rollDelay;
  final Object? rollCue;
  final int? rollFrom;
  final GlobalKey<SpringPulseState>? pulseKey;
  final Widget Function(Widget icon)? parallax;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(familyViewProvider);
    final themed = ref.watch(
      appearanceProvider.select((a) => a.occasionThemes),
    );
    final occasion = next.occasion;
    final texts = _CardTexts(
      l10n,
      next,
      ref.watch(familyFullViewProvider).recipientsById,
      view.gifts,
      ref.watch(freeWishCountsProvider),
    );
    final theme = themed ? OccasionTheme.forOccasion(occasion) : null;
    final motif = GarlandMotif.forTheme(theme);
    // La tarjeta crece hasta el detalle (momento K): una ruta del `Navigator`
    // raíz, porque el detalle vive en otra rama y un `Hero` no volaría. El
    // atrás vuelve a Personas, no a Ocasiones.
    void open() {
      final navigator = Navigator.of(context, rootNavigator: true);
      final root = navigator.context.findRenderObject();
      var tokens = RegalosTokens.of(context);
      if (theme != null && theme != tokens.occasion) {
        tokens = tokens.copyWith(occasion: theme);
      }
      final card = root == null || cardKey == null
          ? null
          : measureRect(cardKey!, root);
      final number = root == null || numberKey == null
          ? null
          : measureRect(numberKey!, root);
      if (card == null || number == null || cardKey == null) {
        // Sin medidas no hay de dónde volar: el detalle entra como una
        // pantalla más.
        context.push('/occasions/${occasion.id}?from=people');
        return;
      }
      unawaited(
        navigator.push<void>(
          OccasionExpandRoute(
            reduce: RegalosMotion.of(context).reduce,
            source: OccasionExpandSource(
              cardKey: cardKey!,
              numberKey: numberKey!,
              card: card,
              number: number,
              days: next.days,
              numberStyle: OccasionCountdownCard.numberStyleOf(
                tokens,
                compact: compact,
              ),
              soft: tokens.soft,
              border: tokens.cardBorder,
              surface: tokens.bg,
            ),
            builder: (_) =>
                OccasionDetailScreen(occasionId: occasion.id, fromPeople: true),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      button: true,
      label:
          '${next.days} ${texts.unit}. ${texts.title}. ${texts.date}. '
          '${texts.meta}',
      excludeSemantics: true,
      onTap: open,
      child: PointerSurface(
        child: InkWell(
          borderRadius: RegalosShape.card,
          onTap: open,
          child: OccasionCountdownCard(
            key: cardKey,
            numberKey: numberKey,
            days: next.days,
            unit: texts.unit,
            title: texts.title,
            date: texts.date,
            // La tarjeta compacta de «Resumen» lleva la fecha y los regalos en
            // una sola línea: con el texto abreviado cabe entera.
            meta: compact ? texts.shortMeta : texts.meta,
            // El icono del tipo (el Tió lleva el suyo, no el abeto de la
            // guirnalda de Navidad que comparte); sin guirnalda, ninguno.
            icon: motif == null
                ? null
                : occasionKindStrokeIcon(next.occasion.kind) ?? motif.cardIcon,
            occasion: theme,
            height: height,
            compact: compact,
            rollFromEmpty: rollFromEmpty,
            rollDelay: rollDelay,
            rollCue: rollCue,
            rollFrom: rollFrom,
            iconBuilder: (icon) {
              // El rebote de «hoy» envuelve al dibujo; el paralaje, por fuera.
              final pulsing = pulseKey == null
                  ? icon
                  : SpringPulse(key: pulseKey, from: 0.92, child: icon);
              return parallax == null ? pulsing : parallax!(pulsing);
            },
          ),
        ),
      ),
    );
  }
}
