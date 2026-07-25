/// A copy of the library in the cloud, so a device can show it with the PC off.
///
/// Only a copy — the music itself never leaves the PC. What this buys is browsing, and choosing
/// what to download next, at a moment when the machine holding the files is asleep.
///
/// Written from [CatalogSnapshot], which already carries both the encoded catalogue and a
/// fingerprint over its CONTENT. So "has anything changed?" is a string comparison that was
/// already being computed for the LAN clients, and enriching a cover — which changes no bytes of
/// that JSON — costs nothing here either.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../lan/catalog.dart';
import 'firestore.dart';

/// How much encoded catalogue goes in one document.
///
/// Firestore's hard limit is 1 MiB per document. This is well under it: the point is not to sail
/// close to the line but to keep a single failed write from costing the whole catalogue.
const int kCatalogChunkChars = 300 * 1024;

class CatalogMirror {
  CatalogMirror({required this.db, required this.uid});

  final Firestore db;
  final String uid;

  String get _meta => 'users/$uid/catalog/meta';
  String _chunk(int i) => 'users/$uid/catalog/chunk-$i';

  /// Last fingerprint written, so an unchanged library costs one read and no writes.
  String? _lastEtag;

  /// Copy [snapshot] up, if it differs from what is already there.
  ///
  /// Returns true when something was actually written. Never throws: a catalogue that failed to
  /// mirror is a device that cannot browse offline, which is a disappointment — not a reason for
  /// the PC to stop serving music over the network it is on.
  Future<bool> publish(CatalogSnapshot snapshot) async {
    try {
      if (_lastEtag == snapshot.etag) return false;

      // Ask before writing. On a fresh start this PC has no _lastEtag but the cloud may already
      // hold this exact catalogue — from the previous run, or from a second machine.
      final existing = await db.get(_meta);
      if (existing != null && existing.data['etag'] == snapshot.etag) {
        _lastEtag = snapshot.etag;
        return false;
      }

      final payload = _encode(snapshot.json);
      final chunks = _split(payload, kCatalogChunkChars);

      // Chunks first, meta last. A reader that arrives mid-write sees the OLD meta and therefore
      // the old chunk count and etag — a stale catalogue, which is correct — rather than a new
      // meta pointing at chunks that are not all there yet.
      for (var i = 0; i < chunks.length; i++) {
        await db.set(_chunk(i), {'data': chunks[i]});
      }
      await db.set(_meta, {
        'etag': snapshot.etag,
        'chunks': chunks.length,
        'encoding': 'gzip+base64',
        'albums': snapshot.catalog.albums.length,
        'tracks': snapshot.catalog.tracks.length,
        'updatedAt': DateTime.now().toUtc(),
      });

      // Anything left over from a larger catalogue. Harmless if it fails — the meta already says
      // how many chunks count, so a stray one is never read.
      final previous = (existing?.data['chunks'] as num?)?.toInt() ?? 0;
      for (var i = chunks.length; i < previous; i++) {
        try {
          await db.delete(_chunk(i));
        } catch (_) {}
      }

      _lastEtag = snapshot.etag;
      return true;
    } catch (e) {
      debugPrint('Catalogue mirror failed: $e');
      return false;
    }
  }

  /// Read the copy back. Null when there is none, or it is incomplete.
  Future<MirroredCatalog?> fetch() async {
    final meta = await db.get(_meta);
    if (meta == null) return null;
    final count = (meta.data['chunks'] as num?)?.toInt() ?? 0;
    if (count <= 0) return null;

    final parts = <String>[];
    for (var i = 0; i < count; i++) {
      final doc = await db.get(_chunk(i));
      final data = doc?.data['data'];
      // A missing chunk is a torn write, and half a library is worse than none: it would look
      // like albums had been deleted.
      if (data is! String) return null;
      parts.add(data);
    }

    try {
      final json = _decode(parts.join());
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      return MirroredCatalog(
        json: decoded,
        etag: (meta.data['etag'] ?? '').toString(),
        updatedAt: meta.data['updatedAt'] is DateTime ? meta.data['updatedAt'] as DateTime : null,
      );
    } catch (e) {
      debugPrint('Catalogue mirror unreadable: $e');
      return null;
    }
  }

  /// Gzip then base64. JSON compresses about five-fold, which is the difference between one
  /// document and several — and between one read and several every time a device starts.
  static String _encode(List<int> jsonBytes) =>
      base64Encode(gzip.encode(jsonBytes));

  static String _decode(String encoded) =>
      utf8.decode(gzip.decode(base64Decode(encoded)));

  static List<String> _split(String s, int size) {
    if (s.length <= size) return [s];
    return [
      for (var i = 0; i < s.length; i += size)
        s.substring(i, i + size > s.length ? s.length : i + size),
    ];
  }
}

class MirroredCatalog {
  const MirroredCatalog({required this.json, required this.etag, this.updatedAt});

  final Map<String, dynamic> json;
  final String etag;

  /// When the PC last copied this up — what a screen shows to say how fresh it is.
  final DateTime? updatedAt;
}
