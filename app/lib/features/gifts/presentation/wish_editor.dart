import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money_input.dart';
import '../../../core/format/short_title.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/card_sheet_route.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/sheet_motion.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/platform/user_link.dart';
import '../../../core/sync/model.dart';
import '../../../core/sync/wish.dart';
import '../../../core/sync/wish_plan.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/choice_grid.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/danger_button.dart';
import '../../../core/widgets/edge_swipe_back.dart';
import '../../../core/widgets/giver_dot.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/screen_header.dart';
import '../../../core/widgets/sheet_parts.dart' show WarningBox;
import '../../../core/widgets/tag_label.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/wish_service.dart';
import '../../family/presentation/family_texts.dart';
import '../../family/presentation/protection_texts.dart';
import '../../web_device/application/web_app_provider.dart';
import 'gift_actions.dart';
import 'gift_editor_screen.dart'
    show giftEditorAsDialogProvider, kPickerNone, occasionPickerOptions;
import 'gift_link_actions.dart';
import 'wish_claim_problem.dart';

/// El texto corto de por qué una acción sobre un deseo no se hizo. [name] es
/// la persona del deseo (para los avisos que la nombran).
String wishProblemText(
  AppLocalizations l10n,
  WishResult result, {
  String name = '',
  bool web = false,
}) => switch (result.problem) {
  null => '',
  WishProblem.capReached => l10n.wishProblemCap,
  WishProblem.tooLarge => l10n.wishProblemTooLarge,
  WishProblem.invalidField => l10n.wishProblemInvalid,
  WishProblem.notOwner => l10n.wishProblemNotOwner,
  WishProblem.wishGone => l10n.wishProblemGone,
  WishProblem.alreadyClaimed => l10n.wishProblemClaimed,
  WishProblem.waitingApproval => l10n.wishProblemApproval,
  WishProblem.notAllowed => l10n.wishProblemNotAllowed,
  WishProblem.noDevice => l10n.wishProblemNoDevice(name),
  WishProblem.blockUnavailable =>
    result.reason == null
        ? l10n.wishProblemBlock(name)
        : protectionReasonText(l10n, result.reason!, name, web: web),
  WishProblem.blockFull => l10n.wishProblemBlockFull(name),
  WishProblem.devicesNeedUpdate => l10n.wishProblemDevicesNeedUpdate,
  WishProblem.failed => l10n.wishProblemFailed,
};

/// Dice en un aviso por qué no se hizo [result].
void showWishProblem(
  BuildContext context,
  WidgetRef ref,
  WishResult result, {
  String name = '',
}) {
  final l10n = AppLocalizations.of(context);
  ref.read(hapticsProvider).medium();
  showRegalosSnackBar(
    context,
    SnackBar(
      content: Text(
        wishProblemText(
          l10n,
          result,
          name: name,
          web: ref.read(webAppProvider),
        ),
      ),
    ),
  );
}

/// Coge el deseo [wish] de otra persona: crea el plan y lo dice. Un fallo se
/// dice con su texto.
Future<bool> claimWishFlow(
  BuildContext context,
  WidgetRef ref,
  Wish wish, {
  BuildContext? rowContext,
}) async {
  final l10n = AppLocalizations.of(context);
  final name =
      ref
          .read(familyFullViewProvider)
          .allRecipientsById[wish.recipientId]
          ?.name ??
      '';
  final result = await ref.read(wishServiceProvider).claim(wish.id);
  if (!context.mounted) return result.ok;
  if (!result.ok) {
    if (wishClaimNeedsFamily(result, web: ref.read(webAppProvider))) {
      showWishClaimNeedsFamily(context, ref, rowContext: rowContext);
    } else {
      showWishProblem(context, ref, result, name: name);
    }
    return false;
  }
  ref.read(hapticsProvider).light();
  showRegalosSnackBar(
    context,
    SnackBar(
      content: Text(
        result.pending
            ? l10n.wishSavedPending
            : l10n.wishClaimedNotice(quotedTitle(wish.title)),
      ),
    ),
  );
  return true;
}

/// Cierra el editor y, si hay [text], lo dice con un aviso que pinta la
/// pantalla de debajo.
void _closeWithNotice(BuildContext context, String? text) {
  final messenger = ScaffoldMessenger.of(context);
  final style = regalosSnackBarStyle(context);
  final notice = text == null
      ? null
      : regalosSnackBar(context, SnackBar(content: Text(text)));
  Navigator.of(context).pop();
  if (notice != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(notice, snackBarAnimationStyle: style);
  }
}

/// La pregunta del editor de regalos al cerrar con cambios sin guardar: los
/// mismos textos y el mismo diálogo.
Future<bool> _confirmDiscard(BuildContext context, {bool wish = false}) {
  final l10n = AppLocalizations.of(context);
  return showRegalosConfirm(
    context,
    title: l10n.giftDiscardTitle,
    body: wish ? l10n.wishDiscardBody : l10n.giftDiscardBody,
    confirmLabel: l10n.actionDiscard,
    cancelLabel: l10n.giftKeepEditing,
  );
}

