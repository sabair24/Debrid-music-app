/// Herkennen waar het naar KLINKT, niet waar het naar heet.
///
/// De vergelijking zelf is pure rekenkunde en dus exact te testen: geen bestanden, geen processen,
/// geen netwerk. Dat is met opzet zo gebouwd, want dit getal beslist straks of een bestand als
/// dubbel wordt aangeboden om weg te doen.
library;

import 'package:debridmusic/fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een reeks die zich als audio gedraagt: geen patroon dat toevallig overal op lijkt.
List<int> reeks(int n, {int zaad = 1}) {
  final out = <int>[];
  var x = zaad;
  for (var i = 0; i < n; i++) {
    // Xorshift: goedkoop, herhaalbaar, en geen enkele regelmaat die de bittelling zou vertekenen.
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    out.add(x & 0xFFFFFFFF);
  }
  return out;
}

/// Zet in elk woord [perWoord] bits om, zoals een andere codering van dezelfde opname doet.
List<int> metRuis(List<int> src, int perWoord) => [
      for (var i = 0; i < src.length; i++)
        src[i] ^ ((1 << (i % 32)) | (perWoord > 1 ? 1 << ((i * 7) % 32) : 0)),
    ];

void main() {
  group('gelijkenis', () {
    test('identiek is 1', () {
      final a = reeks(300);
      expect(similarity(a, a), 1.0);
    });

    test('twee vreemde opnames landen rond de helft, ver onder de drempel', () {
      // Dit is waarom de drempel hoog staat en niet op 0,5: ongelijke audio scoort al ~0,5, omdat
      // twee willekeurige woorden in ongeveer de helft van hun 32 bits verschillen. Op de echte
      // bibliotheek gemeten over 10231 paren: 0,490 tot 0,571.
      final s = similarity(reeks(400, zaad: 1), reeks(400, zaad: 99));
      expect(s, greaterThan(0.4));
      expect(s, lessThan(0.62));
      expect(s, lessThan(maybeSameRecording));
    });

    test('de twijfelband ligt tussen de duetversie en de echte dubbels', () {
      // Gemeten op de bibliotheek: Adele's "Easy On Me" tegen "Easy On Me (With Chris Stapleton)"
      // scoort 0,929 -- een ANDERE opname op dezelfde begeleiding. De echte dubbels begonnen pas bij
      // 0,951. Eén drempel zou die duetversie dus ter verwijdering hebben aangeboden.
      expect(maybeSameRecording, lessThan(0.929));
      expect(sameRecording, greaterThan(0.929));
      expect(sameRecording, lessThan(0.951), reason: 'de laagste echte dubbel moet er nog onder');
    });

    test('dezelfde opname, andere codering, blijft boven de drempel', () {
      final a = reeks(400);
      final s = similarity(a, metRuis(a, 1));
      expect(s, greaterThan(sameRecording),
          reason: 'een ander formaat van hetzelfde nummer hoort herkend te worden');
      expect(s, lessThan(1.0));
    });

    test('een verschoven opname wordt uitgelijnd', () {
      // Waar dit voor is: een herrip begint een fractie eerder of later. Zonder uitlijnen scoort
      // identieke audio dan als ruis, en precies dat maakte deze hele vergelijking waardeloos.
      final a = reeks(400);
      final verschoven = a.sublist(12); // twaalf frames later begonnen
      expect(similarity(a, verschoven), greaterThan(sameRecording));
      expect(similarity(a, verschoven, maxOffset: 0), lessThan(0.62),
          reason: 'zonder uitlijnen is hetzelfde nummer niet van ruis te onderscheiden');
    });

    test('te weinig overlap geeft geen antwoord in plaats van een toevalstreffer', () {
      // Een handvol frames van een nummer van vier minuten vindt vroeg of laat een toevallige
      // gelijkenis, en een toevalstreffer met score 1,0 is erger dan geen antwoord.
      final a = reeks(400);
      expect(similarity(a, a.sublist(0, 10)), 0.0);
    });

    test('leeg is geen gelijkenis', () {
      expect(similarity(const [], reeks(50)), 0.0);
      expect(similarity(reeks(50), const []), 0.0);
    });
  });

  group('gereedschap', () {
    test('zonder fpcalc gebeurt er niets, en niets stort in', () async {
      final fp = Fingerprinter(toolPath: r'C:\bestaat\niet\fpcalc.exe');
      expect(fp.available, isFalse);
      expect(await fp.of(r'C:\ook\niet.flac'), isNull);
    });
  });
}
