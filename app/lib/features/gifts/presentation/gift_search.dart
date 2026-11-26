import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/gifts_secure_scope.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/pointer_surface.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tag_label.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_providers.dart';
import '../../family/application/gift_search.dart';
import '../../../core/sync/wish_plan.dart';
import 'wish_plan_note.dart';
import 'wish_editor.dart';

/// El campo del buscador de regalos del móvil, la tableta y la web estrecha:
/// una lupa delante y, con algo escrito, una cruz que lo borra. Busca por el
/// nombre del regalo, su nota, la tienda y la persona ([giftMatchesQuery]).
class GiftSearchField extends StatelessWidget {
  /// Crea el campo.
  const GiftSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.focusNode,
    this.dense = false,
  });

  /// Si es la variante compacta de la barra lateral de la web: 36 de alto, con
  /// relleno y borde fino. La normal es la del resto de campos (52).
  final bool dense;

  /// Lo escrito.
  final TextEditingController controller;

  /// Se llama con cada cambio (también al borrar con la cruz).
  final ValueChanged<String> onChanged;

  /// El foco del campo, si quien lo usa quiere llevarlo.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    // La ficha: 40 de alto en la barra lateral de la web (lupa de 16) y 48 en
    // el móvil (lupa de 18), con la lupa centrada en el eje del texto.
    final icon = dense ? 16.0 : 18.0;
    final side = dense ? 40.0 : 48.0;
    final start = dense ? 12.0 : 14.0;
    const gap = 10.0;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: RegalosShape.field,
      borderSide: BorderSide(color: color, width: width),
    );
    final textStyle = dense
        ? t.styles.label.copyWith(fontWeight: FontWeight.w400)
        : t.styles.fieldText;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: textStyle,
      cursorColor: t.ink,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: l10n.boardSearchHint,
        hintStyle: textStyle.copyWith(color: t.textSecondary),
        // Con la letra al doble el aviso baja de línea en vez de cortarse.
        hintMaxLines: dense ? 1 : 2,
        isDense: true,
        filled: true,
        fillColor: t.field,
        constraints: BoxConstraints(minHeight: side),
        contentPadding: EdgeInsets.symmetric(
          vertical: (side - (dense ? 20 : 22)) / 2,
        ),
        border: border(t.controlBorder, 1),
        enabledBorder: border(t.controlBorder, 1),
        focusedBorder: border(t.ink, 1.5),
        // La lupa, centrada en vertical: un `Padding` solo la dejaba arriba
        // del alto mínimo del hueco.
        prefixIcon: SizedBox(
          width: start + icon + gap,
          height: side,
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: start),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: StrokeIcon(
                AppIcons.search,
                size: icon,
                color: t.textSecondary,
              ),
            ),
          ),
        ),
        prefixIconConstraints: BoxConstraints(
          minWidth: start + icon + gap,
          minHeight: side,
        ),
        suffixIcon: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => controller.text.isEmpty
              ? const SizedBox.shrink()
              : Semantics(
                  button: true,
                  label: l10n.searchClear,
                  excludeSemantics: true,
                  onTap: () {
                    controller.clear();
                    onChanged('');
                  },
                  child: IconButton(
                    tooltip: l10n.searchClear,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(
                      minWidth: side,
                      minHeight: side,
                    ),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    icon: StrokeIcon(
                      AppIcons.close,
                      size: icon,
                      color: t.textSecondary,
                    ),
                  ),
                ),
        ),
        suffixIconConstraints: BoxConstraints(minWidth: side, minHeight: side),
      ),
    );
  }
}

