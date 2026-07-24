import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'models.dart';
import 'paths.dart';

enum RepeatMode { off, all, one }

/// One item in a Radio / Smart-Shuffle queue: a local library track (plays
/// instantly) or an online recommendation resolved to a stream URL on demand.
class RadioItem {
  final String artist;
  final String title;
  final Track? local; // non-null => in the library
  String? url; // resolved online stream URL (cached after first resolve)
  bool failed = false;
  Future<String?>? pending; // in-flight resolve, so prefetch + open share one call
  RadioItem({required this.artist, required this.title, this.local});
  bool get isLocal => local != null;
}

/// The little of the player that the lockscreen needs. Named here, next to the thing that
/// implements it, so the compiler checks the two agree — and so what publishes to Control Center
/// can be exercised without libmpv, which cannot load in a test at all.
abstract interface class NowPlayingSource implements Listenable {
  Track? get current;
  bool get playing;
  Duration get position;
  Duration get duration;
  Uint8List? get currentCover;
  void playPause();
  Future<void> next();
  Future<void> prev();
  void seek(Duration d);
}

/// Native (libmpv) player with a queue, shuffle, repeat and a Radio mode.
class PlayerStore extends ChangeNotifier implements NowPlayingSource {
  final Player _player = Player();
  List<Track> _original = [];
  List<Track> _order = [];
  int _index = -1;

  // Radio / Smart Shuffle
  List<RadioItem> _radio = [];
  int _radioIndex = -1;
  int _radioGen = 0; // bumped on every (re)open so a stale async open aborts
  bool radioMode = false;
  String radioStatus = '';
  Future<String?> Function(String artist, String title)? resolver;
  Future<List<RadioItem>> Function()? radioExtend; // fetch more items to keep radio endless
  bool _extending = false;
  int _radioSession = 0; // bumped per playRadio() so a stale extend can't pollute a new radio
  List<RadioItem> get radioQueue => _radio;
  int get radioIndex => _radioIndex;

  @override
  Uint8List? currentCover;
  bool shuffle = false;
  RepeatMode repeat = RepeatMode.off;

  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = Duration.zero;

  /// Resolves an album cover for a track (set by main to LibraryStore.coverForTrack)
  /// so the flat Tracks queue shows the right cover per song.
  Uint8List? Function(Track)? coverResolver;

  /// Last step before a path is handed to libmpv. Identity on the machine that owns the music; on
  /// a Mac or an iPad it turns a library path into a stream URL carrying the pairing token.
  ///
  /// It happens HERE, and not in the stored path, because the path is the identity key for
  /// favourites, playlists and resume: baking a token into it would break all three the moment you
  /// paired again, and would write the key for your library into a plain file on disk.
  String Function(String path) mediaResolver = (p) => p;

  /// Where we are, for the other devices. Set by main to the LAN sharing store, so pausing here
  /// and carrying on from the iPad works in both directions. Called on the same throttle as the
  /// local resume file — every few seconds, and always on pause or a track change.
  void Function(Track track, Duration position, bool playing, List<Track> queue, int index)?
      onProgress;

  /// A track started playing — feeds the shared play counts and "recently played".
  void Function(Track track)? onPlayed;

  /// The queue as it will actually play, shuffle applied.
  List<Track> get queueTracks => List.unmodifiable(_order);

  // Resume: persist the library queue + position so the app reopens where you left off.
  bool _resumable = false;
  bool _restoring = false; // block saves while restore() opens+seeks (position blips to 0)
  DateTime _lastPosSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool resumedPaused = false; // true right after a startup restore (awaiting the user's play)

  String get _appDir => appDir;

  File get _queueFile => File('$_appDir${Platform.pathSeparator}resume_queue.json');
  File get _posFile => File('$_appDir${Platform.pathSeparator}resume_pos.json');

