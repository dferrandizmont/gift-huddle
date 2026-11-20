import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/focus_ring.dart';

import '../helpers/screens.dart';

// Una sola tecla (teclado físico, o Gboard con borrar o intro) no puede dejar
// un velo gris sobre toda la app. La causa estaba en el lado nativo (el
// resalte de foco que Android pinta por defecto sobre la FlutterView, que
// `MainActivity.disableFocusHighlight` quita); aquí se vigila el lado de
// Flutter: tras la tecla, ningún elemento de pantalla completa pinta foco.
void main() {
  for (final brightness in Brightness.values) {
    screenTest(
      'una tecla no pinta ningún foco a pantalla completa (${brightness.name})',
      (tester, phone) async {
        await seedSample(tester, phone);
        await pumpRegalos(tester, phone);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
        await tester.pump(const Duration(milliseconds: 300));
        // FocusRingOverlay mide el foco al final de un fotograma y el pintor
        // recibe el rectángulo en el siguiente.
        await tester.pump();

        final screen = tester.getRect(find.byType(FocusRingOverlay));
        for (final paint in tester.widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(FocusRingOverlay),
            matching: find.byType(CustomPaint),
          ),
        )) {
          final painter = paint.painter;
          if (painter is FocusRingPainter && painter.rect != null) {
            final rect = painter.rect!;
            expect(
              rect.width * rect.height,
              lessThan(screen.width * screen.height * 0.9),
              reason: 'el foco no puede cubrir toda la pantalla',
            );
          }
        }

        // Ni una tinta de foco o de ratón de Material sobre todo el fondo.
        final theme = Theme.of(tester.element(find.byType(FocusRingOverlay)));
        expect(theme.focusColor.a, 0);
        expect(theme.hoverColor.a, 0);
        expect(tester.takeException(), isNull);
      },
      size: const Size(1280, 800),
      brightness: brightness,
    );
  }
}
