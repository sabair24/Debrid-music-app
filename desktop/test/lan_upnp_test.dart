import 'package:debridmusic/lan/upnp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

Renderer _renderer({String manufacturer = 'Sonos, Inc.', String model = 'Sonos Move'}) => Renderer(
      id: '192.168.0.188',
      name: 'Sonos Move',
      host: '192.168.0.188',
      avTransportUrl: 'http://192.168.0.188:1400/MediaRenderer/AVTransport/Control',
      renderingControlUrl: 'http://192.168.0.188:1400/MediaRenderer/RenderingControl/Control',
      model: model,
      manufacturer: manufacturer,
    );

void main() {
  group('speaker names', () {
    test('a Sonos name is stripped back to the room', () {
      // Sonos calls itself "192.168.0.188 - Sonos Move - RINCON_F0F6C15190F401400". Nobody wants
      // to pick a speaker from a list that reads like that.
      expect(
        UpnpControlPoint.tidyNameForTest('192.168.0.188 - Sonos Move - RINCON_F0F6C15190F401400'),
        'Sonos Move',
      );
      expect(
        UpnpControlPoint.tidyNameForTest('192.168.0.240 - Sonos Amp - RINCON_48A6B8633C1B01400'),
        'Sonos Amp',
      );
    });

    test('a name that needs no tidying is left alone', () {
      expect(UpnpControlPoint.tidyNameForTest('LS50 Wireless II'), 'LS50 Wireless II');
      expect(UpnpControlPoint.tidyNameForTest('Woonkamer'), 'Woonkamer');
    });
  });

  group('service lookup', () {
    test('reads the service name off the URN', () {
      expect(UpnpControlPoint.serviceNameForTest('urn:schemas-upnp-org:service:AVTransport:1'),
          'AVTransport');
      expect(UpnpControlPoint.serviceNameForTest('urn:schemas-upnp-org:service:RenderingControl:1'),
          'RenderingControl');
    });

    test('GroupRenderingControl is a different service, not a RenderingControl', () {
      // A Sonos exposes both. Matching on `contains` let the group service overwrite the real
      // one, and every volume call then came back "401 Invalid Action" — which reads like a
      // permissions problem and is nothing of the sort. Found against real hardware.
      expect(
        UpnpControlPoint.serviceNameForTest('urn:schemas-upnp-org:service:GroupRenderingControl:1'),
        isNot('RenderingControl'),
      );
      expect(
        UpnpControlPoint.serviceNameForTest('urn:schemas-upnp-org:service:GroupRenderingControl:1'),
        'GroupRenderingControl',
      );
    });
  });

  group('what a speaker can take', () {
    test('a Sonos is capped at 48 kHz', () {
      // Not a preference — Sonos SKIPS a file above 48 kHz rather than downsampling it, so
      // without this the hi-res half of a library would silently refuse to play.
      final sonos = _renderer();
      expect(sonos.isSonos, isTrue);
      expect(sonos.maxSampleRate, 48000);
    });

    test('anything else is left uncapped', () {
      final kef = _renderer(manufacturer: 'KEF', model: 'LS50 Wireless II');
      expect(kef.isSonos, isFalse);
      // The KEF takes 24/384 over the network; capping it would throw away the whole point.
      expect(kef.maxSampleRate, 0);
    });
  });

  group('DIDL metadata', () {
    test('carries what the speaker displays', () {
      // Without this a Sonos plays the audio but shows "—" for title, artist and sleeve, both on
      // the speaker and in the Sonos app.
      final didl = UpnpControlPoint.didlForTest(
        'http://192.168.0.216:47820/stream/abc.flac?token=t',
        title: 'Mysterons',
        artist: 'Portishead',
        album: 'Dummy',
        mime: 'audio/flac',
        artUrl: 'http://192.168.0.216:47820/art/xyz?token=t',
      );
      final document = XmlDocument.parse(didl);
      expect(document.findAllElements('dc:title').first.innerText, 'Mysterons');
      expect(document.findAllElements('upnp:album').first.innerText, 'Dummy');
      expect(document.findAllElements('upnp:albumArtURI').first.innerText, contains('/art/xyz'));
      expect(document.findAllElements('res').first.getAttribute('protocolInfo'),
          'http-get:*:audio/flac:*');
    });

    test('an ampersand in a title does not break the envelope', () {
      // "Simon & Garfunkel" unescaped makes the XML invalid, and the speaker rejects the whole
      // command — the track just never starts.
      final didl = UpnpControlPoint.didlForTest(
        'http://pc/stream/a.flac?token=t&maxRate=48000',
        title: 'Sisters & Brothers',
        artist: 'Simon & Garfunkel',
        album: 'Bookends <Remaster>',
        mime: 'audio/flac',
      );
      final document = XmlDocument.parse(didl); // parses at all == correctly escaped
      expect(document.findAllElements('dc:creator').first.innerText, 'Simon & Garfunkel');
      expect(document.findAllElements('upnp:album').first.innerText, 'Bookends <Remaster>');
      expect(document.findAllElements('res').first.innerText, contains('maxRate=48000'));
    });

    test('no artwork means no empty element', () {
      final didl = UpnpControlPoint.didlForTest(
        'http://pc/a.flac',
        title: 't', artist: 'a', album: 'b', mime: 'audio/flac',
      );
      expect(XmlDocument.parse(didl).findAllElements('upnp:albumArtURI'), isEmpty);
    });
  });

  group('transport state', () {
    test('reads the states the queue depends on', () {
      expect(const TransportState('PLAYING').isPlaying, isTrue);
      expect(const TransportState('STOPPED').isStopped, isTrue);
      expect(const TransportState('NO_MEDIA_PRESENT').isStopped, isTrue);
      // TRANSITIONING is what a Sonos reports while it fetches the first bytes — treating it as
      // stopped would skip to the next track before the current one had a chance to start.
      expect(const TransportState('TRANSITIONING').isStopped, isFalse);
      expect(const TransportState('PAUSED_PLAYBACK').isStopped, isFalse);
    });
  });
}
