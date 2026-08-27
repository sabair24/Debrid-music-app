/// Twee schermen, twee hoezen, één plaat.
///
/// **Wat er misging.** Op Start stond van *Thunderdome VIII* een andere hoes dan op de albumpagina —
/// en de albumpagina had het goed. De oorzaak zat niet in de hoezen maar in wat er NIET bij stond:
/// de albumpagina zocht de hoes van de juiste persing op, tekende hem, en gaf hem door aan de
/// bibliotheek zónder te kunnen zeggen waar hij vandaan kwam.
///
/// Dat laatste is beslissend. `adoptAlbumCover` filet een hoes mét persing als `resolvedCover`, en
/// die gaat vóór de hoes die in de bestanden zit; een hoes zónder persing is een gok op naam en
/// belandt in `enriched`, dat het van de bestanden verliest. Er stond alleen een persing bij als de
/// gebruiker er zelf één had vastgezet — en dat is het uitzonderingsgeval, niet het gewone.
///
/// Zo kon dezelfde hoes op de albumpagina winnen en op Start verliezen, elke keer opnieuw.
library;

import 'package:debridmusic/discogs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hoesHerkomst', () {
    test('de persing waar de hoes werkelijk vandaan komt telt', () {
      // Het geval dat stuk was: niets vastgezet, en de keten heeft de persing uitgezocht.
      expect(hoesHerkomst(artBron: 'rel:9902241'), 'rel:9902241');
      expect(hoesHerkomst(artBron: 'mb:0f5be2b5-1234'), 'mb:0f5be2b5-1234');
    });

    test('zonder vastgezette persing kwam er niets uit, en dat was de fout', () {
      // Dit is letterlijk wat de oude regel deed. Hij staat hier als toets zodat niemand er per
      // ongeluk naar terugkeert: null betekent verderop "gok op naam", en dan verliest de hoes van
      // wat er in de bestanden zit.
      expect(hoesHerkomst(artBron: null, pinnedMbid: null, pinned: null), isNull);
    });

    test('de gevonden persing gaat vóór de vastgezette', () {
      // Niet omdat de pin er niet toe doet — die stuurt de zoektocht al — maar omdat de hoes die
      // TERUGKOMT van een sibling-persing kan zijn: de gepinde heeft niet altijd scans. Wat er
      // opgeschreven wordt, moet de plaat zijn waar de bytes vandaan komen.
      expect(hoesHerkomst(artBron: 'mb:echt', pinnedMbid: 'mb-pin', pinned: 42), 'mb:echt');
    });

    test('de pin is de terugval voor hoezen uit de oude cache', () {
      // Een map die vóór deze versie geschreven is draagt geen herkomst. Dan is de pin nog steeds
      // het beste dat er is, en dat is beter dan terugvallen op "gok op naam".
      expect(hoesHerkomst(artBron: null, pinnedMbid: 'abc-123'), 'mb:abc-123');
      expect(hoesHerkomst(artBron: null, pinned: 9902241), 'rel:9902241');
    });

    test('een lege herkomst telt niet als herkomst', () {
      // `''` is niet-null en zou dus als "er hoort een persing bij" doorgaan — een hoes die de
      // bestanden overruled op grond van niets.
      expect(hoesHerkomst(artBron: ''), isNull);
      expect(hoesHerkomst(artBron: '', pinnedMbid: ''), isNull);
      expect(hoesHerkomst(artBron: '', pinnedMbid: '', pinned: 0), isNull);
    });
  });

  group('ReleaseArt draagt zijn herkomst', () {
    test('zonder bron is er niets bijgekomen', () {
      const a = ReleaseArt();
      expect(a.bron, isNull);
      expect(a.isEmpty, isTrue);
    });
  });

  group('DE KERN: de weg terug, zodat elk scherm dezelfde persing gebruikt', () {
    // Gemeld op 27-08-2026: *"waarom zit er nu nog altijd een verschil van album hoes, dit moet
    // overal gelijk zijn"*. Van "Don't Change" van Worlds Apart stond er één nummer in de
    // bibliotheek. De albumpagina vroeg naar een plaat van veertien nummers en kreeg de gewone cd;
    // het speelscherm kent alleen het aantal BESTANDEN, vroeg dus naar een plaat van één, en kreeg
    // een promo-persing met een sticker op het doosje.
    //
    // De oplossing is niet beter zoeken maar niet nóg eens zoeken: de persing die de hoes al
    // leverde staat in `Album.resolvedFrom`, en elk scherm geeft hem mee als speld. Deze toets
    // bewaakt dat die sleutel terug te lezen is — een sleutel die maar half teruggelezen wordt is
    // stiller kapot dan een die gooit.

    test('een Discogs-persing komt er als nummer uit', () {
      expect(persingUitHerkomst('rel:12345').release, 12345);
      expect(persingUitHerkomst('rel:12345').mbid, isNull);
    });

    test('een MusicBrainz-persing komt er als sleutel uit', () {
      const id = '76df3287-6cda-33eb-8e9a-044b5e15ffdd';
      expect(persingUitHerkomst('mb:$id').mbid, id);
      expect(persingUitHerkomst('mb:$id').release, isNull);
    });

    test('de vorm die de uitgavekiezer gebruikt wordt ook gelezen', () {
      // Daar heet hij `dg:`. Twee schrijfwijzen voor hetzelfde ding, dus allebei lezen.
      expect(persingUitHerkomst('dg:777').release, 777);
    });

    test('niets, leeg of rommel geeft geen persing', () {
      for (final h in [null, '', '   ', 'rel:', 'mb:', 'rel:nul', 'rel:0', 'rel:-3', 'iets anders']) {
        final p = persingUitHerkomst(h);
        expect(p.release, isNull, reason: 'release uit ${h ?? "null"}');
        expect(p.mbid, isNull, reason: 'mbid uit ${h ?? "null"}');
      }
    });

    test('spaties eromheen doen er niet toe', () {
      expect(persingUitHerkomst('  rel:88  ').release, 88);
      expect(persingUitHerkomst(' mb:abc ').mbid, 'abc');
    });

    test('DE AFSPRAAK: wat hoesHerkomst schrijft is terug te lezen', () {
      // Dit is het paar dat niet uit elkaar mag lopen. Verandert de ene schrijfwijze en de andere
      // niet, dan tekenen de schermen weer verschillende hoezen — zonder dat er iets stukgaat.
      expect(persingUitHerkomst(hoesHerkomst(pinned: 4242)).release, 4242);
      expect(persingUitHerkomst(hoesHerkomst(pinnedMbid: 'abc-123')).mbid, 'abc-123');
      expect(persingUitHerkomst(hoesHerkomst(artBron: 'rel:9')).release, 9);
      expect(persingUitHerkomst(hoesHerkomst(artBron: 'mb:zzz')).mbid, 'zzz');
      // En niets in, niets uit.
      final leeg = persingUitHerkomst(hoesHerkomst());
      expect(leeg.release, isNull);
      expect(leeg.mbid, isNull);
    });
  });
}
