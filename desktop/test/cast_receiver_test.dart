/// Being cast to.
///
/// Against a real socket and the exact bytes the PC sends, because that is the whole risk here:
/// the sender is CastManager on the PC and it is not changing. A receiver that answers a slightly
/// different shape does not fail loudly — the speaker list simply stays empty, or the TV goes
/// quiet, and there is nothing on screen to say why.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/cast_receiver.dart';
import 'package:debridmusic/models.dart';

void main() {
  late CastReceiver receiver;
  late List<Track> played;
  late int playedIndex;
  late int stops;

  setUp(() async {
    played = [];
    playedIndex = -1;
    stops = 0;
    receiver = CastReceiver(
      deviceName: () => 'Woonkamer',
      onPlay: (tracks, index) {
        played = tracks;
        playedIndex = index;
      },
      onStop: () => stops++,
    );
    await receiver.start();
  });

  tearDown(() async => receiver.stop());

  Uri url(String path) => Uri.parse('http://127.0.0.1:$kCastReceiverPort$path');

  /// Posts the way CastManager does — with an explicit Content-Length, because its comment says a
  /// chunked request arrives as an empty one.
  Future<HttpClientResponse> post(String path, Map<String, dynamic> body) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(url(path));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      final payload = utf8.encode(jsonEncode(body));
      req.contentLength = payload.length;
      req.add(payload);
      return await req.close();
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(url(path))).close();
      return jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  group('the PC can find this device', () {
    test('ping answers the shape the sender matches on', () async {
      final body = await getJson('/ping');
      // CastManager._pingShield reads exactly this. Anything else and the device never appears in
      // the speaker list at all.
      expect(body['app'], 'debridmusic');
      expect(body['ready'], true);
      expect(body['name'], 'Woonkamer');
    });
  });

  group('being told what to play', () {
    final payload = {
      'streamUrls': [
        'http://192.168.0.117:47820/stream/abc.flac?token=t',
        'http://192.168.0.117:47820/stream/def.flac?token=t',
        'http://192.168.0.117:47820/stream/ghi.flac?token=t',
      ],
      'index': 1,
      'title': 'Sour Times',
      'artist': 'Portishead',
      'album': 'Dummy',
    };

    test('the whole queue arrives, starting where it was told', () async {
      final res = await post('/play', payload);
      expect(res.statusCode, 200);
      await res.drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(played.length, 3, reason: 'de hele wachtrij, niet alleen het eerste nummer');
      expect(playedIndex, 1);
      expect(played[1].title, 'Sour Times');
      expect(played[1].artist, 'Portishead');
      // The paths ARE the stream URLs — that is what the player is handed and what the library
      // looks the album back up by.
      expect(played[1].path, contains('def.flac'));
    });

    test('the answer comes before playback starts', () async {
      // The sender waits on this response, and starting playback pulls bytes over the network. A
      // receiver that plays first reads as "the TV is not responding".
      final res = await post('/play', payload);
      expect(res.statusCode, 200);
      expect(jsonDecode(await utf8.decoder.bind(res).join())['ok'], true);
    });

    test('an empty request is refused rather than silently accepted', () async {
      final res = await post('/play', {'streamUrls': <String>[], 'index': 0});
      expect(res.statusCode, 400);
      await res.drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(played, isEmpty);
    });

    test('tracks the sender did not name still carry something readable', () async {
      await (await post('/play', payload)).drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // The sender names only the track it starts on; it has the catalogue and this end does not.
      expect(played[0].title, 'abc');
      expect(played[2].title, 'ghi');
    });
  });

  group('stopping', () {
    test('stop is answered and passed on', () async {
      final res = await post('/stop', {});
      expect(res.statusCode, 200);
      await res.drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(stops, 1);
    });
  });

  group('anything else', () {
    test('an unknown path is a 404, not a crash', () async {
      final client = HttpClient();
      final res = await (await client.getUrl(url('/nope'))).close();
      expect(res.statusCode, 404);
      await res.drain<void>();
      client.close();
    });
  });
}
