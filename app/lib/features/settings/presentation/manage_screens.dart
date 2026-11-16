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
import '../../family/presentation/giver_sheet.dart';
import '../../family/presentation/occasion_sheet.dart';
import '../../family/presentation/person_sheet.dart';
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
        DevicePersonOwner.thisDevice => l10n.manageLockedThisDevice,
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
          onToggleArchive: () =>
              controller.archiveRecipient(p.id, archived: !p.archived),
          onDelete: () {
            final impact = DeleteImpact.ofRecipient(
              ref.read(familyFullViewProvider),
              p.id,
            );
            _confirmDelete(
              context,
              ref,
              id: p.id,
              title: l10n.deletePersonTitle(p.name),
              body: [
                l10n.deletePersonGifts(impact.gifts),
                if (impact.hasBirthday) l10n.deleteBirthdayToo,
                if (impact.hasRequests) l10n.deleteRequestedByToo,
              ],
              delete: () => controller.deleteRecipient(p.id),
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
      defaultColorIndex: full.givers.length,
    );
    if (result != null) {
      await controller.upsertGiver(result);
    }
  }

  return (
    onAdd: () => edit(null),
    entries: [
      for (final g in full.givers)
        ManageEntry(
          id: g.id,
          title: giverNameFor(l10n, g),
          archived: g.archived,
          tag: g.householdPays ? l10n.giverHouseholdPays : null,
          leading: SizedBox.square(
            dimension: 40,
            child: Center(child: GiverDot(colorIndex: g.colorIndex, size: 14)),
          ),
          onEdit: () => edit(g),
          onToggleArchive: () =>
              controller.archiveGiver(g.id, archived: !g.archived),
          onDelete: () {
            final impact = DeleteImpact.ofGiver(
              ref.read(familyFullViewProvider),
              g.id,
            );
            _confirmDelete(
              context,
              ref,
              id: g.id,
              title: l10n.deletePersonTitle(giverNameFor(l10n, g)),
              body: [
                l10n.deleteGiverGifts(impact.gifts),
                if (impact.paysFromHousehold) l10n.deleteGiverBudget,
              ],
              delete: () => controller.deleteGiver(g.id),
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
      await controller.upsertOccasion(result);
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
  } on Object {
    // No se guardó: la fila vuelve a ser una fila normal y se avisa.
    deleted.clear(id);
    if (context.mounted) {
      showRegalosSnackBar(context, SnackBar(content: Text(l10n.deleteError)));
    }
  }
}
