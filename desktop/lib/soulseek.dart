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

/// The uploader has us in its queue — not a failure: the download should WAIT and retry,
/// exactly like the native client's transfer list does.
class SlskQueued extends SlskResult {
  final int place; // position in the uploader's queue (0 = unknown)
  SlskQueued(this.place);
}

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

/// One INCOMING peer connection. It parses the init message itself rather than going through
/// [_Conn], because what follows the init decides the wire format: for a message connection the
/// rest is length-prefixed Soulseek messages, but for a file connection ('F') it is a raw byte
/// stream that must never be run through the message framer.
class _Inbound {
  final Socket sock;
  final SoulseekClient owner;
  final _buf = BytesBuilder();
  final _raw = StreamController<Uint8List>();
  late final StreamSubscription<Uint8List> _sub;
  Timer? _idle;
  // 0 = awaiting init, 1 = framed messages, 2 = raw file stream, 3 = dead.
  int _mode = 0;

  _Inbound(this.sock, this.owner) {
    _sub = sock.listen(_onData, onError: (_) => _drop(), onDone: _drop);
    _bump(const Duration(seconds: 30));
  }

  /// Raw bytes after the init message — the file stream. Only valid after [takeRaw].
  Stream<Uint8List> get raw => _raw.stream;
  void send(List<int> b) {
    if (_mode != 3) sock.add(b);
  }

  void destroy() => _drop();

  /// Switch this connection to raw mode: no more message framing, bytes go to [raw].
  /// Only called from init routing, so [_process] is on the stack and drains what's left.
  void takeRaw() {
    if (_mode == 3) return;
    _mode = 2;
    _idle?.cancel(); // the transfer runs its own stall watchdog
  }

  /// Claim this connection's messages instead of letting them fall through to the client's
  /// search-result handling. Deliberately NOT broadcast: the controller buffers, so a reply that
  /// arrives before the caller gets around to listening is queued rather than dropped.
  /// Must be called synchronously while routing, for the same reason.
  Stream<Uint8List> takeMessages() {
    _messages ??= StreamController<Uint8List>();
    return _messages!.stream;
  }

  StreamController<Uint8List>? _messages;

  void _bump(Duration d) {
    _idle?.cancel();
    _idle = Timer(d, _drop);
  }

  void _onData(Uint8List data) {
    if (_mode == 3) return;
    if (_mode == 2) {
      _raw.add(data);
      return;
    }
    _buf.add(data);
    final bytes = _buf.takeBytes();
    var off = 0;
    while (bytes.length - off >= 4) {
      final len = bytes[off] | (bytes[off + 1] << 8) | (bytes[off + 2] << 16) | (bytes[off + 3] << 24);
      if (len < 0 || bytes.length - off < 4 + len) break;
      final payload = Uint8List.sublistView(bytes, off + 4, off + 4 + len);
      off += 4 + len;
      if (_mode == 0) {
        _mode = 1;
        final wanted = _handleInit(payload); // may flip us to raw mode, or drop us outright
        if (_mode == 2) {
          // Everything after the init belongs to the file stream, unframed.
          if (off < bytes.length) _raw.add(bytes.sublist(off));
          return;
        }
        if (!wanted || _mode == 3) {
          _drop();
          return;
        }
        continue;
      }
      _bump(const Duration(seconds: 30));
      if (_messages != null && !_messages!.isClosed) {
        _messages!.add(payload);
      } else {
        owner._onFramed(payload);
      }
      if (_mode == 3) return;
    }
    _buf.clear();
    if (off < bytes.length) _buf.add(bytes.sublist(off));
  }

  bool _handleInit(Uint8List payload) {
    if (payload.isEmpty) return false;
    final r = _R(payload);
    final code = r.u8();
    if (code == 0) {
      if (r.remaining < 4) return false;
      return owner._routeInbound(this, 0, '', '', r.u32());
    }
    if (code == 1) {
      final user = r.str();
      final type = r.str();
      final token = r.remaining >= 4 ? r.u32() : 0;
      return owner._routeInbound(this, 1, user, type, token);
    }
    return false;
  }

