import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../core/sync/envelope.dart';
import 'sync_transport_v2.dart';

/// Persist to the recovery journal before sending. No transport retries and no
/// request logging: headers and bodies contain capabilities and credentials.
class RecoveryRequest {
  RecoveryRequest(this.method, this.path, {this.headers = const {}, this.body});
  final String method;
  final String path;
  final Map<String, String> headers;
  final Map<String, Object?>? body;

  Map<String, Object?> toJson() => {
    'method': method,
    'path': path,
    'headers': headers,
    'body': body,
  };
  factory RecoveryRequest.fromJson(Object? raw) {
    final j = raw as Map;
    return RecoveryRequest(
      j['method'] as String,
      j['path'] as String,
      headers: Map<String, String>.from(j['headers'] as Map),
      body: j['body'] == null
          ? null
          : Map<String, Object?>.from(j['body'] as Map),
    );
  }
}

class RecoveryResponse {
  RecoveryResponse(
    this.status, {
    this.body,
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(headers);
  final int status;
  final Object? body;
  final Map<String, String> headers;
  String? get error {
    final raw = body is Map ? (body as Map)['error'] : null;
    if (raw == null) return null;
    return knownRecoveryServerCodes.contains(raw)
        ? raw as String
        : 'invalid_response';
  }

  Map<String, Object?> toJson() => {
    'status': status,
    'body': body,
    'headers': headers,
  };
}

abstract interface class RecoveryTransport {
  Future<RecoveryResponse> send(RecoveryRequest request);
}

class RecoveryTransportException implements Exception {
  const RecoveryTransportException(this.status, this.code);
  final int status;
  final String code;
  bool get retryable =>
      code == 'invalid_response' ||
      status == 408 ||
      status == 429 ||
      status >= 500;
  @override
  String toString() => 'RecoveryTransportException($status, $code)';
}

/// Uses the existing HTTP adapter; capabilities are headers, never query/URL.
class RecoveryClient implements RecoveryTransport {
  RecoveryClient({required this.base, required this.sendRequest});
  final Uri base;
  final V2Send sendRequest;

  @override
  Future<RecoveryResponse> send(RecoveryRequest request) async {
    if (!request.path.startsWith('/v2/') ||
        request.path.contains('?') ||
        request.path.contains('#')) {
      throw const FormatException('invalid recovery path');
    }
    final r = await sendRequest(
      request.method,
      base.replace(path: request.path),
      body: request.body,
      headers: request.headers,
    );
    Object? body;
    try {
      body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.body));
    } on FormatException {
      throw RecoveryTransportException(r.status, 'invalid_response');
    }
    return RecoveryResponse(
      r.status,
      body: body,
      headers: {
        for (final e in r.headers.entries) e.key.toLowerCase(): e.value,
      },
    );
  }
}

const knownRecoveryServerCodes = {
  'invalid_response',
  'invalid_recovery',
  'precondition_required',
  'precondition_failed',
  'unauthorized',
  'revoked',
  'credential_replaced',
  'mobile_required',
  'not_found',
  'rate_limited',
  'recovery_history_full',
  'recovery_too_large',
  'recovery_not_active',
  'recovery_operation_conflict',
  'recovery_credential_conflict',
  'recovery_retired',
  'recovery_exists',
  'recovery_limit',
  'recovery_rotation_expired',
  'recovery_rotation_cancelled',
};

Future<String> recoveryCredentialVerifier(List<int> credential) async =>
    encodeBase64Url((await Sha256().hash(credential)).bytes);

Map<String, String> recoveryAuthHeaders(V2Auth auth, int revision) => {
  'Authorization': auth.bearer,
  'If-Match': '"$revision"',
};
