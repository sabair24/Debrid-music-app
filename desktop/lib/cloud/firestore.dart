/// Firestore over its REST API.
///
/// Firestore's wire format types every value — `{"stringValue": "x"}`, `{"integerValue": "3"}` —
/// so the whole job of this file is turning that into ordinary Dart maps and back. It is tedious
/// and it is the entire reason this is one file with no other responsibilities.
///
/// No realtime listeners: REST has none, so callers poll. That is not the compromise it sounds
/// like — this app already polls the catalogue every fifteen seconds, and the two things being
/// watched here (has the PC come online, is there a new download request) are both fine at that
/// pace.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

class FirestoreException implements Exception {
  const FirestoreException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  /// The session expired, or the rules said no. The caller signs in again rather than retrying.
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

/// One document: its id and its fields, already flattened to plain Dart.
class FirestoreDoc {
  const FirestoreDoc(this.id, this.data, {this.updateTime});
  final String id;
  final Map<String, dynamic> data;
  final DateTime? updateTime;
}

class Firestore {
  Firestore({required this.token, CloudConfig? config, http.Client? client})
      : config = config ?? CloudConfig.current,
        _http = client ?? http.Client();

  /// The Firebase ID token. Short-lived by design; the caller refreshes it and builds a new
  /// [Firestore] rather than this class knowing about auth.
  final String token;
  final CloudConfig config;
  final http.Client _http;

  static const _timeout = Duration(seconds: 25);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// One document, or null when it simply is not there — which is the ordinary case for "has my PC
  /// published itself yet", not an error worth throwing over.
  Future<FirestoreDoc?> get(String path) async {
    final res = await _send(() => _http.get(config.documentsUrl(path), headers: _headers));
    if (res.statusCode == 404) return null;
    final body = _decode(res);
    return _toDoc(body);
  }

  /// Every document in a collection. `pageSize` is generous because the collections here are
  /// small: a handful of devices, a handful of servers, a queue of wishes.
  Future<List<FirestoreDoc>> list(String collectionPath, {int pageSize = 300}) async {
    final res = await _send(() => _http.get(
          config.documentsUrl(collectionPath, {'pageSize': '$pageSize'}),
          headers: _headers,
        ));
    if (res.statusCode == 404) return const [];
    final body = _decode(res);
    final docs = body['documents'];
    if (docs is! List) return const [];
    return [
      for (final d in docs)
        if (d is Map<String, dynamic>) _toDoc(d),
    ];
  }

  /// Create or overwrite. Only the named fields are touched — everything else in the document
  /// survives, which is what lets the PC write a token into a request the device created without
  /// clobbering what the device said about itself.
  Future<void> set(String path, Map<String, dynamic> fields, {bool merge = true}) async {
    // Firestore needs every merged field named explicitly, as a REPEATED query parameter — without
    // the mask a PATCH is a full replace and the other side's fields vanish. Repeated keys cannot
    // go through a Map, so this is built by hand rather than handed to Uri's queryParameters.
    final mask = merge
        ? fields.keys.map((k) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(k)}').join('&')
        : '';
    final base = config.documentsUrl(path);
    final url = mask.isEmpty ? base : Uri.parse('$base?$mask');

    final res = await _send(() => _http.patch(
          url,
          headers: _headers,
          body: jsonEncode({'fields': _encodeFields(fields)}),
        ));
    _decode(res);
  }

  Future<void> delete(String path) async {
    final res = await _send(() => _http.delete(config.documentsUrl(path), headers: _headers));
    if (res.statusCode == 404) return;
    _decode(res);
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } catch (e) {
      throw FirestoreException('Geen verbinding met Firestore: $e');
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (res.statusCode >= 200 && res.statusCode < 300) return map;
    final message = ((map['error'] as Map?)?['message'] ?? '').toString();
    throw FirestoreException(
      res.statusCode == 401 || res.statusCode == 403
          ? 'Je sessie is verlopen of de toegang is geweigerd.'
          : 'Firestore antwoordde met ${res.statusCode}${message.isEmpty ? '' : ': $message'}.',
      statusCode: res.statusCode,
    );
  }

  FirestoreDoc _toDoc(Map<String, dynamic> raw) {
    final name = (raw['name'] ?? '').toString();
    final id = name.contains('/') ? name.split('/').last : name;
    final fields = raw['fields'];
    return FirestoreDoc(
      id,
      fields is Map<String, dynamic> ? _decodeFields(fields) : const {},
      updateTime: DateTime.tryParse((raw['updateTime'] ?? '').toString()),
    );
  }

  // ── The typed wire format ──────────────────────────────────────────────────

  static Map<String, dynamic> _encodeFields(Map<String, dynamic> data) =>
      {for (final e in data.entries) e.key: _encodeValue(e.value)};

  static Map<String, dynamic> _encodeValue(Object? v) => switch (v) {
        null => {'nullValue': null},
        final bool b => {'booleanValue': b},
        // Integers go as strings on the wire — Firestore's int64 does not survive JSON's double.
        final int i => {'integerValue': '$i'},
        final double d => {'doubleValue': d},
        final String s => {'stringValue': s},
        final DateTime t => {'timestampValue': t.toUtc().toIso8601String()},
        final List<dynamic> l => {
            'arrayValue': {'values': [for (final e in l) _encodeValue(e)]}
          },
        final Map<dynamic, dynamic> m => {
            'mapValue': {
              'fields': {for (final e in m.entries) '${e.key}': _encodeValue(e.value)}
            }
          },
        _ => {'stringValue': '$v'},
      };

  static Map<String, dynamic> _decodeFields(Map<String, dynamic> fields) =>
      {for (final e in fields.entries) e.key: _decodeValue(e.value)};

  static Object? _decodeValue(Object? raw) {
    if (raw is! Map) return null;
    if (raw.containsKey('nullValue')) return null;
    if (raw.containsKey('booleanValue')) return raw['booleanValue'] == true;
    if (raw.containsKey('integerValue')) return int.tryParse('${raw['integerValue']}') ?? 0;
    if (raw.containsKey('doubleValue')) {
      return (raw['doubleValue'] as num?)?.toDouble() ?? 0.0;
    }
    if (raw.containsKey('stringValue')) return '${raw['stringValue']}';
    if (raw.containsKey('timestampValue')) return DateTime.tryParse('${raw['timestampValue']}');
    if (raw.containsKey('bytesValue')) return base64Decode('${raw['bytesValue']}');
    if (raw.containsKey('arrayValue')) {
      final values = (raw['arrayValue'] as Map?)?['values'];
      if (values is! List) return const [];
      return [for (final v in values) _decodeValue(v)];
    }
    if (raw.containsKey('mapValue')) {
      final f = (raw['mapValue'] as Map?)?['fields'];
      if (f is! Map) return <String, dynamic>{};
      return {for (final e in f.entries) '${e.key}': _decodeValue(e.value)};
    }
    return null;
  }

  void close() => _http.close();
}
