import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/layout/pane_scope.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/accent_palette.dart';
import '../../../core/theme/gift_status.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/countdown_card.dart';
import '../../../core/widgets/gift_row.dart';
import '../../../core/widgets/regalos_switch.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/spring_pulse.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../application/appearance_provider.dart';
import 'settings_column.dart';

/// Nombre del color en el idioma de la app.
extension AccentIdL10n on AccentId {
  String label(AppLocalizations l10n) => switch (this) {
    AccentId.lavender => l10n.accentLavender,
    AccentId.sage => l10n.accentSage,
    AccentId.peach => l10n.accentPeach,
    AccentId.sky => l10n.accentSky,
    AccentId.rose => l10n.accentRose,
    AccentId.butter => l10n.accentButter,
  };
}

/// Ajustes › Apariencia: color, tema, temas de ocasión y vista previa.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key, this.embedded = false});

  /// Si va apilado en la columna de Ajustes del tablero de la web.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(appearanceProvider);
    final notifier = ref.read(appearanceProvider.notifier);
    final haptics = ref.read(hapticsProvider);
    final hapticsOn = ref.watch(hapticsEnabledProvider);

    // Entran los bloques, no las piezas sueltas (§1.6): el color, el tema,
    // los dos interruptores y la vista previa.
    var order = 0;
    final body = <Widget>[
      StaggerItem(
        index: order++,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ColorHeader(
              title: l10n.appearanceColorSection,
              name: settings.accent.label(l10n),
            ),
            _AccentGrid(
              selected: settings.accent,
              groupLabel: l10n.appearanceColorGroup,
              onSelected: (accent) {
                if (accent != settings.accent) {
                  haptics.selection();
                }
                notifier.setAccent(accent);
              },
            ),
          ],
        ),
      ),
      StaggerItem(
        index: order++,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: l10n.appearanceThemeSection,
              bordered: false,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            ),
            _ThemeModeSelector(
              selected: settings.themeMode,
              groupLabel: l10n.appearanceThemeGroup,
              onSelected: (mode) {
                if (mode != settings.themeMode) {
                  haptics.selection();
                }
                notifier.setThemeMode(mode);
              },
            ),
          ],
        ),
      ),
      StaggerItem(
        index: order++,
        child: _ToggleRow(
          title: l10n.appearanceOccasionTitle,
          hint: l10n.appearanceOccasionHint,
          value: settings.occasionThemes,
          topMargin: 14,
          onChanged: (v) => notifier.setOccasionThemes(enabled: v),
        ),
      ),
      StaggerItem(
        index: order++,
        child: _ToggleRow(
          title: l10n.appearanceHapticsTitle,
          topMargin: 0,
          topBorder: false,
          hint: l10n.appearanceHapticsHint,
          value: hapticsOn,
          onChanged: (v) {
            // Al encenderlas se nota; al apagarlas ya no suena nada.
            ref.read(hapticsEnabledProvider.notifier).set(enabled: v);
            if (v) {
              haptics.selection();
            }
          },
        ),
      ),
      StaggerItem(
        index: order++,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: l10n.appearancePreview,
              bordered: false,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            ),
            const _Preview(),
          ],
        ),
      ),
    ];
    if (embedded) {
      return StaggerScope(
        animate: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EmbeddedSectionHeader(title: l10n.settingsAppearance),
            ...body,
          ],
        ),
      );
    }
    return Scaffold(
      body: StaggerScope(
        // En dos paneles el detalle ya cambia con su propio eje: no repite
        // la entrada escalonada.
        animate: PaneScope.roleOf(context) != PaneRole.detail,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: settingsColumnPadding(context),
            children: [
              ScreenHeader(
                eyebrow: l10n.navSettings,
                title: l10n.settingsAppearance,
                backLabel: l10n.backTo(l10n.navSettings),
                onBack: () =>
                    context.canPop() ? context.pop() : context.go('/settings'),
              ),
              ...body,
            ],
          ),
        ),
      ),
    );
  }
}

