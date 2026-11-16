// Enlace de invitación: `https://<host>/i#<inviteId>`. Dart puro.
// El enlace no lleva ninguna clave: solo sirve para pedir entrada.
library;

final _inviteId = RegExp(r'^[A-Za-z0-9_-]{22}$');
final _link = RegExp(r'https?://([^/#?\s]+)/i#([A-Za-z0-9_-]{22})');
final _whitespace = RegExp(r'\s+');
final _authority = RegExp(
  r'^https://([^/?#\s]+)(?:[/?#]|$)',
  caseSensitive: false,
);

bool _matchesHost(String actual, String expected) =>
    actual.toLowerCase() == expected.toLowerCase();

/// El texto no es una invitación.
class InviteFormatException implements Exception {
  /// Crea el error.
  const InviteFormatException(this.message);

  /// Qué pasó.
  final String message;

  @override
  String toString() => 'InviteFormatException: $message';
}

/// `https://<host>/i#<inviteId>`.
String inviteLink(String host, String inviteId) => 'https://$host/i#$inviteId';

/// Si [inviteId] tiene la forma de un id de invitación (16 bytes en
/// base64url).
bool isInviteId(String inviteId) => _inviteId.hasMatch(inviteId);

/// El id de invitación de un enlace de invitación.
///
/// Acepta el enlace completo, el enlace pegado con espacios o saltos de línea
/// (como lo parten algunas apps de mensajería), un texto que lleve el enlace
/// en medio y el id suelto. Con [expectedHost] solo vale el enlace de ese
/// servidor.
///
/// Lanza [InviteFormatException] si no es una invitación.
String parseInvite(String text, {String? expectedHost}) {
  final compact = text.replaceAll(_whitespace, '');
  if (compact.isEmpty) {
    throw const InviteFormatException('texto vacío');
  }
  if (_inviteId.hasMatch(compact)) {
    return compact;
  }
  final match = _link.firstMatch(compact);
  if (match == null) {
    throw const InviteFormatException('no es un enlace de invitación');
  }
  final uri = Uri.tryParse(match.group(0)!);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (expectedHost != null && !_matchesHost(match.group(1)!, expectedHost))) {
    throw const InviteFormatException('el enlace es de otro servidor');
  }
  return match.group(2)!;
}

/// El id de invitación de un enlace que abre la app (App Link), o `null` si
/// el enlace no es de invitación de [host].
/// Recibe el texto original: [Uri] normaliza y pierde un `:443` explícito.
String? inviteIdFromUri(String link, String host) {
  final authority = _authority.firstMatch(link)?.group(1);
  if (authority == null || !_matchesHost(authority, host)) {
    return null;
  }
  final uri = Uri.tryParse(link);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.path != '/i' ||
      uri.hasQuery ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return isInviteId(uri.fragment) ? uri.fragment : null;
}
