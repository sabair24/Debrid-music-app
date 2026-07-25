/// Signing in, over Firebase's REST API rather than the Flutter SDK.
///
/// Not a preference. Google's own documentation says: "Firebase on Windows is not intended for
/// production use cases, only local development workflows", and both `firebase_auth` and
/// `cloud_firestore` are marked beta there. Windows is the machine that holds the music, so
/// building the whole thing on a platform Google calls unsuitable for production would be putting
/// the load-bearing wall on the beta.
///
/// REST is the same Firebase — same project, same console, same rules — reached through an API
/// that is stable on every platform, including the Kotlin app on the Shield. What it costs is
/// realtime listeners: everything here polls. The app already polls the catalogue every fifteen
/// seconds, so that changes nothing about how it feels.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

/// A signed-in user. [idToken] is what Firestore wants in an Authorization header; it expires
/// after an hour, which is why [expiresAt] is carried alongside it.
class CloudUser {
  const CloudUser({
    required this.uid,
    required this.email,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String uid;
  final String email;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// Refreshed a minute early: a token that expires while a request is in flight fails the request,
  /// and a minute of slack is cheaper than the retry.
  bool get isExpired => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));

  /// Only the refresh token is written to disk — never the password, and not the id token either,
  /// which would be stale by the next start anyway.
  Map<String, dynamic> toJson() => {'uid': uid, 'email': email, 'refreshToken': refreshToken};

  static ({String uid, String email, String refreshToken})? fromJson(Map<String, dynamic> j) {
    final refresh = (j['refreshToken'] ?? '').toString();
    if (refresh.isEmpty) return null;
    return (
      uid: (j['uid'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      refreshToken: refresh,
    );
  }
}

/// Carries the sentence to put in front of the user. Firebase's own error codes are shouty
/// constants like `INVALID_LOGIN_CREDENTIALS`; nobody should have to read those.
class CloudAuthException implements Exception {
  const CloudAuthException(this.message, {this.code = ''});
  final String message;
  final String code;
  @override
  String toString() => message;
}

class CloudAuth {
  CloudAuth({CloudConfig? config, http.Client? client})
      : config = config ?? CloudConfig.current,
        _http = client ?? http.Client();

  final CloudConfig config;
  final http.Client _http;

  static const _timeout = Duration(seconds: 20);

  Future<CloudUser> signIn(String email, String password) =>
      _identity('signInWithPassword', email, password);

  Future<CloudUser> register(String email, String password) =>
      _identity('signUp', email, password);

  Future<CloudUser> _identity(String method, String email, String password) async {
    _requireConfig();
    final body = await _post(
      config.authUrl(method),
      {'email': email.trim(), 'password': password, 'returnSecureToken': true},
    );
    return CloudUser(
      uid: (body['localId'] ?? '').toString(),
      email: (body['email'] ?? email).toString(),
      idToken: (body['idToken'] ?? '').toString(),
      refreshToken: (body['refreshToken'] ?? '').toString(),
      expiresAt: _expiry(body['expiresIn']),
    );
  }

  /// Trade a stored refresh token for a fresh id token. This is what makes a restart silent:
  /// nobody is asked to type a password again.
  ///
  /// Note the snake_case — the refresh endpoint is a different service from the identity one and
  /// answers in a different style. Reading `idToken` here silently yields null, and the symptom is
  /// an app that appears logged in and is refused by every Firestore call.
  Future<CloudUser> refresh(String refreshToken, {String uid = '', String email = ''}) async {
    _requireConfig();
    final body = await _post(
      config.refreshUrl(),
      {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
    );
    return CloudUser(
      uid: (body['user_id'] ?? uid).toString(),
      email: email,
      idToken: (body['id_token'] ?? '').toString(),
      refreshToken: (body['refresh_token'] ?? refreshToken).toString(),
      expiresAt: _expiry(body['expires_in']),
    );
  }

  DateTime _expiry(Object? seconds) {
    final s = int.tryParse('${seconds ?? ''}') ?? 3600;
    return DateTime.now().add(Duration(seconds: s));
  }

  void _requireConfig() {
    if (!config.isConfigured) {
      throw const CloudAuthException(
        'Er is nog geen Firebase-project ingesteld in deze build.',
        code: 'NOT_CONFIGURED',
      );
    }
  }

  Future<Map<String, dynamic>> _post(Uri url, Map<String, dynamic> payload) async {
    final http.Response res;
    try {
      res = await _http
          .post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
          .timeout(_timeout);
    } catch (e) {
      throw CloudAuthException('Geen verbinding met Firebase: $e', code: 'NETWORK');
    }
    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (res.statusCode == 200) return map;

    final code = ((map['error'] as Map?)?['message'] ?? '').toString();
    throw CloudAuthException(_dutch(code, res.statusCode), code: code);
  }

  /// Firebase deliberately blurs "no such account" and "wrong password" into one code so an
  /// attacker cannot enumerate addresses. Say the same thing for both rather than leaking the
  /// difference back in the translation.
  static String _dutch(String code, int status) => switch (code.split(' : ').first) {
        'EMAIL_NOT_FOUND' ||
        'INVALID_PASSWORD' ||
        'INVALID_LOGIN_CREDENTIALS' =>
          'E-mailadres of wachtwoord klopt niet.',
        'EMAIL_EXISTS' => 'Er bestaat al een account met dit e-mailadres.',
        'WEAK_PASSWORD' => 'Kies een wachtwoord van minstens zes tekens.',
        'INVALID_EMAIL' => 'Dat is geen geldig e-mailadres.',
        'USER_DISABLED' => 'Dit account is uitgeschakeld.',
        'TOO_MANY_ATTEMPTS_TRY_LATER' =>
          'Te veel pogingen. Probeer het over een paar minuten opnieuw.',
        'TOKEN_EXPIRED' ||
        'USER_NOT_FOUND' ||
        'INVALID_REFRESH_TOKEN' =>
          'Je sessie is verlopen. Log opnieuw in.',
        'OPERATION_NOT_ALLOWED' =>
          'Inloggen met e-mail staat uit in dit Firebase-project. Zet het aan onder Authentication → Sign-in method.',
        _ => 'Firebase antwoordde met $status${code.isEmpty ? '' : ' ($code)'}.',
      };

  void close() => _http.close();
}
