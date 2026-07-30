/// Steering a speaker from a phone.
///
/// Casting to the KEF worked, and then every control stopped working: the buttons all spoke to the
/// local libmpv, which is deliberately silent while a speaker has the queue. So pause did nothing,
/// next did nothing, the scrubber did nothing, and there was no volume at all.
///
/// These pin the two halves of the fix that can be tested without a speaker in the room: the time
/// format UPnP answers in, and the remote that carries the position between polls.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/upnp.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/speakers.dart';

void main() {
  group('the time format a renderer speaks', () {
    test('a request always carries hours, because UPnP requires them', () {
      expect(UpnpControlPoint.upnpTime(const Duration(seconds: 5)), '0:00:05');
      expect(UpnpControlPoint.upnpTime(const Duration(minutes: 3, seconds: 42)), '0:03:42');
      expect(UpnpControlPoint.upnpTime(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });

    test('a negative target is the start of the track, not a fault', () {
      expect(UpnpControlPoint.upnpTime(const Duration(seconds: -30)), '0:00:00');
    });

    test('the answers actually seen in the wild all parse', () {
      expect(UpnpControlPoint.parseUpnpTime('0:01:23'), const Duration(minutes: 1, seconds: 23));
      expect(UpnpControlPoint.parseUpnpTime('00:01:23.000'), const Duration(minutes: 1, seconds: 23));
      // A Sonos writes the fraction with a comma.
      expect(UpnpControlPoint.parseUpnpTime('00:01:23,500'), const Duration(minutes: 1, seconds: 23));
      expect(UpnpControlPoint.parseUpnpTime('1:00:00'), const Duration(hours: 1));
    });

    test('"nothing loaded" is null, and must never read as back-to-the-start', () {
      // THE one that matters: parsed as zero, a paused speaker would show a track that had jumped
      // to its beginning — and the bar would fight the finger every two seconds.
      expect(UpnpControlPoint.parseUpnpTime('NOT_IMPLEMENTED'), isNull);
      expect(UpnpControlPoint.parseUpnpTime(''), isNull);
      expect(UpnpControlPoint.parseUpnpTime(null), isNull);
      expect(UpnpControlPoint.parseUpnpTime('rubbish'), isNull);
      expect(UpnpControlPoint.parseUpnpTime('1:2'), isNull);
    });
  });

  group('what the speaker reported', () {
    test('a missing field stays missing rather than becoming a zero', () {
      final s = CastStatus.fromJson({'casting': true});
      expect(s.casting, isTrue);
      expect(s.position, isNull, reason: 'geen positie is niet positie nul');
      expect(s.duration, isNull);
      expect(s.playing, isNull);
      expect(s.volume, isNull);
    });

    test('next and previous are offered only where there is one', () {
      final middle = CastStatus.fromJson({'casting': true, 'index': 1, 'queueLength': 3});
      expect(middle.hasPrev, isTrue);
      expect(middle.hasNext, isTrue);

      final first = CastStatus.fromJson({'casting': true, 'index': 0, 'queueLength': 3});
      expect(first.hasPrev, isFalse);
      expect(first.hasNext, isTrue);

      final last = CastStatus.fromJson({'casting': true, 'index': 2, 'queueLength': 3});
      expect(last.hasPrev, isTrue);
      expect(last.hasNext, isFalse);

      // Nothing known: neither button lights up, rather than both.
      final unknown = CastStatus.fromJson({'casting': false});
      expect(unknown.hasPrev, isFalse);
      expect(unknown.hasNext, isFalse);
    });
  });

  group('the remote itself', () {
    test('nothing is playing here until a speaker is chosen', () {
      final t = SpeakerTarget();
      expect(t.isCasting, isFalse);
      expect(t.position, isNull);
      expect(t.duration, isNull);
      expect(t.isPlaying, isFalse);
      expect(t.hasVolume, isFalse, reason: 'geen speaker, geen volumeschuif');
      t.dispose();
    });

    test('choosing this device again clears what the speaker had said', () {
      final t = SpeakerTarget();
      const kef = CastDevice(id: 'kef-1', name: 'KEF LSX', kind: 'upnp');
      t.select(kef);
      expect(t.isCasting, isTrue);
      t.select(null);
      expect(t.isCasting, isFalse);
      expect(t.status, isNull, reason: 'anders blijft de oude positie op het scherm staan');
      expect(t.position, isNull);
      t.dispose();
    });

    test('a drag carries the handle before anything is sent', () {
      // Without this the bar snapped back to where the speaker last said it was, every two
      // seconds, while the finger was still on it.
      final t = SpeakerTarget();
      t.select(const CastDevice(id: 'kef-1', name: 'KEF LSX', kind: 'upnp'));
      t.scrubTo(const Duration(minutes: 2));
      expect(t.position, const Duration(minutes: 2));
      t.dispose();
    });

    test('with no client to steer through, a command is a no-op rather than a crash', () async {
      // A pc that owns the music has no RemoteClient — it drives the speaker directly — and these
      // getters are read by the same widgets on both.
      final t = SpeakerTarget();
      t.select(const CastDevice(id: 'kef-1', name: 'KEF LSX', kind: 'upnp'));
      await t.playPause();
      await t.next();
      await t.previous();
      await t.seekTo(const Duration(seconds: 30));
      await t.setVolume(40);
      expect(t.isCasting, isTrue);
      t.dispose();
    });
  });

  group('de wachtrij die de speaker krijgt', () {
    Track t(String naam) => Track(path: naam, title: naam, artist: 'A', album: 'B');

    test('alles serveerbaar: één op één, en de index blijft staan', () {
      final over = buildHandover([t('1'), t('2'), t('3')], 2, (x) => 'id-${x.path}');
      expect(over.ids, ['id-1', 'id-2', 'id-3']);
      expect(over.at, 2);
    });

    test('een nummer dat de pc niet kan serveren schuift de index mee', () {
      // DE fout. Nummer 2 valt weg, dus wat de gebruiker aantikte staat nu op plek 1 in plaats van 2.
      // Voorheen ging er een 2 naar de speaker en toonde de app nummer 3: een ander album dan er klonk.
      final over = buildHandover(
          [t('1'), t('geen id'), t('3')], 2, (x) => x.path == 'geen id' ? null : 'id-${x.path}');
      expect(over.ids, ['id-1', 'id-3']);
      expect(over.at, 1);
      expect(over.tracks.map((x) => x.path), ['1', '3'],
          reason: 'de speler moet exact deze lijst krijgen, anders rekent hij weer anders');
    });

    test('valt het gevraagde nummer zelf weg, dan iets eerder beginnen', () {
      // Een nummer te vroeg hoor je en corrigeer je; een nummer dat overgeslagen wordt merk je niet.
      final over = buildHandover(
          [t('1'), t('2'), t('weg'), t('4')], 2, (x) => x.path == 'weg' ? null : 'id-${x.path}');
      expect(over.ids, ['id-1', 'id-2', 'id-4']);
      expect(over.at, 1);
    });

    test('niets serveerbaar is geen overdracht', () {
      final over = buildHandover([t('1'), t('2')], 0, (_) => null);
      expect(over.isEmpty, isTrue);
      expect(over.at, 0);
    });

    test('een index buiten de lijst landt binnen de lijst', () {
      final over = buildHandover([t('1'), t('2')], 99, (x) => 'id-${x.path}');
      expect(over.at, 1);
    });
  });
}
