import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'external_link_hosts.dart';
import 'external_link_native.dart'
    if (dart.library.js_interop) 'external_link_web.dart'
    as platform;

export 'external_link_hosts.dart';

/// Abre un enlace fuera de la app, en el navegador del sistema.
///
/// Sin dependencias: en el móvil lo hace el código nativo de la app por el
/// canal que ya tiene (`Intent.ACTION_VIEW` en Android, `UIApplication.open`
/// en iOS) y en la web, `window.open`. La app no hace ninguna petición: quien
/// se conecta es el navegador.
///
/// [open] es solo para los enlaces fijos de la app (hoy, la política de
/// privacidad y el correo de soporte): en el móvil no abre nada que no sea de
/// [kExternalLinkHosts] o [kSupportMailto]. Los enlaces que pega la persona (el
/// de un regalo) **no pasan por ahí**: tienen su propio método,
/// [openUserLink], con sus propias comprobaciones ([userLinkUri]), y la lista
/// de [kExternalLinkHosts] no se amplía.
abstract interface class ExternalLinkOpener {
  /// Abre [url] (solo `https` de [kExternalLinkHosts] o [kSupportMailto]).
  /// Devuelve `false` si no se ha podido: no hay navegador ni app de correo,
  /// el enlace no está permitido o no hay código nativo (pruebas).
  // The original text is required to reject explicit HTTPS default ports.
  Future<bool> open(String url);

  /// Abre el enlace de un regalo que escribió o pegó la persona. Solo `https`
  /// con un nombre de sitio normal ([userLinkUri]): nunca `javascript:`,
  /// `http:` ni otro esquema, ni un usuario, un puerto o una IP. Devuelve
  /// `false` si no vale o no se ha podido abrir.
  Future<bool> openUserLink(String url);
}

/// El correo de soporte (el mismo de la web, `contact_email` de
/// `web/site.toml`). Reenvía al buzón del titular desde el 2026-11-15.
const String kSupportEmail = 'gifthuddle@gifthuddle.app';

/// El enlace `mailto:` al soporte: el único correo que la app abre. Sin asunto
/// ni cuerpo: no lleva ningún dato de la persona.
final Uri kSupportMailto = Uri(scheme: 'mailto', path: kSupportEmail);

/// Si [url] es exactamente [kSupportMailto] (sin parámetros, que podrían
/// añadir destinatarios o texto).
bool isSupportMailto(Uri url) =>
    url.isScheme('mailto') &&
    url.path.toLowerCase() == kSupportEmail &&
    !url.hasQuery &&
    !url.hasFragment &&
    !url.hasAuthority;

/// Quien abre los enlaces externos. Las pruebas lo sustituyen.
final externalLinkOpenerProvider = Provider<ExternalLinkOpener>(
  (ref) => platform.createExternalLinkOpener(),
);