  void _drop() {
    if (_mode == 3) return;
    _mode = 3;
    _idle?.cancel();
    _sub.cancel();
    if (!_raw.isClosed) _raw.close();
    if (_messages != null && !_messages!.isClosed) _messages!.close();
    sock.destroy();
  }
}

class SoulseekClient {
  static const _host = 'server.slsknet.org';
  static const _port = 2242;
  final _rng = Random();
  int _nextTicket() => 10000 + _rng.nextInt(900000);

  // ── Incoming peer connections ─────────────────────────────────────────────
  // Soulseek delivers a search result by having the PEER connect to the searcher. A peer that is
  // itself firewalled can't be reached by us either, so unless WE are reachable its results are
  // lost — measured: of 15 peers referred for one query only 4 were connectable. Listening on a
  // (router-forwarded) port is what lets those peers reach us, matching the native client.
  int listenPort = 0; // 0 = don't listen (set from settings)
  ServerSocket? _listener;
  int get boundPort => _listener?.port ?? 0;

  /// ticket → sink for results arriving on INCOMING connections.
  final Map<int, void Function(List<SoulseekFile>)> _searchSinks = {};

  /// token → handler for a peer we asked the SERVER to make call us back (ConnectToPeer). This
  /// is how you reach a FIREWALLED uploader: we can't dial them, so the server tells them to dial
  /// us, and they arrive here with PierceFirewall(token).
  final Map<int, void Function(_Inbound)> _pierceWaiters = {};

  /// username → handler for the FILE connection the uploader opens to us (PeerInit type 'F').
  /// This is the normal direction: the uploader always dials the downloader, so a firewalled
  /// uploader can only ever deliver if we are listening.
  final Map<String, void Function(_Inbound)> _fInbound = {};

  /// Bind the listening port once. Returns the port actually advertised (0 = not listening, e.g.
  /// the port is taken because the native client is running — then we simply behave as before).
  Future<int> ensureListening() async {
    if (_listener != null) return _listener!.port;
    if (listenPort <= 0) return 0;
    try {
      final s = await ServerSocket.bind(InternetAddress.anyIPv4, listenPort);
      _listener = s;
      s.listen(_onInbound, onError: (_) {}, cancelOnError: false);
      return s.port;
    } catch (_) {
      return 0; // port busy / blocked — fall back to the old firewalled behaviour
    }
  }

  void stopListening() {
    _listener?.close();
    _listener = null;
  }

  /// An incoming peer connection. The FIRST message is an init message (1-byte code):
  /// PeerInit(1) = username/type/token, PierceFirewall(0) = token. After that they're ordinary
  /// peer messages, and a 'P' (peer) connection is what carries FileSearchResponse (code 9).
  void _onInbound(Socket sock) => _Inbound(sock, this);

  /// Routes a fully-initialised incoming connection. Returns false if nobody wanted it.
  bool _routeInbound(_Inbound c, int initCode, String user, String type, int token) {
    if (initCode == 0) {
      // PierceFirewall — a peer the SERVER told to call us back, for a ConnectToPeer we sent.
      final p = _pierceWaiters.remove(token);
      if (p == null) return false;
      p(c);
      return true;
    }
    // PeerInit. 'F' = the uploader is opening the FILE connection to us; anything else ('P') is a
    // normal peer message connection, which is how search results arrive.
    if (type == 'F') {
      final f = _fInbound.remove(user);
      if (f == null) return false;
      f(c);
      return true;
    }
    return true; // keep framing: search results
  }

  void _onFramed(Uint8List payload) {
    if (payload.length < 4) return;
    final code = _R(payload).u32();
    if (code != 9) return; // only search responses are interesting on an inbound connection
    final (ticket, files) = _parseAny(_zlib(Uint8List.sublistView(payload, 4)));
    final sink = _searchSinks[ticket];
    if (sink != null && files.isNotEmpty) sink(files);
  }

