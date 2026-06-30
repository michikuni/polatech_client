/// The two kinds of attendance events. [wireName] is exactly the enum constant
/// the backend expects (and the string that gets appended to the signed bytes).
enum AttendanceType {
  checkIn('CHECK_IN', 'Vào ca'),
  checkOut('CHECK_OUT', 'Tan ca');

  const AttendanceType(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// Result of `POST /api/devices/enroll`. Carries the officer (cán bộ) identity
/// so the paired device can show who it belongs to.
class EnrollResult {
  EnrollResult({
    required this.deviceId,
    required this.employeeId,
    required this.status,
    required this.employeeCode,
    required this.fullName,
    required this.position,
    required this.rank,
  });

  final int deviceId;
  final int employeeId;
  final String status;
  final String employeeCode;
  final String fullName;
  final String position;
  final String rank;

  factory EnrollResult.fromJson(Map<String, dynamic> json) => EnrollResult(
        deviceId: json['deviceId'] as int,
        employeeId: json['employeeId'] as int,
        status: json['status'] as String,
        employeeCode: (json['employeeCode'] as String?) ?? '',
        fullName: (json['fullName'] as String?) ?? '',
        position: (json['position'] as String?) ?? '',
        rank: (json['rank'] as String?) ?? '',
      );
}

/// One day in the attendance history (`GET /api/attendance/history`).
/// [date] is `yyyy-MM-dd`; [checkIn] / [checkOut] are ISO-8601 instants for the
/// earliest (vào ca) and latest (ra ca) punch of that day, or null if absent.
class DailyHistory {
  DailyHistory({required this.date, this.checkIn, this.checkOut});

  final String date;
  final String? checkIn;
  final String? checkOut;

  factory DailyHistory.fromJson(Map<String, dynamic> json) => DailyHistory(
        date: json['date'] as String,
        checkIn: json['checkIn'] as String?,
        checkOut: json['checkOut'] as String?,
      );
}

/// Result of `POST /api/challenge`.
class ChallengeResult {
  ChallengeResult({
    required this.challengeId,
    required this.challenge,
    required this.expiresAt,
  });

  final int challengeId;

  /// Base64 of the 32-byte nonce the device must sign.
  final String challenge;
  final String expiresAt;

  factory ChallengeResult.fromJson(Map<String, dynamic> json) => ChallengeResult(
        challengeId: json['challengeId'] as int,
        challenge: json['challenge'] as String,
        expiresAt: json['expiresAt'] as String,
      );
}

/// Result of `POST /api/attendance`.
class AttendanceEvent {
  AttendanceEvent({
    required this.id,
    required this.employeeId,
    required this.deviceId,
    required this.type,
    required this.eventTime,
  });

  final int id;
  final int employeeId;
  final int deviceId;
  final String type;
  final String eventTime;

  factory AttendanceEvent.fromJson(Map<String, dynamic> json) => AttendanceEvent(
        id: json['id'] as int,
        employeeId: json['employeeId'] as int,
        deviceId: json['deviceId'] as int,
        type: json['type'] as String,
        eventTime: json['eventTime'] as String,
      );
}

/// A backend error surfaced from the `{ success:false, error:{...} }` envelope
/// (or a transport/parse failure). [code] is the backend's `ErrorCode` when known.
class ApiException implements Exception {
  ApiException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => code == null ? message : '$message ($code)';
}
