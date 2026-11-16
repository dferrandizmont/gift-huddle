import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_info.dart';
import '../../../core/layout/pane_selection.dart';
import '../../../core/layout/pane_workspace.dart';
import '../../../core/layout/two_pane.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/shared_axis_switcher.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/pane_list_row.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/settings_row.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../lock/application/lock_controller.dart';
import '../../recovery/presentation/recovery_screen.dart' show recoveryRowValue;
import '../../sync/application/recovery_providers.dart'
    show recoveryStatusProvider;
import '../../sync/application/sync_controller.dart';
import '../../sync/presentation/sync_texts.dart';
import '../../web_device/application/web_app_provider.dart';
import '../../web_device/application/web_device_providers.dart';
import '../../web_device/presentation/web_settings_section.dart';
import '../application/appearance_provider.dart';
import 'appearance_screen.dart';
import 'erase_all_dialog.dart';
import 'language_row.dart';
import 'self_recipient_row.dart';
import 'settings_column.dart';
import 'settings_sections.dart';

/// Lo que se ve en la pestaña Ajustes, según la ventana.
///
/// - Con un panel y sin [section] (`/settings`): la lista de apartados.
/// - Con un panel y [section] (`/settings/appearance`): ese apartado.
/// - Con dos paneles: la lista a la izquierda, con el apartado elegido
///   marcado, y a la derecha el apartado, en su columna (640 a 72 px del filete
///   en escritorio, 560 en tablet) y sin flecha de volver.
///   El elegido es el de la URL o, en `/settings`, el último abierto o el
///   primero.
class SettingsWorkspace extends ConsumerWidget {
  /// Crea la pestaña.
  const SettingsWorkspace({super.key, this.section});

  /// El apartado de la URL, si hay.
  final String? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panes = WindowClass.of(context).usesTwoPanes;
    final selection = ref.read(paneSelectionProvider);
    final ids = settingsSectionIds(web: ref.watch(webAppProvider));
    final String? shown;
    if (panes) {
      final last = selection.lastOf(PaneTab.settings);
      shown = section != null && ids.contains(section)
          ? section
          : (last != null && ids.contains(last) ? last : ids.first);
    } else {
      shown = section;
    }
    final index = shown == null ? 0 : ids.indexOf(shown);

    void step(int delta) {
      final current = shown == null ? -1 : ids.indexOf(shown);
      final next = (current + delta).clamp(0, ids.length - 1);
      if (next == current) {
        return;
      }
      selection.choose(PaneTab.settings, ids[next]);
      context.go('${PaneTab.settings.root}/${ids[next]}');
    }

