/// VM support is deliberately ASCII-only: Unicode PINs require browser NFC.
String normalizeNfc(String pin) {
  if (pin.codeUnits.any((unit) => unit > 0x7f)) {
    throw UnsupportedError(
      'Non-ASCII vault PINs require browser NFC normalization',
    );
  }
  return pin;
}
