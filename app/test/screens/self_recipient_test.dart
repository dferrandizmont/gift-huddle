import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/motion/success_mark.dart';
import 'package:regalos/core/widgets/person_avatar.dart';
import 'package:regalos/core/widgets/sheet_parts.dart';
import 'package:regalos/features/family/application/self_recipient_provider.dart';
import 'package:regalos/features/family/data/family_store.dart';
import 'package:regalos/features/settings/application/locale_provider.dart';

import '../helpers/memory_stores.dart';
import '../helpers/other_phone.dart';
import '../helpers/screens.dart';

const _row = 'Este móvil es de';
const _sheetTitle = '¿De quién es este móvil?';

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Ajustes').last);
  await settle(tester);
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text(_row));
  await settle(tester);
  expect(find.byType(BottomSheet), findsOneWidget);
}

/// El id de «Yo» que ve la app y el que quedó guardado.
Future<(String?, String?)> _self(WidgetTester tester, FakePhone phone) async {
  final stored = await tester.runAsync(
    () => phone.container.read(familyStoreProvider).readSelfRecipient(),
  );
  return (phone.container.read(selfRecipientIdProvider), stored);
}

/// La opción de la hoja con ese nombre.
Finder _option(String name) => find.widgetWithText(CheckOptionRow, name);