/// Una fila con título, frase y un interruptor, entre dos filetes.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.topMargin = 14,
    this.topBorder = true,
  });

  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final double topMargin;
  final bool topBorder;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Container(
      margin: EdgeInsets.only(top: topMargin),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          top: topBorder ? BorderSide(color: t.separator) : BorderSide.none,
          bottom: BorderSide(color: t.separator),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Text(title, style: t.styles.rowTitleCompact),
                ),
                Text(hint, style: t.styles.meta),
              ],
            ),
          ),
          const SizedBox(width: 8),
          RegalosSwitch(
            value: value,
            semanticLabel: title,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// La cabecera de «Color»: como [SectionHeader], pero el nombre del color
/// elegido, a la derecha, se cruza con un fundido y 4 px de desplazamiento al
/// cambiar.
class _ColorHeader extends StatelessWidget {
  const _ColorHeader({required this.title, required this.name});

  final String title;
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final width = PaneScope.widthOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: t.styles.sectionTitle),
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width * 0.55),
            child: ValueSwitcher(
              alignment: Alignment.centerRight,
              child: Text(
                name,
                key: ValueKey<String>(name),
                style: t.styles.meta,
                textAlign: TextAlign.end,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccentGrid extends StatelessWidget {
  const _AccentGrid({
    required this.selected,
    required this.groupLabel,
    required this.onSelected,
  });

  final AccentId selected;
  final String groupLabel;
  final ValueChanged<AccentId> onSelected;

  @override
  Widget build(BuildContext context) {
    const columns = 3;
    final rows = <Widget>[];
    for (var start = 0; start < AccentId.values.length; start += columns) {
      rows.add(
        Row(
          children: [
            for (final id in AccentId.values.skip(start).take(columns))
              Expanded(
                child: _AccentSwatch(
                  accent: id,
                  selected: id == selected,
                  onTap: () => onSelected(id),
                ),
              ),
          ],
        ),
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: groupLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: rows),
      ),
    );
  }
}

/// Un color de acento. Al elegirlo, el anillo crece alrededor del círculo con
/// `snap` (y se encoge igual al soltarlo), el visto aparece con un rebote y,
/// mientras se pulsa, el círculo se hunde un poco. Con «Reducir movimiento» el
/// anillo y el visto solo se funden en 150 ms.
class _AccentSwatch extends StatefulWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AccentId accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AccentSwatch> createState() => _AccentSwatchState();
}

