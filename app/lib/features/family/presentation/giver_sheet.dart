import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/model.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../../core/widgets/sheet_parts.dart' show SheetDoor;
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tabler_icons.dart' show tablerLink;
import '../../../l10n/app_localizations.dart';
import '../application/family_controller.dart';
import '../application/family_providers.dart';
import '../application/gift_logic.dart';
import 'family_texts.dart';
import 'giver_person_flow.dart';

/// Abre la hoja para dar de alta o cambiar a quien regala.
///
/// Devuelve el dato, o `null` si se cancela. No guarda nada, salvo enlazar o
/// desenlazar con una persona, que se confirma aparte y se guarda al momento.
Future<Giver?> showGiverSheet(
  BuildContext context, {
  Giver? initial,
  required int defaultColorIndex,
  bool householdPays = false,
}) => showEditSheet<Giver>(
  context,
  (_) => _GiverSheet(
    initial: initial,
    defaultColorIndex: defaultColorIndex,
    householdPays: householdPays,
  ),
);

class _GiverSheet extends ConsumerStatefulWidget {
  const _GiverSheet({
    required this.initial,
    required this.defaultColorIndex,
    required this.householdPays,
  });

  final Giver? initial;
  final int defaultColorIndex;
  final bool householdPays;

  @override
  ConsumerState<_GiverSheet> createState() => _GiverSheetState();
}

class _GiverSheetState extends ConsumerState<_GiverSheet> {
  late final TextEditingController _name;
  late bool _pays;
  bool _showError = false;
  bool _nameSeeded = false;

