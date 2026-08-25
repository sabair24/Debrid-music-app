/// Wat je typte moet het resultaat zijn, en een persing mag jouw titel niet uitkleden.
///
/// **Twee klachten, en ze bleken één patroon te delen.** Op beide plekken beantwoordde de app een
/// vraag die niemand gesteld had:
///
/// - "Nummering overnemen" toonde `7 → 7  Fields Of Gold (My Songs Version) → Fields Of Gold`. Het
///   nummer klopte al; het enige wat er gebeurde was dat er informatie van af ging. Daarna zocht de
///   app onder die kale titel en vond de plaat uit 1993.
/// - Bij direct zoeken zat er géén enkele zeef tussen de bronnen en het scherm, en de volgorde keek
///   alleen naar geluidskwaliteit. Wat je intikte kwam in de rangschikking niet voor.
///
/// Allebei zijn het zuivere regels, dus allebei zijn ze hier na te meten zonder toestel en zonder
/// netwerk — en dat is nodig, want het verschil tussen "goed" en "bijna goed" is hier één woord.
library;

import 'package:debridmusic/organize.dart';
import 'package:debridmusic/zoekladder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('een persing mag geen versiemerk afhalen', () {
    test('DE KERN: "(My Songs Version)" blijft staan tegen een kale persing', () {
      // Precies de regel uit het gemelde venster.
      expect(titelNaOvername('Fields Of Gold (My Songs Version)', 'Fields Of Gold'),
          'Fields Of Gold (My Songs Version)');
      expect(titelNaOvername('Shape Of My Heart (My Songs Version)', 'Shape Of My Heart'),
          'Shape Of My Heart (My Songs Version)');
    });

    test('een gewone titel neemt de spelling van de persing wél over', () {
      // Dit is waar "Nummering overnemen" voor bestaat: de persing weet beter hoe het heet.
      expect(titelNaOvername('fields of gold', 'Fields Of Gold'), 'Fields Of Gold');
      expect(titelNaOvername('01 Fields Of Gold', 'Fields Of Gold'), 'Fields Of Gold');
    });

    test('een nepmerk mag wél verdwijnen', () {
      // "(Album Version)" zégt letterlijk dat het de albumversie is. Zie `_geenEchtMerk`.
      expect(titelNaOvername('Escape (Album Version)', 'Escape'), 'Escape');
    });

    test('de andere kant op mag: een merk erbij is nieuwe informatie', () {
      expect(titelNaOvername('Roxanne', 'Roxanne (Live)'), 'Roxanne (Live)');
    });

    test('hetzelfde merk aan beide kanten laat de persing beslissen', () {
      expect(titelNaOvername('roxanne (live)', 'Roxanne (Live)'), 'Roxanne (Live)');
    });

    test('geen persing, geen verandering', () {
      expect(titelNaOvername('Fields Of Gold (My Songs Version)', null),
          'Fields Of Gold (My Songs Version)');
      expect(titelNaOvername('Fields Of Gold (My Songs Version)', '   '),
          'Fields Of Gold (My Songs Version)');
    });

    test('een live-opname verliest zijn merk ook niet', () {
      // Belangrijker dan het lijkt: zonder deze regel werd een live-opname stilletjes hernoemd naar
      // de studioversie, en dan is hij in je bibliotheek niet meer van de studioversie te
      // onderscheiden.
      expect(titelNaOvername('Roxanne (Live)', 'Roxanne'), 'Roxanne (Live)');
      expect(titelNaOvername('Message In A Bottle (Radio Edit)', 'Message In A Bottle'),
          'Message In A Bottle (Radio Edit)');
    });
  });

  group('hoe goed past dit bij wat ik typte', () {
    test('alles in de bestandsnaam is een volle score', () {
      expect(vraagScore('fields of gold', r'@@peer\Sting\07 Fields of Gold.flac'), 1.0);
    });

    test('alleen in de mapnaam telt half', () {
      // Het onderscheid dat ontbrak. Soulseek eist zijn woorden in het HELE pad, dus een treffer op
      // een mapnaam sleept elk nummer in die map mee. "Sting" in de artiestenmap is context; "Sting"
      // in de bestandsnaam is wat je zocht.
      final s = vraagScore('sting roxanne', r'@@peer\Sting\Album\01 Roxanne.flac');
      expect(s, 0.75, reason: 'roxanne heel, sting half');
    });

    test('niets van de vraag in het pad is score nul', () {
      // Dit is de jokerruis: de app stuurde naast "Rain" ook "*ain", en dat vindt Brain en Spain.
      // Bij één woord gaat die variant niet meer mee (zie hieronder), bij meer woorden nog wel.
      expect(vraagScore('rain', r'@@peer\Muziek\Brain Damage.flac'), 0);
      expect(volslagenAnders('rain', r'@@peer\Muziek\Brain Damage.flac'), isTrue);
    });

    test('een echte treffer is nooit volslagen anders', () {
      expect(volslagenAnders('rain', r'@@peer\Muziek\Rain.flac'), isFalse);
      expect(volslagenAnders('rain', r'@@peer\Rain\01 iets anders.flac'), isFalse,
          reason: 'in de mapnaam telt half, maar het is niet nul');
    });

    test('een lege vraag oordeelt over niets', () {
      // Zou dit 0 opleveren én gebruikt worden om te zeven, dan verdween de hele lijst.
      expect(vraagScore('', r'@@peer\x.flac'), 0);
      expect(vraagScore('   ', r'@@peer\x.flac'), 0);
    });

    test('meer van de vraag betekent een hogere score', () {
      // De eigenschap waar de rangschikking op leunt: de volledige titel hoort boven de halve.
      final heel = vraagScore('sting fields of gold', r'@@p\Sting - Fields of Gold.flac');
      final half = vraagScore('sting fields of gold', r'@@p\Sting - Roxanne.flac');
      expect(heel, greaterThan(half));
    });

    test('hoofdletters en leestekens maken niet uit', () {
      expect(vraagScore('FIELDS OF GOLD', r'@@p\fields_of_gold.flac'), 1.0);
    });
  });

  group('staat het ook ACHTER ELKAAR', () {
    // Het gemelde geval, met de echte bestandsnamen uit de schermafbeelding. Vier telbare woorden
    // ("i" valt weg, te kort). Dekking alleen zet YORK op 0,75 en de tapes op 0,50 — dat klopt al,
    // maar het maakt geen verschil tussen een treffer en een toevalstreffer.
    const vraag = 'mackenzie you all i need';
    const york = r'@@p\[PTLC049] YORK\01. YORK feat. Ginger Mackenzie - I Need You (Remix).flac';
    const tape = r'@@p\Disc 1\05 - Naby Let Me Follow You Down (First MacKenzie Tape).mp3';
    const echt = r"@@p\Mackenzie\Mackenzie - You're All I Need.mp3";
    // Dezelfde plaat bij een peer die de apostrof weglaat. Zie de toets hieronder: dat kost een woord.
    const echtKaal = r'@@p\Mackenzie\Mackenzie - Youre All I Need.mp3';

    test('vier telbare woorden, want "i" is te kort', () {
      expect(telbareWoorden(vraag), 4);
    });

    test('de dekking zet ze al in de goede volgorde', () {
      expect(gedekteWoorden(vraag, echt), 4);
      expect(gedekteWoorden(vraag, york), 3);
      expect(gedekteWoorden(vraag, tape), 2);
    });

    test('een peer die de apostrof weglaat kost je een woord — en dán telt de reeks', () {
      // "You're" valt uiteen in "you" en "re", dus je woord "you" komt gewoon voor. "Youre" is één
      // woord dat op niets van je vraag lijkt. Diezelfde plaat zakt daarmee van 4 naar 3 gedekte
      // woorden en staat gelijk met YORK — precies het geval waarvoor de reeks bestaat.
      expect(gedekteWoorden(vraag, echtKaal), 3);
      expect(gedekteWoorden(vraag, echtKaal), gedekteWoorden(vraag, york));
      expect(reeksScore(vraag, echtKaal), greaterThan(reeksScore(vraag, york)),
          reason: 'de reeks moet hem hier alsnog bovenaan zetten');
    });

    test('DE KERN: de reeks scheidt de treffer van de toevalstreffer', () {
      // Bij gelijke dekking is dit wat overblijft. "mackenzie you" en "all need" staan hier in de
      // volgorde waarin je ze typte; bij YORK staan dezelfde woorden verspreid door de naam.
      expect(reeksScore(vraag, echt), greaterThan(reeksScore(vraag, york)));
      expect(reeksScore(vraag, york), reeksScore(vraag, tape),
          reason: 'allebei één los woord op een rij');
    });

    test('een naam die je vraag letterlijk bevat haalt de volle reeks', () {
      expect(reeksScore('fields of gold', r'@@p\07 Fields of Gold.flac'), 1.0);
    });

    test('dezelfde woorden in omgekeerde volgorde halen de reeks niet', () {
      expect(reeksScore('need you', r'@@p\You Need.flac'), 0.5,
          reason: 'hooguit één woord op een rij');
    });

    test('de mappen tellen hier niet mee', () {
      // Een mapnaam die toevallig jouw woorden op volgorde draagt zegt iets over het album, niet
      // over dit nummer.
      expect(reeksScore('fields of gold', r'@@p\Fields of Gold\01 Iets anders.flac'), 0);
    });

    test('niets in, niets uit', () {
      expect(reeksScore('', r'@@p\x.flac'), 0);
      expect(reeksScore('iets', ''), 0);
      expect(telbareWoorden(''), 0);
    });
  });

  group('het sterretje gaat niet meer overal mee', () {
    // De app stuurt naast je vraag een variant met een sterretje ervoor, voor het geval Soulseek het
    // eerste teken laat vallen. Bij één woord IS die variant de hele vraag, en dan houdt niets de
    // ruis tegen. Bij meer woorden doen de overige woorden dat vanzelf, want de server eist ze alle.
    test('DE KERN: bij één woord blijft het sterretje thuis', () {
      expect(jokerHelpt('rain'), isFalse);
      expect(jokerHelpt('mackenzie'), isFalse);
      expect(jokerHelpt('  roxanne  '), isFalse, reason: 'spaties eromheen zijn geen tweede woord');
    });

    test('bij meer woorden mag hij mee, want de rest houdt de ruis tegen', () {
      expect(jokerHelpt('sting fields of gold'), isTrue);
      expect(jokerHelpt('mackenzie you all i need'), isTrue);
    });

    test('een heel korte vraag krijgt er nooit een', () {
      // Het sterretje vervangt het eerste teken van het eerste woord. Is dat woord één letter, dan
      // blijft er niets van over: dat is geen zoekvraag meer maar een verzoek om alles.
      expect(jokerHelpt('ab'), isFalse);
      expect(jokerHelpt('a b'), isFalse);
      expect(jokerHelpt(''), isFalse);
      expect(jokerHelpt('   '), isFalse);
    });
  });
}
