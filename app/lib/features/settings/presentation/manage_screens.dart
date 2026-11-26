import '../../web_device/application/web_app_provider.dart';

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/dates.dart';
import '../../../core/layout/pane_scope.dart';
import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/wish_plan.dart' show WishPlanError;
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/giver_dot.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tag_label.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_actions.dart';
import '../../family/application/family_controller.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/gift_logic.dart';
import '../../family/domain/delete_impact.dart';
import '../../family/domain/family_errors.dart';
import '../../family/domain/next_occasion.dart';
import '../../family/presentation/family_texts.dart';
import '../../family/presentation/giver_person_flow.dart';
import '../../family/presentation/giver_sheet.dart';
import '../../family/presentation/occasion_sheet.dart';
import '../../family/presentation/person_sheet.dart';
import '../../web_device/application/web_sync_engine.dart'
    show WebOperationException;
import 'settings_column.dart';

/// Una fila de las pantallas de gestionar: se puede tocar para editar,
/// archivar o recuperar, y eliminar.
class ManageEntry {
  /// Crea la fila.
  const ManageEntry({
    required this.id,
    required this.title,
    required this.archived,
    required this.onEdit,
    required this.onToggleArchive,
    required this.onDelete,
    this.subtitle = '',
    this.leading,
    this.tag,
    this.lockedReason,
  });

  /// Si no es `null`, esto no se puede archivar ni eliminar, y esta frase
  /// dice por qué («Es la persona de este móvil.»): los dos botones salen
  /// desactivados y la frase va bajo el nombre. Recuperar algo ya archivado
  /// sigue pudiéndose.
  final String? lockedReason;

  /// Id del registro.
  final String id;

  /// Nombre.
  final String title;

  /// Línea pequeña bajo el nombre.
  final String subtitle;

  /// Adorno a la izquierda.
  final Widget? leading;

  /// Etiqueta junto al nombre.
  final String? tag;

  /// Si está archivado.
  final bool archived;

  /// Abre la edición.
  final VoidCallback onEdit;

  /// Archiva o recupera.
  final VoidCallback onToggleArchive;

  /// Pregunta y, si se confirma, elimina para siempre.
  final VoidCallback onDelete;
}

/// Las filas de una lista de gestionar y cómo se añade una nueva.
typedef ManageList = ({VoidCallback onAdd, List<ManageEntry> entries});

/// Pantalla de gestionar una lista: lo que está en uso y un botón para añadir.
/// Lo archivado se ve y se recupera en Ajustes › Archivo (`ArchiveScreen`).
/// Las filas se pliegan al archivarlas o eliminarlas (con la salida de borrado
/// en el último caso).
class ManageScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const ManageScreen({
    super.key,
    required this.title,
    required this.addLabel,
    required this.onAdd,
    required this.entries,
    this.embedded = false,
  });

  /// Si va apilado con los demás apartados en la columna de Ajustes del
  /// tablero de la web: sin `Scaffold`, sin lista propia y sin flecha de
  /// volver.
  final bool embedded;

  /// Título.
  final String title;

  /// Texto del botón de añadir.
  final String addLabel;

  /// Abre el alta.
  final VoidCallback onAdd;

  /// Todas las filas; las archivadas no se pintan aquí.
  final List<ManageEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final deleted = ref.watch(recentlyDeletedProvider);
    void deletedGone(String id) =>
        ref.read(recentlyDeletedProvider.notifier).clear(id);
    final active = [
      for (final e in entries)
        if (!e.archived) e,
    ];
    final panes = PaneScope.roleOf(context) == PaneRole.detail;
    final addButton = FilledButton.icon(
      onPressed: onAdd,
      style: panes || embedded
          ? FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
            )
          : null,
      icon: StrokeIcon(
        AppIcons.plus,
        size: 18,
        color: t.onFill,
        strokeWidth: 2.2,
      ),
      label: Text(addLabel),
    );
    final body = <Widget>[
      const SizedBox(height: 8),
      AnimatedRows(
        rows: [
          for (final e in active)
            AnimatedRowItem(
              id: e.id,
              child: ManageRow(entry: e, revealActions: embedded),
            ),
        ],
        deleted: deleted,
        onDeletedGone: deletedGone,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        // En el móvil, a todo el ancho con los márgenes de la lista; con
        // dos paneles, compacto y a la izquierda, a 16 como el título y
        // los filetes.
        child: panes || embedded
            ? Align(
                alignment: AlignmentDirectional.centerStart,
                child: addButton,
              )
            : addButton,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(l10n.manageArchiveHint, style: t.styles.meta),
      ),
    ];
    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EmbeddedSectionHeader(title: title),
          ...body,
        ],
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: settingsColumnPadding(context),
          children: [
            ScreenHeader(
              eyebrow: l10n.navSettings,
              title: title,
              backLabel: l10n.backTo(l10n.navSettings),
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/settings'),
            ),
            ...body,
          ],
        ),
      ),
    );
  }
}

