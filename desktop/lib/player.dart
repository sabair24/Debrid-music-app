import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'models.dart';

enum RepeatMode { off, all, one }

/// Native (libmpv) player with a queue, shuffle and repeat.
class PlayerStore extends ChangeNotifier {
  final Player _player = Player();
  List<Track> _original = [];
  List<Track> _order = [];
  int _index = -1;

  Uint8List? currentCover;
  bool shuffle = false;
  RepeatMode repeat = RepeatMode.off;

  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  Track? get current => (_index >= 0 && _index < _order.length) ? _order[_index] : null;
  bool get hasNext => _index < _order.length - 1 || (repeat == RepeatMode.all && _order.isNotEmpty);
  bool get hasPrev => _index > 0;

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
      _openCurrent();
    } else {
      next();
    }
  }

  Future<void> playQueue(List<Track> tracks, int index, {Uint8List? cover}) async {
    currentCover = cover;
    _original = List.of(tracks);
    _rebuildOrder(start: (index >= 0 && index < _original.length) ? _original[index] : null);
    await _openCurrent();
  }

  /// Play a remote URL (e.g. a resolved TorBox stream) as a one-item queue.
  Future<void> playUrl(String url, {required String title, required String artist}) async {
    currentCover = null;
    _original = [Track(path: url, title: title, artist: artist, album: '')];
    _order = List.of(_original);
    _index = 0;
    await _openCurrent();
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
