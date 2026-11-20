import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/dates.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/accent_palette.dart';
import '../../../core/theme/occasion_theme.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/filter_pill.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tabler_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../application/family_controller.dart';
import '../application/family_providers.dart';
import '../application/gift_logic.dart';
import '../application/reparto_view_provider.dart';
import '../application/self_recipient_provider.dart';
import '../domain/next_occasion.dart';
import 'family_texts.dart';
import 'reparto_flight.dart';
import 'reparto_grid.dart';
import 'reparto_occasion_view.dart';
import 'reparto_sheet.dart';
import 'reparto_view_toggle.dart';
import 'secret_blocks.dart';

/// Valor del selector de ocasión que enseña los regalos de todas.
const String kAllOccasionsKey = 'all';

/// Valor del selector que reúne los cumpleaños de todas las personas.
const String kBirthdaysKey = 'birthdays';

/// Clave de la fila de chips del selector de ocasión (para las pruebas).
const Key kOccasionChipsKey = ValueKey<String>('occasionChips');

/// Una opción del selector de ocasión de Reparto: una ocasión o el conjunto
/// de los cumpleaños.
class OccasionGroup {
  /// Crea la opción.
  const OccasionGroup({
    required this.key,
    required this.label,
    required this.ids,
    required this.theme,
    required this.occasion,
  });

  /// Valor del selector: el id de la ocasión, o [kBirthdaysKey].
  final String key;

  /// Texto del chip.
  final String label;

  /// Ids de las ocasiones que reúne.
  final Set<String> ids;

  /// Su tema, para el color de sus puntos.
  final OccasionTheme theme;

  /// La ocasión, si es una sola; `null` en los cumpleaños.
  final Occasion? occasion;
}

/// Las opciones del selector de Reparto por orden de próxima fecha: cada
/// ocasión y, en el lugar del primer cumpleaños, todos los cumpleaños juntos.
List<OccasionGroup> occasionGroupsFor(
  AppLocalizations l10n,
  Iterable<Occasion> occasions,
  DateTime now,
) {
  final groups = <OccasionGroup>[];
  final birthdayIds = <String>{};
  var birthdayIndex = -1;
  for (final o in occasionsByNextDate(occasions, now)) {
    if (o.kind == OccasionKind.birthday) {
      birthdayIds.add(o.id);
      if (birthdayIndex < 0) {
        birthdayIndex = groups.length;
        groups.add(
          OccasionGroup(
            key: kBirthdaysKey,
            label: l10n.familyChipBirthdays,
            ids: birthdayIds,
            theme: OccasionTheme.birthday,
            occasion: null,
          ),
        );
      }
    } else {
      groups.add(
        OccasionGroup(
          key: o.id,
          label: occasionTitle(l10n, o),
          ids: {o.id},
          theme: OccasionTheme.forOccasion(o),
          occasion: o,
        ),
      );
    }
  }
  return groups;
}

/// La opción del selector a la que pertenece [occasion].
String occasionGroupKey(Occasion occasion) =>
    occasion.kind == OccasionKind.birthday ? kBirthdaysKey : occasion.id;

/// Pantalla Reparto: la rejilla de quién regala qué a cada persona, para una
/// ocasión cada vez.
///
/// Arriba, un selector de ocasión (Todas, Tió, Papá Noel, Reyes,
/// cumpleaños…); por defecto sale «Todas», y con una ocasión elegida el subtítulo
/// dice para cuándo es («Para Reyes, 6 de enero»). Las filas son quienes
/// reciben y las columnas, quienes regalan, con la cabecera fija. La rejilla
/// solo se desplaza en vertical: a lo ancho siempre cabe, con celdas más
/// estrechas (modo compacto) desde cinco columnas. Al tocar una celda crece
/// una hoja con sus regalos, donde se cambia quién regala cada uno.
///
/// En una ventana ancha (tablet, desde 600 dp) sigue siendo un solo panel:
/// la rejilla se centra con celdas más grandes, los chips se centran con
/// ella y las hojas miden 560, centradas en el área de contenido. Desde 840
/// dp (escritorio) la rejilla crece hasta celdas de 120 × 56 y 1400 de ancho.
///
/// Al abrir la pantalla, al cambiar el filtro de ocasión y al volver de la
/// lista por ocasión, nombres y celdas entran en onda (`RepartoRowIntro`,
/// `RepartoCellIntro`); las celdas con regalos aterrizan con un rebote leve.
class FamilyScreen extends ConsumerStatefulWidget {
  const FamilyScreen({
    super.key,
    this.board = false,
    this.showDuplicates = true,
  });