bool _asDialog(BuildContext context) =>
    RegalosLayout.isDesktop(MediaQuery.sizeOf(context).width) &&
    ProviderScope.containerOf(context).read(giftEditorAsDialogProvider);

Future<T?> _openFrame<T>(BuildContext context, Widget Function(bool) builder) {
  final dialog = _asDialog(context);
  Widget page(BuildContext _) => builder(dialog);
  return dialog
      ? showCardDialog<T>(context, builder: page)
      : showCardSheet<T>(context, builder: page);
}

/// Abre el editor de un deseo: nuevo (sin [wish]) o existente. Devuelve el id
/// del deseo guardado, o `null` si no se guardó nada.
Future<String?> openWishEditor(
  BuildContext context, {
  Wish? wish,
  required String recipientId,
  VisibleWishPatch? draft,
}) => _openFrame<String>(
  context,
  (dialog) => WishEditor(
    wish: wish,
    recipientId: recipientId,
    initialDraft: draft,
    asDialog: dialog,
  ),
);

/// Abre el deseo de otra persona para leerlo y cogerlo.
///
/// En el móvil y la tablet es una hoja que mide lo que contiene; en la web de
/// escritorio, el diálogo de los editores.
Future<void> openWishDetail(
  BuildContext context, {
  required String person,
  required String wishId,
}) => _asDialog(context)
    ? showCardDialog<void>(
        context,
        builder: (_) =>
            WishDetail(person: person, wishId: wishId, asDialog: true),
      )
    : showRegalosSheet<void>(
        context,
        flat: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => WishDetail(person: person, wishId: wishId),
      );

/// Abre el plan [planId] de [person] (un deseo que alguien ha cogido).
Future<void> openWishPlanEditor(
  BuildContext context, {
  required String person,
  required WishPlan plan,
}) => _openFrame<void>(
  context,
  (dialog) => WishPlanEditor(person: person, plan: plan, asDialog: dialog),
);

/// El marco de los editores de deseos: la tarjeta que sube desde abajo, o el
/// diálogo de la web de escritorio.
class _EditorFrame extends StatelessWidget {
  const _EditorFrame({
    required this.title,
    required this.asDialog,
    required this.children,
    required this.onClose,
    this.primary,
    this.guarded = false,
    this.autofocusFrame = true,
  });

  final String title;
  final bool asDialog;
  final List<Widget> children;

  /// El cierre que pide la persona (flecha, «Cancelar», Esc, el gesto de
  /// volver): con [guarded] pregunta antes de descartar cambios.
  final VoidCallback onClose;

  /// Si volver (gesto, botón del sistema, Esc) pasa por [onClose] en vez de
  /// cerrar: los editores con cambios sin guardar, como el de regalos.
  final bool guarded;

  /// Si el marco toma el foco al abrirse (para que Esc llegue). No si un
  /// campo ya lo toma con `autofocus`.
  final bool autofocusFrame;

  /// El botón principal (Guardar, «Lo regalo yo»), o `null` si no hay.
  final Widget? primary;

  @override
  Widget build(BuildContext context) {
    final content = _content(context);
    if (!guarded) return content;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onClose();
      },
      child: Focus(
        autofocus: autofocusFrame,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent ||
              event.logicalKey != LogicalKeyboardKey.escape) {
            return KeyEventResult.ignored;
          }
          onClose();
          return KeyEventResult.handled;
        },
        child: content,
      ),
    );
  }

  Widget _content(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    if (asDialog) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(title: title, compactTitle: true),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: children,
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.separator)),
            ),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(onPressed: onClose, child: Text(l10n.actionCancel)),
                ?primary,
              ],
            ),
          ),
        ],
      );
    }
    final card = Scaffold(
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            CardSheetHandle(
              child: ScreenHeader(
                title: title,
                onBack: onClose,
                backLabel: l10n.actionClose,
                compactTitle: true,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: children,
              ),
            ),
            if (primary != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.separator)),
                ),
                child: SizedBox(width: double.infinity, child: primary),
              ),
          ],
        ),
      ),
    );
    // El gesto de volver de iOS (borde izquierdo) pasa por el mismo cierre
    // que la flecha: con cambios sin guardar pregunta antes.
    return guarded ? EdgeSwipeBack(onBack: onClose, child: card) : card;
  }
}

const SizedBox _gap = SizedBox(height: 16);

/// El editor de un deseo propio: título, ocasión, talla, enlace y
/// descripción. Solo lo abre la persona del deseo.
class WishEditor extends ConsumerStatefulWidget {
  /// Crea el editor.
  const WishEditor({
    super.key,
    this.wish,
    required this.recipientId,
    this.initialDraft,
    this.asDialog = false,
  });

  /// El deseo que se edita, o `null` para uno nuevo.
  final Wish? wish;

