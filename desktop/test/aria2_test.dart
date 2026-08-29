/// De lokale torrentmotor: de opdrachtregel, het RPC-verzoek, en wie welke bron haalt.
///
/// **Waarom dit bestaat.** Deze drie dingen zijn onzichtbaar zodra het draait. Een vlag die wegvalt
/// merk je niet aan een foutmelding maar aan een motor die van buitenaf aanstuurbaar is, aan een
/// torrent die eeuwig blijft seeden, of aan een proces dat blijft downloaden nadat de app allang weg
/// is. En de keuzeregel bepaalt of jouw IP wel of niet in de zwerm komt — dat is niets om per
/// ongeluk te wijzigen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/aria2.dart';
import 'package:debridmusic/online.dart';

void main() {
  group('de opdrachtregel', () {
    final a = Aria2.argumenten(
      poort: 46801,
      geheim: 'abc123',
      map: r'D:\Muziek\DebridMusic Downloads',
      logbestand: r'C:\Users\x\AppData\Roaming\DebridMusic\aria2.log',
      stopMetProces: 4242,
    );

    test('luistert alleen op deze machine, en met een geheim', () {
      expect(a, contains('--enable-rpc'));
      expect(a, contains('--rpc-listen-port=46801'));
      // Zonder deze twee is het een torrentmotor die iedereen op het netwerk mag aansturen.
      expect(a, contains('--rpc-listen-all=false'));
      expect(a, contains('--rpc-secret=abc123'));
    });

    test('gaat mee dood met de app', () {
      // Anders blijft er een proces achter dat downloadt voor een app die er niet meer is — en dat
      // ziet niemand, want het heeft geen venster.
      expect(a, contains('--stop-with-process=4242'));
    });

    test('seedt niet uit zichzelf en geeft een dode torrent op', () {
      expect(a, contains('--seed-time=0'));
      expect(a, contains('--bt-stop-timeout=900'));
    });

    test('schrijft op waar het misging', () {
      expect(a, contains(r'--log=C:\Users\x\AppData\Roaming\DebridMusic\aria2.log'));
    });

    test('en een torrentbestand past door de RPC', () {
      // base64 van een .torrent van een plaat met veel stukken haalt de standaardgrens van 2 MB.
      expect(a, contains('--rpc-max-request-size=32M'));
    });
  });

  group('het RPC-verzoek', () {
    test('draagt het geheim als eerste parameter', () {
      final v = Aria2.verzoek('aria2.tellStatus', ['gid1'], 'abc123');

      expect(v['method'], 'aria2.tellStatus');
      expect(v['params'], ['token:abc123', 'gid1']);
      expect(v['jsonrpc'], '2.0');
    });

    test('en laat hem weg als er geen is', () {
      expect(Aria2.verzoek('aria2.getVersion', [], '')['params'], isEmpty);
    });
  });


  group('wie haalt deze bron', () {
    // De feiten die tellen: is er een .torrent, staat het al klaar bij TorBox, en is er een motor.
    bool kies(String motor, {bool bestand = true, bool klaar = false, bool motorEr = true}) =>
        OnlineService.kiesLokaal(
            motor: motor,
            heeftBron: bestand,
            staatKlaarBijTorbox: klaar,
            motorBeschikbaar: motorEr);

    test('automatisch: wat al bij TorBox staat komt daar vandaan', () {
      // Dat is meteen klaar én jouw IP blijft erbuiten. Lokaal halen zou hier alleen maar trager
      // zijn en meer blootleggen.
      expect(kies('auto', klaar: true), isFalse);
    });

    test('automatisch: wat er niet staat halen we zelf', () {
      // Precies het geval van 23-08-2026: TorBox moet dan de hele torrent zelf ophalen, en dat is
      // waar het traag werd en die dag helemaal stilviel.
      expect(kies('auto', klaar: false), isTrue);
    });

    test('de gebruiker kan het overrulen, beide kanten op', () {
      expect(kies('torbox', klaar: false), isFalse, reason: 'nooit lokaal, wat er ook gebeurt');
      expect(kies('lokaal', klaar: true), isTrue, reason: 'altijd lokaal, ook als TorBox het heeft');
    });

    test('een magneet mag óók lokaal', () {
      // Dit stond eerst andersom, en dat was de klacht: alles van Knaben en Pirate Bay is een
      // magneet, dus die vielen állemaal terug op TorBox — ook met veertig seeders in beeld. aria2
      // haalt de inhoudsopgave uit diezelfde zwerm, dus een magneet is hier genoeg.
      expect(kies('auto', bestand: true), isTrue);
    });

    test('zonder magneet én zonder bestand valt er niets te halen', () {
      expect(kies('lokaal', bestand: false), isFalse);
      expect(kies('auto', bestand: false), isFalse);
    });

    test('en zonder motor ook niet', () {
      // Een installatie zonder aria2c.exe moet gewoon blijven werken zoals hij altijd werkte.
      expect(kies('lokaal', motorEr: false), isFalse);
      expect(kies('auto', motorEr: false), isFalse);
    });
  });
}
