/// Music kept on the device.
///
/// Against a fake server over a real socket, because the parts worth testing are the ones that
/// only go wrong halfway: a download that is interrupted, a file that disappeared from under the
/// index, a cancel while bytes are still arriving. A copy that plays a truncated file is worse
/// than no copy at all — it sounds like the track is broken.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/offline.dart';
import 'package:debridmusic/paths.dart';

/// A stand-in for the PC's /stream route. Serves [bytes], and can be told to hang up halfway.
///
/// Doet ook `Range`, want de echte server doet dat (`lan/range.dart`) en het is precies waar
/// verdergaan-na-een-afbreking op steunt.
class FakeServer {
  FakeServer(this.bytes);
  List<int> bytes;
  HttpServer? _server;

  /// Close the connection after this many bytes instead of finishing.
  int? cutAfter;

  /// Stuur de koppen en dan nooit meer iets, en hang ook niet op. Een telefoon die van wifi naar
  /// 4G springt laat precies dit achter: een verbinding die openstaat en zwijgt.
  bool zwijgNaKoppen = false;

  /// How long to wait between chunks, so a test can cancel mid-flight.
  Duration chunkDelay = Duration.zero;

  int requests = 0;

  /// Wat er in de laatste `Range`-kop stond, of null. Zo kan een toets zien dat er echt verdergegaan
  /// is en niet stilletjes opnieuw begonnen.
  String? laatsteBereik;

  Future<Uri> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = s;
    s.listen((req) async {
      requests++;
      final cut = cutAfter;
      laatsteBereik = req.headers.value(HttpHeaders.rangeHeader);

      var vanaf = 0;
      final m = RegExp(r'^bytes=(\d+)-$').firstMatch(laatsteBereik ?? '');
      if (m != null) vanaf = int.parse(m.group(1)!);

      if (vanaf >= bytes.length) {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${bytes.length}');
        await req.response.close();
        return;
      }

      req.response.statusCode = vanaf > 0 ? HttpStatus.partialContent : HttpStatus.ok;
      req.response.headers.contentType = ContentType('audio', 'flac');
      if (vanaf > 0) {
        req.response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes $vanaf-${bytes.length - 1}/${bytes.length}');
      }
      // Promised in full even when the connection is about to drop — that is what a real server
      // does, and it is the only thing that makes a truncated download detectable.
      req.response.contentLength = bytes.length - vanaf;

      if (zwijgNaKoppen) {
        await req.response.flush();
        return; // en verder niets: de verbinding blijft open en zwijgt
      }

      var sent = 0;
      for (var i = vanaf; i < bytes.length; i += 64) {
        final end = (i + 64).clamp(0, bytes.length);
        if (cut != null && sent >= cut) break;
        req.response.add(bytes.sublist(i, end));
        sent += end - i;
        if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
      }
      if (cut != null) {
        // What a dropped connection looks like: bytes, then nothing.
        //
        // De `flush` is niet kosmetisch. Zonder hem blijven die bytes in de bufferruimte staan, en
        // een `close()` die struikelt over de beloofde lengte gooit ze wég: de client kreeg dan
        // NUL bytes en meteen een fout. Dat is geen afgebroken download maar een mislukte, en het
        // liet drie toetsen hierover iets anders meten dan ze dachten.
        await req.response.flush().catchError((_) {});
        await req.response.close().catchError((_) {});
        return;
      }
      await req.response.close();
    });
    return Uri.parse('http://${s.address.address}:${s.port}/stream/x.flac');
  }

  Future<void> stop() async => _server?.close(force: true);
}

