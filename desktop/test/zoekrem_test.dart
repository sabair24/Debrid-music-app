// De zoekrem: hoogstens kZoekPerMinuut zoekopdrachten per minuut naar Soulseek. Gemeten op de pc (22-10-2026,
// 19:35:34): met 39 in een minuut sloot de server de verbinding, en een radio vanaf Lambda stond vijf minuten stil.
import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/soulseek.dart' show Zoekrem, kZoekPerMinuut, kZoekVoorJou, zoekWachttijd;

final _t0 = DateTime(2026, 10, 22, 19, 35);

void main() {
  group('zoekWachttijd', () {
    test('onder de grens: meteen', () {
      final eerder = [for (var i = 0; i < kZoekPerMinuut - 1; i++) _t0.add(Duration(seconds: i))];
      expect(zoekWachttijd(eerder, _t0.add(const Duration(seconds: 30))), Duration.zero);
    });

    test('op de grens: tot de oudste uit de minuut valt', () {
      final eerder = [for (var i = 0; i < kZoekPerMinuut; i++) _t0.add(Duration(seconds: i))];
      expect(zoekWachttijd(eerder, _t0.add(const Duration(seconds: 30))), const Duration(seconds: 30));
      expect(zoekWachttijd(eerder, _t0.add(const Duration(seconds: 60))), Duration.zero,
          reason: 'de eerste is dan een minuut oud');
    });

    test('wat ouder is dan een minuut telt niet', () {
      final eerder = [for (var i = 0; i < 50; i++) _t0.subtract(Duration(seconds: 61 + i))];
      expect(zoekWachttijd(eerder, _t0), Duration.zero);
    });
  });

  group('Zoekrem', () {
    test('de start van de Lambda-radio: 39 tegelijk worden er hoogstens 20 per minuut', () {
      fakeAsync((fa) {
        final rem = Zoekrem(klok: () => _t0.add(fa.elapsed));
        final verstuurd = <Duration>[];
        for (var i = 0; i < 39; i++) {
          unawaited(rem.neem().then((_) => verstuurd.add(fa.elapsed)));
        }
        fa.flushMicrotasks();
        expect(verstuurd, hasLength(kZoekPerMinuut), reason: 'de eerste twintig meteen');
        fa.elapse(const Duration(seconds: 59));
        expect(verstuurd, hasLength(kZoekPerMinuut), reason: 'de rest pas na een minuut');
        fa.elapse(const Duration(seconds: 2));
        expect(verstuurd, hasLength(39));
        // Nergens meer dan twintig in één minuut.
        for (final t in verstuurd) {
          expect(verstuurd.where((u) => u >= t && u - t < const Duration(minutes: 1)).length,
              lessThanOrEqualTo(kZoekPerMinuut));
        }
      });
    });

    test('de radio laat plaats voor wat je zelf zoekt', () {
      fakeAsync((fa) {
        final rem = Zoekrem(klok: () => _t0.add(fa.elapsed));
        var radio = 0, jij = 0;
        for (var i = 0; i < 30; i++) {
          unawaited(rem.neem(achtergrond: true).then((_) => radio++));
        }
        fa.flushMicrotasks();
        expect(radio, kZoekPerMinuut - kZoekVoorJou);
        for (var i = 0; i < kZoekVoorJou; i++) {
          unawaited(rem.neem().then((_) => jij++));
        }
        fa.flushMicrotasks();
        expect(jij, kZoekVoorJou, reason: 'je eigen zoekopdracht wacht niet achter de radio');
      });
    });
  });

  test('aangesloten: elke vraag wacht op de rem, en de radio en de verlanglijst zoeken als achtergrond', () {
    final s = File('lib/soulseek.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final zoek = s.substring(s.indexOf('  Future<List<SoulseekFile>> search(List<String> queries,'));
    final lus = zoek.substring(0, zoek.indexOf('await run.settle();'));
    expect(lus.indexOf('await zoekrem.neem(achtergrond: achtergrond);'),
        lessThan(lus.indexOf('_conn!.send(_message(26,')), reason: 'vóór elke FileSearch');
    final o = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(o, contains('achtergrond: _radiohalen.contains(job),'), reason: 'de radio; ▶ los van de radio niet');
    expect(o, contains('hits = await soulseek.search(w.query, achtergrond: true);'), reason: 'de verlanglijst');
    expect(o, contains('s.search(variants.toList(), onPartial: onPartial, achtergrond: achtergrond)'));
  });
}