  /// El nombre que el campo tenía al cargarse o al actualizarse con lo que hay
  /// en el documento: si el texto sigue igual, la persona no lo ha tocado.
  String _baseName = '';

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _pays = widget.initial?.householdPays ?? widget.householdPays;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_nameSeeded) {
      return;
    }
    _nameSeeded = true;
    if (widget.initial != null) {
      final translated = giverNameFor(
        AppLocalizations.of(context),
        widget.initial,
      );
      _name.text = translated;
      _baseName = translated;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// El quién regala tal como está ahora (puede haberse enlazado o
  /// desenlazado con la hoja abierta).
  Giver? get _current {
    final initial = widget.initial;
    if (initial == null) {
      return null;
    }
    return ref.read(familyFullViewProvider).giversByOriginalId[initial.id] ??
        initial;
  }

  void _save() {
    final current = _current;
    // Enlazado, el nombre y el color son los de la persona: aquí no se editan
    // (el controlador los descartaría).
    if (current?.recipientId != null) {
      Navigator.of(context).pop(
        Giver(
          id: current!.id,
          name: current.name,
          colorIndex: current.colorIndex,
          householdPays: _pays,
          archived: current.archived,
        ),
      );
      return;
    }
    var name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    // Si el texto sigue como se cargó o se actualizó desde el documento (la
    // persona no lo ha tocado), se guarda el nombre que tiene ahora, sin
    // tocarlo (también el de serie con su traducción): no es un renombrado.
    if (current != null && name == _baseName.trim()) {
      name = current.name;
    }
    Navigator.of(context).pop(
      Giver(
        id: widget.initial?.id ?? newId(),
        name: name,
        colorIndex: current?.colorIndex ?? widget.defaultColorIndex,
        householdPays: _pays,
        archived: current?.archived ?? false,
      ),
    );
  }

  /// Elige una persona, confirma y enlaza este quién regala con ella.
  Future<void> _link(Giver giver) async {
    final l10n = AppLocalizations.of(context);
    final view = ref.read(familyFullViewProvider);
    final options = <PickerOption<String>>[
      for (final person in view.recipients)
        if (!person.archived)
          PickerOption(
            value: person.id,
            label: person.name,
            leading: PersonAvatar(
              name: person.name,
              colorIndex: person.colorIndex,
              size: 28,
            ),
            hint: view.giverForPerson(person.id) == null
                ? null
                : l10n.giverLinkExistingHint,
          ),
    ];
    final personId = await showPickerSheet<String>(
      context,
      title: l10n.giverLinkLabel,
      options: options,
    );
    if (personId == null || !mounted) {
      return;
    }
    final person = view.allRecipientsById[personId];
    if (person == null) {
      return;
    }
    final ok = await showRegalosAsk(
      context,
      title: l10n.giverLinkConfirmTitle(person.name),
      body: l10n.giverLinkConfirmBody(giverNameFor(l10n, giver), person.name),
      confirmLabel: l10n.giverLinkConfirm,
      cancelLabel: l10n.actionCancel,
    );
    if (!ok || !mounted) {
      return;
    }
    final changed = await _run(
      () => ref
          .read(familyControllerProvider.notifier)
          .linkGiver(giver.id, person.id, expectedPersonId: giver.recipientId),
    );
    if (changed && mounted) {
      setState(() {
        _name.text = person.name;
        _baseName = person.name;
      });
    }
  }

  /// Confirma y desenlaza este quién regala de su persona; conserva el nombre
  /// y el color de ahora.
  Future<void> _unlink(Giver giver, Recipient? person) async {
    final l10n = AppLocalizations.of(context);
    final name = person?.name ?? giver.name;
    final ok = await showRegalosAsk(
      context,
      title: l10n.giverUnlinkConfirmTitle(name),
      body: l10n.giverUnlinkConfirmBody(name),
      confirmLabel: l10n.giverUnlinkConfirm,
      cancelLabel: l10n.actionCancel,
    );
    if (!ok || !mounted) {
      return;
    }
    String? retainedName;
    try {
      retainedName = await ref
          .read(familyControllerProvider.notifier)
          .unlinkGiver(giver.id, expectedPersonId: giver.recipientId!);
    } on Object {
      if (mounted) {
        showRegalosSnackBar(
          context,
          SnackBar(content: Text(l10n.giverLinkError)),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    if (retainedName == null) {
      // Otro móvil ya lo había cambiado: se avisa y la hoja se refresca con
      // lo que hay ahora.
      showRegalosSnackBar(
        context,
        SnackBar(content: Text(l10n.giverUnlinkStale(name))),
      );
      _syncName(ref.read(familyFullViewProvider));
      setState(() {});
      return;
    }
    setState(() {
      _name.text = retainedName!;
      _baseName = retainedName;
    });
  }

  /// Mantiene el campo al día con el documento: enlazado, su nombre es el de
  /// la persona; si no, el que conserva ahora (por ejemplo tras un desenlace
  /// remoto). Si la persona ya había escrito otra cosa, se respeta.
  void _syncName(FamilyView view) {
    final initial = widget.initial;
    if (initial == null) {
      return;
    }
    final current = view.giversByOriginalId[initial.id];
    if (current == null) {
      return;
    }
    final person = current.recipientId == null
        ? null
        : view.allRecipientsById[current.recipientId];
    final now =
        person?.name ?? giverNameFor(AppLocalizations.of(context), current);
    final untouched = _name.text.trim() == _baseName.trim();
    if ((person != null || untouched) && _name.text != now) {
      _name.text = now;
    }
    if (person != null || untouched) {
      _baseName = now;
    }
  }

  Future<bool> _run(Future<bool> Function() change) async {
    final l10n = AppLocalizations.of(context);
    var changed = false;
    try {
      changed = await change();
    } on Object {
      changed = false;
    }
    if (!changed && mounted) {
      showRegalosSnackBar(
        context,
        SnackBar(content: Text(l10n.giverLinkError)),
      );
    }
    return changed;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(familyFullViewProvider, (_, view) => _syncName(view));
    final l10n = AppLocalizations.of(context);
    final full = ref.watch(familyFullViewProvider);
    final initial = widget.initial;
    final current = initial == null
        ? null
        : full.giversByOriginalId[initial.id] ?? initial;
    final personId = current?.recipientId;
    final person = personId == null ? null : full.allRecipientsById[personId];
    final linked = personId != null;
    return SheetFrame(
      title: initial == null ? l10n.giverNew : l10n.giverEdit,
      onSave: _save,
      children: [
        TextField(
          controller: _name,
          autofocus: initial == null,
          enabled: !linked,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l10n.fieldName,
            hintText: l10n.giverNameHint,
            helperText: linked
                ? l10n.giverLinkedNameHint(person?.name ?? _name.text)
                : null,
            helperMaxLines: 3,
            errorText: !linked && _showError && _name.text.trim().isEmpty
                ? l10n.fieldNameRequired
                : null,
          ),
          onChanged: (_) {
            if (_showError) {
              setState(() {});
            }
          },
        ),
        const SizedBox(height: 16),
        SwitchRow(
          title: l10n.giverHouseholdPays,
          hint: l10n.giverHouseholdPaysHint,
          value: _pays,
          onChanged: (v) => setState(() => _pays = v),
        ),
        if (current != null) ...[
          const SizedBox(height: 8),
          if (linked)
            SheetDoor(
              icon: AppIcons.ban,
              title: l10n.giverUnlinkLabel,
              hint: l10n.giverLinkedLine,
              onTap: () => _unlink(current, person),
            )
          else
            SheetDoor(
              icon: tablerLink,
              title: l10n.giverLinkLabel,
              hint: l10n.giverLinkHint,
              onTap: () => _link(current),
            ),
        ],
      ],
    );
  }
}