/// Una fila de gestionar: nombre (se toca para editar) y los botones de
/// archivar o recuperar y de eliminar.
class ManageRow extends StatelessWidget {
  /// Crea la fila.
  const ManageRow({super.key, required this.entry, this.revealActions = false});

  /// Si «Archivar» y «Eliminar» solo se ven al pasar el ratón por la fila o con
  /// el foco dentro de ella (los apartados de Ajustes del tablero de la web de
  /// escritorio, `reglas-escritorio.md`, M7). Siguen al alcance del teclado.
  final bool revealActions;

  /// Lo que pinta y lo que hace.

  final ManageEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    // Rectángulos de radio 8: ni píldoras ni elipses al pulsar.
    const shape = RoundedRectangleBorder(borderRadius: RegalosShape.button);
    const padding = EdgeInsets.symmetric(horizontal: 10);
    final danger = t.danger;
    final locked = entry.lockedReason;
    final info = Semantics(
      container: true,
      button: true,
      label: [
        entry.title,
        if (entry.subtitle.isNotEmpty) entry.subtitle,
        ?locked,
      ].join('. '),
      excludeSemantics: true,
      onTap: entry.onEdit,
      child: InkWell(
        onTap: entry.onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(entry.title, style: t.styles.rowTitle),
                  if (entry.tag != null) TagLabel(entry.tag!),
                ],
              ),
              if (entry.subtitle.isNotEmpty)
                Text(entry.subtitle, style: t.styles.meta),
              if (locked != null) Text(locked, style: t.styles.meta),
            ],
          ),
        ),
      ),
    );
    final actions = [
      TextButton(
        style: TextButton.styleFrom(shape: shape, padding: padding),
        // Bloqueado no se archiva; recuperar lo ya archivado, sí.
        onPressed: locked != null && !entry.archived
            ? null
            : entry.onToggleArchive,
        child: Semantics(
          label: entry.archived
              ? l10n.manageRestoreLabel(entry.title)
              : l10n.manageArchiveLabel(entry.title),
          excludeSemantics: true,
          child: Text(entry.archived ? l10n.actionRestore : l10n.actionArchive),
        ),
      ),
      TextButton(
        style: TextButton.styleFrom(
          shape: shape,
          padding: padding,
          foregroundColor: danger,
        ),
        onPressed: locked != null ? null : entry.onDelete,
        child: Semantics(
          label: l10n.manageDeleteLabel(entry.title),
          excludeSemantics: true,
          child: Text(l10n.actionEliminate),
        ),
      ),
    ];
    // Con el texto muy grande los dos botones no caben junto al nombre: pasan
    // a una línea propia bajo él.
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 17;
    // Con dos paneles, los filetes, los nombres, el título y el botón de
    // añadir van todos a 16 de cada borde de la columna.
    final panes = PaneScope.roleOf(context) == PaneRole.detail;
    Widget row(bool visible) => _row(
      context,
      t: t,
      info: info,
      actions: actions,
      visible: visible,
      stacked: stacked,
      panes: panes,
    );
    return revealActions ? _RevealOnHover(builder: row) : row(true);
  }

  Widget _row(
    BuildContext context, {
    required RegalosTokens t,
    required Widget info,
    required List<Widget> actions,
    required bool visible,
    required bool stacked,
    required bool panes,
  }) {
    final shown = AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: RegalosMotion.fade,
      child: IgnorePointer(
        ignoring: !visible,
        child: Row(mainAxisSize: MainAxisSize.min, children: actions),
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      margin: panes ? const EdgeInsets.symmetric(horizontal: 16) : null,
      padding: EdgeInsets.only(left: panes ? 0 : 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.separator)),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (entry.leading != null) ...[
                      entry.leading!,
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: info),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(children: [shown, const SizedBox(width: 6)]),
                ),
              ],
            )
          : Row(
              children: [
                if (entry.leading != null) ...[
                  entry.leading!,
                  const SizedBox(width: 12),
                ],
                Expanded(child: info),
                shown,
                const SizedBox(width: 6),
              ],
            ),
    );
  }
}

