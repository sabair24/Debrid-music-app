/// Het zoekscherm onthoudt waar je was.
///
/// **Het gemelde geval.** Zoek op "rihanna", tik een nummer aan om te downloaden, ga naar de speler
/// om te horen of het goed is, en kom terug: alles weg. Opnieuw typen, opnieuw wachten, opnieuw
/// scrollen — en dat elke keer dat je iets wilt controleren.
///
/// De schil gooit een sectie weg zodra je naar een andere gaat, dus het scherm begon elke keer leeg.
/// Wat hier getoetst wordt is het geheugen dat daar tussen zit: een statische bak zonder widget, en
/// daarmee het enige stuk van deze weg dat vóór het uitgeven na te meten is.
///
/// De derde groep is de belangrijkste en de minst voor de hand liggende: het volgnummer van de
/// zoekopdracht stond eerst in de staat van het SCHERM, en begon dus bij elke wissel weer bij nul.
/// Een oudere, nog lopende zoekopdracht werd daardoor opnieuw geldig verklaard en kon over een
/// nieuwere heen vallen — precies de fout die je nooit ziet gebeuren maar wel het verkeerde
/// resultaat oplevert.
library;

import 'package:debridmusic/quality.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/zoek_geheugen.dart';
import 'package:flutter_test/flutter_test.dart';

SoulseekFile _bestand(String naam) =>
    SoulseekFile(username: 'peer', filename: naam, size: 1000);

void main() {
  setUp(ZoekGeheugen.wis);
  tearDown(ZoekGeheugen.wis);

  group('een leeg geheugen opent geen lijst die er niet is', () {
    test('vers is alles leeg en staat Bladeren voor', () {
      expect(ZoekGeheugen.tab, ZoekTab.bladeren);
      expect(ZoekGeheugen.vraag, '');
      expect(ZoekGeheugen.slsk, isEmpty);
      expect(ZoekGeheugen.torrents, isEmpty);
      expect(ZoekGeheugen.artiesten, isEmpty);
      expect(ZoekGeheugen.tidalNummers, isEmpty);
      expect(ZoekGeheugen.getypt, isNull);
      expect(ZoekGeheugen.filter, QFilter.all);
      expect(ZoekGeheugen.slskOpen, isEmpty);
    });
  });

  group('de rondgang die het scherm maakt', () {
    test('wat erin gaat komt er hetzelfde uit', () {
      // Dit is letterlijk wat er gebeurt: het scherm schrijft bij het weggaan, en de volgende
      // instantie begint bij deze waarden.
      ZoekGeheugen.tab = ZoekTab.direct;
      ZoekGeheugen.vraag = 'rihanna';
      ZoekGeheugen.getypt = 'rihanna';
      ZoekGeheugen.filter = QFilter.lossless;
      ZoekGeheugen.slsk = [_bestand(r'@@p\Rihanna\01 Diamonds.flac')];
      ZoekGeheugen.slskOpen.addAll({'Ben_DeRoy', 'koalabeer'});

      expect(ZoekGeheugen.tab, ZoekTab.direct);
      expect(ZoekGeheugen.vraag, 'rihanna');
      expect(ZoekGeheugen.getypt, 'rihanna');
      expect(ZoekGeheugen.filter, QFilter.lossless);
      expect(ZoekGeheugen.slsk.single.filename, contains('Diamonds'));
      expect(ZoekGeheugen.slskOpen, {'Ben_DeRoy', 'koalabeer'});
    });

    test('wissen zet ook het tabblad en het filter terug', () {
      // Zou dit blijven staan, dan opende een verse app op Direct zoeken met een filter dat je nooit
      // gekozen hebt.
      ZoekGeheugen.tab = ZoekTab.tidal;
      ZoekGeheugen.filter = QFilter.hires;
      ZoekGeheugen.wis();
      expect(ZoekGeheugen.tab, ZoekTab.bladeren);
      expect(ZoekGeheugen.filter, QFilter.all);
    });

    test('de open gebruikers gaan op NAAM, niet op plaats', () {
      // De volgorde verandert terwijl er resultaten binnenstromen. Op plaatsnummer zou je na
      // terugkomst een ándere gebruiker opengeklapt zien staan dan die je aantikte.
      ZoekGeheugen.slskOpen.add('Nazgul303');
      expect(ZoekGeheugen.slskOpen.contains('Nazgul303'), isTrue);
      expect(ZoekGeheugen.slskOpen.contains('0'), isFalse);
    });
  });

  group('DE KERN: een oudere zoekopdracht valt niet over een nieuwere heen', () {
    test('een ronde is geldig tot er een nieuwe begint', () {
      final eerste = ZoekGeheugen.nieuweRonde();
      expect(ZoekGeheugen.geldig(eerste), isTrue);

      final tweede = ZoekGeheugen.nieuweRonde();
      expect(ZoekGeheugen.geldig(tweede), isTrue);
      expect(ZoekGeheugen.geldig(eerste), isFalse,
          reason: 'de trage vorige zoekopdracht mag hier niets meer neerzetten');
    });

    test('het volgnummer loopt door over een schermwissel heen', () {
      // Hier zat de fout. Het volgnummer stond in de staat van het scherm; die begint bij een
      // sectiewissel opnieuw bij nul, en dan is het nummer van de vorige zoekopdracht ineens weer
      // het geldige nummer. Statisch loopt hij gewoon door, en dat is het hele verschil.
      final oud = ZoekGeheugen.nieuweRonde();
      // "Schermwissel": een nieuwe instantie leest dezelfde teller, hij begint niet opnieuw.
      expect(ZoekGeheugen.gen, oud);
      final na = ZoekGeheugen.nieuweRonde();
      expect(na, greaterThan(oud));
      expect(ZoekGeheugen.geldig(oud), isFalse);
    });

    test('nul is geen geldige ronde zodra er gezocht is', () {
      // Een instantie die bij nul begint mag niet meeliften op een lopende zoekopdracht.
      ZoekGeheugen.nieuweRonde();
      expect(ZoekGeheugen.geldig(0), isFalse);
    });
  });
}
