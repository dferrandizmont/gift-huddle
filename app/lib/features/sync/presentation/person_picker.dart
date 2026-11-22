import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/motion/success_mark.dart';
import '../../../core/motion/unfold_section.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/settings_icons.dart';
import '../../../core/widgets/soft_note.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../application/pairing_v2_controller.dart' show PairingV2Person;

/// Qué ha tocado quien elige en un [PersonPicker].
enum _Pick { none, person, notOnList, nobody }

/// La pregunta de «de quién es este móvil» (1.0.6), la misma para
/// «¿Para quién es el móvil nuevo?» (quien invita elige la persona del móvil
/// nuevo) y «¿Quién eres?» (este móvil todavía no es de nadie): las personas
/// de la familia, «No está en la lista» con un campo para el nombre y «Nadie»
/// para quien regala y no recibe regalos.
///
/// Tocar una opción no hace nada todavía: la marca (tinte y visto que se
/// dibuja), despliega lo que le toca (el campo del nombre, el aviso) y habilita
/// «Continuar». Así el aviso de que los regalos pasan a estar en secreto se lee
/// antes de empezar. Todo lo que se despliega entra con `UnfoldSection`; con
/// «Reducir movimiento» se funde.
class PersonPicker extends StatefulWidget {
  /// Crea la pregunta.
  const PersonPicker({
    super.key,
    required this.title,
    required this.body,
    required this.people,
    required this.notOnListLabel,
    required this.nobodyLabel,
    required this.nameLabel,
    required this.onPerson,
    required this.onNew,
    this.suggestedName = '',
    this.noticeFor,
    this.newNotice,
    this.selectedPersonId,
    this.thisPhonePersonId,
  });

  /// El título del paso.
  final String title;

  /// La explicación bajo el título.
  final String body;

  /// Las personas que se pueden elegir.
  final List<PairingV2Person> people;

  /// «No está en la lista» o «No estoy en la lista».
  final String notOnListLabel;

  /// «Nadie: solo regala» o «Nadie».
  final String nobodyLabel;

  /// La etiqueta del campo del nombre.
  final String nameLabel;

  /// El nombre con el que se rellena el campo al elegir «No está en la
  /// lista» o «Nadie» (el de la bienvenida), si está vacío.
  final String suggestedName;

  /// Se ha elegido a la persona [id] y se ha pulsado «Continuar».
  final FutureOr<void> Function(String id) onPerson;

  /// Se ha pulsado «Continuar» con un nombre nuevo; [noGifts] si es «Nadie».
  final FutureOr<void> Function(String name, {required bool noGifts}) onNew;

  /// El aviso que se lee al elegir a la persona [id], o `null` si no hay.
  final String? Function(String id)? noticeFor;

  /// El aviso que se lee al elegir «No está en la lista» con [name], o `null`.
  final String? Function(String name)? newNotice;

  /// La persona que sale ya marcada (la de «Este móvil es de»), si está en
  /// [people].
  final String? selectedPersonId;

  /// La persona de este móvil (1.0.6, QA m6): su fila lleva la nota «Este
  /// móvil», sin marcarla como elegida.
  final String? thisPhonePersonId;

