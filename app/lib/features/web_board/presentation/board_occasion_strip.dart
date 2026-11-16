import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/dates.dart';
import '../../../core/motion/rolling_number.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/accent_palette.dart';
import '../../../core/theme/occasion_theme.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/pointer_surface.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/gift_logic.dart';
import '../../family/domain/next_occasion.dart';
import '../../family/presentation/family_texts.dart';
import '../../settings/application/appearance_provider.dart';
import '../application/board_lanes.dart';

/// Los dos colores de una paleta en la interfaz actual: el pastel de fondo y
/// su tinta (los de los avatares y las tarjetas de ocasión).
({Color fill, Color ink}) boardColorsOf(RegalosTokens t, AccentPalette p) =>
    (fill: t.isDark ? p.tintD : p.pastel, ink: t.isDark ? p.tintaD : p.tinta);

/// La tira de próximas ocasiones del tablero: tarjetas pastel con los días que
/// faltan, el nombre, la fecha y cuántos regalos hay comprados.
///
/// **Una sola fila**, nunca dos: todas las tarjetas miden 88 de alto y
/// `clamp(…, 200, 360)` de ancho (se reparten el ancho si caben). Si no caben,
/// la tira se desplaza en horizontal con un degradado en el borde.
class BoardOccasionStrip extends ConsumerStatefulWidget {
  /// Crea la tira.
  const BoardOccasionStrip({
    super.key,
    required this.occasions,
    required this.onOpen,
    this.selectedId,
    this.trailing,
  });

  /// Las ocasiones, por orden.
  final List<Occasion> occasions;

  /// Se llama con la ocasión elegida.
  final ValueChanged<Occasion> onOpen;

  /// La ocasión elegida, si hay.
  final String? selectedId;

  /// Una tarjeta más al final (el presupuesto).
  final Widget? trailing;

  /// El ancho cómodo de una tarjeta.
  static const double minCardWidth = 220;

  /// El ancho mínimo duro: si todas caben a 200 o más se reparten el ancho;
  /// solo si no caben a 200, la tira se desplaza.
  static const double hardMinCardWidth = 200;

  /// El ancho máximo de una tarjeta.
  static const double maxCardWidth = 360;

  /// El alto de todas las tarjetas, también la del presupuesto: 88 con los
  /// datos en una línea y [cardHeightTwoLines] si alguna los lleva en dos.
  static const double cardHeight = 88;

  /// El alto de las tarjetas cuando los datos van en dos líneas.
  static const double cardHeightTwoLines = 100;

  /// El hueco entre tarjetas.
  static const double gap = 12;

  /// El ancho de cada una de [count] tarjetas en [available] de sitio.
  ///
  /// Con 4 o más que caben en una fila, se reparten el ancho entero (como
  /// mucho 520 cada una), así que el borde derecho es el de los carriles. Con
  /// 1 a 3, como mucho 360 y pegadas a la izquierda. Si no caben a
  /// [hardMinCardWidth], 200 y se desplaza.
  static double cardWidthFor(double available, int count) {
    if (count <= 0) {
      return maxCardWidth;
    }
    final share = (available - (count - 1) * gap) / count;
    if (share < hardMinCardWidth) {
      return hardMinCardWidth;
    }
    return math.min(count >= 4 ? maxSharedCardWidth : maxCardWidth, share);
  }

  /// El ancho máximo de una tarjeta cuando son 4 o más y se reparten el ancho.
  static const double maxSharedCardWidth = 520;

  @override
  ConsumerState<BoardOccasionStrip> createState() => _BoardOccasionStripState();
}

class _BoardOccasionStripState extends ConsumerState<BoardOccasionStrip> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final w = widget;
    final count = w.occasions.length + (w.trailing == null ? 0 : 1);
    final l10n = AppLocalizations.of(context);
    final texts = [for (final o in w.occasions) _cardTexts(ref, l10n, o)];
    final scaler = MediaQuery.textScalerOf(context);
    final dataStyle = t.styles.caption.copyWith(height: 1.25);
    return LayoutBuilder(
      builder: (context, box) {
        final width = BoardOccasionStrip.cardWidthFor(box.maxWidth, count);
        // Los datos van en una sola línea si caben en todas las tarjetas; si
        // no, en dos, y todas miden 100 en lugar de 88.
        final twoLines = texts.any((x) {
          final painter = TextPainter(
            text: TextSpan(text: '${x.date} · ${x.detail}', style: dataStyle),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final fits = painter.width <= width - 24;
          painter.dispose();
          return !fits;
        });
        final height = twoLines
            ? BoardOccasionStrip.cardHeightTwoLines
            : BoardOccasionStrip.cardHeight;
        final total = count * width + (count - 1) * BoardOccasionStrip.gap;
        final scrolls = total > box.maxWidth + 0.5;
        final row = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < w.occasions.length; i++) ...[
              if (i > 0) const SizedBox(width: BoardOccasionStrip.gap),
              SizedBox(
                width: width,
                child: BoardOccasionCard(
                  key: ValueKey<String>('board-occasion-${w.occasions[i].id}'),
                  occasion: w.occasions[i],
                  twoLines: twoLines,
                  selected: w.occasions[i].id == w.selectedId,
                  onTap: () => w.onOpen(w.occasions[i]),
                ),
              ),
            ],
            if (w.trailing != null) ...[
              if (w.occasions.isNotEmpty)
                const SizedBox(width: BoardOccasionStrip.gap),
              SizedBox(width: width, height: height, child: w.trailing),
            ],
          ],
        );
        // Sitio para el aro de la ocasión elegida (2 + 2 por fuera).
        return SizedBox(
          height: height + 8,
          child: scrolls
              ? Stack(
                  children: [
                    Scrollbar(
                      controller: _scroll,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: row,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      width: 40,
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _scroll,
                          builder: (context, _) {
                            final more =
                                !_scroll.hasClients ||
                                !_scroll.position.hasContentDimensions ||
                                _scroll.position.pixels <
                                    _scroll.position.maxScrollExtent - 2;
                            return AnimatedOpacity(
                              opacity: more ? 1 : 0,
                              duration: RegalosMotion.fade,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [t.bg.withValues(alpha: 0), t.bg],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Align(alignment: Alignment.topLeft, child: row),
                ),
        );
      },
    );
  }
}

