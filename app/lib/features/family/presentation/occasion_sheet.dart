import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../core/format/dates.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/pop_in.dart';
import '../../../core/motion/unfold_section.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/occasion_theme.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/choice_grid.dart';
import '../../../core/widgets/occasion_icons.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../../l10n/app_localizations.dart';
import '../application/gift_logic.dart';
import '../application/occasion_names.dart';
import '../domain/occasion_presets.dart';
import 'family_texts.dart';

/// Abre la hoja para dar de alta o cambiar una ocasión.
///
/// Al crear una, lo primero es elegir el tipo en una rejilla con su icono
/// (Tió, Papá Noel, Reyes, Año Nuevo Chino, boda, aniversario, Sant Jordi,
/// San Valentín, bautizo, comunión, graduación u «Otra»), y el tipo rellena
/// el nombre y la fecha. «Otra» deja elegir el nombre, un color y un icono.
///
/// Devuelve la ocasión, o `null` si se cancela. No guarda nada. La fecha de
/// un cumpleaños sale de la persona y no se puede cambiar aquí.
///
/// [initialName] es el nombre con que se enseña [initial] (las ocasiones de
/// serie no guardan el suyo: ver `occasionTitle`). Si se deja tal cual, se
/// conserva lo que había guardado.
Future<Occasion?> showOccasionSheet(
  BuildContext context, {
  Occasion? initial,
  String? initialName,
}) => showEditSheet<Occasion>(
  context,
  (_) => _OccasionSheet(initial: initial, initialName: initialName),
);

class _OccasionSheet extends StatefulWidget {
  const _OccasionSheet({required this.initial, this.initialName});

  final Occasion? initial;
  final String? initialName;

  @override
  State<_OccasionSheet> createState() => _OccasionSheetState();
}

class _OccasionSheetState extends State<_OccasionSheet> {
  late final TextEditingController _name;
  late int? _month;
  late int? _day;
  late int? _year;
  late bool _recurring;

  /// El tipo elegido; `null` mientras no se elige ninguno (se guarda como
  /// «Otra»).
  OccasionKind? _kind;

  /// Si el tipo cambió respecto a lo guardado: si no, se conserva el nombre
  /// de tipo que trajera el registro, aunque esta versión no lo conozca.
  bool _kindChanged = false;

  /// El color y el icono de «Otra»; `null` mientras no se eligen (sale el de
  /// serie y no se guarda nada).
  String? _color;
  String? _icon;

  /// Si el nombre lo tecleó la persona (y no se rellena solo al elegir tipo).
  bool _nameTouched = false;

  /// Si la fecha viene del tipo elegido y no de la persona.
  bool _dateFromPreset = false;
  bool _showError = false;

  bool get _isBirthday => widget.initial?.kind == OccasionKind.birthday;

  OccasionPreset? get _preset {
    final kind = _kind;
    return kind == null ? null : presetFor(kind);
  }

  /// La fecha se calcula sola y no se puede elegir.
  bool get _autoDate => _preset?.autoDate ?? false;

