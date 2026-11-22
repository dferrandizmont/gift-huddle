// Las compilaciones de tienda conservan la ruta de reserva (1.0.6): ningún
// comando de publicación fija el servidor, porque `SYNC_HOST` o
// `SYNC_API_ORIGIN` dejan la app con un solo host.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/sync/data/sync_endpoint.dart';

void main() {
  test('ninguna guía ni script de publicación pasa SYNC_HOST o '
      'SYNC_API_ORIGIN', () {
    final roots = ['../docs/tienda', '../fastlane', '../store', '../tool'];
    final checked = <String>[];
    final offenders = <String>[];
    for (final root in roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final String text;
        try {
          text = entity.readAsStringSync();
        } on FileSystemException {
          continue;
        } on FormatException {
          continue; // binarios (capturas de tienda)
        }
        checked.add(entity.path);
        if (RegExp(r'dart-define=(SYNC_HOST|SYNC_API_ORIGIN)').hasMatch(text)) {
          offenders.add(entity.path);
        }
      }
    }
    for (final file in ['../release.json']) {
      final f = File(file);
      if (!f.existsSync()) continue;
      checked.add(file);
      if (RegExp(r'dart-define=(SYNC_HOST|SYNC_API_ORIGIN)')
          .hasMatch(f.readAsStringSync())) {
        offenders.add(file);
      }
    }
    expect(checked, isNotEmpty);
    expect(
      checked.any((p) => p.replaceAll(r'\', '/').endsWith('tienda/play.md')),
      isTrue,
    );
    expect(offenders, isEmpty);
  });

  test('sin servidor fijado, el principal lleva su reserva', () {
    expect(
      SyncEndpoint.parse(kDefaultSyncHost, explicitOrigin: false)!.routes,
      hasLength(kSyncHosts.length),
    );
    expect(kSyncHosts.length, greaterThan(1));
  });
}
