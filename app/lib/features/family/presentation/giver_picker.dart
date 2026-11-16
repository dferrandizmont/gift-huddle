import 'package:flutter/material.dart';

import '../../../core/layout/large_text.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/spring_pulse.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import 'family_texts.dart';

// El chip de quién regala un regalo y la fila de chips que se despliega en
// línea para cambiarlo. Los usan la hoja de una celda de Reparto y la vista
// por ocasión.

/// Opacidad del color de quién regala para el fondo de su chip, sobre la hoja
/// (16 %: con el texto del color llega a 4,5:1 en los seis).
const double kGiverChipTint = 0.16;

/// La fila de un regalo: lo que es ([info]) y quién lo regala ([chip]). Lado
/// a lado, o con letra grande el chip debajo, alineado con el título ([indent]
/// es el hueco de la casilla y su separación): juntos el título se quedaba en
/// dos palabras y «…».
class GiftRowLayout extends StatelessWidget {
  /// Crea la fila.
  const GiftRowLayout({
    super.key,
    required this.large,
    required this.indent,
    required this.info,
    required this.chip,
  });

  /// Si la letra es grande y el chip baja debajo.
  final bool large;

  /// Sangría del chip cuando va debajo.
  final double indent;

  /// Casilla, título y detalle del regalo.
  final Widget info;

  /// El chip de quién lo regala.
  final Widget chip;

  @override
  Widget build(BuildContext context) {
    if (large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          info,
          Padding(
            padding: EdgeInsets.only(left: indent, bottom: kStackedBottom),
            child: Align(alignment: Alignment.centerLeft, child: chip),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: info),
        const SizedBox(width: 8),
        chip,
      ],
    );
  }
}

/// El chip de quién regala un regalo: su color, con una flecha. Cambia de
/// ancho con un muelle (`bounce`) cuando cambia de nombre, y su texto se funde.
class GiverChip extends StatefulWidget {
  const GiverChip({super.key, required this.giver, required this.onTap});

  final Giver? giver;
  final VoidCallback onTap;

  @override
  State<GiverChip> createState() => _GiverChipState();
}

class _GiverChipState extends State<GiverChip> {
  final GlobalKey<SpringPulseState> _pulse = GlobalKey<SpringPulseState>();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final giver = widget.giver;
    // Apilado bajo el título con letra grande: usa el ancho que haya y admite
    // dos líneas, en vez de cortarse a 160 con «…».
    final large = isLargeText(context);
    final color = giver == null ? t.ink : t.giver(giver.colorIndex);
    final name = giver == null
        ? l10n.repartoSheetWho
        : giverDisplayName(l10n, giver.name);
    final face = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: AnimatedSwitcher(
            duration: RegalosMotion.fade,
            child: Text(
              name,
              key: ValueKey<String>(name),
              maxLines: large ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        StrokeIcon(AppIcons.chevronDown, size: 14, color: color),
      ],
    );
    return Semantics(
      button: true,
      label: l10n.repartoSheetChipLabel(
        giver == null
            ? l10n.repartoSheetWho
            : giverDisplayName(l10n, giver.name),
      ),
      excludeSemantics: true,
      onTap: widget.onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: large ? double.infinity : 160),
        child: SpringPulse(
          key: _pulse,
          trigger: giver?.id,
          from: 0.9,
          child: AnimatedSize(
            duration: motion.reduce
                ? Duration.zero
                : RegalosSprings.bounceDuration,
            curve: RegalosCurves.bounce,
            alignment: Alignment.centerRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _pulse.currentState?.play(from: 0.92);
                widget.onTap();
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(
                  widthFactor: 1,
                  child: giver == null
                      ? DashedBox(
                          color: color.withValues(alpha: 0.65),
                          radius: RegalosShape.chipRadius,
                          strokeWidth: 1,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: face,
                          ),
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color.alphaBlend(
                              color.withValues(alpha: kGiverChipTint),
                              t.sheet,
                            ),
                            borderRadius: RegalosShape.chip,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: face,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La fila de chips para elegir quién regala. Cada chip entra desfasado 30 ms
/// (opacidad, subida y escala con `bounce`).
class GiverPicker extends StatelessWidget {
  const GiverPicker({
    super.key,
    required this.givers,
    required this.selectedId,
    required this.onPick,
  });

  final List<Giver> givers;
  final String? selectedId;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final options = <({String? id, String name, Color color, Color onColor})>[
      for (final g in givers)
        (
          id: g.id,
          name: giverDisplayName(l10n, g.name),
          color: t.giver(g.colorIndex),
          onColor: t.giverOn(g.colorIndex),
        ),
      (
        id: null,
        name: l10n.repartoSheetNobody,
        color: t.textSecondary,
        onColor: t.bg,
      ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 0,
      children: [
        for (var i = 0; i < options.length; i++)
          StaggerIn(
            index: i,
            child: PickerChip(
              label: options[i].name,
              color: options[i].color,
              onColor: options[i].onColor,
              selected: options[i].id == selectedId,
              onTap: () => onPick(options[i].id),
            ),
          ),
      ],
    );
  }
}

/// Entrada escalonada de un chip: 30 ms de retraso por posición, opacidad
/// 0 → 1, subida de −8 a 0 y escala 0,88 → 1 con el muelle `bounce`. Con
/// «Reducir movimiento», solo se funde en 150 ms.
class StaggerIn extends StatefulWidget {
  const StaggerIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  static const int _stepMs = 30;
  AnimationController? _controller;
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) {
      return;
    }
    _reduce = RegalosMotion.of(context).reduce;
    final total = _reduce
        ? RegalosMotion.fade.inMilliseconds
        : RegalosSprings.bounceDuration.inMilliseconds + widget.index * _stepMs;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    )..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller!;
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      builder: (context, child) {
        if (c.isCompleted) {
          return child!;
        }
        final elapsed = c.value * c.duration!.inMilliseconds;
        if (_reduce) {
          return Opacity(opacity: c.value, child: child);
        }
        final t =
            ((elapsed - widget.index * _stepMs) /
                    RegalosSprings.bounceDuration.inMilliseconds)
                .clamp(0.0, 1.0);
        final s = RegalosCurves.bounce.transform(t);
        return Opacity(
          opacity: s.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -8 * (1 - s)),
            child: Transform.scale(scale: 0.88 + 0.12 * s, child: child),
          ),
        );
      },
    );
  }
}

