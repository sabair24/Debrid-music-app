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

import 'package:debridmusic/lan/cast_manager.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/upnp.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
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

  group('wat er in een GetPositionInfo-antwoord staat', () {
    String soap({String? rel, String? dur, String? uri}) => '<Res>'
        '${rel == null ? '' : '<RelTime>$rel</RelTime>'}'
        '${dur == null ? '' : '<TrackDuration>$dur</TrackDuration>'}'
        '${uri == null ? '' : '<TrackURI>$uri</TrackURI>'}'
        '</Res>';

    test('een gewoon antwoord geeft alle drie', () {
      final p = UpnpControlPoint.parsePositionInfo(
          soap(rel: '0:01:23', dur: '0:03:28', uri: 'http://x/stream/abc.flac?token=1&amp;maxRate=48000'));
      expect(p!.position, const Duration(minutes: 1, seconds: 23));
      expect(p.duration, const Duration(minutes: 3, seconds: 28));
      expect(p.trackUri, contains('&maxRate=48000'), reason: 'de XML-escape moet eruit');
    });

    test('geen klok, maar wel een URI: de URI blijft', () {
      // DE reden dat dit een losse functie werd. Wie hier null teruggeeft gooit ook de TrackURI weg, en
      // dan kan de app niet meer zien dat zo'n speaker een nummer verder is -- hij loopt achter tot je
      // zelf iets aanraakt.
      final p = UpnpControlPoint.parsePositionInfo(
          soap(rel: 'NOT_IMPLEMENTED', uri: 'http://x/stream/abc.flac'));
      expect(p, isNotNull);
      expect(p!.position, isNull, reason: 'geen klok is niet klok-op-nul');
      expect(p.trackUri, 'http://x/stream/abc.flac');
      expect(p.duration, Duration.zero);
    });

    test('een leeg antwoord blijft niets', () {
      expect(UpnpControlPoint.parsePositionInfo(soap()), isNull);
      expect(UpnpControlPoint.parsePositionInfo(soap(rel: 'NOT_IMPLEMENTED', uri: '')), isNull);
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

  /// Shuffle indrukken terwijl een speaker de wachtrij heeft.
  ///
  /// De speler schudde zijn EIGEN lijst en liet die van de speaker staan. De index die de speaker daarna
  /// elke twee seconden terugmeldt telt in zijn lijst, en die werd hier in een andere gelezen: het scherm
  /// toonde een ander album dan er klonk, zonder dat er iets haperde.
  group('shuffle terwijl de speaker de wachtrij heeft', () {
    Track t(String p) => Track(path: p, title: p, artist: 'A', album: 'B', duration: const Duration(minutes: 3));

    final alles = [for (var i = 0; i < 12; i++) t('n$i')];

    test('het spelende nummer staat op de teruggegeven index, dus de speaker heropent niets', () {
      final klinkt = alles[4];
      final uit = ordenVoor(alles, klinkt, shuffle: true);
      expect(uit.order[uit.index].path, klinkt.path);
    });

    test('dezelfde nummers, alleen anders gerangschikt', () {
      // DE eigenschap. Valt er één weg of komt er één bij, dan wijst elke index die de speaker
      // terugmeldt vanaf dat moment ergens anders heen dan bedoeld.
      final uit = ordenVoor(alles, alles[4], shuffle: true);
      expect(uit.order.length, alles.length);
      expect(uit.order.map((x) => x.path).toSet(), alles.map((x) => x.path).toSet());
    });

    test('shuffle uit: de oorspronkelijke volgorde, en de index zoekt het nummer op', () {
      final uit = ordenVoor(alles, alles[7], shuffle: false);
      expect(uit.order.map((x) => x.path), orderedEquals(alles.map((x) => x.path)));
      expect(uit.index, 7);
    });

    test('zonder anker begint hij vooraan in plaats van bij min één', () {
      expect(ordenVoor(alles, null, shuffle: false).index, 0);
      expect(ordenVoor(const <Track>[], null, shuffle: true).order, isEmpty);
    });
  });

  /// Waarom deze groep bestaat: "ik hoor de Backstreet Boys, maar zie de hoes van Michael Jackson."
  ///
  /// De app gaf de speaker het volgende nummer alvast mee en zag hem daarna in TrackURI terug. Dat werd
  /// gelezen als "hij is doorgeschoven", maar een Sonos meldt die URI al zodra hij hem ONTVANGT. De index
  /// schoof dus op terwijl er niets wisselde, gaf meteen het nummer daarna mee, en acht seconden later
  /// gebeurde hetzelfde -- het scherm wandelde door de wachtrij terwijl één nummer speelde.
  group('is de muziek gewisseld of alleen de boekhouding', () {
    const lengte = Duration(seconds: 208); // een echt nummer van de Sonos-test

    test('de gemeten valse melding: de URI staat er al, maar de klok loopt door', () {
      final o = muziekIsGewisseld(
        top: const Duration(seconds: 20),
        positie: const Duration(seconds: 20),
        gespeeld: const Duration(seconds: 20),
        lengte: lengte,
      );
      expect(o.ja, isFalse, reason: 'twintig seconden in een nummer van 208 is geen overgang');
    });

    test('een heel nummer lang pollen schuift de wachtrij geen enkele plek op', () {
      // DE test. Dit is precies wat er misging: niet één verkeerde beslissing maar een reeks, elke paar
      // seconden opnieuw, tot het scherm albums verder stond dan het geluid.
      var top = Duration.zero;
      for (var s = 1; s < 208; s++) {
        final positie = Duration(seconds: s);
        final o = muziekIsGewisseld(
            top: top, positie: positie, gespeeld: positie, lengte: lengte);
        expect(o.ja, isFalse, reason: 'op $s seconden zei hij toch dat er gewisseld was: ${o.reden}');
        if (positie > top) top = positie;
      }
    });

    test('de echte overgang: de klok valt terug naar het begin', () {
      final o = muziekIsGewisseld(
        top: const Duration(seconds: 207),
        positie: const Duration(seconds: 1),
        gespeeld: const Duration(seconds: 208),
        lengte: lengte,
      );
      expect(o.ja, isTrue);
      expect(o.reden, contains('terug'));
    });

    test('een gat tussen twee metingen laat de overgang niet ontsnappen', () {
      // Wie eist dat de positie bijna nul is, mist hem als er een halve minuut niet gepolst werd -- en
      // loopt daarna de rest van het nummer achter, want terugvallen doet hij pas weer bij het volgende.
      final o = muziekIsGewisseld(
        top: const Duration(seconds: 207),
        positie: const Duration(seconds: 25),
        gespeeld: const Duration(seconds: 232),
        lengte: lengte,
      );
      expect(o.ja, isTrue);
    });

    test('vlak na de start is een lage klok geen overgang maar een begin', () {
      final o = muziekIsGewisseld(
        top: const Duration(seconds: 3),
        positie: const Duration(seconds: 3),
        gespeeld: const Duration(seconds: 3),
        lengte: lengte,
      );
      expect(o.ja, isFalse);
    });

    test('achteruit slepen is geen overgang, want het ijkpunt schuift mee', () {
      // De app zet [hoogstePositie] op de plek waar naartoe gesleept is. Zonder dat zou achteruit slepen
      // niet te onderscheiden zijn van een nummer dat afliep: bij allebei valt de klok terug.
      final o = muziekIsGewisseld(
        top: const Duration(seconds: 5), // net naar 0:05 gesleept
        positie: const Duration(seconds: 5),
        gespeeld: const Duration(seconds: 200),
        lengte: lengte,
      );
      expect(o.ja, isFalse);
    });

    test('een speaker die op nul blijft staan wordt op de klok geloofd', () {
      expect(
        muziekIsGewisseld(
                top: Duration.zero, positie: Duration.zero, gespeeld: const Duration(seconds: 100), lengte: lengte)
            .ja,
        isFalse,
        reason: 'honderd van 208 seconden is nog niet om',
      );
      expect(
        muziekIsGewisseld(
                top: Duration.zero, positie: Duration.zero, gespeeld: const Duration(seconds: 200), lengte: lengte)
            .ja,
        isTrue,
        reason: 'binnen de speling van het einde',
      );
    });

    test('zonder positie én zonder lengte blijft alleen vertrouwen over', () {
      // Niets om aan te toetsen. Dan liever doorschuiven dan de wachtrij laten hangen: de speaker meldde
      // tenslotte wél de volgende-URL, en dat is nog altijd een aanwijzing.
      final o = muziekIsGewisseld(top: Duration.zero, positie: null, gespeeld: const Duration(seconds: 9));
      expect(o.ja, isTrue);
    });
  });
}
