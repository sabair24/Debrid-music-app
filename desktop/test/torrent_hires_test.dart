// Hi-res uit torrents bij "Zoek hi-res" (Saber, 25-10-2026: "ook via torrents moet worden gezocht, wel losse tracks").
// De namen hieronder komen uit zijn lijst "Bronnen voor album" van Stadium Arcadium (Red Hot Chili Peppers).
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart' show DownloadManager;
import 'package:debridmusic/organize.dart' show fileOffersTitle;
import 'package:debridmusic/tidal_beter.dart' show TidalMinstens;
import 'package:debridmusic/torbox.dart' show SearchResult;
import 'package:debridmusic/torrent_hires.dart';
import 'package:flutter_test/flutter_test.dart';

SearchResult _r(String naam, {bool instant = true, int seeders = 5}) =>
    SearchResult(name: naam, magnet: 'magnet:?xt=urn:btih:${naam.hashCode}', hash: '${naam.hashCode}', seeders: seeders, cached: instant);

final _stadium = [
  _r('Red Hot Chili Peppers - Stadium Arcadium (2006 PBTHAL LP 24-96)', seeders: 41),
  _r('Red Hot Chili Peppers - Stadium Arcadium [2006][only1joe]FLAC-EA', seeders: 25),
  _r('Red Hot Chili Peppers - Stadium Arcadium (2006) [FLAC]', seeders: 21),
  _r('Red Hot Chili Peppers - Stadium Arcadium [24 bit FLAC] vinyl', seeders: 10),
  _r('(Rock) [LP] [24/192] Red Hot Chili Peppers - Stadium Arcadium - 2006/2016, FLAC (image+cue)', seeders: 5),
  _r('(Rock/Funk/Alternative) Red Hot Chili Peppers "Stadium Arcadium" (vinyl 24/96) - 2006, FLAC (tracks), 24bit/96kHz',
      seeders: 4),
  _r('(alternative/funk/rock) [LP][24/96] Red Hot Chili Peppers - Stadium Arcadium {SE 180g Heavy Vinyl, by S. Hoffman} - '
      '2006, FLAC (tracks), lossless',
      seeders: 1),
  _r('Red Hot Chili Peppers - Stadium Arcadium [2006 - MP3 - 320 kbps]', instant: false, seeders: 25),
  _r('(Rock/Funk/Alternative)[LP][24/96] Red Hot Chili Peppers - Stadium Arcadium - 2006, FLAC (image+.cue)',
      instant: false, seeders: 10),
  _r('(Бас-гитара / Alternative rock / Табулатуры Guitar Pro) Red Hot Chili Peppers - I\'m with You, Stadium Arcadium, '
      'By the Way [gp5, ENG]',
      instant: false, seeders: 8),
  _r('(Alternative/Funk) [LP] [24/96] Red Hot Chili Peppers - Stadium Arcadium [PBTHAL] (Original US Pressing) - 2006, '
      'FLAC (tracks)',
      instant: false, seeders: 7),
  _r('Red Hot Chili Peppers - Stadium Arcadium 5.1 Surround DVD-Audio 24-96 FLAC'),
  _r('Red Hot Chili Peppers - Stadium Arcadium DSD64'),
  _r('Red Hot Chili Peppers - Discography 1984-2022 FLAC 24-96'),
];

