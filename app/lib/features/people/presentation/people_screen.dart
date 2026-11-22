import '../../web_device/application/web_app_provider.dart';

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/content_gutter.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/layout/pane_selection.dart';
import '../../../core/layout/pane_workspace.dart';
import '../../../core/layout/two_pane.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/avatar_hero.dart';
import '../../../core/motion/completion_ring.dart';
import '../../../core/motion/shared_axis_switcher.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/motion/state_switcher.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/gift_segments.dart';
import '../../../core/motion/unfold_section.dart';
import '../../../core/widgets/header_button.dart';
import '../../../core/widgets/pane_list_row.dart';
import '../../../core/widgets/person_avatar.dart' show personPalette;
import '../../../core/widgets/pointer_surface.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/secret_block.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_actions.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/gift_logic.dart';
import '../../family/application/remote_change.dart';
import '../../family/presentation/family_texts.dart';
import '../../gifts/application/person_completion.dart';
import '../../family/presentation/pending_gifts_sheet.dart';
import '../../family/presentation/person_sheet.dart';
import '../../family/presentation/secret_blocks.dart';
import '../../gifts/presentation/add_gift_button.dart';
import '../../gifts/presentation/gift_editor_screen.dart';
import '../../gifts/presentation/gift_search.dart';
import '../../gifts/presentation/person_list_screen.dart';
import 'countdown_carousel.dart';

/// Pestaña Personas: la cuenta atrás de las próximas ocasiones (un carrusel
/// si hay varias) y la lista de personas con sus regalos.
///
/// Con dos paneles (desde 840 de ancho) es [PeopleWorkspace]: la lista a la
/// izquierda y, a la derecha, la de una persona.
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) => const PeopleWorkspace();
}

/// La persona que se enseña en el detalle de dos paneles cuando la URL no
/// dice ninguna (`/people`): la última abierta en la sesión o, si no hay, la
/// primera de la lista.
@visibleForTesting
String defaultPersonId(List<Recipient> people, String? last) {
  if (last != null && people.any((p) => p.id == last)) {
    return last;
  }
  return people.first.id;
}

/// Lo que se ve en la pestaña Personas, según la ventana.
///
/// - Con un panel y sin [personId] (`/people`): la lista de personas.
/// - Con un panel y [personId] (`/people/:id`): la lista de esa persona.
/// - Con dos paneles: la lista de personas a la izquierda con la elegida
///   marcada, a la derecha el detalle de esa persona y, en escritorio ancho,
///   la columna «Resumen» (sin ella, la próxima ocasión va en una fila sobre
///   la lista). La persona elegida es la de la URL o, en `/people`, la de por
///   defecto ([defaultPersonId]).
///
/// El detalle ([detailFor]) cambia de una persona a otra con un eje compartido
/// de 8 px en 220 ms; la lista no se mueve.
class PeopleWorkspace extends ConsumerWidget {
  const PeopleWorkspace({
    super.key,
    this.personId,
    this.detailFor,
    this.fromFamily = false,
  });

  /// La persona de la URL, si hay.
  final String? personId;

  /// El detalle de una persona; por defecto, su lista sin filtros.
  final Widget Function(String personId)? detailFor;

