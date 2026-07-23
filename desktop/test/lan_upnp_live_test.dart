@Tags(['live'])
library;

import 'dart:io';

import 'package:debridmusic/lan/net.dart';
import 'package:debridmusic/lan/upnp.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real speakers on this network.
///
/// Not part of the ordinary suite — it needs the hardware powered on, and it makes sound. Run it
/// deliberately:
///
///     flutter test test/lan_upnp_live_test.dart
///
/// It is polite about it: the speaker's volume is read, turned down, and put back, and playback
/// is stopped at the end. It refuses to touch a speaker that is already playing something.
void main() {
  test('finds the speakers on this network', () async {
    final renderers = await UpnpControlPoint().discover();
    for (final r in renderers) {
      // ignore: avoid_print
      print('${r.name.padRight(24)} ${r.host.padRight(16)} ${r.manufacturer} ${r.model} '
          '(cap ${r.maxSampleRate == 0 ? 'none' : '${r.maxSampleRate} Hz'})');
    }
    expect(renderers, isNotEmpty, reason: 'no UPnP renderer answered — is anything switched on?');
    // A Philips Hue bridge answers SSDP too; it must not end up in a list of speakers.
    expect(renderers.every((r) => r.avTransportUrl.isNotEmpty), isTrue);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('plays a track on an idle speaker, then puts everything back', () async {
    final upnp = UpnpControlPoint();
    final renderers = await upnp.discover();
    expect(renderers, isNotEmpty);

    // Only a speaker that is doing nothing. Taking over one that is mid-album would wipe its
    // queue, and no test is worth that.
    Renderer? target;
    for (final r in renderers) {
      final state = await upnp.transportState(r);
      if (state != null && state.state == 'STOPPED') {
        target = r;
        break;
      }
    }
    if (target == null) {
      // ignore: avoid_print
      print('every speaker is busy — skipping rather than interrupting one');
      return;
    }
    // ignore: avoid_print
    print('using ${target.name} (${target.host})');

    final fixture = File('test/fixtures/tone.flac');
    expect(fixture.existsSync(), isTrue, reason: 'run tool/make_tone.sh first');

    final address = await lanAddressFor(target.host);
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server.listen((request) async {
      request.response.headers
        ..set(HttpHeaders.contentTypeHeader, 'audio/flac')
        ..set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.contentLength = fixture.lengthSync();
      await request.response.addStream(fixture.openRead());
      await request.response.close();
    });
    final url = 'http://$address:${server.port}/tone.flac';

    final originalVolume = await upnp.getVolume(target);
    try {
      await upnp.setVolume(target, 8); // quiet: this is a test, not a performance
      await upnp.playUrl(
        target,
        url,
        title: 'DebridMusic testtoon',
        artist: 'Verificatie',
        album: 'Netwerktest',
        mime: 'audio/flac',
      );

      // Give it a moment to fetch and start.
      var playing = false;
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final state = await upnp.transportState(target);
        if (state?.isPlaying ?? false) {
          playing = true;
          break;
        }
      }
      expect(playing, isTrue, reason: '${target.name} never started playing');
    } finally {
      await upnp.stop(target);
      if (originalVolume != null) await upnp.setVolume(target, originalVolume);
      await server.close(force: true);
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
