import 'package:flutter/material.dart';

import '../../../core/motion/animated_status_glyph.dart';
import '../../../core/motion/rolling_number.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/theme/gift_status.dart';
import '../../../core/theme/neutral_palette.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/gift_row.dart';
import '../../../core/widgets/giver_dot.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/status_checkbox.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import 'tour_loop.dart';

/// Las seis demostraciones de la guía, en el orden de sus páginas.
enum TourDemo { addGift, bought, people, share, privacy, web }

/// La demostración de [demo]. Con [active] se reproduce; si no, se queda en
/// su punto de partida.
Widget tourDemoFor(TourDemo demo, {required bool active}) => switch (demo) {
  TourDemo.addGift => AddGiftDemo(active: active),
  TourDemo.bought => BoughtDemo(active: active),
  TourDemo.people => PeopleDemo(active: active),
  TourDemo.share => ShareDemo(active: active),
  TourDemo.privacy => PrivacyDemo(active: active),
  TourDemo.web => WebDemo(active: active),
};

/// El escenario de las demostraciones: una tarjeta de [size] fija. Dentro, las
/// filas y tarjetas de la app a su tamaño de siempre y con el tamaño de letra
/// de la propia demostración (no crece con el del sistema: es una ilustración,
/// y su significado lo dan el título y la frase de la página, que sí crecen).
/// Se esconde a los lectores de pantalla y no responde a toques.
class TourStage extends StatelessWidget {
  /// Crea el escenario con la demostración [child].
  const TourStage({super.key, required this.child});

  /// La demostración.
  final Widget child;

  /// Ancho y alto del escenario.
  static const Size size = Size(340, 280);

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.noScaling),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: RegalosShape.card,
              border: Border.all(color: t.separator),
            ),
            child: ClipRRect(
              borderRadius: RegalosShape.card,
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox.fromSize(size: size, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas comunes
// ---------------------------------------------------------------------------

/// Un recuadro que se despliega o se pliega en altura con un fundido (la fila
/// que se pliega de la app), de [factor] 0 a 1.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.factor, required this.child});

  final double factor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final f = factor.clamp(0.0, 1.0);
    if (f <= 0) {
      return const SizedBox.shrink();
    }
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: f,
        child: Opacity(opacity: f, child: child),
      ),
    );
  }
}

/// El aro de un toque, [p] de 0 (empieza) a 1 (se apaga). Sin toque no pinta.
class _TapRing extends StatelessWidget {
  const _TapRing(this.p);

  final double p;

  /// Diámetro del aro.
  static const double size = 36;

  @override
  Widget build(BuildContext context) {
    if (p <= 0 || p >= 1) {
      return const SizedBox.square(dimension: size);
    }
    final t = RegalosTokens.of(context);
    return Opacity(
      opacity: 1 - p,
      child: Transform.scale(
        scale: 0.55 + 0.6 * p,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Solo el aro, sin relleno: no tapa lo que se toca. Son 2 px
            // porque es el dedo, no el borde de un control.
            border: Border.all(color: t.ink, width: 2),
          ),
          child: const SizedBox.square(dimension: size),
        ),
      ),
    );
  }
}

/// Coloca el aro de un toque con su centro en ([x], [y]).
Widget _tapAt(double x, double y, double p) => Positioned(
  left: x - _TapRing.size / 2,
  top: y - _TapRing.size / 2,
  child: _TapRing(p),
);

/// La cabecera de una persona: avatar, nombre y una línea.
class _PersonHeader extends StatelessWidget {
  const _PersonHeader({
    required this.name,
    required this.colorIndex,
    required this.subtitle,
  });

  final String name;
  final int colorIndex;
  final Widget subtitle;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Row(
      children: [
        PersonAvatar(name: name, colorIndex: colorIndex, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: t.styles.screenTitleSmall),
              subtitle,
            ],
          ),
        ),
      ],
    );
  }
}

/// Una fila compacta de regalo: la casilla de estado, el nombre y quién lo
/// regala. Para las demostraciones que no tienen sitio para la fila entera.
class _MiniGift extends StatelessWidget {
  const _MiniGift({
    required this.name,
    required this.status,
    this.giver,
    this.height = 32,
  });

  final String name;
  final GiftStatus status;
  final int? giver;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          StatusGlyph(status: status, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: t.styles.metaStrong)),
          if (giver != null) ...[
            const SizedBox(width: 6),
            GiverDot(colorIndex: giver),
          ],
        ],
      ),
    );
  }
}