  /// Si se llegó desde Reparto: el atrás vuelve a Reparto.
  final bool fromFamily;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(recipientsProvider);
    final known = ref.watch(familyFullViewProvider).recipientsById;
    final window = WindowClass.of(context);
    final panes = window.usesTwoPanes && people.isNotEmpty;
    final width = MediaQuery.sizeOf(context).width;
    // Escritorio ancho: «Resumen» en su columna. Entre el escritorio y el
    // ancho no hay columna y la próxima ocasión va en una fila sobre la lista.
    final aside = panes && RegalosLayout.isDesktopWide(width);
    final upcomingStyle = !panes || !RegalosLayout.isDesktop(width)
        ? UpcomingStyle.carousel
        : (aside ? UpcomingStyle.none : UpcomingStyle.row);
    // La persona que se ve: con dos paneles, la de la URL si existe y, si no,
    // la de por defecto; con uno, la de la URL.
    final String? shown;
    if (panes) {
      final id = personId;
      shown = id != null && known.containsKey(id)
          ? id
          : defaultPersonId(people, ref.read(paneSelectionProvider).lastPerson);
    } else {
      shown = personId;
    }
    final upcoming = ref.watch(upcomingOccasionsProvider);
    final detailBuilder =
        detailFor ??
        (String id) =>
            PersonListScreen(key: ValueKey('/people/$id'), recipientId: id);
    final index = shown == null ? 0 : people.indexWhere((p) => p.id == shown);
    final selection = ref.read(paneSelectionProvider);
    void step(int delta) {
      final current = shown == null
          ? -1
          : people.indexWhere((p) => p.id == shown);
      final next = (current + delta).clamp(0, people.length - 1);
      if (next == current || people.isEmpty) {
        return;
      }
      selection.userChose(people[next].id);
      context.go('/people/${Uri.encodeComponent(people[next].id)}');
    }

    // Con dos paneles, `/people` queda debajo de `/people/:id` y no se ve: no
    // monta nada mientras tanto (la lista y su posición son las de la página
    // de encima). Y la lista de una persona es la raíz de Personas: el atrás
    // del sistema sale de la app (si no, `/people` se queda debajo y el router
    // lo manda de vuelta a una persona, y el atrás no llevaría a ningún
    // sitio). Desde Reparto sí vuelve a Reparto.
    return PaneRootGuard(
      panes: panes,
      routed: personId != null,
      exitOnBack: !fromFamily,
      child: PaneKeyboard(
        enabled: panes,
        onStep: step,
        onNew: (sheetContext) {
          if (shown != null) {
            unawaited(openGiftEditor(sheetContext, recipientId: shown));
          }
        },
        child: TwoPane(
          panes: panes,
          // `/people` con dos paneles queda debajo de `/people/:id` (el router
          // redirige en cuanto se sabe que hay dos paneles): esa página
          // transitoria no gasta la entrada, que es de la que se queda.
          entrance: panes && personId == null
              ? null
              : () => selection.takeEntrance(PaneTab.people),
          list: panes || personId == null
              ? PageStorage(
                  bucket: selection.listBucket,
                  child: PeopleListPane(
                    selectedId: panes ? shown : null,
                    panes: panes,
                    upcomingStyle: upcomingStyle,
                  ),
                )
              : null,
          detail: shown == null
              ? null
              : SharedAxisSwitcher(
                  index: index,
                  childKey: shown,
                  animate: panes,
                  fadeOnly: true,
                  child: detailBuilder(shown),
                ),
          aside: aside ? SummaryColumn(items: upcoming) : null,
        ),
      ),
    );
  }
}

/// El avatar de la fila elegida se asienta con una escala pequeña (de 0,92 a 1
/// en 160 ms, con `easeOut`) cuando pasa a estar elegida: acompaña al recuadro
/// que viaja y acaba con él. Un muelle de rebote seguía vivo 200 ms después de
/// asentarse la persona nueva. Con «Reducir movimiento» solo se funde, de medio
/// a opaco en 150 ms.
class _SelectPulse extends StatefulWidget {
  const _SelectPulse({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  State<_SelectPulse> createState() => _SelectPulseState();
}

class _SelectPulseState extends State<_SelectPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didUpdateWidget(_SelectPulse old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) {
      final reduce = RegalosMotion.of(context).reduce;
      _controller
        ..duration = reduce ? RegalosMotion.fade : kSelectionTravel
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = RegalosMotion.of(context).reduce;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        if (!_controller.isAnimating) {
          return child!;
        }
        final v = Curves.easeOut.transform(_controller.value);
        return reduce
            ? Opacity(opacity: 0.5 + 0.5 * v, child: child)
            : Transform.scale(scale: 0.92 + 0.08 * v, child: child);
      },
    );
  }
}

