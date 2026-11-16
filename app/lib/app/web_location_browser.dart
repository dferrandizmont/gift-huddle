import 'package:web/web.dart' as web;

/// Read and clear the QR route before GoRouter can observe its fragment.
void clearWebPairingLocation() {
  final uri = Uri.parse(web.window.location.href);
  if (uri.path == '/w') web.window.history.replaceState(null, '', '/');
}
