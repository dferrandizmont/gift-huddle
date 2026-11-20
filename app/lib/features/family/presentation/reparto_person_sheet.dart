import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/stagger.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/spring_pulse.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../application/family_controller.dart';
import '../application/family_providers.dart';
import '../application/self_recipient_provider.dart';
import 'family_screen.dart' show OccasionGroup, occasionGroupsFor;
import 'reparto_grid.dart' show RepartoAvatar;
import 'self_tag.dart';

/// Clave de la casilla «Sale en el reparto» de la ficha (para las pruebas).
const Key kRepartoInRepartoKey = ValueKey<String>('repartoInReparto');

/// Clave de la casilla de una ocasión de la ficha (por clave del selector de
/// ocasión: el id de la ocasión o `birthdays`).
Key repartoOccasionBoxKey(String groupKey) =>
    ValueKey<String>('repartoOccasionBox:$groupKey');

/// Lo que lleva la hoja de una persona de Reparto, que se abre al tocar su
/// nombre: «Sale en el reparto» y «Le regaláis en» con una casilla por
/// ocasión. Cada casilla guarda en el momento (la rejilla de detrás cambia
/// mientras se mira) y nada se borra.
class RepartoPersonSheet extends ConsumerWidget {
  /// Crea el contenido de la hoja de [recipient].
  const RepartoPersonSheet({
    super.key,
    required this.recipient,
    required this.onClose,
    required this.onOpenList,
    required this.onDrag,
    required this.onDragEnd,
  });

  /// La persona al abrir la hoja (se relee de la lista, que puede cambiar).
  final Recipient recipient;

  /// Cierra la hoja; con `pop: false` solo la desliza hacia abajo.
  final Future<void> Function({bool pop}) onClose;

  /// Lleva a la lista completa de la persona.
  final VoidCallback onOpenList;

  /// Arrastrar el asa o el título.
  final ValueChanged<double> onDrag;

  /// Soltar el asa o el título.
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final view = ref.watch(familyViewProvider);
    final person = view.recipientsById[recipient.id] ?? recipient;
    final isSelf = ref.watch(selfRecipientIdProvider) == person.id;
    final groups = occasionGroupsFor(l10n, view.occasions, clock.now());
    final controller = ref.read(familyControllerProvider.notifier);
    final bottom = MediaQuery.paddingOf(context).bottom;

    Future<void> toggleGroup(OccasionGroup group) async {
      final skipped = group.ids.where(person.skipsOccasion).toSet();
      // Ninguna saltada: se saltan todas. Alguna o todas: se incluyen todas.
      final skip = skipped.isEmpty;
      for (final id in group.ids) {
        if (person.skipsOccasion(id) != skip) {
          await controller.setRecipientSkipOccasion(person.id, id, skip: skip);
        }
      }
    }

