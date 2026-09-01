/// De meldingsbalk op een televisie: bereikbaar, en met een weg terug.
///
/// **Waarom dit bestaat.** Op de Shield gemeten op 01-09-2026, met een sleutel die de pc weigerde.
/// Op het scherm stond de oranje balk met "Opnieuw proberen" — en die knop was met de
/// afstandsbediening niet te bereiken. OMLAAG vanuit het menu sprong eroverheen naar de inhoud,
/// OMHOOG vanuit de inhoud ging terug naar het menu. De enige knop die de storing kon verhelpen
/// was precies de knop die je niet kon indrukken.
///
/// De oorzaak: de balk stond in géén enkele focusscope, en de sprongen gingen van de bovenbalk
/// rechtstreeks naar de inhoud. Er was dus geen halte.
///
/// En daaronder lag een tweede doodlopende weg: zolang er nog een kopie van de bibliotheek ligt
/// geldt de zitting als klaar, dus het koppelscherm komt nooit terug. Zonder tweede knop was er op
/// een tv geen enkele weg naar opnieuw koppelen.
///
/// Dit is een bronbewaker, net als tv_bovenbalk_test.dart. Een widgettest pumpt geen tweede route
/// en zou de scopegrens die dit veroorzaakte nooit zien; wat hier bewaakt wordt is dat de drie
/// dingen die de fout uitmaakten niet terugsluipen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late final String bron = File('lib/main.dart').readAsStringSync();

  group('de melding is een halte in de route', () {
    test('er is een eigen scope voor de melding, en hij wordt opgeruimd', () {
      expect(bron, contains("FocusScopeNode(debugLabel: 'tv-melding')"),
          reason: 'zonder eigen scope is de balk geen halte en wordt hij weer overgeslagen');
      expect(bron, contains('_tvMelding.dispose()'),
          reason: 'een scope die niet wordt opgeruimd lekt bij elke schil');
    });

    test('de balk zit in die scope, en alleen op een tv', () {
      final start = bron.indexOf('node: _tvMelding');
      expect(start, greaterThan(-1), reason: '_tvMelding wordt nergens om iets heen gezet');

      // Het stuk rond de melding: van de bovenbalk tot net na de statusstrook.
      final blok = bron.substring(
          bron.indexOf('node: _tvBalk'), bron.indexOf('const _TvStatusStrip()'));
      expect(blok, contains('_AlleenOpTv'),
          reason: 'op een pc en een telefoon mag hier geen extra scope bij — daar is de tab-volgorde '
              'in orde en zou dit hem veranderen');
      expect(blok, contains('child: const _OfflineBanner()'),
          reason: 'de scope hoort ÓM de meldingsbalk te zitten, anders is er niets te bereiken');
    });
  });

  group('de sprong slaat een lege melding over', () {
    test('_tvSprong krijgt een rijtje scopes, geen enkele', () {
      expect(bron, contains('List<FocusScopeNode> naar'),
          reason: 'met één scope kan de sprong niet uitwijken als de melding er niet staat, en dan '
              'doet de pijl niets zodra alles het gewoon doet');
    });

    test('een scope zonder iets om op te staan wordt overgeslagen', () {
      final start = bron.indexOf('KeyEventResult _tvSprong');
      expect(start, greaterThan(-1), reason: '_tvSprong is hernoemd of verdwenen');
      final lijf = bron.substring(start, start + 900);
      expect(lijf, contains('traversalDescendants.isNotEmpty'),
          reason: 'zonder deze toets landt de focus in een lege scope en verroert zich niets');
      // Eerst de pagina zelf laten proberen; pas als die niets meer heeft is de rand bereikt.
      expect(lijf.indexOf('focusInDirection'), lessThan(lijf.indexOf('requestFocus')),
          reason: 'binnen een pagina hoort de pijl gewoon te doen wat hij altijd deed');
    });

    test('omlaag vanuit het menu komt eerst bij de melding, omhoog vanuit de inhoud ook', () {
      expect(bron, contains('[_tvMelding, _tvInhoud]'),
          reason: 'omlaag vanuit de bovenbalk moet de melding vóór de inhoud proberen');
      expect(bron, contains('[_tvMelding, _tvBalk]'),
          reason: 'omhoog vanuit de inhoud moet de melding vóór de bovenbalk proberen');
    });
  });

  group('een geweigerde sleutel heeft een weg terug', () {
    /// Alleen de meldingsbalk, niet de rest van het bestand.
    String balk() {
      final start = bron.indexOf('class _OfflineBanner');
      expect(start, greaterThan(-1), reason: '_OfflineBanner is hernoemd of verdwenen');
      final eind = bron.indexOf('class _BannerKnop', start);
      expect(eind, greaterThan(start), reason: '_BannerKnop is verplaatst');
      return bron.substring(start, eind);
    }

    test('er staat een knop om opnieuw te koppelen', () {
      expect(balk(), contains("label: 'Opnieuw koppelen'"),
          reason: 'zonder deze knop is een geweigerde sleutel op een tv een doodlopende weg: het '
              'koppelscherm komt niet terug zolang er nog een kopie ligt');
      expect(balk(), contains('session.unpair()'),
          reason: 'opnieuw koppelen begint met de oude koppeling loslaten');
    });

    test('alleen bij een geweigerde sleutel, niet als de pc gewoon uit staat', () {
      expect(balk(), contains('if (!geweigerd)'),
          reason: 'staat de pc uit, dan mankeert je koppeling niets en zou deze knop je je toegang '
              'voor niets laten weggooien');
    });

    test('"Opnieuw proberen" blijft de eerste knop', () {
      final b = balk();
      expect(b.indexOf("label: 'Opnieuw proberen'"), lessThan(b.indexOf("label: 'Opnieuw koppelen'")),
          reason: 'eerst kijken of de sleutel er gewoon weer is — herkoppelen is de enige handeling '
              'die je koppeling écht weggooit');
    });

    test('er zit een bevestiging tussen', () {
      expect(balk(), contains("title: const Text('Opnieuw koppelen?')"),
          reason: 'zonder de pc erbij is dit onomkeerbaar: opnieuw koppelen kan alleen met de code '
              'van zes cijfers die de pc laat zien');
    });
  });
}
