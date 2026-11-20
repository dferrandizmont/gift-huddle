import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/dates.dart';
import '../../../core/motion/rolling_number.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/accent_palette.dart';
import '../../../core/theme/app_scrollbar.dart';
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
    (fill: p.surfaceOf(t.isDark), ink: p.inkOf(t.isDark));

/// El borde de una superficie de color: el de la muestra en claro y el pastel
/// al 30 % en oscuro.
Color boardBorderOf(RegalosTokens t, AccentPalette p) => p.borderOf(t.isDark);

/// La tira de próximas ocasiones del tablero: tarjetas pastel con los días que
/// faltan, el nombre, la fecha y cuántos regalos hay comprados. La misma en
/// «Hoy» y en «Ocasiones».
///
/// **Una sola fila**, nunca dos: todas las tarjetas miden [cardHeight] (72 a
/// 1×) de alto y `clamp(…, 200, 360)` de ancho (se reparten el ancho si
/// caben, y crecen lo que pida su texto para no cortarlo). Si no caben, la tira
/// se desplaza en horizontal con un degradado en el borde.
class BoardOccasionStrip extends ConsumerStatefulWidget {
  /// Crea la tira.
  const BoardOccasionStrip({
    super.key,
    required this.occasions,
    required this.onOpen,
    this.selectedId,
    this.trailing,
    this.endAction,
  });

  /// Las ocasiones, por orden.
  final List<Occasion> occasions;

  /// Se llama con la ocasión elegida.
  final ValueChanged<Occasion> onOpen;

  /// La ocasión elegida, si hay.
  final String? selectedId;

  /// Una tarjeta más al final de las ocasiones.
  final Widget? trailing;

  /// Un control suelto al final de la tira (p. ej. «Ver todas»): va fuera de
  /// la zona que se desplaza, centrado en vertical con las tarjetas, así que el
  /// desvanecido del borde nunca lo toca y se ve siempre.
  final Widget? endAction;

  /// El ancho cómodo de una tarjeta.
  static const double minCardWidth = 220;

  /// El ancho mínimo duro: si todas caben a 200 o más se reparten el ancho;
  /// solo si no caben a 200, la tira se desplaza.
  static const double hardMinCardWidth = 200;

  /// El ancho máximo de una tarjeta.
  static const double maxCardWidth = 360;

  /// El alto de todas las tarjetas, también la del presupuesto, a letra 1×.
  static const double cardHeight = 72;

  /// El alto de las tarjetas con el texto a [scaler]: [cardHeight] como mínimo
  /// y, si el texto crece, lo que piden los días, el nombre, los datos y la
  /// barra (a 2× no se recorta).
  static double cardHeightFor(TextScaler scaler) {
    final lines =
        scaler.scale(_numberSize) +
        scaler.scale(_titleSize) * _lineHeight +
        scaler.scale(_dataSize) * _lineHeight;
    return math.max(cardHeight, lines + 2 + _vertical * 2 + _barHeight);
  }

  // El cuerpo de la tarjeta: tamaños de los días, el nombre y los datos, el
  // alto de línea de estos dos, el relleno de arriba y de abajo y la barra.
  static const double _numberSize = 28;
  static const double _titleSize = 14;
  static const double _dataSize = 12;
  static const double _lineHeight = 1.15;
  static const double _vertical = 4;
  static const double _barHeight = 3;

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

