import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// One file offered by a Soulseek peer.
class SoulseekFile {
  final String username;
  final String filename; // full remote path (backslash-separated)
  final int size;
  final int speed;
  final int queueLength;
  final bool freeSlots;
  final int? bitrate;
  final int? durationSec;
  final bool isVbr;

  SoulseekFile({
    required this.username,
    required this.filename,
    required this.size,
    this.speed = 0,
    this.queueLength = 0,
    this.freeSlots = false,
    this.bitrate,
    this.durationSec,
    this.isVbr = false,
  });

  SoulseekFile copyWith({int? speed, int? queueLength, bool? freeSlots}) => SoulseekFile(
        username: username, filename: filename, size: size,
        speed: speed ?? this.speed, queueLength: queueLength ?? this.queueLength,
        freeSlots: freeSlots ?? this.freeSlots, bitrate: bitrate, durationSec: durationSec, isVbr: isVbr,
      );

  String get displayName => filename.replaceAll('\\', '/').split('/').last;
  String get ext {
    final i = displayName.lastIndexOf('.');
    return i < 0 ? '' : displayName.substring(i + 1).toLowerCase();
  }

  bool get isFlac => ext == 'flac';
  bool get isAudio => const {'flac', 'mp3', 'm4a', 'ogg', 'opus', 'wav', 'aac', 'alac', 'ape'}.contains(ext);
  Map<String, dynamic> toJson() => {'username': username, 'filename': filename, 'size': size};
}

sealed class SlskResult {}
class SlskDone extends SlskResult { final String path; SlskDone(this.path); }
class SlskFail extends SlskResult { final String reason; SlskFail(this.reason); }

/// Audio files, best-first: FLAC, then free slots, then speed, then size.
List<SoulseekFile> sortSoulseek(Iterable<SoulseekFile> files) {
  final audio = files.where((f) => f.isAudio).toList();
  audio.sort((a, b) {
    final fa = a.isFlac ? 1 : 0, fb = b.isFlac ? 1 : 0;
    if (fa != fb) return fb - fa;
    if (a.freeSlots != b.freeSlots) return a.freeSlots ? -1 : 1;
    if (a.speed != b.speed) return b.speed.compareTo(a.speed);
    return b.size.compareTo(a.size);
  });
  return audio;
}

// ── wire helpers (little-endian) ─────────────────────────────────────────────
class _W {
  final _b = BytesBuilder();
  _W u8(int v) { _b.addByte(v & 0xFF); return this; }
  _W u32(int v) {
    _b.addByte(v & 0xFF); _b.addByte((v >> 8) & 0xFF); _b.addByte((v >> 16) & 0xFF); _b.addByte((v >> 24) & 0xFF);
    return this;
  }
  _W u64(int v) { u32(v & 0xFFFFFFFF); u32((v >> 32) & 0xFFFFFFFF); return this; }
  _W str(String s) { final b = utf8.encode(s); u32(b.length); _b.add(b); return this; }
  Uint8List bytes() => _b.toBytes();
}

class _R {
  final Uint8List d;
  int i = 0;
  _R(this.d);
  int get remaining => d.length - i;
  int u8() => d[i++] & 0xFF;
  int u32() {
    final v = (d[i]) | (d[i + 1] << 8) | (d[i + 2] << 16) | (d[i + 3] << 24);
    i += 4;
    return v & 0xFFFFFFFF;
  }
  int u64() { final lo = u32(); final hi = u32(); return lo + hi * 0x100000000; }
  String str() {
    if (remaining < 4) return '';
    final len = u32().clamp(0, remaining);
    final s = utf8.decode(d.sublist(i, i + len), allowMalformed: true);
    i += len;
    return s;
  }
  bool boolean() => u8() != 0;
  String ip() { final b0 = u8(); final b1 = u8(); final b2 = u8(); final b3 = u8(); return '$b3.$b2.$b1.$b0'; }
}

Uint8List _message(int code, Uint8List payload) =>
    Uint8List.fromList([...(_W()..u32(4 + payload.length)..u32(code)).bytes(), ...payload]);
Uint8List _initMessage(int code, Uint8List payload) =>
    Uint8List.fromList([...(_W()..u32(1 + payload.length)..u8(code)).bytes(), ...payload]);
