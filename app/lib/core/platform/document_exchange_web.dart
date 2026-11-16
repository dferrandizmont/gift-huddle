import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

import '../sync/envelope.dart';
import '../sync/exchange_file_names.dart';
import 'document_exchange.dart';

class WebDocumentExchange implements DocumentExchange {
  @override
  Future<XFile> exportBytes(Uint8List bytes, String name) async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: kExchangeMimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = name;
    web.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
    // Give the browser time to begin the download before revoking the handle.
    Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
    return XFile.fromData(bytes, name: name, mimeType: kExchangeMimeType);
  }

  @override
  Future<ShareResult> shareBytes(
    Uint8List bytes,
    String name, {
    required String text,
    Rect? origin,
  }) async {
    await exportBytes(bytes, name);
    return const ShareResult('', ShareResultStatus.success);
  }

  @override
  Future<void> startReceiving(Future<void> Function(Uint8List) receive) async {}
  @override
  void stopReceiving() {}

  /// The browser keeps downloads; the app has no copy of its own to remove.
  @override
  Future<void> clearExports() async {}

  /// The recovery file is a phone feature (ADR 0008): no picker on the web.
  @override
  Future<Uint8List?> saveWithPicker(
    Uint8List bytes,
    String name, {
    required int maxReadBytes,
  }) => Future.error(
    const DocumentPickerException(DocumentPickerFailure.unavailable),
  );

  @override
  Future<Uint8List?> openWithPicker({required int maxBytes}) => Future.error(
    const DocumentPickerException(DocumentPickerFailure.unavailable),
  );

  @override
  Future<String> normalizeNfc(String text) => Future.error(
    const DocumentPickerException(DocumentPickerFailure.unavailable),
  );

  @override
  Future<ShareResult> shareRecoveryFile(
    Uint8List bytes,
    String name, {
    required String text,
    Rect? origin,
  }) => Future.error(
    const DocumentPickerException(DocumentPickerFailure.unavailable),
  );

  @override
  Future<void> clearRecoveryShares() async {}

  @override
  Future<Uint8List?> pickBytes() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = kExchangeFileExtensions.join(',')
      ..hidden = true.toJS;
    final done = Completer<Uint8List?>();
    final change = ((web.Event _) {
      () async {
        try {
          final file = input.files?.item(0);
          if (file == null) {
            done.complete(null);
            return;
          }
          if (file.size > kMaxEnvelopeBytes) {
            throw const FormatException('document too large');
          }
          final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
          done.complete(bytes);
        } catch (e, st) {
          done.completeError(e, st);
        }
      }();
    }).toJS;
    final cancel = ((web.Event _) {
      if (!done.isCompleted) done.complete(null);
    }).toJS;
    input.addEventListener('change', change);
    input.addEventListener('cancel', cancel);
    web.document.body!.append(input);
    input.click();
    try {
      return await done.future;
    } finally {
      input.removeEventListener('change', change);
      input.removeEventListener('cancel', cancel);
      input.remove();
    }
  }
}

DocumentExchange createDocumentExchange(Ref ref) => WebDocumentExchange();
