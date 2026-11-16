import 'dart:typed_data';

import '../../../core/sync/envelope.dart';
import '../../sync/data/sync_transport_common.dart' show SyncResponse;
import 'vault_crypto.dart';

typedef GuardHttp = Future<SyncResponse> Function(
  String method,
  Uri uri, {
  Object? body,
  Map<String, String> headers,
});

enum GuardFailure {
  wrongPin,
  suspended,
  rateLimited,
  disconnected,
  unauthorized,
  retired,
  conflict,
  forbidden,
  protocol,
}

class GuardException implements Exception {
  const GuardException(this.failure, {this.left, this.retryAfter});
  final GuardFailure failure;
  final int? left;
  final Duration? retryAfter;
  bool get disconnected =>
      failure == GuardFailure.disconnected ||
      failure == GuardFailure.unauthorized ||
      failure == GuardFailure.retired;
  @override
  String toString() => 'GuardException(${failure.name})';
}

class GuardProof {
  GuardProof(this.version, this.guardToken, this.proof);
  final int version;
  final List<int> guardToken, proof;
  Map<String, Object?> toJson() => {
    'version': version,
    'guardToken': encodeBase64Url(guardToken),
    'prueba': encodeBase64Url(proof),
  };
}

class GuardOpened {
  GuardOpened(
    this.version,
    this.b, {
    required this.failedSince,
    required this.mustRotate,
  });
  final int version;
  final Uint8List b;
  final int failedSince;
  final bool mustRotate;
}

/// HTTP is injected. Pass WebSyncTransport.send on web: Fetch omits cookies.
/// No auth header is ever attached to open, even if the caller has a credential.
class GuardClient {
  GuardClient({required this.base, required this.send});
  final Uri base;
  final GuardHttp send;
  Future<Map<String, Object?>> _request(
    String method,
    VaultHeader h,
    String route,
    Object body,
    List<int>? credential,
  ) async {
    final response = await send(
      method,
      base.replace(
        path:
            '/v2/lists/${Uri.encodeComponent(h.syncId)}/guards/${Uri.encodeComponent(h.deviceId)}/$route',
      ),
      body: body,
      headers: {
        if (credential != null)
          'Authorization': 'Bearer ${encodeBase64Url(credential)}',
      },
    );
    final status = response.status;
    if (status == 200) return response.json();
    if (status == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '');
      throw GuardException(
        GuardFailure.rateLimited,
        retryAfter: seconds == null ? null : Duration(seconds: seconds),
      );
    }
    if (status == 403 && route == 'open') {
      final j = response.json();
      final left = j['left'];
      if (j['error'] == 'wrong_pin' && left is int && left >= 1 && left <= 9) {
        throw GuardException(GuardFailure.wrongPin, left: left);
      }
    }
    throw GuardException(switch (status) {
      401 => GuardFailure.unauthorized,
      403 => GuardFailure.forbidden,
      404 when route == 'open' => GuardFailure.disconnected,
      409 => GuardFailure.conflict,
      410 => GuardFailure.retired,
      423 => GuardFailure.suspended,
      _ => GuardFailure.protocol,
    });
  }

  Future<void> prepare(
    VaultHeader h,
    List<int> credential, {
    required String tokenHash,
    required String verifier,
    required List<int> b,
  }) async {
    await _request('PUT', h, 'prepare', {
      'version': h.guardVersion,
      'tokenHash': tokenHash,
      'verifier': verifier,
      'secret': encodeBase64Url(b),
    }, credential);
  }

  Future<void> commit(VaultHeader h, List<int> credential) async {
    await _request('POST', h, 'commit', {
      'version': h.guardVersion,
    }, credential);
  }

  Future<int> cancel(VaultHeader h, List<int> credential) async {
    final j = await _request('POST', h, 'cancel', {
      'version': h.guardVersion,
    }, credential);
    if (j['version'] is! int || (j['version'] as int) < 0) {
      throw const GuardException(GuardFailure.protocol);
    }
    return j['version'] as int;
  }

  Future<void> resume(VaultHeader h, List<int> mobileCredential) async {
    await _request('POST', h, 'resume', const {}, mobileCredential);
  }

  Future<GuardOpened> open(VaultHeader h, List<GuardProof> proofs) async {
    if (proofs.isEmpty ||
        proofs.length > 2 ||
        proofs.map((p) => p.version).toSet().length != proofs.length) {
      throw ArgumentError('One proof per version, at most two');
    }
    final j = await _request('POST', h, 'open', {
      'proofs': proofs.map((p) => p.toJson()).toList(),
    }, null);
    final version = j['version'];
    try {
      final b = decodeBase64Url(j['b'] as String);
      if (version is! int ||
          !proofs.any((p) => p.version == version) ||
          b.length != 32 ||
          j['failedSince'] is! int ||
          (j['failedSince'] as int) < 0 ||
          j['mustRotate'] is! bool) {
        throw const FormatException();
      }
      return GuardOpened(
        version,
        b,
        failedSince: j['failedSince'] as int,
        mustRotate: j['mustRotate'] as bool,
      );
    } catch (_) {
      throw const GuardException(GuardFailure.protocol);
    }
  }
}
