/// Afwisseling in een radio: niet de hele tijd dezelfde artiest, en het origineel als je het hebt.
///
/// Gemeten op 26-09-2026, radio vanaf "Freak Out" van 2 Fabiola: Deezer levert voor de zaadartiest
/// vijftien toppers plus een handvol uit de artiestenradio, dus een derde van het plan was 2 Fabiola —
/// twee keer vlak na elkaar. Saber: *"ik hoor nu al heel de tijd 2fabiola, mag maar niet heel de
/// tijd."* En de eigen muziek die een plek vulde was niet altijd wat er gevraagd werd: je eigen
/// "Freak Out ('97 Remix)" op de plek van "Freak Out", de albumversie van Move On Baby (4:51) op de
/// plek van de single (3:40).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/radiokeuze.dart';

/// Wie er achter elkaar klinkt, in de volgorde die [spreidArtiesten] kiest.
List<String> rij(List<String> artiesten,
        {String? zaad,
        List<String> al = const [],
        List<String> ervoor = const [],
        int afstand = kArtiestAfstand,
        int maxPerArtiest = kMaxPerArtiest}) =>
    [
      for (final i in spreidArtiesten(artiesten,
          zaad: zaad, al: al, ervoor: ervoor, afstand: afstand, maxPerArtiest: maxPerArtiest))
        artiesten[i]
    ];

/// Het mechanisme met de getallen van vóór 21-10-2026 (afstand vier, drie per artiest), zodat het met
/// een handvol regels te volgen blijft.
const klein = (afstand: 4, max: 3);

/// De kleinste afstand tussen twee keer dezelfde artiest.
int kleinsteAfstand(List<String> rij) {
  var kleinst = 1 << 30;
  final laatst = <String, int>{};
  for (var i = 0; i < rij.length; i++) {
    final a = artiestSleutel(rij[i]);
    final v = laatst[a];
    if (v != null && i - v < kleinst) kleinst = i - v;
    laatst[a] = i;
  }
  return kleinst;
}

