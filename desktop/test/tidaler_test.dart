/// Muziek van TIDAL halen met tidaler (sinds 22-10-2026, in plaats van tiddl: Saber, "tidaler als primair tiddl mag
/// weg").
///
/// Wat zonder Python, zonder abonnement en zonder netwerk vastligt: waar het programma en zijn Python gezocht worden,
/// wat er van een geplakte link overblijft, welke instellingen vóór een download gezet worden, de kwaliteit uit het
/// bestand zelf, de zoektreffers van het hulpje, en wat er van een mislukking op het scherm komt.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/tidal.dart' show TidalKwaliteit, tidalKwaliteitUit;
import 'package:debridmusic/tidaler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Het begin van een FLAC: "fLaC" en een STREAMINFO-blok met [hz] en [bits].
Uint8List _flacKop(int hz, int bits, {bool id3 = false}) {
  final si = Uint8List(34);
  si[10] = (hz >> 12) & 0xff;
  si[11] = (hz >> 4) & 0xff;
  si[12] = ((hz & 0x0f) << 4) | ((2 - 1) << 1) | (((bits - 1) >> 4) & 0x01);
  si[13] = ((bits - 1) & 0x0f) << 4;
  final flac = [0x66, 0x4C, 0x61, 0x43, 0x80, 0, 0, 34, ...si];
  if (!id3) return Uint8List.fromList(flac);
  return Uint8List.fromList([0x49, 0x44, 0x33, 3, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, ...flac]);
}

