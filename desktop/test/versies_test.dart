// Versies bewaren (Saber, 26-10-2026): "Behoud ik alles e, cd, studio, en vinyl. Dan kan ik nog kiezen wat ik wil".
import 'dart:io';

import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/versies.dart';
import 'package:debridmusic/vinyl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('de persing uit waar hij vandaan kwam', () {
    test('vinyl: lp, het jaar, dubbel-lp, PBTHAL', () {
      expect(persingUit(r'@@music\Spice Girls\1996 - Spice (Vinyl 24-96)\01 - Wannabe.flac', soort: Kopiesoort.vinyl),
          'LP 1996');
      expect(persingUit(r'Daft Punk - Discovery [2LP] [24-96]\B2 Digital Love.flac', soort: Kopiesoort.vinyl), '2LP');
      expect(
          persingUit(r'@@h\PBTHAL rips  [NOT REENCODED]\Toto\Toto - IV (TML)\10 - Africa.flac', soort: Kopiesoort.vinyl),
          'LP PBTHAL');
      expect(persingUit(r'Spice (2016 Vinyl Reissue)\01.flac', soort: Kopiesoort.vinyl), 'LP 2016 Reissue');
      expect(persingUit(r'Album [12" Maxi]\A1.flac', soort: Kopiesoort.vinyl), '12"');
    });

    test('digitaal: alleen wat over de master gaat', () {
      expect(persingUit(r'Queen\A Night At The Opera (2011 Remaster) [FLAC]\01.flac', soort: Kopiesoort.cd),
          'Remaster 2011');
      expect(persingUit(r'X\Abbey Road (Remastered 2009)\01.flac', soort: Kopiesoort.cd), 'Remaster 2009');
      expect(persingUit(r'MJ\Thriller (MFSL One Step)\01.flac', soort: Kopiesoort.studio), 'MFSL');
      expect(persingUit(r'Dire Straits\Brothers In Arms [Japan SHM-CD]\01.flac', soort: Kopiesoort.cd), 'SHM-CD Japan');
      expect(persingUit(r'Album (Deluxe Edition) [24-96]\01.flac', soort: Kopiesoort.studio), '',
          reason: 'deluxe zegt iets over de nummerlijst, niet over het geluid');
      expect(persingUit(r'Album\1999 - Mono.flac', soort: Kopiesoort.cd), '',
          reason: 'de bestandsnaam is de titel: daar kan "Mono" of "1999" gewoon in staan');
      expect(persingUit('TIDAL 24/44.1', soort: Kopiesoort.studio), '');
    });
  });

  test('de naam: soort · persing · kwaliteit', () {
    expect(versieLabel(Kopiesoort.vinyl, 'LP 1996', bits: 24, hz: 192000), 'Vinyl · LP 1996 · 24/192');
    expect(versieLabel(Kopiesoort.cd, '', bits: 16, hz: 44100), 'CD · 16/44.1');
    expect(versieLabel(Kopiesoort.studio, 'Remaster 2011'), 'Studio · Remaster 2011');
    expect(versieMap(r'D:\Muziek\Albums\Spice Girls\Spice', Kopiesoort.vinyl, 'LP 1996'),
        r'D:\Muziek\Albums\Spice Girls\Spice (vinyl LP 1996)');
    expect(versieMap(r'D:\A\Album', Kopiesoort.vinyl, '12"'), r'D:\A\Album (vinyl 12)', reason: 'geen " in een mapnaam');
  });

  test('DE KERN: twee rips van dezelfde uitgave zijn één versie; een andere soort of persing is een andere', () {
    expect(zelfdeVersie(Kopiesoort.cd, '', Kopiesoort.cd, ''), isTrue);
    expect(zelfdeVersie(Kopiesoort.cd, '', Kopiesoort.cd, 'Remaster 2011'), isTrue, reason: 'onbekend is geen verschil');
    expect(zelfdeVersie(Kopiesoort.cd, '', Kopiesoort.vinyl, 'LP'), isFalse);
    expect(zelfdeVersie(Kopiesoort.studio, '', Kopiesoort.cd, ''), isFalse);
    expect(zelfdeVersie(Kopiesoort.vinyl, 'LP 1996', Kopiesoort.vinyl, 'LP 2016 Reissue'), isFalse);
    expect(zelfdeVersie(Kopiesoort.vinyl, 'LP 1996', Kopiesoort.vinyl, '2LP'), isTrue);
    expect(zelfdeVersie(Kopiesoort.cd, 'Remaster 2011', Kopiesoort.cd, 'Remaster 2009'), isFalse);
    expect(zelfdeVersie(Kopiesoort.studio, 'MFSL', Kopiesoort.studio, 'Japan'), isFalse);
    expect(zelfdeVersie(Kopiesoort.studio, 'MFSL', Kopiesoort.studio, ''), isTrue);
  });

  test('een kaal [LP] of (2LP) is een vinylrip, "(LP Version)" niet', () {
    expect(isVinylRip(r'Daft Punk - Discovery [2LP] [FLAC]\01.flac'), isTrue);
    expect(isVinylRip(r'Toto - IV (LP)\01.flac'), isTrue);
    expect(isVinylRip(r'Toto - IV [LP][24-192]\01.flac'), isTrue);
    expect(isVinylRip(r'Genesis - Duke [LP][24/96]\01.flac'), isTrue);
    expect(isVinylRip(r'Music\Prince - 1999\6. Automatic (LP Version).flac'), isFalse);
    expect(isVinylRip(r'The Remixes LP\01 - Help.flac'), isFalse);
  });

  test('uitlijnen heen en terug', () {
    expect(plekInVersie(60000, verschuivingMs: 1200, snelheid: 1.002), 61320);
    expect(plekInAnker(61320, verschuivingMs: 1200, snelheid: 1.002), 60000);
    expect(plekInVersie(60000), 60000, reason: 'niet gemeten: dezelfde seconde');
  });

  group('het register', () {
    late Versieregister r;
    setUp(() => r = Versieregister());
    final anker = r'D:\M\Albums\Spice Girls\Spice\01 - Wannabe.flac';
    final vinyl = r'D:\M\Albums\Spice Girls\Spice (vinyl LP 1996)\01 - Wannabe.flac';
    final cd = r'D:\M\Albums\Spice Girls\Spice (cd)\01 - Wannabe.flac';

    test('versies van een anker, op volgorde, en terug te vinden per pad', () {
      r.voegToe(anker, Versie(pad: vinyl, soort: Kopiesoort.vinyl, persing: 'LP 1996'), ankerSoort: Kopiesoort.studio);
      r.voegToe(anker, Versie(pad: cd, soort: Kopiesoort.cd));
      expect([for (final v in r.versiesVan(anker)) v.soort], [Kopiesoort.cd, Kopiesoort.vinyl]);
      expect(r.isVersie(vinyl), isTrue);
      expect(r.isVersie(vinyl.toUpperCase()), isTrue, reason: 'Windows: hoofdletters tellen niet');
      expect(r.isVersie(anker), isFalse);
      expect(r.ankerVan(cd), anker);
      expect(r.groep(anker)!.soort, Kopiesoort.studio);
    });

    test('verhuizen: een versie, een anker, en wat naar _dubbel gaat is geen versie meer', () {
      r.voegToe(anker, Versie(pad: vinyl, soort: Kopiesoort.vinyl));
      r.voegToe(anker, Versie(pad: cd, soort: Kopiesoort.cd));
      final ander = vinyl.replaceAll('01 - Wannabe', '01 - Wannabe (2)');
      r.herNoem(vinyl, ander);
      expect(r.versie(ander)?.soort, Kopiesoort.vinyl);
      final nieuwAnker = anker.replaceAll('.flac', '.m4a');
      r.herNoem(anker, nieuwAnker);
      expect(r.versiesVan(nieuwAnker), hasLength(2));
      expect(r.versiesVan(anker), isEmpty);
      r.herNoem(cd, r'D:\M\_dubbel\01 - Wannabe.flac');
      expect(r.versiesVan(nieuwAnker), hasLength(1));
      expect(r.isVersie(cd), isFalse);
    });

    test('een versie wordt anker: hij is geen versie meer, de rest verhuist mee', () {
      r.voegToe(anker, Versie(pad: vinyl, soort: Kopiesoort.vinyl));
      r.voegToe(anker, Versie(pad: cd, soort: Kopiesoort.cd));
      r.verhuisAnker(anker, cd, soort: Kopiesoort.cd);
      expect(r.isVersie(cd), isFalse);
      expect(r.ankerVan(vinyl), cd);
      expect(r.groep(cd)!.soort, Kopiesoort.cd);
    });

    test('na een scan: weg is weg, en een verdwenen anker krijgt de beste versie als opvolger', () {
      r.voegToe(anker, Versie(pad: vinyl, soort: Kopiesoort.vinyl));
      r.voegToe(anker, Versie(pad: cd, soort: Kopiesoort.cd));
      final opvolgers = r.ruimOp((p) => p != anker);
      expect(opvolgers, [cd], reason: 'cd gaat voor vinyl');
      expect(r.ankerVan(vinyl), cd);
      r.ruimOp((p) => p != vinyl);
      expect(r.groep(cd), isNull, reason: 'geen versies meer: geen groep');
    });

    test('DE KERN: kiezen per nummer of per plaat; het nummer gaat voor', () {
      final anker2 = r'D:\M\Albums\Spice Girls\Spice\02 - Say You Will Be There.flac';
      final vinyl2 = r'D:\M\Albums\Spice Girls\Spice (vinyl LP 1996)\02 - Say You Will Be There.flac';
      r.voegToe(anker, Versie(pad: vinyl, soort: Kopiesoort.vinyl, persing: 'LP 1996'), ankerSoort: Kopiesoort.cd);
      r.voegToe(anker2, Versie(pad: vinyl2, soort: Kopiesoort.vinyl, persing: 'LP 1996'), ankerSoort: Kopiesoort.cd);
      expect(r.speelVersie(anker), isNull, reason: 'zonder keuze: het anker');
      r.kies(anker, versieSleutel(Kopiesoort.vinyl, 'LP 1996'), bereik: VersieBereik.plaat);
      expect(r.speelVersie(anker)?.pad, vinyl);
      expect(r.speelVersie(anker2)?.pad, vinyl2, reason: 'voor de hele plaat');
      r.kies(anker2, versieSleutel(Kopiesoort.cd, ''), bereik: VersieBereik.nummer);
      expect(r.speelVersie(anker2), isNull, reason: 'dit nummer: het anker (de cd)');
      expect(r.bereikVan(anker2), VersieBereik.nummer);
      r.kies(anker, versieSleutel(Kopiesoort.vinyl, 'LP 1996'), bereik: VersieBereik.plaat);
      expect(r.speelVersie(anker2)?.pad, vinyl2, reason: 'opnieuw voor de plaat: de keuze per nummer vervalt');
    });

    test('een keuze die niet precies past, neemt dezelfde soort', () {
      r.voegToe(anker, Versie(pad: vinyl, soort: Kopiesoort.vinyl, persing: '2LP'), ankerSoort: Kopiesoort.cd);
      r.kies(anker, versieSleutel(Kopiesoort.vinyl, 'LP 1996'), bereik: VersieBereik.nummer);
      expect(r.speelVersie(anker)?.pad, vinyl);
    });

    test('bewaren en weer inlezen', () async {
      final map = Directory.systemTemp.createTempSync('dm_versies_');
      addTearDown(() => map.deleteSync(recursive: true));
      final pad = '${map.path}${Platform.pathSeparator}versies.json';
      final a = Versieregister(bestand: () => pad);
      a.voegToe(anker, Versie(pad: vinyl, soort: Kopiesoort.vinyl, persing: 'LP 1996', bron: 'PBTHAL', sindsMs: 5),
          ankerSoort: Kopiesoort.cd);
      a.zetUitlijning(vinyl, verschuivingMs: 1830, snelheid: 1.0015);
      a.kies(anker, versieSleutel(Kopiesoort.vinyl, 'LP 1996'), bereik: VersieBereik.plaat);
      await a.bewaarNu();
      final b = Versieregister(bestand: () => pad);
      await b.laad();
      final v = b.versie(vinyl)!;
      expect(v.persing, 'LP 1996');
      expect(v.verschuivingMs, 1830);
      expect(v.snelheid, 1.0015);
      expect(b.groep(anker)!.soort, Kopiesoort.cd);
      expect(b.speelVersie(anker)?.pad, vinyl);
    });

    test('een kapot bestand begint leeg', () async {
      final map = Directory.systemTemp.createTempSync('dm_versies_');
      addTearDown(() => map.deleteSync(recursive: true));
      final pad = '${map.path}${Platform.pathSeparator}versies.json';
      File(pad).writeAsStringSync('{kapot');
      final b = Versieregister(bestand: () => pad);
      await b.laad();
      expect(b.isLeeg, isTrue);
    });
  });
}