/// Enseña lo de dentro solo con el ratón encima o el foco en alguno de sus
/// controles.
class _RevealOnHover extends StatefulWidget {
  const _RevealOnHover({required this.builder});

  final Widget Function(bool visible) builder;

  @override
  State<_RevealOnHover> createState() => _RevealOnHoverState();
}

class _RevealOnHoverState extends State<_RevealOnHover> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) => setState(() => _focus = value),
        child: widget.builder(_hover || _focus),
      ),
    );
  }
}

/// Ajustes › Personas: renombrar, cambiar color, archivar y eliminar.
class ManagePeopleScreen extends ConsumerWidget {
  const ManagePeopleScreen({super.key, this.embedded = false});

  /// Si va apilado en la columna de Ajustes del tablero de la web.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final list = managePeopleEntries(context, ref);
    return ManageScreen(
      embedded: embedded,
      title: l10n.navPeople,
      addLabel: l10n.obPeopleAdd,
      onAdd: list.onAdd,
      entries: list.entries,
    );
  }
}

/// Las filas de Personas (también las archivadas) y el alta.
ManageList managePeopleEntries(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  final full = ref.watch(familyFullViewProvider);
  final family = ref.watch(familyStateProvider);
  final controller = ref.read(familyControllerProvider.notifier);

  // A la persona de un móvil de la familia no se la archiva ni se la
  // elimina: la fila lo dice y sus botones salen desactivados.
  String? lockedReason(Recipient person) =>
      switch (family?.devicePersonOwner(person.id)) {
        DevicePersonOwner.thisDevice =>
          ref.read(webAppProvider)
              ? l10n.manageLockedThisDeviceWeb
              : l10n.manageLockedThisDevice,
        DevicePersonOwner.otherDevice => l10n.manageLockedOtherDevice,
        null => null,
      };

  Future<void> edit(Recipient? person) async {
    final result = await showPersonSheet(
      context,
      initial: person,
      defaultColorIndex: full.recipients.length,
    );
    if (result != null) {
      await saveRecipient(ref, l10n, result);
    }
  }

  return (
    onAdd: () => edit(null),
    entries: [
      for (final p in full.recipients)
        ManageEntry(
          id: p.id,
          title: p.name,
          archived: p.archived,
          lockedReason: lockedReason(p),
          leading: PersonAvatar(name: p.name, colorIndex: p.colorIndex),
          subtitle: [
            ?p.relation,
            if (p.birthMonth != null && p.birthDay != null)
              shortDayMonth(p.birthMonth!, p.birthDay!, l10n.localeName),
          ].join(' · '),
          onEdit: () => edit(p),
          onToggleArchive: () async {
            try {
              await controller.archiveRecipient(p.id, archived: !p.archived);
            } on DevicePersonException catch (error) {
              if (context.mounted) {
                await _showDevicePersonBlocked(context, ref, error);
              }
            }
          },
          onDelete: () async {
            final impact = await controller.recipientDeleteImpact(p.id);
            if (!context.mounted) return;
            await _confirmImpactDelete(
              context,
              ref,
              id: p.id,
              title: l10n.deletePersonTitle(p.name),
              impact: impact,
              refresh: () => controller.recipientDeleteImpact(p.id),
              body: (impact) => [
                l10n.deletePersonGifts(impact.gifts),
                if (impact.wishes > 0) l10n.deletePersonWishes(impact.wishes),
                if (impact.hasBirthday) l10n.deleteBirthdayToo,
                if (impact.hasRequests) l10n.deleteRequestedByToo,
                if (impact.hasLinkedGiver) l10n.deletePersonLinkedGiver,
              ],
              delete: (impact) =>
                  controller.deleteRecipient(p.id, expectedImpact: impact),
            );
          },
        ),
    ],
  );
}

/// Ajustes › Quién regala: renombrar, decidir si paga la casa, archivar y
/// eliminar.
class ManageGiversScreen extends ConsumerWidget {
  const ManageGiversScreen({super.key, this.embedded = false});

  /// Si va apilado en la columna de Ajustes del tablero de la web.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final list = manageGiversEntries(context, ref);
    return ManageScreen(
      embedded: embedded,
      title: l10n.settingsGivers,
      addLabel: l10n.giverNew,
      onAdd: list.onAdd,
      entries: list.entries,
    );
  }
}