String _md5hex(String s) => md5.convert(utf8.encode(s)).toString();
Uint8List _zlib(Uint8List data) {
  try {
    return Uint8List.fromList(ZLibCodec().decode(data));
  } catch (_) {
    return data;
  }
}

/// Reads length-prefixed Soulseek messages off a socket stream (payload = [code][data]).
class _Conn {
  final Socket socket;
  final _controller = StreamController<Uint8List>.broadcast();
  final _buf = BytesBuilder();
  _Conn(this.socket) {
    socket.listen(_onData, onError: (_) => _close(), onDone: _close);
  }
  void _onData(Uint8List data) {
    _buf.add(data);
    var bytes = _buf.toBytes();
    var off = 0;
    while (bytes.length - off >= 4) {
      final len = (bytes[off]) | (bytes[off + 1] << 8) | (bytes[off + 2] << 16) | (bytes[off + 3] << 24);
      final total = 4 + (len & 0xFFFFFFFF);
      if (bytes.length - off < total) break;
      _controller.add(Uint8List.sublistView(bytes, off + 4, off + total));
      off += total;
    }
    _buf.clear();
    if (off < bytes.length) _buf.add(bytes.sublist(off));
  }
  Stream<Uint8List> get messages => _controller.stream;
  void send(Uint8List b) => socket.add(b);
  void _close() { if (!_controller.isClosed) _controller.close(); }
}

class SoulseekClient {
  static const _host = 'server.slsknet.org';
  static const _port = 2242;
  final _rng = Random();
  int _nextTicket() => 10000 + _rng.nextInt(900000);

  /// Search the Soulseek network. Returns audio files, FLAC/free-slot first.
  /// [onPartial] streams results as peers respond (like the native client), so the
  /// UI can show the first hits within a second or two instead of waiting the whole window.
  Future<List<SoulseekFile>> search(String user, String pass, String query,
      {void Function(List<SoulseekFile>)? onPartial}) async {
    final ticket = _nextTicket();
    final results = <SoulseekFile>[];
    final peerJobs = <Future<void>>[];
    void emit() {
      if (onPartial != null) onPartial(sortSoulseek(results));
    }

    Socket? server;
    try {
      server = await Socket.connect(_host, _port, timeout: const Duration(seconds: 8));
      final conn = _Conn(server);
      conn.send(_message(1, (_W()..str(user)..str(pass)..u32(160)..str(_md5hex(pass))..u32(17)).bytes()));

      final done = Completer<void>();
      // Shorter window than before (was 13s). Combined with streaming + running the two
      // query variants in parallel (SoulseekService), the first results show in ~1-2s.
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      final sub = conn.messages.listen((payload) {
        final r = _R(payload);
        final code = r.u32();
        if (code == 1) {
          final ok = r.u8() != 0;
          if (!ok) {
            if (!done.isCompleted) done.completeError('Soulseek-login geweigerd: ${r.str()}');
            return;
          }
          conn.send(_message(2, (_W()..u32(0)).bytes())); // SetWaitPort(0)
          conn.send(_message(26, (_W()..u32(ticket)..str(query)).bytes())); // FileSearch
        } else if (code == 18) {
          r.str(); // peer user
          final type = r.str();
          final ip = r.ip();
          final port = r.u32();
          final token = r.u32();
          if (type == 'P' && ip != '0.0.0.0' && port > 0 && peerJobs.length < 60) {
            peerJobs.add(_collectPeer(ip, port, token, ticket, results, emit));
          }
        }
      }, onError: (_) {}, onDone: () { if (!done.isCompleted) done.complete(); });

      final poll = Timer.periodic(const Duration(milliseconds: 300), (t) {
        if (DateTime.now().isAfter(deadline) || results.length >= 300) {
          t.cancel();
          if (!done.isCompleted) done.complete();
        }
      });
      await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
      poll.cancel();
      await sub.cancel();
      await Future.wait(peerJobs).timeout(const Duration(seconds: 3)).catchError((_) => <void>[]);
    } catch (e) {
      if (results.isEmpty) rethrow;
    } finally {
      server?.destroy();
    }

    return sortSoulseek(results);
  }

