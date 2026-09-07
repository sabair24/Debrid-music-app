/// Wat er WERKELIJK in zit, als getal — zodat "beter" iets vergelijkbaars betekent.
///
/// De ZIN bestond al ([echteResolutie] geeft "24/44.1"), het GETAL niet. Daardoor kon niets in de
/// app vragen wélke van twee bestanden er écht beter is: `firstIsBetter` kende alleen "betrapt:
/// ja/nee" en viel daaronder terug op de GROOTTE — en juist een opgeblazen bestand is groter.
///
/// GEMETEN op Sabers bibliotheek: 1220 nummers, 375 die meer dan 48 kHz claimen, en van de 334
/// beoordeelde hebben er 160 een lege bovenband of erger. Samen 20,6 GB waar 4,1 GB volstaat.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/echtheid.dart';

Echtheidsoordeel _opgeblazen({int gebruikt = 16}) => Echtheidsoordeel(
      bits: Bitdiepte.opgeblazen,
      boven: Bovenband.leeg,
      band: Bandbreedte.doorlopend,
      gebruikteBits: gebruikt,
      vensters: 32,
    );

Echtheidsoordeel _opgeschaald() => const Echtheidsoordeel(
      bits: Bitdiepte.spreektNietTegen,
      boven: Bovenband.leeg,
      band: Bandbreedte.doorlopend,
      vensters: 32,
    );

Echtheidsoordeel _afgekapt(double hz) => Echtheidsoordeel(
      bits: Bitdiepte.spreektNietTegen,
      boven: Bovenband.onbekend,
      band: Bandbreedte.afgekapt,
      afkapHz: hz,
      wandDb: 40,
      vensters: 32,
    );

const Echtheidsoordeel _schoon = Echtheidsoordeel(
  bits: Bitdiepte.spreektNietTegen,
  boven: Bovenband.vol,
  band: Bandbreedte.doorlopend,
  vensters: 32,
);

/// Een echte cd op de schaal van `capaciteitOpEenSchaal`: 44100 × 16 ÷ 1000.
const int cd = 705;

void main() {
  group('de gemeten waarheid als getal', () {
    test('opgeschaald is 24/44.1 en niet zomaar cd — de bits zijn er wél', () {
      // Deze toets corrigeerde de aanname waarmee hij geschreven werd. Een opgeschaald bestand
      // heeft `bits: spreektNietTegen`: de lage bits wórden gebruikt, alleen de bemonstering is
      // opgerekt. Het is dus echt 24/44.1 (1058) en niet 16/44.1 (705).
      //
      // Dat is precies waarom capaciteit NIET de regel mag zijn die nep van echt scheidt: op dit
      // getal wint de opgeschaalde 24/96 van een eerlijke cd. Wat ze uit elkaar houdt is
      // `firstIsBetter`'s regel "wat bewezen nep is verliest", en die staat er bóven.
      expect(echteCapaciteit(_opgeschaald(), kopSampleRate: 96000, kopBits: 24), 44100 * 24 ~/ 1000);
      expect(echteCapaciteit(null, kopSampleRate: 44100, kopBits: 16), cd);
      // Een OPGEBLAZEN bestand zakt wél naar cd-niveau: daar zijn de lage bits aantoonbaar leeg.
      expect(echteCapaciteit(_opgeblazen(), kopSampleRate: 96000, kopBits: 24), cd);
    });

    test('een opgeblazen bestand krijgt de bits die het ECHT gebruikt', () {
      final w = echteWaarden(_opgeblazen(), kopSampleRate: 96000, kopBits: 24);
      expect(w.bits, 16);
      expect(w.rate, 44100);
      expect(w.uitLossy, isFalse);
    });

    test('een afgekapte kopie verliest ALTIJD van een echte cd', () {
      // Per constructie, zonder drempel om te ijken: de muurzoeker kijkt niet hoger dan
      // `hoogsteAfkapHz` = 21000, dus twee keer de afkap is hoogstens 42000 — al minder dan 44100.
      for (final hz in [14000.0, 15600.0, 17200.0, 19000.0, 20500.0, 21000.0]) {
        final c = echteCapaciteit(_afgekapt(hz), kopSampleRate: 44100, kopBits: 16);
        expect(c, lessThan(cd), reason: 'een muur op $hz Hz hoort onder een echte cd te blijven');
      }
    });

    test('en 24 bits beweren helpt een afgekapte kopie niet', () {
      // Zonder de klem op zestien zou 42000 × 24 ÷ 1000 = 1008 zijn, en dan zou een uit mp3
      // omgezet bestand een echte cd verslaan. `Bitdiepte.spreektNietTegen` bewijst uitdrukkelijk
      // nooit dat er 24 echte bits in zitten.
      final w = echteWaarden(_afgekapt(20500), kopSampleRate: 96000, kopBits: 24);
      expect(w.bits, 16);
      expect(w.uitLossy, isTrue);
      expect(echteCapaciteit(_afgekapt(20500), kopSampleRate: 96000, kopBits: 24), lessThan(cd));
    });

    test('lager afgekapt is minder — dezelfde volgorde die de lijst al aanhoudt', () {
      final laag = echteCapaciteit(_afgekapt(15600), kopSampleRate: 44100, kopBits: 16);
      final midden = echteCapaciteit(_afgekapt(17200), kopSampleRate: 44100, kopBits: 16);
      final hoog = echteCapaciteit(_afgekapt(20500), kopSampleRate: 44100, kopBits: 16);
      expect(laag, lessThan(midden));
      expect(midden, lessThan(hoog));
    });

    test('zonder oordeel blijft de kop staan — dit bewijst niets, het spreekt alleen niets tegen', () {
      final w = echteWaarden(null, kopSampleRate: 192000, kopBits: 24);
      expect(w.rate, 192000);
      expect(w.bits, 24);
      expect(echteCapaciteit(_schoon, kopSampleRate: 96000, kopBits: 24), 96000 * 24 ~/ 1000);
    });

    test('en de ZIN zegt nog steeds hetzelfde als voorheen', () {
      // De vier gevallen uit `echtheid_test.dart`, hier nog eens tegen de nieuwe onderbouw. Een
      // afgekapte kopie hoort te blijven zeggen wáár de muur zit, niet welke bemonstering dat is.
      expect(echteResolutie(_opgeschaald(), kopSampleRate: 96000, kopBits: 24), '24/44.1');
      expect(echteResolutie(_opgeblazen(), kopSampleRate: 96000, kopBits: 24), '16/44.1');
      expect(echteResolutie(_afgekapt(14000), kopSampleRate: 44100, kopBits: 16), 'tot 14.0 kHz');
      expect(echteResolutie(_schoon, kopSampleRate: 96000, kopBits: 24), isNull);
    });
  });
}