  @override
  void initState() {
    super.initState();
    final o = widget.initial;
    _name = TextEditingController(text: widget.initialName ?? (o?.name ?? ''));
    _month = o?.month;
    _day = o?.day;
    _year = o?.year;
    _recurring = o?.recurring ?? true;
    _kind = o == null || o.kind == OccasionKind.birthday ? null : o.kind;
    _nameTouched = o != null;
    _color = o?.color;
    _icon = o?.icon;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = clock.now();
    final base = DateTime(now.year, now.month, now.day);
    final initial = _month != null && _day != null
        ? DateTime(_year ?? now.year, _month!, _day!)
        : base;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null && mounted) {
      setState(() {
        _month = picked.month;
        _day = picked.day;
        _year = picked.year;
        _dateFromPreset = false;
      });
    }
  }

  /// Elige un tipo: rellena el nombre (si no lo ha escrito la persona), la
  /// fecha y si se repite.
  void _pickKind(OccasionKind kind, AppLocalizations l10n) {
    final preset = presetFor(kind);
    final date = preset.dateFrom(clock.now());
    setState(() {
      _kind = kind;
      _kindChanged = true;
      if (!_nameTouched) {
        _name.text = kind == OccasionKind.custom
            ? ''
            : occasionKindLabel(l10n, kind);
      }
      if (date != null) {
        _month = date.month;
        _day = date.day;
        _year = null;
        _dateFromPreset = true;
      } else if (_dateFromPreset) {
        _month = null;
        _day = null;
        _year = null;
        _dateFromPreset = false;
      }
      _recurring = preset.recurring;
    });
  }

  void _save() {
    var name = _name.text.trim();
    if (name.isEmpty || _month == null || _day == null) {
      setState(() => _showError = true);
      return;
    }
    final base = widget.initial;
    final kind = _isBirthday
        ? (base?.kind ?? OccasionKind.birthday)
        : (_kind ?? OccasionKind.custom);
    // El nombre de serie no se guarda traducido: cada móvil lo pone en su
    // idioma. Si no lo han cambiado, se conserva lo que había; si es el nombre
    // de su tipo, se guarda el marcador.
    if (base != null && name == (widget.initialName ?? base.name).trim()) {
      name = base.name;
    } else if (kind != OccasionKind.custom &&
        kind != OccasionKind.birthday &&
        name == occasionKindLabel(AppLocalizations.of(context), kind)) {
      name = kSeedOccasionName;
    }
    final custom = kind == OccasionKind.custom;
    final recurring = _autoDate ? true : _recurring;
    final keepRaw = _isBirthday || (!_kindChanged && base != null);
    Navigator.of(context).pop(
      Occasion(
        id: base?.id ?? newId(),
        kind: kind,
        rawKind: keepRaw ? (base?.rawKind ?? kind.name) : kind.name,
        name: name,
        month: _month!,
        day: _day!,
        year: recurring ? null : (_year ?? clock.now().year),
        recurring: recurring,
        recipientId: base?.recipientId,
        archived: base?.archived ?? false,
        color: custom ? _color : null,
        icon: custom ? _icon : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final hasDate = _month != null && _day != null;
    final custom = _kind == OccasionKind.custom;
    return SheetFrame(
      title: widget.initial == null ? l10n.occasionNew : l10n.occasionEdit,
      onSave: _save,
      children: [
        if (!_isBirthday) ...[
          Semantics(
            header: true,
            child: Text(l10n.occasionTypeTitle, style: t.styles.label),
          ),
          const SizedBox(height: 8),
          ChoiceGrid(
            items: [
              for (final kind in kCreatableKinds)
                ChoiceGridItem(
                  label: occasionKindLabel(l10n, kind),
                  leading: (color, _) => OccasionKindIcon(
                    kind,
                    customIcon: _icon,
                    size: 20,
                    color: color,
                  ),
                  selected: _kind == kind,
                  onTap: () => _pickKind(kind, l10n),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _name,
          autofocus: widget.initial == null && _kind == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.fieldName,
            hintText: l10n.occasionNameHint,
            errorText: _showError && _name.text.trim().isEmpty
                ? l10n.fieldNameRequired
                : null,
          ),
          onChanged: (_) {
            _nameTouched = true;
            if (_showError) {
              setState(() {});
            }
          },
        ),
        // El color y el icono de «Otra» se despliegan al elegir ese tipo.
        UnfoldSection(
          show: custom,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(l10n.occasionCustomColor, style: t.styles.label),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in kOccasionColors)
                    _ColorSwatchButton(
                      label: occasionColorLabel(l10n, c.name),
                      color: c,
                      selected: (_color ?? kDefaultOccasionColor) == c.name,
                      onTap: () => setState(() => _color = c.name),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(l10n.occasionCustomIcon, style: t.styles.label),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final entry in kOccasionIcons.entries)
                    _IconButtonTile(
                      label: occasionIconLabel(l10n, entry.key),
                      icon: entry.value,
                      selected: (_icon ?? kDefaultOccasionIcon) == entry.key,
                      onTap: () => setState(() => _icon = entry.key),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.occasionDate, style: t.styles.label),
        const SizedBox(height: 4),
        OutlinedButton(
          onPressed: _isBirthday || _autoDate ? null : _pickDate,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(44, 48),
            foregroundColor: t.text,
            side: BorderSide(color: t.controlBorder),
            alignment: Alignment.centerLeft,
            shape: const RoundedRectangleBorder(
              borderRadius: RegalosShape.field,
            ),
          ),
          child: Text(
            hasDate
                ? longDayMonth(_month!, _day!, l10n.localeName)
                : l10n.occasionDatePick,
            style: t.styles.body,
          ),
        ),
        UnfoldSection(
          show: _showError && !hasDate,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l10n.occasionDateRequired, style: t.styles.meta),
          ),
        ),
        // La nota de una línea que toque (cumpleaños, Año Nuevo Chino o
        // ninguna) ocupa siempre el mismo hueco y se cruza con un fundido;
        // «Se repite» se despliega y se pliega.
        ValueSwitcher(
          dy: 0,
          alignment: Alignment.topLeft,
          child: _isBirthday
              ? Padding(
                  key: const ValueKey('birthday'),
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.occasionBirthdayDateHint,
                    style: t.styles.meta,
                  ),
                )
              : _autoDate
              ? Padding(
                  key: const ValueKey('chinese-new-year'),
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.occasionChineseNewYearHint,
                    style: t.styles.meta,
                  ),
                )
              : const SizedBox(key: ValueKey('no-note')),
        ),
        UnfoldSection(
          show: !_isBirthday && !_autoDate,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SwitchRow(
              title: l10n.occasionRepeats,
              value: _recurring,
              onChanged: (v) => setState(() => _recurring = v),
            ),
          ),
        ),
      ],
    );
  }
}

