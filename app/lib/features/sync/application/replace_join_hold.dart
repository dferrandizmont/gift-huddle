import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Si «Sustituir y unirme» está cambiando ahora mismo la lista de este móvil
/// por la de la familia que entra (`true` = retiene).
///
/// Para sustituir, la instalación borra lo de este móvil y, unos pasos
/// después, instala la familia nueva: entre medias la app no tiene familia.
/// Sin esta retención el router lo tomaba por un primer uso y mandaba a la
/// bienvenida, lo que sacaba de golpe las cuatro pestañas (y la pantalla de
/// unirse que estaba encima); al instalarse la nueva volvía a Personas y las
/// pestañas se montaban otra vez mientras las viejas aún salían. Las mismas
/// `GlobalKey` en los dos sitios rompían el árbol: pantalla en blanco en el
/// móvil y en negro con dos paneles (M1 de la QA iOS 1.0.5 y 1.0.6).
///
/// Mientras retiene, el router no manda a la bienvenida por no tener familia.
/// Vive en memoria y solo dura la instalación.
final Provider<ReplaceJoinHold> replaceJoinHoldProvider =
    Provider<ReplaceJoinHold>((ref) => ReplaceJoinHold());

/// Ver [replaceJoinHoldProvider].
class ReplaceJoinHold extends ValueNotifier<bool> {
  ReplaceJoinHold() : super(false);

  int _holds = 0;

  /// Retiene hasta el [release] que le corresponde.
  void acquire() {
    _holds++;
    value = true;
  }

  /// Suelta una retención; el router vuelve a decidir al soltar la última.
  void release() {
    if (_holds > 0) _holds--;
    value = _holds > 0;
  }
}
