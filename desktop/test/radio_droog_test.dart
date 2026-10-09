/// De radio valt niet meer stil — de speler-kant (plan van 08-10-2026, deel A0).
///
/// Gemeten die dag, radio vanaf "Niels Destadsbader — Vuur en vlam": na dertien nummers "0 hierna"
/// en "Radio klaar", en er klonk niets meer. Vier oorzaken in de speler zelf:
///
/// - na het laatste nummer deed `next()` niets, en de droogstand werd nooit gezet;
/// - een bestand dat er niet meer stond legde de radio stil ("Kan dit nummer niet openen");
/// - het spelende nummer weghalen zette de index op -1 en daarna op 0;
/// - "volgende" op het laatste nummer deed stilzwijgend niets.
///
/// En de foutpoort: mpv meldt een ontbrekend bestand twee keer, en de tweede melding trof het
/// volgende nummer (`speler.log`, 18:23:22.785: "Me And I — Failed to open …Super Trouper.flac.").
library;

import 'dart:async';
import 'dart:io';

import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/vooruithalen.dart' show isNetwerkfout;
import 'package:flutter_test/flutter_test.dart';

/// Een nagespeelde mpv met een rij bestanden, zoals media_kit 1.2.6 zich gedraagt: `playing` staat na
/// elke opening op waar, ook als die mislukt — alleen de TELLER zegt of het speelt. [stuk] staat er
/// niet, [netStuk] is een stroom van een pc die weg is, de rest loopt na 5 ms — behalve [traag], dat op
/// 0:00 blijft (de pc zet om).
class _Mpv {
  _Mpv(this.paden,
      {this.stuk = const {}, this.netStuk = const {}, this.traag = const {}, this.verdacht = const {}});

  final List<String> paden;
  final Set<String> stuk;
  final Set<String> netStuk;
  final Set<String> traag;

  /// Speelbaar maar traag aan de start, en de bestandscontrole slaat er ten onrechte op aan.
  final Set<String> verdacht;

  int i = 0;
  bool loopt = false;
  bool droog = false;
  final overgeslagen = <String>[];
  var pogingen = 0;
  final wachtstand = <String>[];
  final verwerkt = <String>[];
  final _failed = <String>{};
  late final Radiofoutpoort poort = Radiofoutpoort(
    naarVolgende: () async {
      if (i < paden.length - 1) {
        i++;
        open();
      } else {
        droog = true;
      }
    },
    verwerk: verwerk,
    bestandsreden: reden,
    overslaan: overslaan,
    stand: () => (radio: true, pad: paden[i], adres: paden[i], opNul: !loopt, netwacht: false, droog: droog),
    adem: const Duration(milliseconds: 20),
  );

  String? reden(String? p) =>
      p != null && (stuk.contains(p) || verdacht.contains(p)) ? 'het bestand staat er niet meer' : null;

  /// Zoals `_radioOverslaan`: één keer per nummer.
  void overslaan(String r) {
    pogingen++;
    if (_failed.contains(paden[i]) && droog) return;
    _failed.add(paden[i]);
    overgeslagen.add(paden[i]);
    unawaited(poort.slaOver());
  }

  /// Zoals de echte mpv: bij een ontbrekend bestand twee meldingen, ~1 ms na elkaar, in de twee
  /// vormen uit `speler.log`; bij een weggevallen pc eerst de tcp-regel en dan "Failed to open".
  void open() {
    loopt = false;
    final p = paden[i];
    if (stuk.contains(p)) {
      Timer(const Duration(milliseconds: 1),
          () => poort.melding("Cannot open file '\\\\?\\$p': No such file or directory"));
      Timer(const Duration(milliseconds: 2), () => poort.melding('Failed to open \\\\?\\$p.'));
    } else if (netStuk.contains(p)) {
      Timer(const Duration(milliseconds: 1), () => poort.melding('tcp: Connection timed out'));
      Timer(const Duration(milliseconds: 2), () => poort.melding('Failed to open $p.'));
    } else if (!traag.contains(p) && !verdacht.contains(p)) {
      Timer(const Duration(milliseconds: 5), () {
        if (paden[i] == p) loopt = true;
      });
    }
  }

  /// Zoals `_verwerkFout`: eerst naar het bestand van wat NU aan de beurt is kijken.
  void verwerk(String e) {
    verwerkt.add(e);
    final r = reden(paden[i]);
    if (r != null && !loopt) {
      overslaan(r);
      return;
    }
    if (r == null) wachtstand.add(paden[i]);
  }
}

