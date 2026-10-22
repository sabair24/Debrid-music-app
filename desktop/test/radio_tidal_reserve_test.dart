// TIDAL als reserve voor de radio en ▶: alleen als Soulseek niet meedoet of het nummer niet heeft, hoogstens
// kTidalRadioPerUur per uur, en met dezelfde keuringen als een kopie van Soulseek. Saber, 22-10-2026: "oei radio stopt
// al" (Soulseek sloot ons om 19:35 buiten) en "Tidal is wel enkel als back-up e, soulseek blijft prio".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/soulseek.dart' show zoekWachttijd;
import 'package:debridmusic/tidaler.dart' show Tidaler, kTidalRadioPerUur;

String _lijf(String bron, String kop) {
  final i = bron.indexOf(kop);
  expect(i, greaterThanOrEqualTo(0), reason: kop);
  return bron.substring(i, bron.indexOf('\n  }\n', i));
}

void main() {
  final online = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');

  test('hoogstens vijftien per uur: zoveel als je hoort', () {
    expect(kTidalRadioPerUur, 15);
    final t0 = DateTime(2026, 10, 22, 19, 37);
    final al = [for (var i = 0; i < kTidalRadioPerUur; i++) t0.add(Duration(minutes: i))];
    const uur = Duration(hours: 1);
    expect(zoekWachttijd(al, t0.add(const Duration(minutes: 20)), max: kTidalRadioPerUur, venster: uur),
        const Duration(minutes: 40), reason: 'tot de eerste een uur oud is');
    expect(zoekWachttijd(al.sublist(1), t0.add(const Duration(minutes: 20)), max: kTidalRadioPerUur, venster: uur),
        Duration.zero);
  });

  test('in een toets nooit echt naar TIDAL', () {
    expect(Tidaler.inToets, isTrue, reason: 'flutter test zet FLUTTER_TEST; op Sabers pc staat tidaler echt');
  });

  test('DE KERN: Soulseek eerst; TIDAL bij een storing of als Soulseek het nummer niet heeft', () {
    final haal = _lijf(online, '  Future<String?> haalEnLaatHoren({');
    final soulseek = haal.indexOf('await _haalVoorRadio(job, artiest, titel, seconden, jaar,');
    final nietOpSoulseek = haal.indexOf("waarom: 'niet op Soulseek'");
    expect(soulseek, greaterThan(0));
    expect(nietOpSoulseek, greaterThan(soulseek));
    expect(haal, contains('if (!_radioZonderKandidaat.contains(_radioSleutel(artiest, titel))) return null;'),
        reason: 'alle uploaders faalden is niet "niet op Soulseek": dan gewoon de volgende plek');
    final storing = haal.substring(haal.indexOf('} on RadioLaterOpnieuw catch (e) {'));
    expect(storing, contains('await _radioViaTidal(job, artiest, titel, seconden, jaar, album: album, waarom: e.waarom);'));
    expect(storing.indexOf('rethrow;'), greaterThan(storing.indexOf('_radioViaTidal(')),
        reason: 'lukt TIDAL niet, dan blijft het "later opnieuw" zoals vroeger');
  });

  test('wat van TIDAL komt, gaat door dezelfde keuringen als een radiokopie van Soulseek', () {
    final t = _lijf(online, '  Future<String?> _radioViaTidal(');
    expect(t, contains('if (job.cancelled || Tidaler.inToets || !Tidaler.beschikbaar || Tidaler.python == null) return null;'));
    expect(t, contains('zoekWachttijd(_tidalRadioTijden, nu, max: kTidalRadioPerUur, venster: const Duration(hours: 1));'));
    for (final stap in [
      'kiesTidalTreffers(treffers, artiest: artiest, titel: titel)',
      'radioTagsSprekenTegen(artiest, titel, tags)',
      'radioLengteSpreektTegen(seconden, echt)',
      'parkeerAltijd: true, parkeerBinnenkomend: false',
      'throw RadioAlGehad(uit.path);',
      '_geefKeuringsmapVrij(map);',
    ]) {
      expect(t, contains(stap));
    }
    // Dezelfde keuringen staan in de Soulseek-weg: als die verandert, hoort deze mee te veranderen.
    final s = _lijf(online, '  Future<String?> _haalVoorRadio(');
    expect(s, contains('radioTagsSprekenTegen(artiest, titel, t)'));
    expect(s, contains('radioLengteSpreektTegen(seconden, echt)'));
  });
}
