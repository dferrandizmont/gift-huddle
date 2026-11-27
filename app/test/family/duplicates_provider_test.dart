import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:regalos/core/sync/model.dart';
import 'package:regalos/features/family/application/family_providers.dart';

Gift gift(String id, String title, {String? note, String recipientId = 'r'}) =>
    Gift(
      id: id,
      recipientId: recipientId,
      title: title,
      status: GiftStatus.idea,
      rawStatus: 'idea',
      surprise: false,
      year: 2026,
      note: note,
    );
FamilyView view(List<Gift> gifts, {bool visible = true}) => FamilyView(
  recipients: visible
      ? [
          const Recipient(
            id: 'r',
            name: 'Aritz',
            colorIndex: 0,
            archived: false,
          ),
        ]
      : [],
  givers: [],
  occasions: [],
  gifts: gifts,
);

final class _DuplicateCalculationObserver extends ProviderObserver {
  int calculations = 0;

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    if (context.provider.name == '_duplicateIdsProvider') calculations++;
  }
}

void main() {
  test('duplicates follow current gifts and matching inputs', () {
    final source = StateProvider<FamilyView>(
      (ref) => view([gift('1', 'Puzle'), gift('2', 'puzle')]),
    );
    final observer = _DuplicateCalculationObserver();
    final container = ProviderContainer(
      observers: [observer],
      overrides: [familyViewProvider.overrideWith((ref) => ref.watch(source))],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(duplicatesProvider, (_, _) {});
    addTearDown(subscription.close);
    expect(container.read(duplicatesProvider), hasLength(1));
    container.read(source.notifier).state = view([
      gift('1', 'Puzle', note: 'updated'),
      gift('2', 'puzle'),
    ]);
    expect(container.read(duplicatesProvider).single.first.note, 'updated');
    final calculationsAfterNoteChange = observer.calculations;
    container.read(source.notifier).state = view([
      gift('1', 'Puzle', note: 'updated again'),
      gift('2', 'puzle'),
    ]);
    expect(container.read(duplicatesProvider).single.first.note, 'updated again');
    expect(observer.calculations, calculationsAfterNoteChange);
    container.read(source.notifier).state = view([
      gift('1', 'Puzle'),
      gift('2', 'Patinete'),
    ]);
    expect(container.read(duplicatesProvider), isEmpty);
    container.read(source.notifier).state = view([
      gift('1', 'Puzle'),
      gift('2', 'puzle'),
    ]);
    expect(container.read(duplicatesProvider), hasLength(1));
    container.read(source.notifier).state = view([
      gift('1', 'Puzle'),
      gift('2', 'puzle', recipientId: 'other'),
    ]);
    expect(container.read(duplicatesProvider), isEmpty);
    container.read(source.notifier).state = view([
      gift('1', 'Puzle'),
      gift('2', 'puzle'),
    ]);
    expect(container.read(duplicatesProvider), hasLength(1));
    container.read(source.notifier).state = view([
      gift('1', 'Puzle'),
      gift('2', 'puzle'),
    ], visible: false);
    expect(container.read(duplicatesProvider), isEmpty);
    container.read(source.notifier).state = view([
      gift('1', 'Puzle'),
      gift('2', 'puzle'),
    ]);
    expect(container.read(duplicatesProvider), hasLength(1));
    container.read(source.notifier).state = view([gift('1', 'Puzle')]);
    expect(container.read(duplicatesProvider), isEmpty);
  });
}
