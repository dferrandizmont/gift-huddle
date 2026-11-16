import 'package:flutter/material.dart';

import '../../../core/motion/shake.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../l10n/app_localizations.dart';

/// Ancho de la columna de la puerta en escritorio.
const double kWebGateWidth = 480;

/// El hueco de una pantalla de la puerta: fondo, columna centrada de
/// [kWebGateWidth] como mucho, marca arriba y la tarjeta con [children].
///
/// Se desplaza si no cabe (ventana baja o letra grande) y se ve igual a 375 px.
class WebGatePane extends StatelessWidget {
  /// Crea la pantalla.
  const WebGatePane({super.key, required this.children});

  /// El contenido de la tarjeta.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 520;
    return ColoredBox(
      color: t.surface,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 16 : 24,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kWebGateWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          l10n.appTitle,
                          style: t.styles.sectionTitle.copyWith(color: t.ink),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.sheet,
                          borderRadius: RegalosShape.card,
                          border: Border.all(color: t.separator),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(narrow ? 20 : 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: children,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Título de una pantalla de la puerta, con [body] opcional debajo.
class WebGateHeading extends StatelessWidget {
  /// Crea el título.
  const WebGateHeading({super.key, required this.title, this.body});

  /// El título.
  final String title;

  /// La explicación.
  final String? body;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: t.styles.screenTitle),
        ),
        if (body != null) ...[
          const SizedBox(height: 8),
          Text(body!, style: t.styles.body.copyWith(color: t.textSecondary)),
        ],
      ],
    );
  }
}

/// Pasos numerados cortos («1  Abre Gift Huddle en tu móvil.»).
class WebGateSteps extends StatelessWidget {
  /// Crea la lista de [steps].
  const WebGateSteps({super.key, required this.steps});

  /// Los textos, en orden.
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.soft,
                      borderRadius: RegalosShape.chip,
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        '${i + 1}',
                        style: t.styles.metaStrong.copyWith(color: t.ink),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(steps[i], style: t.styles.body),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// «Esperando al móvil…» con un indicador pequeño y quieto en el texto.
class WebGateWaiting extends StatelessWidget {
  /// Crea el indicador.
  const WebGateWaiting({super.key, required this.text});

  /// Lo que se espera.
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.9,
              color: t.ink,
              backgroundColor: t.track,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: t.styles.meta)),
        ],
      ),
    );
  }
}

/// Un hueco de texto que cambia con un fundido y estira o encoge la tarjeta
/// con `fold`. Con [text] `null` no ocupa nada.
class WebGateMessage extends StatelessWidget {
  /// Crea el mensaje.
  const WebGateMessage({
    super.key,
    required this.text,
    this.danger = false,
    this.topGap = 12,
    this.valueKey,
  });

  /// El texto, o `null` para ocultarlo.
  final String? text;

  /// Si va en el rojo de error.
  final bool danger;

  /// Aire por encima cuando hay texto.
  final double topGap;

  /// Clave del cambio, si el texto cambia sin que haya que animarlo (una
  /// cuenta atrás). Por defecto, el propio texto.
  final Object? valueKey;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final motion = RegalosMotion.of(context);
    return AnimatedSize(
      duration: motion.duration(RegalosCurves.foldDuration),
      curve: motion.curve(RegalosCurves.fold),
      alignment: Alignment.topCenter,
      child: ValueSwitcher(
        dy: 4,
        child: text == null
            ? const SizedBox(width: double.infinity, key: ValueKey<Object>(''))
            : Padding(
                key: ValueKey<Object>(valueKey ?? text!),
                padding: EdgeInsets.only(top: topGap),
                child: SizedBox(
                  width: double.infinity,
                  child: Semantics(
                    liveRegion: danger,
                    child: Text(
                      text!,
                      style: t.styles.meta.copyWith(
                        color: danger ? t.danger : t.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Campo de PIN o frase: oculto, con «Mostrar» y «Ocultar». Enter llama a
/// [onSubmitted].
class WebPinField extends StatefulWidget {
  /// Crea el campo.
  const WebPinField({
    super.key,
    required this.controller,
    required this.label,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.autofocus = false,
    this.textInputAction = TextInputAction.done,
    this.focusNode,
    this.error = false,
  });

  /// Lo escrito.
  final TextEditingController controller;

  /// La etiqueta flotante.
  final String label;

  /// Enter.
  final VoidCallback? onSubmitted;

  /// Cada cambio del texto.
  final VoidCallback? onChanged;

  /// Si se puede escribir.
  final bool enabled;

  /// Si toma el foco al aparecer.
  final bool autofocus;

  /// La tecla de acción del teclado.
  final TextInputAction textInputAction;

  /// Foco propio, si quien lo usa lo necesita.
  final FocusNode? focusNode;

  /// Si se pinta con el borde de error.
  final bool error;

  @override
  State<WebPinField> createState() => _WebPinFieldState();
}

class _WebPinFieldState extends State<WebPinField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final borderColor = widget.error ? t.danger : t.controlBorder;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: RegalosShape.field,
      borderSide: BorderSide(color: c, width: w),
    );
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      readOnly: !widget.enabled,
      autofocus: widget.autofocus,
      obscureText: !_visible,
      // Ni sugerencias ni autocorrección: es un secreto.
      enableSuggestions: false,
      autocorrect: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      style: t.styles.rowTitle,
      onChanged: (_) => widget.onChanged?.call(),
      onSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        enabledBorder: border(borderColor),
        focusedBorder: border(widget.error ? t.danger : t.ink, 2),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton(
            onPressed: widget.enabled
                ? () => setState(() => _visible = !_visible)
                : null,
            child: Text(_visible ? l10n.webGatePinHide : l10n.webGatePinShow),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minHeight: 44),
      ),
    );
  }
}

/// Un hijo que tiembla como el PIN erróneo cada vez que [shakeToken] cambia.
class WebShakeOnChange extends StatefulWidget {
  /// Crea el temblor.
  const WebShakeOnChange({
    super.key,
    required this.shakeToken,
    required this.child,
  });

  /// Cuando cambia, tiembla.
  final Object? shakeToken;

  /// Lo que tiembla.
  final Widget child;

  @override
  State<WebShakeOnChange> createState() => _WebShakeOnChangeState();
}

class _WebShakeOnChangeState extends State<WebShakeOnChange> {
  final GlobalKey<ShakeXState> _shake = GlobalKey<ShakeXState>();

  @override
  void didUpdateWidget(WebShakeOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.shakeToken, widget.shakeToken) &&
        widget.shakeToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _shake.currentState?.shake();
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      ShakeX(key: _shake, child: widget.child);
}
