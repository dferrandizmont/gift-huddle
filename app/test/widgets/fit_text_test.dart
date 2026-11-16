import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/widgets/fit_text.dart';

import '../helpers/fonts.dart';
import '../helpers/pump_app.dart';

// FitText: la palabra más larga cabe entera; a letra normal no cambia nada.

void main() {
  setUpAll(loadInter);

  Future<RenderParagraph> pumpFit(
    WidgetTester tester,
    String text, {
    required double width,
    double scale = 1,
    TextStyle style = const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
    ),
    int? maxLines,
  }) async {
    await pumpThemed(
      tester,
      SizedBox(
        width: width,
        child: FitText(text, style: style, maxLines: maxLines),
      ),
      textScale: scale,
    );
    return tester.renderObject<RenderParagraph>(find.text(text));
  }

  double longestWord(RenderParagraph p, String text) {
    var widest = 0.0;
    for (final word in text.split(' ')) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: p.text.style),
        textDirection: TextDirection.ltr,
        textScaler: p.textScaler,
      )..layout();
      widest = painter.width > widest ? painter.width : widest;
    }
    return widest;
  }

  testWidgets('a letra normal es un Text sin tocar', (tester) async {
    await pumpFit(tester, 'Repartiment', width: 236);
    expect(tester.widget<Text>(find.text('Repartiment')).style!.fontSize, 24);
  });

  testWidgets('a letra 2.0 baja el tamaño hasta que la palabra cabe', (
    tester,
  ) async {
    final p = await pumpFit(tester, 'Repartiment', width: 236, scale: 2);
    final size = tester.widget<Text>(find.text('Repartiment')).style!.fontSize!;
    expect(size, lessThan(24));
    expect(size, greaterThan(24 * 0.55));
    expect(longestWord(p, 'Repartiment'), lessThanOrEqualTo(236 + 0.5));
    // Una sola línea: no se parte.
    expect(p.size.height, lessThan(24 * 2 * 1.6));
  });

  testWidgets('varias palabras: se parte entre palabras, nunca dentro', (
    tester,
  ) async {
    final p = await pumpFit(
      tester,
      '24 de desembre',
      width: 130,
      scale: 2,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );
    expect(longestWord(p, '24 de desembre'), lessThanOrEqualTo(130 + 0.5));
  });

  testWidgets('con una palabra corta no cambia el tamaño', (tester) async {
    await pumpFit(tester, 'Ocasions', width: 300, scale: 2);
    expect(tester.widget<Text>(find.text('Ocasions')).style!.fontSize, 24);
  });

  testWidgets('con un tope de líneas la palabra sigue entera', (tester) async {
    final p = await pumpFit(
      tester,
      '1 unassigned',
      width: 90,
      scale: 2,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      maxLines: 3,
    );
    expect(longestWord(p, '1 unassigned'), lessThanOrEqualTo(90 + 0.5));
    expect(p.didExceedMaxLines, isFalse);
  });

  testWidgets('a letra 1,0 una palabra que no cabe no se encoge', (
    tester,
  ) async {
    await pumpFit(tester, 'Repartiment', width: 100);
    final text = tester.widget<Text>(find.text('Repartiment'));
    expect(text.style!.fontSize, 24);
    expect(text.softWrap, isNull);
    expect(text.overflow, isNull);
  });

  for (final scale in [1.4, 1.7]) {
    testWidgets('a letra $scale no baja del tamaño de letra 1,0', (
      tester,
    ) async {
      // Una palabra que ni al suelo cabe: se queda en el tamaño de 1,0
      // (24 px pintados como mínimo) y pasa a una línea con «…».
      await pumpFit(tester, 'Repartiment', width: 100, scale: scale);
      final text = tester.widget<Text>(find.text('Repartiment'));
      final painted = text.style!.fontSize! * scale;
      expect(painted, greaterThanOrEqualTo(24 - 0.01));
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('a letra $scale encoge solo hasta el tamaño de 1,0 si así '
        'cabe', (tester) async {
      // Cabe entera entre el tamaño a esta letra y el de 1,0.
      await pumpFit(tester, 'Repartiment', width: 190, scale: scale);
      final text = tester.widget<Text>(find.text('Repartiment'));
      final painted = text.style?.fontSize ?? 24;
      expect(painted * scale, greaterThanOrEqualTo(24 - 0.01));
      expect(text.softWrap, isNull);
    });
  }
}
