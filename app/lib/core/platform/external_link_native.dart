import 'package:flutter/services.dart';

import 'external_link.dart';
import 'user_link.dart';

/// Canal nativo de la app (el mismo que recibe los ficheros `.regalos`):
/// `openUrl` abre un enlace `https` de la app en el navegador del sistema y
/// `openUserUrl`, el de un regalo (cualquier tienda, ya comprobado).
const MethodChannel _nativeChannel = MethodChannel(
  'com.dferrandizmont.regalos/incoming',
);

/// [ExternalLinkOpener] sobre el canal nativo de la app.
///
/// Solo abre enlaces `https` de [kExternalLinkHosts], sin usuario ni puerto, y
/// el `mailto:` de soporte ([kSupportMailto]): lo demás se rechaza aquí, antes
/// de llegar al código nativo.
class NativeExternalLinkOpener implements ExternalLinkOpener {
  /// Crea el abridor.
  const NativeExternalLinkOpener();

  /// Si [text] es un enlace que la app puede abrir.
  static bool allows(String text) {
    // Compare the raw authority before Uri discards an explicit :443.
    final authority = RegExp(
      r'^https://([^/?#\s]+)(?:[/?#]|$)',
      caseSensitive: false,
    ).firstMatch(text)?.group(1)?.toLowerCase();
    if (authority != null && !kExternalLinkHosts.contains(authority)) {
      return false;
    }
    final url = Uri.tryParse(text);
    return url != null &&
        (isSupportMailto(url) || (authority != null && url.isScheme('https')));
  }

  @override
  Future<bool> open(String url) async {
    if (!allows(url)) {
      return false;
    }
    try {
      final opened = await _nativeChannel.invokeMethod<bool>('openUrl', url);
      return opened ?? false;
    } on MissingPluginException {
      // Sin código nativo (pruebas, escritorio).
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> openUserLink(String url) async {
    final uri = userLinkUri(url);
    if (uri == null) {
      return false;
    }
    try {
      final opened = await _nativeChannel.invokeMethod<bool>(
        'openUserUrl',
        uri.toString(),
      );
      return opened ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

ExternalLinkOpener createExternalLinkOpener() =>
    const NativeExternalLinkOpener();
