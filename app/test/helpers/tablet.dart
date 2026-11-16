import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/sharing/presentation/join_qr_screen.dart';

import 'memory_stores.dart';
import 'screens.dart';

// Los tamaños de prueba del plan de tablet (la guía de diseño para tablet,
// §6, «Para todas las tandas»). En puntos lógicos: las pruebas pintan con
// `devicePixelRatio` 1.

/// El móvil de las pruebas de siempre: la regresión de «compacto no cambia».
const Size kPhoneSize = Size(390, 844);

/// Redmi Pad 2 Pro en vertical: clase «medio».
const Size kTabletPortrait = Size(800, 1280);

/// Redmi Pad 2 Pro en horizontal: clase «expandido».
const Size kTabletLandscape = Size(1280, 800);

/// Los dos tamaños de tablet.
const List<Size> kTabletSizes = [kTabletPortrait, kTabletLandscape];

/// El móvil y los dos de tablet.
const List<Size> kLayoutSizes = [kPhoneSize, kTabletPortrait, kTabletLandscape];

/// «800×1280», para el nombre de las pruebas.
String sizeLabel(Size size) => '${size.width.round()}×${size.height.round()}';

/// Una prueba de pantalla (`screenTest`) que se repite en cada tamaño de
/// [sizes]; por defecto, los dos de tablet. El cuerpo recibe el tamaño con el
/// que arranca.
void tabletScreenTest(
  String description,
  Future<void> Function(WidgetTester tester, FakePhone phone, Size size) body, {
  List<Size> sizes = kTabletSizes,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  ScannerBuilder? scanner,
  Duration writeDelay = Duration.zero,
}) {
  for (final size in sizes) {
    screenTest(
      '$description (${sizeLabel(size)})',
      (tester, phone) => body(tester, phone, size),
      size: size,
      textScale: textScale,
      brightness: brightness,
      scanner: scanner,
      writeDelay: writeDelay,
    );
  }
}

/// Una prueba de widget suelto que se repite en cada tamaño de [sizes]; por
/// defecto, los dos de tablet.
///
/// La ventana ya tiene el tamaño al empezar. Con `pumpThemed` hay que pasarle
/// además `surfaceSize: size`, porque si no vuelve a poner el del móvil.
void tabletWidgetTest(
  String description,
  Future<void> Function(WidgetTester tester, Size size) body, {
  List<Size> sizes = kTabletSizes,
}) {
  for (final size in sizes) {
    testWidgets('$description (${sizeLabel(size)})', (tester) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await body(tester, size);
    });
  }
}

/// El tamaño de la ventana de la prueba, en puntos lógicos.
Size windowSize(WidgetTester tester) =>
    tester.view.physicalSize / tester.view.devicePixelRatio;

/// Cambia el tamaño de la ventana a mitad de la prueba y pinta un fotograma.
///
/// Lo que se ancla a un panel (`PaneAnchor`) se recoloca en el fotograma
/// siguiente: después hace falta otro `pump` o `settle`.
Future<void> setWindowSize(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  await tester.pump();
}

/// Gira la ventana: cambia el ancho por el alto y pinta un fotograma.
Future<void> rotate(WidgetTester tester) {
  final size = windowSize(tester);
  return setWindowSize(tester, Size(size.height, size.width));
}