  @override
  Track? get current {
    if (radioMode) {
      if (_radioIndex >= 0 && _radioIndex < _radio.length) {
        final it = _radio[_radioIndex];
        return it.local ?? Track(path: it.url ?? '', title: it.title, artist: it.artist, album: '');
      }
      return null;
    }
    return (_index >= 0 && _index < _order.length) ? _order[_index] : null;
  }

  bool get hasNext => radioMode
      ? _radioIndex < _radio.length - 1
      : (_index < _order.length - 1 || (repeat == RepeatMode.all && _order.isNotEmpty));
  bool get hasPrev => radioMode ? _radioIndex > 0 : _index > 0;

  PlayerStore() {
    _player.stream.playing.listen((p) {
      playing = p;
      if (p) resumedPaused = false;
      if (!p) _saveProgress(force: true); // capture the spot on pause
      notifyListeners();
    });
    _player.stream.position.listen((p) {
      position = p;
      _saveProgress(); // throttled
      notifyListeners();
    });
    _player.stream.duration.listen((d) {
      duration = d;
      notifyListeners();
    });
    _player.stream.completed.listen((done) {
      if (done) _onCompleted();
    });
  }

  void _onCompleted() {
    if (repeat == RepeatMode.one) {
      radioMode ? _openRadioCurrent() : _openCurrent();
    } else {
      next();
    }
  }

  Future<void> playQueue(List<Track> tracks, int index, {Uint8List? cover}) async {
    radioMode = false;
    _resumable = true;
    resumedPaused = false;
    currentCover = cover;
    _original = List.of(tracks);
    _rebuildOrder(start: (index >= 0 && index < _original.length) ? _original[index] : null);
    await _openCurrent();
    _saveQueue();
  }

  /// Shuffle the whole library (or any list): every track plays exactly once (repeat
  /// off), starting from a random one. Scales to tens of thousands of tracks.
  Future<void> shuffleAll(List<Track> tracks) async {
    radioMode = false;
    _resumable = true;
    resumedPaused = false;
    shuffle = true;
    currentCover = null;
    _original = List.of(tracks);
    _order = List.of(_original)..shuffle();
    _index = _order.isEmpty ? -1 : 0;
    await _openCurrent();
    _saveQueue();
  }

  /// Play a remote URL (e.g. a resolved TorBox stream) as a one-item queue.
  Future<void> playUrl(String url, {required String title, required String artist}) async {
    radioMode = false;
    _resumable = false;
    currentCover = null;
    _original = [Track(path: url, title: title, artist: artist, album: '')];
    _order = List.of(_original);
    _index = 0;
    await _openCurrent();
  }

  /// Start a Radio / Smart-Shuffle queue of mixed local + online items.
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async {
    radioMode = true;
    _resumable = false;
    _radioSession++; // invalidate any in-flight extend from a previous radio
    _extending = false;
    currentCover = null;
    _radio = items;
    _radioIndex = items.isEmpty ? -1 : start.clamp(0, items.length - 1);
    await _openRadioCurrent();
  }

  /// Resolve an item's URL, sharing a single in-flight call between the foreground
  /// open and the background prefetch so they never race a second resolver.
  Future<String?> _resolveItem(RadioItem it) {
    if (it.url != null) return Future.value(it.url);
    if (it.failed) return Future.value(null);
    return it.pending ??= () async {
      final url = await resolver?.call(it.artist, it.title);
      if (url != null) {
        it.url = url;
      } else {
        it.failed = true;
      }
      it.pending = null;
      return it.url;
    }();
  }

