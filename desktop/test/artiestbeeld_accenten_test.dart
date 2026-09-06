/// Artiesten met een accent in hun naam kregen géén foto, logo of backdrop.
///
/// **Gemeten op 06-09-2026.** TheAudioDB's zoekfunctie vindt `Beyonce` wél en `Beyoncé` niet —
/// nagekeken met twee losse aanroepen naar `search.php?s=`. De app stuurt de naam letterlijk mee
/// (`CoverEnricher.artistArt`) en bewaart onder `fnv(naam.toLowerCase())`, dus voor Beyoncé stond er
/// niets in `artistart/` en kon er ook nooit iets komen.
///
/// **Van de 268 artiestnamen in Sabers bibliotheek dragen er dertien een niet-ASCII teken**:
/// Beyoncé, Céline Dion, Édith Piaf, Tiësto, Alizée, Hélène Ségara, Emeli Sandé, Chimène Badi,
/// Gérard Lenorman, Âme, Lil’ Kim (krulapostrof), Aaron Blommaert & Zoë Livay, Hélène Segara.
///
/// **En een eerdere reparatie maakte het erger.** Sinds `canonicalName` een accent laat winnen van
/// het aantal (zie `naamschade_test.dart`) toont de app juist de spelling die deze bron niet kent.
/// Twee verbeteringen die elkaar in de weg zaten.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/settings.dart';

void main() {
  group('de platgeslagen naam', () {
    // Dit is de reparatie zelf: `normKey` is wat de tweede poging stuurt.
    test('DE KERN: normKey maakt van elke gemeten naam iets dat de bron kent', () {
      expect(normKey('Beyoncé'), 'beyonce');
      expect(normKey('Céline Dion'), 'celine dion');
      expect(normKey('Édith Piaf'), 'edith piaf');
      expect(normKey('Tiësto'), 'tiesto');
      expect(normKey('Hélène Ségara'), 'helene segara');
      expect(normKey('Alizée'), 'alizee');
      expect(normKey('Âme'), 'ame');
      // De krulapostrof gaat er ook af — sinds de apostrofregel is dat één woord.
      expect(normKey('Lil’ Kim'), 'lil kim');
    });

    test('een gewone naam verandert niet, dus daar is nooit een tweede aanroep voor nodig', () {
      // De tweede poging kost pas iets als de platte vorm ANDERS is. Bij deze namen is hij gelijk.
      for (final n in ['Michael Jackson', 'Adele', 'Daft Punk', 'Stromae']) {
        expect(normKey(n), n.toLowerCase());
      }
      // En bij een naam met leestekens verschilt hij wél — `P!nk` wordt `p nk`. Dat is geen
      // probleem: de tweede poging vuurt alleen als de EERSTE niets opleverde, en voor P!nk levert
      // die gewoon een treffer op. Het kost dus niets extra's waar het al werkt.
      expect(normKey('P!nk'), 'p nk');
    });

    test('DE GRENS: twee verschillende artiesten vallen niet samen', () {
      expect(normKey('Sade') == normKey('Sadé'), isTrue, reason: 'zelfde artiest, twee spellingen');
      expect(normKey('Alizée') == normKey('Alice'), isFalse);
      expect(normKey('Âme') == normKey('Ame Son'), isFalse);
    });
  });

  group('en dan vindt de bron hem ook echt', () {
    // Een live toets. Slaat zichzelf over als TheAudioDB zwijgt — een rood dat "de bron was even
    // niet bereikbaar" betekent zegt niets over deze weg. Zie `metadata_test.dart` voor dezelfde
    // afspraak bij MusicBrainz.
    test('Beyoncé krijgt beeld, ondanks het accent', () async {
      final e = CoverEnricher(AppSettings());

      final zonder = await e.artistArt('Beyonce');
      if (zonder == null) {
        markTestSkipped('TheAudioDB antwoordde niet — niet nagekeken, geen defect');
        return;
      }
      // De controle: mét accent hoort nu hetzelfde antwoord te komen.
      final met = await e.artistArt('Beyoncé');
      expect(met, isNotNull,
          reason: 'de tweede poging met platgeslagen accenten hoort dit op te lossen');
      expect(met!.isEmpty, isFalse);
      // ignore: avoid_print
      print('Beyoncé -> logo=${met.logo != null} backdrop=${met.backdrop != null} '
          'thumb=${met.thumb != null} cutout=${met.cutout != null}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('de vrijstaande artiest', () {
    test('cutout en clearart zijn eigen velden, geen terugval meer', () {
      // Als noodgreep achter `thumb` werd de cutout nooit gekozen: bijna elke artiest heeft een
      // portret. Gemeten: 10 van de 13 artiesten uit deze bibliotheek hebben er een.
      const met = ArtistArt(thumb: 't', cutout: 'c');
      const zonder = ArtistArt(thumb: 't');
      expect(met.heeftVrijstaand, isTrue);
      expect(zonder.heeftVrijstaand, isFalse);
      expect(const ArtistArt(clearart: 'x').heeftVrijstaand, isTrue,
          reason: 'clearart is dezelfde gedachte in liggend formaat');
    });

    test('en een oude cache-ingang wordt opnieuw opgehaald', () {
      // Zonder de opgehoogde schema zou elke artiest die je al had geopend voor eeuwig
      // cutout: null blijven melden — de fout waar de doc-comment bij `schema` over gaat.
      expect(ArtistArt.fromJson({'v': 2, 'logo': 'x'}), isNull);
      final nu = ArtistArt.fromJson({'v': ArtistArt.schema, 'logo': 'x', 'cutout': 'c'});
      expect(nu, isNotNull);
      expect(nu!.cutout, 'c');
    });

    test('en de rondreis door JSON houdt alles vast', () {
      const a = ArtistArt(
          logo: 'l', backdrop: 'b', thumb: 't', cutout: 'c', clearart: 'ca');
      final terug = ArtistArt.fromJson(a.toJson())!;
      expect([terug.logo, terug.backdrop, terug.thumb, terug.cutout, terug.clearart],
          ['l', 'b', 't', 'c', 'ca']);
    });
  });
}
