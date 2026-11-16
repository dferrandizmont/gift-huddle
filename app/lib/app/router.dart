import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/pane_page.dart';
import '../core/layout/pane_scope.dart';
import '../core/layout/pane_selection.dart';
import '../core/layout/smooth_wheel.dart';
import '../core/layout/window_class.dart';
import '../core/motion/fading_branch_container.dart';
import '../core/widgets/regalos_nav_bar.dart';
import '../core/widgets/regalos_nav_rail.dart';
import '../core/widgets/stroke_icon.dart';
import '../features/family/application/family_providers.dart';
import '../features/family/application/gift_logic.dart';
import '../features/family/presentation/family_screen.dart';
import '../features/gifts/presentation/gift_editor_screen.dart';
import '../features/gifts/presentation/person_list_screen.dart';
import '../features/occasions/application/occasion_rows.dart';
import '../features/occasions/presentation/occasions_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/people/presentation/people_screen.dart';
import '../features/recovery/application/recovery_hold.dart';
import '../features/recovery/presentation/recovery_restore_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/settings_sections.dart';
import '../features/sharing/presentation/join_qr_screen.dart';
import '../features/sync/presentation/join_invite_screen.dart';
import '../features/tour/application/tour_state.dart';
import '../features/tour/presentation/tour_screen.dart';
import '../features/web_board/application/board_lanes.dart'
    show boardGiftsProvider;
import '../features/web_board/application/board_metrics.dart';
import '../features/web_board/application/gift_editor_panel.dart';
import '../features/web_board/application/web_board.dart';
import '../features/web_board/presentation/board_editor_host.dart';
import '../features/web_board/presentation/board_keyboard.dart';
import '../features/web_board/presentation/board_reparto.dart';
import '../features/web_board/presentation/board_screens.dart';
import '../features/web_board/presentation/board_settings_screen.dart';
import '../features/web_board/presentation/board_sidebar.dart';
import '../features/web_device/application/web_app_provider.dart';
import '../features/web_device/presentation/web_desktop_frame.dart';
import '../features/web_device/presentation/web_status_strip.dart';
import '../l10n/app_localizations.dart';
import 'root_navigator.dart';

/// La página de una ruta, con la transición del tema.
///
/// Con `builder:` go_router decide la clase de página según el tipo de app y,
/// aquí, acaba usando una sin transición (`NoTransitionPage`): no hay
/// animación ni `Hero`. Con `MaterialPage` la ruta toma la transición de
/// `ThemeData.pageTransitionsTheme` (la del muelle en Android, la nativa en
/// iOS) y es una `PageRoute`, así que los `Hero` vuelan.
///
/// Con [panes] la página es de una rama con dos paneles (`PanePage`): con dos
/// paneles a la vista no hay transición, porque cada página pinta la lista y
/// el detalle enteros y la lista no se mueve nunca.
GoRouterPageBuilder regalosPage(
  GoRouterWidgetBuilder builder, {
  bool panes = false,
}) => (context, state) {
  final name = state.name ?? state.path;
  final arguments = <String, String>{
    ...state.pathParameters,
    ...state.uri.queryParameters,
  };
  final child = builder(context, state);
  return panes
      ? PanePage(
          key: state.pageKey,
          name: name,
          arguments: arguments,
          restorationId: state.pageKey.value,
          child: child,
        )
      : MaterialPage<void>(
          key: state.pageKey,
          name: name,
          arguments: arguments,
          restorationId: state.pageKey.value,
          child: child,
        );
};

/// Rutas de la app.
abstract final class AppRoutes {
  static const welcome = '/welcome';
  static const join = '/join';
  static const joinLink = '/join-link';

  /// «Tengo un código de recuperación», desde la bienvenida.
  static const recover = '/recover';

  /// «Recuperar con fichero» (ADR 0008), desde la bienvenida o al abrir un
  /// fichero de recuperación desde Archivos.
  static const recoverFile = '/recover-file';

  /// La guía «Cómo funciona». Desde Ajustes lleva `?from=settings`.
  static const tour = '/tour';
  static const people = '/people';
  static const family = '/family';
  static const occasions = '/occasions';

  /// Una fila más de `/occasions/:id`, con [kBudgetRowId] como id.
  static const budget = '/occasions/budget';
  static const settings = '/settings';
  static const appearance = '/settings/appearance';
}

