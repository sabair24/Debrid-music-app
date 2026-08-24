/// Soulseek-treffers gebundeld tot gebruiker → map → nummers.
///
/// **Waarom hier een toets op staat.** Dit is een volgorde, en een volgorde is precies het soort
/// ding dat er op het scherm plausibel uitziet terwijl hij fout is. "De beste kwaliteit en per
/// grote boven" is een regel met drie trappen; of de tweede trap ooit aan bod komt, zie je met het
/// oog pas als je twee even goede bronnen naast elkaar hebt en toevallig op de grootte let.
///
/// Geen netwerk, geen widgets, geen toestel: dit zijn zuivere functies op een lijst die hier staat.
library;

import 'package:debridmusic/slsk_groepen.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een bestand zoals een peer het teruggeeft. Alleen wat deze toetsen aangaat is instelbaar.
SoulseekFile bestand(
  String gebruiker,
  String pad, {
  int grootte = 1000000,
  int? sampleRate,
  int? bitDepth,
  int? bitrate,
  bool vrij = true,
  int wachtrij = 0,
}) =>
    SoulseekFile(
      username: gebruiker,
      filename: pad,
      size: grootte,
      freeSlots: vrij,
      queueLength: wachtrij,
      bitrate: bitrate,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
    );

/// Een rangschikking die genoeg is om deze toetsen te schrijven zonder `quality.dart` na te bouwen:
/// lossless boven lossy, en binnen lossless telt de capaciteit. De echte app geeft
/// `kwaliteitsRang` mee — dat het van buiten komt is juist het punt.
int rangVanBestand(SoulseekFile f) {
  final sr = f.sampleRate, bd = f.bitDepth;
  if (f.isFlac && sr != null && bd != null) return 1000000 + sr * bd ~/ 1000;
  if (f.isFlac) return 1000000;
  return f.bitrate ?? 0;
}

int volgordeVanBestand(SoulseekFile a, SoulseekFile b) {
  final r = rangVanBestand(b) - rangVanBestand(a);
  if (r != 0) return r;
  return b.size.compareTo(a.size);
}

List<SlskGebruiker> groepeer(Iterable<SoulseekFile> files) =>
    groepeerSoulseek(files, rang: rangVanBestand, volgorde: volgordeVanBestand);

