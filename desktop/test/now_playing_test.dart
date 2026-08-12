/// The lockscreen side of playback. libmpv cannot load in a test, so this drives the handler
/// through [NowPlayingSource] — the surface [PlayerStore] implements, checked by the compiler.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:audio_service/audio_service.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/now_playing.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';

class FakePlayer extends ChangeNotifier implements NowPlayingSource {
  @override
  Track? current;
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(seconds: 200);
  @override
  Uint8List? currentCover;
  @override
  bool shuffle = false;
  @override
  RepeatMode repeat = RepeatMode.off;

  @override
  void zetShuffle(bool aan) {
    shuffle = aan;
    notifyListeners();
  }

  @override
  void zetHerhaal(RepeatMode m) {
    repeat = m;
    notifyListeners();
  }

  int nexts = 0, prevs = 0, toggles = 0;
  Duration? sought;

  @override
  void playPause() {
    toggles++;
    playing = !playing;
  }

  @override
  Future<void> next() async => nexts++;

  @override
  Future<void> prev() async => prevs++;

  @override
  void seek(Duration d) => sought = d;

  void tick() => notifyListeners();
}

Track _track(String path, {String title = 'Mysterons'}) => Track(
      path: path,
      title: title,
      artist: 'Portishead',
      album: 'Dummy',
      duration: const Duration(seconds: 305),
    );

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_np_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  test('what is playing reaches the system', () async {
    final player = FakePlayer()..current = _track('/muziek/01.flac');
    final handler = NowPlayingHandler(player, null);

    final item = await _item(handler, '/muziek/01.flac');
    expect(item?.title, 'Mysterons');
    expect(item?.artist, 'Portishead');
    expect(item?.album, 'Dummy');
    expect(item?.duration, const Duration(seconds: 305));
  });

  test('a play while already playing does not pause the music', () async {
    // What a reconnecting headset sends. The store has one toggle, so an unguarded play() here
    // would stop the music instead of doing nothing.
    final player = FakePlayer()
      ..current = _track('/muziek/01.flac')
      ..playing = true;
    final handler = NowPlayingHandler(player, null);

    await handler.play();
    expect(player.playing, isTrue);
    expect(player.toggles, 0);

    await handler.pause();
    expect(player.playing, isFalse);

    await handler.pause();
    expect(player.playing, isFalse, reason: 'twee keer pauze is nog steeds pauze');
  });

  test('the buttons reach the player', () async {
    final player = FakePlayer()..current = _track('/muziek/01.flac');
    final handler = NowPlayingHandler(player, null);

    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.seek(const Duration(seconds: 42));

    expect(player.nexts, 1);
    expect(player.prevs, 1);
    expect(player.sought, const Duration(seconds: 42));
  });

  group('shuffle en herhalen vanuit de auto', () {
    // Android Auto tekent zijn eigen shuffle- en herhaalknop, maar alleen als de sessie zegt dat ze
    // bestaan — en het is de VERTALING tussen zijn standen en de onze die makkelijk verwisselt.
    test('de standen komen aan bij de speler', () async {
      final player = FakePlayer()..current = _track('/muziek/01.flac');
      final handler = NowPlayingHandler(player, null);

      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      expect(player.shuffle, isTrue);
      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      expect(player.shuffle, isFalse);

      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      expect(player.repeat, RepeatMode.one);
      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      expect(player.repeat, RepeatMode.all);
      await handler.setRepeatMode(AudioServiceRepeatMode.none);
      expect(player.repeat, RepeatMode.off);
    });

    test('"group" is geen stilte, maar hetzelfde als alles', () {
      // Auto stuurt group bij een wachtrij. Viel die door de mazen, dan deed de knop niets.
      final player = FakePlayer()..current = _track('/muziek/01.flac');
      NowPlayingHandler(player, null).setRepeatMode(AudioServiceRepeatMode.group);
      expect(player.repeat, RepeatMode.all);
    });

    test('de twee knoppen staan in de sessie, met hun stand in het pictogram', () async {
      // Android Auto op een TELEFOON tekent geen eigen shuffle-/herhaalknop; het doet dat met
      // custom actions. Gemeten in de DHU: met alleen de standen bleef het bij vorige/play/volgende.
      final player = FakePlayer()..current = _track('/muziek/01.flac');
      final handler = NowPlayingHandler(player, null);
      player.notifyListeners();
      await Future<void>.delayed(Duration.zero);

      List<MediaControl> knoppen() => handler.playbackState.value.controls
          .where((c) => c.customAction != null)
          .toList();

      expect([for (final k in knoppen()) k.customAction!.name],
          [NowPlayingHandler.knopShuffle, NowPlayingHandler.knopHerhaal]);
      expect(knoppen().first.androidIcon, endsWith('ic_auto_shuffle'));

      await handler.customAction(NowPlayingHandler.knopShuffle);
      expect(player.shuffle, isTrue);
      expect(knoppen().first.androidIcon, endsWith('ic_auto_shuffle_aan'),
          reason: 'zonder verschil in de tekening zie je in de auto niet wat je net deed');
    });

    test('de herhaalknop loopt dezelfde ronde als in de app', () async {
      final player = FakePlayer()..current = _track('/muziek/01.flac');
      final handler = NowPlayingHandler(player, null);
      for (final verwacht in [RepeatMode.all, RepeatMode.one, RepeatMode.off]) {
        await handler.customAction(NowPlayingHandler.knopHerhaal);
        expect(player.repeat, verwacht);
      }
    });

    test('de sessie meldt dat ze bestaan, anders tekent Auto de knoppen niet', () async {
      final player = FakePlayer()..current = _track('/muziek/01.flac');
      final handler = NowPlayingHandler(player, null);
      player.shuffle = true;
      player.repeat = RepeatMode.one;
      player.notifyListeners();
      await Future<void>.delayed(Duration.zero);

      final s = handler.playbackState.value;
      expect(s.systemActions, contains(MediaAction.setShuffleMode));
      expect(s.systemActions, contains(MediaAction.setRepeatMode));
      expect(s.shuffleMode, AudioServiceShuffleMode.all);
      expect(s.repeatMode, AudioServiceRepeatMode.one);
    });
  });

  test('a cover is written once, and named after itself', () async {
    final art = Uint8List.fromList(List.generate(2048, (i) => (i * 11) % 256));
    final player = FakePlayer()..current = _track('/muziek/01.flac');
    final handler = NowPlayingHandler(player, (_) => art);

    final first = (await _item(handler, '/muziek/01.flac'))?.artUri;
    expect(first, isNotNull);
    expect(File(first!.toFilePath()).existsSync(), isTrue);

    // The same album again — same bytes, so the same file and nothing rewritten. Otherwise this
    // folder grows by a cover for every track you play.
    player.current = _track('/muziek/02.flac', title: 'Sour Times');
    player.tick();
    final second = (await _item(handler, '/muziek/02.flac'))?.artUri;
    expect(second, first);
    expect(Directory('${scratch.path}/nowplaying').listSync().length, 1);
  });

  test('a track with no cover still shows its title', () async {
    final player = FakePlayer()..current = _track('/muziek/01.flac');
    final handler = NowPlayingHandler(player, (_) => null);
    final item = await _item(handler, '/muziek/01.flac');
    expect(item?.title, 'Mysterons');
    expect(item?.artUri, isNull);
  });

  test('correcting the playing track reaches the lockscreen', () async {
    // The guard here used to be the path alone. Renaming the artist of what is playing changes no
    // path, so the republish was suppressed and Control Center kept the old name until the next
    // song — the one surface where you would most notice.
    final player = FakePlayer()..current = _track('/muziek/01.flac');
    final handler = NowPlayingHandler(player, null);
    expect((await _item(handler, '/muziek/01.flac'))?.artist, 'Portishead');

    player
      ..current = Track(
        path: '/muziek/01.flac',
        title: 'Mysterons',
        artist: 'Portishead & Beth Gibbons',
        album: 'Dummy',
        duration: const Duration(seconds: 305),
      )
      ..tick();

    final again = await _until(handler, (i) => i.artist == 'Portishead & Beth Gibbons');
    expect(again?.artist, 'Portishead & Beth Gibbons');
    expect(again?.id, '/muziek/01.flac', reason: 'zelfde nummer, andere naam');
  });

  test('a position tick still republishes nothing', () async {
    // The reason the guard exists at all: this listener fires several times a second, and every
    // republish writes artwork to disk and wakes the OS.
    final art = Uint8List.fromList(List.generate(2048, (i) => (i * 7) % 256));
    final player = FakePlayer()..current = _track('/muziek/01.flac');
    final handler = NowPlayingHandler(player, (_) => art);
    await _item(handler, '/muziek/01.flac');

    for (var i = 1; i <= 20; i++) {
      player
        ..position = Duration(seconds: i)
        ..tick();
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(Directory('${scratch.path}/nowplaying').listSync().length, 1,
        reason: 'één hoes, niet één per tik');
  });

  test('nothing playing publishes nothing', () async {
    final player = FakePlayer()..current = _track('/muziek/01.flac');
    final handler = NowPlayingHandler(player, null);
    await _item(handler, '/muziek/01.flac');

    player
      ..current = null
      ..tick();
    expect(handler.mediaItem.valueOrNull, isNull);
  });
}

/// The handler publishes asynchronously — the artwork has to be written to disk first — so wait
/// for the item that belongs to [path] rather than reading whatever is there this microtask.
Future<MediaItem?> _item(NowPlayingHandler handler, String path) =>
    _until(handler, (i) => i.id == path);

/// Same, for a republish that does NOT change the path — which is the whole point of the
/// correction test: waiting on the id there would return the stale item immediately.
Future<MediaItem?> _until(NowPlayingHandler handler, bool Function(MediaItem) ready) async {
  for (var i = 0; i < 100; i++) {
    final item = handler.mediaItem.valueOrNull;
    if (item != null && ready(item)) return item;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return handler.mediaItem.valueOrNull;
}
