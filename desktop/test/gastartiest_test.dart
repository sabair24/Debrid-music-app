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

ChoiceTrack uitgave(String titel, {int? seconden, String positie = ''}) =>
    ChoiceTrack(positie, titel, seconden);

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

  group('het werkt beide kanten op', () {
    test('de gast staat in het BESTAND en niet op de uitgave', () {
      final lijst = [uitgave('Telephone', seconden: 221)];
      final c = matchAlbumTracks(
          lijst, [bestand('Telephone (feat. Beyoncé)', seconden: 221)], 'Lady Gaga');
      expect(gevonden(c), {'Telephone'});
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
