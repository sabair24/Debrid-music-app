// De torrent-ronde over de hele bibliotheek (Saber, 26-10-2026: "torrent is een mooie aanvulling niet gebruiken voor
// snel download of afspelen functie" — en: "torrent mag veel sneller e, daar is er nie echt controle e, dus die mag
// vollebak gaan"). Plaat na plaat, zonder plafond per uur; rust alleen als TorBox hapert.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/tidal_beter.dart';
import 'package:debridmusic/torrent_beter.dart';
import 'package:flutter_test/flutter_test.dart';

Track _nr(String pad, {String artiest = 'Daft Punk', String album = 'Discovery', int bits = 16, int erbij = 0}) => Track(
    path: pad,
    title: pad.split('/').last.split('.').first,
    artist: artiest,
    album: album,
    duration: const Duration(seconds: 200),
    isFlac: pad.endsWith('.flac'),
    bitsPerSample: pad.endsWith('.flac') ? bits : 0,
    sampleRate: 44100,
    addedMs: erbij);

typedef _Plaat = ({String artiest, String album, List<Track> nummers});

_Plaat _plaat(String artiest, String album, List<Track> nummers) => (artiest: artiest, album: album, nummers: nummers);

final _platen = <_Plaat>[
  _plaat('Daft Punk', 'Discovery', [_nr('dp/One More Time.flac', erbij: 30), _nr('dp/Aerodynamic.flac', bits: 24)]),
  _plaat('Oasis', 'Morning Glory', [
    _nr('oa/Wonderwall.mp3', artiest: 'Oasis', album: 'Morning Glory', erbij: 10),
    _nr('oa/Champagne Supernova.flac', artiest: 'Oasis', album: 'Morning Glory'),
  ]),
  _plaat('Adele', '30', [_nr('ad/Easy On Me.flac', artiest: 'Adele', album: '30', bits: 24)]),
  _plaat('Various Artists', 'Now 42', [_nr('va/Iets.mp3', artiest: 'Iemand', album: 'Now 42')]),
];

