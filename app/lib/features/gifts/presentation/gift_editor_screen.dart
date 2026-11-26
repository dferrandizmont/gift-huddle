import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../../../core/platform/gifts_secure_scope.dart';
import '../../../core/format/money_input.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/card_sheet_route.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/sheet_motion.dart';
import '../../../core/motion/success_mark.dart';
import '../../../core/motion/unfold_section.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/platform/user_link.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/wish.dart' show VisibleWishPatch;
import '../../../core/sync/protected_doc.dart'
    show ProtectedPersonException, ProtectedPersonReason;
import '../../../core/theme/occasion_theme.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/choice_grid.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/danger_button.dart';
import '../../../core/widgets/giver_dot.dart';
import '../../../core/widgets/edge_swipe_back.dart';
import '../../../core/widgets/link_icon_button.dart';
import '../../../core/widgets/more_details.dart';
import '../../../core/widgets/occasion_icons.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../../../core/widgets/sheet_parts.dart' show WarningBox;
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tabler_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_actions.dart';
import '../../family/application/family_controller.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/gift_logic.dart';
import '../../family/application/wish_service.dart';
import '../../family/application/self_recipient_provider.dart';
import '../../family/presentation/family_texts.dart';
import '../../family/presentation/giver_person_flow.dart';
import '../../family/presentation/pending_gifts_sheet.dart';
import '../../family/presentation/person_sheet.dart';
import '../../family/presentation/protection_texts.dart';
import '../../web_board/application/gift_editor_panel.dart';
import '../../web_board/application/web_board.dart';
import '../../web_device/application/web_app_provider.dart';
import '../application/delivered_arm.dart';
import '../application/person_completion.dart';
import '../domain/store_from_url.dart';
import 'gift_actions.dart';
import 'gift_link_actions.dart';
import 'editor_footer_row.dart';
import 'wish_editor.dart'
    show openWishEditor, openWishPlanEditor, showWishProblem;

/// Si el editor de una ventana de escritorio (desde 1280) es un diálogo: solo
/// en la web. Las pruebas lo cambian sin montar toda la web.
final giftEditorAsDialogProvider = Provider<bool>(
  (ref) => ref.watch(webAppProvider),
);

/// Abre el editor de regalo: como una tarjeta que sube desde abajo, por encima
/// de la barra de navegación (§2.1 de la guía de movimiento), o,
/// en la web con una ventana de escritorio (desde 1280), como un diálogo centrado
/// (`showCardDialog`). Con [gift] edita ese regalo; sin él, crea uno nuevo.
///
/// Con [chooseRecipient] (el botón «Añadir regalo» de las pestañas) el editor
/// empieza con la elección de persona arriba, sin ninguna marcada salvo que
/// haya una sola o venga una en [recipientId].
///
/// Con [suggestVisible] (la ficha de una persona cuyo bloque está cerrado) el
/// formulario solo guarda un deseo visible para [recipientId]: «Visible para»
/// va encendido y fijo, y la sorpresa, apagada con su motivo.
///
/// Devuelve el id del regalo guardado, o `null` si no se guardó nada (se
/// cerró o se borró).
Future<String?> openGiftEditor(
  BuildContext context, {
  Gift? gift,
  String? recipientId,
  String? occasionId,
  String? giverId,
  GiftStatus? status,
  bool chooseRecipient = false,
  bool suggestVisible = false,
}) {
  // En el móvil de la propia persona no se apuntan regalos para ella, solo
  // deseos (ADR 0010): si la persona de este móvil es la única que puede
  // recibir el regalo (o viene ya elegida), el alta pasa directa al editor de
  // deseos, con la ocasión de origen; si se elige después, en cualquier
  // selector, el editor se cierra llevando lo escrito y se abre el de deseos.
  if (gift == null) {
    final reader = ProviderScope.containerOf(context).read(wishReaderProvider);
    if (reader != null) {
      final people = ProviderScope.containerOf(context)
          .read(familyFullViewProvider)
          .recipients;
      final active = [
        for (final p in people)
          if (!p.archived) p,
      ];
      final String? chosen =
          recipientId ?? (active.length == 1 ? active.first.id : null);
      if (chosen == reader) {
        return openWishEditor(
          context,
          recipientId: reader,
          draft: VisibleWishPatch(occasionId: occasionId),
        );
      }
      // Sin nadie elegido, el editor propondría a la primera persona de la
      // lista: si es la de este móvil y hay más gente, se elige a mano.
      if (recipientId == null &&
          !chooseRecipient &&
          people.firstOrNull?.id == reader) {
        chooseRecipient = true;
      }
    }
  }
  final handoff = <(String, VisibleWishPatch)>[];
  return _openGiftEditorFrame(
    context,
    gift: gift,
    recipientId: recipientId,
    occasionId: occasionId,
    giverId: giverId,
    status: status,
    chooseRecipient: chooseRecipient,
    suggestVisible: suggestVisible,
    onOwnPerson: (id, draft) => handoff.add((id, draft)),
  ).then((id) async {
    if (handoff.isNotEmpty && context.mounted) {
      final (person, draft) = handoff.first;
      return openWishEditor(context, recipientId: person, draft: draft);
    }
    return id;
  });
}

Future<String?> _openGiftEditorFrame(
  BuildContext context, {
  void Function(String personId, VisibleWishPatch draft)? onOwnPerson,
  Gift? gift,
  String? recipientId,
  String? occasionId,
  String? giverId,
  GiftStatus? status,
  bool chooseRecipient = false,
  bool suggestVisible = false,
}) {
  // Un deseo que alguien ha cogido se ve como un regalo, pero se edita con su
  // plan (ADR 0010): lo suyo es quién regala, el estado y lo privado.
  if (gift != null) {
    final plan = ProviderScope.containerOf(context)
        .read(wishPlanOfGiftProvider(gift.id));
    if (plan != null) {
      return openWishPlanEditor(
        context,
        person: plan.recipientId,
        plan: plan,
      ).then((_) => null);
    }
  }
  // En el tablero de la web de escritorio (desde 1280) el editor es el panel
  // fijo de la derecha: no tapa nada y se puede pasar de un regalo a otro.
  final container = ProviderScope.containerOf(context);
  final panel = container.read(giftEditorPanelProvider);
  if (panel.hosted &&
      container.read(webBoardEnabledProvider) &&
      boardWidth(MediaQuery.sizeOf(context).width)) {
    return panel.open(
      gift: gift,
      recipientId: recipientId,
      occasionId: occasionId,
      giverId: giverId,
      status: status,
      chooseRecipient: chooseRecipient,
      onOwnPerson: onOwnPerson,
    );
  }
  // En la web, desde 1280 de ventana el editor es un diálogo de 880 con el formulario en
  // dos columnas; por debajo, la hoja que sube desde abajo (640), como en el
  // móvil.
  // Solo en la web (el navegador de un ordenador): una tablet en horizontal
  // también mide 1280, pero lleva la tarjeta de 640 centrada del diseño D.
  final dialog =
      RegalosLayout.isDesktop(MediaQuery.sizeOf(context).width) &&
      ProviderScope.containerOf(context).read(giftEditorAsDialogProvider);
  Widget editor(BuildContext _) => GiftEditorScreen(
    gift: gift,
    initialRecipientId: recipientId,
    initialOccasionId: occasionId,
    initialGiverId: giverId,
    initialStatus: status,
    chooseRecipient: chooseRecipient,
    suggestVisible: suggestVisible,
    onOwnPerson: onOwnPerson,
    asDialog: dialog,
  );
  return dialog
      ? showCardDialog<String>(context, builder: editor)
      : showCardSheet<String>(context, builder: editor);
}

const String _none = '__none__';

/// El valor «ninguno» de los selectores del editor (sin ocasión, sin quien
/// regala): lo comparte el editor de deseos.
const String kPickerNone = _none;
const String _other = '__other__';

/// Prefijo del valor de una persona elegida como quién regala en el selector
/// (aún no es un quién regala: se crea o se recupera al guardar).
const String _personPrefix = '__person__:';

/// Editor de un regalo: nuevo o existente.
class GiftEditorScreen extends ConsumerStatefulWidget {
  /// Crea el editor.
  const GiftEditorScreen({
    super.key,
    this.gift,
    this.initialRecipientId,
    this.initialOccasionId,
    this.initialGiverId,
    this.initialStatus,
    this.chooseRecipient = false,
    this.onOwnPerson,
    this.suggestVisible = false,
    this.asDialog = false,
    this.asPanel = false,
    this.onClose,
  });

  /// El regalo que se edita, o `null` para uno nuevo.
  final Gift? gift;

  /// Persona de un regalo nuevo.
  final String? initialRecipientId;

  /// Ocasión de un regalo nuevo.
  final String? initialOccasionId;

  /// Quién regala en un regalo nuevo.
  final String? initialGiverId;

  /// El estado con el que empieza un regalo nuevo (el del carril desde el que
  /// se añade en el tablero); sin él, «Idea».
  final GiftStatus? initialStatus;

