// Las casillas de palabras del código de recuperación, para un lector de
// pantalla: cada palabra se anuncia una sola vez, con su número, y cada campo
// de la comprobación una sola vez, con su etiqueta.
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/screens.dart';
import 'recovery_ui_test.dart'
    show askedNumbers, display, openRecoveryRow, recoveryTest;

/// Todos los nodos del árbol de accesibilidad.
List<SemanticsNode> semanticsNodes(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return nodes;
}

void main() {
  recoveryTest('las 24 palabras se anuncian cada una una sola vez, con su '
      'número', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openRecoveryRow(tester);
    await tapText(tester, 'Crear código de recuperación');
    await tapText(tester, 'Continuar');
    expect(find.text('Tus 24 palabras'), findsOneWidget);

    final nodes = semanticsNodes(tester);
    final labels = [for (final n in nodes) n.label];
    for (var i = 0; i < 24; i++) {
      final word = display.words[i];
      final number = '${i + 1}';
      // Un solo nodo la nombra: «Palabra 7: casa».
      final whole = labels.where((l) => l == 'Palabra $number: $word');
      expect(whole, hasLength(1), reason: 'Palabra $number');
      // Y ningún otro repite la palabra suelta ni el número suelto.
      expect(
        labels.where((l) => l == word || l == number),
        isEmpty,
        reason: 'palabra o número repetidos: $number $word',
      );
    }
    expect(
      labels.where((l) => l.startsWith('Palabra ')),
      hasLength(24),
      reason: 'ninguna casilla duplicada',
    );
  });

  recoveryTest('la comprobación tiene tres campos, cada uno anunciado una '
      'sola vez', (tester, phone) async {
    await seedSample(tester, phone);
    await pumpRegalos(tester, phone);
    await openRecoveryRow(tester);
    await tapText(tester, 'Crear código de recuperación');
    await tapText(tester, 'Continuar');
    await tapText(tester, 'Ya las he guardado');
    expect(find.text('Comprueba que las has guardado'), findsOneWidget);

    final asked = askedNumbers(tester);
    final fields = [
      for (final n in semanticsNodes(tester))
        if (n.getSemanticsData().flagsCollection.isTextField) n,
    ];
    expect(fields, hasLength(3));
    for (final number in asked) {
      expect(
        fields.where((n) => n.label == 'Palabra $number'),
        hasLength(1),
        reason: 'Palabra $number',
      );
    }
    // Fuera de los campos nadie más lleva «Palabra N» (no se duplica).
    final outside = [
      for (final n in semanticsNodes(tester))
        if (!n.getSemanticsData().flagsCollection.isTextField &&
            RegExp(r'^Palabra \d+$').hasMatch(n.label))
          n.label,
    ];
    expect(outside, isEmpty);
  });
}
