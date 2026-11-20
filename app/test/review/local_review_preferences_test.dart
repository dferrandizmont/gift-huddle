import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/features/family/data/storage_native.dart';
import 'package:regalos/features/review/data/local_review_preferences.dart';

void main() {
  test('request history persists in a file excluded from backup', () async {
    final dir = await Directory.systemTemp.createTemp('review_preferences_');
    addTearDown(() => dir.delete(recursive: true));
    final excluded = <String>[];
    final files = DirectoryFileStore(
      () async => dir,
      excludeFromBackupHook: (path) async {
        excluded.add(File(path).uri.pathSegments.last);
      },
    );
    final preferences = LocalReviewPreferences(files);
    expect(await preferences.readHistory(), (count: 0, lastRequestedAt: null));
    expect(await dir.list().toList(), isEmpty);

    final date = DateTime.utc(2026, 11, 20);
    final history = (count: 2, lastRequestedAt: date);
    await preferences.writeHistory(history);
    expect(excluded, ['review.json.tmp', 'review.json']);
    expect(await LocalReviewPreferences(files).readHistory(), history);
    expect(jsonDecode(utf8.decode((await files.read('review.json'))!)), {
      'count': 2,
      'lastRequestedAt': date.toIso8601String(),
    });
  });
}