  /// Log in only (no search) to confirm the credentials — for the status check.
  Future<bool> verifyLogin(String user, String pass) async {
    Socket? server;
    try {
      server = await Socket.connect(_host, _port, timeout: const Duration(seconds: 8));
      final conn = _Conn(server);
      conn.send(_message(1, (_W()..str(user)..str(pass)..u32(160)..str(_md5hex(pass))..u32(17)).bytes()));
      final done = Completer<bool>();
      final sub = conn.messages.listen((payload) {
        final r = _R(payload);
        if (r.u32() == 1 && !done.isCompleted) done.complete(r.u8() != 0);
      }, onError: (_) {
        if (!done.isCompleted) done.complete(false);
      }, onDone: () {
        if (!done.isCompleted) done.complete(false);
      });
      final ok = await done.future.timeout(const Duration(seconds: 12), onTimeout: () => false);
      await sub.cancel();
      return ok;
    } catch (_) {
      return false;
    } finally {
      server?.destroy();
    }
  }

  Future<void> _collectPeer(
      String ip, int port, int token, int ticket, List<SoulseekFile> results, void Function() onBatch) async {
    Socket? peer;
    try {
      peer = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      final conn = _Conn(peer);
      conn.send(_initMessage(0, (_W()..u32(token)).bytes())); // PierceFirewall
      final done = Completer<void>();
      var count = 0;
      final sub = conn.messages.listen((payload) {
        count++;
        final code = _R(payload).u32();
        if (code == 9) {
          _parseResults(_zlib(Uint8List.sublistView(payload, 4)), ticket, results);
          onBatch(); // stream this peer's hits to the UI immediately
          if (!done.isCompleted) done.complete();
        } else if (count >= 10 && !done.isCompleted) {
          done.complete();
        }
      }, onError: (_) {}, onDone: () { if (!done.isCompleted) done.complete(); });
      await done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
      await sub.cancel();
    } catch (_) {} finally {
      peer?.destroy();
    }
  }

  void _parseResults(Uint8List data, int ticket, List<SoulseekFile> results) {
    final r = _R(data);
    final peerUser = r.str();
    if (r.u32() != ticket) return;
    final count = r.u32().clamp(0, 500);
    final files = <SoulseekFile>[];
    for (var i = 0; i < count; i++) {
      if (r.remaining < 5) break;
      r.u8(); // entry type
      final filename = r.str();
      final size = r.u64();
      r.str(); // legacy ext
      final numAttr = r.u32().clamp(0, 10);
      int? bitrate, dur;
      var vbr = false;
      for (var a = 0; a < numAttr; a++) {
        final t = r.u32();
        final v = r.u32();
        if (t == 0) {
          bitrate = v;
        } else if (t == 1) {
          dur = v;
        } else if (t == 2) {
          vbr = v != 0;
        }
      }
      files.add(SoulseekFile(username: peerUser, filename: filename, size: size, bitrate: bitrate, durationSec: dur, isVbr: vbr));
    }
    final freeSlots = r.remaining > 0 ? r.boolean() : false;
    final speed = r.remaining >= 4 ? r.u32() : 0;
    final queueLen = r.remaining >= 4 ? r.u32() : 0;
    for (final f in files) {
      results.add(f.copyWith(freeSlots: freeSlots, speed: speed, queueLength: queueLen));
    }
  }

