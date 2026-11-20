import 'package:flutter/widgets.dart';

/// Una opción de `PickerField`, de `showPickerSheet` y de
/// `showAnchoredPicker`.
@immutable
class PickerOption<T> {
  const PickerOption({
    required this.value,
    required this.label,
    this.leading,
    this.group,
    this.hint,
    this.enabled = true,
  });

  /// El valor que se devuelve al elegirla.
  final T value;

  /// El texto que se ve y que lee el lector de pantalla.
  final String label;

  /// Lo que va delante del texto (punto, icono, inicial). Es decorativo: el
  /// texto siempre va al lado. Debe caber en 28 x 28.
  final Widget? leading;

  /// Cabecera de sección bajo la que se muestra. Las opciones seguidas con el
  /// mismo grupo comparten cabecera; sin grupo no hay cabecera.
  final String? group;

  /// Una frase bajo el texto (por qué no se puede elegir, por ejemplo).
  final String? hint;

  /// Si se puede elegir. Deshabilitada se ve apagada, no se toca y el lector
  /// de pantalla la lee como no disponible.
  final bool enabled;
}
