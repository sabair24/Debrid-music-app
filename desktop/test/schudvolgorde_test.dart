/// De volgorde waarin vijfduizend nummers klinken als je op shuffle drukt.
///
/// **Waarom dit zoveel toetsen waard is.** Elke fout hier valt niet om maar doet stilletjes het
/// verkeerde, en je merkt het pas na een week luisteren: een nummer dat in de trekking verdwijnt,
/// een blok dat in bibliotheekvolgorde blijft plakken, een lievelingsnummer dat je nooit meer hoort,
/// of — de klacht waar dit uit voortkwam — dezelfde liedjes die telkens terugkomen.
///
/// Zuiver: nummers en getallen in, een volgorde uit. Geen netwerk, geen schijf, dus na te meten
/// zonder toestel. `Random(7)` overal, zodat deze toets nooit kan flakkeren.
library;

import 'dart:math';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/schudvolgorde.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(String naam, {String artiest = 'A', String plaat = 'P'}) =>
    Track(path: '/m/$naam.flac', title: naam, artist: artiest, album: plaat);

List<Track> reeks(int n, {String artiest = 'A', String plaat = 'P'}) =>
    [for (var i = 0; i < n; i++) t('n$i', artiest: artiest, plaat: plaat)];

List<String> paden(Iterable<Track> ts) => [for (final x in ts) x.path];