/// Las filas de Quién regala (también las archivadas) y el alta.
ManageList manageGiversEntries(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  final full = ref.watch(familyFullViewProvider);
  final controller = ref.read(familyControllerProvider.notifier);

  Future<void> edit(Giver? giver) async {
    final result = await showGiverSheet(
      context,
      initial: giver,
      defaultColorIndex: full.allGivers.length,
    );
    if (result != null) {
      await controller.upsertGiver(result);
    }
  }

  return (
    onAdd: () => edit(null),
    entries: [
      for (final g in full.allGivers)
        ManageEntry(
          id: g.id,
          title: giverNameFor(l10n, g),
          archived: g.archived,
          tag: g.householdPays ? l10n.giverHouseholdPays : null,
          subtitle: g.recipientId == null ? '' : l10n.giverLinkedLine,
          leading: SizedBox.square(
            dimension: 40,
            child: Center(child: GiverDot(colorIndex: g.colorIndex, size: 14)),
          ),
          onEdit: () => edit(g),
          onToggleArchive: () =>
              controller.archiveGiver(g.id, archived: !g.archived),
          onDelete: () async {
            final impact = await controller.giverAliasDeleteImpact(g.id);
            if (!context.mounted) return;
            await _confirmImpactDelete(
              context,
              ref,
              id: g.id,
              title: l10n.deletePersonTitle(giverNameFor(l10n, g)),
              impact: impact,
              refresh: () => controller.giverAliasDeleteImpact(g.id),
              body: (impact) => _giverDeleteBody(l10n, impact),
              delete: (impact) =>
                  controller.deleteGiverAlias(g.id, expectedImpact: impact),
            );
          },
        ),
    ],
  );
}

/// Ajustes › Ocasiones: renombrar, cambiar la fecha, archivar y eliminar.
class ManageOccasionsScreen extends ConsumerWidget {
  const ManageOccasionsScreen({super.key, this.embedded = false});

  /// Si va apilado en la columna de Ajustes del tablero de la web.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final list = manageOccasionsEntries(context, ref);
    return ManageScreen(
      embedded: embedded,
      title: l10n.navOccasions,
      addLabel: l10n.occasionNew,
      onAdd: list.onAdd,
      entries: list.entries,
    );
  }
}

/// Las filas de Ocasiones (también las archivadas) y el alta.
ManageList manageOccasionsEntries(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  final full = ref.watch(familyFullViewProvider);
  final controller = ref.read(familyControllerProvider.notifier);
  final labels = OccasionLabels(l10n, full.recipientsById);

  Future<void> edit(Occasion? occasion) async {
    final result = await showOccasionSheet(
      context,
      initial: occasion,
      initialName: occasion == null ? null : labels.of(occasion),
    );
    if (result != null) {
      await controller.upsertOccasion(result, original: occasion);
    }
  }

  return (
    onAdd: () => edit(null),
    entries: [
      for (final o in occasionsByNextDate(full.occasions, clock.now()))
        ManageEntry(
          id: o.id,
          title: labels.of(o),
          archived: o.archived,
          subtitle: longDayMonth(
            occasionDayMonth(o, clock.now()).month,
            occasionDayMonth(o, clock.now()).day,
            l10n.localeName,
          ),
          onEdit: () => edit(o),
          onToggleArchive: () =>
              controller.archiveOccasion(o.id, archived: !o.archived),
          onDelete: () {
            final impact = DeleteImpact.ofOccasion(
              ref.read(familyFullViewProvider),
              o.id,
            );
            _confirmDelete(
              context,
              ref,
              id: o.id,
              title: l10n.deleteOccasionTitle(labels.of(o)),
              body: [l10n.deleteOccasionGifts(impact.gifts)],
              delete: () => controller.deleteOccasion(o.id),
            );
          },
        ),
    ],
  );
}

/// Lo que se espera a que se recalcule lo que se elimina con el aviso abierto.
const Duration _impactRefreshLimit = Duration(seconds: 2);

/// Cuántos títulos de regalos caben en el diálogo de eliminar a quien regala.
const int _shownGiftTitles = 5;

