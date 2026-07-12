import 'dart:convert';

/// What a QR from the admin portal carries. Three shapes are accepted:
///
///  * `{"url":"http://192.168.1.10:8080","code":"ABCDEFGH23"}` — connect **and**
///    pair in one scan (the code the admin issued for this officer).
///  * `{"url":"http://192.168.1.10:8080"}` — connect only. An already-paired
///    phone follows the server to a new address ("Đổi máy chủ") without needing
///    a fresh pairing code.
///  * `ABCDEFGH23` — a bare code (older QRs / hand-made ones); [baseUrl] is then
///    null and the server address must already be configured.
class PairingQr {
  const PairingQr({this.code, this.baseUrl})
      : assert(code != null || baseUrl != null, 'a QR must carry a code or a URL');

  /// The one-time pairing code, or null for a connect-only QR.
  final String? code;

  /// Normalised server address (`http://host:port`, no trailing slash), or null
  /// when the QR only carried a code.
  final String? baseUrl;

  /// Parses a scanned QR, or returns null if it holds nothing usable.
  static PairingQr? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    if (text.startsWith('{')) {
      final Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        return null;
      }
      if (decoded is! Map<String, dynamic>) return null;
      final code = (decoded['code'] as Object?)?.toString().trim() ?? '';
      final baseUrl = _normalizeUrl((decoded['url'] as Object?)?.toString());
      if (code.isEmpty && baseUrl == null) return null;
      return PairingQr(
        code: code.isEmpty ? null : code.toUpperCase(),
        baseUrl: baseUrl,
      );
    }

    // Bare pairing code — normalise to the server's alphabet like typed input.
    return PairingQr(code: text.toUpperCase());
  }

  /// Accepts only an absolute http(s) URL; anything else is treated as absent so
  /// a malformed QR can never point the app at a bogus address.
  static String? _normalizeUrl(String? url) {
    var u = url?.trim() ?? '';
    if (!u.startsWith('http://') && !u.startsWith('https://')) return null;
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    final parsed = Uri.tryParse(u);
    if (parsed == null || parsed.host.isEmpty) return null;
    return u;
  }
}
