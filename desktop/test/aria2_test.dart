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

  group('opruimen na een torrent', () {
    // Wat er werkelijk in de map stond na één gekozen nummer van B.B.E. — Seven Days And One Week.
    late Directory map;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_opruim_');
      Directory('${map.path}${Platform.pathSeparator}Album').createSync();
      File('${map.path}${Platform.pathSeparator}01 gevraagd.flac').writeAsBytesSync(List.filled(1000, 7));
      File('${map.path}${Platform.pathSeparator}Album${Platform.pathSeparator}02 niet gevraagd.flac')
          .writeAsBytesSync(List.filled(2048, 3));
      File('${map.path}${Platform.pathSeparator}Album.aria2').writeAsBytesSync([1, 2, 3]);
      File('${map.path}${Platform.pathSeparator}96a14d03.torrent').writeAsBytesSync([4, 5, 6]);
    });

    tearDown(() {
      if (map.existsSync()) map.deleteSync(recursive: true);
    });

    Aria2Stand stand(List<Aria2Bestand> b) => Aria2Stand(
        gid: 'g', status: 'complete', gedaan: 1, totaal: 1, seeders: 0, verbindingen: 0,
        fout: '', bestanden: b);

    test('het halve bestand van een nummer dat je NIET koos verdwijnt', () async {
      await ruimOpNaTorrent(
          map,
          stand([
            Aria2Bestand(2, '${map.path}/Album/02 niet gevraagd.flac', 55000000, 2048, false),
          ]));

      expect(Directory('${map.path}${Platform.pathSeparator}Album').existsSync(), isFalse,
          reason: 'anders staat er een FLAC van twee kilobyte in de bibliotheek');
      // En wat je wél vroeg blijft staan: dat is intussen uit de map van aria2 gehaald.
      expect(File('${map.path}${Platform.pathSeparator}01 gevraagd.flac').existsSync(), isTrue);
    });

    test('de administratie van aria2 blijft niet liggen', () async {
      await ruimOpNaTorrent(map, stand(const []));

      expect(File('${map.path}${Platform.pathSeparator}Album.aria2').existsSync(), isFalse);
      expect(File('${map.path}${Platform.pathSeparator}96a14d03.torrent').existsSync(), isFalse);
    });

    test('een pad buiten de doelmap raakt hij niet aan', () async {
      // Zou hij paden volgen die aria2 ergens anders neerzette, dan verwijdert een download een map
      // die er niets mee te maken heeft.
      final elders = Directory.systemTemp.createTempSync('dm_elders_');
      File('${elders.path}${Platform.pathSeparator}kostbaar.flac').writeAsBytesSync([9]);
      addTearDown(() => elders.deleteSync(recursive: true));

      await ruimOpNaTorrent(
          map, stand([Aria2Bestand(1, '${elders.path}/Album/kostbaar.flac', 1, 1, true)]));

      expect(File('${elders.path}${Platform.pathSeparator}kostbaar.flac').existsSync(), isTrue);
    });
  });

  group('wie haalt deze bron', () {
    // De feiten die tellen: is er een .torrent, staat het al klaar bij TorBox, en is er een motor.
    bool kies(String motor, {bool bestand = true, bool klaar = false, bool motorEr = true}) =>
        OnlineService.kiesLokaal(
            motor: motor,
            heeftTorrentbestand: bestand,
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

    test('zonder torrentbestand nooit lokaal', () {
      // Een kale magneet draagt alleen de infohash; de zwerm van een tracker vind je daar niet mee.
      // Dat is dezelfde reden waarom TorBox op magneten bleef hangen.
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
