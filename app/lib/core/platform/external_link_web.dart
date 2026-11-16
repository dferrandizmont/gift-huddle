import 'package:web/web.dart' as web;

import 'external_link.dart';

/// [ExternalLinkOpener] en la web: una pestaña nueva, sin acceso a esta.
class WebExternalLinkOpener implements ExternalLinkOpener {
  /// Crea el abridor.
  const WebExternalLinkOpener();

  @override
  Future<bool> open(String text) async {
    final url = Uri.tryParse(text);
    if (url == null) {
      return false;
    }
    if (isSupportMailto(url)) {
      // Abre la app de correo sin salir de esta pestaña.
      web.window.location.href = url.toString();
      return true;
    }
    if (!url.isScheme('https')) {
      return false;
    }
    web.window.open(url.toString(), '_blank', 'noopener,noreferrer');
    return true;
  }
}

ExternalLinkOpener createExternalLinkOpener() => const WebExternalLinkOpener();
