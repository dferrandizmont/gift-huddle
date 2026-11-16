import 'package:flutter_test/flutter_test.dart';

import 'helpers/screens.dart';

void main() {
  screenTest('la app arranca con la barra inferior y la pantalla Personas', (
    tester,
    phone,
  ) async {
    await bareFamily(tester, phone);
    await pumpRegalos(tester, phone);
    expect(find.text('Personas'), findsWidgets);
    expect(find.text('Reparto'), findsOneWidget);
    expect(find.text('Ocasiones'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget);
    expect(find.text('Aún no hay personas'), findsOneWidget);
  });
}