void main() {
  group('een pad in tweeën', () {
    test('backslashes en schuine strepen leveren dezelfde map', () {
      expect(mapVan(r'@@abc\Music\Backstreet Boys\Backstreets Back\03 Everybody.flac'),
          r'@@abc\Music\Backstreet Boys\Backstreets Back');
      expect(mapVan('@@abc/Music/Backstreet Boys/Backstreets Back/03 Everybody.flac'),
          r'@@abc\Music\Backstreet Boys\Backstreets Back');
    });

    test('een naam zonder map geeft een lege map', () {
      // Anders krijgt zo'n bestand een map die zijn eigen naam is, en staat er een albumkop boven
      // één los nummer.
      expect(mapVan('Everybody.flac'), '');
      expect(mapNaam(''), '');
    });

    test('alleen de laatste laag komt op het scherm', () {
      expect(mapNaam(r'@@abc\Music\Backstreet Boys\Backstreets Back'), 'Backstreets Back');
      expect(mapNaam('@@abc\\Muziek\\'), 'Muziek', reason: 'een slotstreep telt niet als laag');
    });
  });

  group('nummervolgorde', () {
    test('2 staat voor 10, en niet erna', () {
      // Dit is de hele reden dat er niet gewoon `compareTo` staat: alfabetisch zet "10" vóór "2"
      // en dan staat een album in een volgorde die niemand herkent.
      final namen = ['10 - Tien.flac', '2 - Twee.flac', '1 - Een.flac'];
      namen.sort(natuurlijkeVolgorde);
      expect(namen, ['1 - Een.flac', '2 - Twee.flac', '10 - Tien.flac']);
    });

    test('voorloopnullen maken geen verschil', () {
      expect(natuurlijkeVolgorde('03 x.flac', '3 x.flac'), 0);
    });

    test('hoofdletters tellen niet mee', () {
      final namen = ['b.flac', 'A.flac'];
      namen.sort(natuurlijkeVolgorde);
      expect(namen, ['A.flac', 'b.flac']);
    });

    test('gelijke namen blijven gelijk', () {
      expect(natuurlijkeVolgorde('a.flac', 'a.flac'), 0);
      expect(natuurlijkeVolgorde('', ''), 0);
    });
  });

  group('groeperen', () {
    test('dezelfde albumnaam bij twee gebruikers blijft twee gebruikers', () {
      // De gebruiker hoort bij de sleutel. Zou er alleen op mapnaam gegroepeerd worden, dan stonden
      // hier de nummers van twee vreemden door elkaar in één album — en een download bij de één is
      // geen download bij de ander.
      final g = groepeer([
        bestand('anna', r'@@a\Greatest Hits\01.flac'),
        bestand('bert', r'@@b\Greatest Hits\01.flac'),
      ]);
      expect(g.length, 2);
      expect(g.map((u) => u.naam).toSet(), {'anna', 'bert'});
      expect(g.every((u) => u.mappen.single.naam == 'Greatest Hits'), isTrue);
    });

    test('één gebruiker met twee mappen wordt één gebruiker met twee mappen', () {
      final g = groepeer([
        bestand('anna', r'@@a\Album Een\01.flac'),
        bestand('anna', r'@@a\Album Een\02.flac'),
        bestand('anna', r'@@a\Album Twee\01.flac'),
      ]);
      expect(g.single.mappen.length, 2);
      expect(g.single.aantal, 3);
    });

    test('nummers binnen een map staan op nummervolgorde', () {
      final g = groepeer([
        bestand('anna', r'@@a\Album\10 - Tien.flac'),
        bestand('anna', r'@@a\Album\2 - Twee.flac'),
      ]);
      expect(g.single.mappen.single.nummers.map((f) => f.displayName).toList(),
          ['2 - Twee.flac', '10 - Tien.flac']);
    });

    test('één los nummer meldt zich als los nummer', () {
      // Het scherm slaat de maplaag dan over — anders staat er een albumkop boven één regel.
      expect(groepeer([bestand('anna', r'@@a\Album\01.flac')]).single.losNummer, isTrue);
      expect(
          groepeer([
            bestand('anna', r'@@a\Album\01.flac'),
            bestand('anna', r'@@a\Album\02.flac'),
          ]).single.losNummer,
          isFalse);
    });

    test('slots en wachtrij komen van de peer, niet van het bestand', () {
      final g = groepeer([
        bestand('anna', r'@@a\Album\01.flac', vrij: false, wachtrij: 7),
        bestand('anna', r'@@a\Album\02.flac', vrij: false, wachtrij: 7),
      ]);
      expect(g.single.vrij, isFalse);
      expect(g.single.wachtrij, 7);
    });

    test('een lege lijst geeft een lege uitkomst en geen fout', () {
      expect(groepeer(const <SoulseekFile>[]), isEmpty);
    });
  });

  group('de volgorde: beste kwaliteit, en dan per grootte', () {
    test('24/96 boven 24/48 boven MP3', () {
      final g = groepeer([
        bestand('mp3man', r'@@c\Album\01.mp3', bitrate: 320),
        bestand('vierentwintig', r'@@a\Album\01.flac', sampleRate: 96000, bitDepth: 24),
        bestand('achtenveertig', r'@@b\Album\01.flac', sampleRate: 48000, bitDepth: 24),
      ]);
      expect(g.map((u) => u.naam).toList(), ['vierentwintig', 'achtenveertig', 'mp3man']);
    });

    test('bij gelijke kwaliteit staat de grootste bovenaan', () {
      // Dit is de trap die vandaag ontbrak: de losse lijst stopte bij de wachtrij, en dan was "per
      // grote boven" toeval.
      final g = groepeer([
        bestand('klein', r'@@a\Album\01.flac', sampleRate: 44100, bitDepth: 16, grootte: 20000000),
        bestand('groot', r'@@b\Album\01.flac', sampleRate: 44100, bitDepth: 16, grootte: 60000000),
      ]);
      expect(g.map((u) => u.naam).toList(), ['groot', 'klein']);
    });

    test('bij gelijke kwaliteit en grootte gaan vrije slots voor', () {
      final g = groepeer([
        bestand('wacht', r'@@a\Album\01.flac', sampleRate: 44100, bitDepth: 16, vrij: false, wachtrij: 4),
        bestand('vrij', r'@@b\Album\01.flac', sampleRate: 44100, bitDepth: 16),
      ]);
      expect(g.first.naam, 'vrij');
    });

    test('gelijkspel gaat op naam, zodat de lijst niet danst', () {
      // Zonder deze laatste trap is de volgorde die van binnenkomst, en die verschilt per
      // zoekopdracht — dan springen de rijen onder je vinger terwijl er niets veranderd is.
      final g = groepeer([
        bestand('zoe', r'@@z\Album\01.flac', sampleRate: 44100, bitDepth: 16),
        bestand('aap', r'@@a\Album\01.flac', sampleRate: 44100, bitDepth: 16),
      ]);
      expect(g.map((u) => u.naam).toList(), ['aap', 'zoe']);
    });

    test('de beste map van een gebruiker staat vooraan', () {
      final g = groepeer([
        bestand('anna', r'@@a\MP3-map\01.mp3', bitrate: 192),
        bestand('anna', r'@@a\FLAC-map\01.flac', sampleRate: 96000, bitDepth: 24),
      ]);
      expect(g.single.mappen.first.naam, 'FLAC-map');
      expect(g.single.beste.isFlac, isTrue, reason: 'het keurmerk in de kop hoort van de beste te komen');
    });
  });

  group('filteren gebeurt vóór groeperen', () {
    test('een gebruiker die niets overhoudt, komt niet in de lijst', () {
      // Zo werkt het scherm: eerst `QFilter.matches` over de nummers, dan pas groeperen. Andersom
      // zou er een lege kop blijven staan waar niets onder zit.
      final alles = [
        bestand('flacman', r'@@a\Album\01.flac', sampleRate: 44100, bitDepth: 16),
        bestand('mp3man', r'@@b\Album\01.mp3', bitrate: 320),
      ];
      final g = groepeer(alles.where((f) => f.isFlac));
      expect(g.single.naam, 'flacman');
    });
  });
}
