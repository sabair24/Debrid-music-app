/// De juiste OPNAME vinden, niet alleen het juiste nummer.
///
/// **Het gemelde geval.** Op *My Songs* van Sting staat "Fields of Gold (My Songs Version)" — een
/// heropname uit 2019. Wie die aantikte kreeg steevast de plaat uit 1993, en er was geen enkele weg
/// naar de heropname. Twee dingen werkten tegen elkaar in:
///
/// 1. De zoekopdracht viel van de volledige titel in één stap terug op de eerste twee woorden,
///    "Sting Fields" — de titel kwijt, dus de lijst ging over iets anders.
/// 2. De titelvergelijking keek alleen naar de BESTANDSNAAM, en binnen het album *My Songs* heet
///    dat bestand bij iedereen gewoon `07 Fields of Gold.flac`. Het merk staat één maplaag hoger.
///
/// Beide zijn zuivere rekenkunde, dus beide zijn hier na te meten zonder toestel en zonder netwerk.
library;

import 'package:debridmusic/organize.dart';
import 'package:debridmusic/zoekladder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('de zoekladder', () {
    test('de trede die ontbrak: dezelfde vraag zonder de haakjes', () {
      // Dit is de kern. Zonder deze middelste trede sprong de app van de volledige titel naar
      // "Sting Fields", en dan gaat de lijst over een ander nummer.
      final trappen = zoekLadder('Sting Fields of Gold (My Songs Version)');
      expect(trappen, [
        'Sting Fields of Gold (My Songs Version)',
        'Sting Fields of Gold',
        'Sting Fields',
      ]);
    });

    test('zonder haakjes blijft het bij twee treden', () {
      expect(zoekLadder('Sting Fields of Gold'), ['Sting Fields of Gold', 'Sting Fields']);
    });

    test('een korte vraag heeft geen laatste redmiddel nodig', () {
      expect(zoekLadder('Sting Roxanne'), ['Sting Roxanne']);
    });

    test('een titel die HELEMAAL tussen haakjes staat wordt geen lege vraag', () {
      // "(Reprise)" en "(Everything I Do) I Do It for You" bestaan allebei echt.
      expect(zoekLadder('(Reprise)'), ['(Reprise)']);
      expect(zoekLadder('Bryan Adams (Everything I Do) I Do It for You').first,
          'Bryan Adams (Everything I Do) I Do It for You');
      expect(zoekLadder('Bryan Adams (Everything I Do) I Do It for You'),
          contains('Bryan Adams I Do It for You'));
    });

    test('niets in, niets uit', () {
      expect(zoekLadder('   '), isEmpty);
      expect(zoekLadder(''), isEmpty);
    });

    test('dubbele spaties leveren geen dubbele treden', () {
      expect(zoekLadder('Sting   Fields  of  Gold'), ['Sting Fields of Gold', 'Sting Fields']);
    });

    test('DE KERN: de twee precieze treden gaan SAMEN de deur uit', () {
      // Het gemelde geval. Via het menu "Zoeken met Soulseek" op *Plaza – Yo-Yo (Dance Version)*
      // gaf de eerste trede dertien treffers, dus stopte de ladder daar — en werd "Plaza Yo-Yo"
      // nooit verstuurd. Wie zélf "yo-yo dance version" intikte kreeg tientallen treffers, met een
      // echte 24/96 ertussen. Dertien is "iets", maar het is niet wat er te halen valt.
      //
      // Ze gaan als losse tickets naar dezelfde sessie, dus twee vragen kosten hetzelfde als één.
      expect(zoekRondes('Plaza Yo-Yo (Dance Version)').first,
          ['Plaza Yo-Yo (Dance Version)', 'Plaza Yo-Yo']);
    });

    test('de artiest alleen blijft een APARTE ronde', () {
      // Anders staat de lijst vol met ander werk van dezelfde artiest. Deze ronde gaat alleen de
      // deur uit als de eerste helemaal niets opleverde.
      final rondes = zoekRondes('Sting Fields of Gold (My Songs Version)');
      expect(rondes.length, 2);
      expect(rondes.first, ['Sting Fields of Gold (My Songs Version)', 'Sting Fields of Gold']);
      expect(rondes.last, ['Sting Fields']);
    });

    test('zonder haakjes is de eerste ronde gewoon één vraag', () {
      expect(zoekRondes('Sting Fields of Gold'), [
        ['Sting Fields of Gold'],
        ['Sting Fields'],
      ]);
    });

    test('een korte vraag is één ronde van één vraag', () {
      expect(zoekRondes('Sting Roxanne'), [
        ['Sting Roxanne'],
      ]);
    });

    test('de rondes en de ladder blijven hetzelfde zeggen', () {
      // De ladder is nu letterlijk de rondes achter elkaar. Zou dat uit elkaar lopen, dan gaat er
      // een trede stilletjes verloren.
      for (final v in [
        'Plaza Yo-Yo (Dance Version)',
        'Sting Fields of Gold (My Songs Version)',
        'Sting Roxanne',
        '(Reprise)',
        '',
      ]) {
        expect(zoekRondes(v).expand((r) => r).toList(), zoekLadder(v), reason: v);
      }
    });

    test('er wordt gemeld zodra de lijst over een andere vraag gaat', () {
      expect(ruimerGezocht('Sting Fields of Gold (My Songs Version)', 'Sting Fields of Gold'),
          isTrue);
      expect(ruimerGezocht('Sting Fields of Gold', 'Sting Fields of Gold'), isFalse,
          reason: 'op de eerste trede valt er niets te melden');
      expect(ruimerGezocht('  Sting Fields of Gold  ', 'Sting Fields of Gold'), isFalse,
          reason: 'spaties eromheen zijn geen andere vraag');
    });
  });

  group('de map als bewijs voor de versie', () {
    const map2019 = r'@@peer\Sting\Sting - My Songs (2019)\07 Fields of Gold.flac';
    const map1993 = r"@@peer\Sting\Ten Summoners Tales\06 Fields of Gold.flac";

    test('"(My Songs Version)" wordt bewezen door een map die My Songs heet', () {
      expect(versieVolgtUitMap('Fields of Gold (My Songs Version)', map2019), isTrue);
    });

    test('en niet door een map die iets anders heet', () {
      expect(versieVolgtUitMap('Fields of Gold (My Songs Version)', map1993), isFalse);
    });

    test('"(Live)" bewijst zichzelf nergens mee, ook niet in die map', () {
      // Hier zit de veiligheid. Van "live" blijft na het generieke woord niets over om aan de map te
      // toetsen, dus er valt niets te bewijzen — en een live-opname is een andere opname, waar hij
      // ook ligt.
      expect(versieVolgtUitMap('Fields of Gold (Live)', map2019), isFalse);
      expect(versieVolgtUitMap('Fields of Gold (Radio Edit)', map2019), isFalse);
    });

    test('een titel zonder merk heeft niets te bewijzen', () {
      expect(versieVolgtUitMap('Fields of Gold', map2019), isFalse);
    });

    test('zonder mappen is er geen bewijs', () {
      expect(versieVolgtUitMap('Fields of Gold (My Songs Version)', 'Fields of Gold.flac'), isFalse);
    });
  });

  group('fileOffersTitle op het gemelde Sting-geval', () {
    // De officiële looptijden van de twee opnames liggen ver genoeg uit elkaar om als tweede slot te
    // dienen; de getallen hieronder staan voor die twee.
    const titel = 'Fields of Gold (My Songs Version)';
    const duurHeropname = 255;

    test('de kopie uit de map My Songs telt mee, ook al zegt de bestandsnaam niets', () {
      // Dít is wat er miste. Binnen dat album heet het bestand gewoon "07 Fields of Gold.flac", dus
      // op de bestandsnaam alleen werd juist de goede kopie geweigerd.
      expect(
          fileOffersTitle(titel, duurHeropname, 'Sting',
              r'@@peer\Sting\Sting - My Songs (2019)\07 Fields of Gold.flac', 262),
          isTrue);
    });

    test('de plaat uit 1993 telt NIET mee', () {
      expect(
          fileOffersTitle(titel, duurHeropname, 'Sting',
              r'@@peer\Sting\Ten Summoners Tales\06 Fields of Gold.flac', 219),
          isFalse);
    });

    test('een los bestand zonder map telt ook niet mee', () {
      // Geen mappen, geen bewijs — en dan blijft het merk drie woorden die het bestand niet heeft.
      expect(fileOffersTitle(titel, duurHeropname, 'Sting', r'@@peer\Fields of Gold.flac', 255),
          isFalse);
    });

    test('een live-opname in diezelfde map telt niet mee', () {
      expect(
          fileOffersTitle('Fields of Gold (Live)', duurHeropname, 'Sting',
              r'@@peer\Sting\Sting - My Songs (2019)\07 Fields of Gold.flac', 262),
          isFalse);
    });

    test('de looptijd blijft het tweede slot', () {
      // De map klopt, de naam klopt, maar dit duurt bijna een minuut langer: dat is geen heropname
      // maar iets anders. Zonder deze grens zou de map alles doorlaten wat er toevallig in ligt.
      expect(
          fileOffersTitle(titel, duurHeropname, 'Sting',
              r'@@peer\Sting\Sting - My Songs (2019)\07 Fields of Gold.flac', 312),
          isFalse);
    });

    test('een gewone titel zonder merk werkt precies als voorheen', () {
      expect(
          fileOffersTitle('Fields of Gold', 219, 'Sting',
              r'@@peer\Sting\Ten Summoners Tales\06 Fields of Gold.flac', 219),
          isTrue);
    });
  });
}
