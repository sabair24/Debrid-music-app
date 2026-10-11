/// Een koude start toont meteen wat er op dit toestel ligt — ook als de pc niet antwoordt.
///
/// **Waarom.** Saber op 11-10-2026: *"op men gsm bij de cold start, laadt de home page met recent
/// toegevoegd enzo verder heel traag"*. In `verbinding.log` van de gsm stond 12:43:47 "verbinden met"
/// en 12:44:17 "pc antwoordt": dertig seconden, de time-out van één verzoek. De pc-app draaide nog niet,
/// en Windows laat een verzoek aan een dichte poort onbeantwoord in plaats van het te weigeren. Het
/// verbinden wachtte eerst op de gedeelde sleutels (`config`), en pas daarna kwam de kopie van de
/// catalogus op dit toestel op het scherm. Met de pc aan gemeten: eerste beeld 0,24 s, startpagina met
/// hoezen na 2,1 s.
///
/// De pc hier zwijgt precies zo: hij neemt de verbinding aan en zegt niets terug.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/catalogus_kopie.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/client_session.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String path, String title, String artist, String album, {int no = 1}) => Track(
      path: path,
      title: title,
      artist: artist,
      album: album,
      trackNo: no,
      duration: const Duration(seconds: 240),
      isFlac: true,
      sizeBytes: 4096,
      sampleRate: 44100,
      bitsPerSample: 16,
      year: 2005,
    );

void main() {
  late Directory krab;
  late ServerSocket stil;
  final open = <Socket>[];

  setUp(() async {
    krab = Directory.systemTemp.createTempSync('dm_koudestart_');
    setAppDirForTest(krab.path);
    // De catalogus zoals de pc hem de vorige keer gaf, bewaard op dit toestel.
    final pc = LibraryStore()
      ..rootPath = krab.path
      ..configDirOverride = krab.path;
    pc.tracks.addAll([
      _t('${krab.path}/a1.flac', 'Stuck On You', 'Lionel Richie', 'The Definitive Collection'),
      _t('${krab.path}/b1.flac', 'Believe', 'Justin Bieber', 'Believe Acoustic'),
    ]);
    pc.rebuildAlbums();
    await const CatalogusKopie()
        .bewaar(jsonDecode(utf8.decode(LanCatalog(pc).snapshot().json)) as Map<String, dynamic>);
    // Een pc die de verbinding aanneemt en nooit antwoordt.
    stil = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    stil.listen(open.add);
  });

  tearDown(() async {
    for (final s in open) {
      s.destroy();
    }
    await stil.close();
    try {
      krab.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('DE KERN: de kopie op dit toestel staat er binnen een tel, terwijl de pc nog zwijgt', () async {
    final bib = LibraryStore();
    var hersteld = false;
    final sessie = ClientSession(
      library: bib,
      settings: AppSettings(),
      owner: false,
      applyMediaResolver: (_) {},
    );
    final klok = Stopwatch()..start();
    unawaited(sessie.connect(
      RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:${stil.port}'), token: 't'),
      remember: false,
      zodraErIetsStaat: () async => hersteld = true,
    ));
    while (bib.tracks.isEmpty && klok.elapsed < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(bib.tracks.map((t) => t.title), containsAll(['Stuck On You', 'Believe']),
        reason: 'na ${klok.elapsedMilliseconds} ms nog leeg — vroeger dertig seconden');
    expect(klok.elapsed, lessThan(const Duration(seconds: 2)));
    expect(bib.kopieVanToestel, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(hersteld, isTrue, reason: 'de wachtrij en de spelerbalk horen er dan ook al te staan');
  });
}