    return PaneRootGuard(
      panes: panes,
      routed: section != null,
      child: PaneKeyboard(
        enabled: panes,
        onStep: step,
        child: TwoPane(
          panes: panes,
          entrance: () => selection.takeEntrance(PaneTab.settings),
          list: panes || section == null
              ? PageStorage(
                  bucket: selection.listBucket,
                  child: SettingsScreen(
                    selectedId: panes ? shown : null,
                    panes: panes,
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
                  child: KeyedSubtree(
                    key: ValueKey('/settings/$shown'),
                    child: settingsSectionScreen(shown),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Pestaña Ajustes: cuatro grupos en orden de uso (Familia, Este móvil,
/// Compartir y copia, Acerca de). Cada fila lleva su icono y, a la derecha,
/// el valor de ahora (la maqueta de ajustes, propuesta A).
///
/// Con [panes] es el panel de lista de dos paneles: marca el apartado de
/// [selectedId] con el pastel del acento (el recuadro viaja de uno a otro) y
/// tocar un apartado cambia la URL en vez de apilar.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.selectedId, this.panes = false});

  /// El apartado elegido, si hay dos paneles.
  final String? selectedId;

  /// Si es el panel de lista de dos paneles.
  final bool panes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final view = ref.watch(familyViewProvider);
    final full = ref.watch(familyFullViewProvider);
    final archived =
        full.recipients.where((r) => r.archived).length +
        full.givers.where((g) => g.archived).length +
        full.occasions.where((o) => o.archived).length;
    final lock = ref.watch(lockControllerProvider).value;
    final pinOn = (lock?.enabled ?? false) && (lock?.pinSet ?? false);
    final lockValue = !pinOn
        ? l10n.settingsLockOff
        : (lock?.biometrics ?? false)
        ? l10n.settingsLockPinBiometrics
        : l10n.settingsLockPin;
    final appearance = ref.watch(appearanceProvider);
    final themeName = switch (appearance.themeMode) {
      ThemeMode.system => l10n.themeSystem,
      ThemeMode.light => l10n.themeLight,
      ThemeMode.dark => l10n.themeDark,
    };
    // En la web no hay móviles que gestionar, ni compartir, ni copia de
    // seguridad, ni protecciones del móvil, ni cambiar «Yo» (ADR 0003, §8): se
    // ve lo de la familia, el idioma, la apariencia y «Este ordenador».
    final isWeb = ref.watch(webAppProvider);
    final paired = ref.watch(familyStateProvider)?.paired ?? false;
    final sync = ref.watch(syncControllerProvider);
    final syncShort = syncShortText(l10n, sync);
    final devicesValue = !paired
        ? l10n.settingsDevicesOnlyThis
        : syncShort == null
        ? '2'
        : l10n.settingsDevicesValue(2, syncShort);

    // Tocar un apartado abre su pantalla; con dos paneles cambia la del
    // detalle (la URL es la selección).
    void go(String id) {
      if (panes) {
        ref.read(paneSelectionProvider).choose(PaneTab.settings, id);
      }
      context.go('/settings/$id');
    }

    // En el panel de lista cada bloque va con el margen de las filas de
    // Personas y Ocasiones (`kPaneRowInset`), para que el recuadro de la
    // elegida mida lo mismo en las tres.
    Widget inset(Widget block) => panes
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPaneRowInset),
            child: block,
          )
        : block;
    final headerPadding = const EdgeInsets.fromLTRB(16, 12, 16, 8);

    // Una fila que abre un apartado.
    Widget section(
      String id, {
      required StrokeIconBuilder icon,
      required String title,
      String? value,
    }) {
      final row = SettingsRow(
        icon: icon,
        title: title,
        value: value,
        selected: panes && selectedId == id,
        onTap: () => go(id),
      );
      return panes ? SelectionRow(id: id, child: row) : row;
    }

    final appearanceRow = section(
      'appearance',
      icon: SettingsIcons.palette,
      title: l10n.settingsAppearance,
      value: l10n.settingsAppearanceValue(
        appearance.accent.label(l10n),
        themeName,
      ),
    );

    // Entran los grupos, no las filas sueltas (§1.6): cada grupo con su
    // cabecera es un bloque.
    var order = 0;
    Widget group(String title, List<Widget> rows) => StaggerItem(
      index: order++,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title, bordered: false, padding: headerPadding),
          inset(
            Container(
              // En dos paneles no hay filetes: solo la fila elegida.
              decoration: panes
                  ? null
                  : BoxDecoration(
                      border: Border(top: BorderSide(color: t.separator)),
                    ),
              child: Column(children: rows),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      body: StaggerScope(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: settingsColumnPadding(context),
            children: [
              ScreenHeader(title: l10n.navSettings),
              // El recuadro del apartado elegido viaja por detrás de las filas.
              SelectionScope(
                selectedId: panes ? selectedId : null,
                fill: t.soft,
                border: t.ink,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    group(l10n.settingsSectionFamily, [
                      section(
                        'people',
                        icon: SettingsIcons.people,
                        title: l10n.navPeople,
                        value: '${view.recipients.length}',
                      ),
                      section(
                        'givers',
                        icon: SettingsIcons.gift,
                        title: l10n.settingsGivers,
                        value: '${view.givers.length}',
                      ),
                      section(
                        'occasions',
                        icon: SettingsIcons.calendar,
                        title: l10n.navOccasions,
                        value: '${view.occasions.length}',
                      ),
                      section(
                        'archive',
                        icon: SettingsIcons.archive,
                        title: l10n.settingsArchive,
                        value: '$archived',
                      ),
                    ]),
                    if (isWeb)
                      // Como un grupo más: la cabecera con el margen de las
                      // demás y, debajo, las filas con su filete, dentro del
                      // mismo inset.
                      StaggerItem(
                        index: order++,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SectionHeader(
                              title: l10n.webSettingsTitle,
                              bordered: false,
                              padding: headerPadding,
                            ),
                            inset(
                              Container(
                                decoration: panes
                                    ? null
                                    : BoxDecoration(
                                        border: Border(
                                          top: BorderSide(color: t.separator),
                                        ),
                                      ),
                                child: WebSettingsSection(
                                  showHeader: false,
                                  actions: ref.watch(webGateActionsProvider),
                                  persistenceDenied: ref
                                      .watch(webDeviceStateProvider)
                                      .persistenceDenied,
                                  leading: [const LanguageRow(), appearanceRow],
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      group(l10n.settingsSectionDevice, [
                        // ADR 0004, «Yo»: de quién es este móvil. Solo local.
                        const SelfRecipientRow(),
                        section(
                          'security',
                          icon: SettingsIcons.lock,
                          title: l10n.settingsSecurity,
                          value: lockValue,
                        ),
                        const LanguageRow(),
                        appearanceRow,
                      ]),
                      group(l10n.settingsSectionShare, [
                        section(
                          'share',
                          icon: SettingsIcons.devices,
                          title: l10n.settingsShare,
                          value: devicesValue,
                        ),
                        section(
                          'backup',
                          icon: SettingsIcons.shield,
                          title: l10n.settingsBackup,
                        ),
                        section(
                          'recovery',
                          icon: SettingsIcons.key,
                          title: l10n.settingsRecovery,
                          value: recoveryRowValue(
                            l10n,
                            ref.watch(recoveryStatusProvider),
                          ),
                        ),
                      ]),
                    ],
                    group(l10n.settingsSectionAbout, [
                      // La guía de uso, a pantalla completa por encima de las
                      // pestañas; en la web no hay (se enseña en el móvil).
                      if (!isWeb)
                        SettingsRow(
                          icon: SettingsIcons.help,
                          title: l10n.tourTitle,
                          onTap: () => context.push('/tour?from=settings'),
                        ),
                      section(
                        'about',
                        icon: SettingsIcons.info,
                        title: l10n.settingsAboutApp,
                        value: kAppVersion,
                      ),
                    ]),
                    // Al final y apartado, en rojo: borra todo lo de este móvil
                    // tras una doble confirmación. En la web, «Olvidar este
                    // ordenador» hace ese papel.
                    if (!isWeb)
                      StaggerItem(
                        index: order++,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 28),
                          child: inset(
                            DecoratedBox(
                              decoration: panes
                                  ? const BoxDecoration()
                                  : BoxDecoration(
                                      border: Border(
                                        top: BorderSide(color: t.separator),
                                      ),
                                    ),
                              child: SettingsRow(
                                icon: SettingsIcons.trash,
                                title: l10n.eraseAllTitle,
                                hint: l10n.eraseAllHint,
                                danger: true,
                                chevron: false,
                                onTap: () => runEraseAll(context, ref),
                              ),
                            ),
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
    );
  }
}
