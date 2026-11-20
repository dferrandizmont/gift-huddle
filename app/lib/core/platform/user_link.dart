/// Comprobaciones de los enlaces que escribe o pega la persona (el enlace de
/// un regalo). Dart puro: no abre nada ni hace ninguna petición.
library;

import '../../features/sync/data/sync_endpoint.dart';
import 'external_link_hosts.dart';

/// El largo máximo de un enlace que se abre.
const int kUserLinkMaxLength = 2048;

// Etiquetas ASCII de 1 a 63 caracteres. La última es alfabética o punycode.
const _hostLabel = r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?';
const _hostTld = r'(?:[A-Za-z]{2,63}|[Xx][Nn]--[A-Za-z0-9-]{0,58}[A-Za-z0-9])';
final RegExp _hostPattern = RegExp('^(?:$_hostLabel\\.)+$_hostTld\$');

final RegExp _httpsAuthority = RegExp(
  r'^https://([^/?#]+)(?:[/?#]|$)',
  caseSensitive: false,
);

final RegExp _unsafeCharacters = RegExp(
  r'[\\\p{Cf}\u0080-\u009f]',
  unicode: true,
);
final RegExp _whitespaceOrControl = RegExp(r'[\s\u0000-\u001f\u007f]');

final String? _invitationHost = SyncEndpoint.parse(
  kSyncHost,
  invitationOrigin: kInvitationOrigin,
)?.invitationOrigin.host.replaceFirst(RegExp(r'\.$'), '');

final Set<String> _reservedHosts = {...kExternalLinkHosts, ?_invitationHost};

/// El enlace de [text] si se puede abrir en el navegador: `https` con un
/// nombre de sitio ASCII ajeno a la app.
///
/// Nunca vale `javascript:`, `http:`, `file:`, `intent:` ni otro esquema; ni un
/// usuario antes del sitio (`https://amazon.es` seguido de `@` y otro sitio), ni un puerto, ni una
/// dirección IP, ni `localhost`, ni texto con espacios. Devuelve `null` si no.
Uri? userLinkUri(String text) {
  final value = text.trim();
  if (value.isEmpty || value.length > kUserLinkMaxLength) {
    return null;
  }
  if (text.contains(_unsafeCharacters) ||
      value.contains(_whitespaceOrControl)) {
    return null;
  }
  // La autoridad en bruto, antes de que `Uri` descarte un `:443` explícito.
  final authority = _httpsAuthority.firstMatch(value)?.group(1);
  if (authority == null || !_hostPattern.hasMatch(authority)) {
    return null;
  }
  final host = authority.toLowerCase();
  if (_reservedHosts.any(
    (domain) => host == domain || host.endsWith('.$domain'),
  )) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) {
    return null;
  }
  return uri;
}

/// El sitio de [text] para enseñarlo («amzn.eu»): en minúsculas y sin `www.`.
/// `null` si [text] no es un enlace que se pueda abrir ([userLinkUri]).
String? userLinkHost(String text) {
  final uri = userLinkUri(text);
  if (uri == null) {
    return null;
  }
  final host = uri.host.toLowerCase();
  return host.startsWith('www.') ? host.substring(4) : host;
}