/// «Este móvil es de» en Ajustes y su hoja (ADR 0004, «Yo»).
void main() {
  screenTest('la fila es la primera de Este móvil y dice «Nadie» si no se ha '
      'elegido', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openSettings(tester);
    expect(find.bySemanticsLabel('$_row. Nadie'), findsOneWidget);
    final y = tester.getTopLeft(find.text(_row)).dy;
    expect(y, greaterThan(tester.getTopLeft(find.text('Este móvil')).dy));
    expect(y, lessThan(tester.getTopLeft(find.text('Bloqueo')).dy));
    expect(find.byType(BottomSheet), findsNothing);
    expect(await _self(tester, phone), (null, null));
  });

  screenTest('la hoja lista a las personas con su avatar y «Nadie», con un '
      'visto en la elegida; elegir, cambiar y quitar', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openSettings(tester);
    await _openSheet(tester);

    // Título, la frase que dice que solo vale aquí y nada sobre sorpresas.
    expect(find.text(_sheetTitle), findsOneWidget);
    expect(
      find.text('Solo vale en este móvil; no se comparte.'),
      findsOneWidget,
    );
    expect(find.textContaining('sorpresa'), findsNothing);
    // Las tres personas, por orden, con su avatar cuadrado, y «Nadie» al
    // final.
    final names = [
      for (final row in tester.widgetList<CheckOptionRow>(
        find.byType(CheckOptionRow),
      ))
        row.title,
    ];
    expect(names, ['Aritz', 'Leo', 'Nora', 'Nadie']);
    for (final name in ['Aritz', 'Leo', 'Nora']) {
      final avatar = tester.widget<PersonAvatar>(
        find.descendant(of: _option(name), matching: find.byType(PersonAvatar)),
      );
      expect(avatar.name, name);
      expect(PersonAvatar.radiusFor(avatar.size), lessThanOrEqualTo(8));
    }
    expect(
      find.descendant(
        of: _option('Nadie'),
        matching: find.byType(PersonAvatar),
      ),
      findsNothing,
    );
    // Un solo visto, en «Nadie».
    expect(find.byType(DrawnCheck), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Nadie').last),
      isSemantics(
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Nora')),
      isSemantics(hasCheckedState: true, isChecked: false),
    );

    // Elegir: el visto se dibuja en la persona tocada y la hoja baja sola.
    await tester.tap(_option('Nora'));
    await tester.pump();
    expect(find.byType(DrawnCheck), findsOneWidget);
    expect(
      find.descendant(of: _option('Nora'), matching: find.byType(DrawnCheck)),
      findsOneWidget,
    );
    await settleSaved(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.bySemanticsLabel('$_row. Nora'), findsOneWidget);
    expect(await _self(tester, phone), ('nora', 'nora'));

    // Cambiar: al abrir, el visto está en Nora; se pasa a Leo.
    await _openSheet(tester);
    expect(
      find.descendant(of: _option('Nora'), matching: find.byType(DrawnCheck)),
      findsOneWidget,
    );
    expect(find.byType(DrawnCheck), findsOneWidget);
    await tester.tap(_option('Leo'));
    await settleSaved(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.bySemanticsLabel('$_row. Leo'), findsOneWidget);
    expect(await _self(tester, phone), ('leo', 'leo'));

    // Quitar: «Nadie».
    await _openSheet(tester);
    await tester.tap(_option('Nadie'));
    await settleSaved(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.bySemanticsLabel('$_row. Nadie'), findsOneWidget);
    expect(await _self(tester, phone), (null, null));
  });

  screenTest('cerrar la hoja sin elegir no cambia nada', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openSettings(tester);
    await _openSheet(tester);
    await tester.tap(_option('Leo'));
    await settleSaved(tester);
    await _openSheet(tester);
    await tester.tapAt(const Offset(195, 60));
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.bySemanticsLabel('$_row. Leo'), findsOneWidget);
    expect(await _self(tester, phone), ('leo', 'leo'));
  });

  screenTest('si otro móvil elimina a la persona elegida, la fila vuelve a '
      '«Nadie» y la hoja ya no la lista', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openSettings(tester);
    await _openSheet(tester);
    await tester.tap(_option('Nora'));
    await settleSaved(tester);
    expect(find.bySemanticsLabel('$_row. Nora'), findsOneWidget);

    // Aquí no se puede eliminar a «Yo»: llega de otro móvil.
    await driveAsync(tester, () => deletedElsewhere(phone, 'nora'));
    await settle(tester);
    expect(find.bySemanticsLabel('$_row. Nadie'), findsOneWidget);
    expect(await _self(tester, phone), (null, null));

    await _openSheet(tester);
    expect(_option('Nora'), findsNothing);
    expect(
      find.descendant(of: _option('Nadie'), matching: find.byType(DrawnCheck)),
      findsOneWidget,
    );
    expect(find.byType(DrawnCheck), findsOneWidget);
  });

  screenTest('las personas archivadas no salen en la hoja, salvo la elegida', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await tester.runAsync(() => familyOf(phone).archiveRecipient('leo'));
    await pumpRegalos(tester, phone);
    await _openSettings(tester);
    await _openSheet(tester);
    expect(_option('Leo'), findsNothing);
    await tester.tap(_option('Nora'));
    await settleSaved(tester);

    // Que otro móvil archive a la elegida no le quita este.
    await driveAsync(tester, () => archivedElsewhere(phone, 'nora'));
    await settle(tester);
    expect(find.bySemanticsLabel('$_row. Nora'), findsOneWidget);
    await _openSheet(tester);
    expect(
      find.descendant(of: _option('Nora'), matching: find.byType(DrawnCheck)),
      findsOneWidget,
    );
    expect(_option('Leo'), findsNothing);
  });

  screenTest('sin personas, la hoja solo ofrece «Nadie»', (
    tester,
    phone,
  ) async {
    await bareFamily(tester, phone);
    await pumpRegalos(tester, phone);
    await _openSettings(tester);
    expect(find.bySemanticsLabel('$_row. Nadie'), findsOneWidget);
    await _openSheet(tester);
    expect(find.byType(CheckOptionRow), findsOneWidget);
    expect(_option('Nadie'), findsOneWidget);
  });

  screenTest('con «Reducir movimiento» la hoja también elige y se cierra', (
    tester,
    phone,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openSettings(tester);
    await _openSheet(tester);
    await tester.tap(_option('Aritz'));
    await settleSaved(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.bySemanticsLabel('$_row. Aritz'), findsOneWidget);
  });

  screenTest('la fila y la hoja, en catalán y en inglés', (
    tester,
    phone,
  ) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await _openSettings(tester);
    final locale = phone.container.read(localeProvider.notifier);

    locale.setLocale(const Locale('ca'));
    await settle(tester);
    expect(find.bySemanticsLabel('Aquest mòbil és de. Ningú'), findsOneWidget);
    await tester.tap(find.text('Aquest mòbil és de'));
    await settle(tester);
    expect(find.text('De qui és aquest mòbil?'), findsOneWidget);
    expect(
      find.text('Només val en aquest mòbil; no es comparteix.'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(195, 60));
    await settle(tester);

    locale.setLocale(const Locale('en'));
    await settle(tester);
    expect(
      find.bySemanticsLabel('This phone belongs to. No one'),
      findsOneWidget,
    );
    await tester.tap(find.text('This phone belongs to'));
    await settle(tester);
    expect(find.text('Whose phone is this?'), findsOneWidget);
    expect(
      find.text('Only applies to this phone; it is not shared.'),
      findsOneWidget,
    );
  });
}
