import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/pane_selection.dart';
import '../../../core/motion/avatar_hero.dart';
import '../../../core/motion/rect_flight.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/count_text.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/pointer_surface.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_actions.dart';
import '../../family/application/family_providers.dart';
import '../../family/presentation/person_sheet.dart';
import '../../gifts/presentation/gift_editor_screen.dart';
import '../../gifts/presentation/gift_search.dart';
import '../../occasions/application/occasion_rows.dart';
import '../../web_device/presentation/web_status_strip.dart';
import '../application/board_lanes.dart';
import '../application/board_metrics.dart';
import 'board_occasion_strip.dart';

/// Dónde está la app, dicho para la barra lateral: qué fila va elegida.
String boardSelectionOf(Uri uri) {
  final segments = uri.pathSegments;
  if (segments.isEmpty) {
    return boardTodayId;
  }
  switch (segments.first) {
    case 'people':
      return segments.length >= 2 ? boardPersonId(segments[1]) : boardTodayId;
    case 'family':
      return 'family';
    case 'occasions':
      // El presupuesto es una entrada de la barra, aunque su ruta cuelgue de
      // `/occasions` (`/occasions/budget`, que también abren los enlaces
      // de siempre).
      return segments.length >= 2 && segments[1] == kBudgetRowId
          ? boardBudgetId
          : 'occasions';
    case 'settings':
      return 'settings';
  }
  return boardTodayId;
}

/// Las llaves de los avatares de la barra, por persona: de ellas sale el
/// vuelo a la cabecera, también al cambiar de persona con las flechas.
final boardAvatarKeysProvider = Provider<Map<String, GlobalKey>>(
  (ref) => <String, GlobalKey>{},
);

/// Deja anotado que el avatar de [personId] de la barra va a volar a la
/// cabecera de su lista.
void departBoardAvatar(WidgetRef ref, String personId) {
  final context = ref.read(boardAvatarKeysProvider)[personId]?.currentContext;
  final rect = context == null ? null : globalRectOf(context);
  if (rect != null) {
    ref
        .read(flightRegistryProvider)
        .depart(AvatarHero.flightKeyFor(personId), rect);
  }
}

/// El id de la fila «Hoy».
const String boardTodayId = 'today';

/// El id de la fila «Presupuesto».
const String boardBudgetId = 'budget';

/// El id de la fila de una persona.
String boardPersonId(String personId) => 'person:$personId';

/// Lo que dice a las filas que la barra está plegada a un raíl.
class _Compact extends InheritedWidget {
  const _Compact({required this.compact, required super.child});

  final bool compact;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Compact>()?.compact ?? false;

  @override
  bool updateShouldNotify(_Compact old) => compact != old.compact;
}

/// La barra lateral del tablero de la web de escritorio
/// (la guía de diseño de escritorio): las secciones (Hoy,
/// Reparto, Ocasiones, Presupuesto y Ajustes) y, debajo, las personas, como los proyectos
/// de Todoist. Arriba, «Buscar un regalo»; abajo, el estado de guardado.
///
/// Mide 264 (232 por debajo de 1600 de ventana) y se pliega a un raíl de 64 con
/// el botón de arriba; el ancho cambia con una animación. El recuadro de la
/// fila elegida viaja de una a otra (el mismo de las listas de dos paneles). Al
/// tocar una persona, su avatar vuela a la cabecera de su lista.
class BoardSidebar extends ConsumerStatefulWidget {
  /// Crea la barra.
  const BoardSidebar({
    super.key,
    required this.onSection,
    required this.onBudget,
  });

  /// Se llama con el índice de la pestaña (0 Personas y Hoy, 1 Reparto,
  /// 2 Ocasiones, 3 Ajustes) al tocar una sección.
  final ValueChanged<int> onSection;

  /// Se llama al elegir «Presupuesto».
  final VoidCallback onBudget;

  /// El ancho de la barra desplegada en una ventana ancha.
  static const double width = BoardMetrics.sidebarWide;

  /// Cuánto mide la barra para una ventana de [window] y plegada o no.
  static double widthFor(double window, {required bool collapsed}) =>
      collapsed ? BoardMetrics.sidebarRail : BoardMetrics.sidebarFor(window);

