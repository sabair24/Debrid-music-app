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
      // Dit is de jokerruis: de app stuurt naast "Rain" ook "*ain", en dat vindt Brain en Spain.
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
}
