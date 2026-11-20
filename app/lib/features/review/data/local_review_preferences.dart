import 'dart:convert';

import '../../family/data/storage.dart';
import '../domain/review_ports.dart';

class LocalReviewPreferences implements ReviewPreferences {
  LocalReviewPreferences(this._files);

  static const _fileName = 'review.json';
  static const _emptyHistory = (count: 0, lastRequestedAt: null);

  final FileStore _files;

  @override
  Future<ReviewHistory> readHistory() async {
    final bytes = await _files.read(_fileName);
    if (bytes == null) return _emptyHistory;

    final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    final count = json['count'] as int;
    final timestamp = json['lastRequestedAt'] as String?;
    final date = timestamp == null ? null : DateTime.tryParse(timestamp);
    if (count < 0 || (count > 0 && date == null)) {
      throw const FormatException('Invalid review history');
    }
    return count == 0 ? _emptyHistory : (count: count, lastRequestedAt: date);
  }

  @override
  Future<void> writeHistory(ReviewHistory history) => _files.writeAtomic(
    _fileName,
    utf8.encode(
      jsonEncode({
        'count': history.count,
        'lastRequestedAt': history.lastRequestedAt?.toUtc().toIso8601String(),
      }),
    ),
  );
}