/// Cómo se enseña la cuenta atrás en el panel de lista de Personas.
enum UpcomingStyle {
  /// Un carrusel de tarjetas sobre la lista (el móvil y la tablet).
  carousel,

  /// Una fila de 56 con la próxima ocasión sobre la lista (escritorio sin
  /// columna «Resumen»).
  row,

  /// Nada: va en la columna «Resumen».
  none,
}

/// El panel de lista de Personas: el título, la cuenta atrás (un carrusel o una
/// fila, si no va en su propia columna) y las personas.
///
/// Con [panes] las personas son filas planas de 64 (avatar de 36, nombre y una
/// línea de datos, sin borde ni flecha), marca a la persona de [selectedId]
/// con su pastel y un borde de tinta (el recuadro viaja de una fila a otra),
/// tocar una persona cambia la URL en vez de apilar y no lleva «Añadir regalo»
/// (lo lleva el detalle).
class PeopleListPane extends ConsumerStatefulWidget {
  const PeopleListPane({
    super.key,
    this.selectedId,
    this.panes = false,
    this.upcomingStyle = UpcomingStyle.carousel,
  });

  /// La persona elegida, si hay dos paneles.
  final String? selectedId;

  /// Si es el panel de lista de dos paneles.
  final bool panes;

  /// Cómo va aquí la cuenta atrás. En el escritorio ancho va en su propia
  /// columna.
  final UpcomingStyle upcomingStyle;

  @override
  ConsumerState<PeopleListPane> createState() => _PeopleListPaneState();
}

class _PeopleListPaneState extends ConsumerState<PeopleListPane> {
  // El buscador de regalos: con algo escrito, sus resultados sustituyen a las
  // personas.
  final TextEditingController _query = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // Si el campo está desplegado bajo el título (la lupa de la cabecera lo abre
  // y «Cancelar» lo cierra).
  bool _searchOpen = false;

