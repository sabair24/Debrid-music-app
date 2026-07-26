/// Finding the speakers, on a machine with more than one network card.
///
/// A Sonos is found by multicast and a Shield by sweeping a /24 — completely unrelated mechanisms,
/// which is exactly why both going quiet at once pointed at the one thing they share: which network
/// the PC decided to look on. A Windows PC with a Hyper-V switch, a VPN adapter or two cards has
/// several, and picking the first one is a guess that fails silently. The sweep runs to completion
/// against a subnet with nothing in it and then reports "no devices" with as much confidence as if
/// it had looked in the right place.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/cast_manager.dart';

void main() {
  /// A stand-in for the television: answers /ping the way the receiver does.
  Future<HttpServer> fakeShield({required String name, bool musicApp = true}) async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(musicApp
          ? {'app': 'debridmusic', 'ready': true, 'name': name}
          // What the OTHER app on the same television answers. It must not be offered as a
          // speaker for music — it is a video player that happens to be on the same box.
          : {'app': 'debridmedia', 'ready': true, 'name': name}));
      await req.response.close();
    });
    return s;
  }

  group('what the television calls itself', () {
    test('is what the speaker list shows', () async {
      final shield = await fakeShield(name: 'Woonkamer');
      try {
        final name = await probeShield('127.0.0.1', port: shield.port);
        expect(name, 'Woonkamer',
            reason: 'een IP-adres is waar je op terugvalt, niet wat je toont');
      } finally {
        await shield.close(force: true);
      }
    });

    test('falls back to the address when it does not say', () async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((req) async {
        req.response.write(jsonEncode({'app': 'debridmusic', 'ready': true}));
        await req.response.close();
      });
      try {
        expect(await probeShield('127.0.0.1', port: s.port), contains('127.0.0.1'));
      } finally {
        await s.close(force: true);
      }
    });

    test('the media app on the same box is not a music speaker', () async {
      final other = await fakeShield(name: 'Woonkamer', musicApp: false);
      try {
        expect(await probeShield('127.0.0.1', port: other.port), isNull);
      } finally {
        await other.close(force: true);
      }
    });

    test('nothing listening is silence, not a crash', () async {
      // Bind and immediately release, so the port is almost certainly closed.
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close(force: true);
      expect(await probeShield('127.0.0.1', port: port), isNull);
    });
  });

  group('which networks get searched', () {
    test('every subnet the machine is on, each one only once', () {
      // Wifi, ethernet on a second subnet, and a Hyper-V switch. The television is on exactly one
      // of them and the app cannot know which.
      expect(
        sweepPrefixes(const ['192.168.0.117', '192.168.1.40', '172.20.16.1']),
        {'192.168.0', '192.168.1', '172.20.16'},
      );
    });

    test('two addresses on one subnet is one sweep', () {
      expect(sweepPrefixes(const ['192.168.0.117', '192.168.0.118']), {'192.168.0'});
    });

    test('no cards is no sweep rather than a guess', () {
      expect(sweepPrefixes(const []), isEmpty);
    });
  });
}
