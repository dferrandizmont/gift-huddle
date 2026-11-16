import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/unfold_section.dart';
import '../../../core/theme/regalos_shape.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'recovery_file_problem.dart';
import 'recovery_parts.dart';

/// Un campo de contraseña del fichero de recuperación (ADR 0008): oculto con
/// botón de ver, sin autocorrección, sugerencias ni aprendizaje del teclado,
/// con el pegado permitido y la pista de autorrelleno para que un gestor la
/// guarde ([newPassword]) o la ofrezca al abrir.
class RecoveryPasswordField extends StatefulWidget {
  /// Crea el campo.
  const RecoveryPasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.newPassword,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.done,
    this.error = false,
    this.enabled = true,
    this.autofocus = false,
  });

  /// El texto escrito.
  final TextEditingController controller;

  /// La etiqueta del campo.
  final String label;

  /// Si es una contraseña nueva (crear) o la de un fichero ya emitido.
  final bool newPassword;

  /// Cada cambio del texto.
  final VoidCallback? onChanged;

  /// Al terminar con el teclado.
  final VoidCallback? onSubmitted;

  /// La tecla de acción del teclado.
  final TextInputAction textInputAction;

  /// Si se pinta con el borde de error.
  final bool error;

  /// Si se puede escribir.
  final bool enabled;

  /// Si toma el foco al aparecer.
  final bool autofocus;

  @override
  State<RecoveryPasswordField> createState() => _RecoveryPasswordFieldState();
}

class _RecoveryPasswordFieldState extends State<RecoveryPasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: RegalosShape.field,
      borderSide: BorderSide(color: c, width: w),
    );
    final label = _visible
        ? l10n.recoveryFilePasswordHide
        : l10n.recoveryFilePasswordShow;
    void toggle() => setState(() => _visible = !_visible);
    return TextField(
      controller: widget.controller,
      readOnly: !widget.enabled,
      autofocus: widget.autofocus,
      obscureText: !_visible,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      // Con «ver» activo, iOS cambiaría ' y -- por ’ y —: la contraseña es
      // exactamente lo escrito.
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      autofillHints: [
        widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      style: t.styles.rowTitle,
      onChanged: (_) => widget.onChanged?.call(),
      onSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        enabledBorder: border(widget.error ? t.danger : t.controlBorder),
        focusedBorder: border(widget.error ? t.danger : t.ink, 2),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Semantics(
            button: true,
            toggled: _visible,
            enabled: widget.enabled,
            label: label,
            onTap: widget.enabled ? toggle : null,
            excludeSemantics: true,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: widget.enabled ? toggle : null,
              child: Text(label),
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minHeight: 48),
      ),
    );
  }
}

/// Si hay una restauración con fichero en marcha (la mueve la pantalla de
/// «Recuperar con fichero»). Mientras dura, un segundo fichero que llega espera
/// en cola: cambiar de fichero no puede parar una restauración a medias.
final recoveryFileRestoringProvider =
    NotifierProvider<RecoveryFileRestoring, bool>(RecoveryFileRestoring.new);

/// El valor de [recoveryFileRestoringProvider].
class RecoveryFileRestoring extends Notifier<bool> {
  @override
  bool build() => false;

  /// Cambia el valor.
  void set(bool value) => state = value;
}

/// Cuántas pantallas «Recuperar con fichero» hay abiertas (la ruta de go_router
/// no distingue una pantalla ya apilada). El listener de ficheros recibidos no
/// abre otra encima de una abierta.
final recoveryFileScreenOpenProvider =
    NotifierProvider<RecoveryFileScreenOpen, int>(RecoveryFileScreenOpen.new);

/// El valor de [recoveryFileScreenOpenProvider].
class RecoveryFileScreenOpen extends Notifier<int> {
  @override
  int build() => 0;

  /// Suma o resta una pantalla.
  void add(int delta) => state += delta;
}

/// La derivación de Argon2 en marcha: un progreso indeterminado, el motivo y
/// «Cancelar». Aparece plegándose en su sitio.
class RecoveryDerivingCard extends StatelessWidget {
  /// Crea la tarjeta. [onCancel] null la deja sin botón.
  const RecoveryDerivingCard({
    super.key,
    required this.title,
    required this.body,
    this.onCancel,
  });