  @override
  ConsumerState<BoardSidebar> createState() => _BoardSidebarState();
}

class _BoardSidebarState extends ConsumerState<BoardSidebar> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _addPerson(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final people = ref.read(recipientsProvider);
    final result = await showPersonSheet(
      context,
      defaultColorIndex: people.length,
    );
    if (result != null && context.mounted) {
      await saveRecipient(ref, l10n, result);
    }
  }

  /// Abre el regalo elegido en la búsqueda: su persona y el editor.
  void _openGift(BuildContext context, Gift gift) {
    _query.clear();
    setState(() {});
    ref.read(boardGiftCursorProvider).set(gift.id);
    departBoardAvatar(ref, gift.recipientId);
    context.go('/people/${gift.recipientId}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        openGiftEditor(context, gift: gift);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final collapsed = ref.watch(boardSidebarCollapsedProvider);
    final window = MediaQuery.sizeOf(context).width;
    final target = BoardSidebar.widthFor(window, collapsed: collapsed);
    final people = ref.watch(recipientsProvider);
    final count = ref.watch(boardCountProvider);
    final router = GoRouter.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.navMainLabel,
      child: Material(
        color: t.sidebar,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: t.separator)),
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: target),
            duration: reduce
                ? RegalosMotion.fade
                : const Duration(milliseconds: 220),
            curve: reduce ? Curves.linear : Curves.easeOutCubic,
            builder: (context, width, child) {
              // Por debajo de la mitad del camino, las filas ya son las del
              // raíl; el contenido se recorta al ancho que lleva.
              final compact = width < 150;
              return SizedBox(
                width: width,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: AlignmentDirectional.topStart,
                    minWidth: compact ? BoardMetrics.sidebarRail : width,
                    maxWidth: compact ? BoardMetrics.sidebarRail : width,
                    child: _Compact(compact: compact, child: child!),
                  ),
                ),
              );
            },
            child: ListenableBuilder(
              listenable: router.routerDelegate,
              builder: (context, _) {
                final location = router.routerDelegate.currentConfiguration.uri;
                final selected = boardSelectionOf(location);
                final person = people
                    .where((p) => boardPersonId(p.id) == selected)
                    .firstOrNull;
                final colors = person == null
                    ? (fill: t.selection, ink: t.ink)
                    : boardColorsOf(t, personPalette(person.colorIndex));
                return Builder(
                  builder: (context) {
                    final compact = _Compact.of(context);
                    final searching = !compact && _query.text.trim().isNotEmpty;
                    return SafeArea(
                      right: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(
                            compact: compact,
                            collapsed: collapsed,
                            onToggle: () => ref
                                .read(boardSidebarCollapsedProvider.notifier)
                                .toggle(),
                          ),
                          _SearchField(
                            compact: compact,
                            controller: _query,
                            focusNode: _searchFocus,
                            onChanged: (_) => setState(() {}),
                            onExpand: () {
                              ref
                                  .read(boardSidebarCollapsedProvider.notifier)
                                  .toggle();
                              WidgetsBinding.instance.addPostFrameCallback(
                                (_) => _searchFocus.requestFocus(),
                              );
                            },
                            onSubmit: (gift) => _openGift(context, gift),
                            query: _query.text,
                          ),
                          Expanded(
                            child: searching
                                ? GiftSearchResults(
                                    query: _query.text,
                                    limit: 12,
                                    onOpen: (g) => _openGift(context, g),
                                  )
                                : ListView(
                                    padding: EdgeInsets.fromLTRB(
                                      compact ? 8 : 12,
                                      4,
                                      compact ? 8 : 12,
                                      8,
                                    ),
                                    children: [
                                      SelectionScope(
                                        selectedId: selected,
                                        fill: colors.fill,
                                        border: colors.ink,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _Item(
                                              id: boardTodayId,
                                              label: l10n.boardToday,
                                              icon: AppIcons.check,
                                              selected:
                                                  selected == boardTodayId,
                                              trailing: _Count(
                                                text:
                                                    '${count.total - count.bought}',
                                                selected:
                                                    selected == boardTodayId,
                                              ),
                                              onTap: () => widget.onSection(0),
                                            ),
                                            _Item(
                                              id: 'family',
                                              label: l10n.navFamily,
                                              icon: AppIcons.family,
                                              selected: selected == 'family',
                                              onTap: () => widget.onSection(1),
                                            ),
                                            _Item(
                                              id: 'occasions',
                                              label: l10n.navOccasions,
                                              icon: AppIcons.occasions,
                                              selected: selected == 'occasions',
                                              onTap: () => widget.onSection(2),
                                            ),
                                            _Item(
                                              id: boardBudgetId,
                                              label: l10n.budgetTitle,
                                              icon: AppIcons.budget,
                                              selected:
                                                  selected == boardBudgetId,
                                              onTap: () => widget.onBudget(),
                                            ),
                                            _Item(
                                              id: 'settings',
                                              label: l10n.navSettings,
                                              icon: AppIcons.settings,
                                              selected: selected == 'settings',
                                              onTap: () => widget.onSection(3),
                                            ),
                                            if (compact)
                                              const SizedBox(height: 12)
                                            else
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      12,
                                                      16,
                                                      12,
                                                      8,
                                                    ),
                                                child: Text(
                                                  l10n.navPeople,
                                                  style: t.styles.caption,
                                                ),
                                              ),
                                            for (final p in people)
                                              _PersonItem(
                                                personId: p.id,
                                                name: p.name,
                                                colorIndex: p.colorIndex,
                                                selected:
                                                    selected ==
                                                    boardPersonId(p.id),
                                                onTap: () {
                                                  if (selected !=
                                                      boardPersonId(p.id)) {
                                                    context.go(
                                                      '/people/${p.id}',
                                                    );
                                                  }
                                                },
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      _AddPerson(
                                        compact: compact,
                                        onTap: () => _addPerson(context),
                                      ),
                                    ],
                                  ),
                          ),
                          WebSidebarStatus(compact: compact),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// La cabecera de la barra: el nombre de la app y el botón de plegarla.
class _Header extends StatelessWidget {
  const _Header({
    required this.compact,
    required this.collapsed,
    required this.onToggle,
  });

  final bool compact;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final label = collapsed
        ? l10n.boardSidebarExpand
        : l10n.boardSidebarCollapse;
    final button = Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onToggle,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: PointerSurface(
          child: Material(
            color: Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: RegalosShape.card,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onToggle,
              child: SizedBox.square(
                dimension: 40,
                child: Center(
                  child: StrokeIcon(
                    AppIcons.sidebar,
                    size: 20,
                    color: t.textSecondary,
                    strokeWidth: 1.8,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 24, 12, compact ? 12 : 12, 4),
      child: compact
          ? button
          : Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.appTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.styles.countdownTitle,
                  ),
                ),
                button,
              ],
            ),
    );
  }
}

/// «Buscar un regalo»: un campo en la barra; en el raíl, solo la lupa (que
/// despliega la barra).
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.compact,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onExpand,
    required this.onSubmit,
    required this.query,
  });

  final bool compact;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onExpand;
  final ValueChanged<Gift> onSubmit;
  final String query;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Semantics(
          button: true,
          label: l10n.boardSearchHint,
          excludeSemantics: true,
          onTap: onExpand,
          child: Tooltip(
            message: l10n.boardSearchHint,
            excludeFromSemantics: true,
            child: PointerSurface(
              child: Material(
                color: Colors.transparent,
                shape: const RoundedRectangleBorder(
                  borderRadius: RegalosShape.card,
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onExpand,
                  child: SizedBox.square(
                    dimension: 40,
                    child: Center(
                      child: StrokeIcon(
                        AppIcons.search,
                        size: 20,
                        color: t.textSecondary,
                        strokeWidth: 1.8,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: GiftSearchField(
        key: const ValueKey<String>('board-sidebar-search'),
        dense: true,
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
      ),
    );
  }
}

/// Una sección de la barra.
class _Item extends StatelessWidget {
  const _Item({
    required this.id,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String id;
  final String label;
  final StrokeIconBuilder icon;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final compact = _Compact.of(context);
    final color = selected ? t.ink : t.text;
    return _Row(
      id: id,
      label: label,
      selected: selected,
      onTap: onTap,
      child: compact
          ? Center(
              child: StrokeIcon(icon, size: 20, color: color, strokeWidth: 1.8),
            )
          : Row(
              children: [
                StrokeIcon(icon, size: 20, color: color, strokeWidth: 1.8),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.styles.label.copyWith(color: color),
                  ),
                ),
                ?trailing,
              ],
            ),
    );
  }
}

/// El número de la derecha de una fila de la barra.
class _Count extends StatelessWidget {
  const _Count({required this.text, required this.selected});

  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Text(
      text,
      style: t.styles.caption.copyWith(color: selected ? t.ink : null),
    );
  }
}

/// Una persona de la barra: su avatar (que vuela a la cabecera de su lista),
/// el nombre y cuántos regalos lleva comprados (nada si aún no tiene ninguno).
class _PersonItem extends ConsumerStatefulWidget {
  const _PersonItem({
    required this.personId,
    required this.name,
    required this.colorIndex,
    required this.selected,
    required this.onTap,
  });

  final String personId;
  final String name;
  final int colorIndex;
  final bool selected;
  final VoidCallback onTap;

  @override
  ConsumerState<_PersonItem> createState() => _PersonItemState();
}

class _PersonItemState extends ConsumerState<_PersonItem> {
  late final GlobalKey _avatar = ref
      .read(boardAvatarKeysProvider)
      .putIfAbsent(widget.personId, GlobalKey.new);

  void _tap() {
    // El avatar sale de aquí: la cabecera de la lista lo recibe.
    if (!widget.selected) {
      departBoardAvatar(ref, widget.personId);
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final compact = _Compact.of(context);
    final colors = boardColorsOf(t, personPalette(widget.colorIndex));
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(boardPersonCountProvider(widget.personId));
    // Los deseos sin coger, como en Personas y en la cabecera de la lista
    // (mismas reglas de privacidad: los que no verías en tu móvil no cuentan).
    final wishes = ref.watch(freeWishCountsProvider).ofPerson(widget.personId);
    final meta = wishes > 0
        ? giftsAndWishesText(l10n, count.total, wishes)
        : null;
    final avatar = PersonAvatar(
      key: _avatar,
      name: widget.name,
      colorIndex: widget.colorIndex,
      size: 28,
    );
    return _Row(
      id: boardPersonId(widget.personId),
      label: meta == null ? widget.name : '${widget.name}. $meta',
      selected: widget.selected,
      onTap: _tap,
      child: compact
          ? Center(child: avatar)
          : Row(
              children: [
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.styles.label.copyWith(
                          color: widget.selected ? colors.ink : t.text,
                        ),
                      ),
                      if (meta != null)
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.styles.caption.copyWith(
                            color: widget.selected ? colors.ink : null,
                          ),
                        ),
                    ],
                  ),
                ),
                if (count.total > 0)
                  _Count(
                    text: '${count.bought}/${count.total}',
                    selected: widget.selected,
                  ),
              ],
            ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = _Compact.of(context);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: SelectionRow(
        id: id,
        child: RepaintBoundary(
          child: PointerSurface(
            child: Material(
              color: Colors.transparent,
              shape: const RoundedRectangleBorder(
                borderRadius: RegalosShape.card,
              ),
              clipBehavior: Clip.antiAlias,
              child: Tooltip(
                message: compact ? label : '',
                excludeFromSemantics: true,
                child: InkWell(
                  onTap: onTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 0 : 12,
                        vertical: 6,
                      ),
                      child: child,
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

class _AddPerson extends StatelessWidget {
  const _AddPerson({required this.compact, required this.onTap});

  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final icon = StrokeIcon(
      AppIcons.plus,
      size: 18,
      color: t.textSecondary,
      strokeWidth: 2,
    );
    return Semantics(
      button: true,
      label: l10n.personNew,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: compact ? l10n.personNew : '',
        excludeFromSemantics: true,
        child: PointerSurface(
          child: Material(
            color: Colors.transparent,
            shape: const RoundedRectangleBorder(
              borderRadius: RegalosShape.card,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: compact
                    ? Center(child: icon)
                    : Row(
                        children: [
                          icon,
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.personNew,
                              style: t.styles.meta.copyWith(
                                color: t.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
