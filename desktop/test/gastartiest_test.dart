/// Een nummer met een gastartiest staat wél op de plaat.
///
/// **De klacht, op 31-08-2026, met een schermafdruk van *Dangerously in Love*.** Onder het kopje
/// "Niet op deze uitgave" stonden "Crazy In Love" en "Baby Boy" — twee van de bekendste nummers van
/// precies die plaat. *"en dan ook nog niet op deze opgave??? komaan??? dit is wel op deze opgave!"*
///
/// **Hoe dat kon.** De uitgave schrijft ze als "Crazy in Love (feat. JAY-Z)"; de rip liet de titel
/// kaal en zette de gast in het artiest-veld. De woordvergelijking telt "(feat. …)" met opzet mee —
/// daar kan een echt verschil in zitten, Adele's *30* heeft "Easy On Me" én "Easy On Me (With Chris
/// Stapleton)" — en dus haalde drie gedeelde woorden tegen zes gezette woorden vijftig procent, ver
/// onder de grens van vier vijfde.
///
/// **De rem is uniciteit, geen lagere drempel.** De gaststaart mag alleen weggedacht worden als de
/// kale titel aan beide kanten precies één keer voorkomt. Bij Adele vallen die twee rijen dan samen
/// en gebeurt er niets; bij Beyoncé is er maar één "Crazy in Love".
library;

import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alleen de ZIN, want daar gaan de toetsen hieronder over.
///
/// [waaromGeenPlaatsMet] geeft er sinds 03-09-2026 ook de rij van de uitgave bij, zodat "Titel
/// rechtzetten…" hetzelfde antwoord gebruikt als de regel op het scherm. Die rij wordt in
/// `titel_rechtzetten_test.dart` gemeten; hier blijft het bij de tekst.
String waarom(List<ChoiceTrack> official, Track t) => waaromGeenPlaatsMet(official, t).reden;

ChoiceTrack uitgave(String titel, {int? seconden, String positie = '', String credit = ''}) =>
    ChoiceTrack(positie, titel, seconden, artist: credit);

Track bestand(String titel, {int? seconden, String? artiest, String? pad}) => Track(
      path: pad ?? 'C:\\Muziek\\x\\${titel.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')}.flac',
      title: titel,
      artist: artiest ?? 'Beyoncé',
      album: 'Dangerously in Love',
      duration: seconden == null ? null : Duration(seconds: seconden),
    );

/// Welke rijen van de uitgave een bestand kregen, op titel.
Set<String> gevonden(AlbumCompleteness c) =>
    {for (final s in c.slots) if (s.index >= 0 && s.track != null) s.official!.title};

/// Wat er onder "Niet op deze uitgave" belandt.
List<String> weesjes(AlbumCompleteness c) =>
    [for (final s in c.slots) if (s.index < 0) s.track!.title];