    // Las opciones entran escalonadas (momento de la hoja de Reparto): 40 ms
    // entre una y otra, desde que la hoja ya ha crecido un poco.
    return StaggerScope(
      delay: const Duration(milliseconds: 100),
      step: const Duration(milliseconds: 40),
      maxItems: 8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Se arrastra por el asa y el título.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
              onVerticalDragEnd: (d) =>
                  onDragEnd(d.velocity.pixelsPerSecond.dy),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.chipBorder,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(2),
                        ),
                      ),
                      child: const SizedBox(width: 36, height: 4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Semantics(
                    header: true,
                    child: Row(
                      children: [
                        RepartoAvatar(
                          name: person.name,
                          colorIndex: person.colorIndex,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          fit: isSelf ? FlexFit.loose : FlexFit.tight,
                          child: Text(
                            person.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.styles.rowTitle.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        // «Yo»: la persona dueña de este móvil.
                        if (isSelf) ...[
                          const SizedBox(width: 8),
                          const SelfTag(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(l10n.repartoPersonSheetSub, style: t.styles.meta),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StaggerItem(
                      index: 0,
                      dy: 8,
                      child: _OptionRow(
                        key: kRepartoInRepartoKey,
                        first: true,
                        state: person.inReparto ? _BoxState.on : _BoxState.off,
                        semantics: l10n.repartoPersonInReparto,
                        onTap: () => controller.setRecipientInReparto(
                          person.id,
                          !person.inReparto,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.repartoPersonInReparto,
                              style: t.styles.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.repartoPersonInRepartoHint,
                              style: t.styles.caption.copyWith(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                    StaggerItem(
                      index: 1,
                      dy: 8,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 4),
                        child: Text(
                          l10n.repartoPersonOccasions,
                          style: t.styles.caption.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: person.inReparto ? 1 : 0.5,
                      duration: RegalosMotion.of(context)
                          .duration(RegalosSprings.softDuration),
                      child: Column(
                        children: [
                          for (var i = 0; i < groups.length; i++)
                            StaggerItem(
                              index: 2 + i,
                              dy: 8,
                              child: _OptionRow(
                                key: repartoOccasionBoxKey(groups[i].key),
                                first: i == 0,
                                state: _groupState(person, groups[i]),
                                semantics: groups[i].label,
                                onTap: () => toggleGroup(groups[i]),
                                child: Row(
                                  children: [
                                    ExcludeSemantics(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: groups[i].theme.mark(
                                            dark: t.isDark,
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const SizedBox.square(
                                          dimension: 8,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        groups[i].label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.styles.body.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            StaggerItem(
              index: 2 + groups.length,
              dy: 8,
              child: Align(
                alignment: Alignment.center,
                child: TextButton(
                  style: TextButton.styleFrom(
                    shape: const RoundedRectangleBorder(
                      borderRadius: RegalosShape.button,
                    ),
                  ),
                  onPressed: () async {
                    await onClose(pop: false);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                    onOpenList();
                  },
                  child: Text(l10n.repartoSheetOpenList(person.name)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Marcada si no se salta ninguna ocasión del grupo; a medias si solo
  /// algunas (por ejemplo, unos cumpleaños sí y otros no); sin marcar si se
  /// saltan todas.
  static _BoxState _groupState(Recipient person, OccasionGroup group) {
    final skipped = group.ids.where(person.skipsOccasion).length;
    if (skipped == 0) {
      return _BoxState.on;
    }
    return skipped >= group.ids.length ? _BoxState.off : _BoxState.mixed;
  }
}

enum _BoxState { off, on, mixed }

/// Una fila de la ficha: casilla de radio 4 y su texto; se toca entera.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.first,
    required this.state,
    required this.semantics,
    required this.onTap,
    required this.child,
  });

  final bool first;
  final _BoxState state;
  final String semantics;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      label: semantics,
      checked: state == _BoxState.on,
      mixed: state == _BoxState.mixed,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.separator)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CheckBox(state: state),
                  const SizedBox(width: 12),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La casilla: 22 × 22, radio 4. Al marcarse cambia de color con el muelle
/// `snap`, rebota y el visto entra creciendo; con «Reducir movimiento», solo
/// se funde.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.state});

  final _BoxState state;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    final filled = state != _BoxState.off;
    final icon = state == _BoxState.mixed ? AppIcons.minus : AppIcons.check;
    return SpringPulse(
      trigger: state,
      from: 0.8,
      child: AnimatedContainer(
        duration: motion.duration(RegalosSprings.snapDuration),
        curve: motion.curve(RegalosCurves.snap),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: filled ? t.selection : Colors.transparent,
          borderRadius: RegalosShape.tiny,
          // Marcada, el borde en la tinta (3:1 como casilla); el recuadro
          // rellenado con el color de lo elegido.
          border: Border.all(color: filled ? t.ink : t.chipBorder, width: 1.5),
        ),
        child: AnimatedScale(
          scale: filled || motion.reduce ? 1 : 0.3,
          duration: motion.duration(RegalosSprings.bounceDuration),
          curve: motion.curve(RegalosCurves.bounce),
          child: AnimatedOpacity(
            opacity: filled ? 1 : 0,
            duration: motion.duration(const Duration(milliseconds: 150)),
            child: Center(
              child: StrokeIcon(icon, size: 14, color: t.ink, strokeWidth: 2.5),
            ),
          ),
        ),
      ),
    );
  }
}
