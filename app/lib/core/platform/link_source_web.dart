import 'package:web/web.dart' as web;

import 'link_source.dart';

class WebLinkSource implements LinkSource {
  WebLinkSource() {
    final link = web.window.location.href;
    final uri = Uri.parse(link);
    if (uri.path == '/i' &&
        RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(uri.fragment)) {
      _initial = link;
      // Remove the invitation before the router starts, including its fragment.
      web.window.history.replaceState(null, '', '/');
    }
  }
  String? _initial;
  @override
  String? takeInitialLink() {
    final uri = _initial;
    _initial = null;
    return uri;
  }

  @override
  Stream<String> get links => const Stream.empty();
}

LinkSource createLinkSource() => WebLinkSource();
