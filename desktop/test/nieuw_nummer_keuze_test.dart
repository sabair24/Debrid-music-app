// Een tik of ▶ op een nummer dat je nog niet hebt, krijgt hetzelfde menu als je eigen nummers, en het halen loopt op
// de achtergrond (Saber, 22-10-2026: "liedjes die ik nog niet heb, wil ik ook kunnen klikken en als volgende spelen
// kiezen … en dan kan het liedje als downloaden op de achtergrond … of als ik zeg nu spelen maar de wachtrij laten
// staan").
import 'dart:io';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart' show TikKeuze, gelandTekst, naLandenTekst, tikKeuzeIcoon;

String _lees(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// Het stuk van [tekst] vanaf [van] tot [tot] (beide moeten erin staan).
String _stuk(String tekst, String van, String tot) {
  final a = tekst.indexOf(van);
  expect(a, greaterThanOrEqualTo(0), reason: 'niet gevonden: $van');
  final b = tekst.indexOf(tot, a);
  expect(b, greaterThan(a), reason: 'niet gevonden: $tot');
  return tekst.substring(a, b);
}

void main() {
  group('wat je hoort', () {
    test('bij het begin zegt hij wat er straks gebeurt', () {
      expect(naLandenTekst(TikKeuze.hierna), 'komt hierna zodra hij er is');
      expect(naLandenTekst(TikKeuze.achteraan), 'komt achteraan zodra hij er is');
      expect(naLandenTekst(TikKeuze.nu), contains('de wachtrij blijft staan'));
      expect(naLandenTekst(TikKeuze.vragen), naLandenTekst(TikKeuze.vervang));
    });

    test('en als hij er is', () {
      expect(gelandTekst(TikKeuze.hierna), 'komt hierna');
      expect(gelandTekst(TikKeuze.achteraan), 'staat achteraan in de wachtrij');
      expect(gelandTekst(TikKeuze.nu), contains('de wachtrij blijft staan'));
    });

    test('elke keuze een eigen icoon, zoals in het menu van je eigen nummers', () {
      final iconen = {for (final k in const [TikKeuze.vervang, TikKeuze.nu, TikKeuze.hierna, TikKeuze.achteraan]) tikKeuzeIcoon(k)};
      expect(iconen, hasLength(4));
      expect(tikKeuzeIcoon(TikKeuze.hierna), Icons.playlist_play_rounded);
    });
  });

  group('aangesloten', () {
    final main = _lees('lib/main.dart');

    test('één menu voor eigen en nieuwe nummers, en "Altijd zo" geldt voor allebei', () {
      final eigen = _stuk(main, 'Future<void> speelGetikt(BuildContext context, List<Track> lijst', '\n}\n');
      expect(eigen, contains('await _kiesTikKeuze(context, titel: t.title, artiest: t.artist);'));
      final nieuw = _stuk(main, 'Future<void> speelGetiktNieuw(BuildContext context,', '\n}\n');
      expect(nieuw, contains('if (tikVraagtIets(speelt: speler.current != null, radio: speler.radioMode, lengte: speler.queueTracks.length)) {'),
          reason: 'zonder wachtrij gewoon spelen, zoals bij je eigen nummers');
      expect(nieuw, contains('keuze = tikKeuzeUit(instellingen.tikKeuze);'), reason: 'de vaste keuze van dit toestel');
      expect(nieuw, contains('await _kiesTikKeuze(context, titel: titel, artiest: artiest);'));
      expect(nieuw, contains('altijdZo: gevraagd ? () => _altijdZo(instellingen, k) : null);'));
    });

    test('▶, een nieuw nummer, en een regel van "Bekend, nog niet van jou" gaan langs het menu', () {
      expect(_stuk(main, 'class SpeelNuKnop extends StatelessWidget {', 'class NieuwSpeler'),
          contains('onPressed: () => speelGetiktNieuw(context,'));
      expect(_stuk(main, '  Future<void> speel(BuildContext context, NieuwNummer n)', ';\n'),
          contains('speelGetiktNieuw(context,'));
      final bekend = _stuk(main, 'class _BekendNietVanJou extends StatelessWidget {', 'class ArtistBrowsePage');
      expect(bekend, contains('onTap: () => speelGetiktNieuw(context,'));
      final menu = _stuk(main, 'void _nieuwNummerMenu(BuildContext context, NieuwNummer n', "'Album openen'");
      expect(menu, contains('_StartCache.nieuwSpeler.speelAls(context, n, k)'), reason: 'lang drukken: de vier keuzes meteen');
    });

    test('hierna en achteraan nemen de speler niet over: geen tik, geen vroege stroom, geen TorBox-stroom', () {
      final s = _stuk(main, '  Future<void> speelNummer(BuildContext context,', 'File get _nieuwOpToestel');
      expect(s, contains('final mijnTik = zetInRij ? _tikken : ++_tikken;'),
          reason: 'anders stopt een nummer dat hierna komt de vorige tik ("de laatste tik wint")');
      expect(s, contains('if (vroeg != null && vervangt) {\n        vroeg.zalKlinken();'));
      expect(s, contains('klinkt: vervangt ? klinktOpPc : null'));
      final begin = s.indexOf('if (!vervangt) {');
      expect(begin, greaterThan(0));
      expect(begin, lessThan(s.indexOf('final url = await online.resolveRadio(artiest, titel);')),
          reason: 'TorBox vooraf is een stroom die alleen nu kan klinken');
    });

    test('na het landen zoals gekozen; nu-met-de-rest alleen als je intussen niets anders koos', () {
      final s = _stuk(main, '  Future<void> speelNummer(BuildContext context,', 'File get _nieuwOpToestel');
      final staart = _stuk(s, 'final klinkendAdres = vroeg?.adres ?? elders?.pad;', '} else if (klinkendAdres != null && klinkt');
      expect(staart, contains('if (zetInRij || magNog()) {\n            zetNaarKeuze(t);'));
      final zet = _stuk(s, '    void zetNaarKeuze(Track t) {', '\n    }\n');
      expect(zet, contains('unawaited(speler.speelNuMetRest(t));'));
      expect(zet, contains('speler.speelHierna([t]);'));
      expect(zet, contains('speler.zetAchteraan([t]);'));
      expect(s, contains('    if (eigen != null) {\n      zetNaarKeuze(eigen);'), reason: 'al binnen: meteen zoals gevraagd');
    });

    test('"Bekend, nog niet van jou" krijgt album en hoes van Deezer, voor de hoes en de cd tijdens het streamen', () {
      final laad = _stuk(main, '  Future<void> _loadLastfmTop() async {', '\n  }\n');
      expect(laad, contains(".lijstOpDeezer([AiNummer(n.artiest, n.titel)],\n                  elders: _itunesVoorModel, eldersNaam: 'iTunes', van: 'Last.fm')"),
          reason: 'kent Deezer het niet, dan iTunes');
      expect(laad, contains('setState(() => _lastfmOpDeezer = {'));
      expect(main, contains('_BekendNietVanJou(nummers: _lastfmTop, opDeezer: _lastfmOpDeezer, marge: _marge)'));
    });
  });
}