  /// Lo que ya estaba escrito en un deseo nuevo (viene del editor de regalos
  /// al elegir a la persona de este móvil): título, ocasión, talla, enlace y
  /// descripción. No cuenta como guardado: cerrar pregunta antes de descartar.
  final VisibleWishPatch? initialDraft;

  /// La persona del deseo.
  final String recipientId;

  /// Si es el diálogo de la web de escritorio.
  final bool asDialog;

  @override
  ConsumerState<WishEditor> createState() => _WishEditorState();
}

class _WishEditorState extends ConsumerState<WishEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.wish?.title ?? widget.initialDraft?.title,
  );
  late final TextEditingController _size = TextEditingController(
    text: widget.wish?.size ?? widget.initialDraft?.size,
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.wish?.url ?? widget.initialDraft?.url,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.wish?.description ?? widget.initialDraft?.description,
  );
  late String _occasionId =
      widget.wish?.occasionId ?? widget.initialDraft?.occasionId ?? kPickerNone;
  bool _tried = false;
  bool _busy = false;
  bool _closing = false;
  late final String _initial;

  @override
  void initState() {
    super.initState();
    // Un borrador cuenta como cambios sin guardar: nada se guarda hasta
    // pulsar «Guardar».
    _initial = widget.initialDraft == null
        ? _signature()
        : ['', kPickerNone, '', '', ''].join('\u0001');
  }

  bool get _isNew => widget.wish == null;

  String _signature() => [
    _title.text.trim(),
    _occasionId,
    _size.text.trim(),
    _url.text.trim(),
    _description.text.trim(),
  ].join('\u0001');

  /// El cierre que pide la persona: con cambios sin guardar pregunta antes.
  Future<void> _requestClose() async {
    if (_busy || _closing) return;
    if (_signature() != _initial &&
        !await _confirmDiscard(context, wish: true)) {
      return;
    }
    if (!mounted || _busy || _closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _title.dispose();
    _size.dispose();
    _url.dispose();
    _description.dispose();
    super.dispose();
  }

  String? _text(TextEditingController c) {
    final value = c.text.trim();
    return value.isEmpty ? null : value;
  }

  VisibleWishPatch _patch() {
    final old = widget.wish;
    String? changed(String? now, String? before) => now == before ? null : now;
    final clear = <WishField>{};
    String? field(WishField f, String? now, String? before) {
      if (now == null && before != null) clear.add(f);
      return now == null ? null : changed(now, before);
    }

    final occasion = _occasionId == kPickerNone ? null : _occasionId;
    return VisibleWishPatch(
      title: changed(_title.text.trim(), old?.title),
      year: old == null ? clock.now().year : null,
      occasionId: field(WishField.occasionId, occasion, old?.occasionId),
      size: field(WishField.size, _text(_size), old?.size),
      url: field(WishField.url, _text(_url), old?.url),
      description: field(
        WishField.description,
        _text(_description),
        old?.description,
      ),
      clear: clear,
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _tried = true);
    if (_title.text.trim().isEmpty) {
      ref.read(hapticsProvider).medium();
      return;
    }
    setState(() => _busy = true);
    final service = ref.read(wishServiceProvider);
    final old = widget.wish;
    final result = old == null
        ? await service.createOwn(_patch())
        : await service.edit(old.id, _patch());
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _busy = false);
      showWishProblem(context, ref, result);
      return;
    }
    ref.read(hapticsProvider).light();
    Navigator.of(context).pop(result.wishId ?? old?.id);
  }

  Future<void> _delete() async {
    final wish = widget.wish;
    if (wish == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showRegalosConfirm(
      context,
      title: l10n.wishDeleteTitle(quotedTitle(wish.title)),
      body: l10n.wishDeleteBody,
      confirmLabel: l10n.wishDeleteConfirm,
      cancelLabel: l10n.actionCancel,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final result = await ref.read(wishServiceProvider).remove(wish.id);
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _busy = false);
      showWishProblem(context, ref, result);
      return;
    }
    ref.read(hapticsProvider).medium();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final view = ref.watch(familyFullViewProvider);
    final occasions = [
      for (final o in view.occasions)
        if (!o.archived || o.id == widget.wish?.occasionId) o,
    ];
    final labels = OccasionLabels(l10n, view.recipientsById);
    final linkHost = _url.text.trim().isEmpty ? null : userLinkHost(_url.text);
    return _EditorFrame(
      title: _isNew ? l10n.wishEditorNewTitle : l10n.wishEditorEditTitle,
      asDialog: widget.asDialog,
      guarded: true,
      autofocusFrame: !_isNew,
      onClose: _requestClose,
      primary: FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(l10n.actionSave),
      ),
      children: [
        TextField(
          controller: _title,
          autofocus: _isNew,
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
            if (_tried) setState(() {});
          },
        ),
        _gap,
        PickerField<String>(
          label: l10n.fieldOccasion,
          value: occasions.any((o) => o.id == _occasionId)
              ? _occasionId
              : kPickerNone,
          options: occasionPickerOptions(l10n, labels, occasions, t),
          onChanged: (v) => setState(() => _occasionId = v),
        ),
        _gap,
        TextField(
          controller: _size,
          decoration: InputDecoration(labelText: l10n.giftFieldSize),
        ),
        _gap,
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.giftFieldUrl,
            helperText: linkHost,
          ),
        ),
        _gap,
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: l10n.wishFieldDescription),
        ),
        if (!_isNew) ...[
          const SizedBox(height: 24),
          DangerButton(
            label: l10n.wishDelete,
            onPressed: _busy ? null : _delete,
          ),
        ],
      ],
    );
  }
}