/// Lo que dice el diálogo de eliminar a quien regala: qué registros se
/// eliminan (si son varios), cuántos regalos se quedan sin quién regala y
/// cuáles, y que la persona enlazada sigue en Personas.
List<String> _giverDeleteBody(AppLocalizations l10n, DeleteImpact impact) {
  final rows = [
    for (final alias in impact.affectedAliases)
      '«${giverNameFor(l10n, alias)}»',
  ];
  final titles = [for (final gift in impact.affectedGifts) '«${gift.title}»'];
  final linked = impact.affectedAliases
      .where((alias) => alias.recipientId != null)
      .firstOrNull;
  return [
    if (rows.length > 1) l10n.deleteGiverRows(rows.length, rows.join(', ')),
    l10n.deleteGiverGifts(impact.gifts),
    if (titles.isNotEmpty)
      l10n.deleteGiverGiftTitles(
        titles.take(_shownGiftTitles).join(', '),
        titles.length > _shownGiftTitles ? titles.length - _shownGiftTitles : 0,
      ),
    if (linked != null && impact.linkedPersonExists)
      l10n.deleteGiverLinkedNote(linked.name),
    if (impact.paysFromHousehold) l10n.deleteGiverBudget,
  ];
}

/// Avisa de que una persona con móvil propio no se puede eliminar ni archivar
/// desde aquí.
Future<void> _showDevicePersonBlocked(
  BuildContext context,
  WidgetRef ref,
  DevicePersonException error,
) {
  final l10n = AppLocalizations.of(context);
  final name =
      ref
          .read(familyFullViewProvider)
          .allRecipientsById[error.recipientId]
          ?.name ??
      '';
  final thisDevice = error.owner == DevicePersonOwner.thisDevice;
  // En la web, «este ordenador»; allí no se elige de quién es en Ajustes.
  final web = ref.read(webAppProvider);
  return showRegalosNotice(
    context,
    title: thisDevice
        ? (web
              ? l10n.devicePersonBlockedThisTitleWeb(name)
              : l10n.devicePersonBlockedThisTitle(name))
        : l10n.devicePersonBlockedOtherTitle(name),
    body: thisDevice
        ? (web
              ? l10n.devicePersonBlockedThisBodyWeb(name)
              : l10n.devicePersonBlockedThisBody(name))
        : l10n.devicePersonBlockedOtherBody(name),
    okLabel: l10n.actionUnderstood,
  );
}