  Future<void> _openRadioCurrent() async {
    final gen = ++_radioGen; // any earlier in-flight open is now stale
    while (_radioIndex >= 0 && _radioIndex < _radio.length) {
      final it = _radio[_radioIndex];
      if (it.url == null && !it.failed && !it.isLocal) {
        radioStatus = 'Bron zoeken: ${it.artist} — ${it.title}…';
        notifyListeners();
        await _resolveItem(it);
        if (gen != _radioGen) return; // superseded by a newer next()/prev()
      }
      final path = it.isLocal ? it.local!.path : it.url;
      if (path != null) {
        radioStatus = '';
        currentCover = it.isLocal ? coverResolver?.call(it.local!) : null;
        notifyListeners();
        await _player.open(Media(mediaResolver(path)), play: true);
        if (gen != _radioGen) return; // superseded while opening
        _prefetchNext();
        _maybeExtend();
        return;
      }
      if (_radioIndex >= _radio.length - 1) break; // don't overrun the end
      _radioIndex++; // couldn't source this one — skip forward
    }
    _radioIndex = _radio.isEmpty ? -1 : _radioIndex.clamp(0, _radio.length - 1);
    radioStatus = 'Radio klaar';
    notifyListeners();
    _maybeExtend();
  }

  /// Warm the next couple of online items so skipping ahead is snappy (shares the call).
  void _prefetchNext() {
    for (var i = 1; i <= 2; i++) {
      final ni = _radioIndex + i;
      if (ni >= _radio.length) break;
      final it = _radio[ni];
      if (!it.isLocal && it.url == null && !it.failed) _resolveItem(it);
    }
  }

  /// Keep the radio endless: near the tail, fetch and append more recommendations.
  void _maybeExtend() {
    if (radioExtend == null || _extending || _radioIndex < _radio.length - 3) return;
    _extending = true;
    final session = _radioSession; // tie this extend to the current radio
    radioExtend!().then((more) {
      if (session != _radioSession) return; // a newer radio started; drop this batch
      if (radioMode && more.isNotEmpty) _radio.addAll(more);
      _extending = false;
      notifyListeners();
    }).catchError((_) {
      if (session == _radioSession) _extending = false;
    });
  }

  void _rebuildOrder({Track? start}) {
    final anchor = start ?? current;
    if (shuffle && _original.isNotEmpty) {
      final rest = List.of(_original);
      if (anchor != null) rest.removeWhere((t) => t.path == anchor.path);
      rest.shuffle();
      _order = [if (anchor != null) anchor, ...rest];
      _index = 0;
    } else {
      _order = List.of(_original);
      _index = anchor == null ? 0 : _order.indexWhere((t) => t.path == anchor.path).clamp(0, _order.length - 1);
    }
  }

  /// Ask again what the playing track's cover is.
  ///
  /// [currentCover] is otherwise a snapshot taken when a track opens, so correcting a sleeve while
  /// it plays left this holding the old bytes — and they are what the mini bar, the backdrop and
  /// the tap-to-zoom all read. The album page showed the new sleeve, the zoom showed the old one,
  /// on the same screen.
  ///
  /// A resolver that answers null is not an answer: the album is mid-regroup and the cover it will
  /// have is not known yet. Keeping what we have beats blanking the bar.
  void refreshCover() {
    final t = current;
    if (t == null || coverResolver == null) return;
    final fresh = coverResolver!(t);
    if (fresh == null || identical(fresh, currentCover)) return;
    currentCover = fresh;
    notifyListeners();
  }

  Future<void> _openCurrent() async {
    final t = current;
    if (t == null) return;
    if (coverResolver != null) currentCover = coverResolver!(t);
    await _player.open(Media(mediaResolver(t.path)), play: true);
    _saveProgress(force: true); // track changed → persist the new spot
    onPlayed?.call(t);
    notifyListeners();
  }

  @override
  void playPause() => _player.playOrPause();

  @override
  Future<void> next() async {
    if (radioMode) {
      if (_radioIndex < _radio.length - 1) {
        _radioIndex++;
        await _openRadioCurrent();
      }
      return;
    }
    if (_index < _order.length - 1) {
      _index++;
      await _openCurrent();
    } else if (repeat == RepeatMode.all && _order.isNotEmpty) {
      _index = 0;
      await _openCurrent();
    }
  }