void main() {
  group('het plafond per artiest', () {
    test('DE KERN: elke artiest één keer per vijftig, ook de artiest waarop de radio startte', () {
      // De radio vanaf Sabrina Carpenter — Taste, 20-10-2026 22:17, in de volgorde waarin hij landde.
      // Saber: "variatie is belangrijk, of mag terugkerend zijn maar na 50 liedjes".
      const sabrina = 'Sabrina Carpenter', zara = 'Zara Larsson';
      final artiesten = [
        sabrina, sabrina, 'Madison Beer', zara, 'Reneé Rapp', 'Ashe', 'Charlie Puth', sabrina,
        'Ariana Grande', zara, 'Olivia Rodrigo', 'Tate McRae', 'Ashe', 'Mckenna Grace', 'Maisie Peters',
        zara, 'Reneé Rapp', sabrina, 'Tyla feat. Zara Larsson', 'Charlie Puth',
      ];
      final uit = rij(artiesten, zaad: sabrina, al: [sabrina], ervoor: [sabrina]);
      expect(uit.where((a) => a == sabrina), isEmpty, reason: 'Taste klonk net; vier keer werd nul');
      expect(uit.where((a) => a == zara), hasLength(1), reason: 'drie keer werd één');
      for (final a in ['Reneé Rapp', 'Ashe', 'Charlie Puth']) {
        expect(uit.where((x) => x == a), hasLength(1), reason: a);
      }
      expect(uit, contains('Tyla feat. Zara Larsson'), reason: 'een gastrol is een nummer van Tyla');
    });

    test('DE KERN: een lange lijst houdt één per vijftig over, niet één in totaal', () {
      // Een radio uit een zin: driehonderd nummers, zestig artiesten met elk vijf.
      final artiesten = [for (var r = 0; r < 5; r++) for (var a = 0; a < 60; a++) 'Artiest $a'];
      final uit = rij(artiesten);
      expect(uit, hasLength(300), reason: 'zes per artiest mag, vijf heeft er elk');
      expect(kleinsteAfstand(uit), greaterThanOrEqualTo(kArtiestAfstand));
    });

    test('DE KERN: een andere artiest krijgt er hoogstens drie', () {
      final artiesten = [for (var i = 0; i < 6; i++) 'Cappella', 'Haddaway', 'Snap!'];
      final uit = rij(artiesten, afstand: klein.afstand, maxPerArtiest: klein.max);
      expect(uit.where((a) => a == 'Cappella'), hasLength(klein.max));
      expect(uit, containsAll(['Haddaway', 'Snap!']));
    });

    test('DE VAL: wie al in de radio staat telt mee — een nakomer begint niet opnieuw', () {
      final uit = rij(['Cappella', 'Cappella', 'Haddaway'],
          al: ['Cappella', 'Cappella'], afstand: klein.afstand, maxPerArtiest: klein.max);
      expect(uit.where((a) => a == 'Cappella'), hasLength(1),
          reason: 'twee stonden er al; het plafond is drie');
    });

    test('DE VAL: een gast maakt er geen andere artiest van', () {
      final uit = rij([
        '2 Fabiola',
        '2 Fabiola feat. Loredana',
        '2 Fabiola ft. Loredana',
        '2 FABIOLA',
        for (var i = 0; i < 6; i++) 'Artiest $i',
      ], zaad: '2 Fabiola');
      expect(uit.where((a) => a.toLowerCase().startsWith('2 fabiola')), hasLength(1),
          reason: 'tien plekken: één voor 2 Fabiola, hoe hij ook geschreven is');
    });

    test('DE GRENS: ook in een kleine radio krijgt de zaadartiest er maar één', () {
      // Tot 21-10-2026 minstens twee; Saber koos "voor iedereen 50".
      final uit = rij(['2 Fabiola', '2 Fabiola', '2 Fabiola', 'Snap!'], zaad: '2 Fabiola');
      expect(uit.where((a) => a == '2 Fabiola'), hasLength(1));
    });
  });

  group('de afstand', () {
    test('DE KERN: nooit twee keer dezelfde artiest binnen vijftig plekken', () {
      // Per artiest naast elkaar aangeleverd: de spreiding moet het zelf doen.
      final artiesten = [for (var a = 0; a < 60; a++) ...['Artiest $a', 'Artiest $a']];
      final uit = rij(artiesten);
      expect(uit, hasLength(artiesten.length), reason: 'twee per artiest in honderdtwintig: er valt niets weg');
      expect(kleinsteAfstand(uit), greaterThanOrEqualTo(kArtiestAfstand));
    });

    test('het mechanisme: nooit twee keer dezelfde artiest binnen de afstand', () {
      final artiesten = [
        'A', 'A', 'A', 'B', 'B', 'B', 'C', 'C', 'C', 'D', 'D', 'D', 'E', 'F', 'G', 'H',
      ];
      final uit = rij(artiesten, afstand: klein.afstand, maxPerArtiest: klein.max);
      expect(uit, hasLength(artiesten.length), reason: 'niemand boven het plafond: er valt niets weg');
      expect(kleinsteAfstand(uit), greaterThanOrEqualTo(klein.afstand));
    });

    test('DE KERN: het zaadnummer telt mee — de radio begint niet met nog een van hem', () {
      final uit = rij(['2 Fabiola', 'Cappella', 'Haddaway', 'Snap!', 'Culture Beat'],
          zaad: '2 Fabiola', al: ['2 Fabiola'], ervoor: ['2 Fabiola'], afstand: klein.afstand, maxPerArtiest: klein.max);
      expect(uit.indexOf('2 Fabiola'), greaterThanOrEqualTo(klein.afstand - 1),
          reason: 'het zaadnummer klinkt eerst; drie anderen ertussen');
    });

    test('DE VAL: lukt het niet meer, dan zo ver mogelijk uit elkaar — en er valt niets weg', () {
      final uit = rij(['A', 'A', 'A', 'B'], afstand: klein.afstand, maxPerArtiest: klein.max);
      expect(uit, hasLength(4));
      expect(uit.first, 'A');
      expect(uit[1], 'B', reason: 'B tussen de A\'s, niet achteraan');
    });

    test('DE VAL: past er niets, dan wint wie het langst weg is — niet wie vooraan staat', () {
      // Na A en B staan alleen nog B en A over, allebei te dichtbij. B was net, A twee plekken
      // terug: dan A, anders klinkt B twee keer achter elkaar.
      expect(rij(['A', 'B', 'B', 'A'], afstand: klein.afstand, maxPerArtiest: klein.max), ['A', 'B', 'A', 'B']);
    });

    test('DE GRENS: past alles al, dan blijft de volgorde van het aanbod staan', () {
      final artiesten = ['A', 'B', 'C', 'D', 'A', 'B', 'C', 'D'];
      expect(spreidArtiesten(artiesten, afstand: klein.afstand, maxPerArtiest: klein.max), [0, 1, 2, 3, 4, 5, 6, 7]);
      expect(spreidArtiesten(artiesten), [0, 1, 2, 3], reason: 'met de standaard: één per artiest in acht plekken');
    });

    test('DE GRENS: een lege lijst', () {
      expect(spreidArtiesten(const []), isEmpty);
    });
  });

  group('wat je al hebt vult alleen een plek als het dezelfde uitvoering is', () {
    bool past(String plek, String eigen, {int? plekSec, int? eigenSec}) => eigenPastOpPlek(
        plekTitel: plek,
        plekSeconden: plekSec,
        eigenTitel: eigen,
        eigenSeconden: eigenSec,
        speling: 5);

    test('DE KERN: je eigen remix is het origineel niet', () {
      expect(past('Freak Out', "Freak Out ('97 Remix)"), isFalse);
      expect(past('Freak Out', 'Freak Out (Extended Mix)'), isFalse);
    });

    test('DE KERN: de albumversie van 4:51 is de single van 3:40 niet', () {
      expect(past('Move On Baby', 'Move On Baby', plekSec: 220, eigenSec: 291), isFalse);
    });

    test('DE VAL: een radio-edit of een paar seconden verschil is wél hetzelfde', () {
      expect(past('Mr. Vain', 'Mr. Vain (Radio Edit)'), isTrue);
      expect(past('Move On Baby', 'Move On Baby', plekSec: 220, eigenSec: 223), isTrue);
    });

    test('DE VAL: een plek die om een remix vraagt mag je eigen remix krijgen', () {
      expect(past("Freak Out ('97 Remix)", "Freak Out ('97 Remix)"), isTrue);
    });

    test('DE GRENS: zonder lengte telt alleen de uitvoering', () {
      expect(past('Move On Baby', 'Move On Baby', plekSec: 220), isTrue);
      expect(past('Move On Baby', 'Move On Baby', eigenSec: 291), isTrue);
    });
  });

  group('covers komen er nooit in', () {
    test('DE KERN: de vier tv-covers uit de Deezer-top van 2 Fabiola vallen weg', () {
      // Letterlijk de top-15 van Deezer-artiest 75577, zoals opgevraagd op 26-09-2026 (ingekort).
      // Acht gewone eerst, zodat het rantsoen van twee bewerkingen per tien er twee zou toelaten —
      // alleen dan is te zien dat ze er om een ANDERE reden uit gaan.
      const gewoon = [
        'Freak Out', 'Flashback', 'I Hate 2 Love U', "I'm on Fire", 'Break Away', 'Feel the Vibe',
        "I'm Losing My Mind", 'Let the Music Play (Radio Edit)',
      ];
      final aanbod = <Aanbod>[
        for (final t in gewoon) (artiest: '2 Fabiola', titel: t),
        (artiest: 'Pat Krimson', titel: 'When The Lights Go Down - Uit Liefde Voor Muziek'),
        (artiest: 'Pat Krimson', titel: 'Believe In Me - Uit Liefde Voor Muziek'),
        (artiest: 'Pat Krimson', titel: 'Silence - Uit Liefde Voor Muziek'),
        (artiest: 'Pat Krimson', titel: 'Je Suis La - Uit Liefde Voor Muziek'),
      ];
      expect([for (final i in kiesNummers(aanbod)) aanbod[i].titel], gewoon,
          reason: 'ook zonder andere versie: dit is geen bewerking maar andermans liedje');
    });

    test('DE VAL: een woord dat er alleen op lijkt blijft staan', () {
      expect(nooitOpRadio('Rhythm Is a Dancer (Discovery Mix)'), isFalse,
          reason: '"cover" in "Discovery" is geen cover — dit is een remix, en die mag in het rantsoen');
      expect(nooitOpRadio('Undercover Lover'), isFalse);
      expect(nooitOpRadio('Freed From Desire (Karaoke Version)'), isTrue);
      expect(nooitOpRadio('Mr. Vain (Tribute to Culture Beat)'), isTrue);
    });

    // Gemeten op 22-10-2026: het enige rommelnummer van 80 doorgelaten nummers.
    test('de versie zonder zang: orkestband, instrumental — maar alleen als staart', () {
      expect(nooitOpRadio('Ik Ga Zwemmen (Orkestband)'), isTrue);
      expect(nooitOpRadio('Dromen Zijn Bedrog (Instrumental)'), isTrue);
      expect(nooitOpRadio('Laat Me Nu Toch Niet Alleen (Instrumentaal)'), isTrue);
      expect(nooitOpRadio('Freak Out (Backing Track)'), isTrue);
      expect(nooitOpRadio('Instrumental Love'), isFalse, reason: 'in de titel zelf is het gewoon een woord');
      expect(nooitOpRadio('Children (Dream Version)'), isFalse);
    });
  });

  group('namen splitsen en vergelijken', () {
    test('DE KERN: "Lil Nas X feat. …" is Lil Nas X — de X aan het eind is geen scheiding', () {
      expect(artiestDelenTekst('Lil Nas X feat. Jack Harlow').first, 'lil nas x');
      expect(artiestSleutel('Lil Nas X feat. Jack Harlow'), artiestSleutel('Lil Nas X'));
    });

    test('DE KERN: een duo met x, & of een komma is een duo', () {
      expect(artiestDelenTekst('Regard x Raye'), ['regard', 'raye']);
      expect(artiestDelenTekst('2 Fabiola & Loredana'), ['2 fabiola', 'loredana']);
      expect(artiestSleutel('2 Fabiola x Loredana'), artiestSleutel('2 Fabiola'));
    });

    test('DE VAL: een ander schrift houdt zijn letters — ook met een cijfer erbij', () {
      expect(artiestSleutel('Би-2'), isNot(artiestSleutel('2')));
      expect(basisTitel('Часть 2'), isNot(basisTitel('Глава 2')));
      expect(zelfdeArtiest('Кино', 'Кино'), isTrue);
    });
  });

  group('uit de kwaliteitscontrole met drie zaden (26-09-2026)', () {
    test('DE KERN: live, een repetitie, een demo of een sessie is het origineel niet — ook met "Radio"', () {
      expect(uitvoeringVan('Losing My Religion (Live From BBC Radio 1)'), Uitvoering.bewerking);
      expect(uitvoeringVan('The Man Who Sold the World (Rehearsal)'), Uitvoering.bewerking);
      expect(uitvoeringVan('Heart-Shaped Box (Demo)'), Uitvoering.bewerking);
      expect(uitvoeringVan('Lithium (BBC Session)'), Uitvoering.bewerking);
      expect(uitvoeringVan('Alive'), Uitvoering.origineel, reason: 'alleen in de staart, niet in de titel');
    });

    test('DE KERN: een onbekende toevoeging is vreemd, een radio-edit of een gast niet', () {
      expect(vreemdeStaart('Eins, Zwei, Polizei (Einstein Dr. Dj Konzept)'), isTrue);
      expect(vreemdeStaart('Eins, Zwei, Polizei (Radio Edit)'), isFalse);
      expect(vreemdeStaart('Mr. Vain (Original Radio Edit)'), isFalse);
      expect(vreemdeStaart('Lift U Up (feat. Loredana)'), isFalse);
      expect(vreemdeStaart('Freak Out'), isFalse);
    });

    test('DE KERN: "Hall & Oates" is "Daryl Hall & John Oates", en "The" vooraan telt niet', () {
      expect(zelfdeArtiest('Hall & Oates', 'Daryl Hall & John Oates'), isTrue);
      expect(zelfdeArtiest('Smashing Pumpkins', 'The Smashing Pumpkins'), isTrue);
      expect(zelfdeArtiest('Prodigy', 'The Prodigy'), isTrue,
          reason: 'één woord: hier helpt alleen het weglaten van "The"');
      expect(artiestSleutel('The Mackenzie'), artiestSleutel('Mackenzie'));
    });

    test('DE VAL: maar Queen is geen Queen Latifah, en Robin S geen Robin Schulz', () {
      expect(zelfdeArtiest('Queen', 'Queen Latifah'), isFalse);
      expect(zelfdeArtiest('Robin S', 'Robin Schulz'), isFalse);
    });
  });

  group('radioversies die anders heten', () {
    test('DE KERN: Airplay, Single en Video Mix zijn de radioversie, geen remix', () {
      // Review van 26-09-2026: ze telden als remix omdat er "Mix" in staat.
      expect(uitvoeringVan('Get Ready (Airplay Mix)'), Uitvoering.radio);
      expect(uitvoeringVan('Somebody (Single Mix)'), Uitvoering.radio);
      expect(uitvoeringVan("Can't Stop Raving (Video Mix)"), Uitvoering.radio);
      expect(uitvoeringVan('Dreamer (Short Mix)'), Uitvoering.radio);
    });

    test('DE VAL: maar een Rmx met "Radio" erbij blijft een remix', () {
      expect(uitvoeringVan('Blue (Da Ba Dee) (Gabry Ponte Radio Rmx)'), Uitvoering.bewerking);
    });
  });

  group('wat er nieuw als bewerking telt', () {
    test('een tv-cover, een tribute en een maxi', () {
      expect(uitvoeringVan('Silence - Uit Liefde Voor Muziek'), Uitvoering.bewerking);
      expect(uitvoeringVan('Freed From Desire (Tribute)'), Uitvoering.bewerking);
      expect(uitvoeringVan('Mysterious Times (Original Maxi)'), Uitvoering.bewerking);
    });
  });
}
