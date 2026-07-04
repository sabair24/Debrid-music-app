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
    _radioIndex = start;
    await _openRadioCurrent();
  }

  Future<void> _openRadioCurrent() async {
    while (_radioIndex >= 0 && _radioIndex < _radio.length) {
      final it = _radio[_radioIndex];
      if (it.isLocal) {
        radioStatus = '';
        currentCover = null;
        notifyListeners();
        await _player.open(Media(it.local!.path), play: true);
        _prefetchNext();
        return;
      }
      if (it.url == null && !it.failed) {
        radioStatus = 'Bron zoeken: ${it.artist} — ${it.title}…';
        notifyListeners();
        final url = await resolver?.call(it.artist, it.title);
        if (url != null) {
          it.url = url;
        } else {
          it.failed = true;
        }
      }
      if (it.url != null) {
        radioStatus = '';
        currentCover = null;
        notifyListeners();
        await _player.open(Media(it.url!), play: true);
        _prefetchNext();
        return;
      }
      _radioIndex++; // couldn't source this one — skip
    }
    radioStatus = 'Radio klaar';
    notifyListeners();
  }

  /// Resolve the next online item's URL in the background so it's ready in time.
  void _prefetchNext() {
    final ni = _radioIndex + 1;
    if (ni >= _radio.length) return;
    final it = _radio[ni];
    if (it.isLocal || it.url != null || it.failed) return;
    resolver?.call(it.artist, it.title).then((url) {
      if (url != null) {
        it.url = url;
      } else {
        it.failed = true;
      }
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
      if (_radioIndex > 0) {
        _radioIndex--;
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
