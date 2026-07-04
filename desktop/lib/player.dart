import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'models.dart';

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

/// Native (libmpv) player with a queue, shuffle, repeat and a Radio mode.
class PlayerStore extends ChangeNotifier {
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
  List<RadioItem> get radioQueue => _radio;
  int get radioIndex => _radioIndex;

  Uint8List? currentCover;
  bool shuffle = false;
  RepeatMode repeat = RepeatMode.off;

  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

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
      notifyListeners();
    });
    _player.stream.position.listen((p) {
      position = p;
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
    currentCover = cover;
    _original = List.of(tracks);
    _rebuildOrder(start: (index >= 0 && index < _original.length) ? _original[index] : null);
    await _openCurrent();
  }

  /// Play a remote URL (e.g. a resolved TorBox stream) as a one-item queue.
  Future<void> playUrl(String url, {required String title, required String artist}) async {
    radioMode = false;
    currentCover = null;
    _original = [Track(path: url, title: title, artist: artist, album: '')];
    _order = List.of(_original);
    _index = 0;
    await _openCurrent();
  }

  /// Start a Radio / Smart-Shuffle queue of mixed local + online items.
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async {
    radioMode = true;
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
        currentCover = null;
        notifyListeners();
        await _player.open(Media(path), play: true);
        if (gen != _radioGen) return; // superseded while opening
        _prefetchNext();
        return;
      }
      if (_radioIndex >= _radio.length - 1) break; // don't overrun the end
      _radioIndex++; // couldn't source this one — skip forward
    }
    _radioIndex = _radio.isEmpty ? -1 : _radioIndex.clamp(0, _radio.length - 1);
    radioStatus = 'Radio klaar';
    notifyListeners();
  }

  /// Warm the next online item's URL so it's ready in time (shares the in-flight call).
  void _prefetchNext() {
    final ni = _radioIndex + 1;
    if (ni >= _radio.length) return;
    final it = _radio[ni];
    if (it.isLocal || it.url != null || it.failed) return;
    _resolveItem(it);
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

  Future<void> _openCurrent() async {
    final t = current;
    if (t == null) return;
    await _player.open(Media(t.path), play: true);
    notifyListeners();
  }

  void playPause() => _player.playOrPause();

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

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