  @override
  void dispose() {
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// La lupa: despliega el campo y le da el foco (con el teclado abierto).
  void _openSearch() {
    setState(() => _searchOpen = true);
    // El campo existe desde el primer fotograma del despliegue.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchOpen) _searchFocus.requestFocus();
    });
  }

  /// «Cancelar»: vacía la búsqueda, vuelve la lista y se pliega el campo.
  void _closeSearch() {
    _searchFocus.unfocus();
    _query.clear();
    setState(() => _searchOpen = false);
  }

  // Para saber si lo que cambia en la lista llegó de otro móvil.
  int _seenRemote = 0;

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final people = ref.read(recipientsProvider);
    final result = await showPersonSheet(
      context,
      defaultColorIndex: people.length,
    );
    if (result != null && mounted) {
      await saveRecipient(ref, l10n, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final remote = ref.watch(remoteChangeProvider);
    final fromRemote = remote != _seenRemote;
    _seenRemote = remote;
    final people = ref.watch(recipientsProvider);
    final view = ref.watch(familyViewProvider);
    final upcoming = ref.watch(upcomingOccasionsProvider);
    // Solo el día: la hora no tiene que reconstruir lo que mide texto.
    final now = _today();
    final panes = widget.panes;

    final addButton = HeaderIconButton(
      icon: AppIcons.plus,
      label: l10n.obPeopleAdd,
      onTap: _add,
    );
    // Sin regalos no hay nada que buscar: sin lupa.
    final hasGifts = view.gifts.isNotEmpty;
    final searchButton = HeaderIconButton(
      key: const ValueKey<String>('people-gift-search-button'),
      icon: AppIcons.search,
      label: l10n.giftSearchOpen,
      onTap: _openSearch,
    );

    // El recuadro de selección: el pastel y la tinta de la persona elegida.
    final selected = widget.selectedId == null
        ? null
        : people.where((p) => p.id == widget.selectedId).firstOrNull;
    final palette = selected == null
        ? null
        : personPalette(selected.colorIndex);

    // Los bloques entran de arriba abajo una sola vez por visita; las filas
    // llevan clave estable (el id) para que su estado no salte de una a otra.
    var order = 0;
    // En tablet, una columna de 640 centrada en el panel: la lista lleva el
    // margen como relleno (se sigue desplazando al arrastrar por los lados).
    // En el móvil el margen es cero.
    return AddGiftFabScope(
      child: Scaffold(
        // Apuntar un regalo sin ir antes a la persona: con nadie a quien
        // regalar no hay nada que apuntar (queda «Añadir persona»). Con dos
        // paneles, el botón es el del detalle, para la persona elegida.
        floatingActionButton: people.isEmpty || panes
            ? null
            : const AddGiftButton(),
        body: StaggerScope(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                ContentWidth(
                  maxWidth: RegalosLayout.listColumn,
                  child: ScreenHeader(
                    title: l10n.navPeople,
                    actions: [if (hasGifts) searchButton, addButton],
                  ),
                ),
                Expanded(
                  child: StateSwitcher(
                    stateKey: people.isEmpty ? 'empty' : 'list',
                    child: people.isEmpty
                        ? Column(
                            children: [
                              Expanded(
                                child: EmptyState(
                                  icon: AppIcons.people,
                                  title: l10n.emptyPeopleTitle,
                                  message: l10n.emptyPeopleMessage,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                // Entra tras el título y la frase, a 40 ms de
                                // distancia, como el resto del estado vacío.
                                child: StaggerScope(
                                  step: const Duration(milliseconds: 40),
                                  delay: const Duration(milliseconds: 120),
                                  maxItems: 1,
                                  child: StaggerItem(
                                    index: 0,
                                    dy: 8,
                                    child: FilledButton(
                                      onPressed: _add,
                                      child: Text(l10n.obPeopleAdd),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : _withSearch(
                            context,
                            hasGifts: view.gifts.isNotEmpty,
                            child: ContentListView(
                              maxWidth: RegalosLayout.listColumn,
                              storageKey: const PageStorageKey<String>(
                                'people-list',
                              ),
                              padding: EdgeInsets.only(
                                bottom: addGiftButtonClearance(context),
                              ),
                              children: [
                                // Regalos en secreto guardados solo en este móvil.
                                const PendingGiftsNotice(),
                                if (upcoming.isNotEmpty &&
                                    widget.upcomingStyle == UpcomingStyle.row)
                                  StaggerItem(
                                    index: order++,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        8,
                                        0,
                                        8,
                                        8,
                                      ),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                              color: t.separator,
                                            ),
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: UpcomingOccasionRow(
                                            next: upcoming.first,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (upcoming.isNotEmpty &&
                                    widget.upcomingStyle ==
                                        UpcomingStyle.carousel) ...[
                                  StaggerItem(
                                    index: order++,
                                    child: SectionHeader(
                                      title: l10n.peopleUpcomingTitle,
                                      trailing: l10n.todayShort(now),
                                      bordered: false,
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        4,
                                        16,
                                        8,
                                      ),
                                    ),
                                  ),
                                  StaggerItem(
                                    index: order++,
                                    child: CountdownCarousel(
                                      items: upcoming,
                                      now: now,
                                    ),
                                  ),
                                ],
                                // Con dos paneles, el título de la cabecera ya dice
                                // «Personas»: la lista empieza en la primera fila.
                                if (!panes)
                                  StaggerItem(
                                    index: order++,
                                    child: SectionHeader(
                                      title: l10n.navPeople,
                                      trailing: '${people.length}',
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        16,
                                        8,
                                      ),
                                    ),
                                  ),
                                SelectionScope(
                                  selectedId: palette == null
                                      ? null
                                      : widget.selectedId,
                                  fill: palette == null
                                      ? t.surface
                                      : (t.isDark
                                            ? palette.tintD
                                            : palette.pastel),
                                  border: palette == null
                                      ? t.separator
                                      : (t.isDark
                                            ? palette.tintaD
                                            : palette.tinta),
                                  child: AnimatedRows(
                                    quiet: fromRemote,
                                    rows: [
                                      for (final person in people)
                                        AnimatedRowItem(
                                          id: person.id,
                                          child: StaggerItem(
                                            index: order++,
                                            child: _PersonRow(
                                              person: person,
                                              gifts: view.giftsFor(person.id),
                                              now: now,
                                              panes: panes,
                                              selected:
                                                  panes &&
                                                  person.id ==
                                                      widget.selectedId,
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pone sobre [child] (la lista de personas) el buscador de regalos, que se
  /// despliega bajo el título al tocar la lupa y se cierra con «Cancelar», y,
  /// con algo escrito, cambia la lista por los regalos que casan (nombre,
  /// nota, tienda o persona). Sin regalos aún no hay nada que buscar.
  Widget _withSearch(
    BuildContext context, {
    required bool hasGifts,
    required Widget child,
  }) {
    if (!hasGifts) {
      return child;
    }
    final searching = _searchOpen && _query.text.trim().isNotEmpty;
    return Column(
      children: [
        // El campo se despliega con el muelle de las hojas y se pliega al
        // cancelar; con «Reducir movimiento», solo se funde.
        UnfoldSection(
          show: _searchOpen,
          child: ContentWidth(
            maxWidth: RegalosLayout.listColumn,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: GiftSearchField(
                      key: const ValueKey<String>('people-gift-search'),
                      controller: _query,
                      focusNode: _searchFocus,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    key: const ValueKey<String>('people-gift-search-cancel'),
                    onPressed: _closeSearch,
                    child: Text(AppLocalizations.of(context).actionCancel),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: searching
              ? ContentListView(
                  maxWidth: RegalosLayout.listColumn,
                  padding: EdgeInsets.only(
                    bottom: addGiftButtonClearance(context),
                  ),
                  children: [
                    GiftSearchResults(
                      query: _query.text,
                      scrollable: false,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      onOpen: (g) => openGiftEditor(context, gift: g),
                    ),
                  ],
                )
              : child,
        ),
      ],
    );
  }
}

/// Lo que mide una fila de persona del panel de lista de escritorio.
const double kPersonRowHeight = 64;

/// Hoy, solo la fecha: la hora no tiene que reconstruir lo que mide texto
/// (la guía de diseño de escritorio, §4.6).
DateTime _today() {
  final now = clock.now();
  return DateTime(now.year, now.month, now.day);
}

class _PersonRow extends ConsumerWidget {
  const _PersonRow({
    required this.person,
    required this.gifts,
    required this.now,
    this.panes = false,
    this.selected = false,
  });

  final Recipient person;
  final List<Gift> gifts;
  final DateTime now;

  /// Si es una fila del panel de lista de dos paneles (plana, de 64): tocarla
  /// cambia la persona del detalle (detrás de la elegida viaja el recuadro).
  final bool panes;

  /// Si es la persona elegida del panel de lista.
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final complete = ref.watch(personCompletionProvider(person.id)).complete;
    // Con regalos en secreto que este móvil no ve, la fila no lleva cifras: ni
    // cuántos regalos hay ni cuántos faltan; en su lugar, el bloque fijo.
    final locked = ref.watch(lockedPeopleProvider).contains(person.id);
    final web = ref.watch(webAppProvider);
    final pending = gifts.where(needsBuying).length;
    // Quien solo regala (1.0.6) no recibe regalos: en vez de «0 regalos», lo
    // dice la etiqueta.
    final onlyGives = person.noGifts;
    final pendingText = locked || onlyGives || gifts.isEmpty
        ? null
        : (pending > 0 ? l10n.personPendingBuy(pending) : l10n.personAllBought);
    final meta = <String>[
      ?person.relation,
      ?ageText(l10n, person, now),
      if (onlyGives)
        l10n.personNoGiftsLabel
      else if (!locked)
        l10n.giftCount(gifts.length),
    ].join(' · ');
    final semanticLabel =
        '${person.name}. ${[if (meta.isNotEmpty) meta, ?pendingText, if (locked) secretBlockLabel(l10n, person.name, web: web)].join(' · ')}';
    void open() {
      if (panes) {
        ref.read(paneSelectionProvider).userChose(person.id);
      }
      context.go('/people/${person.id}');
    }

    if (panes) {
      // Escritorio: la fila plana de las listas de los dos paneles
      // (`PaneListRow`): sin borde ni flecha. La elegida, con el recuadro que
      // viaja por detrás; el resto, solo el tinte del ratón.
      return PaneListRow(
        id: person.id,
        selected: selected,
        label: semanticLabel,
        // La fila con el bloque fijo es más alta; el resto no cambia.
        minHeight: locked ? kPaneRowHeight + 44 : kPaneRowHeight,
        onTap: open,
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _SelectPulse(
                  selected: selected,
                  child: AvatarHero(
                    personId: person.id,
                    name: person.name,
                    colorIndex: person.colorIndex,
                    size: 36,
                  ),
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: MiniSeal(visible: complete, size: 14),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PaneListRow.nameStyle(t),
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.styles.meta,
                    ),
                  if (locked) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 36,
                      child: SecretStrip(
                        key: ValueKey<String>('secret-strip:${person.id}'),
                        shown: true,
                        name: person.name,
                        colorIndex: person.colorIndex,
                        web: web,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: open,
      // Una fila con filete de 1 px debajo, sin tarjeta (la ficha).
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SelectionRow(
          id: person.id,
          // Cada fila en su capa: el hover de una no repinta la lista entera.
          child: RepaintBoundary(
            child: PointerSurface(
              child: Material(
                color: Colors.transparent,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: open,
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: RegalosSizes.personCardHeight,
                    ),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: t.separator)),
                    ),
                    padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
                    child: Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Late una vez al quedar completa.
                            CompletionBeat(
                              complete: complete,
                              child: AvatarHero(
                                personId: person.id,
                                name: person.name,
                                colorIndex: person.colorIndex,
                                size: RegalosSizes.personAvatar,
                              ),
                            ),
                            // El sello de «persona completa», en pequeño.
                            Positioned(
                              right: -5,
                              bottom: -5,
                              child: MiniSeal(visible: complete),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // El nombre y, en la misma línea, lo demás; si
                              // no cabe (letra grande), lo demás baja de línea
                              // en vez de cortarse con «…».
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.end,
                                spacing: 8,
                                children: [
                                  Text(
                                    person.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.styles.rowTitle.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (meta.isNotEmpty)
                                    Text(meta, style: t.styles.meta),
                                ],
                              ),
                              if (locked) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 36,
                                  child: SecretStrip(
                                    key: ValueKey<String>(
                                      'secret-strip:${person.id}',
                                    ),
                                    shown: true,
                                    name: person.name,
                                    colorIndex: person.colorIndex,
                                    web: web,
                                  ),
                                ),
                              ],
                              if (pendingText != null) ...[
                                const SizedBox(height: 6),
                                LayoutBuilder(
                                  builder: (context, box) => Row(
                                    children: [
                                      // Los segmentos en la tinta del acento
                                      // y, al lado, lo que falta (en tinta y
                                      // negrita con todo comprado).
                                      Flexible(
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth: box.maxWidth * 0.38,
                                          ),
                                          child: GiftSegments(
                                            total: gifts.length,
                                            done: gifts.length - pending,
                                            color: t.ink,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: box.maxWidth * 0.62,
                                        ),
                                        child: ValueSwitcher(
                                          child: Text(
                                            _capitalized(pendingText),
                                            key: ValueKey(pendingText),
                                            style: t.styles.meta.copyWith(
                                              color: pending == 0
                                                  ? t.ink
                                                  : t.text,
                                              fontWeight: pending == 0
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        StrokeIcon(
                          AppIcons.chevronRight,
                          color: t.textSecondary,
                          strokeWidth: 1.9,
                        ),
                      ],
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

String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
