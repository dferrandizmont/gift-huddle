import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Revisión de la fase 2b, hallazgo 12: la página `/i` de las invitaciones
/// (`https://gifthuddle.app/i#<id>`) es estática, sin scripts ni
/// recursos de fuera, y se sirve sin Referer.
void main() {
  final page = File('../web/public/i/index.html');
  final css = File('../web/public/i/i.css');
  final headers = File('../web/public/_headers');

  test(
    '/i es estática y no manda Referer',
    () {
      final html = page.readAsStringSync();
      expect(html.toLowerCase(), isNot(contains('<script')));
      // Nada de fuera ni manejadores en línea.
      expect(
        RegExp(
          r'''(src|href)\s*=\s*["']?(https?:)?//''',
          caseSensitive: false,
        ).hasMatch(html),
        isFalse,
      );
      expect(
        RegExp(r'\son[a-z]+\s*=', caseSensitive: false).hasMatch(html),
        isFalse,
      );
      // Solo su hoja de estilos, del mismo origen (la CSP global de Cloudflare
      // se suma a la de /i y bloquearía un <style> en línea). Nada más enlazado.
      const ownSheet = '<link rel="stylesheet" href="/i/i.css">';
      expect('<link'.allMatches(html.toLowerCase()).length, 1);
      expect(html, contains(ownSheet));
      expect(html.toLowerCase(), isNot(contains('<style')));
      // Ni redirecciones, ni otros recursos enlazados, ni imágenes.
      final lower = html.replaceFirst(ownSheet, '').toLowerCase();
      for (final banned in [
        'http-equiv="refresh"',
        "http-equiv='refresh'",
        'http-equiv=refresh',
        '<link',
        'url(',
        '@import',
        'srcset',
        '<img',
        '<iframe',
        '<object',
        '<embed',
        '<form',
      ]) {
        expect(lower, isNot(contains(banned)), reason: banned);
      }
      expect(html, contains('<meta name="referrer" content="no-referrer">'));
      // La hoja no carga nada: ni url(), ni @import.
      final sheet = css.readAsStringSync().toLowerCase();
      for (final banned in ['url(', '@import', '//']) {
        expect(sheet, isNot(contains(banned)), reason: 'i.css: $banned');
      }
    },
    skip: !page.existsSync() || !css.existsSync() || !headers.existsSync()
        ? 'needs ../web (not in this repository)'
        : false,
  );

  test(
    '_headers sirve /i con Referrer-Policy: no-referrer',
    () {
      final blocks = <String, List<String>>{};
      String? path;
      for (final line in headers.readAsLinesSync()) {
        if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
        if (!line.startsWith(' ')) {
          path = line.trim();
          blocks[path] = [];
        } else {
          blocks[path]!.add(line.trim());
        }
      }
      for (final p in ['/i', '/i/', '/i/index.html']) {
        expect(blocks[p], contains('Referrer-Policy: no-referrer'), reason: p);
        expect(
          blocks[p]!.any(
            (h) =>
                h.startsWith('Content-Security-Policy:') &&
                h.contains("default-src 'none'") &&
                !h.contains('script-src'),
          ),
          isTrue,
          reason: p,
        );
      }
      expect(
        blocks['/.well-known/apple-app-site-association'],
        contains('Content-Type: application/json'),
      );
    },
    skip: !page.existsSync() || !css.existsSync() || !headers.existsSync()
        ? 'needs ../web (not in this repository)'
        : false,
  );
}