/// Un chip de la fila: tinte con el texto del color de quien regala. Al
/// elegirlo se rellena con ese color, el texto pasa a [onColor] (en oscuro,
/// la tinta oscura de su tono, no blanco) y aparece el visto, con el muelle
/// `snap`. El radio no cambia nunca (8).
class PickerChip extends StatelessWidget {
  const PickerChip({
    super.key,
    required this.label,
    required this.color,
    required this.onColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;

  /// Texto y visto sobre el chip elegido.
  final Color onColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final duration = motion.duration(RegalosSprings.snapDuration);
    final curve = motion.curve(RegalosCurves.snap);
    final tint = Color.alphaBlend(
      color.withValues(alpha: kGiverChipTint),
      t.sheet,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: duration,
              curve: curve,
              constraints: const BoxConstraints(minHeight: 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? color : tint,
                borderRadius: RegalosShape.chip,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: motion.reduce ? Duration.zero : duration,
                    curve: curve,
                    alignment: Alignment.centerLeft,
                    child: selected
                        ? Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: StrokeIcon(
                              AppIcons.check,
                              size: 14,
                              color: onColor,
                              strokeWidth: 2.25,
                            ),
                          )
                        : const SizedBox(height: 14),
                  ),
                  // Un nombre largo con letra grande acaba en «…» en vez de
                  // salirse del chip.
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: duration,
                      curve: curve,
                      style: DefaultTextStyle.of(context).style.merge(
                        TextStyle(
                          fontSize: 13,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          color: selected ? onColor : color,
                        ),
                      ),
                      child: Text(
                        label,
                        maxLines: isLargeText(context) ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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

/// El mismo regalo con otro [giverId] (`null` lo deja sin quién regala).
Gift giftWithGiver(Gift g, String? giverId) => Gift(
  id: g.id,
  recipientId: g.recipientId,
  title: g.title,
  giverId: giverId,
  occasionId: g.occasionId,
  status: g.status,
  rawStatus: g.rawStatus,
  plannedCents: g.plannedCents,
  actualCents: g.actualCents,
  store: g.store,
  url: g.url,
  note: g.note,
  size: g.size,
  requestedBy: g.requestedBy,
  requestNote: g.requestNote,
  surprise: g.surprise,
  year: g.year,
);