void main() {
  group('de trekking blijft een permutatie', () {
    test('niets kwijt, niets erbij, ook niet bij duizend nummers', () {
      final alles = reeks(1000);
      final uit = gewogenVolgorde(alles, gewicht: (_) => 1, toeval: Random(7));
      expect(uit.length, alles.length);
      expect(paden(uit).toSet(), paden(alles).toSet());
    });

    test('hetzelfde pad twee keer blijft twee keer', () {
      // Een wachtrij mag hetzelfde nummer twee keer bevatten. Zou de trekking op pad ontdubbelen,
      // dan klopt de lengte niet meer met de index die de speaker terugmeldt.
      final zelfde = t('a');
      final uit = gewogenVolgorde([zelfde, t('b'), zelfde], gewicht: (_) => 1, toeval: Random(7));
      expect(uit.length, 3);
      expect(paden(uit).where((p) => p == zelfde.path).length, 2);
    });

    test('dezelfde zaadkorrel geeft dezelfde volgorde', () {
      final alles = reeks(200);
      expect(paden(gewogenVolgorde(alles, gewicht: (_) => 1, toeval: Random(7))),
          paden(gewogenVolgorde(alles, gewicht: (_) => 1, toeval: Random(7))));
    });

    test('een leeg of eenkoppig lijstje gooit niet', () {
      expect(gewogenVolgorde(const <Track>[], gewicht: (_) => 1, toeval: Random(7)), isEmpty);
      expect(gewogenVolgorde([t('a')], gewicht: (_) => 1, toeval: Random(7)).length, 1);
    });

    test('DE KERN: een piepklein gewicht loopt niet onder en zet niets vast', () {
      // Dit is waarom de sleutel `-ln(u)/w` is en niet `u^(1/w)`. Die laatste loopt bij een bodem
      // van 0,02 onder naar exact 0,0; alle ondergelopen sleutels zijn dan gelijk, `List.sort` is in
      // Dart niet stabiel, en je krijgt een blok in bibliotheekvolgorde. Een shuffle die
      // alfabetisch begint, en niets dat gooit.
      final alles = reeks(300);
      final een = paden(gewogenVolgorde(alles, gewicht: (_) => .02, toeval: Random(7)));
      final twee = paden(gewogenVolgorde(alles, gewicht: (_) => .02, toeval: Random(8)));
      expect(een, isNot(paden(alles)), reason: 'niet in bibliotheekvolgorde blijven staan');
      expect(een, isNot(twee), reason: 'twee zaadkorrels horen twee volgordes te geven');
      expect(een.toSet().length, alles.length);
    });
  });

  group('het gewicht', () {
    const nu = 1800000000000;
    int dagenTerug(int d) => nu - d * Duration.millisecondsPerDay;

    test('nooit gehoord weegt het zwaarst', () {
      expect(gewichtVan(null, nuMs: nu), 1.0);
      expect(gewichtVan(const Speelstand(), nuMs: nu), 1.0);
    });

    test('vaker gehoord weegt lichter, en dat daalt netjes', () {
      final een = gewichtVan(Speelstand(aantal: 1, laatstMs: nu), nuMs: nu);
      final vier = gewichtVan(Speelstand(aantal: 4, laatstMs: nu), nuMs: nu);
      final twintig = gewichtVan(Speelstand(aantal: 20, laatstMs: nu), nuMs: nu);
      expect(een, lessThan(1));
      expect(vier, lessThan(een));
      expect(twintig, lessThan(vier));
    });

    test('langer geleden weegt weer zwaarder', () {
      // Bij vijfduizend nummers moet een hoek die je een half jaar niet hoorde gewoon weer meedoen.
      final vandaag = gewichtVan(Speelstand(aantal: 5, laatstMs: nu), nuMs: nu);
      final maand = gewichtVan(Speelstand(aantal: 5, laatstMs: dagenTerug(30)), nuMs: nu);
      final jaar = gewichtVan(Speelstand(aantal: 5, laatstMs: dagenTerug(365)), nuMs: nu);
      expect(maand, greaterThan(vandaag));
      expect(jaar, greaterThan(maand));
      expect(jaar, greaterThan(.9));
    });

    test('DE KERN: het gewicht wordt nooit nul', () {
      // Een lievelingsnummer moet vooraan KUNNEN vallen. Wordt dit nul, dan is het geen shuffle meer
      // maar een lijstje — en dat is precies wat er niet gevraagd is.
      for (final n in [1, 10, 100, 100000]) {
        final w = gewichtVan(Speelstand(aantal: n, laatstMs: nu), nuMs: nu);
        expect(w, greaterThan(0), reason: '$n keer');
        expect(w, lessThanOrEqualTo(1), reason: '$n keer');
      }
    });

    test('een klok die verkeerd staat maakt er geen puinhoop van', () {
      // Een toestel dat in de toekomst staat is "zojuist", niet "over een jaar".
      final straks = gewichtVan(Speelstand(aantal: 5, laatstMs: nu + 999999999), nuMs: nu);
      expect(straks, gewichtVan(Speelstand(aantal: 5, laatstMs: nu), nuMs: nu));
    });
  });

  group('DE KERN: de weging bijt, maar sluit niets uit', () {
    test('veel gespeelde nummers komen gemiddeld ver achteraan', () {
      // Twintig van de tweehonderd zijn stukgedraaid. Over driehonderd trekkingen hoort hun
      // gemiddelde plek diep in de achterste helft te liggen.
      const nu = 1800000000000;
      final alles = reeks(200);
      final stuk = {for (var i = 0; i < 20; i++) alles[i].path};
      double gewicht(Track x) => gewichtVan(
          stuk.contains(x.path) ? Speelstand(aantal: 12, laatstMs: nu) : null,
          nuMs: nu);

      final toeval = Random(7);
      var som = 0.0;
      var vroegGezien = false;
      for (var ronde = 0; ronde < 300; ronde++) {
        final uit = gewogenVolgorde(alles, gewicht: gewicht, toeval: toeval);
        for (var i = 0; i < uit.length; i++) {
          if (!stuk.contains(uit[i].path)) continue;
          som += i;
          if (i < uit.length * .1) vroegGezien = true;
        }
      }
      final gemiddeld = som / (300 * stuk.length);
      expect(gemiddeld, greaterThan(alles.length * .6),
          reason: 'stukgedraaide nummers horen achteraan te belanden');
      expect(vroegGezien, isTrue,
          reason: 'maar ze moeten er wel bij KUNNEN zitten — anders is het een lijstje');
    });
  });

  group('spreiding', () {
    test('dezelfde artiest komt niet naast zichzelf te staan', () {
      final alles = [
        for (var a = 0; a < 20; a++)
          for (var i = 0; i < 25; i++) t('a${a}n$i', artiest: 'Artiest $a', plaat: 'Plaat $a'),
      ];
      final geschud = gewogenVolgorde(alles, gewicht: (_) => 1, toeval: Random(7));
      final uit = uitElkaar(geschud);

      int buren(List<Track> lijst, {int tot = -1}) {
        final eind = tot < 0 ? lijst.length : tot;
        var n = 0;
        for (var i = 1; i < eind; i++) {
          if (lijst[i].artist == lijst[i - 1].artist) n++;
        }
        return n;
      }

      // Zolang er nog keus is hoort het waterdicht te zijn.
      expect(buren(uit, tot: (uit.length * .75).round()), 0);
      // Helemaal achteraan is de vijver bijna leeg: wat er dan nog ligt kán van dezelfde artiest
      // zijn, en dan hoort dit niets te forceren. Over de hele lijst moet het wel dramatisch beter
      // zijn dan puur toeval — anders doet de spreiding niets.
      expect(buren(uit), lessThan(buren(geschud) / 3),
          reason: 'zonder spreiden waren het er ${buren(geschud)}');
      expect(paden(uit).toSet(), paden(alles).toSet(), reason: 'spreiden mag niets kwijtraken');
    });

    test('één artiest in de hele bibliotheek is geen fout', () {
      // Dan is klonteren onvermijdelijk, en dan hoort dit niets te doen in plaats van te blijven
      // zoeken of te gooien.
      final uit = uitElkaar(reeks(50));
      expect(uit.length, 50);
      expect(paden(uit).toSet(), paden(reeks(50)).toSet());
    });

    test('wat al geklonken heeft blijft staan', () {
      final alles = [
        for (var i = 0; i < 30; i++) t('n$i', artiest: 'Artiest ${i % 4}', plaat: 'Plaat ${i % 4}'),
      ];
      final uit = uitElkaar(alles, vanaf: 10);
      expect(paden(uit.take(10)), paden(alles.take(10)));
    });
  });

  group('wanneer telt een nummer als beluisterd', () {
    test('de helft van een gewoon nummer', () {
      const drieMin = Duration(minutes: 3);
      expect(telMeeAlsGespeeld(geluisterd: const Duration(seconds: 89), duur: drieMin), isFalse);
      expect(telMeeAlsGespeeld(geluisterd: const Duration(seconds: 90), duur: drieMin), isTrue);
    });

    test('twee minuten is het plafond, ook bij een lange plaatkant', () {
      // Anders zou een stuk van twintig minuten pas na tien minuten meetellen, en wie tien minuten
      // luistert heeft het gehoord.
      expect(
          telMeeAlsGespeeld(
              geluisterd: const Duration(minutes: 2), duur: const Duration(minutes: 20)),
          isTrue);
    });

    test('een kort nummer is er ook zo doorheen', () {
      expect(
          telMeeAlsGespeeld(
              geluisterd: const Duration(seconds: 21), duur: const Duration(seconds: 40)),
          isTrue);
    });

    test('duur onbekend: dan gelden alleen de twee minuten', () {
      for (final duur in [null, Duration.zero]) {
        expect(telMeeAlsGespeeld(geluisterd: const Duration(seconds: 119), duur: duur), isFalse);
        expect(telMeeAlsGespeeld(geluisterd: const Duration(minutes: 2), duur: duur), isTrue);
      }
    });

    test('wegklikken telt niet mee', () {
      // De hele reden dat dit bestaat: doorskippen op zoek naar iets mag geen nummers naar achteren
      // duwen die je nooit gehoord hebt.
      expect(
          telMeeAlsGespeeld(
              geluisterd: const Duration(seconds: 10), duur: const Duration(minutes: 4)),
          isFalse);
    });
  });

  group('DE KERN: een druk op shuffle herhaalt niets wat al klonk', () {
    test('de prefix blijft staan en komt niet terug in de staart', () {
      // Dit is de klacht van 28-08-2026 als toets. `toggleShuffle` bouwde een compleet nieuwe
      // volgorde van ALLES met de index terug op nul, dus alles wat je net gehoord had stond weer
      // voor je. Android Auto loopt langs diezelfde knop.
      final alles = reeks(60);
      final gespeeld = alles.take(12).toList();
      final anker = alles[12];
      final uit = ordenVoor(alles, anker,
          shuffle: true, reedsGespeeld: gespeeld, toeval: Random(7));

      expect(paden(uit.order.take(12)), paden(gespeeld), reason: 'het verleden staat er nog, op volgorde');
      expect(uit.index, 12);
      expect(uit.order[uit.index].path, anker.path, reason: 'wat er klinkt blijft klinken');
      final staart = paden(uit.order.skip(13)).toSet();
      for (final g in gespeeld) {
        expect(staart.contains(g.path), isFalse, reason: '${g.title} kwam terug');
      }
      expect(uit.order.length, alles.length);
      expect(paden(uit.order).toSet(), paden(alles).toSet());
    });

    test('zonder verleden begint hij gewoon vooraan', () {
      final alles = reeks(20);
      final uit = ordenVoor(alles, null, shuffle: true, toeval: Random(7));
      expect(uit.index, 0);
      expect(uit.order.length, 20);
    });
  });

  group('zonder de nieuwe argumenten verandert er niets', () {
    // Dezelfde eigenschappen die cast_control_test.dart al eist. Ze staan hier nog een keer omdat
    // deze toets wél in de bouwstraat draait en die tot vandaag niet.
    final alles = reeks(12);

    test('op de teruggegeven index staat het anker', () {
      final uit = ordenVoor(alles, alles[4], shuffle: true, toeval: Random(7));
      expect(uit.order[uit.index].path, alles[4].path);
    });

    test('dezelfde nummers, alleen anders gerangschikt', () {
      final uit = ordenVoor(alles, alles[4], shuffle: true, toeval: Random(7));
      expect(uit.order.length, alles.length);
      expect(paden(uit.order).toSet(), paden(alles).toSet());
    });

    test('shuffle uit: de oorspronkelijke volgorde, en de index zoekt het nummer op', () {
      final uit = ordenVoor(alles, alles[7], shuffle: false);
      expect(paden(uit.order), orderedEquals(paden(alles)));
      expect(uit.index, 7);
    });

    test('leeg blijft leeg', () {
      expect(ordenVoor(const <Track>[], null, shuffle: true).order, isEmpty);
    });
  });

  group('de prefix eruit halen gaat per stuk, niet per pad', () {
    test('hetzelfde nummer twee keer: er gaat er precies één weg', () {
      final zelfde = t('a');
      final over = zonder([zelfde, t('b'), zelfde], [zelfde]);
      expect(paden(over).where((p) => p == zelfde.path).length, 1);
      expect(over.length, 2);
    });

    test('wat er niet in staat verandert niets', () {
      final alles = reeks(3);
      expect(paden(zonder(alles, [t('vreemd')])), paden(alles));
      expect(paden(zonder(alles, const [])), paden(alles));
    });
  });
}
