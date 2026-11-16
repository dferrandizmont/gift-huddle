import 'package:flutter/material.dart';

import '../../../core/sync/model.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../../l10n/app_localizations.dart';
import '../application/gift_logic.dart';
import 'family_texts.dart';

/// Abre la hoja para dar de alta o cambiar a quien regala.
///
/// Devuelve el dato, o `null` si se cancela. No guarda nada.
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

class _GiverSheet extends StatefulWidget {
  const _GiverSheet({
    required this.initial,
    required this.defaultColorIndex,
    required this.householdPays,
  });

  final Giver? initial;
  final int defaultColorIndex;
  final bool householdPays;

  @override
  State<_GiverSheet> createState() => _GiverSheetState();
}

class _GiverSheetState extends State<_GiverSheet> {
  late final TextEditingController _name;
  late bool _pays;
  bool _showError = false;
  bool _nameSeeded = false;

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
      final translated = giverDisplayName(
        AppLocalizations.of(context),
        widget.initial!.name,
      );
      _name.text = translated;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    var name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    // Si el que regala es de serie y no se ha cambiado el texto (sigue la
    // traducción mostrada), se guarda el nombre original sin tocarlo, para no
    // considerarlo un renombrado.
    if (widget.initial != null) {
      final l10n = AppLocalizations.of(context);
      final displayed = giverDisplayName(l10n, widget.initial!.name).trim();
      if (name == displayed) {
        name = widget.initial!.name;
      }
    }
    Navigator.of(context).pop(
      Giver(
        id: widget.initial?.id ?? newId(),
        name: name,
        colorIndex: widget.initial?.colorIndex ?? widget.defaultColorIndex,
        householdPays: _pays,
        archived: widget.initial?.archived ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SheetFrame(
      title: widget.initial == null ? l10n.giverNew : l10n.giverEdit,
      onSave: _save,
      children: [
        TextField(
          controller: _name,
          autofocus: widget.initial == null,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l10n.fieldName,
            hintText: l10n.giverNameHint,
            errorText: _showError && _name.text.trim().isEmpty
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
      ],
    );
  }
}