  /// El sitio que se deja a cada lado de la tira que se desplaza para el aro
  /// de la tarjeta elegida.
  static const double _ringRoom = 4;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strip = _buildStrip(context);
    final action = widget.endAction;
    if (action == null) {
      return strip;
    }
    final height = BoardOccasionStrip.cardHeightFor(
      MediaQuery.textScalerOf(context),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: strip),
        // Del alto de las tarjetas y a su altura (4 de relleno arriba, como la
        // tira).
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 4),
          child: SizedBox(
            height: height,
            child: Center(child: action),
          ),
        ),
      ],
    );
  }

  Widget _buildStrip(BuildContext context) {
    final t = RegalosTokens.of(context);
    final w = widget;
    final count = w.occasions.length + (w.trailing == null ? 0 : 1);
    final l10n = AppLocalizations.of(context);
    final texts = [for (final o in w.occasions) _cardTexts(ref, l10n, o)];
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        const gap = BoardOccasionStrip.gap;
        // El ancho que pide el texto más largo: si no caben todas, la tira se
        // desplaza, pero ningún nombre ni dato se corta.
        final need = _cardNeed(context, t: t, scaler: scaler, texts: texts);
        final width = math.min(
          math.max(BoardOccasionStrip.cardWidthFor(box.maxWidth, count), need),
          BoardOccasionStrip.maxSharedCardWidth,
        );
        final height = BoardOccasionStrip.cardHeightFor(scaler);
        final total = count * width + (count - 1) * gap;
        final scrolls = total > box.maxWidth + 0.5;
        final row = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < w.occasions.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              SizedBox(
                width: width,
                child: BoardOccasionCard(
                  key: ValueKey<String>('board-occasion-${w.occasions[i].id}'),
                  occasion: w.occasions[i],
                  selected: w.occasions[i].id == w.selectedId,
                  onTap: () => w.onOpen(w.occasions[i]),
                ),
              ),
            ],
            if (w.trailing != null) ...[
              if (w.occasions.isNotEmpty) SizedBox(width: gap),
              SizedBox(width: width, height: height, child: w.trailing),
            ],
          ],
        );
        // Sitio para el aro de la ocasión elegida (2 + 2 por fuera) y, si se
        // desplaza, para la barra, que se dibuja encima del borde: va debajo
        // de las tarjetas, no sobre ellas.
        return SizedBox(
          height: height + 8 + (scrolls ? AppScrollbar.gutter : 0),
          child: scrolls
              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Cuatro de más a cada lado, para que el aro de la tarjeta
                    // elegida no se recorte; el relleno de 4 las devuelve a su
                    // sitio.
                    Positioned(
                      left: -_ringRoom,
                      right: -_ringRoom,
                      top: 0,
                      bottom: 0,
                      child: _EdgeFade(
                        controller: _scroll,
                        // Con el ratón, la tira también se arrastra.
                        child: MouseDragScroll(
                          child: Scrollbar(
                            controller: _scroll,
                            child: SingleChildScrollView(
                              controller: _scroll,
                              scrollDirection: Axis.horizontal,
                              padding: EdgeInsets.fromLTRB(
                                _ringRoom,
                                4,
                                _ringRoom,
                                4 + AppScrollbar.gutter,
                              ),
                              child: row,
                            ),
                          ),
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

/// El ancho que pide la tarjeta más ancha: el relleno y lo más largo entre los
/// días con su unidad, el nombre y los datos.
double _cardNeed(
  BuildContext context, {
  required RegalosTokens t,
  required TextScaler scaler,
  required List<_CardTexts> texts,
}) {
  final direction = Directionality.of(context);
  double widthOf(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  final number = _numberStyle(t);
  final title = _titleStyle(t);
  final data = _dataStyle(t);
  var need = BoardOccasionStrip.hardMinCardWidth;
  for (final x in texts) {
    final days =
        widthOf('${x.days ?? '·'}', number) + 8 + widthOf(x.unit, data);
    final body = math.max(
      days,
      math.max(
        widthOf(x.title, title),
        widthOf('${x.date} · ${x.detail}', data),
      ),
    );
    // 12 de relleno por lado y 8 de holgura (el número rueda y el texto se
    // pinta unas décimas más ancho).
    need = math.max(need, 12 + body + 12 + 8);
  }
  return need.ceilToDouble();
}

TextStyle _numberStyle(RegalosTokens t) => t.styles.screenTitle.copyWith(
  height: 1,
  fontSize: BoardOccasionStrip._numberSize,
);

TextStyle _titleStyle(RegalosTokens t) => t.styles.label.copyWith(
  height: BoardOccasionStrip._lineHeight,
  fontSize: BoardOccasionStrip._titleSize,
);

TextStyle _dataStyle(RegalosTokens t) => t.styles.caption.copyWith(
  height: BoardOccasionStrip._lineHeight,
  fontSize: BoardOccasionStrip._dataSize,
);

/// Lo que dice una tarjeta de ocasión: el nombre, los días con su unidad, la
/// fecha y el recuento de comprados, tal como los lee la tira y la propia
/// tarjeta.
typedef _CardTexts = ({
  String title,
  int? days,
  String unit,
  String date,
  String detail,
  String semantics,
});

_CardTexts _cardTexts(WidgetRef ref, AppLocalizations l10n, Occasion occasion) {
  final people = ref.watch(familyFullViewProvider).recipientsById;
  final count = ref.watch(boardOccasionCountProvider(occasion.id));
  final now = clock.now();
  final days = daysUntil(occasion, now);
  final date = nextDateOf(occasion, now);
  final dateText = date == null
      ? l10n.occasionPassed
      : shortDate(date, l10n.localeName);
  final empty = count.total == 0;
  final detail = empty
      ? l10n.boardNoGiftsYet
      : l10n.occasionGiftsBoughtShort(count.bought, count.total);
  final title = OccasionLabels(l10n, people).of(occasion);
  return (
    title: title,
    days: days,
    unit: l10n.daysUnit(days ?? 0),
    date: dateText,
    detail: detail,
    semantics: [
      title,
      if (days != null) '$days ${l10n.daysUnit(days)}',
      dateText,
      detail,
    ].join(', '),
  );
}

/// Una tarjeta de ocasión de la tira, de [BoardOccasionStrip.cardHeight] de
/// alto: los días en grande con su unidad, el nombre, los datos y la barra de
/// comprados abajo.
class BoardOccasionCard extends ConsumerWidget {
  /// Crea la tarjeta.
  const BoardOccasionCard({
    super.key,
    required this.occasion,
    required this.onTap,
    this.selected = false,
  });

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
    final palette = themed
        ? OccasionTheme.forOccasion(occasion).palette
        : t.accent;
    final colors = boardColorsOf(t, palette);
    final count = ref.watch(boardOccasionCountProvider(occasion.id));
    final texts = _cardTexts(ref, l10n, occasion);
    final empty = count.total == 0;
    final fraction = empty ? 0.0 : count.bought / count.total;
    final dataStyle = _dataStyle(t).copyWith(color: colors.ink);
    final numberStyle = _numberStyle(t).copyWith(color: colors.ink);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: texts.semantics,
      excludeSemantics: true,
      onTap: onTap,
      child: AnimatedContainer(
        duration: reduce ? RegalosMotion.fade : RegalosSprings.snapDuration,
        curve: reduce ? Curves.linear : RegalosCurves.snap,
        height: BoardOccasionStrip.cardHeightFor(
          MediaQuery.textScalerOf(context),
        ),
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
                    bottom: BoardOccasionStrip._barHeight,
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
                              if (texts.days == null)
                                Text('·', style: numberStyle)
                              else
                                RollingNumber(
                                  value: texts.days!,
                                  style: numberStyle,
                                ),
                              const SizedBox(width: 8),
                              Text(texts.unit, style: dataStyle),
                            ],
                          ),
                          Text(
                            texts.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _titleStyle(t).copyWith(color: colors.ink),
                          ),
                          Text(
                            '${texts.date} · ${texts.detail}',
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
      height: BoardOccasionStrip._barHeight,
      decoration: BoxDecoration(
        color: ink.withValues(alpha: 0.18),
        borderRadius: RegalosShape.bar,
      ),
      alignment: Alignment.centerLeft,
      child: AnimatedFractionallySizedBox(
        duration: reduce ? RegalosMotion.fade : RegalosSprings.snapDuration,
        curve: reduce ? Curves.linear : RegalosCurves.snap,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(color: ink, borderRadius: RegalosShape.bar),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Un desvanecido suave en los bordes de una tira que se desplaza, solo en el
/// lado donde hay más contenido: la máscara resta opacidad al propio contenido
/// (no pinta un color encima), así que sirve con cualquier fondo, en claro y en
/// oscuro, y nunca corta una tarjeta con un borde duro.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  /// El ancho del desvanecido.
  static const double width = 48;

  @override
  Widget build(BuildContext context) {
    final reduce = RegalosMotion.of(context).reduce;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final ready =
            controller.hasClients && controller.position.hasContentDimensions;
        final position = ready ? controller.position : null;
        // Antes de medir, se supone que hay más a la derecha.
        final moreRight =
            position == null || position.pixels < position.maxScrollExtent - 2;
        final moreLeft = position != null && position.pixels > 2;
        return TweenAnimationBuilder<({double left, double right})>(
          tween: _SidesTween(
            end: (left: moreLeft ? 1.0 : 0.0, right: moreRight ? 1.0 : 0.0),
          ),
          duration: reduce ? Duration.zero : RegalosMotion.fade,
          builder: (context, fade, child) => ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              final f = bounds.width <= 0
                  ? 0.0
                  : math.min(0.5, width / bounds.width);
              return LinearGradient(
                stops: [0, f, 1 - f, 1],
                colors: [
                  Color.fromRGBO(0, 0, 0, 1 - fade.left),
                  const Color(0xFF000000),
                  const Color(0xFF000000),
                  Color.fromRGBO(0, 0, 0, 1 - fade.right),
                ],
              ).createShader(bounds);
            },
            child: child,
          ),
          child: child,
        );
      },
    );
  }
}

class _SidesTween extends Tween<({double left, double right})> {
  _SidesTween({required ({double left, double right}) super.end});

  @override
  ({double left, double right}) lerp(double t) {
    final a = begin ?? end!;
    final b = end!;
    return (
      left: a.left + (b.left - a.left) * t,
      right: a.right + (b.right - a.right) * t,
    );
  }
}
