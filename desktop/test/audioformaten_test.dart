/// Eén lijst van wat muziek is, en niet vijf.
///
/// **De klacht, op 31-08-2026.** *"dsd, ape, wav files enzo worden niet herkend, de app moet alle
/// audio formaten herkennen."*
///
/// **Wat er aan de hand was.** De vraag "is dit muziek?" werd op vijf plekken los van elkaar
/// beantwoord — de bibliotheekscan, twee lijsten in `organize.dart`, `TbFile.isAudio` en
/// `TorrentBestand.isAudio` — en de vijf antwoorden waren alle vijf anders. Elk verschil is een
/// manier waarop muziek verdwijnt zonder één woord; `audioformaten.dart` legt uit welke.
///
/// **Waarom hier een toets op staat.** Een nieuw formaat toevoegen is één regel, en het is precies
/// het soort wijziging waarbij iemand (ik) er één plek van de zes vergeet. Deze toets is niet een
/// lijst overschrijven in andere woorden: hij legt vast dat de vijf plekken NIET meer uit elkaar
/// kunnen lopen, en dat de soorten waar de gebruiker naar wees erin zitten.
library;

import 'package:debridmusic/audioformaten.dart';
import 'package:debridmusic/quality.dart';
import 'package:debridmusic/torrentbestand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('wat er als muziek telt', () {
    test('de soorten uit de klacht zitten erin', () {
      for (final s in ['dsf', 'dff', 'ape', 'wav', 'wv', 'aiff', 'aif', 'tta', 'mpc', 'shn']) {
        expect(audioSoorten, contains(s), reason: s);
      }
    });

    test('en het gewone werk ook', () {
      for (final s in ['flac', 'mp3', 'm4a', 'ogg', 'opus', 'aac', 'wma', 'alac']) {
        expect(audioSoorten, contains(s), reason: s);
      }
    });

    test('gesproken boeken en bladmuziek horen hier niet', () {
      // Een `.m4b` of een `.mid` tussen je platen is geen vondst maar rommel. Dit is een grens die
      // makkelijk per ongeluk verdwijnt bij "gewoon alles erin".
      for (final s in ['m4b', 'aax', 'mid', 'midi', 'cue', 'log', 'jpg', 'txt', 'mkv', 'mp4']) {
        expect(audioSoorten, isNot(contains(s)), reason: s);
      }
    });

    test('geen soort staat twee keer, met en zonder verlies', () {
      expect(verliesvrijeSoorten.intersection(verliesgevendeSoorten), isEmpty);
    });

    test('de extensies zijn precies de soorten met een punt ervoor', () {
      expect(audioExtensies.length, audioSoorten.length);
      for (final s in audioSoorten) {
        expect(audioExtensies, contains('.$s'));
      }
    });
  });

  group('de extensie uit een pad halen', () {
    test('gewoon', () {
      expect(extensieVan(r'C:\Muziek\a\01 - Bad.flac'), '.flac');
      expect(soortVan('/muziek/a/01 - Bad.FLAC'), 'flac');
    });

    test('een punt in een MAPnaam is geen extensie', () {
      // "R.E.M" is een artiest, geen bestandstype. Zonder deze regel heet dit bestand ".E.M/track"
      // en is het geen muziek meer.
      expect(extensieVan(r'C:\Muziek\R.E.M\track'), '');
      expect(extensieVan('/muziek/R.E.M/track'), '');
    });

    test('een bestand zonder punt', () {
      expect(extensieVan('track'), '');
      expect(soortVan('track'), '');
    });
  });

  group('de vijf plekken geven hetzelfde antwoord', () {
    test('een torrent met een DSD-rip erin wordt niet meer geweigerd', () {
      // Dit is letterlijk gemeten geweest: vier en een halve minuut wachten om te horen "geen
      // afspeelbare audio in deze torrent" — bij een DSD-rip van vinyl.
      const t = TorrentBestand(0, 'Bill Evans/01 - Waltz for Debby.dsf', 500000000);
      expect(t.isAudio, isTrue);
    });

    test('een .wv naast een .flac telt allebei als muziek', () {
      expect(isAudioBestand('x.wv'), isTrue);
      expect(isAudioBestand('x.flac'), isTrue);
      expect(isAudioBestand('x.nfo'), isFalse);
    });
  });

  group('wat verliesvrij is', () {
    test('een WavPack is geen lossy bestand', () {
      // Hier stond een eigen lijstje met "wavpack" erin, terwijl het bestand `.wv` heet. Daardoor
      // kreeg élke WavPack-rip het etiket lossy, en verdween hij uit het "Lossless"-filter.
      final q = qualityFromFile(name: 'iets.wv', ext: 'wv', isFlac: false);
      expect(q.lossless, isTrue);
    });

    test('en een DSD-rip evenmin', () {
      final q = qualityFromFile(name: 'iets.dsf', ext: 'dsf', isFlac: false);
      expect(q.lossless, isTrue);
    });

    test('maar een mp3 nog steeds wel', () {
      expect(qualityFromFile(name: 'iets.mp3', ext: 'mp3', isFlac: false).lossless, isFalse);
    });

    test('een m4a blijft onbeslist, want die doos zegt het niet', () {
      // ALAC en AAC dragen allebei deze naam. Raden zou het gouden merkje op een gewone AAC plakken.
      expect(isVerliesvrij('m4a'), isFalse);
    });

    test('met of zonder punt maakt niet uit', () {
      expect(isVerliesvrij('.flac'), isTrue);
      expect(isVerliesvrij('FLAC'), isTrue);
    });
  });
}
