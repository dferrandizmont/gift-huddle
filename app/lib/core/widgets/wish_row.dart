import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../motion/value_switcher.dart';
import '../theme/accent_palette.dart';
import '../theme/regalos_motion.dart';
import '../theme/regalos_tokens.dart';
import 'gift_row.dart';
import 'pointer_surface.dart';
import 'stroke_icon.dart';
import 'tabler_icons.dart';
import 'tag_label.dart';

/// El lado de la estrella de un deseo: el del dibujo de estado de una fila de
/// regalo (22) y su trazo (1,6).
const double kWishStarSize = 22;

/// El trazo de la estrella de un deseo.
const double kWishStarStroke = 1.6;

/// El alto visual de «Lo regalo yo» (la zona táctil es de 48).
const double kWishActionHeight = 36;

/// El relleno horizontal del botón «Lo regalo yo».
const double _kActionPad = 12;

/// El hueco entre el texto de la fila y el botón.
const double _kActionGap = 8;

/// Lo mínimo que debe quedarle al texto junto al botón; con menos, el botón
/// cae debajo.
const double _kMinTextWidth = 132;

/// Desde este factor de letra el botón cae siempre debajo del texto.
const double _kStackedTextScale = 1.3;

/// Fila de un deseo (ADR 0010, opción A de la revisión del 26-11): como una
/// fila de regalo. A la izquierda el título y, debajo, la etiqueta «Deseo» con
/// el detalle (talla o descripción); a la derecha «Lo regalo yo», un botón
/// tonal compacto, donde un regalo tiene su precio y su estado (en la
/// tablet, en la columna del estado).
///
/// Con el botón no hay «Nadie lo ha cogido»: ya lo dice el botón. Sin botón,
/// el estado («Nadie lo ha cogido», un aviso) va debajo. Con letra grande o
/// sin ancho el botón cae debajo del texto, nunca recortado.
///
/// En el dispositivo de la propia persona no hay estado ni acción: solo el
/// deseo. Sustituye a la casilla de estado por una estrella discreta, para
/// que los títulos queden a la altura de los de los regalos.
class WishRow extends StatefulWidget {
  /// Crea la fila.
  const WishRow({
    super.key,
    required this.title,
    this.detail,
    this.stateText,
    this.warning = false,
    this.actionLabel,
    this.onAction,
    this.onTap,
    this.table = false,
    this.bordered = true,
    this.accent,
    this.columnsFrom,
  });

  /// Qué se desea.
  final String title;

  /// La talla, la descripción o el enlace, en una línea.
  final String? detail;

  /// El estado del deseo para quien abre el bloque, o `null`. Se ve si no hay
  /// botón o si es un aviso; el lector de pantalla siempre lo lee.
  final String? stateText;

  /// Si [stateText] es un aviso (dos personas lo han cogido).
  final bool warning;

  /// El texto de la acción («Lo regalo yo»), o `null` si no hay.
  final String? actionLabel;

  /// Lo que hace la acción; devuelve si salió bien. Con `false` el botón
  /// vuelve; con `true` deja paso al estado hasta que la fila se va.
  final Future<bool> Function()? onAction;

  /// Abre el deseo.
  final VoidCallback? onTap;

  /// Si es una fila de la tabla del tablero de la web.
  final bool table;

  /// Si lleva el filete de abajo.
  final bool bordered;

  /// El color de la persona del deseo para el botón; `null`, el del tema.
  final AccentPalette? accent;

  /// El ancho de fila desde el que va en columnas como [GiftRow]; `null`,
  /// nunca.
  final double? columnsFrom;

  @override
  State<WishRow> createState() => _WishRowState();
}

class _WishRowState extends State<WishRow> {
  /// Si se ha tocado el botón y la acción sigue en marcha o salió bien.
  bool _claiming = false;

  /// Si el botón está pulsado (se encoge un poco, 80 ms).
  bool _pressed = false;

  bool get _hasAction => widget.actionLabel != null && widget.onAction != null;

  /// Cuánto se ve el estado en el sitio del botón tras coger. Si pasado ese
  /// tiempo la lista aún tiene esta fila (misma clave, el deseo sigue libre),
  /// vuelve el botón: el estado es un instante, no una cerradura.
  static const Duration _claimedFor = Duration(milliseconds: 1500);

  Timer? _revert;

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  Future<void> _act() async {
    final run = widget.onAction;
    if (run == null || _claiming) {
      return;
    }
    setState(() => _claiming = true);
    var ok = false;
    try {
      ok = await run();
    } catch (_) {
      ok = false;
    }
    if (!mounted) {
      return;
    }
    if (ok) {
      _revert?.cancel();
      _revert = Timer(_claimedFor, () {
        if (mounted) {
          setState(() => _claiming = false);
        }
      });
    } else {
      setState(() => _claiming = false);
    }
  }

