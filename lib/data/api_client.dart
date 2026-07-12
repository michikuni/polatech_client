import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Thin HTTP client for the three public device endpoints of the attendance
/// backend. Talks plain `http://` to a LAN address; every response is the
/// backend's `{ success, data, error }` envelope.
class AttendanceApi {
  AttendanceApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// e.g. `http://192.168.1.10:8080` (no trailing slash).
  final String baseUrl;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 10);

  Future<EnrollResult> enroll({
    required String pairingCode,
    required String publicKeyBase64,
    required String platform,
    required String proofSignatureBase64,
    String? deviceName,
  }) async {
    final data = await _post('/api/devices/enroll', {
      'pairingCode': pairingCode,
      'publicKey': publicKeyBase64,
      'platform': platform,
      'proofSignature': proofSignatureBase64,
      if (deviceName != null && deviceName.isNotEmpty) 'deviceName': deviceName,
    });
    return EnrollResult.fromJson(data);
  }

  Future<ChallengeResult> requestChallenge(int deviceId) async {
    final data = await _post('/api/challenge', {'deviceId': deviceId});
    return ChallengeResult.fromJson(data);
  }

  Future<AttendanceEvent> recordAttendance({
    required int challengeId,
    required AttendanceType type,
    required String signatureBase64,
  }) async {
    final data = await _post('/api/attendance', {
      'challengeId': challengeId,
      'type': type.wireName,
      'signature': signatureBase64,
    });
    return AttendanceEvent.fromJson(data);
  }

  /// Daily check-in/out history for [deviceId]'s officer, most recent first.
  Future<List<DailyHistory>> fetchHistory(int deviceId, {int days = 30}) async {
    final data = await _getList('/api/attendance/history?deviceId=$deviceId&days=$days');
    return data
        .map((e) => DailyHistory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Current check-in/check-out state for [deviceId]'s officer today.
  Future<AttendanceStatus> fetchStatus(int deviceId) async {
    final data = await _get('/api/attendance/status?deviceId=$deviceId');
    return AttendanceStatus.fromJson(data);
  }

  /// Attaches the one-time shift-handover note to check-in [eventId].
  /// The backend rejects a second write, so this only succeeds once per event.
  Future<String> saveNote({
    required int deviceId,
    required int eventId,
    required String note,
  }) async {
    final data = await _post('/api/attendance/note', {
      'deviceId': deviceId,
      'eventId': eventId,
      'note': note,
    });
    return data['note'] as String;
  }

  /// POSTs [body] as JSON, unwraps the envelope, and returns `data` on success.
  /// Throws [ApiException] for backend errors, bad payloads, or transport faults.
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    final http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw ApiException('Hết thời gian chờ máy chủ ($baseUrl). Kiểm tra cùng mạng LAN.');
    } catch (e) {
      throw ApiException('Không kết nối được tới máy chủ: $baseUrl');
    }

    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Phản hồi không hợp lệ (HTTP ${res.statusCode}).');
    }

    final success = envelope['success'] == true;
    if (success && envelope['data'] != null) {
      return envelope['data'] as Map<String, dynamic>;
    }

    final error = envelope['error'] as Map<String, dynamic>?;
    throw ApiException(
      (error?['message'] as String?) ?? 'Yêu cầu thất bại (HTTP ${res.statusCode}).',
      code: error?['code'] as String?,
    );
  }

  /// GETs [path], unwraps the envelope, and returns the `data` object on success.
  /// Throws [ApiException] for backend errors, bad payloads, or transport faults.
  Future<Map<String, dynamic>> _get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw ApiException('Hết thời gian chờ máy chủ ($baseUrl). Kiểm tra cùng mạng LAN.');
    } catch (e) {
      throw ApiException('Không kết nối được tới máy chủ: $baseUrl');
    }

    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Phản hồi không hợp lệ (HTTP ${res.statusCode}).');
    }

    if (envelope['success'] == true && envelope['data'] != null) {
      return envelope['data'] as Map<String, dynamic>;
    }

    final error = envelope['error'] as Map<String, dynamic>?;
    throw ApiException(
      (error?['message'] as String?) ?? 'Yêu cầu thất bại (HTTP ${res.statusCode}).',
      code: error?['code'] as String?,
    );
  }

  /// GETs [path], unwraps the envelope, and returns the `data` array on success.
  /// Throws [ApiException] for backend errors, bad payloads, or transport faults.
  Future<List<dynamic>> _getList(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw ApiException('Hết thời gian chờ máy chủ ($baseUrl). Kiểm tra cùng mạng LAN.');
    } catch (e) {
      throw ApiException('Không kết nối được tới máy chủ: $baseUrl');
    }

    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Phản hồi không hợp lệ (HTTP ${res.statusCode}).');
    }

    if (envelope['success'] == true) {
      return (envelope['data'] as List<dynamic>?) ?? const <dynamic>[];
    }

    final error = envelope['error'] as Map<String, dynamic>?;
    throw ApiException(
      (error?['message'] as String?) ?? 'Yêu cầu thất bại (HTTP ${res.statusCode}).',
      code: error?['code'] as String?,
    );
  }

  void close() => _client.close();
}