  /// Si es Reparto del tablero de la web de escritorio
  /// (la guía de diseño de escritorio, «Reparto»): la
  /// rejilla va alineada a la izquierda y llena el ancho, con nombres de 220 y
  /// celdas de `clamp(…, 120, 280)`.
  final bool board;

  /// Si el aviso de posibles duplicados sale encima de la rejilla (en el
  /// tablero ancho va en la columna lateral).
  final bool showDuplicates;

  @override
  ConsumerState<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends ConsumerState<FamilyScreen> {
  /// Lo que eligió la persona en el selector de la rejilla; `null` mientras no
  /// ha elegido (sale «Todas»).
  String? _chosen;

  /// La pestaña de la vista por ocasión; `null` mientras no ha elegido (sale
  /// la más cercana).
  String? _occasionTab;

  /// Si la persona tocó una pestaña de la vista por ocasión desde la última
  /// vez que cambió de vista. Solo entonces la rejilla toma esa ocasión al
  /// volver: una pestaña que salió sola (la más cercana) no es una elección y
  /// la rejilla sigue donde estaba («Todas» la primera vez).
  bool _tabPicked = false;

  /// Las celdas que rebotan cuando un regalo cambia de quien regala.
  final RepartoBumps _bumps = RepartoBumps();

  /// El escenario de la vista que se ve (anclas del vuelo entre vistas).
  RepartoStage _stage = RepartoStage();

  /// Mientras los regalos viajan de una vista a otra no se admite otro cambio.
  bool _busy = false;

  /// Si la vista que acaba de llegar debe entrar escalonada.
  bool _entering = false;
  OverlayEntry? _flight;

  /// El cuerpo de la pantalla, para saber qué regalos se ven.
  final GlobalKey _bodyKey = GlobalKey(debugLabel: 'repartoBody');

  @override
  void initState() {
    super.initState();
    // Al abrir la pantalla, la vista entra escalonada una sola vez: el aviso
    // se retira tras el primer fotograma y lo que llegue después (datos de
    // sincronización, filas nuevas) aparece sin entrada.
    _entering = true;
    _clearEntering();
  }

  @override
  void dispose() {
    _flight
      ?..remove()
      ..dispose();
    super.dispose();
  }

  /// La opción del selector que se ve en la rejilla: la que eligió la persona
  /// si todavía existe y, si no (la primera vez, o si esa ocasión ya no está),
  /// «Todas». La ocasión más cercana solo manda en la lista por ocasión.
  String _selectedKey(List<OccasionGroup> groups) {
    final chosen = _chosen;
    return chosen != null &&
            (chosen == kAllOccasionsKey || groups.any((g) => g.key == chosen))
        ? chosen
        : kAllOccasionsKey;
  }

  /// La ocasión que se ve en la vista por ocasión.
  Occasion? _selectedOccasion(List<Occasion> ordered, NextOccasion? next) {
    if (ordered.isEmpty) {
      return null;
    }
    final chosen = ordered.where((o) => o.id == _occasionTab).firstOrNull;
    if (chosen != null) {
      return chosen;
    }
    return ordered.where((o) => o.id == next?.occasion.id).firstOrNull ??
        ordered.first;
  }

  /// Cambia de vista, con los regalos viajando de su celda a su fila (y al
  /// revés). Mantiene los dos filtros de acuerdo: la vista por ocasión abre la
  /// ocasión filtrada en la rejilla y, a la vuelta, la rejilla queda filtrada
  /// por la ocasión que se estaba viendo.
  void _setView(RepartoView to) {
    final from = ref.read(repartoViewProvider);
    if (_busy || from == to) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    final now = clock.now();
    final view = ref.read(familyViewProvider);
    final occasions = ref.read(occasionsProvider);
    final next = ref.read(nextOccasionProvider);
    final groups = occasionGroupsFor(l10n, occasions, now);
    final ordered = occasionsByNextDate(occasions, now);

    // 1. Los dos filtros se ponen de acuerdo.
    if (to == RepartoView.occasion) {
      // La rejilla en una ocasión concreta: la lista abre esa pestaña. En
      // «Todas» no hay nada que copiar y la pestaña se queda como estaba (la
      // más cercana si nunca se eligió).
      final key = _selectedKey(groups);
      if (key != kAllOccasionsKey) {
        final group = groups.firstWhere((g) => g.key == key);
        _occasionTab =
            group.occasion?.id ??
            ordered.where((o) => group.ids.contains(o.id)).firstOrNull?.id;
      }
    } else if (_tabPicked) {
      // La persona eligió una pestaña a mano: la rejilla se filtra por ella.
      final tab = _selectedOccasion(ordered, next);
      if (tab != null) {
        _chosen = occasionGroupKey(tab);
      }
    }
    _tabPicked = false;
    final target = _selectedOccasion(ordered, next);
    final gifts = target == null
        ? const <Gift>[]
        : [
            for (final g in view.gifts)
              if (g.occasionId == target.id) g,
          ];

    // 2. Con «Reducir movimiento» no vuela nada: las vistas se funden.
    final toOccasion = to == RepartoView.occasion;
    final clip = _bodyRect();
    final recipients = view.recipients;

    // Origen de los nombres y avatares: los que se ven ahora.
    String anchorOf(Recipient r, bool avatar) =>
        avatar ? repartoAvatarAnchor(r.id) : repartoNameAnchor(r.id);
    final personSources = <String, Rect>{};
    if (!reduce) {
      for (final r in recipients) {
        for (final avatar in const [true, false]) {
          final anchor = anchorOf(r, avatar);
          final rect = _stage.rect(anchor);
          if (rect != null && clip != null && rect.overlaps(clip)) {
            personSources[anchor] = rect;
          }
        }
      }
    }
    if (reduce || (gifts.isEmpty && personSources.isEmpty)) {
      _stage = RepartoStage();
      _entering = !reduce;
      ref.read(repartoViewProvider.notifier).set(to);
      setState(() {});
      if (!reduce) {
        _clearEntering();
      }
      return;
    }

    // 3. Origen: la celda (o la fila) de cada regalo que se ve ahora.
    String? gridAnchor(Gift g) {
      final giverId = view.repartoGiverId(g);
      if (giverId == null) return null;
      return giverId == FamilyGrid.unassignedGiverId
          ? repartoUnassignedAnchor(g.recipientId)
          : repartoCellAnchor(g.recipientId, giverId);
    }

    final sources = <Gift, Rect>{};
    for (final g in gifts) {
      final anchor = toOccasion ? gridAnchor(g) : repartoGiftAnchor(g.id);
      final rect = anchor == null ? null : _stage.rect(anchor);
      if (rect != null && clip != null && rect.overlaps(clip)) {
        sources[g] = rect;
      }
    }
    String? destAnchor(Gift g) =>
        toOccasion ? repartoGiftAnchor(g.id) : gridAnchor(g);

    // 4. La vista nueva, con los destinos ocultos hasta que llegue lo suyo:
    // los regalos, y los nombres y avatares de quienes reciben.
    final giftDests = <String>{for (final g in gifts) ?destAnchor(g)};
    final personAnchors = <String>[
      for (final r in recipients)
        for (final avatar in const [true, false]) anchorOf(r, avatar),
    ];
    // Bajo el nombre de la rejilla hay líneas que no viajan («Sin Navidad»,
    // «1 sin quién»): esperan ocultas a su nombre y se funden cuando llega,
    // para que no se vea ninguna parte de la fila quieta.
    // La etiqueta «Yo» tampoco viaja, ni a la rejilla ni a la lista: espera
    // igual a su nombre y se funde con él.
    final selfId = ref.read(selfRecipientIdProvider);
    final extrasByName = <String, List<String>>{
      for (final r in recipients)
        if (!toOccasion || r.id == selfId)
          repartoNameAnchor(r.id): [
            if (r.id == selfId) repartoSelfAnchor(r.id),
            if (!toOccasion) ...[
              repartoSkipAnchor(r.id),
              if (!giftDests.contains(repartoUnassignedAnchor(r.id)))
                repartoUnassignedAnchor(r.id),
            ],
          ],
    };
    final incoming = RepartoStage(
      hidden: {
        ...giftDests,
        ...personAnchors,
        for (final extras in extrasByName.values) ...extras,
      },
    );
    _stage = incoming;
    _busy = true;
    _entering = true;
    ref.read(repartoViewProvider.notifier).set(to);
    setState(() {});

    // 5. En el primer fotograma de la vista nueva se leen los destinos y
    // salen los vuelos.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final newClip = _bodyRect() ?? clip!;
      final flyers = <RepartoFlyer>[];
      final need = <String, int>{};
      for (final e in sources.entries) {
        final g = e.key;
        final anchor = destAnchor(g);
        final dest = anchor == null ? null : incoming.rect(anchor);
        if (anchor == null || dest == null || !dest.overlaps(newClip)) {
          continue;
        }
        final person = view.recipientsById[g.recipientId];
        flyers.add(
          RepartoFlyer(
            giftId: g.id,
            landId: anchor,
            from: e.value,
            to: dest,
            fill: person == null
                ? t.surface
                : repartoPersonColors(t, person.colorIndex).fill,
            title: g.title,
          ),
        );
        need[anchor] = (need[anchor] ?? 0) + 1;
      }
      // Los nombres y avatares viajan de su fila a su tarjeta (o al revés),
      // cambiando de tamaño y de estilo por el camino.
      final fromStyle = toOccasion
          ? repartoGridNameStyle(t)
          : repartoCardNameStyle(t);
      final toStyle = toOccasion
          ? repartoCardNameStyle(t)
          : repartoGridNameStyle(t);
      final people = <RepartoPersonFlyer>[];
      final flown = <String>{};
      var order = 0;
      for (final r in recipients) {
        var any = false;
        for (final avatar in const [true, false]) {
          final anchor = anchorOf(r, avatar);
          final from = personSources[anchor];
          final dest = incoming.rect(anchor);
          if (from == null || dest == null || !dest.overlaps(newClip)) {
            continue;
          }
          people.add(
            RepartoPersonFlyer(
              landId: anchor,
              order: order,
              from: from,
              to: dest,
              name: r.name,
              colorIndex: r.colorIndex,
              avatar: avatar,
              fromStyle: fromStyle,
              toStyle: toStyle,
            ),
          );
          flown.add(anchor);
          any = true;
        }
        if (any) {
          order++;
        }
      }
      // Lo que no recibe nada (su origen no se ve, o no tiene destino) se
      // funde en su sitio en vez de aparecer de golpe.
      for (final anchor in giftDests) {
        if (!need.containsKey(anchor)) {
          incoming.reveal(anchor, fade: true);
        }
      }
      for (final anchor in personAnchors) {
        if (!flown.contains(anchor)) {
          incoming.reveal(anchor, fade: true);
          for (final extra in extrasByName[anchor] ?? const <String>[]) {
            incoming.reveal(extra, fade: true);
          }
        }
      }
      if (flyers.isEmpty && people.isEmpty) {
        _busy = false;
        _clearEntering();
        return;
      }
      final landed = <String, int>{};
      // El vuelo vibra una sola vez, cuando aterriza el primero, aunque
      // aterricen diez.
      final haptics = ref.read(hapticsProvider);
      var vibrated = false;
      void landingHaptic() {
        if (!vibrated) {
          vibrated = true;
          haptics.light();
        }
      }

      _flight = startRepartoFlight(
        context,
        flyers: flyers,
        people: people,
        toOccasion: toOccasion,
        clip: newClip,
        onLanded: (f) {
          landingHaptic();
          final n = (landed[f.landId] ?? 0) + 1;
          landed[f.landId] = n;
          if (n >= (need[f.landId] ?? 1)) {
            incoming.land(f.landId);
          }
        },
        onPersonLanded: (f) {
          landingHaptic();
          incoming.land(f.landId);
          for (final extra in extrasByName[f.landId] ?? const <String>[]) {
            incoming.reveal(extra, fade: true);
          }
        },
        onDone: () {
          _flight = null;
          incoming.hidden.value = const <String>{};
          if (mounted) {
            setState(() {
              _busy = false;
              _entering = false;
            });
          }
        },
      );
    });
  }

  /// Quita el aviso de entrada escalonada tras el primer fotograma.
  void _clearEntering() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _entering = false);
      }
    });
  }

  /// El rectángulo del cuerpo en pantalla.
  Rect? _bodyRect() {
    final box = _bodyKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mode = ref.watch(repartoViewProvider);
    final view = ref.watch(familyViewProvider);
    final occasions = ref.watch(occasionsProvider);
    final next = ref.watch(nextOccasionProvider);
    final now = clock.now();

    final groups = occasionGroupsFor(l10n, occasions, now);
    final selectedKey = _selectedKey(groups);
    final group = selectedKey == kAllOccasionsKey
        ? null
        : groups.firstWhere((g) => g.key == selectedKey);

    // Lo que cuenta en Reparto: sin las personas que no salen y sin los
    // regalos de las ocasiones que cada una se salta.
    final shown = ref.watch(repartoFamilyViewProvider(selectedKey));
    final grid = ref.watch(familyGridForOccasionProvider(selectedKey));
    // Los posibles duplicados cuentan entre ocasiones (la misma cosa en
    // Papá Noel y en Reyes es justo lo que se quiere ver); en la rejilla solo
    // se marcan las celdas de los regalos que se están viendo.
    final duplicates = ref.watch(duplicatesProvider);
    final shownIds = {for (final g in shown.gifts) g.id};
    final duplicateCells = <String>{
      for (final pair in duplicates)
        for (final g in [pair.first, pair.second])
          if (shownIds.contains(g.id))
            if (shown.repartoGiverId(g) case final id?)
              '$id|${pair.recipientId}',
    };

    // Las ocasiones de los regalos de cada celda, solo en «Todas»: no se
    // pintan (las celdas son pequeñas) pero las lee el lector de pantalla.
    final marks = group == null
        ? {
            for (final e in _cellOccasions(view, groups).entries)
              e.key: [for (final g in e.value) g.label],
          }
        : const <String, List<String>>{};
    final stats = _cellStats(shown, grid);

    final subtitle = mode == RepartoView.occasion
        ? l10n.repartoViewOccasion
        : group == null
        ? l10n.familyForAll
        : (group.occasion == null
              ? l10n.familyForBirthdays
              : l10n.familyForOccasion(
                  group.label,
                  _dateText(group.occasion!, now, l10n.localeName),
                ));

    final ordered = occasionsByNextDate(occasions, now);
    final tab = _selectedOccasion(ordered, next);
    // Con todas las personas fuera del reparto aún se ve el bloque para
    // volver a incluirlas.
    final empty =
        (grid.recipients.isEmpty && grid.outsideReparto.isEmpty) ||
        grid.givers.isEmpty;
    final excluded = {for (final r in grid.excludedRecipients) r.id};
    final skipLabels = group == null
        ? _skipLabels(l10n, view, grid.recipients)
        : const <String, String>{};
    final excludedText = group == null
        ? ''
        : l10n.familyExcludedStrip(group.label);
    final reduce = RegalosMotion.of(context).reduce;
    final stage = _stage;
    // Desde 600 dp (con raíl). En el móvil, también tumbado, nada cambia.
    final wide = WindowClass.of(context).usesRail;

    final Widget body;
    if (empty) {
      body = EmptyState(
        icon: AppIcons.family,
        title: l10n.emptyFamilyTitle,
        message: l10n.emptyFamilyMessage,
      );
    } else {
      final Widget current = mode == RepartoView.grid
          ? Column(
              key: const ValueKey<RepartoView>(RepartoView.grid),
              children: [
                if (groups.isNotEmpty)
                  RepartoBlock(
                    index: 0,
                    // En escritorio los filtros empiezan donde empieza la
                    // rejilla (misma columna), no centrados en la ventana.
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final column = _alignedColumn(
                          context,
                          constraints.maxWidth,
                          grid: true,
                          givers: grid.givers.length,
                        );
                        final chips = _OccasionChips(
                          groups: groups,
                          selectedKey: selectedKey,
                          centered: wide && column == null && !widget.board,
                          fill: column != null || widget.board,
                          onSelected: (key) => setState(() => _chosen = key),
                        );
                        // Con margen y no con `ContentWidth`: una fila de
                        // chips que se desplaza se encogería a lo que miden.
                        return column == null
                            ? chips
                            : Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: math.max(
                                    0,
                                    (constraints.maxWidth - column) / 2,
                                  ),
                                ),
                                child: chips,
                              );
                      },
                    ),
                  ),
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      if (duplicates.isNotEmpty && widget.showDuplicates)
                        SliverToBoxAdapter(
                          child: RepartoBlock(
                            index: 1,
                            // El aviso no se estira de lado a lado.
                            child: LayoutBuilder(
                              builder: (context, constraints) => ContentWidth(
                                // En escritorio, en la columna de la rejilla.
                                maxWidth:
                                    _alignedColumn(
                                      context,
                                      constraints.maxWidth,
                                      grid: true,
                                      givers: grid.givers.length,
                                    ) ??
                                    (wide && !widget.board
                                        ? RegalosLayout.listColumn
                                        : double.infinity),
                                child: _DuplicateBanner(
                                  pairs: duplicates,
                                  view: view,
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 10)),
                      RepartoGrid(
                        recipients: grid.recipients,
                        givers: grid.givers,
                        stats: stats,
                        duplicateCells: duplicateCells,
                        marks: marks,
                        bumps: _bumps,
                        stage: stage,
                        filterKey: selectedKey,
                        selfId: ref.watch(selfRecipientIdProvider),
                        excluded: excluded,
                        secret: ref.watch(lockedPeopleProvider),
                        skipLabels: skipLabels,
                        excludedText: excludedText,
                        outside: grid.outsideReparto,
                        onOpenPerson: _openPerson,
                        onInclude: (r) => ref
                            .read(familyControllerProvider.notifier)
                            .setRecipientInReparto(r.id, true),
                        onOpenCell: (recipient, giver, from, fromColor) =>
                            _openCell(
                              recipient,
                              giver,
                              from,
                              fromColor,
                              stats,
                              group?.occasion,
                            ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                ),
              ],
            )
          : RepartoOccasionView(
              key: const ValueKey<RepartoView>(RepartoView.occasion),
              occasions: ordered,
              selectedId: tab?.id ?? '',
              onSelect: (id) => setState(() {
                _occasionTab = id;
                _tabPicked = true;
              }),
              stage: stage,
              onOpenPerson: _openPerson,
            );
      body = KeyedSubtree(
        key: _bodyKey,
        child: RepartoEntrance(
          active: _entering,
          child: AnimatedSwitcher(
            // La vista que se va se funde y se encoge a 0,985 en 200 ms; la
            // que llega ya está debajo y sus bloques entran escalonados.
            duration: reduce
                ? RegalosMotion.fade
                : const Duration(milliseconds: 200),
            switchInCurve: Curves.fastOutSlowIn,
            switchOutCurve: Curves.fastOutSlowIn,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              children: [?currentChild, ...previousChildren],
            ),
            transitionBuilder: (child, animation) {
              final incoming = child.key == ValueKey<RepartoView>(mode);
              if (reduce) {
                return FadeTransition(opacity: animation, child: child);
              }
              // La misma forma de árbol para la que llega y la que se va: al
              // cambiar, `AnimatedSwitcher` vuelve a pedir la transición de
              // la vista saliente y, si su forma cambiara, la desmontaría y
              // la montaría de nuevo (pierde el desplazamiento y repite su
              // entrada escalonada justo cuando despegan los vuelos).
              return IgnorePointer(
                ignoring: !incoming,
                child: FadeTransition(
                  opacity: incoming ? kAlwaysCompleteAnimation : animation,
                  child: ScaleTransition(
                    scale: incoming
                        ? kAlwaysCompleteAnimation
                        : Tween<double>(
                            begin: 0.985,
                            end: 1,
                          ).animate(animation),
                    child: child,
                  ),
                ),
              );
            },
            child: current,
          ),
        ),
      );
    }

    final scaffold = Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // En el tablero, la cabecera empieza a la misma altura que la de
            // las demás pantallas (24 desde arriba).
            if (widget.board) const SizedBox(height: 16),
            // En escritorio, título, subtítulo y conmutador van en la misma
            // columna que el contenido de la vista (la rejilla o las
            // tarjetas), alineados con ella.
            LayoutBuilder(
              builder: (context, constraints) {
                final column = widget.board
                    ? null
                    : empty
                    ? (WindowClass.of(context).usesTwoPanes
                          ? RepartoLayout.desktopMaxWidth
                          : null)
                    : _alignedColumn(
                        context,
                        constraints.maxWidth,
                        grid: mode == RepartoView.grid,
                        givers: grid.givers.length,
                      );
                final header = ScreenHeader(
                  title: l10n.navFamily,
                  subtitle: subtitle,
                  actions: [
                    if (!empty)
                      RepartoViewToggle(view: mode, onChanged: _setView),
                  ],
                );
                return column == null
                    ? header
                    : ContentWidth(maxWidth: column, child: header);
              },
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
    return widget.board ? RepartoBoardMode(child: scaffold) : scaffold;
  }

  /// En escritorio (dos paneles), el ancho de la columna donde empieza y acaba
  /// el contenido de la vista, con los 16 de margen de la cabecera y los
  /// filtros: en la rejilla, la que ocupa la rejilla (nombres y celdas, como
  /// mucho 1400); en la vista por ocasión, la de sus tarjetas. `null` si no
  /// hay dos paneles: ahí todo queda como siempre.
  double? _alignedColumn(
    BuildContext context,
    double available, {
    required bool grid,
    required int givers,
  }) {
    if (widget.board || !WindowClass.of(context).usesTwoPanes) {
      return null;
    }
    if (!grid) {
      return RepartoOccasionView.columnMaxOf(context);
    }
    final layout = RepartoLayout(
      width: available,
      columns: givers,
      scaler: MediaQuery.textScalerOf(context),
      wide: true,
      desktop: true,
    );
    return available - 2 * layout.pad + 32;
  }

  /// Abre la ficha de una persona (la hoja sube desde su nombre, [from]).
  void _openPerson(Recipient recipient, Rect from) {
    showRepartoPersonSheet(
      context,
      from: from,
      recipient: recipient,
      onOpenList: () => context.push(
        Uri(
          path: '/people/${recipient.id}',
          queryParameters: {'from': 'family'},
        ).toString(),
      ),
    );
  }

  /// «Sin Navidad, Reyes»: bajo el nombre de quien se salta alguna ocasión,
  /// cuando se ven todas.
  static Map<String, String> _skipLabels(
    AppLocalizations l10n,
    FamilyView view,
    List<Recipient> recipients,
  ) {
    final labels = <String, String>{};
    for (final r in recipients) {
      final names = [
        for (final o in view.occasions)
          if (!o.archived && r.skipsOccasion(o.id))
            occasionTitle(
              l10n,
              o,
              personName: view.recipientsById[o.recipientId]?.name,
            ),
      ];
      if (names.isNotEmpty) {
        labels[r.id] = l10n.familySkipsLabel(names.join(', '));
      }
    }
    return labels;
  }

  /// Abre la hoja de una celda; [giver] nulo es la de los regalos sin quién
  /// regala de la persona.
  void _openCell(
    Recipient recipient,
    Giver? giver,
    Rect from,
    Color fromColor,
    Map<String, RepartoCellStats> stats,
    Occasion? single,
  ) {
    final cell = stats[repartoCellKey(recipient.id, giver?.id)];
    final empty = giver != null && (cell?.count ?? 0) == 0;
    // Una celda vacía enseña los regalos de la persona que aún no tienen
    // quién los regale, para darlos desde ahí.
    final ids = empty
        ? (stats[repartoCellKey(recipient.id, null)]?.ids ?? const <String>[])
        : (cell?.ids ?? const <String>[]);
    showRepartoSheet(
      context,
      from: from,
      fromColor: fromColor,
      recipient: recipient,
      giver: giver,
      giftIds: ids,
      empty: empty,
      occasionId: single?.id,
      bumps: _bumps,
      onOpenList: () => context.push(
        Uri(
          path: '/people/${recipient.id}',
          queryParameters: {
            'from': 'family',
            'giver': giver?.id ?? '',
            if (single != null) 'occasion': single.id,
          },
        ).toString(),
      ),
    );
  }

  /// Los datos de cada celda (`persona|quien regala`; sin quien regala, el
  /// segundo trozo va vacío).
  static Map<String, RepartoCellStats> _cellStats(
    FamilyView shown,
    FamilyGrid grid,
  ) {
    final lists = <String, List<Gift>>{};
    for (final gift in shown.gifts) {
      final row = shown.repartoGiverId(gift);
      if (row == null) continue;
      lists
          .putIfAbsent(repartoCellKey(gift.recipientId, row), () => <Gift>[])
          .add(gift);
    }
    return {
      for (final e in lists.entries)
        e.key: RepartoCellStats(
          count: e.value.length,
          bought: e.value.where((g) => g.status.isBoughtOrLater).length,
          cents: _centsOf(e.key, grid),
          ids: [for (final g in e.value) g.id],
        ),
    };
  }

  static int _centsOf(String key, FamilyGrid grid) {
    final cut = key.indexOf('|');
    return grid.cells[key.substring(0, cut)]?[key.substring(cut + 1)]?.cents ??
        0;
  }

  static String _dateText(Occasion occasion, DateTime now, String locale) {
    final d = occasionDayMonth(occasion, now);
    return longDayMonth(d.month, d.day, locale);
  }

  /// Para cada celda (`persona|quien regala`), las opciones del selector de las que
  /// tiene regalos, por orden del selector.
  static Map<String, List<OccasionGroup>> _cellOccasions(
    FamilyView view,
    List<OccasionGroup> groups,
  ) {
    final byOccasion = <String, OccasionGroup>{
      for (final g in groups)
        for (final id in g.ids) id: g,
    };
    final cells = <String, Set<OccasionGroup>>{};
    for (final gift in view.gifts) {
      final group = byOccasion[gift.occasionId];
      final row = view.repartoGiverId(gift);
      if (group == null || row == null) {
        continue;
      }
      cells
          .putIfAbsent(repartoCellKey(gift.recipientId, row), () => {})
          .add(group);
    }
    return {
      for (final entry in cells.entries)
        entry.key: [
          for (final g in groups)
            if (entry.value.contains(g)) g,
        ],
    };
  }
}