/// Como [_confirmDelete], pero comprobando contra el [impact] que se enseñó:
/// si cuando se confirma lo que se elimina ha cambiado (otro móvil), el
/// diálogo se vuelve a abrir con lo nuevo y pide confirmar de nuevo. Si la
/// persona resulta ser la de un móvil de la familia, lo explica. Con el
/// diálogo abierto, si cambia lo que se ve (otro móvil, o este móvil pierde la
/// autorización sobre algún regalo), se cierra y vuelve a abrirse con lo de
/// ahora: nunca queda a la vista contenido que ya no se puede ver.
Future<void> _confirmImpactDelete(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String title,
  required DeleteImpact impact,
  required Future<DeleteImpact> Function() refresh,
  required List<String> Function(DeleteImpact impact) body,
  required Future<void> Function(DeleteImpact impact) delete,
}) async {
  final l10n = AppLocalizations.of(context);
  final haptics = ref.read(hapticsProvider);
  var current = impact;
  var changed = false;
  // Cada cambio que llega cuenta una generación: solo vale el recálculo de la
  // más reciente, aunque el diálogo se haya reabierto entre tanto.
  var generation = 0;
  while (true) {
    var open = true;
    var failed = false;
    // `null` es «comprobando»: el diálogo no enseña títulos ni recuentos.
    final shown = ValueNotifier<({DeleteImpact? impact, bool changed})>((
      impact: current,
      changed: changed,
    ));
    var lastShown = current;
    final subscription = ref.listenManual(familyFullViewProvider, (_, _) async {
      final mine = ++generation;
      shown.value = (impact: null, changed: shown.value.changed);
      try {
        final latest = await refresh().timeout(_impactRefreshLimit);
        if (!open || failed || mine != generation) {
          return;
        }
        final differs = !latest.matches(lastShown);
        lastShown = latest;
        shown.value = (impact: latest, changed: shown.value.changed || differs);
      } on Object {
        // No se pudo recalcular (falla o tarda): el aviso no se queda con
        // títulos y recuentos que quizá ya no se pueden ver.
        if (open && !failed && mine == generation && context.mounted) {
          failed = true;
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    });
    // «Eliminar» devuelve el impacto que se estaba enseñando; cancelar, `null`.
    final confirmed = await showRegalosDialog<DeleteImpact>(
      context,
      avoidKeyboard: false,
      builder: (dialogContext) =>
          _ImpactDialog(title: title, shown: shown, body: body, l10n: l10n),
    );
    open = false;
    subscription.close();
    shown.dispose();
    if (failed) {
      if (context.mounted) {
        showRegalosSnackBar(
          context,
          SnackBar(content: Text(l10n.deleteImpactUnavailable)),
        );
      }
      return;
    }
    if (confirmed == null || !context.mounted) {
      return;
    }
    // Se borra con el impacto que el usuario vio: si ha cambiado aunque sea
    // un instante antes, el controlador lanza `DeleteImpactChanged`.
    current = confirmed;
    haptics.medium();
    final deleted = ref.read(recentlyDeletedProvider.notifier)..add(id);
    try {
      await delete(current);
      return;
    } on DeleteImpactChanged catch (error) {
      deleted.clear(id);
      current = error.current;
      changed = true;
    } on DevicePersonException catch (error) {
      deleted.clear(id);
      if (context.mounted) {
        await _showDevicePersonBlocked(context, ref, error);
      }
      return;
    } on Object catch (error) {
      deleted.clear(id);
      if (context.mounted) {
        showRegalosSnackBar(
          context,
          SnackBar(content: Text(_deleteFailureText(l10n, error))),
        );
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
  }
}

/// El diálogo de [_confirmImpactDelete]: enseña lo que se elimina mientras se
/// sabe; con un cambio en marcha no enseña nada («Comprobando…») y no deja
/// confirmar hasta tener el resultado más reciente.
class _ImpactDialog extends StatelessWidget {
  const _ImpactDialog({
    required this.title,
    required this.shown,
    required this.body,
    required this.l10n,
  });

  final String title;
  final ValueNotifier<({DeleteImpact? impact, bool changed})> shown;
  final List<String> Function(DeleteImpact impact) body;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return RegalosDialogSurface(
      scrollable: true,
      child: ValueListenableBuilder(
        valueListenable: shown,
        builder: (context, state, _) {
          final impact = state.impact;
          final text = impact == null
              ? l10n.deleteImpactChecking
              : [
                  if (state.changed) l10n.deleteImpactChanged,
                  ...body(impact).where((part) => part.isNotEmpty),
                  l10n.deleteIrreversible,
                ].join(' ');
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: t.styles.screenTitleSmall),
              ),
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(text, style: t.styles.body),
              ),
              const SizedBox(height: 20),
              DialogButtonRow(
                cancelLabel: l10n.actionCancel,
                confirmLabel: l10n.actionEliminate,
                cancel: OutlinedButton(
                  style: regalosDialogCancelStyle(t),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.actionCancel),
                ),
                confirm: FilledButton(
                  style: regalosDialogDangerStyle(t),
                  onPressed: impact == null
                      ? null
                      : () => Navigator.of(context).pop(impact),
                  child: Text(l10n.actionEliminate),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Pregunta antes de eliminar y, si se confirma, apunta la fila como borrada
/// (para que se pliegue con la salida de borrado) y ejecuta [delete].
///
/// [body] dice la consecuencia; el diálogo añade siempre que no se puede
/// deshacer.
Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String title,
  required List<String> body,
  required Future<void> Function() delete,
}) async {
  final l10n = AppLocalizations.of(context);
  final haptics = ref.read(hapticsProvider);
  final ok = await showRegalosConfirm(
    context,
    title: title,
    body: [
      ...body.where((part) => part.isNotEmpty),
      l10n.deleteIrreversible,
    ].join(' '),
    confirmLabel: l10n.actionEliminate,
    cancelLabel: l10n.actionCancel,
  );
  if (!ok || !context.mounted) {
    return;
  }
  haptics.medium();
  final deleted = ref.read(recentlyDeletedProvider.notifier)..add(id);
  try {
    await delete();
  } on Object catch (error) {
    // No se guardó: la fila vuelve a ser una fila normal y se avisa.
    deleted.clear(id);
    if (context.mounted) {
      showRegalosSnackBar(
        context,
        SnackBar(content: Text(_deleteFailureText(l10n, error))),
      );
    }
  }
}

/// Por qué no se eliminó: si algún móvil de la familia aún no entiende los
/// planes de deseos, un reintento no lo arregla y se dice; si no, el aviso
/// genérico.
String _deleteFailureText(AppLocalizations l10n, Object error) =>
    switch (error) {
      WishPlanError.devicesNeedUpdate => l10n.deleteDevicesNeedUpdate,
      WebOperationException(operation: 'deleteProtectedReferences') =>
        l10n.webOperationUnavailable,
      _ => l10n.deleteError,
    };