/// Una opción del editor (la ficha de «Para quién», «Ocasión»...), elegida o no.
class _DemoChip extends StatelessWidget {
  const _DemoChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return AnimatedContainer(
      duration: RegalosMotion.fade,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? t.selection : null,
        border: Border.all(color: selected ? t.selectionBorder : t.chipBorder),
        borderRadius: RegalosShape.chip,
      ),
      // El texto cambia de color a la vez que el fondo, no antes.
      child: AnimatedDefaultTextStyle(
        duration: RegalosMotion.fade,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.styles.metaStrong.copyWith(color: selected ? t.ink : t.text),
        child: Text(label),
      ),
    );
  }
}

/// Un elemento que entra: de 0 a 1, con un fundido y subiendo [dy] píxeles.
Widget _appear(double p, Widget child, {double dy = 6}) {
  final v = p.clamp(0.0, 1.0);
  return Opacity(
    opacity: v,
    child: Transform.translate(offset: Offset(0, dy * (1 - v)), child: child),
  );
}

/// El rebote de las entradas pequeñas: de [from] a 1 con `bounce`.
double _pop(double p, {double from = 0.8}) =>
    from + (1 - from) * RegalosCurves.bounce.transform(p.clamp(0.0, 1.0));

/// El nombre del estado, el mismo que usa el resto de la app.
String _statusLabel(AppLocalizations l10n, GiftStatus status) =>
    switch (status) {
      GiftStatus.idea => l10n.statusIdea,
      GiftStatus.decided => l10n.statusDecided,
      GiftStatus.bought => l10n.statusBought,
      GiftStatus.arrived => l10n.statusArrived,
      GiftStatus.wrapped => l10n.statusWrapped,
      GiftStatus.delivered => l10n.statusDelivered,
    };

// ---------------------------------------------------------------------------
// 1. Apunta un regalo
// ---------------------------------------------------------------------------

/// Página 1: el «+» abre el editor, se escribe el regalo, se elige a quién,
/// la ocasión y quién lo regala, y el regalo aparece en la lista.
class AddGiftDemo extends StatelessWidget {
  /// Crea la demostración.
  const AddGiftDemo({super.key, required this.active});

  /// Si se reproduce.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return TourLoop(active: active, rest: 0.7, builder: _build);
  }

  Widget _build(BuildContext context, double t) {
    final tk = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);

    final open =
        tourSeg(t, 0.14, 0.24, RegalosCurves.snap) -
        tourSeg(t, 0.80, 0.88, RegalosCurves.fold);
    final typing = tourSeg(t, 0.26, 0.40);
    final word = l10n.tourDemoScooter;
    final typed = word.substring(0, (word.length * typing).round());
    final isTyping = t >= 0.26 && t < 0.42;
    final newRow = tourSeg(t, 0.86, 0.94, RegalosCurves.fold);

    final list = Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PersonHeader(
              name: 'Nora',
              colorIndex: 4,
              subtitle: Text(l10n.giftCount(2), style: tk.styles.meta),
            ),
            const SizedBox(height: 8),
            GiftRow(
              name: l10n.tourDemoPajamas,
              giverName: l10n.giverUs,
              giverColorIndex: 0,
              status: GiftStatus.idea,
            ),
            _Reveal(
              factor: newRow,
              child: GiftRow(
                name: word,
                giverName: l10n.giverUs,
                giverColorIndex: 0,
                status: GiftStatus.idea,
              ),
            ),
          ],
        ),
      ),
    );

    final fab = Positioned(
      right: 16,
      bottom: 16,
      child: Opacity(
        opacity: (1 - open * 2).clamp(0.0, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tk.fill,
            borderRadius: RegalosShape.fab,
          ),
          child: SizedBox.square(
            dimension: 52,
            child: Center(
              child: StrokeIcon(
                AppIcons.plus,
                size: 24,
                color: tk.onFill,
                strokeWidth: 2.4,
              ),
            ),
          ),
        ),
      ),
    );

    final editor = Positioned(
      left: 12,
      right: 12,
      top: TourStage.size.height + (12 - TourStage.size.height) * open,
      height: 258,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tk.sheet,
          borderRadius: RegalosShape.card,
          border: Border.all(color: tk.separator),
          boxShadow: [BoxShadow(color: tk.shadow, blurRadius: 18)],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.giftEditorNewTitle, style: tk.styles.rowTitle),
                  const SizedBox(height: 8),
                  Text(l10n.giftFieldTitle, style: tk.styles.meta),
                  const SizedBox(height: 2),
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isTyping ? tk.ink : tk.chipBorder,
                      ),
                      borderRadius: RegalosShape.field,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(typed, style: tk.styles.body),
                        if (isTyping)
                          Container(
                            width: 1.5,
                            height: 18,
                            margin: const EdgeInsets.only(left: 1),
                            color: tk.ink,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  _chips(tk, l10n.fieldFor, [
                    ('Aritz', false),
                    ('Nora', t >= 0.42),
                    ('Leo', false),
                  ]),
                  _chips(tk, l10n.fieldOccasion, [
                    (l10n.tourDemoChristmas, false),
                    (l10n.occasionNameKings, t >= 0.52),
                  ]),
                  _chips(tk, l10n.fieldGiver, [
                    (l10n.giverUs, t >= 0.62),
                    (l10n.obGiverGrandparents, false),
                  ]),
                  const Spacer(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tk.fill,
                      borderRadius: RegalosShape.button,
                    ),
                    child: SizedBox(
                      height: 36,
                      child: Center(
                        child: Text(
                          l10n.actionSave,
                          style: tk.styles.label.copyWith(color: tk.onFill),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _tapAt(158, 258 - 12 - 18, tourSeg(t, 0.72, 0.80)),
          ],
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        list,
        fab,
        _tapAt(
          TourStage.size.width - 16 - 26,
          TourStage.size.height - 16 - 26,
          tourSeg(t, 0.08, 0.16),
        ),
        editor,
      ],
    );
  }

  Widget _chips(RegalosTokens tk, String label, List<(String, bool)> options) =>
      SizedBox(
        height: 34,
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tk.styles.meta,
              ),
            ),
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              // El espacio se reparte según lo largo de cada ficha: con partes
              // iguales «Grandparents» se recortaría junto a «Us».
              Flexible(
                flex: options[i].$1.length + 3,
                child: _DemoChip(label: options[i].$1, selected: options[i].$2),
              ),
            ],
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// 2. Márcalo como comprado
// ---------------------------------------------------------------------------

