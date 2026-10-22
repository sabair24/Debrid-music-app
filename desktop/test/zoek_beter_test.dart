// Een betere kopie zoeken voor nummers uit je bibliotheek (online.dart, `zoekBeterVoor`): de knop "Zoek
// hi-res" op een album, en een 👍 op een radionummer. Saber, 20-10-2026: "alleen als ik het vraag", en voor
// de radio "bij nummers die ik beslis om bij te houden".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/soulseek.dart';

void main() {
  // Een 16/44,1 FLAC van 3:51 van 30 MB; een 24/96 van dezelfde lengte ± 110 MB (de app schat de kwaliteit
  // uit de bitrate, zoals Soulseek die toont).
  final mijn = Track(
      path: r'D:\Muziek\Meskerem Mees\Caesar\08 - Joe.flac',
      title: 'Joe',
      artist: 'Meskerem Mees',
      album: 'Caesar',
      trackNo: 8,
      duration: const Duration(seconds: 231),
      isFlac: true,
      sizeBytes: 30000000,
      sampleRate: 44100,
      bitsPerSample: 16);

  SoulseekFile kopie(String peer, {required String naam, int sec = 231, bool hires = false}) => SoulseekFile(
      username: peer,
      filename: 'Muziek\\Meskerem Mees - Caesar (2023)${hires ? ' [24-96]' : ''}\\$naam',
      size: hires ? 110000000 : 30000000,
      freeSlots: true,
      speed: 2000000,
      durationSec: sec,
      sampleRate: hires ? 96000 : 44100,
      bitDepth: hires ? 24 : 16);

  test('je eigen bestand als maatstaf: grootte en lengte, anders niets te vergelijken', () {
    final e = DownloadManager.eigenAlsKandidaat(mijn)!;
    expect(e.size, 30000000);
    expect(e.durationSec, 231);
    expect(DownloadManager.eigenAlsKandidaat(Track(path: 'x.flac', title: 'a', artist: 'b', album: '')), isNull);
  });

  test('alleen wat dit nummer is én duidelijk beter dan wat er ligt — uit een albummap of los', () {
    final hits = [
      kopie('hires', naam: '08 - Joe.flac', hires: true),
      kopie('cd', naam: '08 - Joe.flac'),
      kopie('ander', naam: '07 - Best Friend.flac', hires: true),
      kopie('lang', naam: '08 - Joe.flac', hires: true, sec: 260),
    ];
    final beter = DownloadManager.beterDanWatErLigt(mijn, hits);
    expect(beter.map((k) => k.username), ['hires'],
        reason: 'een cd-kopie is niet beter, een ander nummer uit dezelfde map telt niet, en 29 s langer is een '
            'andere versie');
  });

  test('aangesloten: één zoekopdracht voor een album, de knop op de pc, en 👍 op de radio', () {
    final online = File('lib/online.dart').readAsStringSync();
    final z = online.substring(online.indexOf('  Future<int> zoekBeterVoor('));
    expect(z, contains('albumHits = await soulseek.search(zoekvraagVoorAlbum(te.first.artist, albumNaam), achtergrond: true);'));
    expect(z, contains('if (albumHits != null) {\n        hits = albumHits;'), reason: 'niet nog eens per nummer');
    expect(z, contains('!isVasteKeuze(t.path)'), reason: 'wat je zelf koos blijft de baas');
    expect(z, contains('_queueUpgrade(beter, job, speeltPad: t.path, parkeerAltijd: true, blijfZoeken: verdacht);'));
    final main = File('lib/main.dart').readAsStringSync();
    // Sinds 21-10-2026 op elk toestel behalve de tv; op gsm, iPad en Mac zoekt de pc ([zoekBeterOpPc]).
    expect(main, contains("if (!isTv)\n                            TextButton.icon(\n                              onPressed: () => unawaited(_zoekHires(context, album)),"));
    expect(main, contains("label: const Text('Zoek hi-res', style: TextStyle(fontSize: 12)),"));
    expect(main, contains('.zoekBeterVoor(album.tracks, album: album.title, gezag: lib.tagsVoorVervanger)'));
    expect(main, contains('final r = await zoekBeterOpPc(lib, album.tracks, album: album.title);'));
    expect(main, contains("await c.ask('/api/soulseek/zoek-beter', {'trackIds': ids, if (album != null) 'album': album});"));
    expect(RegExp(r'opTik: \(\) => unawaited\(_duimOmhoogRadio\(context, (t|track)\)\),').allMatches(main).length, 2,
        reason: 'beide radioduimen');
    expect(main, contains('if (nu != Oordeel.omhoog) return;'), reason: 'uitzetten zoekt niets');
    expect(main, contains('unawaited(zoekBeterOpPc(lib, [t]));'), reason: '👍 op een toestel: de pc zoekt');
    final server = File('lib/lan/server.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(server, contains("case '/api/soulseek/zoek-beter':\n        return _soulseekZoekBeter(req);"));
    expect(server, contains('.zoekBeterVoor(nummers, album: album, gezag: library.tagsVoorVervanger)'));
    expect(main, isNot(contains('opTik: () => unawaited(oordelen.wissel(track, Oordeel.omhoog)),')));
  });
}
