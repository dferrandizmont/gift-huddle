import 'dart:convert';

import 'vault_store_stub.dart'
    if (dart.library.js_interop) 'vault_store_web.dart'
    as platform;

typedef VaultJson = Map<String, Object?>;

VaultJson cloneVaultJson(VaultJson value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

/// One complete encrypted generation: header, vault, queue and marks.
/// Only the header and opaque entry ids are cleartext.
class VaultSet {
  VaultSet({
    required this.header,
    required this.box,
    Map<String, VaultJson> entries = const {},
    this.marks,
  }) : entries = Map.of(entries);
  final VaultJson header, box;
  final Map<String, VaultJson> entries;
  final VaultJson? marks;
  VaultJson toJson() => {
    'header': header,
    'box': box,
    'entries': entries,
    'marks': marks,
  };
  factory VaultSet.fromJson(Map j) => VaultSet(
    header: Map<String, Object?>.from(j['header'] as Map),
    box: Map<String, Object?>.from(j['box'] as Map),
    entries: {
      for (final e in (j['entries'] as Map).entries)
        e.key as String: Map<String, Object?>.from(e.value as Map),
    },
    marks: j['marks'] == null
        ? null
        : Map<String, Object?>.from(j['marks'] as Map),
  );
  VaultSet copy({Map<String, VaultJson>? entries, VaultJson? marks}) =>
      VaultSet(
        header: header,
        box: box,
        entries: entries ?? this.entries,
        marks: marks ?? this.marks,
      );
}

class VaultState {
  VaultState({this.current, this.pending});
  final VaultSet? current, pending;
  VaultJson toJson() => {
    'current': current?.toJson(),
    'pending': pending?.toJson(),
  };
  factory VaultState.fromJson(Map j) => VaultState(
    current: j['current'] == null
        ? null
        : VaultSet.fromJson(j['current'] as Map),
    pending: j['pending'] == null
        ? null
        : VaultSet.fromJson(j['pending'] as Map),
  );
}

/// The synchronous update runs inside one transaction; completion means durable
/// transaction completion, never just the success of an individual IDB request.
abstract class VaultStore {
  Future<VaultState> read();
  Future<void> transaction(VaultState Function(VaultState state) update);
  Future<void> writePending(VaultSet set) =>
      transaction((s) => VaultState(current: s.current, pending: set));
  Future<void> promotePending() => transaction((s) {
    if (s.pending == null) throw StateError('No pending vault');
    return VaultState(current: s.pending);
  });
  Future<void> deletePending() =>
      transaction((s) => VaultState(current: s.current));
  Future<void> clear() => transaction((_) => VaultState());
}

class MemoryVaultStore extends VaultStore {
  VaultState _state = VaultState();
  Future<void> _tail = Future.value();

  /// Fault injection: called before the atomic replacement, never afterwards.
  void Function()? beforeWrite;
  @override
  Future<VaultState> read() async {
    await _tail;
    return VaultState.fromJson(cloneVaultJson(_state.toJson()));
  }

  @override
  Future<void> transaction(VaultState Function(VaultState) update) {
    final result = _tail.then((_) {
      final next = update(VaultState.fromJson(cloneVaultJson(_state.toJson())));
      beforeWrite?.call();
      _state = VaultState.fromJson(cloneVaultJson(next.toJson()));
    });
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}

Future<VaultStore> openVaultStore({String name = 'gift-huddle-vault'}) =>
    platform.openVaultStore(name);
Future<bool> requestVaultPersistence() => platform.requestVaultPersistence();