/// Lo que dice el estado de un deseo de otra persona en su detalle, o `null`
/// si no hay nada que decir: en el móvil de la propia persona (que nunca sabe
/// quién ha cogido qué ni si alguien lo ha hecho) y en un móvil que no abre
/// el bloque de la persona, el estado no existe.
String? wishDetailStateText(
  AppLocalizations l10n,
  WishActions actions, {
  required Map<String, Recipient> people,
  required String? reader,
  required String personName,
}) {
  if (actions.isOwner) return null;
  switch (actions.state) {
    case null:
      return null;
    case WishPlanState.available:
      return l10n.wishAvailableNote;
    case WishPlanState.conflictingClaims:
      return l10n.wishConflict;
    case WishPlanState.removedFromList:
      return l10n.wishRemovedFromList(personName);
    case WishPlanState.claimed:
      final plan = actions.plans.firstOrNull;
      if (plan == null) return null;
      return plan.claimantPersonId == reader
          ? l10n.wishClaimedByYou
          : l10n.wishClaimedBy(people[plan.claimantPersonId]?.name ?? '');
  }
}

/// El deseo de otra persona, para leerlo y cogerlo («Lo regalo yo»).
///
/// En el móvil es una hoja que mide lo que contiene (con el asa de siempre) y
/// «Lo regalo yo» a lo ancho como acción principal; en el diálogo de la web
/// de escritorio, el marco de los editores. Dice la ocasión, la talla, la
/// descripción, el enlace y el estado («Nadie lo ha cogido», «Lo ha cogido
/// Aritz»): el estado solo en los móviles que abren el bloque de la persona,
/// nunca en el suyo.
class WishDetail extends ConsumerWidget {
  /// Crea la hoja.
  const WishDetail({
    super.key,
    required this.person,
    required this.wishId,
    this.asDialog = false,
  });

  /// La persona del deseo.
  final String person;

  /// El deseo.
  final String wishId;

  /// Si es el diálogo de la web de escritorio.
  final bool asDialog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final entry = ref
        .watch(wishEntriesProvider(person))
        .where((e) => e.wish.id == wishId)
        .firstOrNull;
    final wish = entry?.wish;
    final view = ref.watch(familyFullViewProvider);
    final name = view.allRecipientsById[person]?.name;
    void close() => Navigator.of(context).maybePop();
    if (wish == null) {
      final gone = Text(l10n.wishProblemGone, style: t.styles.body);
      return asDialog
          ? _EditorFrame(
              title: l10n.wishTag,
              asDialog: true,
              onClose: close,
              children: [gone],
            )
          : _DetailSheet(
              close: close,
              closeLabel: l10n.actionClose,
              children: [gone],
            );
    }
    final actions = entry!.actions;
    final host = wish.url == null ? null : userLinkHost(wish.url!);
    final state = wishDetailStateText(
      l10n,
      actions,
      people: view.allRecipientsById,
      reader: ref.watch(wishReaderProvider),
      personName: name ?? '',
    );
    final occasion = wish.occasionId == null
        ? null
        : view.occasionsById[wish.occasionId];
    final occasionText = occasion == null
        ? null
        : OccasionLabels(l10n, view.recipientsById).of(occasion);
    final primary = actions.canClaim
        ? FilledButton(
            onPressed: () async {
              final ok = await claimWishFlow(context, ref, wish);
              if (ok && context.mounted) Navigator.of(context).pop();
            },
            child: Text(l10n.wishClaim),
          )
        : null;
    final facts = <Widget>[
      if (state != null)
        _DetailFact(
          label: l10n.fieldStatus,
          child: ValueSwitcher(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              state,
              key: ValueKey(state),
              style: actions.state == WishPlanState.conflictingClaims
                  ? t.styles.body.copyWith(color: t.danger)
                  : t.styles.body,
            ),
          ),
        ),
      if (occasionText != null)
        _DetailFact(
          label: l10n.fieldOccasion,
          child: Text(occasionText, style: t.styles.body),
        ),
      if (wish.size != null)
        _DetailFact(
          label: l10n.giftFieldSize,
          child: Text(wish.size!, style: t.styles.body),
        ),
      if (wish.description != null)
        _DetailFact(
          label: l10n.wishFieldDescription,
          child: Text(wish.description!, style: t.styles.body),
        ),
    ];
    // Sin hueco extra encima: la zona táctil de 48 ya lo deja.
    final link = host == null
        ? null
        : Align(
            alignment: AlignmentDirectional.centerStart,
            // Pegado al margen como el resto de datos, con zona táctil de 48.
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size(0, 48),
                alignment: AlignmentDirectional.centerStart,
              ),
              onPressed: () => openGiftLink(context, ref, wish.url!),
              child: Text('${l10n.giftLinkOpen}: $host'),
            ),
          );
    if (asDialog) {
      return _EditorFrame(
        title: name ?? l10n.wishTag,
        asDialog: true,
        onClose: close,
        primary: primary,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(wish.title, style: t.styles.screenTitleSmall),
              TagLabel(l10n.wishTag),
            ],
          ),
          for (final fact in facts) ...[const SizedBox(height: 12), fact],
          ?link,
        ],
      );
    }
    return _DetailSheet(
      close: close,
      closeLabel: l10n.actionClose,
      primary: primary,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            TagLabel(l10n.wishTag),
            if (name != null) Text(name, style: t.styles.meta),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          header: true,
          child: Text(wish.title, style: t.styles.screenTitleSmall),
        ),
        for (final fact in facts) ...[const SizedBox(height: 12), fact],
        ?link,
      ],
    );
  }
}

