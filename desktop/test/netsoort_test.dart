/// Welke stroomstand er nu geldt, en hoeveel er vooruit gelezen wordt.
///
/// Twee regels, allebei zuiver, allebei het soort som dat je nergens tussen de schermcode wilt
/// hebben staan omdat een fout erin niet omvalt maar stilletjes het verkeerde doet.
library;

import 'dart:io';

import 'package:debridmusic/lan/stroomstand.dart';
import 'package:debridmusic/lan/tokens.dart' show bronIsThuis;
import 'package:debridmusic/lan/verbindingsstand.dart' show Verbindingsweg;
import 'package:debridmusic/netsoort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Stroomstand stand({
    Stroomstand thuis = Stroomstand.max,
    Stroomstand onderweg = Stroomstand.cd,
    bool adaptief = true,
    Netsoort net = Netsoort.wifi,
    Verbindingsweg? weg,
    bool noodstand = false,
    bool tv = false,
  }) =>
      welkeStand(
          thuis: thuis,
          onderweg: onderweg,
          adaptief: adaptief,
          net: net,
          weg: weg,
          noodstand: noodstand,
          tv: tv);

  group('regel A: de netsoort kiest de sport', () {
    test('op wifi geldt wat je thuis wilt', () {
      expect(stand(net: Netsoort.wifi), Stroomstand.max);
    });

    test('op mobiel geldt wat je onderweg wilt', () {
      expect(stand(net: Netsoort.mobiel), Stroomstand.cd);
    });

    test('DE KERN: onbekend valt naar THUIS en niet naar onderweg', () {
      // De dure kant, met opzet. Een mislukte meting mag je thuis nooit stilletjes je hi-res kosten
      // — dat merk je niet en zoek je nooit. Een gemiste meting onderweg kost je een keer meer data
      // dan je wilde, en dát zie je.
      expect(stand(net: Netsoort.onbekend), Stroomstand.max);
    });

    test('staat adaptief uit, dan geldt thuis altijd', () {
      expect(stand(adaptief: false, net: Netsoort.mobiel), Stroomstand.max);
      expect(stand(adaptief: false, net: Netsoort.onbekend), Stroomstand.max);
    });

    test('de twee standen zijn vrij te kiezen, ook andersom', () {
      // Niemand houdt je tegen om onderweg juist méér te willen. Rare keuze, maar geen fout.
      expect(stand(thuis: Stroomstand.cd, onderweg: Stroomstand.max, net: Netsoort.mobiel),
          Stroomstand.max);
    });
  });

  group('de weg naar de pc (21-10-2026: Wonderwall als origineel op mobiele data)', () {
    test('niet thuis verbonden is onderweg, ook als de netsoort nog onbekend is of wifi zegt', () {
      expect(stand(net: Netsoort.onbekend, weg: Verbindingsweg.rechtstreeks), Stroomstand.cd,
          reason: 'koude start of midden in een wissel: Android zegt nog niets, de weg is al bekend');
      expect(stand(net: Netsoort.onbekend, weg: Verbindingsweg.tailscale), Stroomstand.cd);
      expect(stand(net: Netsoort.wifi, weg: Verbindingsweg.rechtstreeks), Stroomstand.cd,
          reason: 'een wifi die niet de jouwe is (op het werk)');
    });

    test('thuis verbonden blijft thuis; zonder weg beslist de netsoort zoals voorheen', () {
      expect(stand(net: Netsoort.wifi, weg: Verbindingsweg.thuis), Stroomstand.max);
      expect(stand(net: Netsoort.onbekend, weg: Verbindingsweg.thuis), Stroomstand.max);
      expect(stand(net: Netsoort.onbekend), Stroomstand.max);
      expect(stand(net: Netsoort.mobiel, weg: Verbindingsweg.thuis), Stroomstand.cd);
    });

    test('een tv blijft thuis, en adaptief uit blijft thuis', () {
      expect(stand(tv: true, weg: Verbindingsweg.rechtstreeks), Stroomstand.max);
      expect(stand(adaptief: false, weg: Verbindingsweg.rechtstreeks), Stroomstand.max);
    });

    test('de noodstand geldt ook onderweg op een vreemde wifi', () {
      expect(
          stand(net: Netsoort.wifi, weg: Verbindingsweg.rechtstreeks, noodstand: true, onderweg: Stroomstand.hoog),
          Stroomstand.cd);
    });

    test('NetsoortStore gebruikt de weg van de sessie', () {
      final s = NetsoortStore()..wegNu = () => Verbindingsweg.rechtstreeks;
      expect(s.onderweg, isTrue);
      s.wegNu = () => Verbindingsweg.thuis;
      expect(s.onderweg, isFalse);
    });

    test('heropenen als de stand na de verbinding anders is — gepauzeerd of in het begin', () {
      const origineel = 'http://pc/stream/abc.flac?token=x';
      const cd = 'http://pc/stream/abc.flac?token=x&maxRate=44100&maxBits=16';
      expect(heropenVoorStand(geopend: origineel, nu: cd, speelt: false, plek: const Duration(seconds: 95)), isTrue,
          reason: 'koude start: hervat en gepauzeerd');
      expect(heropenVoorStand(geopend: origineel, nu: cd, speelt: true, plek: const Duration(seconds: 3)), isTrue);
      expect(heropenVoorStand(geopend: origineel, nu: cd, speelt: true, plek: const Duration(minutes: 2)), isTrue,
          reason: 'omlaag ook midden in een nummer: de rest in cd-kwaliteit (Barry White, 83 MB hi-res over 5G)');
      expect(heropenVoorStand(geopend: cd, nu: origineel, speelt: true, plek: const Duration(minutes: 2)), isFalse,
          reason: 'omhoog midden in een nummer geen hik voor betere kwaliteit');
      const hoog = 'http://pc/stream/abc.flac?token=x&maxRate=96000&maxBits=24';
      expect(heropenVoorStand(geopend: hoog, nu: cd, speelt: true, plek: const Duration(minutes: 2)), isTrue,
          reason: 'van 24/96 naar 16/44,1 is ook omlaag');
      expect(heropenVoorStand(geopend: cd, nu: hoog, speelt: true, plek: const Duration(minutes: 2)), isFalse);
      expect(heropenVoorStand(geopend: cd, nu: cd, speelt: false, plek: Duration.zero), isFalse);
      expect(heropenVoorStand(geopend: '/storage/abc.flac', nu: cd, speelt: false, plek: Duration.zero), isFalse,
          reason: 'een kopie op het toestel');
      expect(heropenVoorStand(geopend: null, nu: cd, speelt: false, plek: Duration.zero), isFalse);
      expect(heropenVoorStand(geopend: cd, nu: origineel, speelt: false, plek: Duration.zero), isTrue,
          reason: 'andersom ook: thuis na een koude start met de weg van buiten');
    });

    test('strenger omzetten: geen grens is het origineel, bits 0 is een vrije diepte', () {
      expect(grensLager((rate: 44100, bits: 16), dan: null), isTrue);
      expect(grensLager(null, dan: (rate: 44100, bits: 16)), isFalse);
      expect(grensLager((rate: 44100, bits: 16), dan: (rate: 44100, bits: 0)), isTrue);
      expect(grensLager((rate: 44100, bits: 0), dan: (rate: 44100, bits: 16)), isFalse);
      expect(grensLager((rate: 48000, bits: 24), dan: (rate: 96000, bits: 24)), isTrue);
      expect(grensLager((rate: 44100, bits: 16), dan: (rate: 44100, bits: 16)), isFalse);
    });

    test('een wissel naar mobiele data kijkt meteen naar de stand van het lopende nummer', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final i = main.indexOf('  netStore.addListener(() {\n    unawaited(player.zetVooruitlezen(');
      expect(i, greaterThan(0));
      expect(main.substring(i, main.indexOf('\n  });\n', i)), contains('    if (!mode.owner) player.kijkNaarStand();\n'));
      final speler = File('lib/player.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final p = speler.indexOf('  void pcWeerBereikbaar() {');
      expect(speler.substring(p, speler.indexOf('\n  }\n', p)), contains('    if (kijkNaarStand()) return;\n'));
    });

    test('een bewaarde weg terug', () {
      expect(wegUitNaam('rechtstreeks'), Verbindingsweg.rechtstreeks);
      expect(wegUitNaam('thuis'), Verbindingsweg.thuis);
      expect(wegUitNaam(''), isNull);
      expect(wegUitNaam('iets'), isNull);
    });

    test('aangesloten: de sessie geeft haar weg, en het vooruithalen volgt onderweg', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main, contains('netStore.wegNu = () => session.wegVoorStroom ?? wegUitNaam(settings.laatsteWeg);'));
      expect(main, contains('settings.laatsteWeg = w.name;'));
      final speler = File('lib/player.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(speler, contains('if (!heropenVoorStand(geopend: mpvAdres, nu: mediaResolver(_speelPad(t.path)), speelt: playing, plek: position)) {'));
      expect(main, contains('opMobiel: netStore.onderweg,'));
    });
  });

  group('thuis via de eigen deur is thuis (21-10-2026: de Mac kreeg The Door als 16/44,1)', () {
    test('de pc herkent zijn thuisnetwerk en zijn eigen publieke adres', () {
      const publiek = '178.118.55.105';
      expect(bronIsThuis(InternetAddress('192.168.0.216'), publiek), isTrue, reason: 'de Mac op de wifi');
      expect(bronIsThuis(InternetAddress('::ffff:192.168.0.216'), publiek), isTrue);
      expect(bronIsThuis(InternetAddress(publiek), publiek), isTrue,
          reason: 'via de eigen deur, door de modem teruggestuurd naar binnen');
      expect(bronIsThuis(InternetAddress('127.0.0.1'), publiek), isTrue);
      expect(bronIsThuis(InternetAddress('212.123.26.50'), publiek), isFalse, reason: 'de wifi van de kliniek');
      expect(bronIsThuis(InternetAddress('100.73.186.40'), publiek), isFalse, reason: 'Tailscale kan van buiten zijn');
      expect(bronIsThuis(InternetAddress(publiek), null), isFalse, reason: 'geen deur: dan weet de pc het niet');
    });

    test('aangesloten: de pc zegt het in /api/config, de sessie gebruikt het, en main bewaart die weg', () {
      String lees(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
      expect(lees('lib/lan/server.dart'), contains("'opHetThuisnet': _vanThuis(req) ? 'ja' : 'nee',"));
      final sessie = lees('lib/lan/client_session.dart');
      expect(sessie,
          contains('return w == Verbindingsweg.rechtstreeks && _pcZegtThuis == true ? Verbindingsweg.thuis : w;'));
      expect(sessie, contains("_zetThuis(shared['opHetThuisnet']);"));
      expect(sessie, contains('unawaited(_vraagOfThuis());'));
      expect(lees('lib/main.dart'),
          contains('final w = session.verbinding.weg == null ? null : session.wegVoorStroom;'));
    });
  });

  group('regel B: hapert het, dan één sport lager', () {
    test('precies één sport, niet twee', () {
      expect(eenSportLager(Stroomstand.max), Stroomstand.hoog);
      expect(eenSportLager(Stroomstand.hoog), Stroomstand.cd);
    });

    test('en nooit onder de onderste', () {
      // Er is niets onder cd zonder lossy te gaan coderen, en dat gebeurt hier niet.
      expect(eenSportLager(Stroomstand.cd), Stroomstand.cd);
      expect(eenSportLager(eenSportLager(eenSportLager(Stroomstand.max))), Stroomstand.cd);
    });

    test('onderweg werkt de noodstand op de sport die op dat moment geldt', () {
      expect(stand(net: Netsoort.mobiel, noodstand: true), Stroomstand.cd);
      expect(stand(net: Netsoort.mobiel, onderweg: Stroomstand.max, noodstand: true),
          Stroomstand.hoog);
    });

    test('de noodstand klimt nooit vanzelf terug', () {
      // Zolang de grendel staat blijft hij staan; hem laten opklimmen na een geslaagd nummer lokt
      // precies de hapering uit die hij net oploste.
      final een = stand(net: Netsoort.mobiel, onderweg: Stroomstand.hoog, noodstand: true);
      final twee = stand(net: Netsoort.mobiel, onderweg: Stroomstand.hoog, noodstand: true);
      expect(een, twee);
      expect(een, Stroomstand.cd);
    });

    test('DE KERN: thuis zakt het nooit — één kapot bestand is geen zwakke lijn', () {
      // 10-10-2026 op de Shield: "Stromae – Sommeil" van 0,1 MB brak af, de noodstand ging aan, en de
      // rest van de avond ging elk hi-res nummer als 24/48 de deur uit. Thuis lost een lagere sport
      // niets op; onderweg wel.
      expect(stand(net: Netsoort.wifi, noodstand: true), Stroomstand.max);
      expect(stand(net: Netsoort.onbekend, noodstand: true), Stroomstand.max);
      expect(stand(net: Netsoort.wifi, thuis: Stroomstand.hoog, noodstand: true), Stroomstand.hoog,
          reason: 'wat je thuis zelf koos blijft staan, niet lager');
    });
  });

  group('DE KERN: een televisie zit thuis', () {
    test('ook als Android zijn netwerk "beperkt" noemt (een VPN), en ook na een hapering', () {
      expect(stand(tv: true, net: Netsoort.mobiel), Stroomstand.max);
      expect(stand(tv: true, net: Netsoort.mobiel, noodstand: true), Stroomstand.max);
      expect(stand(tv: true, net: Netsoort.wifi, noodstand: true), Stroomstand.max);
    });

    test('wat je op de tv als thuisstand koos, blijft het', () {
      expect(stand(tv: true, thuis: Stroomstand.hoog, net: Netsoort.mobiel), Stroomstand.hoog);
    });

    test('de winkel geeft de tv mee', () {
      final bron = File('lib/netsoort.dart').readAsStringSync();
      expect(bron.contains('        tv: isTv,\n'), isTrue);
    });
  });

  group('vooruitlezen', () {
    test('op wifi blijft het driehonderd seconden', () {
      // Dat is de reparatie van 15-08-2026 voor draadloos Android Auto. Niet aankomen.
      expect(vooruitleesSeconden(Netsoort.wifi), 300);
    });

    test('bij onbekend ook, om dezelfde reden als bij de stand', () {
      expect(vooruitleesSeconden(Netsoort.onbekend), 300);
    });

    test('op mobiel korter, want vooruitlezen is daar niet gratis', () {
      // 300 s op de cd-stand is ~34 MB per nummer. Skip je na twintig seconden door, dan gooi je
      // ~32 MB weg waar je voor betaald hebt.
      expect(vooruitleesSeconden(Netsoort.mobiel), 90);
      expect(vooruitleesSeconden(Netsoort.mobiel),
          lessThan(vooruitleesSeconden(Netsoort.wifi)));
    });
  });
}
