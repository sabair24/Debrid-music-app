// Twijfelgevallen (Saber, 25-10-2026: "ja doe maar zo"): een kopie die bewezen beter klinkt maar waarvan de vingerafdruk
// tussen 0,70 en 0,90 zit, wordt niet weggegooid en niet vanzelf vervangen, maar aangeboden bij het nummer.
import 'dart:io';

import 'package:debridmusic/fingerprint.dart' show maybeSameRecordingScore;
import 'package:debridmusic/twijfel.dart';
import 'package:flutter_test/flutter_test.dart';

Twijfelgeval _g(String pad, {String id = 'a1', int grootte = 31090120, double score = 0.858}) => Twijfelgeval(
      id: id,
      pad: pad,
      kandidaat: 'D:/Muziek/$twijfelMap/$id.flac',
      bron: 'torrent "(House, Disco) [24/96] Daft Punk - Discovery"',
      score: score,
      kwaliteit: 'FLAC 24/96',
      ms: 1,
      grootte: grootte,
      gezag: const {'title': 'Nightvision', 'artist': 'Daft Punk', 'album': 'Discovery', 'trackNo': 6},
    );

void main() {
  test('het oordeel op de gemeten scores', () {
    // Dezelfde plaat: Africa vinyl 0,932, twee cd-rips 0,948.
    expect(opnameOordeel(0.932), Opnameoordeel.zelfde);
    expect(opnameOordeel(maybeSameRecordingScore), Opnameoordeel.zelfde);
    // Dezelfde plaat onder de grens: Nightvision vinyl 0,858 en 0,719, MJ 24/192 0,867.
    expect(opnameOordeel(0.858), Opnameoordeel.twijfel);
    expect(opnameOordeel(0.867), Opnameoordeel.twijfel);
    expect(opnameOordeel(0.719), Opnameoordeel.twijfel);
    expect(opnameOordeel(kTwijfelVanaf), Opnameoordeel.twijfel);
    // Live tegen studio 0,571 en 0,535; een ander nummer 0,521.
    expect(opnameOordeel(0.571), Opnameoordeel.andere);
    expect(opnameOordeel(0.521), Opnameoordeel.andere);
    expect(opnameOordeel(null), Opnameoordeel.onbekend);
  });

  test('de lijst overleeft een herstart, met wat je weggooide', () async {
    final map = Directory.systemTemp.createTempSync('dm_twijfel_');
    addTearDown(() => map.deleteSync(recursive: true));
    final pad = '${map.path}/twijfel.json';
    final l = Twijfellijst(pad)
      ..zet(_g('D:/Muziek/Albums/Daft Punk/Discovery/06 - Nightvision.flac'))
      ..zet(_g('D:/Muziek/Albums/Michael Jackson/Got To Be There/03 - Girl.flac', id: 'b2', grootte: 171107289, score: 0.867));
    l.verwijder('D:/Muziek/Albums/Michael Jackson/Got To Be There/03 - Girl.flac', nee: true);
    await l.bewaar();

    final m = Twijfellijst(pad);
    await m.laad();
    expect(m.alle, hasLength(1));
    final g = m.van(r'd:\muziek\albums\daft punk\discovery\06 - nightvision.flac')!;
    expect(g.kwaliteit, 'FLAC 24/96');
    expect(g.ext, 'flac');
    expect(g.gezag?['title'], 'Nightvision');
    expect(m.metId('a1')?.pad, g.pad);
    expect(m.afgewezen('D:/Muziek/Albums/Michael Jackson/Got To Be There/03 - Girl.flac', 171107289), isTrue,
        reason: 'weggegooid: dezelfde kandidaat komt niet terug');
    expect(m.afgewezen('D:/Muziek/Albums/Michael Jackson/Got To Be There/03 - Girl.flac', 5), isFalse);
  });

  test('wat de albumpagina leest: op de pc uit de lijst, op een toestel uit de catalogus', () {
    final l = Twijfellijst('${Directory.systemTemp.path}/ongebruikt.json');
    const pad = 'D:/Muziek/Albums/Daft Punk/Discovery/06 - Nightvision.flac';
    final voor = twijfelUitgave.value;
    l.zet(_g(pad));
    expect(twijfelVoor(pad)?.kwaliteit, 'FLAC 24/96');
    expect(twijfelUitgave.value, greaterThan(voor), reason: 'de catalogus en de albumpagina luisteren hiernaar');
    l.verwijder(pad);
    expect(twijfelVoor(pad), isNull);

    const opToestel = 'http://pc.invalid/stream/abc.flac';
    zetTwijfelVanPc(opToestel, (id: 'x', bron: 'Soulseek a', score: 0.86, kwaliteit: 'FLAC 24/192', ext: 'flac'));
    expect(twijfelVoor(opToestel)?.id, 'x');
    zetTwijfelVanPc(opToestel, null);
    expect(twijfelVoor(opToestel), isNull);
  });
}