  @override
  Future<void> prev() async {
    if (position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    if (radioMode) {
      // Step back to the previous item that's playable or still resolvable
      // (skip ones already known to have failed to source).
      var i = _radioIndex - 1;
      while (i >= 0 && _radio[i].failed && !_radio[i].isLocal && _radio[i].url == null) {
        i--;
      }
      if (i >= 0) {
        _radioIndex = i;
        await _openRadioCurrent();
      }
      return;
    }
    if (_index > 0) {
      _index--;
      await _openCurrent();
    }
  }

  @override
  void seek(Duration d) => _player.seek(d);
  void setVolume(double v) => _player.setVolume(v);

  void toggleShuffle() {
    shuffle = !shuffle;
    if (_original.isNotEmpty) _rebuildOrder();
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = RepeatMode.values[(repeat.index + 1) % RepeatMode.values.length];
    notifyListeners();
  }

  // ── Resume (persist the library queue + position) ──────────────────────────
  Future<void> _saveQueue() async {
    if (!_resumable) return;
    try {
      await Directory(_appDir).create(recursive: true);
      await _queueFile.writeAsString(jsonEncode({
        'order': _order.map((t) => t.path).toList(),
        'shuffle': shuffle,
        'repeat': repeat.index,
      }));
    } catch (_) {}
  }

  Future<void> _saveProgress({bool force = false}) async {
    if (!_resumable || _restoring) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastPosSave).inSeconds < 5) return; // throttle
    _lastPosSave = now;
    final t = current;
    if (t == null) return;
    onProgress?.call(t, position, playing, _order, _index);
    try {
      await Directory(_appDir).create(recursive: true);
      await _posFile.writeAsString(jsonEncode({
        'index': _index,
        'positionMs': position.inMilliseconds,
        'path': t.path,
      }));
    } catch (_) {}
  }

  /// On startup, reopen the last library queue at the saved song + position — PAUSED,
  /// so nothing blasts out; the player bar shows it and the user presses play to resume.
  Future<void> restore(Track? Function(String path) resolveTrack) async {
    _restoring = true;
    try {
      if (!await _queueFile.exists()) return;
      final q = jsonDecode(await _queueFile.readAsString()) as Map<String, dynamic>;
      final paths = ((q['order'] as List?) ?? const []).cast<String>();
      final tracks = paths.map(resolveTrack).whereType<Track>().toList();
      if (tracks.isEmpty) return;
      shuffle = q['shuffle'] == true;
      repeat = RepeatMode.values[((q['repeat'] as int?) ?? 0).clamp(0, RepeatMode.values.length - 1)];
      _original = List.of(tracks);
      _order = tracks;

      var idx = 0, posMs = 0;
      if (await _posFile.exists()) {
        final p = jsonDecode(await _posFile.readAsString()) as Map<String, dynamic>;
        final byPath = _order.indexWhere((t) => t.path == (p['path'] as String? ?? ''));
        idx = byPath >= 0 ? byPath : ((p['index'] as int?) ?? 0);
        posMs = (p['positionMs'] as int?) ?? 0;
      }
      _index = idx.clamp(0, _order.length - 1);
      _resumable = true;
      radioMode = false;
      final t = current;
      if (t == null) return;
      currentCover = coverResolver?.call(t);
      await _player.open(Media(mediaResolver(t.path)), play: false); // reopen PAUSED
      if (posMs > 0) {
        // The seek only sticks once libmpv has loaded the file (duration known);
        // seeking too early is silently dropped → playback would restart at 0.
        for (var i = 0; i < 40 && duration <= Duration.zero; i++) {
          await Future.delayed(const Duration(milliseconds: 75));
        }
        await _player.seek(Duration(milliseconds: posMs));
        position = Duration(milliseconds: posMs);
      }
      resumedPaused = true;
      notifyListeners();
    } catch (_) {
    } finally {
      _restoring = false;
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