/// Crea el router con la navegación de cuatro destinos (Personas, Familia,
/// Ocasiones y Ajustes): barra inferior o raíl lateral, según la ventana
/// ([AppShell]). Cada destino conserva su pila.
///
/// Con [redirect] y [refreshListenable] la app manda al primer uso mientras
/// no haya familia.
GoRouter buildRouter({
  String initialLocation = AppRoutes.people,
  GoRouterRedirect? redirect,
  Listenable? refreshListenable,
}) {
  late final GoRouter router;
  router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    redirect: (context, state) {
      // Los documentos y enlaces /i y /s tienen sus propios receptores.
      // Nunca deben sustituir la pantalla actual por una ruta externa.
      if (state.uri.hasScheme ||
          state.uri.hasAuthority ||
          state.error != null) {
        final current = router.routerDelegate.currentConfiguration;
        return current.isNotEmpty && !current.isError
            ? router.state.uri.toString()
            : AppRoutes.people;
      }
      return redirect?.call(context, state);
    },
    onException: (context, state, router) => router.go(AppRoutes.people),
    refreshListenable: refreshListenable,
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: regalosPage((context, state) => const OnboardingScreen()),
      ),
      GoRoute(
        path: AppRoutes.join,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: regalosPage(
          (context, state) =>
              JoinQrScreen(deviceName: state.extra as String? ?? ''),
        ),
      ),
      GoRoute(
        path: AppRoutes.recover,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: regalosPage(
          (context, state) => const RecoveryRestoreScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.recoverFile,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: regalosPage(
          (context, state) => const RecoveryRestoreScreen(fileMode: true),
        ),
      ),
      GoRoute(
        path: AppRoutes.tour,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: regalosPage(
          (context, state) => TourScreen(
            fromSettings: state.uri.queryParameters['from'] == 'settings',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.joinLink,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: regalosPage(
          (context, state) => JoinInviteScreen(
            fromWelcome: true,
            deviceName: state.extra as String? ?? '',
          ),
        ),
      ),
      StatefulShellRoute(
        builder: (context, state, shell) => AppShell(shell: shell),
        // Como `indexedStack`, pero el contenido que llega se funde en 150 ms.
        navigatorContainerBuilder: (context, shell, children) =>
            FadingBranchContainer(
              currentIndex: shell.currentIndex,
              children: children,
            ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.people,
                pageBuilder: regalosPage(
                  // En la web, desde 1280, es el tablero «Hoy».
                  (context, state) => const WebBoardGate(
                    board: BoardHomeScreen(),
                    classic: PeopleScreen(),
                  ),
                  panes: true,
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    pageBuilder: regalosPage((context, state) {
                      final id = state.pathParameters['id']!;
                      final giver = state.uri.queryParameters['giver'];
                      final occasion = state.uri.queryParameters['occasion'];
                      final fromFamily =
                          state.uri.queryParameters['from'] == 'family';
                      final uri = state.uri.toString();
                      return WebBoardGate(
                        board: BoardPersonPage(
                          personId: id,
                          fromFamily: fromFamily,
                          initialFilter: GiftFilter(
                            giverId: giver,
                            occasionId: occasion,
                          ),
                        ),
                        classic: PeopleWorkspace(
                          personId: id,
                          fromFamily: fromFamily,
                          // Con dos paneles, la persona de la URL; si ya no
                          // existe, la de por defecto (sin los filtros de la
                          // URL, que eran de otra).
                          detailFor: (shownId) => PersonListScreen(
                            key: ValueKey(
                              shownId == id ? uri : '/people/$shownId',
                            ),
                            recipientId: shownId,
                            fromFamily: shownId == id && fromFamily,
                            initialFilter: shownId == id
                                ? GiftFilter(
                                    giverId: giver,
                                    occasionId: occasion,
                                  )
                                : const GiftFilter(),
                          ),
                        ),
                      );
                    }, panes: true),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.family,
                pageBuilder: regalosPage(
                  // En la web, desde 1280, es el Reparto del tablero.
                  (context, state) => const WebBoardGate(
                    board: BoardRepartoScreen(),
                    classic: FamilyScreen(),
                  ),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.occasions,
                pageBuilder: regalosPage(
                  (context, state) => const WebBoardGate(
                    board: BoardOccasionsScreen(),
                    classic: OccasionsWorkspace(),
                  ),
                  panes: true,
                ),
                routes: [
                  GoRoute(
                    path: ':id',
                    pageBuilder: regalosPage(
                      (context, state) => WebBoardGate(
                        board: BoardOccasionsScreen(
                          selected: state.pathParameters['id']!,
                        ),
                        classic: OccasionsWorkspace(
                          selected: state.pathParameters['id']!,
                          fromPeople:
                              state.uri.queryParameters['from'] == 'people',
                        ),
                      ),
                      panes: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                pageBuilder: regalosPage(
                  (context, state) => const WebBoardGate(
                    board: BoardSettingsScreen(),
                    classic: SettingsWorkspace(),
                  ),
                  panes: true,
                ),
                routes: [
                  // Un solo `GoRoute` para todos los apartados: go_router usa
                  // el patrón de la ruta como clave de la página, así que
                  // cambiar de apartado reutiliza la página (la lista de
                  // apartados no se monta de nuevo y el recuadro de selección
                  // viaja) en vez de apilar una página por apartado.
                  GoRoute(
                    path: ':section',
                    // Un apartado que no existe vuelve a la lista.
                    redirect: (context, state) =>
                        kSettingsSections.contains(
                          state.pathParameters['section'],
                        )
                        ? null
                        : AppRoutes.settings,
                    pageBuilder: regalosPage(
                      (context, state) => WebBoardGate(
                        board: BoardSettingsScreen(
                          section: state.pathParameters['section'],
                        ),
                        classic: SettingsWorkspace(
                          section: state.pathParameters['section'],
                        ),
                      ),
                      panes: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  return router;
}

/// Las rutas que la web no tiene (ADR 0003, §8): compartir, copia de
/// seguridad, protecciones del móvil y unirse a una familia. Si alguien llega
/// a ellas por la dirección, vuelve a Ajustes.
const _hiddenOnWeb = <String>{
  '/settings/share',
  '/settings/backup',
  '/settings/security',
  '/settings/recovery',
  AppRoutes.join,
  AppRoutes.joinLink,
  AppRoutes.recover,
  AppRoutes.recoverFile,
  AppRoutes.tour,
};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<bool?>(
    familyStateProvider.select((state) => state?.hasFamily),
    (_, _) => refresh.value++,
  );
  // Personas con dos paneles lleva a una persona elegida (la URL es la
  // selección): hay que volver a decidir cuando cambia el número de paneles de
  // la ventana y cuando aparece la primera persona.
  final panes = ref.read(paneSelectionProvider);
  void onPanes() => refresh.value++;
  panes.twoPanes.addListener(onPanes);
  ref.listen<bool>(
    recipientsProvider.select((people) => people.isEmpty),
    (_, _) => refresh.value++,
  );
  ref.listen<bool>(
    occasionsProvider.select((occasions) => occasions.isEmpty),
    (_, _) => refresh.value++,
  );
  // La recuperación con el código retiene la entrada mientras enseña su
  // pantalla final; al soltarla, el router vuelve a decidir.
  final hold = ref.read(recoveryHoldProvider);
  void onHold() => refresh.value++;
  hold.addListener(onHold);
  final router = buildRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final family = ref.read(familyStateProvider);
      if (family == null) {
        // Todavía cargando: el bloqueo tapa la app hasta que acabe.
        return null;
      }
      final location = state.matchedLocation;
      if (ref.read(webAppProvider) && _hiddenOnWeb.contains(location)) {
        return family.hasFamily ? AppRoutes.settings : null;
      }
      final firstRun =
          location == AppRoutes.welcome ||
          location == AppRoutes.join ||
          location == AppRoutes.joinLink ||
          location == AppRoutes.recover ||
          location == AppRoutes.recoverFile;
      if (!family.hasFamily && !firstRun) {
        return AppRoutes.welcome;
      }
      if (family.hasFamily && location == AppRoutes.welcome) {
        // «Recuperar con el código» se abre encima de la bienvenida y la
        // familia aparece antes de que acabe: su pantalla final no se pierde.
        if (hold.value) {
          return null;
        }
        // Al terminar la bienvenida la primera vez, la guía «Cómo funciona».
        return ref.read(tourAfterWelcomeProvider).pending
            ? AppRoutes.tour
            : AppRoutes.people;
      }
      final occasions = ref.read(occasionsProvider);
      return panes.redirectPeople(location, [
            for (final person in ref.read(recipientsProvider)) person.id,
          ]) ??
          panes.redirectTab(
            PaneTab.occasions,
            location,
            occasions.isEmpty
                ? const <String>[]
                : occasionRowIds(occasions, clock.now()),
            fallback: nextOccasionRowId(occasions, clock.now()),
          ) ??
          panes.redirectTab(
            PaneTab.settings,
            location,
            settingsSectionIds(web: ref.read(webAppProvider)),
          );
    },
  );
  ref.onDispose(() {
    panes.twoPanes.removeListener(onPanes);
    hold.removeListener(onHold);
    router.dispose();
    refresh.dispose();
  });
  return router;
});

/// Marco de las cuatro pestañas: la navegación y, a su lado, el contenido de
/// la rama activa (la guía de diseño para tablet, §2.1 y §3.1).
///
/// En una ventana compacta (ancho menor de 600 o alto menor de 480) la
/// navegación es la barra inferior de siempre; desde 600 dp, el raíl lateral y
/// ninguna barra abajo. Cruzar el corte no anima nada.
///
/// El contenido va siempre en el mismo sitio del árbol, dentro de un
/// [PaneScope], con raíl o con barra: girar o cambiar el tamaño de la ventana
/// no desmonta las ramas, así que cada una conserva su pila, su posición y lo
/// que tuviera a medias. `PaneScope.widthOf` da dentro el ancho del área de
/// contenido (la ventana menos el raíl).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final window = WindowClass.of(context);
    // En la web, desde 1280, la app es el tablero «Hoy»: barra lateral, el
    // tablero y el editor como panel fijo a la derecha (`WebBoardGate`).
    final board = isWebBoard(context, ref);
    final rail = window.usesRail && !board;
    // El router no ve el tamaño de la ventana: se lo cuenta este marco, para
    // que Personas lleve a una persona elegida cuando hay dos paneles. El
    // tablero no usa esa elección: `/people` es «Hoy».
    ref
        .read(paneSelectionProvider)
        .reportTwoPanes(window.usesTwoPanes && !board);
    final destinations = [
      NavDestination(icon: AppIcons.people, label: l10n.navPeople),
      NavDestination(icon: AppIcons.family, label: l10n.navFamilyShort),
      NavDestination(icon: AppIcons.occasions, label: l10n.navOccasions),
      NavDestination(icon: AppIcons.settings, label: l10n.navSettings),
    ];
    // Tocar el destino activo vuelve a su primera pantalla.
    void onSelected(int i) {
      if (board) {
        // El foco de la pantalla que se va no se lleva el filete a la nueva.
        FocusManager.instance.primaryFocus?.unfocus();
        // «Hoy» es siempre la pantalla de «Hoy», no la última persona vista.
        if (i == 0) {
          context.go(AppRoutes.people);
          return;
        }
      }
      shell.goBranch(i, initialLocation: i == shell.currentIndex);
    }

    // En el tablero el estado de guardado va al pie de la barra lateral.
    final area = _ContentArea(
      besideRail: rail || board,
      syncInRail: rail || board,
      child: shell,
    );
    final content = Expanded(child: area);

    // En la web, en una ventana más ancha que la columna de escritorio, todo
    // (raíl incluido) se centra en esa columna; en el móvil, no hace nada.
    return SmoothWheel(
      child: WebDesktopFrame(
        child: Scaffold(
          body: board
              ? _BoardFrame(shell: shell, onSelected: onSelected, child: area)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Siempre dos hijos, para que el contenido no cambie de
                    // sitio.
                    if (rail)
                      RegalosNavRail(
                        semanticLabel: l10n.navMainLabel,
                        selectedIndex: shell.currentIndex,
                        destinations: destinations,
                        onSelected: onSelected,
                        // El estado de guardado de la web, abajo del raíl.
                        footer: const WebRailStatus(),
                      )
                    else
                      const SizedBox.shrink(),
                    content,
                  ],
                ),
          bottomNavigationBar: rail || board
              ? null
              : RegalosNavBar(
                  semanticLabel: l10n.navMainLabel,
                  selectedIndex: shell.currentIndex,
                  destinations: destinations,
                  onSelected: onSelected,
                ),
        ),
      ),
    );
  }
}

/// El marco del tablero de la web de escritorio: la barra lateral, el
/// contenido y el panel del editor, con los atajos de teclado (↑ y ↓ cambian
/// de persona, N abre «Nuevo regalo» y Esc cierra el editor).
class _BoardFrame extends ConsumerWidget {
  const _BoardFrame({
    required this.shell,
    required this.onSelected,
    required this.child,
  });

  final StatefulNavigationShell shell;
  final ValueChanged<int> onSelected;

  /// El contenido (sin `Expanded`: lo coloca el marco del editor).
  final Widget child;

  Uri _location(BuildContext context) =>
      GoRouter.of(context).routerDelegate.currentConfiguration.uri;

  /// Alt + ↑ y Alt + ↓: la persona de al lado de la lista de la barra lateral
  /// (con «Hoy» antes de la primera).
  void _stepPage(BuildContext context, WidgetRef ref, int delta) {
    final people = ref.read(recipientsProvider);
    final ids = [boardTodayId, for (final p in people) boardPersonId(p.id)];
    final current = ids.indexOf(boardSelectionOf(_location(context)));
    if (current < 0 || shell.currentIndex != 0) {
      return;
    }
    final next = (current + delta).clamp(0, ids.length - 1);
    if (next == current) {
      return;
    }
    if (next > 0) {
      departBoardAvatar(ref, people[next - 1].id);
    }
    context.go(next == 0 ? AppRoutes.people : '/people/${people[next - 1].id}');
  }

  /// Abre en el editor el regalo `id` (si existe).
  void _openGift(BuildContext context, WidgetRef ref, String? id) {
    if (id == null) {
      return;
    }
    final gift = ref
        .read(boardGiftsProvider)
        .where((g) => g.id == id)
        .firstOrNull;
    if (gift != null) {
      openGiftEditor(context, gift: gift);
    }
  }

  /// ↑ y ↓: los regalos de la pantalla (los carriles o la tabla de una
  /// persona). Con el editor abierto, el editor sigue a la marca.
  void _stepGift(BuildContext context, WidgetRef ref, int delta) {
    final id = ref.read(boardGiftCursorProvider).step(delta);
    if (ref.read(giftEditorPanelProvider).isOpen) {
      _openGift(context, ref, id);
    }
  }

  /// N: un regalo nuevo para la persona o la ocasión de la pantalla.
  void _newGift(BuildContext context) {
    final segments = _location(context).pathSegments;
    final id = segments.length >= 2 ? segments[1] : null;
    if (segments.isNotEmpty && segments.first == 'people' && id != null) {
      openGiftEditor(context, recipientId: id);
    } else if (segments.isNotEmpty &&
        segments.first == 'occasions' &&
        id != null &&
        id != kBudgetRowId) {
      openGiftEditor(context, occasionId: id, chooseRecipient: true);
    } else {
      openGiftEditor(context, chooseRecipient: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.read(giftEditorPanelProvider);
    final cursor = ref.read(boardGiftCursorProvider);
    final collapsed = ref.watch(boardSidebarCollapsedProvider);
    final sidebar = BoardSidebar.widthFor(
      MediaQuery.sizeOf(context).width,
      collapsed: collapsed,
    );
    return BoardKeyboard(
      onStep: (delta) => _stepGift(context, ref, delta),
      onPage: (delta) => _stepPage(context, ref, delta),
      onOpen: () => _openGift(context, ref, cursor.current),
      onNew: () => _newGift(context),
      // Esc cierra el editor aunque el foco no esté dentro de él; sin editor,
      // quita la marca del teclado.
      escapeEnabled: () => panel.isOpen || cursor.current != null,
      onEscape: () => panel.isOpen ? panel.close() : cursor.clear(),
      openEnabled: () => cursor.current != null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaneScope(
            role: PaneRole.list,
            child: BoardSidebar(onSection: onSelected),
          ),
          Expanded(
            child: BoardEditorHost(sidebar: sidebar, child: child),
          ),
        ],
      ),
    );
  }
}

/// El área de contenido: el panel de la rama activa.
///
/// Junto al raíl ya no le toca el margen seguro de ese lado (lo ha gastado el
/// raíl). El árbol es el mismo con raíl y sin él.
class _ContentArea extends StatelessWidget {
  const _ContentArea({
    required this.besideRail,
    required this.syncInRail,
    required this.child,
  });

  final bool besideRail;

  /// Si el estado de guardado de la web va en el pie del raíl (no hay raíl en
  /// el tablero: va en la franja de arriba).
  final bool syncInRail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return MediaQuery.removePadding(
      context: context,
      removeLeft: besideRail && !rtl,
      removeRight: besideRail && rtl,
      // Arriba, en la web, el aviso de cambios apartados y el estado de
      // guardado; en el móvil no ocupa nada.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebStatusStrip(syncInRail: syncInRail),
          Expanded(child: PaneScope(child: child)),
        ],
      ),
    );
  }
}
