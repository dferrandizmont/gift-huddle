import 'package:flutter/material.dart';

/// Antes de abrir un selector de fecha o un desplegable, lleva el foco a [to]
/// si se pasa (siempre, esté donde esté el foco) o, sin [to], quita el foco al
/// campo de texto que lo tenga (y a nadie más).
///
/// Si el campo de texto sigue enfocado, al cerrarse el selector el navegador
/// de rutas le devuelve el foco, el teclado se abre solo y tapa el formulario
/// (y un toque rápido mete una letra en el nombre).
///
/// [to] es el control que abre el selector (el botón de fecha o el
/// `PickerField`): el foco pasa a él, así al cerrarse (se confirme o se
/// cancele) el foco vuelve ahí y el siguiente Tab sigue desde él, no desde el
/// principio del formulario. Sin [to] se libera con `UnfocusDisposition.scope`,
/// que además vacía el historial del ámbito: nada lo restaura, pero Tab
/// empieza por el principio.
///
/// Sin [to], no toca otros focos que el de un campo de texto (un botón o un
/// `PickerField` que se abre con el teclado): esos los devuelve
/// `showAnchoredPicker` a quien corresponde.
void releaseTextFocus({FocusNode? to}) {
  // Con [to], el foco va siempre al control que abre el selector, esté donde
  // esté ahora (en un texto o en el contenedor del editor): si no, al cerrarse
  // el selector el foco volvería a ese contenedor.
  if (to != null && to.canRequestFocus && (to.context?.mounted ?? false)) {
    to.requestFocus();
    return;
  }
  final node = FocusManager.instance.primaryFocus;
  final context = node?.context;
  if (node == null || context == null) return;
  final inText =
      context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
  if (inText) node.unfocus(disposition: UnfocusDisposition.scope);
}
