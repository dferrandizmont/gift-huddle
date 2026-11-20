import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money_input.dart';
import '../../../core/sync/model.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/gift_logic.dart';
import '../../family/presentation/family_texts.dart';

/// Lo que devuelve la hoja del presupuesto: la ocasión y su importe en
/// céntimos (`null` quita el presupuesto).
typedef BudgetChoice = ({String occasionId, int? cents});

/// Abre la hoja pequeña del presupuesto de una ocasión: un solo campo de
/// importe, con el mismo teclado y la misma lectura que el precio de un regalo.
/// Vacío quita el presupuesto.
///
/// Con [occasion] es para esa ocasión; sin ella (el acceso de arriba cuando
/// ninguna tiene presupuesto) la hoja deja elegir cuál entre [choices].
/// [budgetOf] permite leer el importe actual al cambiar de ocasión.
/// Devuelve `null` si se cancela o se confirma el importe que se mostró.
Future<BudgetChoice?> showBudgetSheet(
  BuildContext context, {
  Occasion? occasion,
  List<Occasion> choices = const [],
  required String Function(Occasion) nameOf,
  int? Function(String)? budgetOf,
}) => showEditSheet<BudgetChoice>(
  context,
  (_) => _BudgetSheet(
    occasion: occasion,
    choices: choices,
    nameOf: nameOf,
    budgetOf:
        budgetOf ?? (id) => choices.firstWhere((o) => o.id == id).budgetCents,
  ),
);

/// Pone o quita el presupuesto de una ocasión desde su botón de la pantalla de
/// Presupuesto (nativa o web) y guarda lo que elija la persona.
Future<void> editOccasionBudget(
  BuildContext context, {
  Occasion? occasion,
  String? title,
}) async {
  // El botón que abre la hoja puede desaparecer al sincronizar un presupuesto.
  final container = ProviderScope.containerOf(context, listen: false);
  final view = container.read(familyViewProvider);
  final l10n = AppLocalizations.of(context);
  // Los nombres, con las personas archivadas: el cumpleaños de una que ya no
  // está sigue llamándose «Cumpleaños de Nora».
  final labels = OccasionLabels(
    l10n,
    container.read(familyFullViewProvider).recipientsById,
  );
  final choice = await showBudgetSheet(
    context,
    occasion: occasion == null
        ? null
        : view.occasionsById[occasion.id] ?? occasion,
    choices: occasion == null ? _occasionsToChoose(view) : const [],
    nameOf: (o) =>
        o.id == occasion?.id ? (title ?? labels.of(o)) : labels.of(o),
    budgetOf: (id) =>
        container.read(familyViewProvider).occasionsById[id]?.budgetCents,
  );
  if (choice != null) {
    await container
        .read(familyControllerProvider.notifier)
        .setOccasionBudget(choice.occasionId, choice.cents);
  }
}

/// Las ocasiones entre las que se elige desde el acceso de arriba: las que
/// siguen en marcha, la más próxima primero.
List<Occasion> _occasionsToChoose(FamilyView view) => [
  for (final o in occasionsByNextDate(view.occasions, clock.now()))
    if (!o.archived) o,
];

class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet({
    required this.occasion,
    required this.choices,
    required this.nameOf,
    required this.budgetOf,
  });

  final Occasion? occasion;
  final List<Occasion> choices;
  final String Function(Occasion) nameOf;
  final int? Function(String) budgetOf;

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  final TextEditingController _amount = TextEditingController();
  final FocusNode _focus = FocusNode();
  late String? _occasionId =
      widget.occasion?.id ?? widget.choices.firstOrNull?.id;
  int? _originalCents;
  bool _tried = false;
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_filled) {
      _loadAmount((widget.occasion ?? widget.choices.firstOrNull)?.budgetCents);
      _filled = true;
    }
  }

  void _loadAmount(int? cents) {
    _originalCents = cents;
    _amount.text = cents == null ? '' : centsInputText(cents, _language);
  }

  void _selectOccasion(String id) {
    if (id == _occasionId) return;
    setState(() {
      _occasionId = id;
      _loadAmount(widget.budgetOf(id));
      _tried = false;
    });
  }

  String get _language => Localizations.localeOf(context).languageCode;

  ({int? cents, bool valid}) get _value =>
      readMoneyField(_amount.text, _language);

  @override
  void dispose() {
    _amount.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() {
    final value = _value;
    final id = _occasionId;
    if (!value.valid || id == null) {
      setState(() => _tried = true);
      return;
    }
    if (value.cents == _originalCents) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop((occasionId: id, cents: value.cents));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final occasion = widget.occasion;
    return SheetFrame(
      title: occasion == null
          ? l10n.budgetSetAction
          : l10n.budgetSheetTitle(widget.nameOf(occasion)),
      onSave: _save,
      children: [
        if (occasion == null) ...[
          PickerField<String>(
            label: l10n.fieldOccasion,
            value: _occasionId,
            options: [
              for (final o in widget.choices)
                PickerOption(value: o.id, label: widget.nameOf(o)),
            ],
            onChanged: _selectOccasion,
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          key: const ValueKey<String>('budget-sheet-field'),
          controller: _amount,
          focusNode: _focus,
          autofocus: true,
          keyboardType: moneyKeyboard,
          inputFormatters: moneyInputFormatters,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          onChanged: (_) {
            if (_tried) {
              setState(() {});
            }
          },
          decoration: InputDecoration(
            labelText: l10n.budgetFigure,
            helperText: l10n.budgetSheetHint,
            helperMaxLines: 3,
            suffixText: '€',
            errorText: _tried && !_value.valid ? l10n.giftPriceInvalid : null,
            errorMaxLines: 3,
          ),
        ),
      ],
    );
  }
}