  /// A download session that logs in ONCE and reuses that connection for every download in it
  /// (see [SlskSession]). Use one session per batch (a whole album, or a single track's peer
  /// fallback) so downloading N tracks costs ONE login, not one per peer attempt — Soulseek
  /// rate-limits repeated logins and blocks the account on a burst.
  SlskSession newSession(String user, String pass) => SlskSession(this, user, pass);

  // ── Circuit breaker ───────────────────────────────────────────────────────
  // If Soulseek refuses a login (the account is rate-limited/blocked), STOP touching Soulseek
  // entirely for a while. Without this, ordinary use — every album you open fires a background
  // search — keeps hammering a blocked account and keeps extending the block. Shared by search,
  // verify AND downloads because they all go through this one client instance.
  DateTime? _blockedUntil;

  /// True while we're backing off after a refused login — callers must NOT connect.
  bool get blocked => _blockedUntil != null && DateTime.now().isBefore(_blockedUntil!);

  /// How much of the back-off is left (null when not backing off) — for the UI.
  Duration? get blockedFor => blocked ? _blockedUntil!.difference(DateTime.now()) : null;

  void noteLoginRefused() => _blockedUntil = DateTime.now().add(const Duration(minutes: 30));
  void noteLoginOk() => _blockedUntil = null;

  /// Search Soulseek covering all [queries] (the raw query + its "*"-variant) on ONE
  /// short-lived connection with a SINGLE login — instead of one login per variant, which
  /// (during heavy use) made Soulseek temporarily block the account for too many logins.
  /// Short-lived on purpose: a persistent connection would fight the download connections
  /// (Soulseek allows only one connection per username). [onPartial] streams merged hits.
  Future<List<SoulseekFile>> searchMulti(String user, String pass, List<String> queries,
      {void Function(List<SoulseekFile>)? onPartial}) async {
    if (blocked) return const []; // backing off after a refused login — don't touch the server
    final tickets = <int>{};
    final byTicket = <int, String>{};
    for (final q in queries) {
      final t = _nextTicket();
      tickets.add(t);
      byTicket[t] = q;
    }
    final merged = <String, SoulseekFile>{}; // username|filename → file (dedup across variants)
    void addFiles(List<SoulseekFile> files) {
      for (final f in files) {
        merged['${f.username}|${f.filename}'] = f;
      }
      if (onPartial != null) onPartial(sortSoulseek(merged.values));
    }

    // Accept results from peers that connect TO us (the firewalled ones we can't reach outbound).
    final advertise = await ensureListening();
    for (final t in tickets) {
      _searchSinks[t] = addFiles;
    }

    final peerJobs = <Future<void>>[];
    Socket? server;
    try {
      server = await Socket.connect(_host, _port, timeout: const Duration(seconds: 8));
      final conn = _Conn(server);
      final done = Completer<void>();
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      final sub = conn.messages.listen((payload) {
        final r = _R(payload);
        final code = r.u32();
        if (code == 1) {
          if (r.u8() == 0) {
            noteLoginRefused(); // back off — stop hammering a blocked account
            if (!done.isCompleted) done.completeError('Soulseek-login geweigerd');
            return;
          }
          noteLoginOk();
          // Advertise our real listening port when we have one: peers we can't dial out to will
          // then connect to US with their results (that's how the native client sees them all).
          conn.send(_message(2, (_W()..u32(advertise)).bytes())); // SetWaitPort
          for (final t in byTicket.keys) {
            conn.send(_message(26, (_W()..u32(t)..str(byTicket[t]!)).bytes())); // FileSearch
          }
        } else if (code == 18) {
          r.str(); // peer user
          final type = r.str();
          final ip = r.ip();
          final port = r.u32();
          final token = r.u32();
          if (type == 'P' && ip != '0.0.0.0' && port > 0 && peerJobs.length < 100) {
            peerJobs.add(_collectPeer(ip, port, token, tickets, addFiles));
          }
        }
      }, onError: (_) {}, onDone: () { if (!done.isCompleted) done.complete(); });

      conn.send(_message(1, (_W()..str(user)..str(pass)..u32(160)..str(_md5hex(pass))..u32(17)).bytes()));
      final poll = Timer.periodic(const Duration(milliseconds: 300), (t) {
        if (DateTime.now().isAfter(deadline) || merged.length >= 400) {
          t.cancel();
          if (!done.isCompleted) done.complete();
        }
      });
      await done.future.timeout(const Duration(seconds: 12), onTimeout: () {});
      poll.cancel();
      await sub.cancel();
      await Future.wait(peerJobs).timeout(const Duration(seconds: 3)).catchError((_) => <void>[]);
    } catch (e) {
      if (merged.isEmpty) rethrow;
    } finally {
      for (final t in tickets) {
        _searchSinks.remove(t);
      }
      server?.destroy();
    }
    return sortSoulseek(merged.values);
  }

