import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:regalos/core/platform/document_exchange.dart';
import 'package:share_plus/share_plus.dart';

/// Los bytes de un texto hexadecimal.
Uint8List hexBytes(String text) => Uint8List.fromList([
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
]);

/// Los ficheros de recuperación de los vectores del ADR 0008.
class RecoveryFileVectors {
  RecoveryFileVectors._(this.open, this.protectedAscii, this.asciiPassword);

  /// Un fichero de la variante abierta.
  final Uint8List open;

  /// Un fichero protegido.
  final Uint8List protectedAscii;

  /// La contraseña del protegido.
  final String asciiPassword;

  /// Lee los vectores (`docs/adr/0008-vector-fichero.json`).
  static RecoveryFileVectors load() {
    final vector = jsonDecode(
      File('../docs/adr/0008-vector-fichero.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final ascii = [
      for (final p in vector['protected'] as List) p as Map<String, Object?>,
    ].firstWhere((p) => p['name'] == 'ascii');
    return RecoveryFileVectors._(
      hexBytes((vector['open'] as Map)['fileHex'] as String),
      hexBytes(ascii['fileHex'] as String),
      utf8.decode(hexBytes(ascii['passwordUtf8Hex'] as String)),
    );
  }
}

/// La plataforma sin plataforma, para las pruebas de pantalla del fichero de
/// recuperación: selectores y hoja de compartir simulados.
class FakeDocumentExchange implements DocumentExchange {
  /// Lo que devuelve el selector de abrir (null = la persona cancela).
  Uint8List? picked;

  /// Si el selector de abrir falla con esto.
  Object? pickError;

  /// Si el selector de guardar falla con esto.
  Object? saveError;

  /// Lo que se escribió con el selector de guardar.
  final List<Uint8List> saved = [];

  /// Lo que se relee del destino (por defecto, lo mismo que se escribió);
  /// null = la persona cancela.
  Uint8List? Function(Uint8List written) readBack = (w) => w;

  /// Lo compartido con la hoja de compartir y su texto.
  final List<Uint8List> shared = [];
  final List<String> sharedTexts = [];

  /// Los nombres con que se guardó o compartió.
  final List<String> names = [];

  /// Si la normalización NFC de la plataforma falla con esto.
  Object? normalizeError;

  @override
  Future<String> normalizeNfc(String text) async {
    final error = normalizeError;
    if (error != null) throw error;
    return text;
  }

  @override
  Future<Uint8List?> openWithPicker({required int maxBytes}) async {
    final error = pickError;
    if (error != null) throw error;
    return picked;
  }

  @override
  Future<Uint8List?> saveWithPicker(
    Uint8List bytes,
    String name, {
    required int maxReadBytes,
  }) async {
    final error = saveError;
    if (error != null) throw error;
    saved.add(bytes);
    names.add(name);
    return readBack(bytes);
  }

  @override
  Future<ShareResult> shareRecoveryFile(
    Uint8List bytes,
    String name, {
    required String text,
    Rect? origin,
  }) async {
    shared.add(bytes);
    sharedTexts.add(text);
    names.add(name);
    return const ShareResult('', ShareResultStatus.success);
  }

  @override
  Future<void> clearRecoveryShares() async {}

  @override
  Future<void> startReceiving(Future<void> Function(Uint8List) receive) async {}

  @override
  void stopReceiving() {}

  @override
  Future<void> clearExports() async {}

  @override
  Future<XFile> exportBytes(Uint8List bytes, String name) =>
      throw UnimplementedError();

  @override
  Future<Uint8List?> pickBytes() => throw UnimplementedError();

  @override
  Future<ShareResult> shareBytes(
    Uint8List bytes,
    String name, {
    required String text,
    Rect? origin,
  }) => throw UnimplementedError();
}
