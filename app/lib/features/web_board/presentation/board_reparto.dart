import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/pointer_surface.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../family/presentation/family_screen.dart';
import '../../gifts/presentation/gift_editor_screen.dart';
import '../application/board_lanes.dart';
import 'board_page.dart';
import 'board_scope.dart';

/// Reparto en el tablero de la web de escritorio
/// (la guía de diseño de escritorio, «Reparto»): la rejilla
/// de siempre, alineada a la izquierda en el mismo margen que las demás
/// pantallas, con nombres de 220 y celdas de
/// `clamp((A − 2·margen − 220 − lateral − 40) / quienes, 120, 280)`.
///
/// Con 1600 o más de contenido suma una columna lateral con «Sin quién regala»
/// y los posibles duplicados, **justo detrás de la rejilla** (a 40 de ella):
/// mide 400 si el contenido pasa de 2200 y 340 si no. Lo que sobre queda a la
/// derecha, en el color de fondo. La columna aparece y desaparece con una
/// animación al cambiar el tamaño de la ventana.
class BoardRepartoScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const BoardRepartoScreen({super.key});

  /// Desde este ancho de contenido sale la columna lateral.
  static const double asideFrom = 1600;

  /// Con más de este ancho de contenido, la columna lateral mide
  /// [asideWide].
  static const double asideWideFrom = 2200;

  /// El ancho de la columna lateral hasta [asideWideFrom] de contenido.
  static const double asideWidth = 340;

  /// El ancho de la columna lateral por encima.
  static const double asideWide = 400;

  /// El hueco entre la rejilla y la columna lateral.
  static const double asideGap = 40;

  /// Lo que mide la columna lateral para [content] de ancho.
  static double asideWidthFor(double content) =>
      content > asideWideFrom ? asideWide : asideWidth;

  /// El ancho del área de la rejilla (con el margen izquierdo ya dentro) para
  /// [content] de ancho, [margin] de margen y [givers] columnas de quienes
  /// regalan: lo que pide la rejilla con celdas de 120 a 280.
  static double gridAreaFor(double content, double margin, int givers) {
    final n = givers < 1 ? 1 : givers;
    const gap = 3.0;
    // Lo que queda para las celdas, sin los márgenes, los nombres (220), los 16
    // de relleno de la rejilla por cada lado, la columna lateral y su hueco.
    final room =
        (content - 2 * margin - 220 - 16 - asideWidthFor(content) - asideGap) /
            n -
        gap;
    final cell = room < 120 ? 120.0 : (room > 280 ? 280.0 : room);
    return (margin - 16) + 32 + 220 + n * (cell + gap);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final margin = BoardScope.marginOf(context);
    final reduce = RegalosMotion.of(context).reduce;
    final givers = ref
        .watch(familyGridForOccasionProvider(kAllOccasionsKey))
        .givers
        .length;
    return BoardCoveredGuard(
      child: LayoutBuilder(
        builder: (context, box) {
          final content = box.maxWidth;
          final aside = content >= asideFrom;
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(end: aside ? 1 : 0),
            duration: reduce
                ? RegalosMotion.fade
                : const Duration(milliseconds: 280),
            curve: reduce ? Curves.linear : Curves.easeOutCubic,
            builder: (context, phase, _) {
              final side = asideWidthFor(content);
              final area = givers == 0
                  ? content
                  : gridAreaFor(content, margin, givers).clamp(0.0, content);
              final gridWidth = phase == 0
                  ? content
                  : content + (area - content) * phase;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: gridWidth,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: margin - 16,
                        right: phase > 0 ? 0 : margin - 16,
                      ),
                      child: FamilyScreen(board: true, showDuplicates: !aside),
                    ),
                  ),
                  if (phase > 0)
                    SizedBox(
                      width: (asideGap + side) * phase,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: AlignmentDirectional.centerStart,
                          minWidth: asideGap + side,
                          maxWidth: asideGap + side,
                          child: Opacity(
                            opacity: phase,
                            child: Padding(
                              padding: const EdgeInsets.only(left: asideGap),
                              child: _RepartoAside(margin: margin),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// La columna lateral de Reparto: lo que falta por repartir y lo que parece
/// repetido.
class _RepartoAside extends ConsumerWidget {
  const _RepartoAside({required this.margin});

  final double margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final full = ref.watch(familyFullViewProvider);
    final people = full.recipientsById;
    final loose = [
      for (final g in ref.watch(boardGiftsProvider))
        if (full.resolveGiver(g.giverId) == null &&
            g.status != GiftStatus.delivered)
          g,
    ];
    final duplicates = ref.watch(duplicatesProvider);
    return SafeArea(
      left: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(0, 24, margin, 24),
        children: [
          _Heading(title: l10n.boardRepartoNoGiver, count: loose.length),
          if (loose.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(l10n.boardRepartoNoGiverNone, style: t.styles.meta),
            )
          else
            for (final g in loose.take(30))
              _GiftRow(
                gift: g,
                name: people[g.recipientId]?.name ?? '',
                colorIndex: people[g.recipientId]?.colorIndex ?? 0,
              ),
          const SizedBox(height: 24),
          _Heading(
            title: l10n.boardRepartoDuplicates,
            count: duplicates.length,
          ),
          if (duplicates.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.boardRepartoDuplicatesNone,
                style: t.styles.meta,
              ),
            )
          else
            for (final pair in duplicates)
              _GiftRow(
                gift: pair.first,
                name: people[pair.recipientId]?.name ?? '',
                colorIndex: people[pair.recipientId]?.colorIndex ?? 0,
                note: pair.second.title,
              ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.styles.sectionTitle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$count', style: t.styles.meta),
        ],
      ),
    );
  }
}

/// Un regalo de la columna lateral: tocarlo lo abre en el editor.
class _GiftRow extends StatelessWidget {
  const _GiftRow({
    required this.gift,
    required this.name,
    required this.colorIndex,
    this.note,
  });

  final Gift gift;
  final String name;
  final int colorIndex;

  /// El título del otro regalo, en un posible duplicado.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final second = note == null ? name : '$name · $note';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: true,
        label: '${gift.title}, $second',
        excludeSemantics: true,
        onTap: () => openGiftEditor(context, gift: gift),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: RegalosShape.card,
          ),
          child: PointerSurface(
            strength: 1.6,
            child: Material(
              color: Colors.transparent,
              borderRadius: RegalosShape.card,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => openGiftEditor(context, gift: gift),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      PersonAvatar(
                        name: name,
                        colorIndex: colorIndex,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              gift.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.styles.label,
                            ),
                            Text(
                              second,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.styles.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
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
