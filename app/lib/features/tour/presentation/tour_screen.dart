import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/page_physics.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../application/tour_state.dart';
import 'tour_demos.dart';

/// La guía «Cómo funciona»: seis páginas cortas, cada una con una
/// demostración animada hecha con las filas y tarjetas de la app.
///
/// Se abre sola al terminar la bienvenida la primera vez y siempre desde
/// Ajustes (`/tour?from=settings`). «Saltar» está siempre a la vista; en la
/// última página el botón es «Empezar» (primer uso) o «Hecho» (desde Ajustes).
///
/// Con la ventana más ancha que alta y de 600 dp o más (tablet horizontal,
/// móvil girado) la demostración y el texto van lado a lado (la demostración
/// hasta 1,25 veces); en el móvil y en la tablet vertical, la demostración
/// arriba y el texto debajo, centrados y en una columna de 520 (en la tablet
/// vertical la demostración llena esa columna). Cabecera, texto y botones
/// comparten bordes, y la demostración no cambia de sitio de una página a
/// otra.
///
/// Movimiento: las páginas se cruzan con el muelle `snap`; la demostración
/// viaja algo más despacio que la página (parallax ligero) y cada una se
/// reproduce sola en bucle y vuelve a empezar al entrar. Con «Reducir
/// movimiento» no hay parallax ni bucle: cada demostración se queda en su
/// estado final y los botones cambian de página sin deslizar.
class TourScreen extends ConsumerStatefulWidget {
  /// Crea la guía. [onClose] la cierra; por defecto, vuelve a Ajustes si se
  /// abrió desde allí ([fromSettings]) y, si no, va a Personas.
  const TourScreen({super.key, this.fromSettings = false, this.onClose});

  /// Si se abrió desde Ajustes (y por tanto se cierra volviendo a ellos).
  final bool fromSettings;

  /// Lo que hace «Saltar» y el botón de la última página.
  final VoidCallback? onClose;

  /// Cuántas páginas tiene.
  static const int pageCount = 6;

