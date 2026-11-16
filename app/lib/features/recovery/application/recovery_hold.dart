import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Si la pantalla de «Recuperar con el código» retiene la entrada a la app
/// (`true` = retiene).
///
/// La familia aparece en pleno proceso, antes de que el usuario vea la
/// pantalla final («Lista recuperada», a quién pertenece el móvil y cuántas
/// personas trae). Mientras la pantalla está abierta:
///
/// - el router no saca de la bienvenida a quien ya tiene familia (se llevaba
///   la pantalla a Personas), y
/// - la puerta del bloqueo no tapa la app con «Crea un PIN».
///
/// Al pulsar «Entrar en la lista», o al salir de la pantalla, se suelta: el
/// router vuelve a decidir y el aviso del PIN sale entonces, si toca. Vive en
/// memoria.
///
/// No se "desecha" con el contenedor: los oyentes (router y puerta) se quitan
/// ellos, y soltar la retención en un microtask tras desmontar la pantalla no
/// debe tropezar con un notificador ya cerrado.
final Provider<ValueNotifier<bool>> recoveryHoldProvider =
    Provider<ValueNotifier<bool>>((ref) => ValueNotifier<bool>(false));
