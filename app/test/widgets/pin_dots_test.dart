import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/lock/presentation/pin_pad.dart';

import '../helpers/pump_app.dart';

void main() {
  for (final count in [0, 3, 6]) {
    testWidgets(
      'los puntos del PIN son un solo nodo: «PIN: $count de 6 dígitos»',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await pumpThemed(tester, PinDots(count: count));
          final row = find.bySemanticsLabel(RegExp('PIN'));
          // Un solo nodo para la fila, con el valor real.
          expect(row, findsOneWidget);
          final node = tester.getSemantics(row);
          expect(node.label, 'PIN: $count de 6 dígitos');
          // Los seis puntos sueltos no cuelgan de la fila.
          var children = 0;
          node.visitChildren((_) {
            children++;
            return true;
          });
          expect(children, 0);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