  /// Si un regalo nuevo empieza por elegir la persona (arriba del todo y sin
  /// marcar ninguna si hay varias). Con un regalo existente no se usa.
  final bool chooseRecipient;

  /// Si el regalo nuevo solo puede guardarse como un deseo visible para la
  /// persona (su bloque de sorpresas está cerrado en este móvil): «Visible
  /// para» queda encendido y fijo, y la sorpresa apagada con su motivo.
  final bool suggestVisible;

  /// Lo que se llama si, en un regalo nuevo, se elige a la persona de este
  /// móvil (que no recibe regalos, solo deseos): con su id y lo escrito que
  /// vale para un deseo. Quien abre el editor abre entonces el de deseos.
  final void Function(String personId, VisibleWishPatch draft)? onOwnPerson;

  /// Si se abre como diálogo de escritorio (`showCardDialog`): sin flecha en la
  /// cabecera, con el alto de su contenido y «Cancelar» y «Guardar» abajo a la
  /// derecha. Si no, ocupa la hoja de `showCardSheet`, de alto completo.
  final bool asDialog;

  /// Si es el panel fijo de la derecha del tablero de la web de escritorio
  /// (la guía de diseño de escritorio, A): sin ruta que cerrar, así
  /// que al guardar, borrar o cancelar avisa por [onClose].
  final bool asPanel;

  /// Lo que se llama al cerrar el panel: con el id del regalo guardado o
  /// `null` si no se guardó nada. Solo con [asPanel].
  final ValueChanged<String?>? onClose;

  @override
  ConsumerState<GiftEditorScreen> createState() => _GiftEditorScreenState();
}

class _GiftEditorScreenState extends ConsumerState<GiftEditorScreen> {
  final _title = TextEditingController();
  final _planned = TextEditingController();
  final _actual = TextEditingController();
  final _store = TextEditingController();
  final _url = TextEditingController();
  final _note = TextEditingController();

  /// La descripción pública de «Visible para [persona]»: su propio borrador.
  /// Nunca comparte texto con [_note] (las notas son privadas): al encender o
  /// apagar el interruptor no se mueve nada de un campo al otro.
  final _description = TextEditingController();
  final _size = TextEditingController();
  final _requestNote = TextEditingController();
  final _requestName = TextEditingController();
  final _titleFocus = FocusNode();
  final _scroll = ScrollController();

  // Para llevar la vista hasta el primer campo con error al guardar.
  final _titleKey = GlobalKey();
  final _priceKey = GlobalKey();
  final _actualKey = GlobalKey();
  final _moreKey = GlobalKey();
  final _requestNameKey = GlobalKey();
  final _plannedFocus = FocusNode();
  final _actualFocus = FocusNode();
  final _requestNameFocus = FocusNode();

  late String _recipientId;
  String _giverId = _none;

  /// La persona elegida en la sección «Personas» del selector de quién regala;
  /// se asigna al guardar. Sustituye a [_giverId] mientras está elegida.
  String? _giverPersonId;
  String _occasionId = _none;
  GiftStatus _status = GiftStatus.idea;
  bool _surprise = false;

  /// Si «Más detalles» (precio real, tienda, enlace, talla y nota) está
  /// abierta. Se abre sola al editar un regalo que ya tiene alguno de esos
  /// datos y cuando el precio real no vale al guardar.
  bool _moreOpen = false;

  /// «Visible para [persona]» (ADR 0010): en vez de una sorpresa, un deseo
  /// que la persona ve. Solo en un regalo nuevo para alguien con móvil.
  bool _visible = false;
  bool _isRequest = false;
  String _requestedBy = _other;
  bool _tried = false;
  bool _busy = false;

  /// Si la persona ha escrito en «Tienda»: entonces el enlace ya no la rellena.
  bool _storeTouched = false;

  /// La tienda que rellenó el enlace y nadie ha tocado después; mientras siga
  /// así, un enlace distinto la cambia. `null` si no la rellenó el enlace.
  String? _autoStore;
  bool _saved = false;

  /// Si el regalo dejó de estar autorizado en este móvil: el formulario se
  /// retira y el editor se cierra solo.
  bool _revoked = false;
  bool _deleting = false;

  /// Los diálogos con contenido de un regalo abiertos encima del editor
  /// (borrar, regalo parecido), con el id del OTRO regalo que citan, si lo
  /// hay: se cierran si la autorización es incierta o ese regalo deja de verse.
  final Map<Object, String?> _dialogs = <Object, String?>{};

  /// Si el editor ya se está cerrando (no se vuelve a decidir nada).
  bool _closing = false;

  /// Abre un diálogo con contenido de un regalo y lo apunta mientras dure.
  Future<T> _trackedDialog<T>(
    Future<T> Function() open, {
    String? quotedGiftId,
  }) async {
    final token = Object();
    _dialogs[token] = quotedGiftId;
    try {
      return await open();
    } finally {
      _dialogs.remove(token);
    }
  }

  void _closeDialogs() {
    final count = _dialogs.length;
    _dialogs.clear();
    final root = Navigator.of(context, rootNavigator: true);
    for (var i = 0; i < count; i++) {
      root.pop();
    }
  }

  Gift? _originalDraft;

  /// Cómo estaba el formulario al abrirse, para saber si hay cambios sin
  /// guardar (el panel del tablero no se cierra al cambiar de pantalla con
  /// cambios a medias).
  String? _initialSignature;
  GiftEditorPanelController? _panelRef;

  String _signature() => [
    _recipientId,
    _title.text.trim(),
    _giverId,
    _giverPersonId ?? '',
    _occasionId,
    _status.name,
    _planned.text.trim(),
    _actual.text.trim(),
    _store.text.trim(),
    _url.text.trim(),
    _note.text.trim(),
    _description.text.trim(),
    _size.text.trim(),
    _surprise,
    _visible,
    _isRequest,
    _requestedBy,
    _requestName.text.trim(),
    _requestNote.text.trim(),
  ].join('');

  bool _isDirty() => _dirty;

