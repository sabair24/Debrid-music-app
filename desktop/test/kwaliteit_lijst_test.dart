/// Wat komt er in de Kwaliteit-lijst, en in welke volgorde?
///
/// De vraag die deze lijst beantwoordt is niet "wat is betrapt" maar "waar valt iets te winnen". Dat
/// zijn twee verschillende verzamelingen, en het verschil is de hele reden dat de lijst bestaat: een
/// opgeblazen bestand — 16 bits in een 24-bits jas — IS al cd-kwaliteit, en opnieuw downloaden geeft
/// exact hetzelfde geluid terug. Zet je die er toch in, dan beloof je werk dat niets oplevert.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

Track _t(String pad, {String artist = 'A', String title = 'T', String album = 'Alb', int no = 1,
    int total = 0, int? year}) =>
    Track(
      path: pad,
      title: title,
      artist: artist,
      album: album,
      trackNo: no,
      trackTotal: total,
      year: year,
      duration: const Duration(seconds: 200),
      isFlac: true,
    );

/// Een oordeel met een muur erin, op [hz].
Echtheidsoordeel _afgekapt(double hz) => Echtheidsoordeel(
      bits: Bitdiepte.spreektNietTegen,
      boven: Bovenband.onbekend,
      band: Bandbreedte.afgekapt,
      afkapHz: hz,
      wandDb: 45,
      vensters: 32,
    );

/// Opgeblazen, maar zonder muur — dus geen verlies, alleen lucht.
Echtheidsoordeel get _opgeblazen => const Echtheidsoordeel(
      bits: Bitdiepte.opgeblazen,
      boven: Bovenband.leeg,
      band: Bandbreedte.doorlopend,
      gebruikteBits: 16,
      vensters: 32,
    );

Echtheidsoordeel get _schoon => const Echtheidsoordeel(
      bits: Bitdiepte.spreektNietTegen,
      boven: Bovenband.vol,
      band: Bandbreedte.doorlopend,
      vensters: 32,
    );