void main() {
  group('de gemelde plaat', () {
    // De echte tracklijst zoals de catalogus hem schrijft, en de bestanden zoals de rip ze noemde.
    final lijst = [
      uitgave('Crazy in Love (feat. JAY-Z)', seconden: 236, positie: '1'),
      uitgave('Naughty Girl', seconden: 208, positie: '2'),
      uitgave('Baby Boy (feat. Sean Paul)', seconden: 244, positie: '3'),
      uitgave('Hip Hop Star', seconden: 220, positie: '4'),
    ];
    final mijne = [
      bestand('Crazy In Love', seconden: 235, artiest: 'Jay-Z'),
      bestand('Naughty Girl', seconden: 208),
      bestand('Baby Boy', seconden: 244, artiest: 'Sean Paul'),
    ];

    test('alle drie worden herkend', () {
      final c = matchAlbumTracks(lijst, mijne, 'Beyoncé');
      expect(gevonden(c), {
        'Crazy in Love (feat. JAY-Z)',
        'Naughty Girl',
        'Baby Boy (feat. Sean Paul)',
      });
    });

    test('en er staat niets meer onder "Niet op deze uitgave"', () {
      expect(weesjes(matchAlbumTracks(lijst, mijne, 'Beyoncé')), isEmpty);
    });

    test('wat er echt ontbreekt blijft ontbreken', () {
      final c = matchAlbumTracks(lijst, mijne, 'Beyoncé');
      expect(c.missing.map((s) => s.official!.title), ['Hip Hop Star']);
    });
  });

  group('de rem: alleen als er niets te verwarren valt', () {
    test('twee rijen die samenvallen zodra je de gast wegdenkt, blijven af', () {
      // Adele's 30. "Easy On Me" en het duet zijn twee opnames; welke van de twee dit ene bestand
      // is, valt niet te zeggen. Dan is niets doen het enige eerlijke antwoord.
      final lijst = [
        uitgave('Easy On Me', seconden: 224),
        uitgave('Easy On Me (With Chris Stapleton)', seconden: 224),
      ];
      final c = matchAlbumTracks(lijst, [bestand('Iets anders', seconden: 224)], 'Adele');
      expect(gevonden(c), isEmpty);
    });

    test('maar de rij die exact klopt wordt gewoon gepakt', () {
      final lijst = [
        uitgave('Easy On Me', seconden: 224),
        uitgave('Easy On Me (With Chris Stapleton)', seconden: 224),
      ];
      final c = matchAlbumTracks(lijst, [bestand('Easy On Me', seconden: 224)], 'Adele');
      expect(gevonden(c), {'Easy On Me'}, reason: 'de exacte titel gaat altijd voor');
    });

    test('twee kopieën van hetzelfde nummer blijven ook af', () {
      // Twee bestanden, allebei "Crazy In Love", allebei even lang, in verschillende mappen. Eentje
      // pakken zou een gok zijn tussen twee kopieën — en dan staat de andere ineens als weesje
      // onder de plaat alsof hij er niet op hoort.
      final lijst = [uitgave('Crazy in Love (feat. JAY-Z)', seconden: 236)];
      final c = matchAlbumTracks(
          lijst,
          [
            bestand('Crazy In Love', seconden: 236, pad: r'C:\Muziek\a\Crazy In Love.flac'),
            bestand('Crazy In Love', seconden: 236, pad: r'C:\Muziek\b\Crazy In Love.flac'),
          ],
          'Beyoncé');
      expect(gevonden(c), isEmpty);
      expect(weesjes(c), hasLength(2));
    });

    test('een duidelijk andere lengte telt nog steeds niet mee', () {
      // Een live-uitvoering van zes minuten is niet de albumversie, hoe gelijk de kale titel ook is.
      final lijst = [uitgave('Crazy in Love (feat. JAY-Z)', seconden: 236)];
      final c = matchAlbumTracks(lijst, [bestand('Crazy In Love', seconden: 400)], 'Beyoncé');
      expect(gevonden(c), isEmpty);
    });
  });

  group('MusicBrainz zet de gast NAAST de titel', () {
    // Dit is de vorm waarin de klacht op de telefoon terugkwam. MusicBrainz noemt de rij gewoon
    // "Crazy in Love" en zet "Beyoncé feat. JAY-Z" in de artiestcredit ernaast; de rip schreef hem
    // juist in de titel. Op de titel alleen is dat niet te herkennen — mét de credit wel.
    test('een bestand dat de gast in de titel draagt vindt zijn plaats', () {
      final lijst = [
        uitgave('Crazy in Love', seconden: 236, credit: 'Beyoncé feat. JAY-Z'),
        uitgave('Baby Boy', seconden: 244, credit: 'Beyoncé feat. Sean Paul'),
      ];
      final c = matchAlbumTracks(
          lijst,
          [
            bestand('Crazy in Love (feat. Jay-Z)', seconden: 235),
            bestand('Baby Boy (feat. Sean Paul)', seconden: 244),
          ],
          'Beyoncé');
      expect(gevonden(c), {'Crazy in Love', 'Baby Boy'});
      expect(weesjes(c), isEmpty);
    });

    test('ook als de gast in het ARTIEST-veld staat en niet in de titel', () {
      final lijst = [uitgave('Crazy in Love', seconden: 236, credit: 'Beyoncé feat. JAY-Z')];
      final c = matchAlbumTracks(
          lijst, [bestand('Crazy in Love', seconden: 236, artiest: 'Beyoncé feat. Jay-Z')], 'Beyoncé');
      expect(gevonden(c), {'Crazy in Love'});
    });

    test('maar niet als de uitgave die gast NIET noemt', () {
      // Adele's 30, met de credit erbij: de rij "Easy on Me" staat op naam van Adele alleen. Het
      // duet is dus een andere opname, en dat is nu een feit in plaats van een gok.
      final lijst = [uitgave('Easy on Me', seconden: 224, credit: 'Adele')];
      final c = matchAlbumTracks(
          lijst, [bestand('Easy On Me (With Chris Stapleton)', seconden: 224)], 'Adele');
      expect(gevonden(c), isEmpty);
    });

    test('en niet als de uitgave maar één van de twee gasten noemt', () {
      final lijst = [uitgave('Song', seconden: 200, credit: 'X feat. A')];
      final c = matchAlbumTracks(lijst, [bestand('Song (feat. A & B)', seconden: 200)], 'X');
      expect(gevonden(c), isEmpty);
    });

    test('zonder credit gebeurt er niets, precies zoals voorheen', () {
      // Discogs levert dit veld hier niet. Geen bewijs, dus geen treffer.
      final lijst = [uitgave('Crazy in Love', seconden: 236)];
      final c = matchAlbumTracks(
          lijst, [bestand('Crazy in Love (feat. Jay-Z)', seconden: 236)], 'Beyoncé');
      expect(gevonden(c), isEmpty);
    });
  });

  group('maar het loopt maar één kant op', () {
    test('een credit die alleen in het BESTAND staat wordt niet weggedacht', () {
      // Dit is de andere kant, en die is niet veilig. Noemt de uitgave "Easy on Me" en heet jouw
      // bestand "Easy On Me (With Chris Stapleton)", dan heb je iets wat die uitgave NIET noemt —
      // Adele's 30 heeft de solo en het duet allebei, met bijna dezelfde lengte. Het duet op de rij
      // van de albumversie leggen zou het ene verbergen en het andere ten onrechte meetellen.
      //
      // Dit stond al als toets in completeness_test.dart, en die zakte toen deze pas nog beide
      // kanten op liep. Van buiten zijn de twee gevallen niet te onderscheiden, dus er valt niets
      // slims te bedenken: de tracklijst van de persing is de autoriteit, en dus mag de credit
      // alleen daarvan af.
      final lijst = [uitgave('Easy on Me', seconden: 224)];
      final c = matchAlbumTracks(
          lijst, [bestand('Easy On Me (With Chris Stapleton)', seconden: 224)], 'Adele');
      expect(gevonden(c), isEmpty);
    });

    test('een bestand met een eigen credit vult ook geen kale uitgaverij', () {
      final lijst = [uitgave('Telephone', seconden: 221)];
      final c = matchAlbumTracks(
          lijst, [bestand('Telephone (feat. Beyoncé)', seconden: 221)], 'Lady Gaga');
      expect(gevonden(c), isEmpty);
    });

    test('een versiemerk blijft wél tellen', () {
      // "(Radio Edit)" is geen gastartiest maar een andere opname, en `zonderFeat` laat die staan.
      // Zonder deze regel zou een radio-edit stilletjes de albumversie invullen.
      final lijst = [uitgave('Crazy in Love (feat. JAY-Z)', seconden: 236)];
      final c = matchAlbumTracks(
          lijst, [bestand('Crazy In Love (Radio Edit)', seconden: 236)], 'Beyoncé');
      expect(gevonden(c), isEmpty);
    });
  });

  group('de app zegt waarom een bestand geen plaats kreeg', () {
    // "Niet op deze uitgave" is een uitkomst, geen uitleg. Het heeft drie ronden raden op
    // schermafdrukken gekost om erachter te komen dat de nummerrij de "(feat. …)" wegtekent en dat
    // daar het verschil zat. Eén regel onder de rij was elke keer genoeg geweest.
    test('een andere lengte wordt met beide tijden benoemd', () {
      final r = waarom(
          [uitgave('Crazy in Love', seconden: 236)], bestand('Crazy in Love', seconden: 400));
      expect(r, contains('3:56'));
      expect(r, contains('6:40'));
    });

    test('een titel die de uitgave niet kent', () {
      final r = waarom([uitgave('Halo', seconden: 261)], bestand('Iets Anders'));
      expect(r, contains('Iets Anders'));
    });

    test('de RUWE titel komt erin, want de rij tekent de gast weg', () {
      // Dit is de regel die het hele misverstand had voorkomen: op het scherm stond "Crazy in Love",
      // in het bestand stond "Crazy in Love (feat. Jay-Z)".
      final r = waarom([uitgave('Crazy in Love', seconden: 236)],
          bestand('Crazy in Love (feat. Jay-Z)', seconden: 236));
      expect(r, contains('feat. Jay-Z'));
    });

    test('een nummer dat twee keer op de uitgave staat', () {
      final r = waarom(
          [uitgave('Halo', seconden: 261), uitgave('Halo', seconden: 261)], bestand('Halo'));
      expect(r, contains('2 keer'));
    });

    test('zonder tracklijst wordt er niets beweerd', () {
      expect(waarom(const [], bestand('Halo')), contains('geen tracklijst'));
    });
  });

  group('wat er niet verandert', () {
    test('zonder gastartiesten werkt alles zoals het werkte', () {
      final lijst = [uitgave('Halo', seconden: 261), uitgave('Sweet Dreams', seconden: 208)];
      final c = matchAlbumTracks(
          lijst, [bestand('Halo', seconden: 261), bestand('Sweet Dreams', seconden: 208)], 'Beyoncé');
      expect(gevonden(c), {'Halo', 'Sweet Dreams'});
    });

    test('een bestand dat er echt niet op staat blijft een weesje', () {
      final lijst = [uitgave('Halo', seconden: 261)];
      final c = matchAlbumTracks(lijst, [bestand('Iets Heel Anders', seconden: 200)], 'Beyoncé');
      expect(weesjes(c), ['Iets Heel Anders'], reason: 'muziek die je hebt mag nooit verdwijnen');
    });
  });
}