void main() {
  group('waar tidaler gezocht wordt', () {
    test('PATH staat vooraan, want daar zetten pip en uv hem allebei neer', () {
      expect(tidalerKandidaten(os: 'linux', thuis: '/home/saber').first, 'tidaler');
      expect(tidalerKandidaten(os: 'windows', thuis: r'C:\Users\saber').first, 'tidaler.exe');
    });

    test('en de plekken waar ze hem laten staan als PATH niet bijgewerkt is', () {
      // Na een verse installatie op Windows is dat het gewone geval; zo staat hij ook op Sabers pc.
      expect(tidalerKandidaten(os: 'windows', thuis: r'C:\Users\saber'),
          contains(r'C:\Users\saber\.local\bin\tidaler.exe'));
      expect(tidalerKandidaten(os: 'macos', thuis: '/Users/saber'), contains('/Users/saber/.local/bin/tidaler'));
      expect(tidalerKandidaten(os: 'macos', thuis: '/Users/saber'), contains('/opt/homebrew/bin/tidaler'));
    });

    test('zonder thuismap blijft alleen PATH over, en dat stort niet in', () {
      expect(tidalerKandidaten(os: 'linux'), ['tidaler', '/opt/homebrew/bin/tidaler', '/usr/local/bin/tidaler']);
      expect(tidalerKandidaten(os: 'windows'), ['tidaler.exe']);
    });

    test('zijn Python, voor het zoekhulpje: de omgeving die uv of pipx hem gaf', () {
      final win = tidalerPythonKandidaten(
          os: 'windows', thuis: r'C:\Users\saber', appData: r'C:\Users\saber\AppData\Roaming');
      expect(win.first, r'C:\Users\saber\AppData\Roaming\uv\tools\tidaler\Scripts\python.exe',
          reason: 'zo staat hij op Sabers pc (uv tool install)');
      expect(
          tidalerPythonKandidaten(os: 'windows', thuis: r'C:\U', appData: r'C:\A', uvToolDir: r'D:\uvtools').first,
          r'D:\uvtools\tidaler\Scripts\python.exe',
          reason: 'UV_TOOL_DIR gaat voor');
      expect(tidalerPythonKandidaten(os: 'macos', thuis: '/Users/saber'),
          contains('/Users/saber/.local/share/uv/tools/tidaler/bin/python'));
    });
  });

  group('wat er van een geplakte link overblijft', () {
    test('de twee adressen die Tidal zelf gebruikt', () {
      expect(tidalDoel('https://tidal.com/browse/album/103805723'), 'album/103805723');
      expect(tidalDoel('https://listen.tidal.com/album/103805723'), 'album/103805723');
    });

    test('de meelifterij van de deelknop gaat eraf', () {
      expect(tidalDoel('https://tidal.com/browse/track/103805726?u'), 'track/103805726');
      expect(tidalDoel('https://listen.tidal.com/album/103805723/'), 'album/103805723');
    });

    test('de korte vorm', () {
      expect(tidalDoel('album/103805723'), 'album/103805723');
      expect(tidalDoel('  track/103805726  '), 'track/103805726');
    });

    test('alle zes de soorten', () {
      for (final soort in ['track', 'album', 'artist', 'playlist', 'mix', 'video']) {
        expect(tidalDoel('https://tidal.com/browse/$soort/123'), '$soort/123');
      }
    });

    test('wat niet klopt wordt hier geweigerd, niet door Python', () {
      expect(tidalDoel(''), isNull);
      expect(tidalDoel('   '), isNull);
      expect(tidalDoel('https://open.spotify.com/album/123'), isNull);
      expect(tidalDoel('https://tidal.com/browse/album'), isNull, reason: 'geen id');
      expect(tidalDoel('https://tidal.com/browse/onzin/123'), isNull, reason: 'geen bekende soort');
      expect(tidalDoel('103805723'), isNull, reason: 'een kaal getal zegt niet wát het is');
      expect(tidalDoel('gewoon wat tekst'), isNull);
    });

    test('tidaler neemt alleen een volle link', () {
      // Een kaal "track/123" weigert hij met "It seems like you have supplied an invalid URL" (cli.py, 0.1.8).
      expect(tidalerUrl('track/96600827'), 'https://tidal.com/browse/track/96600827');
    });
  });

  group('de instellingen vóór een download', () {
    test('de keuringsmap, de kwaliteit, en niets overslaan', () {
      final i = tidalerInstellingen(map: r'D:\keuring\tidal-wens-1', kwaliteit: 'max', ffmpeg: r'C:\ffmpeg\bin\ffmpeg.exe');
      final m = {for (final x in i) x[0]: x[1]};
      expect(m['download_base_path'], r'D:\keuring\tidal-wens-1', reason: 'één argument, ook met spaties');
      expect(m['quality_audio'], 'HI_RES_LOSSLESS');
      expect(m['skip_existing'], 'False', reason: 'anders levert hij niets en sluit toch af met 0');
      expect(m['extract_flac'], 'True');
      expect(m['path_binary_ffmpeg'], r'C:\ffmpeg\bin\ffmpeg.exe', reason: 'zonder ffmpeg geen FLAC uit de MP4');
      expect(tidalerInstellingen(map: 'x', kwaliteit: 'max').any((x) => x[0] == 'path_binary_ffmpeg'), isFalse,
          reason: 'ffmpeg via PATH: dan niets overschrijven');
    });

    test('de kwaliteiten van het venster, zoals tidalapi ze noemt', () {
      expect(tidalKwaliteiten.first, 'max');
      expect(tidalerKwaliteit('max'), 'HI_RES_LOSSLESS');
      expect(tidalerKwaliteit('high'), 'LOSSLESS');
      expect(tidalerKwaliteit('normal'), 'HIGH');
      expect(tidalerKwaliteit('low'), 'LOW');
    });
  });

  group('wat er binnenkwam, en niet wat je vroeg', () {
    test('de kwaliteit uit de STREAMINFO van het bestand', () {
      // Gemeten op 22-10-2026: Tamino — Indigo Night van tidaler, 24 bit / 44,1 kHz.
      expect(flacKwaliteit(_flacKop(44100, 24)), '24 bit / 44.1 kHz');
      expect(flacKwaliteit(_flacKop(96000, 24)), '24 bit / 96 kHz');
      expect(flacKwaliteit(_flacKop(44100, 16, id3: true)), '16 bit / 44.1 kHz', reason: 'ook met een ID3 ervoor');
      expect(flacKwaliteit(Uint8List.fromList([0, 1, 2, 3])), isNull, reason: 'geen FLAC: niets verzinnen');
    });

    test('een map: elke kwaliteit één keer, gemengd allebei', () async {
      final map = await Directory.systemTemp.createTemp('dm_tidaler_');
      addTearDown(() => map.delete(recursive: true));
      await Directory('${map.path}/Tracks').create();
      await File('${map.path}/Tracks/a.flac').writeAsBytes(_flacKop(44100, 24));
      await File('${map.path}/Tracks/b.flac').writeAsBytes(_flacKop(44100, 24));
      expect(await kwaliteitInMap(map), '24 bit / 44.1 kHz');
      await File('${map.path}/Tracks/c.flac').writeAsBytes(_flacKop(44100, 16));
      expect(await kwaliteitInMap(map), contains(' · '));
      expect(await kwaliteitInMap(Directory('${map.path}/bestaat-niet')), isNull);
    });

    test('de melding, met en zonder keuring', () {
      expect(opgehaaldMelding(''), isNot(contains('(')));
      expect(opgehaaldMelding('24 bit / 44.1 kHz'), contains('24 bit / 44.1 kHz'));
      final m = opgehaaldMelding('24 bit / 96 kHz', keuring: '11 opgeborgen · 1 afgekeurd (kapot)');
      expect(m, contains('1 afgekeurd (kapot)'));
      expect(opgehaaldMelding('', keuring: ''), opgehaaldMelding(''));
    });
  });

  group('de zoektreffers van het hulpje', () {
    test('elke regel JSON één treffer, met de versie in de titel; Atmos en rommel vallen weg', () {
      const uit = 'Failed to load API keys from gist: timeout\n'
          '{"id": "19823990", "artiest": "Daft Punk", "titel": "Get Lucky (Radio Edit)", "seconden": 248, '
          '"stereo": true, "tags": ["LOSSLESS", "HIRES_LOSSLESS"]}\n'
          '{"id": "19823990", "artiest": "Daft Punk", "titel": "Get Lucky (Radio Edit)", "stereo": true}\n'
          '{"id": "1", "artiest": "Daft Punk", "titel": "Get Lucky", "stereo": false}\n'
          '{kapot\n';
      final t = tidalZoektreffers(uit);
      expect(t, hasLength(1));
      expect(t.single, (id: '19823990', artiest: 'Daft Punk', titel: 'Get Lucky (Radio Edit)'));
    });

    test('het zoekscherm: platen én nummers, elk één keer; de wens ziet alleen de nummers', () {
      const uit = '{"soort": "album", "id": "96600816", "artiest": "Tamino", "titel": "Amir", "jaar": "2018"}\n'
          '{"soort": "album", "id": "96600816", "artiest": "Tamino", "titel": "Amir", "jaar": "2018"}\n'
          '{"id": "96600827", "artiest": "Tamino", "titel": "Indigo Night", "stereo": true}\n'
          '{"id": "1", "artiest": "Tamino", "titel": "Indigo Night", "stereo": false}\n';
      final r = tidalCatalogusUit(uit);
      expect(r.albums.single.id, '96600816');
      expect(r.albums.single.jaar, '2018');
      expect(r.albums.single.label, 'Tamino — Amir');
      expect(r.tracks.map((t) => t.id), ['96600827', '1'], reason: 'het scherm toont de catalogus; de keuring beslist');
      expect(tidalZoektreffers(uit).map((t) => t.id), ['96600827'], reason: 'geen platen en alleen stereo voor de wens');
      expect(kTidalZoekHulp, contains('alles = len(sys.argv) > 3 and sys.argv[3] == "alles"'));
      expect(kTidalZoekHulp, contains('sys.stdout.reconfigure(encoding="utf-8")'),
          reason: 'met -I negeert Python PYTHONIOENCODING: KAYTRAMINÉ werd KAYTRAMIN?');
    });

    test('aangesloten: het TIDAL-zoekscherm zoekt op de pc via tidaler, zonder tweede login', () {
      final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final zoek = m.substring(m.indexOf('  Future<void> _searchTidal(String q) async {'));
      expect(zoek.substring(0, 900), contains('if (!viaTidaler && !tidal.connected) return;'));
      expect(zoek.substring(0, 1800), contains('await zoekCatalogusOpTidal(q) ??'));
      final scherm = m.substring(m.indexOf('  Widget _tidalResults() {'));
      expect(scherm.substring(0, 400), contains('if (!viaTidaler && !tidal.configured) {'));
      expect(m, contains('return _isDesktop && !lib.isRemote && Tidaler.beschikbaar && Tidaler.python != null;'));
    });

    test('aangesloten: gsm, iPad, Mac en Shield vragen het de pc (Saber: "ook mogelijk vanaf men gsm, mac ipad en shield")', () {
      final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final poort = m.substring(m.indexOf('  bool get _tidalerZoekt {'));
      expect(poort.substring(0, 300), contains('if (lib.remote != null) return true;'));
      final zoek = m.substring(m.indexOf('  Future<void> _searchTidal(String q) async {'));
      expect(zoek.substring(0, 1800), contains("await _tidalOpPc(context.read<LibraryStore>(), 'zoek', {'q': q})"));
      expect(m, contains("final a = await c.ask('/api/tidal/\$wat', vraag);"));
      expect(m, contains("return tidalCatalogusUit('\${a['uitvoer'] ?? ''}');"), reason: 'dezelfde lezer als op de pc');
      expect(m, contains("await c.ask('/api/tidal/haal', {'doel': doel});"), reason: 'ophalen doet de pc');
      expect(m, contains('final kanOphalen = _tidalViaPc || (_isDesktop && !context.read<LibraryStore>().isRemote);'));
      final s = File('lib/lan/server.dart').readAsStringSync().replaceAll('\r\n', '\n');
      for (final wat in ['zoek', 'album', 'artiest', 'haal']) {
        expect(s, contains("case '/api/tidal/$wat':\n        return _tidal(req, '$wat');"));
      }
      final h = s.substring(s.indexOf('  Future<void> _tidal(HttpRequest req, String wat) async {'));
      expect(h, contains('final uit = await tidalHulpUitvoer(argumenten);'));
      expect(h, contains('unawaited(_tidalHaalHier(manager, doel));'));
      final hier = s.substring(s.indexOf('  Future<void> _tidalHaalHier('));
      expect(hier, contains("manager.keurBinnengekomen(keuring, 'TIDAL \$doel', zichtbaar: manager.tidalRest)"),
          reason: 'door dezelfde keuring als "Ophalen van Tidal…" op de pc');
    });

    test('het hulpje gebruikt tidalers eigen inlog en geeft de volle titel', () {
      expect(kTidalZoekHulp, contains('from tidaler.config import Settings, Tidal'));
      expect(kTidalZoekHulp, contains('if not t.login_token():'));
      expect(kTidalZoekHulp, contains('return f"{naam} ({versie})"'));
      expect(kTidalZoekHulp, contains('if not versie or versie.lower() in naam.lower():'),
          reason: 'bij "Close To Me (Solo)" stond de versie al in de naam: "(Solo) (Solo)"');
      expect(kTidalZoekHulp, isNot(contains('access_token')), reason: 'de sleutel komt nooit in de uitvoer');
    });

    test('foto’s, hoezen en de nummers van een plaat (Saber: "liedje per liedje … artiest foto en album cover")', () {
      const uit = '{"soort": "artiest", "id": "8495179", "naam": "Tamino", "foto": "https://resources.tidal.com/a.jpg"}\n'
          '{"soort": "album", "id": "96600816", "artiest": "Tamino", "titel": "Amir", "jaar": "2018", '
          '"hoes": "https://resources.tidal.com/h320.jpg", "aantal": 12}\n'
          '{"soort": "track", "id": "96600827", "artiest": "Tamino", "titel": "Indigo Night", "seconden": 255, '
          '"nummer": 6, "schijf": 1, "album": "Amir", "albumId": "96600816", "hoes": "https://resources.tidal.com/h160.jpg", '
          '"stereo": true}\n';
      final r = tidalCatalogusUit(uit);
      expect(r.artiesten.single.foto, 'https://resources.tidal.com/a.jpg');
      expect(r.albums.single.hoes, 'https://resources.tidal.com/h320.jpg');
      expect(r.albums.single.aantal, 12);
      final t = r.tracks.single;
      expect([t.hoes, t.album, t.albumId, t.seconden, t.nummer],
          ['https://resources.tidal.com/h160.jpg', 'Amir', '96600816', 255, 6]);
      expect(tidalZoektreffers(uit).map((x) => x.id), ['96600827'], reason: 'de wens ziet geen artiesten of platen');
      expect(kTidalZoekHulp, contains('if sys.argv[1] == "--album":'));
      expect(kTidalZoekHulp, contains('if sys.argv[1] == "--artiest":'));
    });

    test('EG.0 staat twee keer bij TIDAL: de 24-bitversie komt vóór de 16-bitversie, en het label zegt het', () {
      // Gemeten op 22-10-2026: album 568446935 (Close To Me (Solo) 568446942) alleen LOSSLESS — 16 bit; album
      // 568446947 (568446955) HIRES_LOSSLESS — 24 bit. Saber haalde de eerste: "de solo ook enkel 16/44.1 binnen".
      const uit = '{"soort": "album", "id": "568446935", "artiest": "Ellie Goulding", "titel": "EG.0", "tags": ["LOSSLESS"]}\n'
          '{"soort": "album", "id": "29583536", "artiest": "Ellie Goulding", "titel": "Halcyon Days", "tags": ["LOSSLESS"]}\n'
          '{"soort": "album", "id": "568446947", "artiest": "Ellie Goulding", "titel": "EG.0", '
          '"tags": ["LOSSLESS", "HIRES_LOSSLESS"]}\n'
          '{"soort": "track", "id": "568446942", "artiest": "Ellie Goulding", "titel": "Close To Me (Solo)", '
          '"tags": ["LOSSLESS"], "stereo": true}\n'
          '{"soort": "track", "id": "568446955", "artiest": "Ellie Goulding", "titel": "Close To Me (Solo)", '
          '"tags": ["LOSSLESS", "HIRES_LOSSLESS"], "stereo": true}\n';
      final r = tidalCatalogusUit(uit);
      expect(r.albums.map((a) => a.id), ['568446947', '568446935', '29583536'], reason: 'op de plek van de eerste');
      expect(r.albums.first.kwaliteit, TidalKwaliteit.hires);
      expect(r.albums[1].kwaliteit, TidalKwaliteit.cd);
      expect(r.tracks.map((t) => t.id), ['568446955', '568446942']);
      expect(tidalKwaliteitUit(const []), TidalKwaliteit.onbekend, reason: 'de officiële API zegt het niet: geen label');
      final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(m, contains("child: Text(hoog ? '24 bit' : '16 bit',"));
      expect('_tidalKwaliteitsLabel('.allMatches(m).length, 4, reason: 'de functie, een plaat, een nummer, een nummer op een plaat');
    });

    test('aangesloten: een plaat klapt open op haar nummers, elk met Ophalen; een artiest opent met zijn foto', () {
      final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final rij = m.substring(m.indexOf('  Widget _tidalAlbumRow(int i, TidalAlbum a, bool kanOphalen) {'));
      expect(rij.substring(0, 1200), contains('if (!open && viaTidaler) unawaited(_laadTidalAlbum(a.id));'));
      expect(rij, contains('if (open && viaTidaler) _tidalAlbumInhoud(a, kanOphalen),'));
      final inhoud = m.substring(m.indexOf('  Widget _tidalAlbumInhoud(TidalAlbum a, bool kanOphalen) {'));
      expect(inhoud.substring(0, 2600), contains("_ophaalKnop(tidalDoelVanId('track', t.id), t.label)"));
      expect(m, contains('onPressed: () => _openTidalArtiest(a),'));
      expect(m, contains('_netCover(a.hoes, size: 48, radius: 6),'));
      expect(m, contains('_netCover(t.hoes, size: 40, radius: 5),'));
    });
  });

  group('wat er van een mislukking op het scherm komt', () {
    test('de kleurcodes van Rich gaan eraf', () {
      expect(leesbareFout('\x1B[31mTrack not available in your country\x1B[0m'), 'Track not available in your country');
    });

    test('alleen de laatste regels, want de rest is voortgangsbalk', () {
      final rauw = [for (var i = 1; i <= 20; i++) 'regel $i'].join('\n');
      expect(leesbareFout(rauw, regels: 3), 'regel 18\nregel 19\nregel 20');
    });

    test('regelterugloop telt als een nieuwe regel', () {
      expect(leesbareFout('bezig 10%\rbezig 90%\rklaar', regels: 1), 'klaar');
    });

    test('niets is ook een antwoord', () {
      expect(leesbareFout(''), isNotEmpty);
      expect(leesbareFout('   \n \n '), isNotEmpty);
    });
  });

  group('ffmpeg ook op het PATH', () {
    test('de map van ffmpeg komt vooraan te staan, één keer', () {
      expect(padMetFfmpeg(r'C:\ffmpeg\bin\ffmpeg.exe', r'C:\Windows', windows: true), r'C:\ffmpeg\bin;C:\Windows');
      const eerst = r'C:\ffmpeg\bin;C:\Windows';
      expect(padMetFfmpeg(r'C:\FFmpeg\Bin\ffmpeg.exe', eerst, windows: true), eerst);
      expect(padMetFfmpeg('ffmpeg.exe', r'C:\Windows', windows: true), r'C:\Windows');
      expect(padMetFfmpeg(null, r'C:\Windows', windows: true), r'C:\Windows');
      expect(padMetFfmpeg(r'C:\ffmpeg\bin\ffmpeg.exe', '', windows: true), r'C:\ffmpeg\bin');
    });
  });

  test('aangesloten: gelukt is een bestand, niet de afloopcode; één download tegelijk', () {
    final s = File('lib/tidaler.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final haal = s.substring(s.indexOf('Future<({String? fout, String? kwaliteit})> _haal('));
    expect(haal, contains("final r = await Process.run(tool, ['dl', tidalerUrl(doel)],"));
    expect(haal, contains('if (!iets) {'), reason: 'tidaler dl sluit ook na een mislukking af met 0');
    expect(s, contains('_beurt = klaar.future.then((_) {}, onError: (_) {});'));
    expect(File('lib/tiddl.dart').existsSync(), isFalse, reason: 'tiddl is weg (Saber, 22-10-2026)');
  });
}