  @override
  State<PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<PersonPicker> {
  final TextEditingController _name = TextEditingController();
  final FocusNode _focus = FocusNode();
  _Pick _pick = _Pick.none;
  String? _personId;
  bool _working = false;

  /// El último aviso que se vio: se conserva mientras el bloque se pliega.
  String _lastNotice = '';

  @override
  void initState() {
    super.initState();
    final selected = widget.selectedPersonId;
    if (selected != null && widget.people.any((p) => p.id == selected)) {
      _pick = _Pick.person;
      _personId = selected;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _asksName => _pick == _Pick.notOnList || _pick == _Pick.nobody;

  String get _typed => _name.text.trim();

  bool get _canContinue =>
      !_working &&
      switch (_pick) {
        _Pick.none => false,
        _Pick.person => _personId != null,
        _Pick.notOnList || _Pick.nobody => _typed.isNotEmpty,
      };

  void _choose(_Pick pick, {String? personId}) {
    if (_working) return;
    setState(() {
      _pick = pick;
      _personId = personId;
    });
    if (pick == _Pick.notOnList || pick == _Pick.nobody) {
      // La propuesta de la bienvenida, solo si el campo está vacío.
      if (_name.text.isEmpty && widget.suggestedName.isNotEmpty) {
        _name.text = widget.suggestedName;
        _name.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _name.text.length,
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  Future<void> _continue() async {
    if (!_canContinue) return;
    setState(() => _working = true);
    try {
      switch (_pick) {
        case _Pick.person:
          await widget.onPerson(_personId!);
        case _Pick.notOnList:
          await widget.onNew(_typed, noGifts: false);
        case _Pick.nobody:
          await widget.onNew(_typed, noGifts: true);
        case _Pick.none:
          break;
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String? get _notice => switch (_pick) {
    _Pick.person =>
      _personId == null ? null : widget.noticeFor?.call(_personId!),
    _Pick.notOnList => _typed.isEmpty ? null : widget.newNotice?.call(_typed),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final notice = _notice;
    if (notice != null) _lastNotice = notice;
    final rows = <_RowSpec>[
      for (var i = 0; i < widget.people.length; i++)
        _RowSpec(
          key: ValueKey<String>('person:${widget.people[i].id}'),
          leading: PersonAvatar(
            name: widget.people[i].name,
            colorIndex: i,
            size: 40,
          ),
          title: widget.people[i].name,
          hint: widget.people[i].id == widget.thisPhonePersonId
              ? l10n.personPickerThisPhone
              : null,
          selected: _pick == _Pick.person && _personId == widget.people[i].id,
          onTap: () => _choose(_Pick.person, personId: widget.people[i].id),
        ),
      _RowSpec(
        key: const ValueKey<String>('notOnList'),
        leading: const _OptionIcon(AppIcons.plus),
        title: widget.notOnListLabel,
        selected: _pick == _Pick.notOnList,
        onTap: () => _choose(_Pick.notOnList),
      ),
      _RowSpec(
        key: const ValueKey<String>('nobody'),
        leading: const _OptionIcon(AppIcons.people),
        title: widget.nobodyLabel,
        hint: l10n.whoAreYouNobodyHint,
        selected: _pick == _Pick.nobody,
        onTap: () => _choose(_Pick.nobody),
      ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(widget.title, style: t.styles.screenTitleSmall),
        ),
        const SizedBox(height: 8),
        Text(widget.body, style: t.styles.body),
        const SizedBox(height: 12),
        // El filete de arriba falta en la primera fila y en la elegida y la
        // que va a continuación: el fondo teñido ya hace de límite.
        for (var i = 0; i < rows.length; i++)
          _ChoiceRow(
            key: rows[i].key,
            leading: rows[i].leading,
            title: rows[i].title,
            hint: rows[i].hint,
            selected: rows[i].selected,
            topBorder: i > 0 && !rows[i].selected && !rows[i - 1].selected,
            onTap: rows[i].onTap,
          ),
        UnfoldSection(
          show: _asksName,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: _name,
              focusNode: _focus,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => unawaited(_continue()),
              decoration: InputDecoration(labelText: widget.nameLabel),
            ),
          ),
        ),
        // El aviso conserva el último texto mientras se pliega.
        UnfoldSection(
          show: notice != null,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: SoftNote(
                icon: SettingsIcons.lock,
                text: notice ?? _lastNotice,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey<String>('personPickerContinue'),
          onPressed: _canContinue ? () => unawaited(_continue()) : null,
          child: Text(l10n.pairingV2ChooseContinue),
        ),
      ],
    );
  }
}

/// Lo que dibuja una fila del paso.
class _RowSpec {
  const _RowSpec({
    required this.key,
    required this.leading,
    required this.title,
    required this.selected,
    required this.onTap,
    this.hint,
  });

  final Key key;
  final Widget leading;
  final String title;
  final String? hint;
  final bool selected;
  final VoidCallback onTap;
}

/// Una fila del paso: la persona o una de las opciones. Elegida, el fondo se
/// tiñe y se dibuja un visto. El contenido no se mueve: el tinte sale 8 por
/// cada lado de la fila, sobre el margen de la pantalla, y la letra no cambia
/// de peso (si no, el texto saltaría al elegir).
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.leading,
    required this.title,
    required this.selected,
    required this.onTap,
    this.hint,
    this.topBorder = true,
  });

  final Widget leading;
  final String title;
  final String? hint;
  final bool selected;

  /// Si lleva un filete encima.
  final bool topBorder;
  final VoidCallback onTap;

  /// Lo que sobresale el tinte del contenido por cada lado.
  static const double _bleed = 8;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final tint = RegalosMotion.of(context).duration(RegalosChoiceMotion.tint);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: hint == null ? title : '$title. $hint',
      excludeSemantics: true,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -_bleed,
            right: -_bleed,
            top: 0,
            bottom: 0,
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(
                begin: Colors.transparent,
                end: selected ? t.selection : Colors.transparent,
              ),
              duration: tint,
              builder: (context, color, _) => DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: RegalosShape.button,
                ),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: RegalosShape.button,
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(vertical: 8),
                // Sin filete el filete sigue ahí, transparente: la fila no cambia
                // de alto al elegirla.
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: topBorder ? t.separator : Colors.transparent,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    leading,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: selected
                                ? t.styles.rowTitle.copyWith(color: t.ink)
                                : t.styles.rowTitle,
                          ),
                          if (hint != null) Text(hint!, style: t.styles.meta),
                        ],
                      ),
                    ),
                    // El hueco del visto esta siempre: la fila no cambia de
                    // ancho al elegirla.
                    SizedBox.square(
                      dimension: 22,
                      child: selected
                          ? DrawnCheck(
                              color: t.ink,
                              size: 22,
                              strokeWidth: 2.2,
                              duration: RegalosChoiceMotion.check,
                              delay: RegalosChoiceMotion.checkDelay,
                              curve: RegalosChoiceMotion.checkCurve,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El icono de las opciones que no son una persona: un cuadro suave de 40, con
/// las mismas esquinas que el avatar de una persona, y el trazo dentro.
class _OptionIcon extends StatelessWidget {
  const _OptionIcon(this.icon);

  final void Function(Path) icon;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return ExcludeSemantics(
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.soft,
          borderRadius: BorderRadius.circular(PersonAvatar.radiusFor(40)),
        ),
        child: StrokeIcon(
          icon,
          size: 22,
          color: t.textOnSoft,
          strokeWidth: 1.9,
        ),
      ),
    );
  }
}
