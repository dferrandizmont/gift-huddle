import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'link_source.dart';

class NativeLinkSource implements LinkSource {
  bool _initialTaken = false;

  @override
  FutureOr<String?> takeInitialLink() {
    // Android already receives its launch intent through stringLinkStream.
    if (defaultTargetPlatform != TargetPlatform.iOS || _initialTaken) {
      return null;
    }
    _initialTaken = true;
    return _initialLink();
  }

  Future<String?> _initialLink() async {
    try {
      // Keep the original string so validation can reject explicit ports.
      return await AppLinks().getInitialLinkString();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<String> get links => AppLinks().stringLinkStream;
}

LinkSource createLinkSource() => NativeLinkSource();