/// Los chips del selector de ocasión, en una fila que se desplaza.
class _OccasionChips extends StatelessWidget {
  const _OccasionChips({
    required this.groups,
    required this.selectedKey,
    required this.onSelected,
    this.centered = false,
    this.fill = false,
  });

  final List<OccasionGroup> groups;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  /// En una ventana ancha los chips se centran, como la rejilla; si no
  /// caben, empiezan a la izquierda y se desplazan como en el móvil.
  final bool centered;

  /// Si la franja ocupa todo el sitio que le dan aunque los chips midan menos
  /// (empiezan a la izquierda): así su borde es el de la columna de la
  /// rejilla y no el de lo que miden los chips.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.familyOccasionPickerLabel,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: kOccasionChipsKey,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: ConstrainedBox(
            // Con el ancho mínimo del hueco, la fila puede centrarse; sin él
            // (el móvil) mide lo que sus chips.
            constraints: BoxConstraints(
              minWidth: (centered || fill) && constraints.hasBoundedWidth
                  ? math.max(0, constraints.maxWidth - 32)
                  : 0,
            ),
            child: Row(
              mainAxisAlignment: centered
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                FilterPill(
                  label: l10n.familyChipAll,
                  selected: selectedKey == kAllOccasionsKey,
                  solid: true,
                  radius: RegalosShape.repartoChipRadius,
                  onTap: () => onSelected(kAllOccasionsKey),
                ),
                for (final g in groups) ...[
                  const SizedBox(width: 6),
                  FilterPill(
                    label: g.label,
                    selected: selectedKey == g.key,
                    solid: true,
                    radius: RegalosShape.repartoChipRadius,
                    leading: _Dot(color: g.theme.mark(dark: t.isDark)),
                    onTap: () => onSelected(g.key),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;
  final double size = 8;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: SizedBox.square(dimension: size),
    ),
  );
}

class _DuplicateBanner extends StatelessWidget {
  const _DuplicateBanner({required this.pairs, required this.view});

