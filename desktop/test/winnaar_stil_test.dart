// De winnaar van een wedloop die stilvalt, valt af (online.dart, `bewaakStilte`). Gemeten op de gsm
// (20-10-2026, 3.9.529, Hozier — Too Sweet): de winnaar stuurde na 3,6 s, de kop kwam nooit binnen, en alles
// wachtte 34 s op Soulseek; de ronde erna leverde in 2,9 s. 44 s van tik tot geluid.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/online.dart';
import 'package:debridmusic/soulseek.dart';

void main() {
  late Directory map;
  late File dest;
  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_winnaarstil_');
    dest = File('${map.path}${Platform.pathSeparator}in.flac');
  });
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('bytes, dan stilte: na de grens gestopt, met hoeveel er binnen was', () async {
    dest.writeAsBytesSync(List.filled(4096, 1));
    final stop = SlskCancel();
    int? binnen;
    final klok = Stopwatch()..start();
    final uit = await bewaakStilte(dest, 1 << 20, stop, () => false,
        stil: const Duration(milliseconds: 300),
        peil: const Duration(milliseconds: 20),
        gestopt: (b, _) => binnen = b);
    expect(uit, isTrue);
    expect(stop.isCancelled, isTrue);
    expect(binnen, 4096);
    expect(klok.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('een uploader die blijft leveren: nooit gestopt, ook niet als het langer duurt dan de grens', () async {
    final stop = SlskCancel();
    var klaar = false;
    final schrijver = Timer.periodic(const Duration(milliseconds: 50), (_) {
      dest.writeAsBytesSync(List.filled(1024, 1), mode: FileMode.append);
    });
    final uit = bewaakStilte(dest, 1 << 20, stop, () => klaar,
        stil: const Duration(milliseconds: 300), peil: const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 900));
    schrijver.cancel();
    klaar = true;
    expect(await uit, isFalse);
    expect(stop.isCancelled, isFalse);
  });

  test('compleet, of de overdracht is klaar, of al gestopt: geen ingreep', () async {
    dest.writeAsBytesSync(List.filled(2048, 1));
    final heel = SlskCancel();
    expect(
        await bewaakStilte(dest, 2048, heel, () => false,
            stil: const Duration(milliseconds: 100), peil: const Duration(milliseconds: 20)),
        isFalse,
        reason: 'het hele bestand staat er');
    expect(heel.isCancelled, isFalse);
    final klaar = SlskCancel();
    expect(await bewaakStilte(dest, 1 << 20, klaar, () => true, stil: Duration.zero), isFalse);
    expect(klaar.isCancelled, isFalse);
    final al = SlskCancel()..cancel();
    expect(await bewaakStilte(dest, 1 << 20, al, () => false, stil: Duration.zero), isFalse);
  });

  test('nog geen bestand en geen bytes: na de grens ook gestopt', () async {
    final stop = SlskCancel();
    expect(
        await bewaakStilte(dest, 1 << 20, stop, () => false,
            stil: const Duration(milliseconds: 200), peil: const Duration(milliseconds: 20)),
        isTrue);
  });

  group('te traag (Saber: "als het echt zo traag gaat, beter niet wachten en direct een andere proberen")', () {
    const mb = 1024 * 1024;
    test('⬇: 42 kB/s met nog 30 MB te gaan is te traag; snel, of bijna klaar, niet', () {
      // dweee bij Lola Young — Messy: 42 kB/s.
      expect(teTraag(binnen: 42 * 1024 * 10, totaal: 40 * mb, bezig: const Duration(seconds: 10)), isTrue);
      expect(teTraag(binnen: 2 * mb * 10, totaal: 40 * mb, bezig: const Duration(seconds: 10)), isFalse,
          reason: '2 MB/s');
      expect(teTraag(binnen: 39 * mb, totaal: 40 * mb, bezig: const Duration(seconds: 200)), isFalse,
          reason: 'traag, maar nog maar een paar seconden te gaan');
      expect(teTraag(binnen: 1024, totaal: 40 * mb, bezig: const Duration(seconds: 4)), isFalse,
          reason: 'de eerste vijf seconden zeggen nog niets');
    });

    test('▶: onder 1,2 keer het verbruik te traag, erboven niet', () {
      const verbruik = 200.0 * 1024; // een cd-FLAC
      expect(teTraag(binnen: (180 * 1024 * 6).round(), totaal: 50 * mb, bezig: const Duration(seconds: 6), verbruik: verbruik),
          isTrue, reason: 'trager dan het afspelen: dat hapert');
      expect(teTraag(binnen: 300 * 1024 * 6, totaal: 50 * mb, bezig: const Duration(seconds: 6), verbruik: verbruik),
          isFalse, reason: '1,5 keer het verbruik: speelt, met wat buffer');
    });

    test('de bewaker stopt een trage winnaar met de reden, ook al komt er nog wel iets binnen', () async {
      final stop = SlskCancel();
      String? waarom;
      final schrijver = Timer.periodic(const Duration(milliseconds: 50), (_) {
        dest.writeAsBytesSync(List.filled(512, 1), mode: FileMode.append);
      });
      final uit = await bewaakStilte(dest, 1 << 30, stop, () => false,
          stil: const Duration(seconds: 5),
          peil: const Duration(milliseconds: 20),
          traag: (binnen, bezig) => bezig >= const Duration(milliseconds: 300) && binnen < 1 << 20,
          gestopt: (_, w) => waarom = w);
      schrijver.cancel();
      expect(uit, isTrue);
      expect(stop.isCancelled, isTrue);
      expect(waarom, startsWith('te traag ('));
    });
  });

  test('aangesloten: ⬇ — een trage leider maakt plaats voor wie daarna begint te sturen', () {
    final online = File('lib/online.dart').readAsStringSync();
    final race = online.substring(online.indexOf('    Future<(SlskDone, SoulseekFile)?> race('));
    final claim = race.substring(race.indexOf('          claim: () {'), race.indexOf("c.cancel(); // someone else is already sending"));
    expect(claim, contains('if (teTraag(binnen: binnen, totaal: l.size, bezig: bezig)) {'));
    expect(claim, contains('leaderStop?.cancel();'));
    expect(claim, contains('leader = f;'));
    expect(claim.indexOf('leaderSinds = DateTime.now();'), greaterThan(0));
  });

  test('aangesloten: de winnaar van de wedloop wordt bewaakt, en wie stilviel doet niet meer mee', () {
    expect(kWinnaarStil, const Duration(seconds: 6));
    final online = File('lib/online.dart').readAsStringSync();
    final w = online.substring(online.indexOf('  Future<({SoulseekFile f, SlskResult res, bool afgekeurd})?> _wedloop('));
    final staart = w.substring(w.indexOf('    var overdrachtKlaar = false;'), w.indexOf('  /// Kijkt mee terwijl één kandidaat'));
    expect(staart, contains('final stilgevallen = bewaakStilte(_bestemming(w), w.size, lopers[w]!.stop, () => overdrachtKlaar,'));
    expect(staart, contains('viel?.call(w.username);'));
    expect(staart, contains('traag: verbruik == null || lopend < 2'),
        reason: 'te traag alleen als er anderen meededen: de enige is liever traag dan niets');
    expect(staart.indexOf('await stilgevallen;'), greaterThan(staart.indexOf('overdrachtKlaar = true;')),
        reason: 'pas na het einde van de overdracht wachten, anders wacht de bewaker op zichzelf');
  });
}