/// Un dato del detalle de un deseo: su nombre pequeño y el valor debajo.
class _DetailFact extends StatelessWidget {
  const _DetailFact({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.styles.meta),
        const SizedBox(height: 2),
        child,
      ],
    );
  }
}

/// La hoja del detalle de un deseo en el móvil: mide lo que contiene (y se
/// desplaza si no cabe, con letra grande o el teclado), con la acción
/// principal a lo ancho debajo, o «Cerrar» si no hay ninguna.
class _DetailSheet extends StatelessWidget {
  const _DetailSheet({
    required this.children,
    required this.close,
    required this.closeLabel,
    this.primary,
  });

  final List<Widget> children;
  final VoidCallback close;
  final String closeLabel;
  final Widget? primary;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...children,
          const SizedBox(height: 16),
          primary ?? TextButton(onPressed: close, child: Text(closeLabel)),
        ],
      ),
    ),
  );
}

/// El plan de un deseo que alguien ha cogido: lo privado de quien regala
/// (quién, estado, precios, tienda, enlace de compra y notas) y las acciones
/// de soltarlo, borrarlo o convertirlo en una sorpresa.
class WishPlanEditor extends ConsumerStatefulWidget {
  /// Crea el editor.
  const WishPlanEditor({
    super.key,
    required this.person,
    required this.plan,
    this.asDialog = false,
  });

  /// La persona del deseo.
  final String person;

  /// El plan al abrir.
  final WishPlan plan;

  /// Si es el diálogo de la web de escritorio.
  final bool asDialog;

  @override
  ConsumerState<WishPlanEditor> createState() => _WishPlanEditorState();
}

class _WishPlanEditorState extends ConsumerState<WishPlanEditor> {
  late final TextEditingController _planned;
  late final TextEditingController _actual;
  late final TextEditingController _store = TextEditingController(
    text: widget.plan.store,
  );
  late final TextEditingController _purchaseUrl = TextEditingController(
    text: widget.plan.purchaseUrl,
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.plan.giverNote,
  );
  late String _giverId = widget.plan.giverId ?? kPickerNone;
  late GiftStatus _status = widget.plan.status;
  bool _tried = false;
  bool _busy = false;
  bool _closing = false;
  String? _initial;

  /// Si el plan dejó de estar autorizado en este dispositivo: el formulario se
  /// retira y el editor se cierra solo (como el de regalos).
  bool _revoked = false;

  /// Los diálogos con contenido del plan abiertos encima del editor (soltar,
  /// borrar, convertir, descartar cambios): se cierran con el editor si el
  /// plan deja de verse.
  final Set<Object> _dialogs = <Object>{};