  /// El ancho del botón con el texto y la letra de ahora.
  double _buttonWidth(BuildContext context, RegalosTokens t) {
    final painter = TextPainter(
      text: TextSpan(text: widget.actionLabel, style: t.styles.label),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    // Más el relleno y el borde de 1.
    return (width + 2 * _kActionPad + 2).ceilToDouble().clamp(48, 1000);
  }

  /// El texto de la fila: título, «Deseo» con el detalle y, si toca, el
  /// estado. Es un solo botón que se lee entero; el de la acción viene
  /// después, aparte.
  Widget _text(BuildContext context, RegalosTokens t, {bool oneLine = false}) {
    final l10n = AppLocalizations.of(context);
    final showState =
        widget.stateText != null && (!_hasAction || widget.warning);
    final detail = widget.detail;
    return Semantics(
      container: true,
      button: widget.onTap != null,
      label: [
        widget.title,
        l10n.wishTag,
        ?detail,
        ?widget.stateText,
      ].join('. '),
      excludeSemantics: true,
      onTap: widget.onTap,
      child: PointerSurface(
        radius: BorderRadius.zero,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueSwitcher(
                  child: Text(
                    widget.title,
                    key: ValueKey(widget.title),
                    style: widget.table
                        ? t.styles.tableTitle
                        : t.styles.rowTitle,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: [
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: TagLabel(l10n.wishTag),
                      ),
                      if (detail != null) ...[
                        const WidgetSpan(child: SizedBox(width: 8)),
                        TextSpan(text: detail),
                      ],
                    ],
                  ),
                  maxLines: oneLine ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.styles.meta,
                ),
                if (showState)
                  ValueSwitcher(
                    child: Text(
                      widget.stateText!,
                      key: ValueKey(widget.stateText),
                      style: widget.warning
                          ? t.styles.metaWarning
                          : t.styles.meta,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// El botón tonal: relleno pastel de la persona, tinta, borde, radio 8,
  /// 36 de alto y 48 de zona táctil.
  Widget _button(BuildContext context, RegalosTokens t) {
    final accent = widget.accent;
    final dark = t.isDark;
    final fill = accent?.fillOf(dark) ?? t.fill;
    final ink = accent?.inkOf(dark) ?? t.ink;
    final border = accent?.borderOf(dark) ?? t.selectionBorder;
    final l10n = AppLocalizations.of(context);
    final reduce = RegalosMotion.of(context).reduce;
    return Semantics(
      container: true,
      button: true,
      label: l10n.wishClaimFor(widget.title),
      excludeSemantics: true,
      onTap: _act,
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed && !reduce ? 0.96 : 1,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          child: FilledButton(
            onPressed: _act,
            style: FilledButton.styleFrom(
              backgroundColor: fill,
              foregroundColor: ink,
              elevation: 0,
              side: BorderSide(color: border),
              minimumSize: const Size(48, kWishActionHeight),
              padding: const EdgeInsets.symmetric(horizontal: _kActionPad),
              tapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              textStyle: t.styles.label,
            ),
            child: Text(widget.actionLabel!),
          ),
        ),
      ),
    );
  }

  /// El sitio del botón: al cogerlo se funde y entra el estado, en el mismo
  /// sitio y sin cambiar el alto de la fila.
  Widget _actionCell(BuildContext context, RegalosTokens t, double width) {
    final l10n = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: SizedBox(
        width: width,
        child: ValueSwitcher(
          alignment: Alignment.centerRight,
          child: _claiming
              ? Align(
                  key: const ValueKey<String>('claimed'),
                  alignment: Alignment.centerRight,
                  heightFactor: 1,
                  // Sin encoger la letra: a ×2 el texto sigue en otra línea.
                  child: Text(
                    l10n.wishClaimedByYou,
                    textAlign: TextAlign.end,
                    style: t.styles.meta,
                  ),
                )
              : KeyedSubtree(
                  key: const ValueKey<String>('claim'),
                  child: _button(context, t),
                ),
        ),
      ),
    );
  }

  /// La fila de móvil: el texto y el botón en la misma línea; si no cabe, el
  /// botón debajo.
  Widget _compact(BuildContext context, RegalosTokens t, double available) {
    if (!_hasAction) {
      return _text(context, t);
    }
    final buttonWidth = _buttonWidth(context, t);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final inline =
        scale < _kStackedTextScale &&
        available - buttonWidth - _kActionGap >= _kMinTextWidth;
    // Junto al botón la fila mide como una de regalo: el detalle, en una
    // línea (entero en la ficha del deseo y para el lector de pantalla).
    final text = _text(context, t, oneLine: inline);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: inline ? available - buttonWidth - _kActionGap : available,
          child: text,
        ),
        _actionCell(context, t, buttonWidth),
      ],
    );
  }

  /// La fila de tablet: el texto, las columnas de quién regala y el precio en
  /// blanco y el botón en la columna del estado.
  Widget _columns(BuildContext context, RegalosTokens t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        Expanded(child: _text(context, t)),
        const SizedBox(width: GiftRow.giverColumn + GiftRow.priceColumn),
        if (_hasAction)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: GiftRow.statusColumn),
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                heightFactor: 1,
                child: _actionCell(context, t, _buttonWidth(context, t)),
              ),
            ),
          )
        else
          const SizedBox(width: GiftRow.statusColumn + 16),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final table = widget.table;
    return Container(
      constraints: BoxConstraints(minHeight: table ? 48 : 60),
      padding: table
          ? const EdgeInsets.symmetric(horizontal: 16)
          : const EdgeInsets.only(left: 4, right: 16),
      decoration: widget.bordered
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: t.separator)),
            )
          : null,
      child: LayoutBuilder(
        builder: (context, box) {
          final from = widget.columnsFrom;
          final columns = from != null && box.maxWidth >= from;
          return Row(
            children: [
              // El hueco de la casilla de estado: aquí solo una marca
              // discreta, con el tamaño y el trazo de los iconos de la fila de
              // regalo.
              ExcludeSemantics(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: StrokeIcon(
                      tablerStar,
                      size: kWishStarSize,
                      color: t.textSecondary,
                      strokeWidth: kWishStarStroke,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: columns
                    ? _columns(context, t)
                    : LayoutBuilder(
                        builder: (context, inner) =>
                            _compact(context, t, inner.maxWidth),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
