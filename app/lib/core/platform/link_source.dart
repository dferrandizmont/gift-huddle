import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'link_source_native.dart'
    if (dart.library.js_interop) 'link_source_web.dart'
    as platform;

abstract interface class LinkSource {
  // Keep the original authority, including explicit default ports.
  String? takeInitialLink();
  Stream<String> get links;
}

final linkSourceProvider = Provider<LinkSource>(
  (ref) => platform.createLinkSource(),
);
