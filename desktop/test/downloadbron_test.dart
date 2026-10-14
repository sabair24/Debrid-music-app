import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/downloadbron.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/rutracker.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/torbox.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een toestel kan de pc niet meer naar een vreemd adres sturen, en zeker niet met je
/// RuTracker-koekje erbij. Zie `downloadbron.dart`.
class _TelDownloads extends DownloadManager {
  _TelDownloads(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged);
  final gestart = <SearchResult>[];

  @override
  void enqueue(SearchResult result, {int? fileId, TbFile? bestand, TbTorrent? klaar}) =>
      gestart.add(result);
}

void main() {
  group('rutrackerTorrentAdres', () {
    test('het adres dat de pc zelf uitgeeft, en alleen dat', () {
      expect(rutrackerTorrentAdres('https://rutracker.org/forum/dl.php?t=6543210'),
          'https://rutracker.org/forum/dl.php?t=6543210');
    });

    test('alles wat er net naast zit, wordt geweigerd', () {
      for (final u in [
        'https://example.invalid/',
        'http://rutracker.org/forum/dl.php?t=1', // geen https
        'https://rutracker.org.example.invalid/forum/dl.php?t=1', // andere host
        'https://rutracker.org@example.invalid/forum/dl.php?t=1', // host achter een gebruikersnaam
        'https://x@rutracker.org/forum/dl.php?t=1', // gebruikersnaam ervoor
        'https://rutracker.org:8443/forum/dl.php?t=1', // andere poort
        'https://rutracker.org/forum/viewtopic.php?t=1', // ander pad
        'https://rutracker.org/forum/dl.php?t=1&x=2', // tweede parameter
        'https://rutracker.org/forum/dl.php?t=1&t=2', // dubbel
        'https://rutracker.org/forum/dl.php?t=abc',
        'https://rutracker.org/forum/dl.php?t=1#x',
        '-o C:/Users/x/Opstarten/a.bat https://rutracker.org/forum/dl.php?t=1', // curl-optie
        'file:///C:/Windows/win.ini',
        'http://192.168.0.1/',
        '',
      ]) {
        expect(rutrackerTorrentAdres(u), isNull, reason: u);
      }
    });
  });

  group('redactedTorrentAdres', () {
    test('het downloadadres op beide namen', () {
      expect(redactedTorrentAdres('https://redacted.sh/ajax.php?action=download&id=42'),
          'https://redacted.sh/ajax.php?action=download&id=42');
      expect(redactedTorrentAdres('https://redacted.ch/ajax.php?action=download&id=42'),
          'https://redacted.ch/ajax.php?action=download&id=42');
    });

    test('een ander adres dat "redacted.sh/ajax.php" alleen bevat, telt niet', () {
      expect(redactedTorrentAdres('https://example.invalid/?redacted.sh/ajax.php&id=5'), isNull);
      expect(redactedTorrentAdres('https://redacted.sh/ajax.php?action=browse&id=42'), isNull);
      expect(redactedTorrentAdres('https://redacted.sh/ajax.php?action=download&id=42&authkey=x'), isNull);
    });
  });

  group('downloadBronFout', () {
    test('een gewoon resultaat van elke bron gaat door', () {
      expect(
          downloadBronFout({
            'torrentUrl': 'https://rutracker.org/forum/dl.php?t=1',
            'magnet': 'magnet:?xt=urn:btih:${'a' * 40}&dn=Kai%20Tracid',
            'hash': 'a' * 40,
          }),
          isNull);
      expect(downloadBronFout({'magnet': 'magnet:?xt=urn:btih:${'b' * 40}&dn=met spatie', 'hash': 'B' * 40}),
          isNull);
      expect(downloadBronFout({'torrentUrl': 'https://redacted.sh/ajax.php?action=download&id=9'}), isNull);
      expect(downloadBronFout({}), isNull, reason: 'leeg mag leeg zijn');
    });

    test('een vreemd adres, een niet-magneet of een rare hash krijgt een zin', () {
      expect(downloadBronFout({'torrentUrl': 'https://example.invalid/'}), contains('niet van RuTracker'));
      expect(downloadBronFout({'magnet': 'http://192.168.0.1/admin'}), contains('geen magneetlink'));
      expect(downloadBronFout({'magnet': 'magnet:?xt=urn:btih:x\nX-Kop: y'}), contains('geen magneetlink'));
      expect(downloadBronFout({'hash': '../../x'}), contains('hash'));
      expect(downloadBronFout({'torrentUrl': 5}), contains('niet te lezen'));
    });
  });

  group('/api/online/download', () {
    late Directory map;
    late LanServer server;
    late _TelDownloads pc;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_dlbron_');
      final settings = AppSettings();
      pc = _TelDownloads(OnlineService(settings), SoulseekService(settings), map.path, () async {});
      server = LanServer(
        library: LibraryStore()..rootPath = map.path,
        token: 'sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
        settings: settings,
        downloads: pc,
        online: OnlineService(settings),
      );
      expect(await server.start(), isNull);
    });

    tearDown(() async {
      await server.dispose();
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<(int, String)> post(String pad, Map<String, dynamic> body) async {
      final http = HttpClient();
      try {
        final req = await http.postUrl(Uri.parse('http://127.0.0.1:${server.boundPort}$pad'));
        req.headers
          ..set(HttpHeaders.authorizationHeader, 'Bearer sleutel')
          ..contentType = ContentType.json;
        req.write(jsonEncode(body));
        final res = await req.close();
        return (res.statusCode, await res.transform(utf8.decoder).join());
      } finally {
        http.close(force: true);
      }
    }

    test('een vreemd torrentadres: 400 met de reden, en er start niets', () async {
      final (status, lichaam) =
          await post('/api/online/download', {'name': 'x', 'torrentUrl': 'https://example.invalid/', 'magnet': '', 'hash': ''});
      expect(status, 400);
      expect(jsonDecode(lichaam)['error'], contains('niet van RuTracker'));
      expect(pc.gestart, isEmpty);
    });

    test('een RuTracker-resultaat zoals de pc het zelf uitgaf, start gewoon', () async {
      final (status, _) = await post('/api/online/download', {
        'name': 'Kai Tracid - Liquid Skies',
        'torrentUrl': 'https://rutracker.org/forum/dl.php?t=6543210',
        'magnet': 'magnet:?xt=urn:btih:${'c' * 40}',
        'hash': 'c' * 40,
      });
      expect(status, 200);
      expect(pc.gestart.single.torrentUrl, 'https://rutracker.org/forum/dl.php?t=6543210');
    });

    test('de tracklijst van een vreemd adres wordt evenmin opgehaald', () async {
      final (status, lichaam) =
          await post('/api/online/tracklist', {'name': 'x', 'torrentUrl': 'https://example.invalid/', 'magnet': ''});
      expect(status, 400);
      expect(jsonDecode(lichaam)['error'], contains('niet van RuTracker'));
    });

    test('ook de cloudwachtrij loopt langs dezelfde controle', () {
      expect(server.startTorrentDownload({'name': 'x', 'torrentUrl': 'https://example.invalid/'}),
          contains('niet van RuTracker'));
      expect(pc.gestart, isEmpty);
    });
  });

  group('haalTorrentBestand: hier gaat het koekje de deur uit', () {
    late Directory map;
    final adressen = <String>[];

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_rtbron_');
      setAppDirForTest(map.path);
      adressen.clear();
      RuTrackerService.curlBeschikbaarVoorTest = true;
      RuTrackerService.curlDichtTot = null;
      RuTrackerService.curlVoorTest = (url) async {
        adressen.add(url);
        return (status: 200, bytes: utf8.encode('d8:announce3:urle'));
      };
    });

    tearDown(() {
      RuTrackerService.curlVoorTest = null;
      RuTrackerService.curlBeschikbaarVoorTest = null;
      RuTrackerService.curlDichtTot = null;
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    RuTrackerService dienst() => RuTrackerService(AppSettings()
      ..rutrackerCookie = 'bb_session=s'
      ..flaresolverrUrl = '');

    test('een vreemd adres: curl wordt niet eens gestart', () async {
      expect(await dienst().haalTorrentBestand('https://example.invalid/x'), isNull);
      expect(await dienst().haalTorrentBestand('https://rutracker.org/forum/dl.php?t=1&x=http://e.invalid'), isNull);
      expect(adressen, isEmpty);
    });

    test('het echte adres gaat door, opnieuw opgebouwd', () async {
      expect(await dienst().haalTorrentBestand(' https://rutracker.org/forum/dl.php?t=77 '), isNotNull);
      expect(adressen, ['https://rutracker.org/forum/dl.php?t=77']);
    });
  });
}