/// Página 2: el detalle de una ocasión. Se toca la casilla de un regalo de
/// «Pendiente de comprar»: la casilla barre a «Comprado», la fila se pliega, el
/// número de «por llegar» sube y el aviso con «Deshacer» lo devuelve. Es lo que
/// hace la pantalla de la ocasión (`_BuyRow` en `occasion_detail_screen.dart`).
class BoughtDemo extends StatelessWidget {
  /// Crea la demostración.
  const BoughtDemo({super.key, required this.active});

  /// Si se reproduce.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return TourLoop(active: active, rest: 0.62, builder: _build);
  }

  Widget _stat(RegalosTokens tk, GiftStatus glyph, int count, String label) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: tk.bg,
            border: Border.all(color: tk.separator),
            borderRadius: RegalosShape.card,
          ),
          child: Row(
            children: [
              StatusGlyph(status: glyph, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RollingNumber(
                      value: count,
                      style: tk.styles.stat.copyWith(fontSize: 20, height: 1.1),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tk.styles.meta,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  /// La fila de «Pendiente de comprar»: casilla, regalo y, a la derecha, la
  /// persona.
  Widget _buyRow(
    RegalosTokens tk,
    String title,
    String person,
    GiftStatus status,
  ) => SizedBox(
    height: 48,
    child: Row(
      children: [
        const SizedBox(width: 4),
        SizedBox.square(
          dimension: 44,
          child: Center(child: AnimatedStatusGlyph(status: status, size: 24)),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tk.styles.body,
          ),
        ),
        const SizedBox(width: 8),
        Text(person, style: tk.styles.meta),
      ],
    ),
  );

  Widget _build(BuildContext context, double t) {
    final tk = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final away = tourSeg(t, 0.30, 0.44, RegalosCurves.fold);
    final back = tourSeg(t, 0.80, 0.92, RegalosCurves.fold);
    final rowFactor = 1 - away + back;
    // El estado de la casilla y los números cambian con el primer toque, y
    // vuelven con «Deshacer».
    final bought = t >= 0.2 && t < 0.8;
    final pending = bought ? 1 : 2;
    final toArrive = bought ? 1 : 0;
    final notice =
        tourSeg(t, 0.46, 0.52, RegalosCurves.snap) -
        tourSeg(t, 0.82, 0.88, RegalosCurves.fold);
    final scooter = l10n.tourDemoScooter;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.occasionNameKings, style: tk.styles.screenTitleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _stat(tk, GiftStatus.wrapped, 0, l10n.occasionToWrap),
                    const SizedBox(width: 10),
                    _stat(
                      tk,
                      GiftStatus.bought,
                      toArrive,
                      l10n.occasionToArrive,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.occasionPendingBuySection,
                        style: tk.styles.sectionTitle,
                      ),
                    ),
                    ValueSwitcher(
                      alignment: Alignment.centerRight,
                      child: Text(
                        l10n.giftCount(pending),
                        key: ValueKey<int>(pending),
                        style: tk.styles.meta,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Text(
                    l10n.occasionStoreNone,
                    style: tk.styles.label.copyWith(color: tk.ink),
                  ),
                ),
                _Reveal(
                  factor: rowFactor,
                  child: _buyRow(
                    tk,
                    scooter,
                    'Nora',
                    bought ? GiftStatus.bought : GiftStatus.decided,
                  ),
                ),
                _buyRow(tk, l10n.tourDemoPuzzle, 'Leo', GiftStatus.decided),
              ],
            ),
          ),
        ),
        _tapAt(42, 196, tourSeg(t, 0.12, 0.20)),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Opacity(
            opacity: notice.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 40 * (1 - notice)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.inverseSurface,
                  borderRadius: RegalosShape.card,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.giftStatusChanged(
                            scooter,
                            _statusLabel(l10n, GiftStatus.bought),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tk.styles.body.copyWith(
                            color: scheme.onInverseSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        l10n.actionUndo,
                        style: tk.styles.label.copyWith(
                          color: scheme.inversePrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        _tapAt(
          TourStage.size.width - 12 - 14 - 26,
          TourStage.size.height - 12 - 22,
          tourSeg(t, 0.70, 0.78),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Personas y ocasiones
// ---------------------------------------------------------------------------

/// Página 3: tres personas, la lista de una por ocasiones y el reparto de
/// quién paga.
class PeopleDemo extends StatelessWidget {
  /// Crea la demostración.
  const PeopleDemo({super.key, required this.active});

  /// Si se reproduce.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return TourLoop(active: active, rest: 0.5, builder: _build);
  }

  Widget _build(BuildContext context, double t) {
    final tk = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);

    final selected = t >= 0.14;
    final listIn = 1 - tourSeg(t, 0.52, 0.60);
    final splitIn = tourSeg(t, 0.58, 0.66);
    final grow = tourSeg(t, 0.66, 0.84, RegalosCurves.soft);

    Widget card(String name, int color, int count, {required bool on}) =>
        Expanded(
          child: AnimatedContainer(
            duration: RegalosMotion.fade,
            height: 76,
            decoration: BoxDecoration(
              color: on ? tk.soft : tk.bg,
              border: Border.all(color: on ? tk.ink : tk.separator),
              borderRadius: RegalosShape.card,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PersonAvatar(name: name, colorIndex: color, size: 30),
                const SizedBox(height: 4),
                Text(name, style: tk.styles.label),
                Text(l10n.giftCount(count), style: tk.styles.meta),
              ],
            ),
          ),
        );

    Widget occasionHeader(String name, int count) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(name, style: tk.styles.sectionTitle)),
          Text(l10n.giftCount(count), style: tk.styles.meta),
        ],
      ),
    );

    Widget split(String name, int giver, double fraction) => SizedBox(
      height: 30,
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Row(
              children: [
                GiverDot(colorIndex: giver),
                const SizedBox(width: 6),
                Expanded(child: Text(name, style: tk.styles.metaStrong)),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: tk.track),
                  child: const SizedBox(height: 10, width: double.infinity),
                ),
                FractionallySizedBox(
                  widthFactor: fraction * grow,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: tk.giver(giver)),
                    child: const SizedBox(height: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Las filas entran una tras otra tras elegir a Nora.
    Widget row(double from, Widget child) =>
        _appear(tourSeg(t, from, from + 0.07), child);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Row(
            children: [
              card('Aritz', 0, 3, on: false),
              const SizedBox(width: 8),
              card('Nora', 4, 3, on: selected),
              const SizedBox(width: 8),
              card('Leo', 3, 1, on: false),
            ],
          ),
        ),
        _tapAt(170, 56, tourSeg(t, 0.08, 0.16)),
        Positioned(
          left: 16,
          right: 16,
          top: 94,
          child: Opacity(
            opacity: listIn,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row(0.18, occasionHeader(l10n.tourDemoChristmas, 1)),
                row(
                  0.22,
                  GiftRow(
                    name: l10n.tourDemoScooter,
                    giverName: l10n.giverUs,
                    giverColorIndex: 0,
                    status: GiftStatus.decided,
                  ),
                ),
                row(0.30, occasionHeader(l10n.occasionNameKings, 1)),
                row(
                  0.34,
                  GiftRow(
                    name: l10n.tourDemoPajamas,
                    giverName: l10n.obGiverGrandparents,
                    giverColorIndex: 4,
                    status: GiftStatus.idea,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 94,
          child: Opacity(
            opacity: splitIn,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(l10n.navFamily, style: tk.styles.sectionTitle),
                ),
                split(l10n.giverUs, 0, 0.62),
                split(l10n.obGiverGrandparents, 4, 0.3),
                split(l10n.obGiverUncles, 1, 0.14),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. La familia comparte la lista
// ---------------------------------------------------------------------------

/// Página 4: un móvil enseña su QR, el otro lo lee, se conectan y el regalo
/// que apunta uno llega cifrado al otro.
class ShareDemo extends StatelessWidget {
  /// Crea la demostración.
  const ShareDemo({super.key, required this.active});

  /// Si se reproduce.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return TourLoop(active: active, rest: 0.92, builder: _build);
  }

  static const double _phoneW = 112;
  static const double _phoneH = 196;
  static const double _phoneTop = 36;
  static const double _leftX = 22;
  static const double _rightX = 340 - 22 - _phoneW;

  Widget _build(BuildContext context, double t) {
    final tk = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);

    // Primero se va el código, luego aparece «Conectado» y, al fin, la lista.
    final connected = tourSeg(t, 0.38, 0.43);
    final toList = tourSeg(t, 0.56, 0.62);
    final okLayer = tourSeg(t, 0.43, 0.48) * (1 - tourSeg(t, 0.52, 0.57));
    final qrLayer = 1 - connected;
    final badge = tourSeg(t, 0.44, 0.52, RegalosCurves.bounce);
    final packet = tourSeg(t, 0.68, 0.80, Curves.easeInOut);
    final packetShown = tourSeg(t, 0.66, 0.70) * (1 - tourSeg(t, 0.80, 0.84));
    final aRow = tourSeg(t, 0.64, 0.72);
    final bRow = tourSeg(t, 0.82, 0.90);
    // Dos barridos del visor: baja y sube.
    final scan = tourSeg(t, 0.10, 0.36) * 2;
    final sweepY = scan <= 1 ? scan : (scan <= 2 ? 2 - scan : 0.0);

    Widget phone(double left, Widget screen) => Positioned(
      left: left,
      top: _phoneTop,
      width: _phoneW,
      height: _phoneH,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tk.bg,
          borderRadius: RegalosShape.card,
          border: Border.all(color: tk.chipBorder),
        ),
        child: ClipRRect(borderRadius: RegalosShape.chip, child: screen),
      ),
    );

    Widget ok() => Opacity(
      opacity: okLayer.clamp(0.0, 1.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StrokeIcon(
              AppIcons.check,
              size: 30,
              color: tk.ink,
              strokeWidth: 2.6,
            ),
            const SizedBox(height: 6),
            Text(l10n.tourDemoConnected, style: tk.styles.metaStrong),
          ],
        ),
      ),
    );

    Widget list(double newRow) => Opacity(
      opacity: toList.clamp(0.0, 1.0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nora', style: tk.styles.label),
            const SizedBox(height: 6),
            _MiniGift(name: l10n.tourDemoPuzzle, status: GiftStatus.decided),
            _MiniGift(name: l10n.tourDemoPajamas, status: GiftStatus.idea),
            _Reveal(
              factor: newRow,
              child: _MiniGift(
                name: l10n.tourDemoScooter,
                status: GiftStatus.idea,
              ),
            ),
          ],
        ),
      ),
    );

    final qr = Opacity(
      opacity: qrLayer.clamp(0.0, 1.0),
      child: Center(
        // Un QR de verdad es oscuro sobre papel claro, también con el tema
        // oscuro.
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: NeutralPalette.light.bg,
            borderRadius: RegalosShape.chip,
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: SizedBox.square(
              dimension: 72,
              child: CustomPaint(
                painter: _QrPainter(NeutralPalette.light.text),
              ),
            ),
          ),
        ),
      ),
    );

    final viewfinder = Opacity(
      opacity: qrLayer.clamp(0.0, 1.0),
      child: Center(
        child: SizedBox.square(
          dimension: 84,
          child: CustomPaint(
            painter: _ViewfinderPainter(
              tk.ink,
              sweepY,
              qr: NeutralPalette.light.text,
              paper: NeutralPalette.light.bg,
            ),
          ),
        ),
      ),
    );

    final midY = _phoneTop + _phoneH / 2;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // La línea entre los dos móviles.
        Positioned(
          left: _leftX + _phoneW,
          width: _rightX - _leftX - _phoneW,
          top: midY,
          child: Opacity(
            opacity: badge.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(color: tk.ink),
              child: const SizedBox(height: 2),
            ),
          ),
        ),
        phone(_leftX, Stack(children: [qr, ok(), list(aRow)])),
        phone(_rightX, Stack(children: [viewfinder, ok(), list(bRow)])),
        Positioned(
          left: 170 - 17,
          top: midY - 17 - 28,
          child: Transform.scale(
            scale: badge.clamp(0.0, 1.4),
            child: Opacity(
              opacity: badge.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tk.soft,
                  border: Border.all(color: tk.ink),
                  borderRadius: RegalosShape.card,
                ),
                child: SizedBox.square(
                  dimension: 34,
                  child: Center(
                    child: StrokeIcon(
                      SettingsIcons.lock,
                      size: 18,
                      color: tk.ink,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: _leftX + _phoneW,
          width: _rightX - _leftX - _phoneW,
          top: midY + 8,
          child: _appear(
            tourSeg(t, 0.50, 0.58),
            Text(
              l10n.tourDemoEncrypted,
              textAlign: TextAlign.center,
              style: tk.styles.meta,
            ),
          ),
        ),
        // El paquete cifrado que viaja de un móvil al otro.
        Positioned(
          left: _leftX + _phoneW + (_rightX - _leftX - _phoneW - 22) * packet,
          top: midY - 8,
          child: Opacity(
            opacity: packetShown.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tk.fill,
                borderRadius: RegalosShape.tiny,
              ),
              child: SizedBox(
                width: 22,
                height: 18,
                child: Center(
                  child: StrokeIcon(
                    SettingsIcons.lock,
                    size: 12,
                    color: tk.onFill,
                    strokeWidth: 2.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Un código QR de mentira: tres cuadros de esquina y un relleno fijo.
class _QrPainter extends CustomPainter {
  const _QrPainter(this.color);

  final Color color;

  static const int _n = 17;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _n;
    final paint = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell;
    void finder(int cx, int cy) {
      canvas
        ..drawRect(
          Rect.fromLTWH(
            (cx + 0.5) * cell,
            (cy + 0.5) * cell,
            6 * cell,
            6 * cell,
          ),
          stroke,
        )
        ..drawRect(
          Rect.fromLTWH((cx + 2) * cell, (cy + 2) * cell, 3 * cell, 3 * cell),
          paint,
        );
    }

    finder(0, 0);
    finder(_n - 7, 0);
    finder(0, _n - 7);
    var seed = 7;
    for (var y = 0; y < _n; y++) {
      for (var x = 0; x < _n; x++) {
        final inFinder =
            (x < 8 && y < 8) ||
            (x >= _n - 8 && y < 8) ||
            (x < 8 && y >= _n - 8);
        seed = (seed * 31 + 17) % 97;
        if (!inFinder && seed % 3 != 0) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.color != color;
}

/// El visor de la cámara: cuatro esquinas, el QR pequeño y la línea que
/// barre.
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter(
    this.color,
    this.sweep, {
    required this.qr,
    required this.paper,
  });

  final Color color;

  /// El papel claro sobre el que va el QR.
  final Color paper;

  /// De 0 (arriba) a 1 (abajo).
  final double sweep;
  final Color qr;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final corner = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.square;
    const l = 16.0;
    canvas
      ..drawPath(
        Path()
          ..moveTo(0, l)
          ..lineTo(0, 0)
          ..lineTo(l, 0),
        corner,
      )
      ..drawPath(
        Path()
          ..moveTo(w - l, 0)
          ..lineTo(w, 0)
          ..lineTo(w, l),
        corner,
      )
      ..drawPath(
        Path()
          ..moveTo(0, w - l)
          ..lineTo(0, w)
          ..lineTo(l, w),
        corner,
      )
      ..drawPath(
        Path()
          ..moveTo(w - l, w)
          ..lineTo(w, w)
          ..lineTo(w, w - l),
        corner,
      )
      ..save()
      ..drawRect(
        Rect.fromLTWH(w * 0.14, w * 0.14, w * 0.72, w * 0.72),
        Paint()..color = paper,
      )
      ..translate(w * 0.2, w * 0.2);
    _QrPainter(qr).paint(canvas, Size.square(w * 0.6));
    canvas
      ..restore()
      ..drawLine(
        Offset(2, 2 + (w - 4) * sweep),
        Offset(w - 2, 2 + (w - 4) * sweep),
        Paint()
          ..color = color
          ..strokeWidth = 2,
      );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) =>
      old.sweep != sweep ||
      old.color != color ||
      old.qr != qr ||
      old.paper != paper;
}

// ---------------------------------------------------------------------------
// 5. Sorpresas y privacidad
// ---------------------------------------------------------------------------

/// Página 5: el móvil de Aritz no enseña sus regalos y se abre con un PIN.
class PrivacyDemo extends StatelessWidget {
  /// Crea la demostración.
  const PrivacyDemo({super.key, required this.active});

  /// Si se reproduce.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return TourLoop(active: active, rest: 0.92, builder: _build);
  }

  Widget _build(BuildContext context, double t) {
    final tk = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);

    final hide = tourSeg(t, 0.30, 0.42);
    final chip = tourSeg(t, 0.18, 0.28);
    const dots = [0.56, 0.63, 0.70, 0.77];

    Widget skeleton(double factor) => SizedBox(
      height: 36,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: factor,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tk.track,
              borderRadius: RegalosShape.tiny,
            ),
            child: const SizedBox(height: 14),
          ),
        ),
      ),
    );

    Widget gift(String name, GiftStatus status, int giver) =>
        _MiniGift(name: name, status: status, giver: giver, height: 36);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 16,
          right: 16,
          top: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Opacity(
                opacity: chip.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, -8 * (1 - chip)),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tk.soft,
                      borderRadius: RegalosShape.card,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          StrokeIcon(
                            SettingsIcons.phone,
                            size: 18,
                            color: tk.ink,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${l10n.settingsSelf}: Aritz',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tk.styles.metaStrong,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _PersonHeader(
                name: 'Aritz',
                colorIndex: 0,
                subtitle: Text(l10n.giftCount(3), style: tk.styles.meta),
              ),
              const SizedBox(height: 8),
              Stack(
                children: [
                  Opacity(
                    opacity: 1 - hide,
                    child: Column(
                      children: [
                        gift(l10n.tourDemoScooter, GiftStatus.decided, 0),
                        gift(l10n.tourDemoPuzzle, GiftStatus.bought, 4),
                        gift(l10n.tourDemoPajamas, GiftStatus.idea, 1),
                      ],
                    ),
                  ),
                  Opacity(
                    opacity: hide,
                    child: Column(
                      children: [
                        skeleton(0.72),
                        skeleton(0.56),
                        skeleton(0.66),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: Opacity(
                      opacity: hide,
                      child: Center(
                        child: Transform.scale(
                          scale: _pop(tourSeg(t, 0.34, 0.46)),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: tk.sheet,
                              border: Border.all(color: tk.separator),
                              borderRadius: RegalosShape.card,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StrokeIcon(
                                    SettingsIcons.lock,
                                    size: 18,
                                    color: tk.ink,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    l10n.tourDemoHidden,
                                    style: tk.styles.metaStrong,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: Opacity(
            opacity: tourSeg(t, 0.48, 0.56).clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tk.bg,
                border: Border.all(color: tk.separator),
                borderRadius: RegalosShape.card,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    StrokeIcon(SettingsIcons.lock, size: 20, color: tk.ink),
                    const SizedBox(width: 14),
                    for (final at in dots) ...[
                      AnimatedContainer(
                        duration: RegalosMotion.fade,
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: t >= at ? tk.ink : null,
                          border: Border.all(
                            color: t >= at ? tk.ink : tk.chipBorder,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    const Spacer(),
                    Transform.scale(
                      scale: _pop(tourSeg(t, 0.82, 0.92), from: 0.4),
                      child: Opacity(
                        opacity: tourSeg(t, 0.82, 0.88).clamp(0.0, 1.0),
                        child: StrokeIcon(
                          SettingsIcons.shield,
                          size: 24,
                          color: tk.ink,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 6. La web para el ordenador
// ---------------------------------------------------------------------------

/// Página 6: una ventana de navegador con los tres carriles; el cursor lleva
/// un regalo de «Por comprar» a «Listo».
class WebDemo extends StatelessWidget {
  /// Crea la demostración.
  const WebDemo({super.key, required this.active});

  /// Si se reproduce.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return TourLoop(active: active, rest: 0.8, builder: _build);
  }

  // Geometría de la ventana, dentro del escenario de 340 x 280.
  static const double _winX = 8;
  static const double _winY = 34;
  static const double _winW = 324;
  static const double _winH = 212;
  static const double _bar = 24;
  static const double _side = 36;
  static const double _lane = 88;
  static const double _gap = 6;
  static const double _card = 40;

  static double _laneX(int i) => _winX + _side + _gap + i * (_lane + _gap);
  static double _slotY(int k) => _winY + _bar + 8 + 22 + k * (_card + 6);

  Widget _build(BuildContext context, double t) {
    final tk = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);

    final toCard = tourSeg(t, 0.08, 0.26, Curves.easeInOut);
    final drag = tourSeg(t, 0.30, 0.64, Curves.easeInOut);
    final leave = tourSeg(t, 0.72, 0.84, Curves.easeInOut);
    final lifted = t >= 0.28 && t < 0.68;
    final puzzleUp = tourSeg(t, 0.62, 0.74, RegalosCurves.fold);

    final fromX = _laneX(1);
    final fromY = _slotY(0);
    final toX = _laneX(2);
    final toY = _slotY(0);
    final cardX = fromX + (toX - fromX) * drag;
    final cardY = fromY + (toY - fromY) * drag;

    Widget card(
      String name,
      GiftStatus status,
      double x,
      double y, {
      bool floating = false,
    }) => Positioned(
      left: x,
      top: y,
      width: _lane,
      height: _card,
      child: Transform.scale(
        scale: floating ? 1.05 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: floating ? tk.soft : tk.bg,
            border: Border.all(color: floating ? tk.ink : tk.separator),
            borderRadius: RegalosShape.chip,
            boxShadow: floating
                ? [BoxShadow(color: tk.shadow, blurRadius: 10)]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                StatusGlyph(status: status, size: 14),
                const SizedBox(width: 4),
                Expanded(child: Text(name, style: tk.styles.metaStrong)),
              ],
            ),
          ),
        ),
      ),
    );

    // Tarjetas sin nombre: el resto de la lista.
    Widget ghost(int lane, int slot) => Positioned(
      left: _laneX(lane),
      top: _slotY(slot),
      width: _lane,
      height: _card,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tk.surface,
          border: Border.all(color: tk.separator),
          borderRadius: RegalosShape.chip,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tk.track,
                borderRadius: RegalosShape.tiny,
              ),
              child: const SizedBox(width: 44, height: 8),
            ),
          ),
        ),
      ),
    );

    Widget laneHeader(int i, String text) => Positioned(
      left: _laneX(i),
      top: _winY + _bar + 8,
      width: _lane,
      child: Text(text, style: tk.styles.sectionTitle),
    );

    final cursorStart = Offset(_winX + _winW - 40, _winY + _winH - 40);
    final cursorOnCard = Offset(fromX + 52, fromY + 26);
    final cursorEnd = Offset(toX + 52, toY + 26);
    final Offset cursor;
    if (t < 0.30) {
      cursor = Offset.lerp(cursorStart, cursorOnCard, toCard)!;
    } else if (t < 0.72) {
      cursor = Offset.lerp(cursorOnCard, cursorEnd, drag)!;
    } else {
      cursor = Offset.lerp(cursorEnd, cursorEnd + const Offset(26, 34), leave)!;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: _winX,
          top: _winY,
          width: _winW,
          height: _winH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tk.bg,
              border: Border.all(color: tk.chipBorder),
              borderRadius: RegalosShape.card,
            ),
          ),
        ),
        // La barra del navegador.
        Positioned(
          left: _winX,
          top: _winY,
          width: _winW,
          height: _bar,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tk.soft,
              border: Border(bottom: BorderSide(color: tk.separator)),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(RegalosShape.cardRadius),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 10),
                for (var i = 0; i < 3; i++) ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tk.ink.withValues(alpha: 0.4),
                    ),
                    child: const SizedBox.square(dimension: 6),
                  ),
                  const SizedBox(width: 5),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tk.bg,
                      borderRadius: RegalosShape.tiny,
                    ),
                    child: const SizedBox(height: 12),
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ),
        // La barra lateral.
        Positioned(
          left: _winX,
          top: _winY + _bar,
          width: _side,
          height: _winH - _bar,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: tk.separator)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                StrokeIcon(SettingsIcons.people, size: 18, color: tk.ink),
                const SizedBox(height: 14),
                StrokeIcon(
                  SettingsIcons.gift,
                  size: 18,
                  color: tk.textSecondary,
                ),
                const SizedBox(height: 14),
                StrokeIcon(
                  SettingsIcons.calendar,
                  size: 18,
                  color: tk.textSecondary,
                ),
              ],
            ),
          ),
        ),
        ghost(0, 1),
        ghost(0, 2),
        ghost(1, 2),
        ghost(2, 1),
        ghost(2, 2),
        laneHeader(0, l10n.boardLaneDecide),
        laneHeader(1, l10n.boardLaneBuy),
        laneHeader(2, l10n.boardLaneReady),
        card(l10n.tourDemoPajamas, GiftStatus.idea, _laneX(0), _slotY(0)),
        card(
          l10n.tourDemoPuzzle,
          GiftStatus.decided,
          _laneX(1),
          _slotY(0) + (_slotY(1) - _slotY(0)) * (1 - puzzleUp),
        ),
        card(
          l10n.tourDemoScooter,
          t >= 0.66 ? GiftStatus.bought : GiftStatus.decided,
          cardX,
          cardY,
          floating: lifted,
        ),
        Positioned(
          left: cursor.dx,
          top: cursor.dy,
          child: CustomPaint(
            size: const Size(14, 20),
            painter: _CursorPainter(tk.text, tk.bg),
          ),
        ),
      ],
    );
  }
}

/// Un cursor de ratón.
class _CursorPainter extends CustomPainter {
  const _CursorPainter(this.fill, this.edge);

  final Color fill;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height * 0.86)
      ..lineTo(size.width * 0.3, size.height * 0.64)
      ..lineTo(size.width * 0.55, size.height)
      ..lineTo(size.width * 0.72, size.height * 0.92)
      ..lineTo(size.width * 0.48, size.height * 0.58)
      ..lineTo(size.width, size.height * 0.56)
      ..close();
    canvas
      ..drawPath(path, Paint()..color = fill)
      ..drawPath(
        path,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_CursorPainter old) =>
      old.fill != fill || old.edge != edge;
}
