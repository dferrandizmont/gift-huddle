import 'package:flutter/material.dart';

/// Si la interfaz se maneja con el dedo (Android, iOS): los controles pequeños
/// del tablero (el «+» de un carril) ganan una zona de toque de 44 por 44. En
/// un ordenador (ratón) siguen con su dibujo compacto.
///
/// Sale de la plataforma del tema, no del ratón conectado: no cambia de
/// tamaño cuando llega el primer movimiento del puntero.
bool usesTouchTargets(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => false,
    };
