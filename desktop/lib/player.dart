import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'models.dart';

/// Wraps a native (libmpv) player with a simple queue + transport state.
class PlayerStore extends ChangeNotifier {
  final Player _player = Player();
  List<Track> _queue = [];
  int _index = -1;

  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  Track? get current => (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  bool get hasNext => _index < _queue.length - 1;
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
      if (done) next();
    });
  }

  Future<void> playQueue(List<Track> tracks, int index) async {
    _queue = List.of(tracks);
    _index = index;
    await _openCurrent();
  }

  Future<void> _openCurrent() async {
    final t = current;
    if (t == null) return;
    await _player.open(Media(t.path), play: true);
    notifyListeners();
  }

  void playPause() => _player.playOrPause();

  Future<void> next() async {
    if (hasNext) {
      _index++;
      await _openCurrent();
    }
  }

  Future<void> prev() async {
    if (position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    if (hasPrev) {
      _index--;
      await _openCurrent();
    }
  }

  void seek(Duration d) => _player.seek(d);

  void setVolume(double v) => _player.setVolume(v);

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
