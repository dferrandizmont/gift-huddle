import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/confirm_dialog.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

const _body =
    'Se borrará el regalo y todo lo que lleva: las notas, el enlace y el '
    'historial de quién lo ha tocado. Esta acción no se puede deshacer y '
    'se propagará a los demás móviles de la familia la próxima vez que '
    'sincronices. Si solo querías esconderlo, mejor déjalo como está.';

Future<bool?> _open(
  WidgetTester tester, {
  required double scale,
  required Size size,
}) async {
  bool? result;
  await pumpThemed(
    tester,
    Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () async => result = await showRegalosConfirm(
            context,
            title: '¿Borrar «Patinete con ruedas grandes»?',
            body: _body,
            confirmLabel: 'Borrar regalo',
            cancelLabel: 'Cancelar',
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
    textScale: scale,
    surfaceSize: size,
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  setUpAll(loadInter);

  for (final size in const [Size(390, 844), Size(800, 1280), Size(360, 640)]) {
    testWidgets('el diálogo de confirmar no desborda al 200 % en $size', (
      tester,
    ) async {
      await _open(tester, scale: 2, size: size);
      expect(tester.takeException(), isNull);
      // Se ve entero o se puede desplazar: nunca se sale de la pantalla.
      final surface = tester.getRect(
        find
            .descendant(
              of: find.byType(ConfirmDialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(surface.top, greaterThanOrEqualTo(0));
      expect(surface.bottom, lessThanOrEqualTo(size.height));
      expect(surface.width, lessThanOrEqualTo(340));
      // Los dos botones están y se pueden tocar.
      expect(find.text('Cancelar'), findsOneWidget);
      await tester.ensureVisible(find.text('Borrar regalo'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('al 200 % los botones se apilan', (tester) async {
    await _open(tester, scale: 2, size: const Size(390, 844));
    expect(
      tester.getTopLeft(find.byType(OutlinedButton)).dy,
      lessThan(tester.getTopLeft(find.byType(FilledButton)).dy),
    );
    expect(
      tester.getTopLeft(find.byType(OutlinedButton)).dx,
      tester.getTopLeft(find.byType(FilledButton)).dx,
    );
  });

  testWidgets('al 100 % los botones van lado a lado', (tester) async {
    await _open(tester, scale: 1, size: const Size(390, 844));
    expect(
      tester.getTopLeft(find.byType(OutlinedButton)).dy,
      tester.getTopLeft(find.byType(FilledButton)).dy,
    );
  });

  testWidgets('al 200 % se puede confirmar y cancelar', (tester) async {
    await _open(tester, scale: 2, size: const Size(390, 844));
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmDialog), findsNothing);
  });
}