  /// Lo que se está haciendo.
  final String title;

  /// Por qué tarda.
  final String body;

  /// Cancela la derivación.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: RegalosShape.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: RegalosShape.tiny,
              child: LinearProgressIndicator(
                minHeight: 4,
                color: t.ink,
                backgroundColor: t.soft,
              ),
            ),
            const SizedBox(height: 14),
            Semantics(
              header: true,
              child: Text(title, style: t.styles.rowTitle),
            ),
            const SizedBox(height: 4),
            Text(body, style: t.styles.body.copyWith(color: t.textSecondary)),
            if (onCancel != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onCancel,
                  child: Text(l10n.actionCancel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// El aviso de un fallo bajo un campo o un botón: entra plegándose y se queda
/// con el último texto mientras se pliega al irse.
class RecoveryProblemNote extends StatefulWidget {
  /// Crea el aviso. [problem] null lo pliega.
  const RecoveryProblemNote({super.key, required this.problem});

  /// El fallo, o null.
  final RecoveryFileProblem? problem;

  @override
  State<RecoveryProblemNote> createState() => _RecoveryProblemNoteState();
}

class _RecoveryProblemNoteState extends State<RecoveryProblemNote> {
  RecoveryFileProblem? _last;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final problem = widget.problem ?? _last;
    _last = problem;
    return UnfoldSection(
      show: widget.problem != null,
      child: problem == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recoveryFileProblemTitle(l10n, problem),
                      style: t.styles.metaStrong.copyWith(color: t.danger),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      recoveryFileProblemBody(l10n, problem),
                      style: t.styles.meta,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Una línea corta de aviso (el motivo de una contraseña) que entra y sale
/// plegándose.
class RecoveryFieldNote extends StatefulWidget {
  /// Crea la línea. [text] null la pliega.
  const RecoveryFieldNote({super.key, required this.text});

  /// El texto, o null.
  final String? text;

  @override
  State<RecoveryFieldNote> createState() => _RecoveryFieldNoteState();
}

class _RecoveryFieldNoteState extends State<RecoveryFieldNote> {
  String? _last;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    final text = widget.text ?? _last;
    _last = text;
    return UnfoldSection(
      show: widget.text != null,
      child: text == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  text,
                  style: t.styles.meta.copyWith(color: t.danger),
                ),
              ),
            ),
    );
  }
}

/// Una tarjeta de «trabajando» con indicador, para la pantalla que no tiene
/// derivación (comprobar un fichero abierto).
class RecoveryWorkingCard extends StatelessWidget {
  /// Crea la tarjeta.
  const RecoveryWorkingCard({
    super.key,
    required this.title,
    required this.body,
  });

  /// Lo que se hace.
  final String title;

  /// Una frase.
  final String body;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: RecoveryCard(
      leading: const SizedBox(
        width: 48,
        height: 48,
        child: Center(child: RecoverySpinner(size: 24)),
      ),
      title: title,
      body: body,
    ),
  );
}

/// Un paso de las pantallas de fichero: un aviso corto opcional, el título y
/// la explicación, un campo opcional y el fallo de la última vez.
class RecoveryFileStepBody extends StatelessWidget {
  /// Crea el paso.
  const RecoveryFileStepBody({
    super.key,
    required this.title,
    required this.body,
    this.note,
    this.field,
    this.problem,
  });

  /// El título.
  final String title;

  /// La explicación.
  final String body;

  /// Una línea sobre el título (p. ej. «Has abierto un fichero…»).
  final String? note;

  /// El campo de contraseña, si el paso lo pide.
  final Widget? field;

  /// El fallo de la última vez.
  final RecoveryFileProblem? problem;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (note != null) ...[
          Text(note!, style: t.styles.metaStrong),
          const SizedBox(height: 8),
        ],
        RecoveryHeading(title: title, body: body),
        if (field != null) ...[const SizedBox(height: 20), field!],
        RecoveryProblemNote(problem: problem),
      ],
    );
  }
}