TidalMinstens _minstens(Track t) => tidalMinstens(t);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('dm_torrent_beter_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  TorrentBeterGeheugen geheugen() => TorrentBeterGeheugen('${tmp.path}${Platform.pathSeparator}torrent_beter.json');

  test('DE KERN: eerst de plaat met een mp3, dan 16 bit; 24 bit en verzamelaars nooit', () {
    final g = geheugen();
    final eerst = volgendePlaatVoorTorrents(_platen, g, nuMs: 0, minstens: _minstens, overslaan: (_) => false)!;
    expect(eerst.album, 'Morning Glory');
    expect([for (final t in eerst.nummers) t.title], ['Wonderwall', 'Champagne Supernova']);
    g.zet(eerst.sleutel, TorrentBeterUitslag.geen, 0);
    final daarna = volgendePlaatVoorTorrents(_platen, g, nuMs: 0, minstens: _minstens, overslaan: (_) => false)!;
    expect(daarna.album, 'Discovery');
    expect([for (final t in daarna.nummers) t.title], ['One More Time'], reason: 'Aerodynamic is al 24 bit');
    g.zet(daarna.sleutel, TorrentBeterUitslag.geen, 0);
    expect(volgendePlaatVoorTorrents(_platen, g, nuMs: 0, minstens: _minstens, overslaan: (_) => false), isNull,
        reason: 'Adele is al hi-res, Now 42 is een verzamelaar');
  });

  test('overgeslagen nummers (vaste keuze, radio, cd gekozen, twijfel) gaan niet mee', () {
    final p = volgendePlaatVoorTorrents(_platen, geheugen(),
        nuMs: 0, minstens: _minstens, overslaan: (t) => t.title == 'Wonderwall')!;
    expect(p.album, 'Discovery', reason: 'zonder de mp3 is Oasis geen voorrang meer; Discovery is nieuwer');
    expect([for (final t in p.nummers) t.title], ['One More Time']);
    final alleen = volgendePlaatVoorTorrents([_platen[1]], geheugen(),
        nuMs: 0, minstens: _minstens, overslaan: (t) => t.album == 'Morning Glory');
    expect(alleen, isNull);
  });

  test('aan de beurt: niets beters na 30 dagen opnieuw, mislukt na een dag', () {
    final g = geheugen();
    const dag = 24 * 3600 * 1000;
    g.zet('a', TorrentBeterUitslag.geen, 0);
    g.zet('b', TorrentBeterUitslag.mislukt, 0);
    g.zet('c', TorrentBeterUitslag.vervangen, 0, n: 3);
    expect(g.aanDeBeurt('a', 29 * dag), isFalse);
    expect(g.aanDeBeurt('a', kTorrentBeterOpnieuwDagen * dag), isTrue);
    expect(g.aanDeBeurt('b', dag - 1), isFalse);
    expect(g.aanDeBeurt('b', dag), isTrue);
    expect(g.aanDeBeurt('c', 29 * dag), isFalse);
    expect(g.aanDeBeurt('nooit', 0), isTrue);
  });

  test('het geheugen overleeft een herstart; een nieuwe regelversie laat "geen" opnieuw toe', () async {
    final g = geheugen();
    g.zet('a', TorrentBeterUitslag.geen, 5);
    g.zet('b', TorrentBeterUitslag.vervangen, 6, n: 2);
    await g.bewaar();
    final weer = geheugen();
    await weer.laad();
    expect(weer.van('a')?.uit, TorrentBeterUitslag.geen);
    expect(weer.van('b')?.n, 2);
    final f = File('${tmp.path}${Platform.pathSeparator}torrent_beter.json');
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    f.writeAsStringSync(jsonEncode({...j, 'versie': kTorrentBeterGeheugenVersie - 1}));
    final oud = geheugen();
    await oud.laad();
    expect(oud.van('a'), isNull);
    expect(oud.van('b')?.uit, TorrentBeterUitslag.vervangen);
  });

  group('de ronde', () {
    late DateTime nu;
    late List<String> gejaagd;
    late List<String> log;

    TorrentBeterRonde ronde(Future<TorrentJacht> Function(List<Track>, String) jaag, {bool Function()? kan}) =>
        TorrentBeterRonde(
          geheugen: geheugen(),
          platen: () => _platen,
          jaag: (nummers, album) {
            gejaagd.add(album);
            return jaag(nummers, album);
          },
          minstens: _minstens,
          overslaan: (_) => false,
          kan: kan,
          log: log.add,
          klok: () => nu,
        );

    setUp(() {
      nu = DateTime(2026, 10, 26, 12);
      gejaagd = [];
      log = [];
    });

    test('DE KERN: plaat na plaat, zonder plafond per uur', () async {
      final r = ronde((n, a) async => (vervangen: a == 'Morning Glory' ? 1 : 0, bruikbaar: 2, storing: false, alBezig: false));
      expect(await r.stap(), TorrentBeterUitslag.vervangen);
      expect(await r.stap(), TorrentBeterUitslag.geen);
      expect(await r.stap(), isNull, reason: 'alles bekeken');
      expect(gejaagd, ['Morning Glory', 'Discovery'], reason: 'geen wachttijd tussen twee platen');
      expect(log.first, contains('1 van 2 nummers beter uit torrents'));
      expect(kTorrentBeterAdem, lessThanOrEqualTo(const Duration(seconds: 30)));
      expect(kTorrentBeterTegelijk, greaterThanOrEqualTo(2));
    });

    test('TorBox hapert: een kwartier rust, en de plaat komt morgen terug', () async {
      final r = ronde((n, a) async => (vervangen: 0, bruikbaar: 3, storing: true, alBezig: false));
      expect(await r.stap(), TorrentBeterUitslag.mislukt);
      expect(await r.stap(), isNull);
      nu = nu.add(kTorrentBeterRust);
      expect(await r.stap(), TorrentBeterUitslag.mislukt, reason: 'na de rust de volgende plaat');
      expect(gejaagd, ['Morning Glory', 'Discovery']);
    });

    test('een fout in de jacht telt als storing', () async {
      final r = ronde((n, a) async => throw 'geen netwerk');
      expect(await r.stap(), TorrentBeterUitslag.mislukt);
      expect(log.single, contains('geen netwerk'));
      expect(await r.stap(), isNull);
    });

    test('"Zoek hi-res" zoekt de plaat al af: niets onthouden, een halfuur overslaan', () async {
      final r = ronde((n, a) async => (vervangen: 0, bruikbaar: 0, storing: false, alBezig: a == 'Morning Glory'));
      expect(await r.stap(), TorrentBeterUitslag.geen);
      expect(await r.stap(), TorrentBeterUitslag.geen);
      expect(gejaagd, ['Morning Glory', 'Discovery']);
      expect(r.geheugen.van(torrentPlaatSleutel('Oasis', 'Morning Glory')), isNull);
      nu = nu.add(kTorrentBeterAlBezig);
      expect(await r.stap(), TorrentBeterUitslag.geen);
      expect(gejaagd.last, 'Morning Glory');
    });

    test('TorBox niet ingesteld: niets gezocht en niets onthouden', () async {
      final r = ronde((n, a) async => (vervangen: 0, bruikbaar: 0, storing: false, alBezig: false), kan: () => false);
      expect(await r.stap(), isNull);
      expect(gejaagd, isEmpty);
      expect(r.geheugen.aantal, 0);
    });

    test('twee tegelijk nemen elk een andere plaat', () async {
      final los = <String, Completer<TorrentJacht>>{};
      final r = ronde((n, a) => (los[a] = Completer<TorrentJacht>()).future);
      final een = r.stap();
      final twee = r.stap();
      await Future<void>.delayed(Duration.zero);
      expect(gejaagd, ['Morning Glory', 'Discovery']);
      expect(r.bezig, hasLength(2));
      for (final c in los.values) {
        c.complete((vervangen: 0, bruikbaar: 1, storing: false, alBezig: false));
      }
      expect(await een, TorrentBeterUitslag.geen);
      expect(await twee, TorrentBeterUitslag.geen);
      expect(r.bezig, isEmpty);
    });
  });

  test('aangesloten: op de pc, met de jacht van "Zoek hi-res", en storing als TorBox niets opent', () {
    String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    final m = bron('lib/main.dart');
    expect(m, contains('        jaag: downloads.zoekBeterInTorrents,\n'));
    expect(m, contains('        kan: () => online.torboxReady,\n'));
    expect(m, contains('            twijfelVoor(t.path) != null,\n'));
    final o = bron('lib/online.dart');
    expect(o, contains('  Future<TorrentJacht> zoekBeterInTorrents(List<Track> nummers, String album) =>\n'
        '      _zoekHiresInTorrents(nummers, album, gezagVoor);\n'));
    expect(o, contains('      return (vervangen: vervangen, bruikbaar: bruikbaar, storing: klaarDicht > 0 && klaarOpen == 0, '
        'alBezig: false);\n'));
    expect(o, contains('          if (r.cached) klaarDicht++;\n'));
    // Nooit bij halen of ▶: alleen "Zoek hi-res" en de ronde roepen de torrentjacht aan.
    expect(RegExp(r'_zoekHiresInTorrents\(').allMatches(o).length, 3, reason: 'de definitie, Zoek hi-res, de ronde');
  });
}