  @override
  ConsumerState<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends ConsumerState<TourScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Se anota nada más abrirla: si la app se cierra a mitad, no vuelve a
    // salir sola. El router ya no tiene que mandar aquí.
    ref.read(tourAfterWelcomeProvider).pending = false;
    ref.read(tourSeenProvider).markSeen();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// La página ahora mismo, también entre dos.
  double get _pageValue => _pages.hasClients && _pages.position.haveDimensions
      ? (_pages.page ?? _index.toDouble())
      : _index.toDouble();

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else if (widget.fromSettings) {
      context.pop();
    } else {
      context.go(AppRoutes.people);
    }
  }

  void _goTo(int page) {
    final target = page.clamp(0, TourScreen.pageCount - 1);
    if (!_pages.hasClients) {
      return;
    }
    if (RegalosMotion.of(context).reduce) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(
        target,
        duration: RegalosSprings.snapDuration,
        curve: RegalosCurves.snap,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final last = _index == TourScreen.pageCount - 1;

    final titles = <String>[
      l10n.tour1Title,
      l10n.tour2Title,
      l10n.tour3Title,
      l10n.tour4Title,
      l10n.tour5Title,
      l10n.tour6Title,
    ];
    final bodies = <String>[
      l10n.tour1Body,
      l10n.tour2Body,
      l10n.tour3Body,
      l10n.tour4Body,
      l10n.tour5Body,
      l10n.tour6Body,
    ];

    // Los mismos bordes para la cabecera, la columna de texto y los botones:
    // la columna de 520 (más el margen de 24) o, lado a lado, la de 960.
    final wide = tourIsWide(MediaQuery.sizeOf(context));
    final backWidth = MediaQuery.textScalerOf(context)
        .scale(_backMinWidth)
        .clamp(_backMinWidth, _backMaxWidth)
        .toDouble();
    final nextLabel = last
        ? (widget.fromSettings ? l10n.actionDone : l10n.obStart)
        : l10n.actionNext;

    return PopScope(
      // Atrás retrocede una página y, en la primera, cierra la guía: nunca
      // saca de la app.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (_index > 0) {
          _goTo(_index - 1);
        } else {
          _close();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              ContentWidth(
                maxWidth: wide ? _wideColumn : _stackedColumn + 2 * _pad,
                child: Padding(
                  // «Saltar» lleva 12 de relleno: su texto acaba en el margen.
                  padding: const EdgeInsets.fromLTRB(_pad, 4, _pad - 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(l10n.tourTitle, style: t.styles.meta),
                        ),
                      ),
                      TextButton(onPressed: _close, child: Text(l10n.tourSkip)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  physics: RegalosPagePhysics(reduce: reduce),
                  itemCount: TourScreen.pageCount,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _TourPage(
                    index: i,
                    demo: TourDemo.values[i],
                    titles: titles,
                    bodies: bodies,
                    active: i == _index,
                    pages: _pages,
                    pageValue: () => _pageValue,
                  ),
                ),
              ),
              ContentWidth(
                maxWidth: _stackedColumn + 2 * _pad,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(_pad, 4, _pad, 12),
                  // «Atrás» entra por la izquierda empujando a «Siguiente» (y
                  // a los puntos, que van sobre él: mismo eje) con `snap`;
                  // con «Reducir movimiento», sin animar.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: _index > 0 ? 1 : 0),
                    duration: reduce
                        ? Duration.zero
                        : RegalosSprings.snapDuration,
                    curve: RegalosCurves.snap,
                    builder: (context, v, _) {
                      final gap = (backWidth + _backGap) * v.clamp(0.0, 1.0);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              SizedBox(width: gap),
                              Expanded(
                                child: Semantics(
                                  key: const ValueKey<String>('tour-dots'),
                                  container: true,
                                  liveRegion: true,
                                  label: l10n.tourPageOf(
                                    _index + 1,
                                    TourScreen.pageCount,
                                  ),
                                  excludeSemantics: true,
                                  child: _TourDots(
                                    count: TourScreen.pageCount,
                                    current: _index,
                                    page: _pages,
                                    pageValue: () => _pageValue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              SizedBox(
                                width: gap,
                                height: kMinInteractiveDimension,
                                child: ClipRect(
                                  child: OverflowBox(
                                    alignment: Alignment.centerLeft,
                                    minWidth: backWidth + _backGap,
                                    maxWidth: backWidth + _backGap,
                                    child: Opacity(
                                      opacity: v.clamp(0.0, 1.0),
                                      child: IgnorePointer(
                                        ignoring: _index == 0,
                                        child: ExcludeSemantics(
                                          excluding: _index == 0,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: _backGap,
                                            ),
                                            child: TextButton(
                                              onPressed: () =>
                                                  _goTo(_index - 1),
                                              child: Text(l10n.actionBack),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: FilledButton(
                                  onPressed: last
                                      ? _close
                                      : () => _goTo(_index + 1),
                                  child: Text(nextLabel),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Lo que mide «Atrás» (que quepa «Enrere» y «Back»), sin letra grande, y
  /// lo que se separa de «Siguiente».
  static const double _backMinWidth = 88;
  static const double _backMaxWidth = 150;
  static const double _backGap = 8;
}

/// Margen lateral de la guía.
const double _pad = 24;

/// Ancho de la columna de texto (y de los botones) apilada.
const double _stackedColumn = 520;

/// Ancho de la columna de la guía lado a lado.
const double _wideColumn = 960;

/// Si la guía va lado a lado: la ventana es de tablet (600 dp o más) y más
/// ancha que alta. Si no, la demostración arriba y el texto debajo.
bool tourIsWide(Size window) =>
    window.width >= RegalosBreakpoints.medium && window.width > window.height;

/// Una página de la guía: la demostración y su texto.
///
/// Lado a lado (ver [tourIsWide]): centrados en una columna de 960 como
/// máximo y la demostración hasta 1,25 veces. Si no, la demostración arriba y
/// el texto debajo, en una columna de 520 centrada; en tablet la demostración
/// ocupa el ancho de esa columna si cabe en el alto. La demostración nunca
/// cambia de sitio de una página a otra: el texto reserva la altura de la
/// página que más ocupa (con la letra y el idioma de ahora) y se alinea arriba,
/// y es el bloque entero el que se centra. Si no cabe (letra grande, móvil
/// girado) la página se desplaza.
class _TourPage extends StatelessWidget {
  const _TourPage({
    required this.index,
    required this.demo,
    required this.titles,
    required this.bodies,
    required this.active,
    required this.pages,
    required this.pageValue,
  });

  final int index;
  final TourDemo demo;
  final List<String> titles;
  final List<String> bodies;
  final bool active;
  final Listenable pages;
  final double Function() pageValue;

  /// Lo que se agranda la demostración como máximo lado a lado.
  static const double maxScale = 1.25;

  /// Hueco entre la demostración y el texto cuando van apilados.
  static const double gap = 24;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final window = MediaQuery.sizeOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final defaultStyle = DefaultTextStyle.of(context).style;
    final wide = tourIsWide(window);
    final tablet = window.width >= RegalosBreakpoints.medium;
    return LayoutBuilder(
      builder: (context, box) {
        final contentWidth = math.min(
          box.maxWidth,
          wide ? _wideColumn : _stackedColumn + 2 * _pad,
        );
        final columnWidth = wide
            ? (contentWidth - 3 * _pad) / 2
            : contentWidth - 2 * _pad;

        // La altura del texto de la página que más ocupa: todas la reservan.
        double textHeight(int i) {
          double measure(String text, TextStyle style) {
            final painter = TextPainter(
              text: TextSpan(
                text: text,
                // Como lo resuelve `Text`: sobre el estilo por defecto.
                style: defaultStyle.merge(style),
              ),
              textDirection: direction,
              textScaler: scaler,
            )..layout(maxWidth: columnWidth);
            final h = painter.height;
            painter.dispose();
            return h;
          }

          return measure(titles[i], t.styles.screenTitle) +
              8 +
              measure(bodies[i], t.styles.body);
        }

        var reserved = 0.0;
        for (var i = 0; i < titles.length; i++) {
          reserved = math.max(reserved, textHeight(i));
        }

        var scale = math.min(
          wide ? maxScale : (tablet ? double.infinity : 1.0),
          columnWidth / TourStage.size.width,
        );
        if (wide) {
          // Lado a lado no se desplaza la demostración: cabe en el alto.
          scale = math.min(
            scale,
            (box.maxHeight - 2 * 16) / TourStage.size.height,
          );
        } else if (tablet) {
          // La tablet vertical llena la columna si cabe en el alto.
          scale = math.min(
            scale,
            (box.maxHeight - reserved - gap - 2 * 16) / TourStage.size.height,
          );
        }
        scale = scale.clamp(0.4, 2.0).toDouble();

        final stage = SizedBox(
          width: TourStage.size.width * scale,
          height: TourStage.size.height * scale,
          child: FittedBox(
            child: TourStage(child: tourDemoFor(demo, active: active)),
          ),
        );

        final texts = SizedBox(
          height: reserved,
          width: columnWidth,
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(titles[index], style: t.styles.screenTitle),
                ),
                const SizedBox(height: 8),
                Text(bodies[index], style: t.styles.body),
              ],
            ),
          ),
        );

        // La demostración viaja más despacio que la página y el texto algo más
        // deprisa: parallax ligero. Con «Reducir movimiento», nada se mueve.
        Widget parallax(double factor, Widget child) => AnimatedBuilder(
          animation: pages,
          child: child,
          builder: (context, child) {
            if (reduce) {
              return child!;
            }
            final delta = (index - pageValue()).clamp(-1.0, 1.0);
            return Opacity(
              opacity: (1 - delta.abs() * 0.7).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(delta * box.maxWidth * factor, 0),
                child: child,
              ),
            );
          },
        );

        final content = wide
            ? ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _pad,
                    vertical: 16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: Center(child: parallax(-0.25, stage))),
                      const SizedBox(width: _pad),
                      Expanded(child: parallax(0.08, texts)),
                    ],
                  ),
                ),
              )
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _pad,
                    vertical: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: parallax(-0.25, stage)),
                      const SizedBox(height: gap),
                      parallax(0.08, texts),
                    ],
                  ),
                ),
              );

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

/// Los puntos de página: siguen al dedo (cada uno se enciende según cuánto
/// de él cubre la página, también entre dos) y el activo crece de escala 1 a
/// 1,3; nunca se ensanchan a píldora. Con «Reducir movimiento» solo cambia el
/// color, en 150 ms, al llegar a la página.
class _TourDots extends StatelessWidget {
  const _TourDots({
    required this.count,
    required this.current,
    required this.page,
    required this.pageValue,
  });

  final int count;
  final int current;
  final Listenable page;
  final double Function() pageValue;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    if (motion.reduce) {
      return _row(
        (i) => AnimatedContainer(
          duration: motion.duration(RegalosSprings.softDuration),
          curve: motion.curve(RegalosCurves.soft),
          width: RegalosSizes.dot,
          height: RegalosSizes.dot,
          decoration: BoxDecoration(
            color: i == current ? t.ink : t.track,
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: page,
      builder: (context, _) {
        final p = pageValue().clamp(0.0, count - 1.0);
        return _row((i) {
          final c = (1 - (p - i).abs()).clamp(0.0, 1.0);
          return Transform.scale(
            scale: 1 + 0.3 * c,
            child: DecoratedBox(
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

  Widget _row(Widget Function(int i) dot) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: dot(i),
        ),
    ],
  );
}