  /// Log in only (no search) to confirm the credentials — for the status check.
  Future<bool> verifyLogin(String user, String pass) async {
    if (blocked) return false; // backing off after a refused login — don't touch the server
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
      if (ok) {
        noteLoginOk();
      } else {
        noteLoginRefused();
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      server?.destroy();
    }
  }

  Future<void> _collectPeer(
      String ip, int port, int token, Set<int> validTickets, void Function(List<SoulseekFile>) onBatch) async {
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
          final files = _parseResults(_zlib(Uint8List.sublistView(payload, 4)), validTickets);
          if (files.isNotEmpty) onBatch(files);
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

  /// Parse a peer's FileSearchResponse; returns its files if the ticket is one of ours.
  List<SoulseekFile> _parseResults(Uint8List data, Set<int> validTickets) {
    final (ticket, files) = _parseAny(data);
    return validTickets.contains(ticket) ? files : const [];
  }

  /// Parse a FileSearchResponse and return its ticket + files (no filtering) — incoming
  /// connections need the ticket to know WHICH search the results belong to.
  (int, List<SoulseekFile>) _parseAny(Uint8List data) {
    final r = _R(data);
    final peerUser = r.str();
    final ticket = r.remaining >= 4 ? r.u32() : -1;
    final count = r.remaining >= 4 ? r.u32().clamp(0, 500) : 0;
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
    return (
      ticket,
      [for (final f in files) f.copyWith(freeSlots: freeSlots, speed: speed, queueLength: queueLen)]
    );
  }

  // Single-file download now lives in [SlskSession.download] — it reuses ONE login per batch
  // instead of logging in per call (which burst-tripped Soulseek's login block). [_streamFile]
  // (the actual byte pump) stays here and is shared by the session.
  Future<bool> _streamFile(String ip, int port, int ctpToken, int total, File destFile, void Function(int, int) onProgress) async {
    Socket? f;
    try {
      f = await Socket.connect(ip, port, timeout: const Duration(seconds: 8));
      final sock = f;
      f.add(_initMessage(0, (_W()..u32(ctpToken)).bytes())); // PierceFirewall
      return await _pump(f, f.add, () => sock.destroy(), total, destFile, onProgress);
    } catch (_) {
      return false;
    } finally {
      f?.destroy();
    }
  }

  /// The actual byte pump of a Soulseek file transfer, independent of HOW the connection was made:
  /// we may have dialled the uploader (see [_streamFile]) or — for a firewalled uploader — it may
  /// have dialled US and arrived on the listening port. Both hand the same raw stream in here.
  /// Wire format from this point: [u32 ticket] echoed by the uploader, then we answer with a
  /// [u64 offset], then the file bytes flow.
  Future<bool> _pump(
    Stream<Uint8List> input,
    void Function(List<int>) send,
    void Function() abort,
    int total,
    File destFile,
    void Function(int, int) onProgress,
  ) async {
    Timer? stall;
    IOSink? sink;
    try {
      await destFile.parent.create(recursive: true);
      sink = destFile.openWrite();
      var received = 0;
      var skipped = 0;
      var lastEmit = 0;
      final headerSent = _Box(0);
      // Stall watchdog: keep going as long as bytes keep arriving (a slow-but-working peer must
      // be allowed to finish a big FLAC); only abort if the transfer goes silent for 30s. Closing
      // the socket ends the await-for below. This replaces relying on a fixed total-time cap.
      void bump() {
        stall?.cancel();
        stall = Timer(const Duration(seconds: 30), abort);
      }
      bump();
      await for (final chunk in input) {
        bump();
        var data = chunk;
        if (skipped < 4) {
          final take = min(4 - skipped, data.length);
          skipped += take;
          data = Uint8List.sublistView(data, take);
          if (skipped == 4 && headerSent.v == 0) {
            headerSent.v = 1;
            send(Uint8List(8)); // offset = 0
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
      stall?.cancel();
      await sink.close();
      sink = null;
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
      stall?.cancel();
      // An abort mid-stream must still release the file handle, or the retry's openWrite() on
      // Windows hits a sharing violation and every following attempt "fails" for the wrong reason.
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
        await destFile.delete().catchError((_) => destFile);
      }
    }
  }
}

class _Box {
  int v;
  _Box(this.v);
}

/// A reusable, logged-in Soulseek SERVER connection for a batch of downloads.
///
/// Soulseek allows only ONE login per username and rate-limits/blocks repeated logins. The
/// old per-file `download()` logged in fresh EVERY call, and the peer-fallback tried up to 5
/// peers per track → a whole album could fire dozens of logins in a minute and trip the block.
/// A session logs in ONCE and routes every GetPeerAddress (code 3) + firewalled ConnectToPeer
/// (code 18 'F') through the same connection.
///
/// Downloads run CONCURRENTLY on that single login (like the native client): a file transfer is a
/// separate peer socket and costs no login, so many can run at once. Server replies are routed to
/// the right download by PEER USERNAME (both code 3 and code 18 carry it as their first field).
/// Transfers from the SAME peer are serialised — a peer grants one upload slot at a time, and it
/// keeps the username→waiter routing unambiguous. Call [close] to free Soulseek's connection slot.
class SlskSession {
  final SoulseekClient client;
  final String user, pass;
  SlskSession(this.client, this.user, this.pass);

  Socket? _server;
  _Conn? _conn;
  StreamSubscription<Uint8List>? _sub;
  int _loginTries = 0; // consecutive failed logins — capped so a blocked account isn't hammered
  DateTime? _lastLoginAttempt; // throttle re-logins (guards a kick/re-login storm)
  Future<bool>? _ensuring; // in-flight login, shared by concurrent downloads (never 2 logins)

  // Per-peer routing for the concurrently-active downloads.
  final Map<String, Completer<(String, int)>> _addrWaiters = {};
  final Map<String, void Function(String ip, int port, int token)> _fWaiters = {};
  final Map<String, Future<void>> _peerLocks = {}; // one transfer at a time per peer

  bool get _alive => _conn != null;

  /// Connect + log in once; reuse on later calls. Reconnects only if the socket dropped.
  /// Two guards against a login burst tripping the block: (a) at most 2 CONSECUTIVE failed logins
  /// per session; (b) at most one login attempt per 10s (so a kicked/oscillating connection —
  /// e.g. the native client is also online — can't storm re-logins).
  /// Concurrency-safe: if several downloads start at once they all await the SAME login attempt
  /// (never two logins). Returns true once the shared connection is up.
  Future<bool> _ensure() {
    if (_alive) return Future.value(true);
    return _ensuring ??= _login().whenComplete(() => _ensuring = null);
  }

  Future<bool> _login() async {
    if (_alive) return true;
    if (client.blocked) return false; // global back-off after a refused login
    if (_loginTries >= 2) return false;
    final now = DateTime.now();
    if (_lastLoginAttempt != null && now.difference(_lastLoginAttempt!) < const Duration(seconds: 10)) {
      return false;
    }
    _lastLoginAttempt = now;
    _loginTries++;
    try {
      final s = await Socket.connect(SoulseekClient._host, SoulseekClient._port, timeout: const Duration(seconds: 8));
      _server = s; // own the socket NOW so _drop() closes it on ANY failure path (no leak)
      final c = _Conn(s);
      final login = Completer<bool>();
      _sub = c.messages.listen((payload) {
        final r = _R(payload);
        final code = r.u32();
        if (code == 1) {
          if (!login.isCompleted) login.complete(r.u8() != 0);
        } else if (code == 3) {
          // GetPeerAddress reply — route to the download waiting on THIS peer.
          final uname = r.str();
          final ip = r.ip();
          final port = r.u32();
          final w = _addrWaiters[uname];
          if (w != null && !w.isCompleted) w.complete((ip, port));
        } else if (code == 18) {
          // ConnectToPeer — the username is the first field, so route 'F' to that peer's download.
          final uname = r.str();
          final type = r.str();
          final ip = r.ip();
          final port = r.u32();
          final tok = r.u32();
          if (type == 'F' && ip != '0.0.0.0' && port > 0) _fWaiters[uname]?.call(ip, port, tok);
        }
      }, onError: (_) => _drop(), onDone: _drop);
      c.send(_message(1, (_W()..str(user)..str(pass)..u32(160)..str(_md5hex(pass))..u32(17)).bytes()));
      final ok = await login.future.timeout(const Duration(seconds: 12), onTimeout: () => false);
      if (!ok) {
        client.noteLoginRefused(); // trip the global breaker — stop all Soulseek traffic for a while
        _drop();
        return false;
      }
      client.noteLoginOk();
      c.send(_message(2, (_W()..u32(client.boundPort)).bytes())); // SetWaitPort (real port if listening)
      _conn = c;
      _loginTries = 0; // healthy login → reset the consecutive-failure counter
      return true;
    } catch (_) {
      _drop();
      return false;
    }
  }

  void _drop() {
    _sub?.cancel();
    _sub = null;
    _server?.destroy();
    _server = null;
    _conn = null;
  }

  /// Close the session's server connection (frees Soulseek's single connection slot).
  void close() => _drop();

  /// Download one file over the shared, already-logged-in connection. Safe to call CONCURRENTLY for
  /// different peers — replies are routed by username. Two downloads from the SAME peer are
  /// serialised (a peer grants one slot at a time, and it keeps routing unambiguous).
  Future<SlskResult> download(SoulseekFile file, File destFile, void Function(int, int) onProgress,
      {void Function(SlskQueued)? onStatus, bool waitInQueue = true}) async {
    if (!await _ensure()) return SlskFail('Kan niet inloggen bij Soulseek');
    // Queue behind any transfer already running for this same peer.
    final prev = _peerLocks[file.username];
    final mine = Completer<void>();
    _peerLocks[file.username] = mine.future;
    if (prev != null) {
      try {
        await prev;
      } catch (_) {}
    }
    try {
      return await _transfer(file, destFile, onProgress, onStatus: onStatus, waitInQueue: waitInQueue);
    } finally {
      mine.complete();
      if (identical(_peerLocks[file.username], mine.future)) _peerLocks.remove(file.username);
    }
  }

  /// Ask the SERVER to tell [username] to call US back. This is the only way to reach an uploader
  /// that is itself firewalled: we can't dial them, but they can dial us — provided we are
  /// listening on an advertised port. They arrive with PierceFirewall(token).
  Future<(_Inbound, Stream<Uint8List>)?> _reverseConnect(String username) async {
    if (await client.ensureListening() == 0) return null; // not reachable ourselves → no point
    final token = client._nextTicket();
    final got = Completer<(_Inbound, Stream<Uint8List>)>();
    client._pierceWaiters[token] = (c) {
      // takeMessages() synchronously, before the connection's read loop moves on: anything the
      // peer already sent must land in our queue, not in the search-result sink.
      if (!got.isCompleted) got.complete((c, c.takeMessages()));
    };
    try {
      _conn!.send(_message(18, (_W()..u32(token)..str(username)..str('P')).bytes()));
      return await got.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      return null;
    } finally {
      client._pierceWaiters.remove(token);
    }
  }

  /// [waitInQueue] false = a "queued" reply ends the attempt at once (so the caller can sweep the
  /// other peers first); true = hold the connection and wait for a slot, keeping our queue place.
  Future<SlskResult> _transfer(SoulseekFile file, File destFile, void Function(int, int) onProgress,
      {void Function(SlskQueued)? onStatus, bool waitInQueue = true}) async {
    if (!await _ensure()) return SlskFail('Kan niet inloggen bij Soulseek');
    // The uploader opens the file connection TO us, so we must be listening before we ask for the
    // file — not only after a search happened to bind the port earlier in this process.
    await client.ensureListening();
    Socket? peer;
    _Inbound? viaServer;
    _Inbound? fileConn;
    try {
      // GetPeerAddress on the shared connection, routed back to us by username.
      final addr = Completer<(String, int)>();
      _addrWaiters[file.username] = addr;
      _conn!.send(_message(3, (_W()..str(file.username)).bytes()));
      (String, int) peerAddr = ('0.0.0.0', 0);
      try {
        peerAddr = await addr.future.timeout(const Duration(seconds: 10));
      } catch (_) {
        // no address — the reverse path below is still worth a try
      } finally {
        _addrWaiters.remove(file.username);
      }
      final (ip, port) = peerAddr;

      final delivered = Completer<SlskResult>();
      final dlToken = client._nextTicket();
      final fileSize = _Box(0);
      var fStarted = false;
      String? deny;

      Future<void> runPump(Stream<Uint8List> input, void Function(List<int>) send, void Function() abort) async {
        final ok = await client._pump(input, send, abort, fileSize.v, destFile, onProgress);
        if (!delivered.isCompleted) {
          delivered.complete(ok ? SlskDone(destFile.path) : SlskFail('Overdracht afgebroken'));
        }
      }

      // (1) The uploader opens the FILE connection to US — the normal direction, and the ONLY one
      // that works when the uploader is firewalled. Reaches us because we advertise a listen port.
      client._fInbound[file.username] = (c) {
        if (fStarted || delivered.isCompleted) {
          c.destroy();
          return;
        }
        fStarted = true;
        fileConn = c; // so the finally below always closes it, success or not
        c.takeRaw();
        runPump(c.raw, c.send, c.destroy);
      };

      // (2) Firewalled ConnectToPeer 'F' for THIS peer arrives on the shared connection → we dial.
      // Guard on fStarted too: a duplicate/late 'F' must not launch a SECOND pump writing the same
      // dest file concurrently.
      _fWaiters[file.username] = (fip, fport, ftok) async {
        if (fStarted || delivered.isCompleted) return;
        fStarted = true;
        final ok = await client._streamFile(fip, fport, ftok, fileSize.v, destFile, onProgress);
        if (!delivered.isCompleted) {
          delivered.complete(ok ? SlskDone(destFile.path) : SlskFail('Overdracht afgebroken'));
        }
      };

      // Message connection: dial the uploader, and if that fails have the server flip it around.
      void Function(Uint8List) psend;
      Stream<Uint8List> pmsgs;
      if (ip != '0.0.0.0' && port > 0) {
        try {
          peer = await Socket.connect(ip, port, timeout: const Duration(seconds: 8));
        } catch (_) {
          peer = null;
        }
      }
      if (peer != null) {
        final pconn = _Conn(peer);
        psend = pconn.send;
        pmsgs = pconn.messages;
        pconn.send(_initMessage(1, (_W()..str(user)..str('P')..u32(dlToken)).bytes())); // PeerInit "P"
      } else {
        final rev = await _reverseConnect(file.username);
        if (rev == null) return SlskFail('Uploader niet bereikbaar (firewall)');
        viaServer = rev.$1;
        psend = (b) => rev.$1.send(b);
        pmsgs = rev.$2;
        // No PeerInit here: the peer initiated, the handshake is already done.
      }
      psend(_message(43, (_W()..str(file.filename)).bytes())); // QueueUpload
      psend(_message(40, (_W()..u32(0)..u32(dlToken)..str(file.filename)).bytes())); // TransferRequest
      onProgress(0, 0);

      // "Queued" is NOT a failure — the uploader has accepted us and will start when a slot frees.
      // The native client simply keeps the row waiting, so we do too: hold the connection (which
      // holds our queue position; reconnecting would send us to the back) and report the wait.
      var queued = false;
      var place = 0;
      Timer? poll;
      final startTimer = Timer(const Duration(seconds: 20), () {
        if (fStarted || delivered.isCompleted || queued) return;
        delivered.complete(SlskFail(deny != null ? 'Geweigerd: $deny' : 'Geen reactie (slot bezet of offline)'));
      });

      void noteQueued() {
        if (queued) return;
        queued = true;
        if (!waitInQueue) {
          // The caller would rather try another peer than sit in this one's queue. Report it and
          // let go immediately — a free peer beats a good place in a busy peer's line.
          if (!delivered.isCompleted) delivered.complete(SlskQueued(place));
          return;
        }
        onStatus?.call(SlskQueued(0));
        // Ask for our position now and then, so the UI can show it moving.
        poll = Timer.periodic(const Duration(seconds: 30), (_) {
          if (fStarted || delivered.isCompleted) return;
          try {
            psend(_message(51, (_W()..str(file.filename)).bytes())); // PlaceInQueueRequest
          } catch (_) {/* peer hung up; onDone below settles the transfer */}
        });
      }

      final psub = pmsgs.listen((payload) {
        final r = _R(payload);
        final code = r.u32();
        if (code == 41) {
          r.u32();
          if (r.boolean()) {
            if (fileSize.v == 0) fileSize.v = r.u64();
          } else {
            deny = r.str();
            if (deny!.toLowerCase().contains('queued')) noteQueued();
          }
        } else if (code == 40) {
          r.u32();
          final tok = r.u32();
          r.str();
          if (r.remaining >= 8 && fileSize.v == 0) fileSize.v = r.u64();
          psend(_message(41, (_W()..u32(tok)..u8(1)).bytes())); // accept
        } else if (code == 44) {
          // PlaceInQueueResponse(filename, place)
          r.str();
          if (r.remaining >= 4) {
            place = r.u32();
            if (queued && !fStarted) onStatus?.call(SlskQueued(place));
          }
        }
      }, onError: (_) {}, onDone: () {
        // The uploader hung up before starting: if we were queued, that's a retryable wait.
        if (!fStarted && !delivered.isCompleted && queued) delivered.complete(SlskQueued(place));
      });

      // A queued transfer may legitimately take a long time; 30 min matches leaving the native
      // client open. Past that we hand back SlskQueued so the manager retries rather than fails.
      final result = await delivered.future.timeout(const Duration(seconds: 1800), onTimeout: () {
        // fStarted means bytes were already flowing, so this is a stalled transfer, not a wait.
        if (queued && !fStarted) return SlskQueued(place);
        if (deny != null) return SlskFail('Geweigerd: $deny');
        return SlskFail('Geen reactie van uploader (slot bezet of offline)');
      });
      startTimer.cancel();
      poll?.cancel();
      await psub.cancel();
      return result;
    } catch (_) {
      return SlskFail('Verbinding mislukt');
    } finally {
      _fWaiters.remove(file.username);
      client._fInbound.remove(file.username);
      peer?.destroy();
      viaServer?.destroy();
      // Also on the paths that return while a pump is still running (timeout / throw): tearing the
      // socket down ends that pump, so it can never keep writing while the next peer is tried.
      fileConn?.destroy();
    }
  }
}