/// Una muestra de color de 44 px; la elegida lleva un visto.
class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final OccasionColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final dark = t.isDark;
    final fill = dark ? color.palette.pastelD : color.palette.pastel;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 44,
        child: InkResponse(
          onTap: () {
            if (!selected) {
              context.haptics.selection();
            }
            onTap();
          },
          customBorder: const CircleBorder(),
          child: Center(
            // El borde cambia de color y de grosor con `soft` y el visto entra
            // con un rebote pequeño.
            child: AnimatedContainer(
              duration: RegalosMotion.of(context).reduce
                  ? RegalosMotion.fade
                  : RegalosSprings.softDuration,
              curve: RegalosCurves.soft,
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? t.text : color.palette.swatchBorder,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: ValueSwitcher(
                dy: 0,
                alignment: Alignment.center,
                child: selected
                    ? PopIn(
                        key: const ValueKey('chosen'),
                        from: 0.6,
                        child: Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: dark
                              ? color.palette.onFill
                              : color.palette.tinta,
                        ),
                      )
                    : const SizedBox(key: ValueKey('free')),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un icono elegible de 44 px; el elegido se rellena con el acento.
class _IconButtonTile extends StatelessWidget {
  const _IconButtonTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 44,
        // El relleno y el icono cambian con `soft`, con el radio fijo.
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: selected ? 1 : 0),
          duration: RegalosMotion.of(context).reduce
              ? RegalosMotion.fade
              : RegalosSprings.softDuration,
          curve: RegalosCurves.soft,
          builder: (context, k, _) => Material(
            color: t.fill.withValues(alpha: k),
            shape: RoundedRectangleBorder(
              borderRadius: RegalosShape.chip,
              side: BorderSide(color: Color.lerp(t.chipBorder, t.fill, k)!),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (!selected) {
                  context.haptics.selection();
                }
                onTap();
              },
              child: Center(
                child: Icon(
                  icon,
                  size: 22,
                  color: Color.lerp(t.text, t.onFill, k),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