  /// Download one file to [destFile]. Firewalled/relayed transfer, streams to disk.
  Future<SlskResult> download(String user, String pass, SoulseekFile file, File destFile, void Function(int, int) onProgress) async {
    Socket? server;
    Socket? peer;
    try {
      server = await Socket.connect(_host, _port, timeout: const Duration(seconds: 8));
      final sconn = _Conn(server);
      sconn.send(_message(1, (_W()..str(user)..str(pass)..u32(160)..str(_md5hex(pass))..u32(17)).bytes()));
      sconn.send(_message(2, (_W()..u32(0)).bytes()));
      sconn.send(_message(3, (_W()..str(file.username)).bytes())); // GetPeerAddress

      final addr = Completer<(String, int)>();
      final delivered = Completer<SlskResult>();
      final dlToken = _nextTicket();
      final fileSize = _Box(0);

      final ssub = sconn.messages.listen((payload) async {
        final r = _R(payload);
        final code = r.u32();
        if (code == 3) {
          r.str(); // username
          final ip = r.ip();
          final port = r.u32();
          if (!addr.isCompleted) addr.complete((ip, port));
        } else if (code == 18) {
          r.str();
          final type = r.str();
          final ip = r.ip();
          final port = r.u32();
          final ctpToken = r.u32();
          if (type == 'F' && ip != '0.0.0.0' && port > 0 && !delivered.isCompleted) {
            final ok = await _streamFile(ip, port, ctpToken, fileSize.v, destFile, onProgress);
            if (ok && !delivered.isCompleted) delivered.complete(SlskDone(destFile.path));
          }
        }
      }, onError: (_) {}, onDone: () {});

      final (ip, port) = await addr.future.timeout(const Duration(seconds: 10));
      if (ip == '0.0.0.0' || port == 0) return SlskFail('Uploader niet bereikbaar (firewalled)');

      peer = await Socket.connect(ip, port, timeout: const Duration(seconds: 8));
      final pconn = _Conn(peer);
      pconn.send(_initMessage(1, (_W()..str(user)..str('P')..u32(dlToken)).bytes())); // PeerInit "P"
      pconn.send(_message(43, (_W()..str(file.filename)).bytes())); // QueueUpload
      pconn.send(_message(40, (_W()..u32(0)..u32(dlToken)..str(file.filename)).bytes())); // TransferRequest
      onProgress(0, 0);

      String? deny;
      final psub = pconn.messages.listen((payload) {
        final r = _R(payload);
        final code = r.u32();
        if (code == 41) {
          r.u32();
          if (r.boolean()) {
            if (fileSize.v == 0) fileSize.v = r.u64();
          } else {
            deny = r.str();
          }
        } else if (code == 40) {
          r.u32();
          final tok = r.u32();
          r.str();
          if (r.remaining >= 8 && fileSize.v == 0) fileSize.v = r.u64();
          pconn.send(_message(41, (_W()..u32(tok)..u8(1)).bytes())); // accept
        }
      }, onError: (_) {}, onDone: () {});

      final result = await delivered.future.timeout(const Duration(seconds: 90), onTimeout: () {
        if (deny != null) {
          return deny!.toLowerCase().contains('queued')
              ? SlskFail('In wachtrij bij uploader')
              : SlskFail('Geweigerd: $deny');
        }
        return SlskFail('Geen reactie van uploader (slot bezet of offline)');
      });
      await ssub.cancel();
      await psub.cancel();
      return result;
    } catch (e) {
      return SlskFail(e.toString());
    } finally {
      server?.destroy();
      peer?.destroy();
    }
  }

  Future<bool> _streamFile(String ip, int port, int ctpToken, int total, File destFile, void Function(int, int) onProgress) async {
    Socket? f;
    try {
      f = await Socket.connect(ip, port, timeout: const Duration(seconds: 8));
      f.add(_initMessage(0, (_W()..u32(ctpToken)).bytes())); // PierceFirewall
      await destFile.parent.create(recursive: true);
      final sink = destFile.openWrite();
      var received = 0;
      var skipped = 0;
      var lastEmit = 0;
      final headerSent = _Box(0);
      await for (final chunk in f) {
        var data = chunk;
        if (skipped < 4) {
          final take = min(4 - skipped, data.length);
          skipped += take;
          data = Uint8List.sublistView(data, take);
          if (skipped == 4 && headerSent.v == 0) {
            headerSent.v = 1;
            f.add(Uint8List(8)); // offset = 0
          }
          if (data.isEmpty) continue;
        }
        sink.add(data);
        received += data.length;
        if (total > 0 && received >= total) break;
        if (received - lastEmit >= 1000000) {
          lastEmit = received;
          onProgress(received, total);
        }
      }
      await sink.close();
      final ok = received > 0 && (total == 0 || received >= total);
      if (ok) {
        onProgress(received, total > 0 ? total : received);
      } else {
        await destFile.delete().catchError((_) => destFile);
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      f?.destroy();
    }
  }
}

class _Box {
  int v;
  _Box(this.v);
}