/// La fecha y el recuento de comprados de una ocasión, tal como los dice su
/// tarjeta.
({String date, String detail}) _cardTexts(
  WidgetRef ref,
  AppLocalizations l10n,
  Occasion occasion,
) {
  final count = ref.watch(boardOccasionCountProvider(occasion.id));
  final date = nextDateOf(occasion, clock.now());
  return (
    date: date == null ? l10n.occasionPassed : shortDate(date, l10n.localeName),
    detail: count.total == 0
        ? l10n.boardNoGiftsYet
        : l10n.occasionGiftsBoughtShort(count.bought, count.total),
  );
}

/// Una tarjeta de ocasión de la tira, de 88 de alto (100 con los datos en dos
/// líneas).
class BoardOccasionCard extends ConsumerWidget {
  /// Crea la tarjeta.
  const BoardOccasionCard({
    super.key,
    required this.occasion,
    required this.onTap,
    this.selected = false,
    this.twoLines = false,
  });

  /// Si los datos (fecha y comprados) van en dos líneas: la tarjeta mide 100.
  final bool twoLines;

  /// La ocasión.
  final Occasion occasion;

  /// Al tocarla.
  final VoidCallback onTap;

  /// Si es la elegida: lleva un aro de tinta de 2, separado 2 de la tarjeta.
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final themed = ref.watch(
      appearanceProvider.select((a) => a.occasionThemes),
    );
    final people = ref.watch(familyFullViewProvider).recipientsById;
    final palette = themed
        ? OccasionTheme.forOccasion(occasion).palette
        : t.accent;
    final colors = boardColorsOf(t, palette);
    final count = ref.watch(boardOccasionCountProvider(occasion.id));
    final now = clock.now();
    final days = daysUntil(occasion, now);
    final date = nextDateOf(occasion, now);
    final dateText = date == null
        ? l10n.occasionPassed
        : shortDate(date, l10n.localeName);
    final title = OccasionLabels(l10n, people).of(occasion);
    final empty = count.total == 0;
    final fraction = empty ? 0.0 : count.bought / count.total;
    final detail = empty
        ? l10n.boardNoGiftsYet
        : l10n.occasionGiftsBoughtShort(count.bought, count.total);
    final dataStyle = t.styles.caption.copyWith(
      color: colors.ink,
      height: 1.25,
    );
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: '$title, $dateText',
      excludeSemantics: true,
      onTap: onTap,
      child: AnimatedContainer(
        duration: reduce ? RegalosMotion.fade : RegalosSprings.snapDuration,
        curve: reduce ? Curves.linear : RegalosCurves.snap,
        height: twoLines
            ? BoardOccasionStrip.cardHeightTwoLines
            : BoardOccasionStrip.cardHeight,
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: RegalosShape.card,
          boxShadow: selected
              ? [
                  // La tinta, la de fuera (4), y encima el fondo (2): un aro de
                  // 2 separado 2 de la tarjeta.
                  BoxShadow(color: colors.ink, spreadRadius: 4),
                  BoxShadow(color: t.bg, spreadRadius: 2),
                ]
              : const <BoxShadow>[],
        ),
        child: PointerSurface(
          strength: 1.6,
          child: Material(
            color: Colors.transparent,
            borderRadius: RegalosShape.card,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Stack(
                children: [
                  // El texto, centrado en lo que deja la barra de abajo, que va
                  // pegada al borde.
                  Positioned.fill(
                    bottom: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              if (days == null)
                                Text(
                                  '·',
                                  style: t.styles.screenTitle.copyWith(
                                    height: 1,
                                    color: colors.ink,
                                  ),
                                )
                              else
                                RollingNumber(
                                  value: days,
                                  style: t.styles.screenTitle.copyWith(
                                    height: 1,
                                    color: colors.ink,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.daysUnit(days ?? 0),
                                style: t.styles.caption.copyWith(
                                  color: colors.ink,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.styles.label.copyWith(
                              color: colors.ink,
                              height: 1.25,
                            ),
                          ),
                          if (twoLines) ...[
                            Text(
                              dateText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: dataStyle,
                            ),
                            Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: dataStyle,
                            ),
                          ] else
                            Text(
                              '$dateText · $detail',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: dataStyle,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!empty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _Bar(fraction: fraction, ink: colors.ink),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.ink});

  final double fraction;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final reduce = RegalosMotion.of(context).reduce;
    return Container(
      height: 3,
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(2),
      ),
      alignment: Alignment.centerLeft,
      child: AnimatedFractionallySizedBox(
        duration: reduce ? RegalosMotion.fade : RegalosSprings.snapDuration,
        curve: reduce ? Curves.linear : RegalosCurves.snap,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(2),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
