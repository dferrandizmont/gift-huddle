import 'package:app_links/app_links.dart';

import 'link_source.dart';

class NativeLinkSource implements LinkSource {
  @override
  String? takeInitialLink() => null;
  @override
  Stream<String> get links => AppLinks().stringLinkStream;
}

LinkSource createLinkSource() => NativeLinkSource();
