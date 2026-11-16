import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/motion/haptics.dart';
import '../../../core/motion/pop_in.dart';
import '../../../core/motion/unfold_section.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/accent_palette.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/presentation/appearance_screen.dart';
import '../application/gift_logic.dart';
import 'protection_sheet.dart';

/// Abre la hoja para dar de alta o cambiar una persona.
///
/// Devuelve la persona con sus datos, o `null` si se cancela. No guarda nada:
/// quien llama decide.
Future<Recipient?> showPersonSheet(
  BuildContext context, {
  Recipient? initial,
  required int defaultColorIndex,
}) => showEditSheet<Recipient>(
  context,
  (_) => _PersonSheet(initial: initial, defaultColorIndex: defaultColorIndex),
);

class _PersonSheet extends StatefulWidget {
  const _PersonSheet({required this.initial, required this.defaultColorIndex});

  final Recipient? initial;
  final int defaultColorIndex;

  @override
  State<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends State<_PersonSheet> {
  late final TextEditingController _name;
  late final TextEditingController _relation;
  late int _color;
  int? _month;
  int? _day;
  int? _year;
  bool _skipYear = false;
  bool _showNameError = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _name = TextEditingController(text: p?.name ?? '');
    _relation = TextEditingController(text: p?.relation ?? '');
    _color = p?.colorIndex ?? widget.defaultColorIndex;
    _month = p?.birthMonth;
    _day = p?.birthDay;
    _year = p?.birthYear;
    _skipYear = p != null && p.birthMonth != null && p.birthYear == null;
  }

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = clock.now();
    final initial = _month != null && _day != null
        ? DateTime(_year ?? now.year, _month!, _day!)
        : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(1900),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null && mounted) {
      setState(() {
        _month = picked.month;
        _day = picked.day;
        _year = picked.year;
      });
    }
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _showNameError = true);
      return;
    }
    final relation = _relation.text.trim();
    Navigator.of(context).pop(
      Recipient(
        id: widget.initial?.id ?? newId(),
        name: name,
        colorIndex: _color,
        relation: relation.isEmpty ? null : relation,
        birthMonth: _month,
        birthDay: _day,
        birthYear: _month == null || _skipYear ? null : _year,
        archived: widget.initial?.archived ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final hasDate = _month != null && _day != null;
    final dateText = hasDate
        ? DateFormat.yMMMMd(l10n.localeName)
              .format(DateTime(_year ?? 2000, _month!, _day!))
        : l10n.personBirthdayNone;
    final dateTextShown = hasDate && _skipYear
        ? DateFormat.MMMMd(l10n.localeName)
              .format(DateTime(2000, _month!, _day!))
        : dateText;
    return SheetFrame(
      title: widget.initial == null ? l10n.personNew : l10n.personEdit,
      onSave: _save,
      children: [
        TextField(
          controller: _name,
          autofocus: widget.initial == null,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.fieldName,
            errorText: _showNameError && _name.text.trim().isEmpty
                ? l10n.fieldNameRequired
                : null,
          ),
          onChanged: (_) {
            if (_showNameError) {
              setState(() {});
            }
          },
        ),
        const SizedBox(height: 16),
        Text(l10n.personColor, style: t.styles.label),
        const SizedBox(height: 4),
        ColorChoice(
          selected: _color,
          onSelected: (i) => setState(() => _color = i),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _relation,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.personRelation,
            hintText: l10n.personRelationHint,
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.personBirthday, style: t.styles.label),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pickDate,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(44, 48),
                  foregroundColor: t.text,
                  side: BorderSide(color: t.controlBorder),
                  alignment: Alignment.centerLeft,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  hasDate ? dateTextShown : l10n.personBirthdayPick,
                  style: t.styles.body,
                ),
              ),
            ),
            if (hasDate)
              Semantics(
                button: true,
                label: l10n.personBirthdayClear,
                excludeSemantics: true,
                child: SizedBox.square(
                  dimension: 48,
                  child: InkResponse(
                    onTap: () => setState(() {
                      _month = null;
                      _day = null;
                      _year = null;
                    }),
                    child: Center(
                      child: StrokeIcon(
                        AppIcons.close,
                        color: t.text,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        // «Sin año» se despliega al poner una fecha.
        UnfoldSection(
          show: hasDate,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _skipYear,
            title: Text(l10n.personBirthdayNoYear, style: t.styles.body),
            onChanged: (v) {
              context.haptics.selection();
              setState(() => _skipYear = v ?? false);
            },
          ),
        ),
        // Regalos en secreto: solo al editar a una persona que ya existe y si
        // la familia lo admite (la fila no sale en otro caso).
        if (widget.initial != null) ...[
          const SizedBox(height: 8),
          ProtectionRow(personId: widget.initial!.id),
        ],
      ],
    );
  }
}

/// Las seis muestras de color para una persona.
class ColorChoice extends StatelessWidget {
  const ColorChoice({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    void select(int i) {
      if (i != selected) {
        context.haptics.selection();
      }
      onSelected(i);
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.personColor,
      child: Wrap(
        children: [
          for (var i = 0; i < AccentId.values.length; i++)
            Semantics(
              container: true,
              inMutuallyExclusiveGroup: true,
              checked: i == selected,
              label: AccentId.values[i].label(l10n),
              onTap: () => select(i),
              excludeSemantics: true,
              child: InkResponse(
                onTap: () => select(i),
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    // El borde cambia de color y de grosor con `soft` y el
                    // visto entra con un rebote pequeño.
                    child: AnimatedContainer(
                      duration: RegalosMotion.of(context).reduce
                          ? RegalosMotion.fade
                          : RegalosSprings.softDuration,
                      curve: RegalosCurves.soft,
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.isDark
                            ? personPalette(i).pastelD
                            : personPalette(i).pastel,
                        border: Border.all(
                          color: i == selected
                              ? (t.isDark
                                    ? personPalette(i).tintaD
                                    : personPalette(i).tinta)
                              : (t.isDark
                                    ? Colors.transparent
                                    : personPalette(i).swatchBorder),
                          width: i == selected ? 2.5 : 1.5,
                        ),
                      ),
                      child: ValueSwitcher(
                        dy: 0,
                        alignment: Alignment.center,
                        child: i == selected
                            ? PopIn(
                                key: const ValueKey('chosen'),
                                from: 0.6,
                                child: StrokeIcon(
                                  AppIcons.check,
                                  size: 20,
                                  strokeWidth: 2.6,
                                  color: t.isDark
                                      ? personPalette(i).onFill
                                      : personPalette(i).tinta,
                                ),
                              )
                            : const SizedBox(key: ValueKey('free')),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