void main() {
  test('losse nummers of image: wat de naam zegt', () {
    expect(indelingUitTitel('… 2006, FLAC (tracks), 24bit/96kHz'), TorrentIndeling.losseNummers);
    expect(indelingUitTitel('… 2006/2016, FLAC (image+cue)'), TorrentIndeling.image);
    expect(indelingUitTitel('… 2006, FLAC (image+.cue)'), TorrentIndeling.image);
    expect(indelingUitTitel('… 2006, APE (img+cue)'), TorrentIndeling.image);
    expect(indelingUitTitel('… (2006 PBTHAL LP 24-96)'), TorrentIndeling.onbekend);
  });

  test('losse nummers of image: wat de bestanden zeggen', () {
    expect(indelingUitBestanden([for (var i = 1; i <= 12; i++) 'SA/$i - Nummer.flac', 'SA/SA.cue', 'SA/folder.jpg']),
        TorrentIndeling.losseNummers);
    expect(indelingUitBestanden(['SA/Stadium Arcadium.flac', 'SA/Stadium Arcadium.cue', 'SA/scan.jpg']), TorrentIndeling.image);
    expect(indelingUitBestanden(['SA/CD1.flac', 'SA/CD1.cue', 'SA/CD2.flac', 'SA/CD2.cue']), TorrentIndeling.image,
        reason: 'een image per schijf');
    expect(indelingUitBestanden(['SA/info.txt', 'SA/scan.jpg']), TorrentIndeling.onbekend);
  });

  test('hi-res volgens de naam, ook zonder het woord FLAC', () {
    expect(hiresVolgensNaam('Red Hot Chili Peppers - Stadium Arcadium (2006 PBTHAL LP 24-96)'), isTrue);
    expect(hiresVolgensNaam('… [24 bit FLAC] vinyl'), isTrue);
    expect(hiresVolgensNaam('… [2006][only1joe]FLAC-EA'), isFalse);
    expect(hiresVolgensNaam('… [2006 - MP3 - 320 kbps]'), isFalse);
    expect(hiresVolgensNaam('… DSD64'), isFalse, reason: 'geen FLAC: niet door de keuring te halen');
  });

  group('welke torrents, in welke volgorde', () {
    test('hi-res nodig: de plaat zelf, losse nummers, geen surround, geen DSD, geen discografie; Instant eerst', () {
      final uit = torrentsVoorHires(_stadium,
          artiest: 'Red Hot Chili Peppers', album: 'Stadium Arcadium', jaar: 2006, hiresNodig: true);
      expect([for (final r in uit) r.name], [
        'Red Hot Chili Peppers - Stadium Arcadium (2006 PBTHAL LP 24-96)',
        'Red Hot Chili Peppers - Stadium Arcadium [24 bit FLAC] vinyl',
        '(Rock/Funk/Alternative) Red Hot Chili Peppers "Stadium Arcadium" (vinyl 24/96) - 2006, FLAC (tracks), 24bit/96kHz',
        '(alternative/funk/rock) [LP][24/96] Red Hot Chili Peppers - Stadium Arcadium {SE 180g Heavy Vinyl, by S. Hoffman} - '
            '2006, FLAC (tracks), lossless',
        // Nog niet bij TorBox, maar 7 seeders: na alles wat er al is.
        '(Alternative/Funk) [LP] [24/96] Red Hot Chili Peppers - Stadium Arcadium [PBTHAL] (Original US Pressing) - 2006, '
            'FLAC (tracks)',
      ]);
    });

    test('nog niet bij TorBox: pas na alles wat er al is, ook als het digitaal is; met minder dan 3 seeders niet', () {
      final uit = torrentsVoorHires([
        _r('Red Hot Chili Peppers - Stadium Arcadium (2006) [FLAC 24-96] WEB', instant: false, seeders: 30),
        _r('Red Hot Chili Peppers - Stadium Arcadium [24 bit FLAC] vinyl', seeders: 1),
        _r('Red Hot Chili Peppers - Stadium Arcadium (2006) [FLAC 24-192] WEB', instant: false, seeders: 2),
      ], artiest: 'Red Hot Chili Peppers', album: 'Stadium Arcadium', jaar: 2006, hiresNodig: true);
      expect([for (final r in uit) r.name], [
        'Red Hot Chili Peppers - Stadium Arcadium [24 bit FLAC] vinyl',
        'Red Hot Chili Peppers - Stadium Arcadium (2006) [FLAC 24-96] WEB',
      ]);
    });

    test('een digitale hi-res gaat voor vinyl', () {
      final uit = torrentsVoorHires([..._stadium, _r('Red Hot Chili Peppers - Stadium Arcadium (2006) [FLAC 24-96] WEB', seeders: 2)],
          artiest: 'Red Hot Chili Peppers', album: 'Stadium Arcadium', jaar: 2006, hiresNodig: true);
      expect(uit.first.name, 'Red Hot Chili Peppers - Stadium Arcadium (2006) [FLAC 24-96] WEB');
    });

    test('alleen cd-kwaliteit nodig (een mp3): ook een cd-FLAC, digitaal vóór vinyl', () {
      final uit = torrentsVoorHires(_stadium,
          artiest: 'Red Hot Chili Peppers', album: 'Stadium Arcadium', jaar: 2006, hiresNodig: false);
      expect(uit.take(2).map((r) => r.name), [
        'Red Hot Chili Peppers - Stadium Arcadium [2006][only1joe]FLAC-EA',
        'Red Hot Chili Peppers - Stadium Arcadium (2006) [FLAC]',
      ]);
      expect(uit, hasLength(7));
    });

    test('een andere plaat telt niet', () {
      expect(
          torrentsVoorHires(_stadium, artiest: 'Red Hot Chili Peppers', album: 'By the Way', jaar: 2002, hiresNodig: true),
          isEmpty);
    });
  });

  test('een vinylrip noemt zijn nummers naar de plaatkant: "A1 - One More Time.flac" is One More Time', () {
    // De echte namen bij TorBox (25-10-2026), uit "(House, Disco) [24/96] Daft Punk - Discovery - 2001, FLAC (tracks)".
    const map = 'Daft Punk - 2001 - Discovery [Virgin, 8496061 V2940, vinyl rip by Guardian]';
    bool past(String titel, String bestand) =>
        fileOffersTitle(titel, 320, 'Daft Punk', '$map/$bestand', null, album: 'Discovery');
    expect(past('One More Time', 'A1 - One More Time.flac'), isTrue);
    expect(past('Harder, Better, Faster, Stronger', 'B1 - Harder Better Faster Stronger.flac'), isTrue);
    expect(past('Face to Face', 'D2 - Face To Face.flac'), isTrue);
    expect(past('One More Time', 'A2 - Aerodynamic.flac'), isFalse);
    expect(past('Too Long', 'D3 - Too Long (Live).flac'), isFalse, reason: 'een ander merk blijft een andere opname');
    expect(fileOffersTitle('Voyager', 227, 'Daft Punk', 'x/Voyager B2.flac', null), isFalse,
        reason: 'alleen vooraan is het een plaatkant');
  });

  test('intussen al vervangen (Soulseek of TIDAL was sneller): niet nog eens uit de torrent halen', () {
    final map = Directory.systemTemp.createTempSync('dm_torrent_hires_');
    addTearDown(() => map.deleteSync(recursive: true));
    File flac(String naam, int bits, int hz) {
      final si = Uint8List(34);
      si[10] = (hz >> 12) & 0xFF;
      si[11] = (hz >> 4) & 0xFF;
      si[12] = ((hz & 0x0F) << 4) | (1 << 1) | (((bits - 1) >> 4) & 0x01);
      si[13] = ((bits - 1) & 0x0F) << 4;
      si[17] = 100;
      return File('${map.path}/$naam')..writeAsBytesSync([...'fLaC'.codeUnits, 0x80, 0x00, 0x00, 0x22, ...si]);
    }

    // [t] is de stand bij de start van de jacht: 16/44,1, tenzij anders gezegd.
    Track t(String pad, {int bits = 16, int hz = 44100}) => Track(
        path: pad, title: 'One More Time', artist: 'Daft Punk', album: 'Discovery', isFlac: true, bitsPerSample: bits, sampleRate: hz);
    expect(DownloadManager.intussenVervangen(t(flac('cd.flac', 16, 44100).path), TidalMinstens.hires), isFalse);
    expect(DownloadManager.intussenVervangen(t(flac('hoog.flac', 24, 96000).path), TidalMinstens.hires), isTrue);
    // Seal, "Stand by Me": 16 bit op 192 kHz bij de start, en nog steeds. Niet "intussen al beter".
    expect(DownloadManager.intussenVervangen(t(flac('raar.flac', 16, 192000).path, hz: 192000), TidalMinstens.hires), isFalse);
    expect(DownloadManager.intussenVervangen(t('${map.path}/weg.mp3'), TidalMinstens.cd), isTrue,
        reason: 'de mp3 is er niet meer: hij werd een FLAC');
    expect(DownloadManager.intussenVervangen(t(flac('cd2.flac', 16, 44100).path), TidalMinstens.cd), isFalse);
  });

  test('aangesloten: alleen bij "Zoek hi-res" op een plaat, niet na het landen', () {
    final online = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(online,
        contains("if (!alleenHires && (album?.trim() ?? '').isNotEmpty) unawaited(_zoekHiresInTorrents(te, album!.trim(), gezag));"));
    expect(online, contains('if (intussenVervangen(t, eis[t]!)) {'), reason: 'niet halen wat Soulseek al verving');
    final i = online.indexOf('Future<bool> _haalUitTorrentEnKeur(');
    expect(i, greaterThan(0));
    final lijf = online.substring(i, online.indexOf('\n  }\n', i));
    expect(lijf, contains("final uitslag = await _keurVoorWens(w, doel, bron, inJacht: false);"),
        reason: 'dezelfde keuring als Soulseek en TIDAL');
    expect(lijf, contains('if (!await _wachtTotNietMeerSpeelt(t.path)) {'), reason: 'niet vervangen terwijl het speelt');
  });
}