Future<void> _rust() => Future<void>.delayed(const Duration(milliseconds: 200));

void main() {
  group('na het laatste nummer', () {
    test('DE KERN: het laatste nummer is droog, de rest gaat door', () {
      expect(naRadioEinde(index: 0, lengte: 3), NaRadioEinde.volgende);
      expect(naRadioEinde(index: 1, lengte: 3), NaRadioEinde.volgende);
      expect(naRadioEinde(index: 2, lengte: 3), NaRadioEinde.droog);
      expect(naRadioEinde(index: 0, lengte: 1), NaRadioEinde.droog);
    });

    test('DE GRENS: een lege rij is droog', () {
      expect(naRadioEinde(index: -1, lengte: 0), NaRadioEinde.droog);
    });

    test('weghalen zet de index op het laatste dat over is, niet op -1 of 0', () {
      expect(radioIndexNaWeghalen(lengteNa: 13), 12);
      expect(radioIndexNaWeghalen(lengteNa: 1), 0);
      expect(radioIndexNaWeghalen(lengteNa: 0), -1);
    });
  });

  group('de tekst onder de titel', () {
    test('DE KERN: zolang de radio loopt nooit "Radio klaar"', () {
      for (final droog in [false, true]) {
        for (final wilVerder in [false, true]) {
          final s = radioStatusTekst(
              spelerStatus: 'Radio klaar', droog: droog, wilVerder: wilVerder, loopt: true);
          expect(s, isNot('Radio klaar'), reason: 'droog=$droog wilVerder=$wilVerder');
        }
      }
    });

    test('droog of "volgende" op het laatste: hij zoekt, of zegt wat er speelt', () {
      expect(radioStatusTekst(spelerStatus: 'Radio klaar', droog: true, wilVerder: false, loopt: true),
          'Zoekt het volgende nummer…');
      expect(radioStatusTekst(spelerStatus: '', droog: false, wilVerder: true, loopt: true),
          'Zoekt het volgende nummer…');
      expect(
          radioStatusTekst(
              spelerStatus: '',
              droog: true,
              wilVerder: false,
              loopt: true,
              stand: 'Herhaalt nummers van eerder in deze radio tot er iets nieuws is'),
          'Herhaalt nummers van eerder in deze radio tot er iets nieuws is');
    });

    test('een radio uit een zin die zijn aantal gespeeld heeft, zegt dat', () {
      expect(
          radioStatusTekst(
              spelerStatus: '', droog: true, wilVerder: false, loopt: true, aantalBereikt: true, aantal: 300),
          'Je vroeg 300 nummers — de radio stopt hier');
      // Zolang er nog iets speelt, niet: dan staat de artiest er gewoon.
      expect(
          radioStatusTekst(
              spelerStatus: '', droog: false, wilVerder: false, loopt: true, aantalBereikt: true, aantal: 300),
          isNull);
    });

    test('wat de speler zelf meldt blijft staan; een oude "Radio klaar" niet', () {
      expect(
          radioStatusTekst(spelerStatus: 'Bron zoeken: Bazart — Goud…', droog: false, wilVerder: false, loopt: true),
          'Bron zoeken: Bazart — Goud…');
      expect(radioStatusTekst(spelerStatus: 'Radio klaar', droog: false, wilVerder: false, loopt: true), isNull);
      expect(radioStatusTekst(spelerStatus: '', droog: false, wilVerder: false, loopt: true), isNull);
      // Gestopt: dan mag het.
      expect(radioStatusTekst(spelerStatus: 'Radio klaar', droog: true, wilVerder: false, loopt: false),
          'Radio klaar');
    });

    test('de kop: "0 hierna" alleen met wat hij nog doet erbij', () {
      expect(radioKop(hierna: 0, onderweg: 6, loopt: true), '0 hierna · 6 onderweg');
      expect(radioKop(hierna: 2, onderweg: 6, loopt: true), '2 hierna · 6 onderweg');
      expect(radioKop(hierna: 0, onderweg: 0, loopt: true), '0 hierna · zoekt verder');
      expect(radioKop(hierna: 5, onderweg: 0, loopt: true), '5 hierna');
      expect(radioKop(hierna: -1, onderweg: 0, loopt: true), '0 hierna · zoekt verder');
      expect(radioKop(hierna: 2, onderweg: 6, loopt: false), '2 hierna');
    });

    test('DE GRENS: geen "zoekt verder" als hij niet zoekt', () {
      expect(radioKop(hierna: 0, onderweg: 0, loopt: true, zoekt: false), '0 hierna');
    });
  });

  group('welk bestand een melding noemt', () {
    const pad = r'D:\Flac music 2024\DebridMusic Downloads\Singles\ABBA\Super Trouper.flac';
    const ander = r'D:\Flac music 2024\DebridMusic Downloads\Singles\ABBA\Me And I.flac';

    test('DE KERN: de tweede vorm, zonder aanhalingstekens, noemt ook een bestand', () {
      // Letterlijk de regel van 18:23:22.785, maar dan op het nummer dat al aan de beurt was.
      expect(meldtAnderBestand('Failed to open \\\\?\\$pad.', [ander]), isTrue);
      expect(meldtAnderBestand("Cannot open file '\\\\?\\$pad': No such file or directory", [ander]), isTrue);
    });

    test('hetzelfde bestand, met voorvoegsel en punt, is niet een ander', () {
      expect(meldtAnderBestand('Failed to open \\\\?\\$pad.', [pad]), isFalse);
      expect(meldtAnderBestand("Cannot open file '\\\\?\\$pad': No such file or directory", [pad]), isFalse);
    });

    test("DE VAL: een apostrof in de naam (Guns N' Roses) maakt het geen ander bestand", () {
      const gnr = r"D:\Flac music 2024\Singles\Guns N' Roses\Knockin' On Heaven's Door.flac";
      expect(meldtAnderBestand('Failed to open \\\\?\\$gnr.', [gnr]), isFalse);
      expect(meldtAnderBestand("Cannot open file '\\\\?\\$gnr': No such file or directory", [gnr]), isFalse);
      expect(meldtAnderBestand("Cannot open file '\\\\?\\$gnr': No such file or directory", [ander]), isTrue);
    });

    test('een stroom: het adres dat mpv kreeg telt, ook met een reden erachter', () {
      const url = 'http://100.97.101.113:47820/api/stream?id=abc';
      expect(meldtAnderBestand('Failed to open $url: Connection refused', ['abc.flac', url]), isFalse);
      expect(meldtAnderBestand('Failed to open http://andere/stream', ['abc.flac', url]), isTrue);
    });

    test('een melding zonder bestand geldt voor het huidige nummer', () {
      expect(meldtAnderBestand('Error decoding audio.', [pad]), isFalse);
      expect(meldtAnderBestand('Failed to recognize file format.', [pad]), isFalse);
      expect(meldtAnderBestand('tcp: Connection timed out', [pad]), isFalse);
    });
  });

  group('de foutpoort, nagespeeld met de meldingen van mpv', () {
    test('DE KERN: twee meldingen van één bestand slaan precies één nummer over', () async {
      // Het volgende nummer blijft op 0:00 (de pc zet om) — juist dan trof de tweede melding het.
      final m = _Mpv(['/a.flac', '/b.flac'], stuk: {'/a.flac'}, traag: {'/b.flac'});
      m.open();
      await _rust();
      expect(m.overgeslagen, ['/a.flac']);
      expect(m.wachtstand, isEmpty, reason: 'de late melding van a mag b geen herkansing geven');
      expect(m.i, 1);
    });

    test('DE VAL: twee ontbrekende bestanden achter elkaar: allebei weg, het derde speelt', () async {
      final m = _Mpv(['/a.flac', '/b.flac', '/c.flac'], stuk: {'/a.flac', '/b.flac'});
      m.open();
      await _rust();
      expect(m.overgeslagen, ['/a.flac', '/b.flac']);
      expect(m.i, 2);
      expect(m.loopt, isTrue);
    });

    test('drie op rij (een verplaatste keuringsmap): de radio valt niet stil', () async {
      final m = _Mpv(['/a.flac', '/b.flac', '/c.flac', '/d.flac'], stuk: {'/a.flac', '/b.flac', '/c.flac'});
      m.open();
      await _rust();
      expect(m.overgeslagen, ['/a.flac', '/b.flac', '/c.flac']);
      expect(m.loopt, isTrue);
    });

    test('DE GRENS: het laatste nummer ontbreekt — één keer overgeslagen, droog, geen lus', () async {
      final m = _Mpv(['/a.flac'], stuk: {'/a.flac'});
      m.open();
      await _rust();
      expect(m.overgeslagen, ['/a.flac']);
      expect(m.droog, isTrue);
      expect(m.pogingen, 1, reason: 'een droge radio wordt niet nog eens overgeslagen');
    });

    test("met een apostrof in de naam blijft het niet liggen", () async {
      const a = r"/Guns N' Roses/Knockin' On Heaven's Door.flac";
      const b = r"/Guns N' Roses/Patience.flac";
      final m = _Mpv([a, b, '/c.flac'], stuk: {a, b});
      m.open();
      await _rust();
      expect(m.overgeslagen, [a, b]);
      expect(m.loopt, isTrue);
    });

    test('een netwerkfout van het volgende nummer: de tcp-regel gaat voor, niets overgeslagen', () async {
      final m = _Mpv(['/a.flac', 'http://pc/b'], stuk: {'/a.flac'}, netStuk: {'http://pc/b'});
      m.open();
      await _rust();
      expect(m.overgeslagen, ['/a.flac']);
      expect(m.wachtstand, ['http://pc/b'], reason: 'naar de wachtstand, niet overgeslagen en niet weg');
      expect(m.verwerkt.where(isNetwerkfout), isNotEmpty, reason: 'de speler moet horen dat het het net is');
      expect(m.verwerkt.last, 'tcp: Connection timed out');
    });

    test('DE GRENS: zonder melding wordt niets op verdenking overgeslagen', () async {
      final m = _Mpv(['/a.flac', '/b.flac'], stuk: {'/a.flac'}, verdacht: {'/b.flac'});
      m.open();
      await _rust();
      expect(m.overgeslagen, ['/a.flac'], reason: 'b start traag, maar niemand meldde dat het stuk is');
    });

    test('buiten een overslag gaat een melding meteen door', () {
      final m = _Mpv(['http://pc/a'], netStuk: {'http://pc/a'});
      expect(m.poort.open, isFalse);
      m.poort.melding('Failed to open http://pc/a');
      expect(m.wachtstand, ['http://pc/a']);
    });
  });

  group('de tweede regel van een netwerkfout', () {
    test('DE KERN: zolang de wachtklok loopt, is "Failed to open" de tweede regel', () {
      expect(
          isTweedeRegelVanNetfout(radio: true, fout: 'Failed to open http://pc/b.', klokLoopt: true, wachtVoorDit: true),
          isTrue);
    });

    test('DE VAL: de pc is terug en antwoordt met een gewone fout — die krijgt zijn herkansing', () {
      // De klok is afgegaan (of de verbinding meldde zich): geen klok meer, en dan is een 404 een 404.
      expect(
          isTweedeRegelVanNetfout(radio: true, fout: 'Failed to open http://pc/b.', klokLoopt: false, wachtVoorDit: true),
          isFalse);
    });

    test('een netwerkfout zelf, een ander nummer, of geen radio: niet negeren', () {
      expect(isTweedeRegelVanNetfout(radio: true, fout: 'tcp: Connection timed out', klokLoopt: true, wachtVoorDit: true),
          isFalse);
      expect(
          isTweedeRegelVanNetfout(radio: true, fout: 'Failed to open http://pc/b.', klokLoopt: true, wachtVoorDit: false),
          isFalse);
      expect(
          isTweedeRegelVanNetfout(radio: false, fout: 'Failed to open http://pc/b.', klokLoopt: true, wachtVoorDit: true),
          isFalse);
    });
  });

  group('de bedrading', () {
    final speler = File('lib/player.dart').readAsStringSync();
    final scherm = File('lib/main.dart').readAsStringSync();

    String stuk(String bron, String begin, [int lengte = 2500]) {
      final i = bron.indexOf(begin);
      expect(i, greaterThanOrEqualTo(0), reason: 'niet gevonden: $begin');
      return bron.substring(i, (i + lengte).clamp(0, bron.length));
    }

    test('na het laatste nummer: droog, niet next()', () {
      final s = stuk(speler, 'void _onCompleted()');
      expect(s, contains('naRadioEinde(index: _radioIndex, lengte: _radio.length) == NaRadioEinde.droog'));
      expect(s, contains('_radioDroog = true'));
    });

    test('elke melding in radiostand gaat door de poort, en de poort kent het droge en het wachten', () {
      expect(stuk(speler, '_player.stream.error.listen(', 600), contains('_poort.melding(e)'));
      final st = stuk(speler, 'late final Radiofoutpoort _poort', 900);
      expect(st, contains('netwacht: _pcKlok != null && _pcWachtVoor != null && _pcWachtVoor == current?.path'));
      expect(st, isNot(contains('speelt')), reason: 'media_kit zet playing ook na een mislukte open op waar');
      expect(st, contains('droog: _radioDroog'));
    });

    test('een bestandsreden op 0:00 slaat over, ook na een mislukte tweede poging', () {
      expect(
          stuk(speler, 'void _verwerkFout(String e)', 3500),
          contains('      if (eigen != null && radioMode && position == Duration.zero) {\n'
              '        unawaited(_radioOverslaan(eigen, bestand: true));\n'
              '        return;\n'
              '      }'));
      expect(speler, contains("_radioOverslaan('ook de tweede poging mislukte', bestand: false)"));
      final o = stuk(speler, 'Future<void> _radioOverslaan(', 700);
      expect(o, contains('if (it.failed && _radioDroog) return;'));
      expect(o, contains('_stopPcWacht();'));
    });

    test('DE VAL: wachten op de pc slaat niets over', () {
      expect(stuk(speler, 'case NaOpenfout.opgeven when radioMode:', 400), contains("'Wacht op de pc…'"));
      expect(stuk(speler, 'void _naOpenfout(String fout)', 1200),
          contains('if (isTweedeRegelVanNetfout(\n        radio: radioMode,\n        fout: fout,\n'
              '        klokLoopt: _pcKlok != null,\n'
              '        wachtVoorDit: _pcWachtVoor != null && _pcWachtVoor == current?.path)) {\n      return;'));
      expect(stuk(speler, 'void _probeerNogEens()', 900),
          contains('_herkansingGedaanVoor == t.path && !(_pcKlok != null && _pcWachtVoor == t.path)'));
      expect(scherm.contains('player.pcWeerBereikbaar();'), isTrue, reason: 'de verbinding is terug: meteen opnieuw');
    });

    test('weghalen, volgende, een landing en een pauze', () {
      final v = stuk(speler, 'Future<void> vergeetPaden(', 3000);
      expect(v, contains('if (radioMode) {\n          _radioDroog = true;'));
      expect(v, contains('radioIndexNaWeghalen(lengteNa: _radio.length)'));
      expect(stuk(speler, 'Future<void> next() async {', 800), contains('_wilVerder = true'));
      expect(stuk(speler, 'void voegToeAanRadio(', 600),
          contains('if (_radioDroog || _wilVerder) {\n      // Eén sprong: de vlag gaat hier uit, anders brak elke '
              'volgende landing het spelende nummer af.\n      _radioDroog = false;\n      _wilVerder = false;'));
      expect(stuk(speler, 'void playPause() {', 300), contains('if (playing) _wilVerder = false;'));
      expect(stuk(speler, 'void pauzeer() {', 400), contains('_wilVerder = false;'));
    });

    test('een droge radio laat de melding van het overgeslagen nummer niet staan', () {
      expect(stuk(speler, 'Future<void> _naarVolgendeNaOverslaan()', 900), contains('speelFout = null;'));
    });

    test('hervatten springt nooit met het VOLGENDE nummer naar de afbreekplek', () {
      expect(
          stuk(speler, 'Future<void> _hervatOpDezelfdePlek() async {', 4000),
          contains('        if (current?.path != t.path) return;\n      }\n'
              '      for (var poging = 0; poging < 60; poging++) {\n        if (current?.path != t.path) return;'));
    });

    test('het scherm toont nooit meer de kale radiostatus, en kost op het speelscherm geen regel extra', () {
      // Ja/nee en geen `contains` op het hele bestand: dat drukt bij een fout heel main.dart af.
      expect(scherm.contains('Text(p.radioStatus'), isFalse, reason: 'de kale radiostatus staat er weer');
      expect(RegExp(r'_radioRegel\(context, p\)').allMatches(scherm).length, greaterThanOrEqualTo(3));
      expect(scherm.contains('radioKop('), isTrue, reason: 'de kop van het paneel');
      expect(scherm.contains('_RadioStatusRegel'), isFalse, reason: 'geen eigen regel op het gestapelde scherm');
      expect(scherm.contains('] else if ((p.radioMode ? _radioRegel(context, p) : null) case final status?) ...['),
          isTrue, reason: 'de status in het vak van de melding');
      expect(scherm.contains("label: const Text('Ga door'),"), isTrue, reason: 'Ga door naast Radio afsluiten');
    });

    test('de luistertelling telt ook voor de radio', () {
      expect(stuk(scherm, 'player.onPlayed = (t) {', 300), contains('radio.gehoord(t)'));
    });
  });
}