  /// Al escribir o pegar el enlace: si «Tienda» está vacía y nadie la ha
  /// tocado, la rellena con la tienda que dice el sitio (sin red). Lo que haya
  /// escrito la persona no se cambia nunca.
  void _onUrlChanged(String text) {
    final guess = storeFromUrl(text);
    final current = _store.text;
    final mine = _autoStore != null && current == _autoStore;
    final free = !_storeTouched && current.trim().isEmpty;
    if (!mine && !free) {
      return;
    }
    final next = guess ?? '';
    if (next == current) {
      _autoStore = guess;
      return;
    }
    _autoStore = guess;
    _store.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  /// El botón «Abrir» del campo del enlace: se funde al aparecer y solo
  /// responde si el texto es un enlace `https` válido.
  Widget _openLinkButton(AppLocalizations l10n) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _url,
      builder: (context, value, _) {
        final valid = userLinkUri(value.text) != null;
        return ExcludeFocus(
          excluding: !valid,
          child: IgnorePointer(
            ignoring: !valid,
            child: AnimatedOpacity(
              opacity: valid ? 1 : 0,
              duration: RegalosMotion.fade,
              curve: Curves.easeOut,
              child: LinkIconButton(
                icon: tablerExternalLink,
                label: l10n.giftLinkOpen,
                iconSize: 20,
                hitSize: 40,
                color: RegalosTokens.of(context).text,
                onTap: valid
                    ? () => openGiftLink(context, ref, value.text)
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }

  bool get _dirty =>
      !_saved && _initialSignature != null && _signature() != _initialSignature;

  /// Por qué el guardado de un regalo para una persona protegida se rechazó
  /// (el formulario se conserva); `null` si no hay rechazo.
  String? _rejected;

  bool get _isNew => widget.gift == null;

  /// Si cerrar ahora perdería cambios que la persona hizo y aún no ha
  /// guardado. Guardando, borrando, ya cerrándose o con el acceso retirado
  /// (otro móvil movió el regalo) no se pregunta nada.
  bool get _needsConfirm =>
      _dirty && !_busy && !_deleting && !_closing && !_revoked;

  /// Mientras se guarda o se borra no se cierra nada a petición de la persona:
  /// la operación decide (si falla, el borrador sigue ahí; si acaba, ella cierra
  /// una sola vez).
  bool get _closeBlocked => _busy || _deleting || _closing || _saved;

  /// El cierre que pide la persona (flecha, «Cerrar», «Cancelar», Esc, el
  /// gesto de volver, arrastrar la hoja o tocar fuera): con cambios sin
  /// guardar pregunta antes de descartarlos.

  Future<void> _requestClose() async {
    if (_closeBlocked) {
      return;
    }
    if (_needsConfirm && !await _confirmDiscard()) {
      return;
    }
    if (!mounted || _closeBlocked || _revoked) {
      return;
    }
    _close();
  }

  Future<bool> _confirmDiscard() {
    final l10n = AppLocalizations.of(context);
    return _trackedDialog(
      () => showRegalosConfirm(
        context,
        title: l10n.giftDiscardTitle,
        body: l10n.giftDiscardBody,
        confirmLabel: l10n.actionDiscard,
        cancelLabel: l10n.giftKeepEditing,
      ),
    );
  }

  /// Cierra el editor: baja la hoja o el diálogo, o avisa al panel.
  void _close([String? result]) {
    _closing = true;
    if (widget.asPanel) {
      widget.onClose?.call(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  /// Si la persona se elige arriba, antes que nada (regalo nuevo desde el
  /// botón «Añadir regalo»).
  bool get _choosing => _isNew && widget.chooseRecipient;

  @override
  void initState() {
    super.initState();
    _plannedFocus.addListener(() => _tidyPrice(_planned, _plannedFocus));
    _actualFocus.addListener(() => _tidyPrice(_actual, _actualFocus));
    final g = widget.gift;
    final view = ref.read(familyFullViewProvider);
    final people = view.recipients;
    // Eligiendo, solo valen las personas activas y, si hay varias, ninguna
    // viene marcada: el regalo no va a la primera por defecto.
    final active = [
      for (final p in people)
        if (!p.archived) p,
    ];
    _recipientId =
        g?.recipientId ??
        widget.initialRecipientId ??
        (_choosing
            ? (active.length == 1 ? active.first.id : '')
            : (people.isEmpty ? '' : people.first.id));
    if (g != null) {
      _title.text = g.title;
      _giverId = g.giverId ?? _none;
      _occasionId = g.occasionId ?? _none;
      _status = g.status;
      _surprise = g.surprise;
      _store.text = g.store ?? '';
      _url.text = g.url ?? '';
      _note.text = g.note ?? '';
      _size.text = g.size ?? '';
      _requestNote.text = g.requestNote ?? '';
      _moreOpen =
          g.actualCents != null ||
          [
            g.store,
            g.url,
            g.note,
            g.size,
          ].any((v) => v?.trim().isNotEmpty == true);
      final by = g.requestedBy;
      _isRequest = by != null;
      switch (by) {
        case RequestedByRecipient(:final recipientId):
          _requestedBy = recipientId;
        case RequestedByName(:final name):
          _requestedBy = _other;
          _requestName.text = name;
        case null:
          break;
      }
    } else {
      final initialGiver = view.resolveGiver(widget.initialGiverId);
      _giverId = initialGiver?.recipientId == _recipientId
          ? _none
          : widget.initialGiverId ?? _none;
      _occasionId = widget.initialOccasionId ?? _none;
      _status = widget.initialStatus ?? GiftStatus.idea;
      // Con el bloque de la persona cerrado solo cabe un deseo visible.
      _visible = widget.suggestVisible;
    }
  }

  bool _pricesShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final g = widget.gift;
    if (!_pricesShown && g != null) {
      _pricesShown = true;
      _planned.text = g.plannedCents == null ? '' : _centsText(g.plannedCents!);
      _actual.text = g.actualCents == null ? '' : _centsText(g.actualCents!);
      // Compara valores del formulario: importes y textos ya normalizados,
      // sin convertir esa normalización en una edición del usuario.
      _originalDraft = _draft();
    }
    _initialSignature ??= _signature();
    if (widget.asPanel && _panelRef == null) {
      final panel = ref.read(giftEditorPanelProvider);
      panel.dirtyCheck = _isDirty;
      panel.closeRequest = _requestClose;
      _panelRef = panel;
    }
  }

  @override
  void dispose() {
    // Otro editor del panel ya pudo ocupar el sitio: solo se suelta lo propio.
    final panel = _panelRef;
    if (panel != null && panel.dirtyCheck == _isDirty) {
      panel.dirtyCheck = null;
      panel.closeRequest = null;
    }
    for (final c in [
      _title,
      _planned,
      _actual,
      _store,
      _url,
      _note,
      _description,
      _size,
      _requestNote,
      _requestName,
    ]) {
      c.dispose();
    }
    _titleFocus.dispose();
    _plannedFocus.dispose();
    _actualFocus.dispose();
    _requestNameFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _centsText(int cents) {
    final euros = cents ~/ 100;
    final rest = cents % 100;
    if (rest == 0) {
      return '$euros';
    }
    final sep = Localizations.localeOf(context).languageCode == 'en'
        ? '.'
        : ',';
    return '$euros$sep${rest.toString().padLeft(2, '0')}';
  }

  String? _optional(TextEditingController c) {
    final text = c.text.trim();
    return text.isEmpty ? null : text;
  }

  /// `true` si el importe escrito no vale.
  bool _badPrice(TextEditingController c) {
    final text = c.text.trim();
    return text.isNotEmpty && _cents(c) == null;
  }

  /// El importe escrito en [c] en céntimos, con la coma y el punto valiendo
  /// de decimal (el idioma solo decide qué es un millar), o `null` si no vale.
  int? _cents(TextEditingController c) =>
      parseCents(c.text, locale: Localizations.localeOf(context).languageCode);

  /// Al salir de un campo de importe lo deja escrito como lo escribe el idioma
  /// («12.5» pasa a «12,50» en es y ca; en en, a «12.50»).
  void _tidyPrice(TextEditingController c, FocusNode focus) {
    if (focus.hasFocus || !mounted) {
      return;
    }
    final cents = c.text.trim().isEmpty ? null : _cents(c);
    if (cents == null) {
      return;
    }
    final tidy = _centsText(cents);
    if (c.text != tidy) {
      c.text = tidy;
    }
  }

  Gift? _build() {
    setState(() {
      _tried = true;
      // Un precio real que no vale se corrige a la vista.
      if (_badPrice(_actual)) _moreOpen = true;
    });
    if (_title.text.trim().isEmpty ||
        _recipientId.isEmpty ||
        _badPrice(_planned) ||
        _badPrice(_actual)) {
      return null;
    }
    if (_isRequest &&
        _requestedBy == _other &&
        _requestName.text.trim().isEmpty) {
      return null;
    }
    return _draft();
  }

  Gift _draft() {
    RequestedBy? requestedBy;
    if (_isRequest) {
      if (_requestedBy == _other) {
        final name = _requestName.text.trim();
        requestedBy = RequestedByName(name);
      } else {
        requestedBy = RequestedByRecipient(_requestedBy);
      }
    }
    return Gift(
      id: widget.gift?.id ?? newId(),
      recipientId: _recipientId,
      title: _title.text.trim(),
      giverId: _giverId == _none ? null : _giverId,
      occasionId: _occasionId == _none ? null : _occasionId,
      status: _status,
      rawStatus: _status.name,
      plannedCents: _planned.text.trim().isEmpty ? null : _cents(_planned),
      actualCents: _actual.text.trim().isEmpty ? null : _cents(_actual),
      store: _optional(_store),
      url: _optional(_url),
      note: _optional(_note),
      size: _optional(_size),
      requestedBy: requestedBy,
      requestNote: _isRequest ? _optional(_requestNote) : null,
      surprise: _surprise,
      year: widget.gift?.year ?? clock.now().year,
    );
  }

  /// El motivo por el que este móvil no puede guardar regalos para la persona
  /// [id], o `null` si puede. En un regalo que se edita, su persona de siempre
  /// no se bloquea aquí: si hace falta, el guardado lo explica.
  ProtectedPersonReason? _blockedReason(
    Map<String, GiftRecipientAccess> access,
    String id,
  ) {
    final a = access[id];
    if (a == null || a.canSelect) {
      return null;
    }
    if (widget.gift?.recipientId == id) {
      return null;
    }
    return a.reason;
  }

  /// Si se ofrece «Visible para»: un regalo nuevo para alguien que tiene
  /// móvil en la familia, desde un móvil (la web no sugiere deseos).
  bool _canSuggestFor(String recipientId) =>
      _isNew && ref.read(canSuggestWishProvider(recipientId));

  /// Si la persona elegida es la de este móvil: no se le apuntan regalos.
  bool get _isOwnPerson =>
      _isNew &&
      _recipientId.isNotEmpty &&
      ref.read(wishReaderProvider) == _recipientId;

  /// Guarda el formulario como un deseo visible para la persona (ADR 0010):
  /// título, ocasión, talla, enlace y descripción.
  Future<void> _saveVisible() async {
    setState(() => _tried = true);
    if (_title.text.trim().isEmpty) {
      ref.read(hapticsProvider).medium();
      unawaited(_showFirstError());
      return;
    }
    String? text(TextEditingController c) {
      final value = c.text.trim();
      return value.isEmpty ? null : value;
    }

    setState(() {
      _busy = true;
      _rejected = null;
    });
    final patch = VisibleWishPatch(
      title: _title.text.trim(),
      year: clock.now().year,
      occasionId: _occasionId == _none ? null : _occasionId,
      size: text(_size),
      url: text(_url),
      description: text(_description),
    );
    // La persona de este móvil no recibe regalos: lo suyo es un deseo propio.
    final service = ref.read(wishServiceProvider);
    final result = _isOwnPerson
        ? await service.createOwn(patch)
        : await service.suggest(_recipientId, patch);
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _busy = false);
      showWishProblem(
        context,
        ref,
        result,
        name:
            ref
                .read(familyFullViewProvider)
                .recipientsById[_recipientId]
                ?.name ??
            '',
      );
      return;
    }
    ref.read(hapticsProvider).light();
    setState(() => _saved = true);
    _close(result.wishId);
  }

  Future<void> _save() async {
    if (_busy || _deleting) {
      return;
    }
    // Un deseo visible para la persona no se guarda en su bloque secreto: no
    // necesita la clave privada que pide el resto de regalos.
    if (_isOwnPerson || (_visible && _canSuggestFor(_recipientId))) {
      return _saveVisible();
    }
    final access = {
      for (final a
          in ref.read(giftRecipientAccessProvider).value ??
              const <GiftRecipientAccess>[])
        a.recipient.id: a,
    };
    if (_blockedReason(access, _recipientId) != null) {
      // El aviso junto a la persona ya lo explica: solo un toque de error.
      ref.read(hapticsProvider).medium();
      return;
    }
    final gift = _build();
    if (gift == null) {
      // No se ha guardado nada: un toque de error y la vista va hasta el
      // primer campo que lo explica (con el muelle de la app, y sin viaje con
      // «Reducir movimiento»).
      ref.read(hapticsProvider).medium();
      unawaited(_showFirstError());
      return;
    }
    final l10n = AppLocalizations.of(context);
    final original = widget.gift;
    final titleChanged =
        original == null ||
        original.title != gift.title ||
        original.recipientId != gift.recipientId;
    if (titleChanged) {
      final view = ref.read(familyViewProvider);
      final pairs = duplicatesOf(view, gift);
      if (pairs.isNotEmpty) {
        final pair = pairs.first;
        final other = pair.first.id == gift.id ? pair.second : pair.first;
        final person = view.recipientsById[gift.recipientId]?.name ?? '';
        final giver = giverNameFor(l10n, view.resolveGiver(other.giverId));
        final keep = await _trackedDialog(
          quotedGiftId: other.id,
          () => showRegalosDialog<bool>(
            context,
            builder: (dialogContext) {
              final dt = RegalosTokens.of(dialogContext);
              return RegalosDialogSurface(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.giftDuplicateTitle,
                        style: dt.styles.screenTitleSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.giftDuplicateBody(other.title, person, giver),
                      style: dt.styles.body,
                    ),
                    const SizedBox(height: 20),
                    DialogButtonRow(
                      cancelLabel: l10n.giftDuplicateReview,
                      confirmLabel: l10n.giftDuplicateSave,
                      cancel: OutlinedButton(
                        style: regalosDialogCancelStyle(dt),
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: Text(l10n.giftDuplicateReview),
                      ),
                      confirm: FilledButton(
                        style: regalosDialogPrimaryStyle(dt),
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: Text(l10n.giftDuplicateSave),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
        if (keep != true) {
          return;
        }
      }
    }
    setState(() {
      _busy = true;
      _rejected = null;
    });
    // Guardar es una acción del usuario: si completa a la persona, se celebra.
    ref.read(celebrationArmedProvider.notifier).arm(gift.recipientId);
    if (gift.status == GiftStatus.delivered &&
        widget.gift?.status != GiftStatus.delivered) {
      ref.read(deliveredArmsProvider).arm(gift.id);
    }
    try {
      final controller = ref.read(familyControllerProvider.notifier);
      final personId = _giverPersonId;
      final result = personId == null
          ? await controller.upsertGiftResult(gift, original: _originalDraft)
          : await controller.upsertGiftWithGiverPerson(
              gift,
              personId,
              original: _originalDraft,
            );
      if (mounted && result != GiftWriteResult.saved) {
        // Otro móvil cambió algo mientras se editaba: no se ha guardado nada,
        // el aviso dice por qué y no se dibuja el visto.
        setState(() => _busy = false);
        showRegalosSnackBar(
          context,
          SnackBar(
            content: Text(
              giftWriteResultText(l10n, result, web: ref.read(webAppProvider)),
            ),
          ),
        );
      } else if (mounted) {
        // Solo lo que hace la persona lleva háptica. El visto se dibuja
        // mientras la tarjeta baja: no se espera a que termine.
        ref.read(hapticsProvider).light();
        setState(() => _saved = true);
        _close(gift.id);
      }
    } on GiverPersonNeedsPublicAdd catch (e) {
      // El regalo pasó a ser secreto con la persona ya elegida: no se crea en
      // silencio. El formulario se conserva; tras el paso explícito, la
      // persona queda elegida y se guarda con «Guardar».
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      final person = ref
          .read(familyFullViewProvider)
          .allRecipientsById[e.personId];
      if (person != null) {
        // La persona sigue elegida: al guardar se resuelve su quién regala.
        final added = await addPersonAsGiverExplicitly(context, ref, person);
        if (added != null && mounted) {
          setState(() => _giverPersonId = person.id);
        }
      }
    } on ProtectedPersonException catch (e) {
      if (!mounted) {
        return;
      }
      final name =
          ref.read(familyFullViewProvider).recipientsById[e.personId]?.name ??
          '';
      if (e.savedLocally) {
        _savedLocally(gift, e.personId);
      } else {
        // No se ha guardado nada y el formulario se conserva: el motivo, junto
        // a los campos.
        ref.read(hapticsProvider).medium();
        final reason = protectionReasonText(
          l10n,
          e.reason,
          name,
          web: ref.read(webAppProvider),
        );
        setState(() {
          _busy = false;
          _rejected = '$reason ${l10n.giftProtectedRejected}';
        });
        unawaited(_scrollToTop());
      }
    } on Object {
      if (mounted) {
        setState(() => _busy = false);
        showRegalosSnackBar(
          context,
          SnackBar(content: Text(l10n.giftSaveError)),
        );
      }
    } finally {
      // Acabado el guardado, con o sin rechazo, se vuelve a mirar si el
      // regalo sigue autorizado (durante el guardado no se decidía nada).
      if (mounted) {
        _scheduleAuthorizationCheck();
      }
    }
  }

  /// El regalo secreto quedó cifrado solo en este móvil: se cierra el editor y
  /// el aviso dice que está pendiente de guardar y compartir (sin afirmar que
  /// se haya compartido), con la puerta a los pendientes.
  void _savedLocally(Gift gift, String personId) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final style = regalosSnackBarStyle(context);
    final root = Navigator.of(context, rootNavigator: true).context;
    final notice = regalosSnackBar(
      context,
      SnackBar(
        persist: false,
        duration: const Duration(seconds: 8),
        content: Text(l10n.giftSavedLocally),
        action: SnackBarAction(
          label: l10n.giftSavedLocallyAction,
          onPressed: () {
            if (root.mounted) {
              unawaited(showPendingGiftsSheet(root, personId: personId));
            }
          },
        ),
      ),
      besideRail: SheetPane.anchorOf(context) != null,
    );
    ref.read(hapticsProvider).warning();
    setState(() => _saved = true);
    _close(gift.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(notice, snackBarAnimationStyle: style);
  }

  /// Abre o cierra «Más detalles». Al abrir, sube la vista para que los
  /// campos nuevos queden a la vista cuando acaba de desplegarse.
  void _toggleMore() {
    ref.read(hapticsProvider).light();
    final opening = !_moreOpen;
    setState(() => _moreOpen = opening);
    if (!opening) return;
    final reduce = RegalosMotion.of(context).reduce;
    Future<void>.delayed(
      reduce ? const Duration(milliseconds: 200) : RegalosSprings.snapDuration,
      () {
        final target = _moreKey.currentContext;
        if (!mounted || !_moreOpen || target == null || !target.mounted) {
          return;
        }
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: 0.02,
            duration: reduce ? Duration.zero : RegalosSprings.snapDuration,
            curve: RegalosCurves.snap,
          ),
        );
      },
    );
  }

  /// Los campos de «Más detalles» que ya tienen datos, para la fila plegada.
  String _moreSummary(AppLocalizations l10n, {required bool visible}) {
    bool has(TextEditingController c) => c.text.trim().isNotEmpty;
    return [
      if (!visible && has(_actual)) l10n.giftFieldActualPrice,
      if (!visible && has(_store)) l10n.giftFieldStore,
      if (has(_url)) l10n.giftFieldUrl,
      if (has(_size)) l10n.giftFieldSize,
      if (visible && has(_description)) l10n.wishFieldDescription,
      if (!visible && has(_note)) l10n.giftFieldNote,
    ].join(' · ');
  }

  Future<void> _scrollToTop() async {
    if (!_scroll.hasClients || _scroll.offset <= 0) {
      return;
    }
    final reduce = RegalosMotion.of(context).reduce;
    await _scroll.animateTo(
      0,
      duration: reduce ? Duration.zero : RegalosSprings.snapDuration,
      curve: RegalosCurves.snap,
    );
  }

  /// La clave del campo que lleva el foco [focus].
  GlobalKey? _titleKeyFor(FocusNode focus) => identical(focus, _titleFocus)
      ? _titleKey
      : (identical(focus, _requestNameFocus)
            ? _requestNameKey
            : (identical(focus, _actualFocus) ? _actualKey : _priceKey));

  /// Lleva la vista hasta el primer campo con error, de arriba abajo.
  Future<void> _showFirstError() async {
    final reduce = RegalosMotion.of(context).reduce;
    BuildContext? target;
    final FocusNode focus;
    if (_recipientId.isEmpty) {
      // El aviso de la persona está arriba del todo.
      if (_scroll.hasClients && _scroll.offset > 0) {
        await _scroll.animateTo(
          0,
          duration: reduce ? Duration.zero : RegalosSprings.snapDuration,
          curve: RegalosCurves.snap,
        );
      }
      return;
    } else if (_title.text.trim().isEmpty) {
      target = _titleKey.currentContext;
      focus = _titleFocus;
    } else if (_badPrice(_planned)) {
      target = _priceKey.currentContext;
      focus = _plannedFocus;
    } else if (_badPrice(_actual)) {
      // «Más detalles» acaba de abrirse: el campo aparece en un par de
      // cuadros.
      for (var i = 0; i < 3 && _actualKey.currentContext == null; i++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      target = _actualKey.currentContext;
      focus = _actualFocus;
    } else {
      target = _requestNameKey.currentContext;
      focus = _requestNameFocus;
    }
    if (target == null || !target.mounted) {
      // La lista no tiene montado ese campo (está lejos): primero se lleva
      // hasta arriba, donde están los campos, y luego se afina.
      if (!_scroll.hasClients) {
        return;
      }
      await _scroll.animateTo(
        0,
        duration: reduce ? Duration.zero : RegalosSprings.snapDuration,
        curve: RegalosCurves.snap,
      );
      if (!mounted) {
        return;
      }
      target = _titleKeyFor(focus)?.currentContext;
      if (target == null || !target.mounted) {
        return;
      }
    }
    // Solo se mueve lo que haga falta para verlo: cada política mueve en un
    // sentido (hacia arriba o hacia abajo) y la otra no hace nada.
    Future<void> reveal(ScrollPositionAlignmentPolicy policy) =>
        Scrollable.ensureVisible(
          target!,
          alignmentPolicy: policy,
          duration: reduce ? Duration.zero : RegalosSprings.snapDuration,
          curve: RegalosCurves.snap,
        );
    final scrolling = Future.wait([
      reveal(ScrollPositionAlignmentPolicy.keepVisibleAtStart),
      reveal(ScrollPositionAlignmentPolicy.keepVisibleAtEnd),
    ]);
    // El cursor se queda en el campo que hay que corregir.
    focus.requestFocus();
    await scrolling;
  }

  /// Cambia la persona: si la ocasión elegida es el cumpleaños de otra, ya no
  /// pega y se quita.
  void _pickRecipient(String id) {
    // La persona de este móvil no recibe regalos, solo deseos (en cualquiera
    // de los selectores): el editor se cierra llevando título, ocasión, talla,
    // enlace y descripción (nunca la nota privada ni los precios) y se abre
    // el de deseos. Nada se guarda hasta que se pulse «Guardar» allí.
    final onOwn = widget.onOwnPerson;
    if (_isNew && onOwn != null && ref.read(wishReaderProvider) == id) {
      String? text(TextEditingController c) {
        final value = c.text.trim();
        return value.isEmpty ? null : value;
      }

      onOwn(
        id,
        VisibleWishPatch(
          title: text(_title),
          occasionId: _occasionId == _none ? null : _occasionId,
          size: text(_size),
          url: text(_url),
          description: text(_description),
        ),
      );
      _close();
      return;
    }
    setState(() {
      _recipientId = id;
      _visible = widget.suggestVisible && ref.read(canSuggestWishProvider(id));
      final view = ref.read(familyFullViewProvider);
      if (_giverId != widget.gift?.giverId &&
          view.resolveGiver(_giverId)?.recipientId == id) {
        _giverId = _none;
      }
      if (_giverPersonId == id) {
        _giverPersonId = null;
      }
      if (_occasionId != _none) {
        for (final o in view.occasions) {
          if (o.id == _occasionId &&
              o.kind == OccasionKind.birthday &&
              o.recipientId != null &&
              o.recipientId != id) {
            _occasionId = _none;
          }
        }
      }
    });
    // Sin pedir el foco para el título: con el dedo o el ratón abriría el
    // teclado solo. Con Tab, `showAnchoredPicker` ya lleva el foco al campo
    // siguiente.
  }

  /// Cambia quién regala con lo elegido en el selector: un quién regala, «Sin
  /// asignar» o una persona de la sección «Personas». Elegir a una persona no
  /// crea nada todavía (se asigna al guardar), salvo el paso explícito de un
  /// regalo secreto, que se confirma aparte.
  Future<void> _pickGiver(
    String value,
    String? currentId,
    List<GiverPersonCandidate> candidates,
  ) async {
    if (!value.startsWith(_personPrefix)) {
      if (value != currentId || _giverPersonId != null) {
        setState(() {
          _giverId = value;
          _giverPersonId = null;
        });
      }
      return;
    }
    final personId = value.substring(_personPrefix.length);
    final candidate = candidates
        .where((c) => c.person.id == personId)
        .firstOrNull;
    if (candidate == null) {
      return;
    }
    if (!candidate.needsPublicAdd) {
      setState(() => _giverPersonId = personId);
      return;
    }
    final added = await addPersonAsGiverExplicitly(
      context,
      ref,
      candidate.person,
    );
    if (added != null && mounted) {
      setState(() => _giverPersonId = personId);
    }
  }

  /// Sin ninguna persona: crea la primera con la hoja de siempre y la deja
  /// elegida.
  Future<void> _addPerson() async {
    final l10n = AppLocalizations.of(context);
    final people = ref.read(familyFullViewProvider).recipients;
    final result = await showPersonSheet(
      context,
      defaultColorIndex: people.length,
    );
    if (result == null || !mounted) {
      return;
    }
    await saveRecipient(ref, l10n, result);
    if (mounted) {
      _pickRecipient(result.id);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final gift = widget.gift;
    if (gift == null || _busy || _deleting || _saved) {
      return;
    }
    final ok = await _trackedDialog(
      () => showRegalosConfirm(
        context,
        title: l10n.confirmDeleteTitle(gift.title),
        body: l10n.confirmDeleteBody,
        confirmLabel: l10n.actionEliminate,
        cancelLabel: l10n.actionCancel,
      ),
    );
    if (!ok || !mounted || _busy || _deleting || _saved || _closing) {
      return;
    }
    // El regalo desaparece al momento y la fila se pliega con la salida de
    // borrado cuando la tarjeta baja, pero la lápida no se escribe hasta que
    // caduca el aviso con «Deshacer» (el contenido sigue en memoria). Todo lo
    // que necesita el aviso se toma antes de cerrar: después ya no hay
    // pantalla de la que leerlo.
    final controller = ref.read(familyControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final style = regalosSnackBarStyle(context);
    // El aviso sale cuando el editor ya ha bajado: lo pinta la pantalla de
    // debajo, y si es la de las pestañas va centrado junto al raíl.
    final undoNotice = regalosSnackBar(
      context,
      SnackBar(
        // Con acción, Flutter la deja fija hasta que se toca: que caduque,
        // siempre antes que el borrado pendiente (ver [FamilyController.undoWindow]).
        persist: false,
        duration: FamilyController.undoNoticeDuration,
        content: Text(l10n.giftDeletedNotice(gift.title)),
        action: SnackBarAction(
          label: l10n.actionUndo,
          onPressed: () => unawaited(controller.undoDeleteGift(gift.id)),
        ),
      ),
      besideRail: SheetPane.anchorOf(context) != null,
    );
    ref.read(hapticsProvider).medium();
    ref.read(recentlyDeletedProvider.notifier).add(gift.id);
    setState(() => _deleting = true);
    var hidden = false;
    try {
      hidden = await controller.deleteGiftWithUndo(gift.id);
      if (mounted) {
        _close();
      }
    } on Object {
      if (mounted) {
        showRegalosSnackBar(context, SnackBar(content: Text(l10n.deleteError)));
      }
    } finally {
      if (!hidden) {
        // Falló o no borró nada: el regalo sigue ahí y se vuelve a mirar si
        // sigue autorizado.
        if (mounted) {
          setState(() => _deleting = false);
          _scheduleAuthorizationCheck();
        } else {
          _deleting = false;
        }
      }
    }
    if (!hidden) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(undoNotice, snackBarAnimationStyle: style);
  }

  void _scheduleAuthorizationCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuthorization());
  }

  /// Si el regalo que se edita ya no está en la proyección autorizada de este
  /// móvil (otro móvil lo movió a una persona protegida que es «Yo» aquí, por
  /// ejemplo), el editor se cierra solo, sin guardar y retirando el
  /// formulario, con un aviso. El regalo tiene que estar vivo en la vista
  /// autorizada: una lápida en el común (el regalo pasó a un ámbito secreto)
  /// tampoco vale. Mientras la proyección carga o falla, o se está guardando,
  /// no se decide nada y los campos no se pintan.
  void _checkAuthorization() {
    if (!mounted || _revoked || _closing) {
      return;
    }
    final projection = ref.read(authorizedProjectionProvider);
    final uncertain = projection.isLoading || projection.hasError;
    final view = ref.read(familyFullViewProvider);
    // Un diálogo con contenido de un regalo no sigue abierto con la
    // autorización incierta ni si el otro regalo que cita ya no se ve (también
    // al crear un regalo nuevo).
    if (_dialogs.isNotEmpty &&
        (uncertain ||
            _dialogs.values.any(
              (id) => id != null && !view.allGifts.any((g) => g.id == id),
            ))) {
      _closeDialogs();
    }
    final gift = widget.gift;
    if (gift == null || _saved || _busy || _deleting || uncertain) {
      return;
    }
    // La misma regla que la lista: el regalo tiene que estar en la vista
    // autorizada (un regalo vivo cuyo destinatario tiene lápida no está).
    if (ref.read(familyStateProvider) == null ||
        view.allGifts.any((g) => g.id == gift.id)) {
      return;
    }
    _revokeAccess();
  }

  void _revokeAccess() {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final style = regalosSnackBarStyle(context);
    final notice = regalosSnackBar(
      context,
      SnackBar(
        content: Text(
          ref.read(webAppProvider)
              ? l10n.giftNoLongerVisibleWeb
              : l10n.giftNoLongerVisible,
        ),
      ),
      besideRail: SheetPane.anchorOf(context) != null,
    );
    for (final c in [
      _title,
      _planned,
      _actual,
      _store,
      _url,
      _note,
      _description,
      _size,
      _requestNote,
      _requestName,
    ]) {
      c.clear();
    }
    ref.read(hapticsProvider).warning();
    setState(() => _revoked = true);
    // Los diálogos con contenido del regalo se cierran con el editor.
    _closing = true;
    _closeDialogs();
    if (widget.asPanel) {
      widget.onClose?.call(null);
    } else {
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) {
        Navigator.of(context).pop();
      } else if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(notice, snackBarAnimationStyle: style);
  }

  @override
  Widget build(BuildContext context) =>
      GiftsSecureScope(child: _buildEditor(context));

  Widget _buildEditor(BuildContext context) {
    // En la web, lo que habla del propio dispositivo dice «este ordenador».
    final web = ref.watch(webAppProvider);
    ref.listen(familyStateProvider, (_, _) => _scheduleAuthorizationCheck());
    ref.listen(
      authorizedProjectionProvider,
      (_, _) => _scheduleAuthorizationCheck(),
    );
    if (_revoked) {
      return const SizedBox.expand();
    }
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final view = ref.watch(familyFullViewProvider);
    final projectionAsync = ref.watch(authorizedProjectionProvider);
    final projection = projectionAsync.value;
    // Con la autorización incierta (la proyección carga o falla, o se está
    // guardando) un regalo que ya existe no pinta sus campos.
    final uncertain =
        widget.gift != null &&
        (projectionAsync.isLoading ||
            projectionAsync.hasError ||
            (_busy && !_saved));
    final labels = OccasionLabels(l10n, view.recipientsById);
    final people = view.recipients;
    final givers = view.selectableGiversFor(_recipientId);
    // Las personas de la familia que aún no son quién regala. En un regalo
    // secreto (o para una persona protegida) hay que añadirlas antes por un
    // paso explícito.
    final giftProtected =
        (widget.gift != null &&
            projection?.secretGiftIds.contains(widget.gift!.id) == true) ||
        projection?.policies[_recipientId]?.hideOwnGifts == true;
    final giverPeople = _recipientId.isEmpty
        ? const <GiverPersonCandidate>[]
        : personSectionOf(
            view.giverPersonCandidatesFor(
              _recipientId,
              protected: giftProtected,
            ),
          );
    // La persona elegida en «Personas» se resuelve con la vista de ahora: si
    // entre tanto tiene un quién regala activo (se dio de alta en otro móvil o
    // en el paso explícito), el campo muestra ese; si no, a la persona.
    final chosenPerson = _giverPersonId;
    final chosenGiver = chosenPerson == null
        ? null
        : view.giverForPerson(chosenPerson);
    final chosenActive = chosenGiver != null && !chosenGiver.archived
        ? (view.resolveGiver(chosenGiver.id)?.id ?? chosenGiver.id)
        : null;
    final chosenLabel = chosenPerson == null
        ? null
        : view.giverForPersonLabel(chosenPerson);
    final selectedGiver = view.resolveGiver(_giverId);
    final selectedIsAvailable = givers.any((g) => g.id == selectedGiver?.id);
    final historicalGiver =
        selectedIsAvailable || _giverId != widget.gift?.giverId
        ? null
        : selectedGiver;
    final occasions = [
      for (final o in view.occasions)
        if (!o.archived || o.id == widget.gift?.occasionId) o,
    ];
    // Regalos en secreto: las personas protegidas que este móvil no puede
    // elegir salen apagadas, con su motivo.
    final access = {
      for (final a
          in ref.watch(giftRecipientAccessProvider).value ??
              const <GiftRecipientAccess>[])
        a.recipient.id: a,
    };
    PickerOption<String> personOption(Recipient p, {required bool gated}) {
      // A quien se le puede sugerir un deseo visible se le puede elegir aunque
      // este móvil no pueda guardarle una sorpresa: el deseo no la necesita.
      // La persona de este móvil tampoco se bloquea: lo suyo son deseos, y al
      // elegirla se abre el editor de deseos.
      final reason =
          gated &&
              !(_isNew &&
                  (ref.watch(canSuggestWishProvider(p.id)) ||
                      ref.watch(wishReaderProvider) == p.id))
          ? _blockedReason(access, p.id)
          : null;
      return PickerOption(
        value: p.id,
        label: p.name,
        enabled: reason == null,
        hint: reason == null
            ? null
            : protectionReasonText(l10n, reason, p.name, web: web),
        leading: PersonAvatar(name: p.name, colorIndex: p.colorIndex, size: 28),
      );
    }

    final personOptions = [
      // Quien solo regala no es destinatario; solo se conserva en un regalo
      // que ya era suyo (historia).
      for (final p in people)
        if (!p.noGifts || p.id == widget.gift?.recipientId)
          // Un regalo nuevo no se apunta a una persona archivada (salvo que
          // ya esté elegida).
          if (!_isNew || !p.archived || p.id == _recipientId)
            personOption(p, gated: true),
    ];
    // Quien lo pidió puede ser cualquiera: ahí no se apaga a nadie.
    final requesterOptions = [
      for (final p in people)
        if (!_isNew || !p.archived || p.id == _recipientId)
          personOption(p, gated: false),
    ];
    final blockedReason = _blockedReason(access, _recipientId);
    final blockedName = people
        .where((p) => p.id == _recipientId)
        .map((p) => p.name)
        .firstOrNull;
    // Aviso junto a la persona cuando no se puede guardar para ella.
    final canSuggest =
        !web && _isNew && ref.watch(canSuggestWishProvider(_recipientId));
    final visible = canSuggest && _visible;
    final recipientNotice = UnfoldSection(
      show: blockedReason != null && !visible,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Semantics(
          liveRegion: true,
          child: WarningBox(
            blockedReason == null
                ? ''
                : protectionReasonText(
                    l10n,
                    blockedReason,
                    blockedName ?? '',
                    web: web,
                  ),
          ),
        ),
      ),
    );
    final selfId = ref.watch(selfRecipientIdProvider);
    final ownRestricted =
        ref.watch(ownGiftRequestStateProvider).value ==
        OwnGiftRequestState.protectionRestricted;
    final occasionOptions = _occasionOptions(l10n, labels, occasions, t);
    const gap = SizedBox(height: 16);

    final dialog = widget.asDialog;
    final panel = widget.asPanel;
    final title = _isNew ? l10n.giftEditorNewTitle : l10n.giftEditorEditTitle;
    // Ya guardado el botón se queda con su color: el visto sigue
    // dibujándose mientras baja la tarjeta.
    final VoidCallback? onSave = _saved
        ? () {}
        : (_busy || _deleting ? null : _save);
    // Guardar y borrar no se solapan: mientras una está en curso, la otra no
    // responde (en la hoja, el panel y el diálogo).
    final VoidCallback? onDelete = _busy || _saved || _deleting
        ? null
        : _delete;
    final saveChild = _saved
        ? DrawnCheck(color: t.onFill, size: 22, strokeWidth: 2.4)
        : Text(l10n.actionSave);
    final bodyList = LayoutBuilder(
      builder: (context, box) {
        // Dos columnas desde 1280 de ventana (la hoja de 880): lo
        // que identifica el regalo a la izquierda y su detalle a la
        // derecha. Por debajo, una columna, como siempre.
        final two =
            RegalosLayout.isDesktop(MediaQuery.sizeOf(context).width) &&
            box.maxWidth >= RegalosLayout.editorTwoColumnsMinWidth;
        final identity = <Widget>[
          // El guardado se rechazó: el motivo, arriba, y el formulario
          // intacto.
          UnfoldSection(
            show: _rejected != null,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Semantics(
                liveRegion: true,
                child: WarningBox(_rejected ?? ''),
              ),
            ),
          ),
          if (_choosing) ...[
            _RecipientChooser(
              label: l10n.fieldFor,
              options: personOptions,
              value: _recipientId,
              invalid: _tried && _recipientId.isEmpty,
              onChanged: _pickRecipient,
              onAddPerson: _addPerson,
            ),
            recipientNotice,
            gap,
          ],
          TextField(
            key: _titleKey,
            controller: _title,
            focusNode: _titleFocus,
            autofocus: _isNew && (!_choosing || _recipientId.isNotEmpty),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.giftFieldTitle,
              hintText: l10n.giftFieldTitleHint,
              errorText: _tried && _title.text.trim().isEmpty
                  ? l10n.giftFieldTitleRequired
                  : null,
            ),
            onChanged: (_) {
              if (_tried) {
                setState(() {});
              }
            },
          ),
          gap,
          // «Visible para [persona]» (ADR 0010): por defecto apagado, y es
          // una sorpresa como siempre.
          if (canSuggest) ...[
            SwitchRow(
              key: const ValueKey<String>('gift-visible-switch'),
              title: l10n.giftVisibleSwitch(blockedName ?? ''),
              hint: l10n.giftVisibleHint(blockedName ?? ''),
              value: _visible,
              // Con el bloque cerrado no hay otra forma de guardar: fijo.
              onChanged: widget.suggestVisible
                  ? null
                  : (v) => setState(() => _visible = v),
            ),
            if (widget.suggestVisible) ...[
              SwitchRow(
                key: const ValueKey<String>('gift-surprise-disabled'),
                title: l10n.giftSurpriseSwitch,
                hint: l10n.giftVisibleNoSurprise(blockedName ?? ''),
                value: false,
                onChanged: null,
              ),
            ],
            gap,
          ],
          if (!_choosing) ...[
            PickerField<String>(
              label: l10n.fieldFor,
              value: _recipientId,
              options: personOptions,
              onChanged: _pickRecipient,
            ),
            recipientNotice,
            gap,
          ],
          UnfoldSection(
            show: !visible,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PickerField<String>(
                  label: l10n.fieldGiver,
                  value: chosenPerson != null
                      ? (chosenActive ?? '$_personPrefix$chosenPerson')
                      : (selectedIsAvailable || historicalGiver != null
                            ? selectedGiver!.id
                            : _none),
                  options: [
                    PickerOption(
                      value: _none,
                      label: l10n.giverUnassigned,
                      leading: const GiverDot(size: 12),
                    ),
                    for (final g in givers)
                      PickerOption(
                        value: g.id,
                        label: giverNameFor(l10n, g),
                        leading: GiverDot(colorIndex: g.colorIndex, size: 12),
                      ),
                    if (historicalGiver != null)
                      PickerOption(
                        value: historicalGiver.id,
                        label: giverNameFor(l10n, historicalGiver),
                        leading: GiverDot(
                          colorIndex: historicalGiver.colorIndex,
                          size: 12,
                        ),
                        enabled: false,
                      ),
                    for (final c in giverPeople)
                      PickerOption(
                        value: '$_personPrefix${c.person.id}',
                        label: c.person.name,
                        group: l10n.giverPeopleSection,
                        hint: personCandidateHint(l10n, c),
                        leading: PersonAvatar(
                          name: c.person.name,
                          colorIndex: c.person.colorIndex,
                          size: 28,
                        ),
                      ),
                    // La elegida sigue ahí aunque ya no sea una candidata.
                    if (chosenPerson != null &&
                        chosenActive == null &&
                        chosenLabel != null &&
                        !giverPeople.any((c) => c.person.id == chosenPerson))
                      PickerOption(
                        value: '$_personPrefix$chosenPerson',
                        label: chosenLabel,
                        group: l10n.giverPeopleSection,
                        leading: PersonAvatar(
                          name: chosenLabel,
                          colorIndex:
                              view
                                  .allRecipientsById[chosenPerson]
                                  ?.colorIndex ??
                              0,
                          size: 28,
                        ),
                      ),
                  ],
                  onChanged: (v) =>
                      _pickGiver(v, selectedGiver?.id, giverPeople),
                ),
                gap,
              ],
            ),
          ),
          PickerField<String>(
            label: l10n.fieldOccasion,
            value: occasions.any((o) => o.id == _occasionId)
                ? _occasionId
                : _none,
            options: occasionOptions,
            onChanged: (v) => setState(() => _occasionId = v),
          ),
          gap,
          UnfoldSection(
            show: !visible,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.fieldStatus,
                    style: t.styles.label.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                ChoiceGrid(
                  leadingSize: kStatusChoiceGlyph,
                  leadingGap: kStatusChoiceGap,
                  items: [
                    for (final status in GiftStatus.values)
                      statusChoice(
                        l10n,
                        status,
                        selected: status == _status,
                        onTap: () => setState(() => _status = status),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ];
        final moreFields = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UnfoldSection(
              show: !visible,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: _actualKey,
                    controller: _actual,
                    focusNode: _actualFocus,
                    keyboardType: moneyKeyboard,
                    inputFormatters: moneyInputFormatters,
                    decoration: InputDecoration(
                      labelText: l10n.giftFieldActualPrice,
                      suffixText: '€',
                      errorText: _tried && _badPrice(_actual)
                          ? l10n.giftPriceInvalid
                          : null,
                      errorMaxLines: 3,
                    ),
                  ),
                  gap,
                  TextField(
                    controller: _store,
                    textCapitalization: TextCapitalization.sentences,
                    // Solo salta con lo que escribe la persona, no con el
                    // relleno del enlace: desde ahí, la tienda ya es suya.
                    onChanged: (_) {
                      _storeTouched = true;
                      _autoStore = null;
                    },
                    decoration: InputDecoration(labelText: l10n.giftFieldStore),
                  ),
                  gap,
                ],
              ),
            ),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: _onUrlChanged,
              decoration: InputDecoration(
                labelText: l10n.giftFieldUrl,
                suffixIcon: _openLinkButton(l10n),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 48,
                ),
              ),
            ),
            gap,
            TextField(
              controller: _size,
              decoration: InputDecoration(labelText: l10n.giftFieldSize),
            ),
            gap,
            TextField(
              // Un campo distinto para cada uso: la descripción pública y
              // la nota privada tienen cada una su borrador.
              key: ValueKey<String>(visible ? 'gift-description' : 'gift-note'),
              controller: visible ? _description : _note,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: visible
                    ? l10n.wishFieldDescription
                    : l10n.giftFieldNote,
              ),
            ),
          ],
        );
        // Lo esencial a la vista: el precio previsto y los dos interruptores que
        // cambian cómo se enseña el regalo (encargo y sorpresa). El resto de
        // campos, opcionales, van plegados en «Más detalles».
        final details = <Widget>[
          UnfoldSection(
            show: !visible,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.giftPriceSection,
                    style: t.styles.label.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  key: _priceKey,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _planned,
                        focusNode: _plannedFocus,
                        keyboardType: moneyKeyboard,
                        inputFormatters: moneyInputFormatters,
                        decoration: InputDecoration(
                          labelText: l10n.giftFieldPlanned,
                          suffixText: '€',
                          errorText: _tried && _badPrice(_planned)
                              ? l10n.giftPriceInvalid
                              : null,
                          errorMaxLines: 3,
                        ),
                      ),
                    ),
                  ],
                ),
                gap,
                SwitchRow(
                  title: l10n.giftRequestSwitch,
                  value: _isRequest,
                  onChanged: (v) => setState(() => _isRequest = v),
                ),
                // Los campos del pedido se despliegan al activar el
                // interruptor y se pliegan al apagarlo.
                UnfoldSection(
                  show: _isRequest,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      PickerField<String>(
                        label: l10n.giftRequestedByField,
                        value:
                            _requestedBy == _other ||
                                people.any((p) => p.id == _requestedBy)
                            ? _requestedBy
                            : _other,
                        options: [
                          ...requesterOptions,
                          PickerOption(
                            value: _other,
                            label: l10n.giftRequestedByOther,
                          ),
                        ],
                        onChanged: (v) => setState(() => _requestedBy = v),
                      ),
                      // Mientras la protección de la propia persona esté activa,
                      // este móvil no puede crear ni ver sus peticiones.
                      UnfoldSection(
                        show:
                            ownRestricted &&
                            selfId != null &&
                            _requestedBy == selfId,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: WarningBox(
                              web
                                  ? l10n.giftOwnRequestRestrictedWeb
                                  : l10n.giftOwnRequestRestricted,
                            ),
                          ),
                        ),
                      ),
                      UnfoldSection(
                        show: _requestedBy == _other,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextField(
                            key: _requestNameKey,
                            controller: _requestName,
                            focusNode: _requestNameFocus,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: l10n.giftRequestedByName,
                              errorText:
                                  _tried && _requestName.text.trim().isEmpty
                                  ? l10n.fieldNameRequired
                                  : null,
                            ),
                            onChanged: (_) {
                              if (_tried) {
                                setState(() {});
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _requestNote,
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: l10n.giftRequestNote,
                        ),
                      ),
                    ],
                  ),
                ),
                gap,
                SwitchRow(
                  title: l10n.giftSurpriseSwitch,
                  hint: l10n.giftSurpriseHint,
                  value: _surprise,
                  onChanged: (v) => setState(() => _surprise = v),
                ),
                gap,
              ],
            ),
          ),
          // Con las dos columnas (diálogo y panel anchos) cabe todo: sin
          // pliegue. En una columna, lo opcional va en «Más detalles».
          if (two)
            moreFields
          else
            MoreDetails(
              key: _moreKey,
              title: l10n.giftMoreDetails,
              open: _moreOpen,
              onToggle: _toggleMore,
              summary: _moreSummary(l10n, visible: visible),
              child: moreFields,
            ),
          // En el panel del tablero y en el diálogo de escritorio, «Borrar
          // regalo» va en el pie (a la izquierda, como botón de texto): al
          // final de la lista se cortaba con el pie al desplazarse.
          if (!_isNew && !panel && !dialog) ...[
            const SizedBox(height: 24),
            DangerButton(label: l10n.giftDelete, onPressed: onDelete),
          ],
        ];
        return ListView(
          controller: _scroll,
          // En el diálogo la lista mide lo que su contenido y solo
          // se desplaza si no cabe en la ventana.
          shrinkWrap: dialog,
          padding: panel
              ? const EdgeInsets.fromLTRB(20, 8, 20, 24)
              : (dialog
                    ? const EdgeInsets.fromLTRB(24, 8, 24, 24)
                    : const EdgeInsets.fromLTRB(16, 16, 16, 24)),
          children: two
              ? [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: identity,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: details,
                        ),
                      ),
                    ],
                  ),
                ]
              : [...identity, gap, ...details],
        );
      },
    );
    // Los campos del panel miden lo mismo que los de la hoja: 48 de alto, del
    // tema.
    final body = uncertain ? const SizedBox.expand() : bodyList;
    // Esc cierra el editor, como la «x» de la cabecera (la hoja no se cierra
    // tocando fuera: tiene datos sin guardar). Ya guardado o guardando, no. El
    // foco es de la tarjeta desde que se abre (en un regalo nuevo lo toma el
    // título): así Esc llega aunque no se haya tocado nada.
    // Volver (gesto, botón del sistema, Esc, arrastrar la hoja o tocar fuera)
    // pasa por aquí: con cambios sin guardar se pregunta antes de descartarlos.
    // El panel de la web no es una ruta: no hay nada que interceptar.
    return PopScope(
      canPop: widget.asPanel,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_requestClose());
        }
      },
      child: Focus(
        autofocus: !(_isNew && (!_choosing || _recipientId.isNotEmpty)),
        skipTraversal: true,
        // Sin nodo de accesibilidad propio: uniría lo de debajo en uno solo.
        includeSemantics: false,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent ||
              event.logicalKey != LogicalKeyboardKey.escape ||
              _busy ||
              _saved) {
            return KeyEventResult.ignored;
          }
          if (widget.asPanel) {
            unawaited(_requestClose());
          } else {
            unawaited(Navigator.of(context).maybePop());
          }
          return KeyEventResult.handled;
        },
        child: panel
            // Panel fijo de la derecha del tablero de la web: cabecera con su
            // «x», el formulario ocupando el alto y «Cancelar» y «Guardar»
            // abajo a la derecha. No tapa nada: la pantalla de al lado se
            // estrecha.
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ScreenHeader(
                    title: title,
                    compactTitle: true,
                    actions: [
                      Semantics(
                        button: true,
                        label: l10n.actionClose,
                        excludeSemantics: true,
                        onTap: _busy || _saved ? null : _requestClose,
                        child: Tooltip(
                          message: l10n.actionClose,
                          excludeFromSemantics: true,
                          child: SizedBox.square(
                            dimension: 44,
                            child: InkResponse(
                              onTap: _busy || _saved ? null : _requestClose,
                              radius: 22,
                              child: Center(
                                child: StrokeIcon(
                                  AppIcons.close,
                                  size: 22,
                                  color: t.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(child: body),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: t.separator)),
                    ),
                    child: EditorFooterRow(
                      start: _isNew
                          ? null
                          : DangerButton(
                              label: l10n.giftDelete,
                              onPressed: onDelete,
                              compact: true,
                            ),
                      end: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: _busy || _saved ? null : _requestClose,
                            child: Text(l10n.actionCancel),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(onPressed: onSave, child: saveChild),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : dialog
            // En escritorio es un diálogo: cabecera sin flecha, el formulario
            // con el alto de su contenido (y desplazable si no cabe) y
            // «Cancelar» y «Guardar» abajo a la derecha.
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ScreenHeader(title: title, compactTitle: true),
                  Flexible(child: body),
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: t.separator)),
                    ),
                    child: EditorFooterRow(
                      start: _isNew
                          ? null
                          : DangerButton(
                              label: l10n.giftDelete,
                              onPressed: onDelete,
                              compact: true,
                            ),
                      end: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: _busy || _saved ? null : _requestClose,
                            child: Text(l10n.actionCancel),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(onPressed: onSave, child: saveChild),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : EdgeSwipeBack(
                onBack: () => unawaited(_requestClose()),
                enabled: !_closeBlocked,
                child: Scaffold(
                  body: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        CardSheetHandle(
                          child: ScreenHeader(
                            title: title,
                            onBack: () => unawaited(_requestClose()),
                            backLabel: l10n.actionClose,
                            compactTitle: true,
                          ),
                        ),
                        Expanded(child: body),
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: t.separator)),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: onSave,
                              child: saveChild,
                            ),
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

/// La persona del regalo cuando se elige arriba del todo: el campo de
/// siempre, con el aviso si se intenta guardar sin elegir; y, si todavía no
/// hay ninguna persona, la invitación a crear la primera.
class _RecipientChooser extends StatelessWidget {
  const _RecipientChooser({
    required this.label,
    required this.options,
    required this.value,
    required this.invalid,
    required this.onChanged,
    required this.onAddPerson,
  });

  final String label;
  final List<PickerOption<String>> options;
  final String value;
  final bool invalid;
  final ValueChanged<String> onChanged;
  final VoidCallback onAddPerson;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final Widget body;
    if (options.isEmpty) {
      body = Column(
        key: const ValueKey('recipient-none'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.giftEditorNoPeople, style: t.styles.body),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onAddPerson, child: Text(l10n.obPeopleAdd)),
        ],
      );
    } else {
      body = PickerField<String>(
        key: const ValueKey('recipient-picker'),
        label: label,
        value: value,
        options: options,
        onChanged: onChanged,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueSwitcher(child: body),
        // El aviso entra desplegándose, sin saltos.
        UnfoldSection(
          show: invalid,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 12, 0),
            child: Semantics(
              liveRegion: true,
              // Ancho completo y a la izquierda, como el error de «Regalo»
              // (`UnfoldSection` centra lo que no ocupa todo el ancho).
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  l10n.giftRecipientRequired,
                  textAlign: TextAlign.start,
                  style: t.styles.meta.copyWith(color: t.danger),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Las ocasiones para la hoja de selección: «Sin ocasión» arriba, luego las
/// fiestas y después los cumpleaños, como en la pantalla Ocasiones.
List<PickerOption<String>> _occasionOptions(
  AppLocalizations l10n,
  OccasionLabels labels,
  List<Occasion> occasions,
  RegalosTokens t,
) {
  final ordered = occasionsByNextDate(occasions, clock.now());
  PickerOption<String> option(Occasion o, String group) {
    final p = OccasionTheme.forOccasion(o).palette;
    return PickerOption(
      value: o.id,
      label: labels.of(o),
      group: group,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: p.surfaceOf(t.isDark),
          borderRadius: RegalosShape.chip,
        ),
        child: SizedBox.square(
          dimension: 28,
          child: Center(
            child: OccasionKindIcon(
              o.kind,
              customIcon: o.icon,
              size: 18,
              color: p.inkOf(t.isDark),
            ),
          ),
        ),
      ),
    );
  }

  return [
    PickerOption(
      value: _none,
      label: l10n.giftNoOccasion,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: t.track,
          borderRadius: RegalosShape.chip,
        ),
        child: SizedBox.square(
          dimension: 28,
          child: Icon(
            Icons.horizontal_rule_rounded,
            size: 18,
            color: t.textSecondary,
          ),
        ),
      ),
    ),
    for (final o in ordered)
      if (o.kind != OccasionKind.birthday)
        option(o, l10n.occasionsGroupCelebrations),
    for (final o in ordered)
      if (o.kind == OccasionKind.birthday)
        option(o, l10n.occasionsGroupBirthdays),
  ];
}

/// Las opciones del selector de ocasión del editor, para el de deseos.
List<PickerOption<String>> occasionPickerOptions(
  AppLocalizations l10n,
  OccasionLabels labels,
  List<Occasion> occasions,
  RegalosTokens t,
) => _occasionOptions(l10n, labels, occasions, t);