void main() {
  late Directory scratch;
  late OfflineStore store;
  late FakeServer server;
  late Uri url;

  // Big enough that it arrives in many chunks, which is what the throttling and the cancel path
  // are about.
  final payload = List<int>.generate(20000, (i) => i % 256);

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('dm_offline_');
    setAppDirForTest(scratch.path);
    store = OfflineStore();
    await store.load();
    server = FakeServer(payload);
    url = await server.start();
  });

  tearDown(() async {
    await server.stop();
    store.dispose();
    // Windows keeps a handle for a moment after the last close, so a straight delete failed with
    // "the process cannot access the file" — but only when the suite ran under load, which is the
    // worst kind of red: one that never reproduces on its own. Retry briefly, then let it go; a
    // leftover temp folder is not worth failing a test that has already made its point.
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        scratch.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  const path = r'D:\Flac music 2024\Adele\30\01 Strangers By Nature.flac';

  Future<bool> download() => store.download(
        libraryPath: path,
        url: url.toString(),
        title: 'Strangers By Nature',
        artist: 'Adele',
        album: '30',
      );

  group('a copy on this device', () {
    test('the bytes arrive whole and the player is pointed at them', () async {
      expect(await download(), isTrue);

      final local = store.localFor(path);
      expect(local, isNotNull);
      expect(File(local!).readAsBytesSync(), payload,
          reason: 'een halve kopie klinkt als een kapot nummer, niet als een fout');
      expect(store.bytes, payload.length);
      expect(store.has(path), isTrue);
    });

    test('the file keeps the extension, because that is how a player knows the format', () async {
      await download();
      // libmpv and AVFoundation both decide from the extension before reading a byte.
      expect(store.localFor(path), endsWith('.flac'));
    });

    test('it survives a restart', () async {
      await download();

      final second = OfflineStore();
      await second.load();
      expect(second.localFor(path), isNotNull);
      expect(second.bytes, payload.length);
      second.dispose();
    });

    test('the same track is not fetched twice', () async {
      await download();
      await download();
      expect(server.requests, 1);
    });
  });

  group('half a copy is no copy', () {
    test('a dropped connection is never offered as a copy', () async {
      server.cutAfter = 5000;
      await download();

      expect(store.has(path), isFalse);
      expect(store.localFor(path), isNull);
      // Wat er WEL blijft staan is het halve bestand, en dat is met opzet — zie de groep hieronder.
      // Wat er niet mag staan is een af bestand: dat zou spelen en dan stoppen, en dat klinkt als
      // een kapot nummer in plaats van als een mislukte download.
      final af = Directory('${scratch.path}/offline')
          .listSync()
          .where((f) => !f.path.contains('.part'))
          .toList();
      expect(af, isEmpty, reason: 'een half bestand mag nooit voor een heel bestand doorgaan');
    });

    test('a file that vanished stops being offered', () async {
      await download();
      final local = store.localFor(path)!;
      // Android reclaims an app's files under storage pressure without telling anybody.
      File(local).deleteSync();

      expect(store.localFor(path), isNull,
          reason: 'anders krijgt libmpv een pad naar niets en weigert het nummer zonder uitleg');
      expect(store.has(path), isFalse);
    });

    test('cancelling mid-download leaves nothing behind', () async {
      server.chunkDelay = const Duration(milliseconds: 2);
      final running = download();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      store.cancel(path);

      expect(await running, isFalse);
      expect(store.has(path), isFalse);
      expect(Directory('${scratch.path}/offline').listSync(), isEmpty);
    });
  });

  group('een hele plaat in de rij', () {
    // Waarom deze groep bestaat: het ophalen van een album zat als lus IN de knop op de
    // albumpagina, met een `mounted`-toets per nummer. Verliet je die pagina, dan stopte het
    // stilletjes. Gemeten op 17-08-2026 met Discovery: 3 van de 14 nummers, geen melding.
    // De rij hoort in de winkel, want die leeft langer dan een scherm.
    List<OfflineRequest> plaat(int n) => [
          for (var i = 1; i <= n; i++)
            OfflineRequest(
              libraryPath: 'D:\\m\\Daft Punk\\Discovery\\$i.flac',
              url: url.toString(),
              title: 'Nummer $i',
              artist: 'Daft Punk',
              album: 'Discovery',
            ),
        ];

    test('alle nummers komen binnen, ook al wacht niemand erop', () async {
      store.bewaarAlles(plaat(5));

      // Precies wat de knop deed: aanvragen en weglopen. Niemand awaitet hier iets.
      for (var i = 0; i < 200 && store.tracks.length < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(store.tracks.length, 5, reason: 'de rij hoort door te lopen zonder scherm');
      expect(server.requests, 5);
      expect(store.jobs, isEmpty);
    });

    test('wat al op het toestel staat wordt niet opnieuw gehaald', () async {
      await download();
      final voor = server.requests;

      store.bewaarAlles([
        OfflineRequest(
            libraryPath: path, url: url.toString(), title: 'x', artist: 'y', album: 'z'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(server.requests, voor);
    });

    test('een nummer dat nog wacht is zichtbaar als wachtend, niet als bezig', () async {
      server.chunkDelay = const Duration(milliseconds: 2);
      store.bewaarAlles(plaat(3));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final wachtend = store.jobs.where((j) => j.wacht).length;
      expect(store.jobs.length, 3);
      expect(wachtend, 2, reason: 'er loopt er één; de andere twee staan in de rij');
      expect(store.wachtend, 2);

      for (var i = 0; i < 300 && store.tracks.length < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.tracks.length, 3);
    });

    test('uit de rij halen betekent dat hij ook niet alsnog begint', () async {
      server.chunkDelay = const Duration(milliseconds: 2);
      final wensen = plaat(3);
      store.bewaarAlles(wensen);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      store.cancel(wensen.last.libraryPath);

      for (var i = 0; i < 300 && store.jobs.isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.tracks.length, 2);
      expect(store.has(wensen.last.libraryPath), isFalse);
    });
  });

  group('als het misgaat', () {
    // Waarom deze groep bestaat: gemeld op 20-08-2026 met Thriller (MFSL One Step) — één bestand
    // van 32 bit/384 kHz, dus gigabytes. De knop bleef "Ophalen 0/1" melden en was uitgezet, dus
    // opnieuw proberen kon niet eens. Drie dingen misten: een wachtklok, een taak die blijft staan
    // met de reden erbij, en verdergaan waar het stopte.

    test('een mislukking blijft staan, met een reden die iemand kan lezen', () async {
      server.cutAfter = 5000;
      expect(await download(), isFalse);

      final job = store.jobs.singleWhere((j) => j.path == path);
      expect(job.error, isNotNull, reason: 'anders weet niemand ooit dat het misging');
      // Hoever hij kwam, niet hoe de uitzondering heette. De ruwe tekst is
      // "ClientException: Connection closed while receiving data, uri=http://..." en daar heeft
      // niemand op een telefoon iets aan.
      expect(job.error, contains('afgebroken bij'));
      expect(job.error, isNot(contains('Exception')));
      expect(store.foutVoor(path), isNotNull);
      // En hij is NIET bezig, want daar hangt de knop aan: een uitgezette knop na een mislukking
      // laat geen weg terug open.
      expect(store.isBusy(path), isFalse);
      expect(store.mislukt, 1);
    });

    test('opnieuw proberen gaat verder waar hij stopte', () async {
      server.cutAfter = 5000;
      await download();
      expect(server.requests, 1);

      final deel = Directory('${scratch.path}/offline')
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.part'));
      final al = deel.lengthSync();
      expect(al, greaterThan(0), reason: 'er stond al wat, en dat is het hele punt');

      server.cutAfter = null;
      expect(await download(), isTrue);

      expect(server.requests, 2);
      expect(server.laatsteBereik, 'bytes=$al-',
          reason: 'zonder Range begint een bestand van gigabytes elke keer weer van voren af aan');
      expect(File(store.localFor(path)!).readAsBytesSync(), payload,
          reason: 'twee helften aan elkaar moeten precies het bestand zijn');
      expect(store.jobs, isEmpty);
    });

    test('een half bestand van een ANDER bestand wordt niet aangeplakt', () async {
      server.cutAfter = 5000;
      await download();

      // De plaat op de pc is vervangen. Verdergaan zou nu twee helften van twee bestanden aan
      // elkaar plakken: dat speelt af als ruis en niets meldt dat er iets mis is.
      server
        ..cutAfter = null
        ..bytes = List<int>.generate(30000, (i) => (i + 7) % 256);

      expect(await download(), isFalse);
      expect(store.foutVoor(path), contains('veranderd'));

      // En de volgende poging begint dan wél schoon.
      expect(await download(), isTrue);
      expect(File(store.localFor(path)!).readAsBytesSync(), server.bytes);
    });

    test('een verbinding die stilvalt blijft niet eeuwig hangen', () async {
      // Dít was de klacht: "Ophalen 0/1" dat blijft staan. Geen fout, geen einde — een verbinding
      // die openstaat en zwijgt laat `await for` wachten tot het einde der tijden.
      server.zwijgNaKoppen = true;
      final geduldig = OfflineStore(stilte: const Duration(milliseconds: 300));

      final klaar = await geduldig
          .download(libraryPath: path, url: url.toString(), title: 't', artist: 'a', album: 'b')
          .timeout(const Duration(seconds: 10));

      expect(klaar, isFalse);
      expect(geduldig.foutVoor(path), 'de verbinding viel stil');
      expect(geduldig.isBusy(path), isFalse);
      geduldig.dispose();
    });

    test('een mislukking wegtikken haalt ook het halve bestand weg', () async {
      server.cutAfter = 5000;
      await download();
      expect(Directory('${scratch.path}/offline').listSync(), isNotEmpty);

      store.cancel(path);
      // cancel ruimt op de achtergrond op.
      for (var i = 0; i < 100 && Directory('${scratch.path}/offline').listSync().isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(store.jobs, isEmpty);
      expect(Directory('${scratch.path}/offline').listSync(), isEmpty);
    });

    test('een hele plaat loopt door als er één nummer misgaat', () async {
      // De rij mag niet stoppen op de eerste die niet lukt: dan zijn de andere elf er ook niet.
      server.cutAfter = 5000;
      store.bewaarAlles([
        OfflineRequest(
            libraryPath: r'D:\m\A\B\1.flac', url: url.toString(), title: '1', artist: 'a',
            album: 'b'),
      ]);
      for (var i = 0; i < 200 && store.mislukt == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      server.cutAfter = null;
      store.bewaarAlles([
        OfflineRequest(
            libraryPath: r'D:\m\A\B\2.flac', url: url.toString(), title: '2', artist: 'a',
            album: 'b'),
      ]);
      for (var i = 0; i < 200 && store.tracks.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(store.has(r'D:\m\A\B\2.flac'), isTrue);
      expect(store.mislukt, 1, reason: 'de mislukte staat er nog, zichtbaar en te herhalen');
    });
  });

  group('removing a copy is not deleting the track', () {
    test('remove takes the bytes and leaves the index consistent', () async {
      await download();
      final local = store.localFor(path)!;

      await store.remove(path);

      expect(File(local).existsSync(), isFalse);
      expect(store.has(path), isFalse);
      expect(store.bytes, 0);

      // And it can be fetched again — removing a copy says nothing about the PC's file.
      expect(await download(), isTrue);
      expect(store.localFor(path), isNotNull);
    });

    test('clear empties the folder', () async {
      await download();
      await store.clear();
      expect(store.tracks, isEmpty);
      expect(Directory('${scratch.path}/offline').listSync(), isEmpty);
    });
  });

  group('what the screen is told', () {
    test('progress moves, and not on every chunk', () async {
      server.chunkDelay = const Duration(milliseconds: 1);
      var notifications = 0;
      store.addListener(() => notifications++);

      await download();

      // 20000 bytes in 64-byte chunks is 313 of them. Reporting each would rebuild the downloads
      // screen 313 times for one track.
      expect(notifications, lessThan(70),
          reason: 'de voortgang mag alleen melden als de balk zichtbaar beweegt');
      expect(notifications, greaterThan(2), reason: 'maar hij moet wel bewegen');
    });

    test('a track being fetched is busy, and afterwards it is not', () async {
      server.chunkDelay = const Duration(milliseconds: 2);
      final running = download();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(store.isBusy(path), isTrue);

      await running;
      expect(store.isBusy(path), isFalse);
      expect(store.has(path), isTrue);
    });
  });
}
