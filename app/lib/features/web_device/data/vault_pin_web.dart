import 'dart:js_interop';

extension type _NormalizableString(JSString value) implements JSString {
  external JSString normalize(JSString form);
}

String normalizeNfc(String pin) =>
    _NormalizableString(pin.toJS).normalize('NFC'.toJS).toDart;