void main() {
  late Directory scratch;
  late LibraryStore lib;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('dm_kwal_');
    setAppDirForTest(scratch.path);
    resetEchtheidVoorTest();
    await laadEchtheid();
    lib = LibraryStore()..configDirOverride = '${scratch.path}${Platform.pathSeparator}_cfg';
  });

  tearDown(() {
    resetEchtheidVoorTest();
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('wie komt er in de lijst', () {
    test('alleen de afgekapte, en het ergste bovenaan', () async {
      final zacht = _t(r'D:\m\zacht.flac', title: 'zacht');
      final hard = _t(r'D:\m\hard.flac', title: 'hard');
      final midden = _t(r'D:\m\midden.flac', title: 'midden');
      lib.tracks.addAll([zacht, hard, midden]);

      await onthoudOordeel(zacht.path, _afgekapt(20900));
      await onthoudOordeel(hard.path, _afgekapt(15600));
      await onthoudOordeel(midden.path, _afgekapt(17200));

      final uit = lib.uitMp3Bestanden();
      expect(uit.map((e) => e.track.title), ['hard', 'midden', 'zacht'],
          reason: 'de laagste muur is het meeste verlies en hoort bovenaan');
    });

    test('een opgeblazen bestand hoort er NIET in — dat is al cd-kwaliteit', () async {
      final blaas = _t(r'D:\m\blaas.flac', title: 'blaas');
      final echt = _t(r'D:\m\echt.flac', title: 'echt');
      final mp3 = _t(r'D:\m\mp3.flac', title: 'mp3');
      lib.tracks.addAll([blaas, echt, mp3]);

      await onthoudOordeel(blaas.path, _opgeblazen);
      await onthoudOordeel(echt.path, _schoon);
      await onthoudOordeel(mp3.path, _afgekapt(19000));

      // De bredere lijst ziet er twee; deze lijst maar één. Dat verschil is het hele punt.
      expect(lib.betrapteBestanden().length, 2);
      expect(lib.uitMp3Bestanden().map((e) => e.track.title), ['mp3']);
    });

    test('een ongemeten bestand komt er niet in', () {
      lib.tracks.add(_t(r'D:\m\onbekend.flac'));
      expect(lib.uitMp3Bestanden(), isEmpty);
    });

    test('een oordeel zonder afkapfrequentie laat de lijst niet omvallen', () async {
      // Kan niet ontstaan door de huidige meting, maar wél door een oordelenbestand van een oudere
      // versie op schijf. Eén rij verkeerd gesorteerd is dan het juiste gedrag; een crash niet.
      final raar = _t(r'D:\m\raar.flac', title: 'raar');
      final normaal = _t(r'D:\m\normaal.flac', title: 'normaal');
      lib.tracks.addAll([raar, normaal]);
      await onthoudOordeel(
          raar.path,
          const Echtheidsoordeel(
              bits: Bitdiepte.onbekend,
              boven: Bovenband.onbekend,
              band: Bandbreedte.afgekapt,
              vensters: 32));
      await onthoudOordeel(normaal.path, _afgekapt(18000));

      expect(lib.uitMp3Bestanden().length, 2);
      expect(lib.uitMp3Bestanden().first.track.title, 'raar');
    });
  });

  group('waarom een rij op deze lijst staat', () {
    test('de afkap staat vooraan, ook als het bestand OOK opgeblazen is', () {
      // Precies wat er misging op het scherm: naast een chipje met 17,2 kHz stond "opgeschaald,
      // geen echte hi-res", en dan lijkt de rij over iets anders te gaan dan waarom hij er staat.
      const beide = Echtheidsoordeel(
        bits: Bitdiepte.opgeblazen,
        boven: Bovenband.leeg,
        band: Bandbreedte.afgekapt,
        gebruikteBits: 16,
        afkapHz: 17200,
        wandDb: 45,
        vensters: 32,
      );
      expect(waarom(beide), startsWith('zegt meer dan 16 bits'));
      expect(waaromAfkap(beide), startsWith('harde afkap op 17.2 kHz'));
      // en de tweede bevinding gaat niet verloren
      expect(waaromAfkap(beide), contains('16 bits'));
    });

    test('opgeschaald én afgekapt noemt allebei, afkap eerst', () {
      const o = Echtheidsoordeel(
        bits: Bitdiepte.spreektNietTegen,
        boven: Bovenband.leeg,
        band: Bandbreedte.afgekapt,
        afkapHz: 19100,
        wandDb: 45,
        vensters: 32,
      );
      expect(waaromAfkap(o), startsWith('harde afkap op 19.1 kHz'));
      expect(waaromAfkap(o), contains('opgeschaald'));
    });

    test('zonder afkap valt hij terug op de gewone uitleg', () {
      expect(waaromAfkap(_opgeblazen), waarom(_opgeblazen));
      expect(waaromAfkap(_schoon), waarom(_schoon));
    });
  });

  group('welke tags de vervanger erft', () {
    test('de tags komen van het bestand dat vervangen wordt, niet van de peer', () {
      final t = _t(r'D:\m\x.flac',
          artist: 'Stromae', title: 'Papaoutai', album: 'Racine Carrée', no: 2, total: 13, year: 2013);
      lib.tracks.add(t);

      final tags = lib.tagsVoorVervanger(t);
      expect(tags.title, 'Papaoutai');
      expect(tags.artist, 'Stromae');
      expect(tags.album, 'Racine Carrée');
      expect(tags.trackNo, 2);
      expect(tags.trackTotal, 13);
      expect(tags.year, 2013);
    });

    test('met tracktotaal of jaartal geldt de tagset als gezaghebbend', () {
      // Dit is wat `placeFileDetailed` laat zeggen "dit pad IS de identiteit" — en dus wat ervoor
      // zorgt dat de vervanger OP het oude bestand landt in plaats van ernaast.
      expect(lib.tagsVoorVervanger(_t(r'D:\m\a.flac', total: 13)).isAuthoritative, isTrue);
      expect(lib.tagsVoorVervanger(_t(r'D:\m\b.flac', year: 1995)).isAuthoritative, isTrue);
    });

    test('zonder allebei is de tagset NIET gezaghebbend — dat is de bekende grens', () {
      // Geen fout, wel een grens die vast moet liggen: dan valt het filen terug op zijn gewone
      // gelijkenistoets, en kan de vervanging naast het origineel belanden in plaats van erop.
      // Precies zoals elke andere download op zo'n bestand zich vandaag ook gedraagt.
      final kaal = lib.tagsVoorVervanger(_t(r'D:\m\kaal.flac'));
      expect(kaal.isAuthoritative, isFalse);
      expect(kaal.vanBestand, isFalse, reason: 'ze komen niet uit het gedownloade bestand zelf');
    });
  });
}
