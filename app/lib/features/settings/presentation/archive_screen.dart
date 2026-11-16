import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/pane_scope.dart';
import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/section_header.dart';
import '../../../l10n/app_localizations.dart';
import 'manage_screens.dart';
import 'settings_column.dart';

/// Ajustes › Familia › Archivo: lo archivado de Personas, Quién regala y
/// Ocasiones en una sola pantalla, para recuperarlo o eliminarlo.
///
/// Cada grupo solo sale si tiene algo; la fila que se recupera o se elimina
/// se pliega como en las pantallas de gestionar.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key, this.embedded = false});

  /// Si va apilado en la columna de Ajustes del tablero de la web.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final deleted = ref.watch(recentlyDeletedProvider);
    void deletedGone(String id) =>
        ref.read(recentlyDeletedProvider.notifier).clear(id);

    List<ManageEntry> archivedOf(ManageList list) => [
      for (final e in list.entries)
        if (e.archived) e,
    ];
    final groups = <(String, List<ManageEntry>)>[
      (l10n.navPeople, archivedOf(managePeopleEntries(context, ref))),
      (l10n.settingsGivers, archivedOf(manageGiversEntries(context, ref))),
      (l10n.navOccasions, archivedOf(manageOccasionsEntries(context, ref))),
    ];
    final empty = groups.every((g) => g.$2.isEmpty);

    var order = 0;
    final body = <Widget>[
      for (final (title, entries) in groups)
        // El grupo se queda montado aunque se vacíe, para que su
        // última fila pueda plegarse; solo pierde la cabecera.
        StaggerItem(
          key: ValueKey<String>(title),
          index: order++,
          dy: 10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (entries.isNotEmpty)
                SectionHeader(
                  title: title,
                  trailing: '${entries.length}',
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                ),
              AnimatedRows(
                rows: [
                  for (final e in entries)
                    AnimatedRowItem(
                      id: e.id,
                      child: ManageRow(entry: e),
                    ),
                ],
                deleted: deleted,
                onDeletedGone: deletedGone,
              ),
            ],
          ),
        ),
      StaggerItem(
        index: order++,
        dy: 10,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(l10n.archiveNote, style: t.styles.meta),
        ),
      ),
    ];
    if (embedded) {
      return StaggerScope(
        animate: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EmbeddedSectionHeader(
              title: l10n.settingsArchive,
              subtitle: empty ? l10n.archiveEmpty : l10n.archiveSubtitle,
            ),
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
        step: const Duration(milliseconds: 40),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: settingsColumnPadding(context),
            children: [
              ScreenHeader(
                eyebrow: l10n.navSettings,
                title: l10n.settingsArchive,
                subtitle: empty ? l10n.archiveEmpty : l10n.archiveSubtitle,
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
