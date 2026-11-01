/// Tegen een ECHTE Cast-speaker, alleen met de hand: `CAST_ECHT=192.168.0.253 CAST_URL=<adres> flutter test test/google_cast_echt_test.dart`.
/// Zonder die omgeving slaat hij zichzelf over (de bouwstraat heeft geen Nest). Het volume blijft wat het was.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/google_cast.dart';

void main() {
  final host = Platform.environment['CAST_ECHT'];
  final url = Platform.environment['CAST_URL'];
  final overslaan = host == null || url == null ? 'alleen met CAST_ECHT en CAST_URL' : null;

  test('vinden: de Nest Minis via mDNS', () async {
    final r = await zoekCasts(wacht: const Duration(seconds: 3));
    // ignore: avoid_print
    print('gevonden: ${[for (final x in r) '${x.name} ${x.host}:${castAdres(x).poort} ${x.model}']}');
    expect(r.any((x) => x.host == host), isTrue);
  }, skip: overslaan, timeout: const Timeout(Duration(seconds: 20)));

  test('spelen, plek, pauze, verder, spoelen, stoppen', () async {
    final cast = CastBediening(log: (s) => print(s)); // ignore: avoid_print
    final r = castRenderer(id: 'echt', host: host!, poort: 8009, naam: 'echt');
    final volume = await cast.getVolume(r);
    final klok = Stopwatch()..start();
    await cast.playUrl(r, url!, title: 'proef', artist: 'Debrid Music', album: 'proef', mime: 'audio/flac');
    // ignore: avoid_print
    print('volume $volume, geladen in ${klok.elapsedMilliseconds} ms');
    var stand = '';
    for (var i = 0; i < 20 && stand != 'PLAYING'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      stand = (await cast.transportState(r))!.state;
    }
    final p1 = await cast.positionInfo(r);
    await Future<void>.delayed(const Duration(seconds: 2));
    final p2 = await cast.positionInfo(r);
    // ignore: avoid_print
    print('stand $stand na ${klok.elapsedMilliseconds} ms; plek ${p1?.position} → ${p2?.position}, duur ${p2?.duration}');
    expect(stand, 'PLAYING');
    expect(p2!.position! - p1!.position!, greaterThan(const Duration(milliseconds: 1500)));
    expect(p2.trackUri, url);
    await cast.pause(r);
    expect((await cast.transportState(r))!.state, 'PAUSED_PLAYBACK');
    await cast.seek(r, const Duration(seconds: 30));
    final p3 = await cast.positionInfo(r);
    // ignore: avoid_print
    print('na spoelen: ${p3?.position}');
    expect(p3!.position!.inSeconds, inInclusiveRange(29, 31));
    await cast.play(r);
    await cast.stop(r);
    await cast.kanaal(r).stopSpeler();
    if (volume != null) await cast.setVolume(r, volume);
    expect(await cast.getVolume(r), volume);
    cast.sluit();
  }, skip: overslaan, timeout: const Timeout(Duration(seconds: 60)));
}