  final List<DuplicatePair> pairs;
  final FamilyView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final pair = pairs.first;
    final person = view.recipientsById[pair.recipientId]?.name ?? '';
    final text = StringBuffer(
      l10n.familyDuplicateBanner(person, pair.first.title),
    );
    if (pairs.length > 1) {
      text.write(' ${l10n.familyDuplicateMore(pairs.length - 1)}');
    }
    // Mantequilla como la maqueta: un aviso, no una alarma. Claro: fondo
    // pastel y texto en su tinta oscura; oscuro: el par oscuro del acento.
    final warn = AccentId.butter.palette;
    final fill = warn.surfaceOf(t.isDark);
    final ink = warn.inkOf(t.isDark);
    final action = warn.inkOf(t.isDark);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(color: fill, borderRadius: RegalosShape.card),
      child: Row(
        children: [
          StrokeIcon(tablerAlertTriangle, size: 18, color: action),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  text.toString(),
                  style: t.styles.meta.copyWith(color: ink),
                ),
              ),
            ),
          ),
          TextButton(
            // Esquinas de 8, nunca una píldora.
            style: TextButton.styleFrom(
              foregroundColor: action,
              shape: const RoundedRectangleBorder(
                borderRadius: RegalosShape.button,
              ),
            ),
            onPressed: () =>
                context.push('/people/${pair.recipientId}?from=family'),
            child: Text(l10n.giftDuplicateReview),
          ),
        ],
      ),
    );
  }
}