  Future<T> _trackedDialog<T>(Future<T> Function() open) async {
    final token = Object();
    _dialogs.add(token);
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

  /// El plan de [WishPlanEditor.plan] tal como lo ve ahora este dispositivo,
  /// o `null` si ya no lo ve (la fila no está o ya no lo trae).
  WishPlan? _livePlan() => ref
      .read(wishPlanStateRowsProvider(widget.person))
      .where((r) => r.sourceWishId == widget.plan.sourceWishId)
      .expand((r) => r.plans)
      .where((p) => p.planId == widget.plan.planId)
      .firstOrNull;

  void _scheduleAuthorizationCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuthorization());
  }

  /// Si el plan ya no está en lo que este dispositivo está autorizado a ver
  /// (le quitaron el derecho al bloque, o el plan se soltó en otro móvil), el
  /// editor se cierra solo, sin guardar y retirando el formulario. Mientras la
  /// proyección carga o falla, o se está guardando, no se decide nada.
  void _checkAuthorization() {
    if (!mounted || _revoked || _closing) return;
    final projection = ref.read(authorizedProjectionProvider);
    final uncertain = projection.isLoading || projection.hasError;
    final live = _livePlan();
    if (_dialogs.isNotEmpty && (uncertain || live == null)) _closeDialogs();
    if (_busy || uncertain || live != null) return;
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
    );
    for (final c in [_planned, _actual, _store, _purchaseUrl, _note]) {
      c.clear();
    }
    ref.read(hapticsProvider).warning();
    setState(() => _revoked = true);
    _closing = true;
    _closeDialogs();
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      Navigator.of(context).pop();
    } else if (route != null && route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(notice, snackBarAnimationStyle: style);
  }

  String _signature() => [
    _giverId,
    _status.name,
    _planned.text.trim(),
    _actual.text.trim(),
    _store.text.trim(),
    _purchaseUrl.text.trim(),
    _note.text.trim(),
  ].join('\u0001');

  /// El cierre que pide la persona: con cambios sin guardar pregunta antes.
  Future<void> _requestClose() async {
    if (_busy || _closing) return;
    if (_signature() != _initial &&
        !await _trackedDialog(() => _confirmDiscard(context))) {
      return;
    }
    if (!mounted || _busy || _closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    _planned = TextEditingController();
    _actual = TextEditingController();
  }

  String _lang(BuildContext context) =>
      Localizations.localeOf(context).languageCode;

  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final lang = _lang(context);
    final plan = widget.plan;
    _planned.text = plan.plannedCents == null
        ? ''
        : centsInputText(plan.plannedCents!, lang);
    _actual.text = plan.actualCents == null
        ? ''
        : centsInputText(plan.actualCents!, lang);
    _initial = _signature();
  }

  @override
  void dispose() {
    _planned.dispose();
    _actual.dispose();
    _store.dispose();
    _purchaseUrl.dispose();
    _note.dispose();
    super.dispose();
  }

  bool _bad(TextEditingController c) =>
      !readMoneyField(c.text, _lang(context)).valid;

  /// El enlace de compra está escrito y no vale (QA 1.0.7, m5).
  bool get _badUrl {
    final text = _purchaseUrl.text.trim();
    return text.isNotEmpty && !isPlanPurchaseUrl(text);
  }

  /// Hay algo mal escrito: se marca el campo y se avisa con la vibración.
  bool _invalidForm() {
    setState(() => _tried = true);
    if (_bad(_planned) || _bad(_actual) || _badUrl) {
      ref.read(hapticsProvider).medium();
      return true;
    }
    return false;
  }

  int? _cents(TextEditingController c) =>
      readMoneyField(c.text, _lang(context)).cents;

  String? _text(TextEditingController c) {
    final value = c.text.trim();
    return value.isEmpty ? null : value;
  }

  PrivatePlanPatch _patch() {
    final plan = widget.plan;
    final clear = <WishPlanField>{};
    T? field<T>(WishPlanField f, T? now, T? before) {
      if (now == null && before != null) clear.add(f);
      return now == null || now == before ? null : now;
    }

    final giver = _giverId == kPickerNone ? null : _giverId;
    return PrivatePlanPatch(
      giverId: field(WishPlanField.giverId, giver, plan.giverId),
      status: _status == plan.status ? null : _status,
      plannedCents: field(
        WishPlanField.plannedCents,
        _cents(_planned),
        plan.plannedCents,
      ),
      actualCents: field(
        WishPlanField.actualCents,
        _cents(_actual),
        plan.actualCents,
      ),
      store: field(WishPlanField.store, _text(_store), plan.store),
      purchaseUrl: field(
        WishPlanField.purchaseUrl,
        _text(_purchaseUrl),
        plan.purchaseUrl,
      ),
      giverNote: field(WishPlanField.giverNote, _text(_note), plan.giverNote),
      clear: clear,
    );
  }

  String get _personName =>
      ref.read(familyFullViewProvider).allRecipientsById[widget.person]?.name ??
      '';

  Future<void> _save() async {
    if (_busy) return;
    if (_invalidForm()) return;
    setState(() => _busy = true);
    final result = await ref
        .read(wishServiceProvider)
        .editPlan(widget.person, widget.plan.planId, _patch());
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _busy = false);
      showWishProblem(context, ref, result, name: _personName);
      return;
    }
    ref.read(hapticsProvider).light();
    _closeWithNotice(
      context,
      result.pending ? AppLocalizations.of(context).wishSavedPending : null,
    );
  }

  /// Suelta, borra o convierte el plan, tras confirmarlo.
  Future<void> _act({
    required String title,
    required String body,
    required String confirmLabel,
    required Future<WishResult> Function(WishService) run,
    required String notice,
    bool carryEdits = false,
  }) async {
    if (_busy) return;
    // Convertir lleva lo escrito y sin guardar a la sorpresa nueva: se
    // comprueba antes de preguntar (QA 1.0.7, m3).
    if (carryEdits && _signature() != _initial && _invalidForm()) return;
    final l10n = AppLocalizations.of(context);
    final ok = await _trackedDialog(
      () => showRegalosConfirm(
        context,
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: l10n.actionCancel,
      ),
    );
    if (!ok || !mounted || _revoked) return;
    setState(() => _busy = true);
    final service = ref.read(wishServiceProvider);
    var result = const WishResult.ok();
    // Lo escrito y sin guardar pasa al plan antes de convertirlo, y de él a la
    // sorpresa (que copia el plan): no se pierde.
    if (carryEdits && _signature() != _initial) {
      result = await service.editPlan(
        widget.person,
        widget.plan.planId,
        _patch(),
      );
      if (!mounted) return;
    }
    if (result.ok) result = await run(service);
    if (!mounted) return;
    if (!result.ok) {
      setState(() => _busy = false);
      showWishProblem(context, ref, result, name: _personName);
      return;
    }
    ref.read(hapticsProvider).medium();
    _closeWithNotice(context, notice);
  }

  /// El plan de otra persona: quién lo ha cogido y su estado, sin campos ni
  /// acciones.
  Widget _readOnly(
    BuildContext context,
    WishPlan live,
    WishPlanState? state,
    String name,
  ) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final claimant =
        ref
            .watch(familyFullViewProvider)
            .allRecipientsById[live.claimantPersonId]
            ?.name ??
        '';
    return _EditorFrame(
      title: l10n.wishPlanTitle,
      asDialog: widget.asDialog,
      onClose: () => Navigator.of(context).maybePop(),
      children: [
        if (state == WishPlanState.conflictingClaims) ...[
          Semantics(liveRegion: true, child: WarningBox(l10n.wishConflict)),
          _gap,
        ],
        if (state == WishPlanState.removedFromList) ...[
          Semantics(
            liveRegion: true,
            child: WarningBox(l10n.wishRemovedFromList(name)),
          ),
          _gap,
        ],
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(live.title, style: t.styles.screenTitleSmall),
            TagLabel(l10n.wishTag),
          ],
        ),
        const SizedBox(height: 8),
        Text(l10n.wishClaimedBy(claimant), style: t.styles.body),
        const SizedBox(height: 8),
        Text(l10n.wishPlanReadOnly(claimant), style: t.styles.meta),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      wishPlanStateRowsProvider(widget.person),
      (_, _) => _scheduleAuthorizationCheck(),
    );
    ref.listen(
      authorizedProjectionProvider,
      (_, _) => _scheduleAuthorizationCheck(),
    );
    if (_revoked) return const SizedBox.expand();
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final view = ref.watch(familyFullViewProvider);
    final plan = widget.plan;
    final service = ref.watch(wishServiceProvider);
    final row = ref
        .watch(wishPlanStateRowsProvider(widget.person))
        .where((r) => r.sourceWishId == plan.sourceWishId)
        .firstOrNull;
    final live = row?.plans.where((p) => p.planId == plan.planId).firstOrNull;
    if (live == null) {
      // Este dispositivo ya no ve el plan (o aún no sabe si lo ve): no se
      // pinta nada suyo; si es seguro que no lo ve, el editor se cierra.
      _scheduleAuthorizationCheck();
      return const SizedBox.expand();
    }
    final state = row?.state;
    final name = view.allRecipientsById[widget.person]?.name ?? '';
    // Solo quien lo ha cogido cambia, suelta, borra o convierte su plan: los
    // demás lo ven y nada más (ADR 0010).
    final reader = ref.watch(wishReaderProvider);
    if (reader == null || reader != live.claimantPersonId) {
      return _readOnly(context, live, state, name);
    }
    final givers = view.selectableGiversFor(widget.person);
    final selected = view.resolveGiver(_giverId);
    final host = plan.url == null ? null : userLinkHost(plan.url!);
    final removed = state == WishPlanState.removedFromList;
    final year = row?.wish?.year ?? clock.now().year;
    // Mientras se recalcula la proyección (o falla) las filas son las de la
    // última vez, no una confirmación: no se enseña lo privado. La web no
    // depende de la proyección del móvil.
    final projection = ref.watch(authorizedProjectionProvider);
    final uncertain =
        !ref.watch(webAppProvider) &&
        (projection.isLoading || projection.hasError);
    return _EditorFrame(
      title: l10n.wishPlanTitle,
      asDialog: widget.asDialog,
      guarded: true,
      onClose: _requestClose,
      primary: FilledButton(
        onPressed: _busy || uncertain ? null : _save,
        child: Text(l10n.actionSave),
      ),
      children: [
        if (state == WishPlanState.conflictingClaims) ...[
          Semantics(liveRegion: true, child: WarningBox(l10n.wishConflict)),
          _gap,
        ],
        if (removed) ...[
          Semantics(
            liveRegion: true,
            child: WarningBox(l10n.wishRemovedFromList(name)),
          ),
          _gap,
        ],
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(plan.title, style: t.styles.screenTitleSmall),
            TagLabel(l10n.wishTag),
          ],
        ),
        if (plan.size != null) ...[
          const SizedBox(height: 4),
          Text(l10n.giftSizeLine(plan.size!), style: t.styles.meta),
        ],
        if (host != null) ...[
          const SizedBox(height: 4),
          Text(host, style: t.styles.meta),
        ],
        const SizedBox(height: 8),
        Text(l10n.wishPlanNote(name), style: t.styles.meta),
        _gap,
        // Lo privado del plan (quién regala, estado, precios, tienda, enlace
        // y nota) no se enseña mientras se recalcula qué puede ver este
        // dispositivo: el formulario sigue montado (lo escrito se conserva y
        // el teclado no se pierde) pero fuera de pantalla, hasta que las
        // filas vigentes confirmen el acceso.
        Visibility(
          visible: !uncertain,
          maintainState: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PickerField<String>(
                // Si el plan deja de verse (o se duda) con la hoja abierta, se
                // cierra con el editor: no se queda la asignación a la vista.
                track: (open) => _trackedDialog(open),
                label: l10n.fieldGiver,
                value: selected == null ? kPickerNone : selected.id,
                options: [
                  PickerOption(
                    value: kPickerNone,
                    label: l10n.giverUnassigned,
                    leading: const GiverDot(size: 12),
                  ),
                  for (final g in givers)
                    PickerOption(
                      value: g.id,
                      label: giverNameFor(l10n, g),
                      leading: GiverDot(colorIndex: g.colorIndex, size: 12),
                    ),
                ],
                onChanged: (v) => setState(() => _giverId = v),
              ),
              _gap,
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
              _gap,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _planned,
                      keyboardType: moneyKeyboard,
                      inputFormatters: moneyInputFormatters,
                      decoration: InputDecoration(
                        labelText: l10n.giftFieldPlanned,
                        suffixText: '€',
                        errorText: _tried && _bad(_planned)
                            ? l10n.giftPriceInvalid
                            : null,
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _actual,
                      keyboardType: moneyKeyboard,
                      inputFormatters: moneyInputFormatters,
                      decoration: InputDecoration(
                        labelText: l10n.giftFieldActualPrice,
                        suffixText: '€',
                        errorText: _tried && _bad(_actual)
                            ? l10n.giftPriceInvalid
                            : null,
                        errorMaxLines: 3,
                      ),
                    ),
                  ),
                ],
              ),
              _gap,
              TextField(
                controller: _store,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.giftFieldStore),
              ),
              _gap,
              TextField(
                controller: _purchaseUrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.wishFieldPurchaseUrl,
                  // El sitio del enlace, como en el campo de enlace del editor de
                  // regalos.
                  helperText: _purchaseUrl.text.trim().isEmpty
                      ? null
                      : userLinkHost(_purchaseUrl.text),
                  errorText: _tried && _badUrl
                      ? l10n.wishPurchaseUrlInvalid
                      : null,
                ),
              ),
              _gap,
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.giftFieldNote),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (service.canConvertPlan) ...[
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _act(
                    title: l10n.wishConvertTitle(quotedTitle(plan.title)),
                    body: l10n.wishConvertBody,
                    confirmLabel: l10n.wishConvertConfirm,
                    notice: l10n.wishConvertedNotice,
                    carryEdits: true,
                    run: (s) => s.convertPlan(
                      widget.person,
                      plan.planId,
                      year: year,
                      occasionId: row?.wish?.occasionId,
                    ),
                  ),
            child: Text(l10n.wishPlanConvert),
          ),
          const SizedBox(height: 4),
          Text(l10n.wishPlanConvertHint, style: t.styles.meta),
          const SizedBox(height: 24),
        ],
        if (removed)
          DangerButton(
            label: l10n.wishPlanDelete,
            onPressed: _busy
                ? null
                : () => _act(
                    title: l10n.wishPlanDeleteTitle(quotedTitle(plan.title)),
                    body: l10n.wishPlanDeleteBody,
                    confirmLabel: l10n.actionEliminate,
                    notice: l10n.wishPlanDeletedNotice,
                    // La web no borra planes: suelta, que es lo mismo.
                    run: (s) => service.canConvertPlan
                        ? s.deletePlan(widget.person, plan.planId)
                        : s.releasePlan(widget.person, plan.planId),
                  ),
          )
        else
          DangerButton(
            label: l10n.wishPlanRelease,
            onPressed: _busy
                ? null
                : () => _act(
                    title: l10n.wishReleaseTitle(quotedTitle(plan.title)),
                    body: l10n.wishReleaseBody,
                    confirmLabel: l10n.wishPlanRelease,
                    notice: l10n.wishReleasedNotice,
                    run: (s) => s.releasePlan(widget.person, plan.planId),
                  ),
          ),
      ],
    );
  }
}
