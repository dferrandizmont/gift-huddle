import 'package:flutter/widgets.dart';

/// Si el sistema pide la letra grande (más de 1,3 veces).
///
/// Las filas que a letra normal llevan texto y un control lado a lado (nombre
/// y resumen, regalo y quién lo regala…) pasan entonces a ir una debajo de la
/// otra, para que el texto no se quede en dos letras ni acabe en «…». A letra
/// normal no cambia nada.
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) > 16 * 1.3;

/// Sangría del contenido que baja debajo del nombre cuando una fila se apila:
/// el avatar (28) y su separación (10).
const double kAvatarIndent = 38;

/// Margen inferior de lo que baja apilado debajo de una fila con letra grande.
const double kStackedBottom = 8;
