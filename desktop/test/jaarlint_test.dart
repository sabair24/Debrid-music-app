/// Het jaarlint onder de biografie moet een tijdlijn zijn, geen veeg.
///
/// **Waarom dit bestaat.** Onder de biografie komt een strook jaartallen waarop je een periode
/// aanwijst. De grondstof komt uit drie samengevoegde bronnen (Deezer, MusicBrainz, Discogs) plus
/// de feiten van TheAudioDB, en dat levert drie manieren op waarop zo'n strook stuk gaat:
///
/// * **Te veel.** Zonder zeef staat elke single erin — voor Enrique Iglesias tweehonderd regels.
/// * **Rommeljaren.** Beide catalogi sturen ze: één `0202` rekt het lint uit over achttien eeuwen
///   en dan plakt alles wat er echt toe doet op elkaar aan de rechterkant.
/// * **Onbepaaldheid.** De drie bronnen komen in willekeurige volgorde binnen. Beslist die volgorde
///   welke plaat een jaar krijgt, dan verspringt het lint onder je hand bij elke hertekening — en
///   `main.dart` schrijft al voor dat samenvoegen bij het tekenen hetzelfde antwoord moet geven
///   ongeacht wie het eerst binnenkwam.
///
/// De opbouw is puur, dus dit toetst zonder netwerk en zonder widgetboom.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/discography.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/jaarlint.dart';

DiscoRelease plaat(String titel, int? jaar,
        {RecordKind soort = RecordKind.album, int bronnen = 1, String? hoes}) =>
    DiscoRelease(
      title: titel,
      kind: soort,
      firstDate: jaar?.toString(),
      cover: hoes,
      sources: {
        if (bronnen >= 1) DiscoSource.deezer,
        if (bronnen >= 2) DiscoSource.musicbrainz,
        if (bronnen >= 3) DiscoSource.discogs,
      },
    );

/// Michael Jackson, zoals de feiten van TheAudioDB binnenkomen.
const _mj = ArtiestFeiten(geborenJaar: 1958, gestorvenJaar: 2009, land: 'USA', label: 'Epic');

