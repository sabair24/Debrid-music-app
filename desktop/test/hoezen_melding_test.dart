// "Covers ophalen…" onder het menu (Saber, 26-10-2026, op de Mac: "covers ophalen , gaat niet weg"). De verbindingen
// van de Mac met de pc stonden stil — er kwam niets meer binnen —, maar één vraag die nooit afrondde hield het aan.
import 'dart:async';

import 'package:debridmusic/library.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DE KERN: een vraag die nooit afrondt houdt het regeltje niet langer dan kHoezenMeldingStil aan', () {
    fakeAsync((fa) {
      final lib = LibraryStore();
      unawaited(lib.haaltHoesVoorToets(() => Completer<void>().future));
      expect(lib.hoezenOphalen.value, isTrue);
      fa.elapse(LibraryStore.kHoezenMeldingStil - const Duration(milliseconds: 100));
      expect(lib.hoezenOphalen.value, isTrue, reason: 'eventjes mag het');
      fa.elapse(const Duration(milliseconds: 200));
      expect(lib.hoezenOphalen.value, isFalse);
    });
  });

  test('hoezen die blijven binnenkomen houden het aan; daarna gaat het weg', () {
    fakeAsync((fa) {
      final lib = LibraryStore();
      for (var i = 0; i < 6; i++) {
        unawaited(lib.haaltHoesVoorToets(() => Future<void>.delayed(const Duration(seconds: 5))));
        fa.elapse(const Duration(seconds: 3));
        expect(lib.hoezenOphalen.value, isTrue, reason: 'er komt telkens iets binnen');
      }
      fa.elapse(const Duration(seconds: 10));
      expect(lib.hoezenOphalen.value, isFalse);
    });
  });
}
