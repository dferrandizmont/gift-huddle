import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/pane_selection.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/pane_list_row.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/about_screen.dart';
import '../../settings/presentation/appearance_screen.dart';
import '../../settings/presentation/archive_screen.dart';
import '../../settings/presentation/language_row.dart';
import '../../settings/presentation/manage_screens.dart';
import '../../settings/presentation/settings_column.dart';
import '../../web_device/application/web_device_providers.dart';
import '../../web_device/presentation/web_settings_section.dart';
import 'board_page.dart';
import 'board_scope.dart';

/// Los apartados de Ajustes en el tablero de la web, por orden.
const List<String> kBoardSettingsSections = <String>[
  'people',
  'givers',
  'occasions',
  'archive',
  'computer',
  'appearance',
  'about',
];

/// Ajustes en el tablero de la web (la guía de diseño de escritorio,
/// A): todos los apartados apilados en una sola columna que se desplaza, con un
/// índice a la izquierda que salta a cada uno y marca el que se ve.
///
/// Cada apartado es la misma pantalla de siempre en su variante `embedded`
/// (sin `Scaffold` ni lista propia). Con [section] (la dirección
/// `/settings/appearance`) se abre ya desplazado a ese apartado.
class BoardSettingsScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const BoardSettingsScreen({super.key, this.section});

  /// El apartado al que se abre desplazado, si hay.
  final String? section;

  @override
  ConsumerState<BoardSettingsScreen> createState() =>
      _BoardSettingsScreenState();
}

class _BoardSettingsScreenState extends ConsumerState<BoardSettingsScreen> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _viewport = GlobalKey();
  final Map<String, GlobalKey> _keys = {
    for (final id in kBoardSettingsSections) id: GlobalKey(),
  };
  String _active = kBoardSettingsSections.first;

  /// Mientras el desplazamiento lo manda un toque en el índice, el índice no
  /// se mueve solo.
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    final section = widget.section;
    if (section != null && _keys.containsKey(section)) {
      _active = section;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _goTo(section, animate: false);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _goTo(String id, {bool animate = true}) async {
    final target = _keys[id]?.currentContext;
    if (target == null) {
      return;
    }
    setState(() => _active = id);
    final reduce = RegalosMotion.of(context).reduce;
    _jumping = true;
    try {
      await Scrollable.ensureVisible(
        target,
        duration: animate && !reduce
            ? const Duration(milliseconds: 375)
            : Duration.zero,
        curve: Curves.easeOutCubic,
      );
    } finally {
      _jumping = false;
    }
  }

  /// El apartado que se ve: el último cuya cabecera ya pasó del borde de
  /// arriba; al llegar al final, el último.
  void _updateActive() {
    if (_jumping || !_scroll.hasClients) {
      return;
    }
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) {
      return;
    }
    final top = viewport.localToGlobal(Offset.zero).dy;
    var active = kBoardSettingsSections.first;
    for (final id in kBoardSettingsSections) {
      final box = _keys[id]!.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.attached &&
          box.localToGlobal(Offset.zero).dy - top <= 48) {
        active = id;
      }
    }
    final position = _scroll.position;
    if (position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 4) {
      active = kBoardSettingsSections.last;
    }
    if (active != _active) {
      setState(() => _active = active);
    }
  }

  String _label(AppLocalizations l10n, String id) => switch (id) {
    'people' => l10n.navPeople,
    'givers' => l10n.settingsGivers,
    'occasions' => l10n.navOccasions,
    'archive' => l10n.settingsArchive,
    'computer' => l10n.webSettingsTitle,
    'appearance' => l10n.settingsAppearance,
    _ => l10n.settingsAbout,
  };

  Widget _content(String id) => switch (id) {
    'people' => const ManagePeopleScreen(embedded: true),
    'givers' => const ManageGiversScreen(embedded: true),
    'occasions' => const ManageOccasionsScreen(embedded: true),
    'archive' => const ArchiveScreen(embedded: true),
    'computer' => const _ComputerSection(),
    'appearance' => const AppearanceScreen(embedded: true),
    _ => const AboutScreen(embedded: true),
  };

  Widget _index(AppLocalizations l10n, RegalosTokens t) => SizedBox(
    width: 200,
    child: Semantics(
      container: true,
      label: l10n.boardSettingsIndex,
      child: SelectionScope(
        selectedId: _active,
        fill: t.soft,
        border: t.ink,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final id in kBoardSettingsSections)
              PaneListRow(
                id: id,
                label: _label(l10n, id),
                selected: id == _active,
                minHeight: 44,
                onTap: () => _goTo(id),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _label(l10n, id),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.styles.label.copyWith(
                      color: id == _active ? t.ink : t.text,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _column() => SingleChildScrollView(
    key: _viewport,
    controller: _scroll,
    padding: const EdgeInsets.only(bottom: 48),
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final id in kBoardSettingsSections)
              _Section(
                key: _keys[id],
                first: id == kBoardSettingsSections.first,
                child: _content(id),
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return BoardCoveredGuard(
      child: ColoredBox(
        color: t.bg,
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                BoardScope.marginOf(context),
                BoardPage.top,
                BoardScope.marginOf(context),
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.navSettings,
                        style: t.styles.screenTitle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _index(l10n, t),
                        const SizedBox(width: 24),
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (_) {
                              _updateActive();
                              return false;
                            },
                            child: _column(),
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
      ),
    );
  }
}

/// Un apartado de la columna: un filete y 24 de aire por encima y por debajo
/// del filete (el primero, sin filete).
class _Section extends StatelessWidget {
  const _Section({super.key, required this.first, required this.child});

  final bool first;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: t.separator)),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: first ? 0 : 24),
          child: child,
        ),
      ),
    );
  }
}

/// «Este ordenador»: idioma, cambiar el PIN, bloquear y olvidar el ordenador.
class _ComputerSection extends ConsumerWidget {
  const _ComputerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmbeddedSectionHeader(title: l10n.webSettingsTitle),
        WebSettingsSection(
          showHeader: false,
          actions: ref.watch(webGateActionsProvider),
          persistenceDenied: ref
              .watch(webDeviceStateProvider)
              .persistenceDenied,
          leading: const [LanguageRow()],
        ),
      ],
    );
  }
}