void main() {
  group('de vorm van het lint', () {
    test('DE KERN: geboorte vooraan, platen op jaar, overlijden achteraan', () {
      final lint = bouwJaarlint(
        platen: [plaat('Bad', 1987), plaat('Thriller', 1982), plaat('Off the Wall', 1979)],
        feiten: _mj,
      );
      expect(lint.map((p) => p.jaar).toList(), [1958, 1979, 1982, 1987, 2009]);
      expect(lint.first.soort, Jaarsoort.geboorte);
      expect(lint.last.soort, Jaarsoort.overlijden);
      expect(lint[2].label, 'Thriller',
          reason: 'onder het jaartal hoort te staan wat er dat jaar uitkwam');
      expect(lint[2].plaatSleutel, isNotNull,
          reason: 'zonder sleutel vindt het lint je eigen exemplaar van die plaat niet terug');
    });

    test('DE KERN: een band krijgt oprichting in plaats van geboorte', () {
      final lint = bouwJaarlint(
        platen: [plaat('Homework', 1997)],
        feiten: const ArtiestFeiten(opgerichtJaar: 1993, ontbonden: '2021'),
      );
      expect(lint.first.soort, Jaarsoort.oprichting);
      expect(lint.first.jaar, 1993);
      expect(lint.last.soort, Jaarsoort.ontbinding);
      expect(lint.last.jaar, 2021);
    });

    test('DE VAL: alleen albums, tenzij dat te weinig oplevert', () {
      // Zonder deze zeef is het lint voor een artiest met veel singles geen tijdlijn meer.
      final lint = bouwJaarlint(platen: [
        plaat('Album A', 1990),
        plaat('Album B', 1992),
        plaat('Album C', 1994),
        plaat('Album D', 1996),
        for (var i = 0; i < 30; i++) plaat('Single $i', 2000 + i, soort: RecordKind.single),
      ]);
      expect(lint.length, 4, reason: 'dertig singles maken van een tijdlijn een veeg');

      // Maar een artiest met twee albums en tien singles hoort niet met twee stipjes te eindigen.
      final mager = bouwJaarlint(platen: [
        plaat('Album A', 1990),
        for (var i = 0; i < 10; i++) plaat('Single $i', 1991 + i, soort: RecordKind.single),
      ]);
      expect(mager.length, greaterThan(4),
          reason: 'een lint van één punt is geen lint; dan mag de zeef ruimer');
    });
  });

  group('bepaaldheid', () {
    test('DE VAL: twee platen in één jaar geven één punt, en de meeste bronnen wint', () {
      final lint = bouwJaarlint(platen: [
        plaat('Zwak gedocumenteerd', 1982, bronnen: 1),
        plaat('Thriller', 1982, bronnen: 3),
      ]);
      expect(lint.where((p) => p.jaar == 1982).length, 1);
      expect(lint.single.label, 'Thriller');
    });

    test('DE VAL: een gehusselde invoer geeft een IDENTIEK lint', () {
      // Dit is de regel die telt. De drie bronnen komen in willekeurige volgorde binnen; beslist
      // die volgorde het antwoord, dan verspringt het lint bij elke hertekening.
      final a = [plaat('Aaa', 1990, bronnen: 2), plaat('Bbb', 1990, bronnen: 2), plaat('Ccc', 1991)];
      final b = [a[2], a[1], a[0]];
      String toon(List<Jaarpunt> l) => l.map((p) => '${p.jaar}:${p.label}').join('|');
      expect(toon(bouwJaarlint(platen: a)), toon(bouwJaarlint(platen: b)),
          reason: 'het lint verspringt onder je hand bij elke hertekening');
      expect(toon(bouwJaarlint(platen: a)), contains('1990:Aaa'),
          reason: 'bij gelijkspel wint de alfabetisch eerste, en dat moet vaststaan');
    });
  });

  group('rommel en grenzen', () {
    test('DE GRENS: onmogelijke jaartallen vallen af', () {
      final lint = bouwJaarlint(
        platen: [plaat('Rommel', 202), plaat('Echt', 1994), plaat('Toekomst', 2099)],
        nu: 2026,
      );
      expect(lint.map((p) => p.jaar).toList(), [1994],
          reason: 'één 0202 rekt het lint uit over achttien eeuwen');
    });

    test('DE GRENS: een plaat zonder jaartal telt niet mee', () {
      final lint = bouwJaarlint(platen: [plaat('Zonder', null), plaat('Met', 1994)]);
      expect(lint.length, 1);
    });

    test('DE GRENS: de kap laat het begin en het einde staan', () {
      final lint = bouwJaarlint(
        platen: [for (var j = 1960; j < 2010; j++) plaat('Plaat $j', j)],
        feiten: _mj,
        maximum: 10,
      );
      expect(lint.length, lessThanOrEqualTo(10));
      expect(lint.first.soort, Jaarsoort.geboorte,
          reason: 'het begin van een loopbaan mag nooit wegvallen bij het uitdunnen');
      expect(lint.last.soort, Jaarsoort.overlijden);
      // En de middenmoot wordt gelijkmatig gedund, niet "de laatste tien".
      final jaren = lint.where((p) => p.soort == Jaarsoort.plaat).map((p) => p.jaar).toList();
      expect(jaren.first, lessThan(1970),
          reason: 'anders begint de tijdlijn pas in de laatste jaren van de loopbaan');
    });

    test('DE GRENS: zonder feiten en zonder platen blijft het lint leeg zonder om te vallen', () {
      expect(bouwJaarlint(platen: []), isEmpty);
      expect(bouwJaarlint(platen: [], feiten: const ArtiestFeiten()), isEmpty);
    });

    test('DE VAL: "ontbonden" als vrije tekst wordt geen jaartal', () {
      // strDisbanded staat regelmatig vol met een hele zin. Daar een jaartal uit vissen zou een
      // gok zijn die er als een feit uitziet.
      final lint = bouwJaarlint(
        platen: [plaat('Plaat', 1994)],
        feiten: const ArtiestFeiten(opgerichtJaar: 1990, ontbonden: 'still active'),
      );
      expect(lint.any((p) => p.soort == Jaarsoort.ontbinding), isFalse);
      expect(ArtiestFeiten.jaarUit('still active'), isNull);
      expect(ArtiestFeiten.jaarUit('2011'), 2011);
    });
  });

  group('de feiten zelf', () {
    test('DE KERN: "actief" leest als een periode', () {
      expect(_mj.actief, '1958 – 2009');
      expect(const ArtiestFeiten(opgerichtJaar: 1993).actief, 'sinds 1993');
      expect(const ArtiestFeiten(opgerichtJaar: 1993, ontbonden: '2011').actief, '1993 – 2011');
      expect(const ArtiestFeiten(land: 'BE').actief, isNull,
          reason: 'zonder beginjaar is er geen periode en hoort er geen regel te staan');
    });

    test('DE VAL: een oprichtingsjaar gaat voor een geboortejaar', () {
      // Bij een band is dat het jaar dat telt. Staan ze er allebei, dan is het een persoon die
      // ook een groep begon, en dan is de groep het onderwerp van deze pagina.
      expect(const ArtiestFeiten(geborenJaar: 1975, opgerichtJaar: 1993).actief, 'sinds 1993');
    });

    test('DE VAL: de letterlijke tekst "null" wordt nooit een waarde', () {
      final f = ArtiestFeiten.uitAudioDb({
        'strBorn': 'null',
        'strCountry': 'USA',
        'intBornYear': '1958',
        'strLabel': '',
      });
      expect(f.geboren, isNull, reason: 'anders staat er letterlijk "null" in je feitenstrook');
      expect(f.land, 'USA');
      expect(f.geborenJaar, 1958, reason: 'de jaartallen komen als tekst binnen, niet als getal');
      expect(f.label, isNull);
    });

    test('DE VAL: een ander schema geeft null in plaats van halve feiten', () {
      expect(ArtiestFeiten.fromJson({'v': 0, 'land': 'USA'}), isNull);
      final terug = ArtiestFeiten.fromJson(_mj.toJson())!;
      expect(terug.geborenJaar, 1958);
      expect(terug.gestorvenJaar, 2009);
      expect(terug.label, 'Epic');
    });

    test('DE GRENS: leeg is leeg, en dan hoort er geen strook te komen', () {
      expect(const ArtiestFeiten().isEmpty, isTrue);
      expect(const ArtiestFeiten(aantalLeden: 4).isEmpty, isTrue,
          reason: 'alleen een ledental is geen feitenstrook waard');
      expect(const ArtiestFeiten(land: 'BE').isEmpty, isFalse);
    });
  });
}