class _AccentSwatchState extends State<_AccentSwatch>
    with SingleTickerProviderStateMixin {
  /// 0 sin elegir, 1 elegido: manda el anillo y la opacidad del visto.
  late final AnimationController _ring = AnimationController(
    vsync: this,
    value: widget.selected ? 1 : 0,
    animationBehavior: AnimationBehavior.preserve,
  );
  final GlobalKey<SpringPulseState> _check = GlobalKey<SpringPulseState>();
  bool _pressed = false;

  @override
  void didUpdateWidget(_AccentSwatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) {
      return;
    }
    final motion = RegalosMotion.of(context);
    if (widget.selected) {
      _ring.animateTo(
        1,
        duration: motion.duration(RegalosSprings.snapDuration),
        curve: motion.curve(RegalosCurves.snap),
      );
      _check.currentState?.play(from: 0.6);
    } else {
      _ring.animateTo(
        0,
        duration: motion.duration(RegalosCurves.foldDuration),
        curve: motion.curve(RegalosCurves.fold),
      );
    }
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final p = widget.accent.palette;
    final name = widget.accent.label(AppLocalizations.of(context));
    // La muestra lleva el pastel tal cual en los dos temas (velado no se
    // distinguiría un color de otro) y su tinta encima.
    final fill = p.pastel;
    final ink = t.isDark ? t.text : p.tinta;
    final onFill = p.tinta;

    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: widget.selected,
      label: name,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (down) {
          if (_pressed != down) {
            setState(() => _pressed = down);
          }
        },
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        borderRadius: RegalosShape.chip,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              // Al pulsar se hunde en 80 ms y vuelve con `soft`.
              AnimatedScale(
                scale: _pressed && !reduce ? 0.94 : 1,
                duration: _pressed
                    ? const Duration(milliseconds: 80)
                    : RegalosSprings.softDuration,
                curve: _pressed ? Curves.linear : RegalosCurves.soft,
                child: AnimatedBuilder(
                  animation: _ring,
                  builder: (context, child) {
                    final r = _ring.value.clamp(0.0, 1.0);
                    // Con «Reducir movimiento» el anillo no crece: tiene su
                    // tamaño entero y solo cambia el alfa.
                    final grow = reduce ? 1.0 : r;
                    return DecoratedBox(
                      key: ValueKey<String>(
                        'swatch-ring-${widget.accent.name}',
                      ),
                      decoration: BoxDecoration(
                        color: fill,
                        shape: BoxShape.circle,
                        border: t.isDark
                            ? null
                            : Border.all(color: p.swatchBorder, width: 1.5),
                        boxShadow: r <= 0
                            ? null
                            : [
                                BoxShadow(
                                  color: t.bg.withValues(alpha: r),
                                  spreadRadius: 3 * grow,
                                ),
                                BoxShadow(
                                  color: ink.withValues(alpha: r),
                                  spreadRadius: 5 * grow,
                                ),
                              ],
                      ),
                      child: child,
                    );
                  },
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(
                      // El visto marca el elegido: no depende solo del anillo.
                      child: AnimatedBuilder(
                        animation: _ring,
                        builder: (context, child) => Opacity(
                          opacity: _ring.value.clamp(0.0, 1.0),
                          child: child,
                        ),
                        child: SpringPulse(
                          key: _check,
                          child: StrokeIcon(
                            AppIcons.check,
                            color: onFill,
                            strokeWidth: 2.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                textAlign: TextAlign.center,
                style: t.styles.caption.copyWith(
                  color: t.text,
                  height: 16 / 13,
                  fontWeight: widget.selected
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El selector de tema: un recuadro con el color de relleno que se desliza de
/// un segmento al otro con `snap` (cambio de forma, no un corte) y, a la vez,
/// el texto de cada segmento pasa de color. Con «Reducir movimiento» el
/// recuadro no viaja: cada segmento se funde en 150 ms.
class _ThemeModeSelector extends StatefulWidget {
  const _ThemeModeSelector({
    required this.selected,
    required this.groupLabel,
    required this.onSelected,
  });

  final ThemeMode selected;
  final String groupLabel;
  final ValueChanged<ThemeMode> onSelected;

  @override
  State<_ThemeModeSelector> createState() => _ThemeModeSelectorState();
}

class _ThemeModeSelectorState extends State<_ThemeModeSelector>
    with SingleTickerProviderStateMixin {
  static const List<ThemeMode> _modes = [
    ThemeMode.system,
    ThemeMode.light,
    ThemeMode.dark,
  ];

  /// Posición del recuadro en segmentos (0, 1 o 2); sin límites para dejar
  /// pasar el sobrepaso mínimo del muelle.
  late final AnimationController _pos = AnimationController.unbounded(
    vsync: this,
    value: _modes.indexOf(widget.selected).toDouble(),
    animationBehavior: AnimationBehavior.preserve,
  );

  /// De dónde viene y adónde va el último cambio (en segmentos). Con
  /// «Reducir movimiento» solo se funden esos dos: el del medio no parpadea
  /// al saltar de un extremo al otro.
  late double _from = _pos.value;
  late double _target = _pos.value;

  @override
  void didUpdateWidget(_ThemeModeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) {
      return;
    }
    final target = _modes.indexOf(widget.selected).toDouble();
    // La velocidad del recuadro que ya iba de camino se conserva: tocar otro
    // segmento a mitad de viaje no frena en seco.
    final velocity = _pos.velocity;
    _from = _pos.value;
    _target = target;
    _pos.stop();
    if (RegalosMotion.of(context).reduce) {
      _pos.value = _from;
      _pos.animateTo(
        target,
        duration: RegalosMotion.fade,
        curve: Curves.linear,
      );
    } else {
      _pos.animateWith(
        SpringSimulation(
          RegalosSprings.snap,
          _pos.value,
          target,
          velocity,
          snapToEnd: true,
        ),
      );
    }
  }

  /// Cuánto cubre el recuadro al segmento [i] (0 a 1). Con movimiento, lo
  /// cerca que pasa el recuadro; con «Reducir movimiento», el progreso del
  /// fundido: sube el destino, baja el origen y el resto no se toca.
  double _coverOf(int i, {required bool reduce}) {
    if (!reduce) {
      return (1 - (_pos.value - i).abs()).clamp(0.0, 1.0);
    }
    final span = _target - _from;
    if (span == 0) {
      return i == _target ? 1 : 0;
    }
    final t = ((_pos.value - _from) / span).clamp(0.0, 1.0);
    if (i == _target) {
      return t;
    }
    return i == _from ? 1 - t : 0;
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final labels = {
      ThemeMode.system: l10n.themeSystem,
      ThemeMode.light: l10n.themeLight,
      ThemeMode.dark: l10n.themeDark,
    };
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.groupLabel,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(color: t.controlBorder),
          borderRadius: RegalosShape.chip,
        ),
        child: Stack(
          children: [
            // El recuadro que se desliza, debajo de los textos. Con reducir
            // movimiento, un relleno por segmento que sube y baja de opacidad.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pos,
                builder: (context, _) {
                  final box = DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.fill,
                      borderRadius: BorderRadius.circular(
                        RegalosShape.repartoChipRadius,
                      ),
                    ),
                  );
                  if (!reduce) {
                    return FractionallySizedBox(
                      key: const ValueKey<String>('theme-box'),
                      widthFactor: 1 / _modes.length,
                      alignment: Alignment(
                        -1 + 2 * _pos.value / (_modes.length - 1),
                        0,
                      ),
                      child: box,
                    );
                  }
                  return Row(
                    children: [
                      for (var i = 0; i < _modes.length; i++)
                        Expanded(
                          child: Opacity(
                            key: ValueKey<String>('theme-fill-$i'),
                            opacity: _coverOf(i, reduce: true),
                            child: box,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            AnimatedBuilder(
              animation: _pos,
              builder: (context, _) => Row(
                children: [
                  for (var i = 0; i < _modes.length; i++)
                    Expanded(
                      child: _Segment(
                        label: labels[_modes[i]]!,
                        selected: _modes[i] == widget.selected,
                        // 1 con el recuadro encima, 0 lejos: el color del
                        // texto sigue al recuadro.
                        cover: _coverOf(i, reduce: reduce),
                        onTap: () => widget.onSelected(_modes[i]),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.cover,
    required this.onTap,
  });

  final String label;
  final bool selected;

  /// Cuánto cubre el recuadro deslizante a este segmento (0 a 1).
  final double cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RegalosShape.repartoChipRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.styles.label.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: Color.lerp(t.text, t.onFill, cover),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila de regalo y cuenta atrás con el acento y el tema actuales.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeName;
    final today = clock.now();
    final price = NumberFormat.currency(
      locale: locale,
      symbol: '€',
      decimalDigits: 2,
    ).format(49.99);

    // Próximos Reyes (6 de enero).
    var kings = DateTime.utc(today.year, 1, 6);
    final todayUtc = DateTime.utc(today.year, today.month, today.day);
    if (kings.isBefore(todayUtc)) kings = DateTime.utc(today.year + 1, 1, 6);
    final days = kings.difference(todayUtc).inDays;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: t.separator),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          GiftRow(
            name: l10n.previewGiftName,
            giverName: l10n.previewGiver,
            giverColorIndex: 0,
            price: price,
            status: GiftStatus.bought,
            bordered: false,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: CountdownCard(
              days: days,
              title: l10n.countdownDaysFor(days, l10n.previewOccasion),
              date: l10n.todayIs(today),
            ),
          ),
        ],
      ),
    );
  }
}