/// Los regalos y los deseos que casan con [query], como filas (el regalo o el
/// deseo y su persona), o «Ningún regalo coincide» si no hay ninguno. Con
/// [limit], solo los primeros. Un deseo sale una vez: como su plan si alguien
/// lo ha cogido y este dispositivo puede verlo (ADR 0010).
class GiftSearchResults extends ConsumerWidget {
  /// Crea la lista.
  const GiftSearchResults({
    super.key,
    required this.query,
    required this.onOpen,
    this.limit,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 8),
  });

  /// Lo escrito en el buscador.
  final String query;

  /// Se llama con el regalo elegido.
  final ValueChanged<Gift> onOpen;

  /// Cuántos salen como mucho; sin él, todos.
  final int? limit;

  /// Si es una lista que se desplaza por sí misma. Sin ello son las filas en
  /// una columna, para ponerlas dentro de otra lista (sin listas anidadas).
  final bool scrollable;

  /// El relleno de la lista.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = RegalosTokens.of(context);
    final people = ref.watch(familyFullViewProvider).recipientsById;
    final results = ref.watch(searchResultsProvider(query));
    final reader = ref.watch(wishReaderProvider);
    final planIds = {
      for (final plans in ref.watch(projectedPlansByWishProvider).values)
        for (final plan in plans) plan.planId,
      for (final plans in ref.watch(webWishPlansProvider).values)
        for (final plan in plans) plan.planId,
    };
    final fullPeople = ref.watch(familyFullViewProvider).allRecipientsById;
    final l10n = AppLocalizations.of(context);
    // Un deseo cogido dice quién lo ha cogido, o el aviso de dos reservas,
    // igual que en la lista de la persona.
    String? noteOf(Gift g) => planIds.contains(g.id)
        ? wishPlanNoteText(
            l10n,
            ref.watch(wishPlanRowByPlanProvider(g.recipientId))[g.id],
            g.id,
            fullPeople,
            reader,
          )
        : null;
    final all = <_Hit>[
      for (final g in results.gifts)
        _Hit(
          id: g.id,
          title: g.title,
          personId: g.recipientId,
          isWish: planIds.contains(g.id),
          note: noteOf(g),
          warning:
              planIds.contains(g.id) &&
              ref
                      .watch(wishPlanRowByPlanProvider(g.recipientId))[g.id]
                      ?.state ==
                  WishPlanState.conflictingClaims,
          onOpen: () => onOpen(g),
        ),
      for (final w in results.wishes)
        _Hit(
          id: w.id,
          title: w.title,
          personId: w.recipientId,
          isWish: true,
          onOpen: () => w.recipientId == reader
              ? openWishEditor(context, wish: w, recipientId: w.recipientId)
              : openWishDetail(context, person: w.recipientId, wishId: w.id),
        ),
    ];
    final found = limit == null ? all : all.take(limit!).toList();
    // Los resultados enseñan regalos: sin capturas en la versión de tienda.
    return GiftsSecureScope(child: _results(context, t, l10n, people, found));
  }

  Widget _results(
    BuildContext context,
    RegalosTokens t,
    AppLocalizations l10n,
    Map<String, Recipient> people,
    List<_Hit> found,
  ) {
    if (found.isEmpty) {
      return Padding(
        // El texto de las filas va a 12 del borde de su fondo.
        padding: EdgeInsets.fromLTRB(
          padding.left + 12,
          8,
          padding.right + 12,
          8,
        ),
        child: Text(
          l10n.boardSearchNone,
          key: const ValueKey<String>('gift-search-none'),
          style: t.styles.meta,
        ),
      );
    }
    final rows = [
      for (final g in found)
        Semantics(
          button: true,
          label:
              '${g.title}, ${people[g.personId]?.name ?? ''}'
              '${g.isWish ? ', ${l10n.wishTag}' : ''}'
              '${g.note == null ? '' : ', ${g.note}'}',
          excludeSemantics: true,
          onTap: g.onOpen,
          child: PointerSurface(
            child: Material(
              color: Colors.transparent,
              shape: const RoundedRectangleBorder(
                borderRadius: RegalosShape.card,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: g.onOpen,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                g.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.styles.label,
                              ),
                            ),
                            if (g.isWish) ...[
                              const SizedBox(width: 8),
                              TagLabel(l10n.wishTag),
                            ],
                          ],
                        ),
                        Text(
                          people[g.personId]?.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.styles.caption,
                        ),
                        if (g.note != null)
                          Text(
                            g.note!,
                            key: ValueKey<String>('gift-search-note-${g.id}'),
                            style: g.warning
                                ? t.styles.metaWarning
                                : t.styles.meta,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
    return scrollable
        ? ListView(padding: padding, children: rows)
        : Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          );
  }
}

/// Una fila del buscador: un regalo o un deseo.
class _Hit {
  const _Hit({
    required this.id,
    required this.title,
    required this.personId,
    required this.isWish,
    required this.onOpen,
    this.note,
    this.warning = false,
  });

  final String id;
  final String title;
  final String personId;
  final bool isWish;

  /// Quién lo ha cogido o el aviso de dos reservas (un deseo cogido).
  final String? note;

  /// Si [note] es el aviso de dos reservas.
  final bool warning;
  final VoidCallback onOpen;
}
