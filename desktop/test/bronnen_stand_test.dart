/// Welke bron heeft wat gedaan — want zonder dat is "die tracker is down" niet te weerleggen.
///
/// **Waarom dit bestaat.** Op het scherm stond één getal: `TORRENTS · TORBOX 27`. Welke van de vier
/// bronnen daaraan meebetaald heeft stond er niet bij, en de zoekverdeler slikte elke mislukking met
/// `catch (_) {}`.
///
/// Gemeld als "volgens mij is BitSearch down", terwijl op diezelfde schermafdruk álle zichtbare
/// treffers júist van BitSearch kwamen. Zo'n vermoeden is niet te bevestigen én niet te weerleggen
/// zolang het scherm er niets over zegt — en een bron die écht wegvalt is op precies dezelfde manier
/// onzichtbaar. Dat is hetzelfde patroon dat bij RuTracker drie uitgaven kostte.
library;

import 'package:debridmusic/search.dart';
import 'package:debridmusic/torbox.dart';
import 'package:flutter_test/flutter_test.dart';

SearchResult _treffer(String naam, String hash) => SearchResult(
      name: naam,
      magnet: 'magnet:?xt=urn:btih:$hash',
      hash: hash,
      seeders: 5,
      source: 'toets',
    );

/// Een bron die teruggeeft wat de toets nodig heeft — of stukgaat.
class _Nep implements SearchSource {
  _Nep(this.id, {this.uit = const [], this.gooit});
  @override
  final String id;
  final List<SearchResult> uit;
  final Object? gooit;

  @override
  Future<List<SearchResult>> search(String query) async {
    if (gooit != null) throw gooit!;
    return uit;
  }
}

void main() {
  group('DE KERN: elke bron laat een spoor na', () {
    test('een bron die treffers geeft, telt wat er DOOR de zeef kwam', () async {
      final verdeler = SearchAggregator([
        _Nep('knaben', uit: [
          _treffer('Gala - Come Into My Life FLAC', 'a' * 40),
          _treffer('Gala - Come Into My Life 24-96', 'b' * 40),
        ]),
      ]);

      await verdeler.search('iets');

      expect(verdeler.standen['knaben']?.aantal, 2);
      expect(verdeler.standen['knaben']?.gelukt, isTrue);
    });

    test('een bron die stukgaat laat dat weten, in plaats van te verdwijnen', () async {
      // Hier stond `catch (_) {}`. Een weggevallen tracker liet geen enkel spoor na.
      final verdeler = SearchAggregator([
        _Nep('bitsearch', gooit: Exception('kon de naam niet opzoeken')),
      ]);

      await verdeler.search('iets');

      expect(verdeler.standen['bitsearch']?.aantal, -1);
      expect(verdeler.standen['bitsearch']?.gelukt, isFalse);
      expect(verdeler.standen['bitsearch']?.fout, contains('opzoeken'),
          reason: 'de uitzondering zelf, niet "er ging iets mis"');
    });

    test('en een bron waarvan de zeef alles wegwierp is weer iets anders', () async {
      // Nul treffers op het scherm, maar de bron deed het prima. Dat verschil bepaalt wat je
      // vervolgens gaat repareren.
      final verdeler = SearchAggregator([
        _Nep('apibay', uit: [_treffer('Concert 2011 1080p x264', 'c' * 40)]),
      ]);

      await verdeler.search('iets');

      expect(verdeler.standen['apibay']?.aantal, 0);
      expect(verdeler.standen['apibay']?.fout, contains('weggezeefd'));
    });

    test('alle bronnen staan erin, ook de lege', () async {
      final verdeler = SearchAggregator([
        _Nep('knaben', uit: [_treffer('Iets - Iets FLAC', 'd' * 40)]),
        _Nep('apibay'),
        _Nep('bitsearch', gooit: Exception('stuk')),
      ]);

      await verdeler.search('iets');

      expect(verdeler.standen.keys.toSet(), {'knaben', 'apibay', 'bitsearch'});
      expect(verdeler.standen['apibay']?.aantal, 0);
      expect(verdeler.standen['apibay']?.gelukt, isTrue,
          reason: 'niets gevonden is iets anders dan stukgegaan');
    });

    test('een nieuwe zoekopdracht wist de vorige stand', () async {
      // Anders lees je op het scherm de uitslag van je vórige zoekopdracht, en dat is erger dan
      // niets: het lijkt te kloppen.
      final verdeler = SearchAggregator([_Nep('knaben', uit: [_treffer('A FLAC', 'e' * 40)])]);
      await verdeler.search('een');
      expect(verdeler.standen['knaben']?.aantal, 1);

      final leeg = SearchAggregator([_Nep('knaben')]);
      await leeg.search('twee');
      expect(leeg.standen['knaben']?.aantal, 0);
    });
  });

  group('de zin die op het scherm komt', () {
    test('gelukt is naam plus aantal', () {
      expect(const BronStand(aantal: 12).zin('Knaben'), 'Knaben 12');
      expect(const BronStand(aantal: 0).zin('BitSearch'), 'BitSearch 0');
    });

    test('mislukt noemt de reden, niet het aantal', () {
      const stuk = BronStand(aantal: -1, fout: 'te traag (12 s)');
      expect(stuk.zin('PirateBay'), 'PirateBay — te traag (12 s)');
      expect(stuk.zin('PirateBay').contains('-1'), isFalse,
          reason: 'min één is een rekenwaarde, geen mededeling');
    });
  });

  // Een bron die over de kap van twaalf seconden gaat staat hier met opzet niet: die toets zou
  // twaalf seconden duren en daarmee de hele bouwstraat vertragen. Wat er dan gebeurt staat in
  // `SearchAggregator.search`: `on TimeoutException` zet er "te traag (12 s)" neer.
}
