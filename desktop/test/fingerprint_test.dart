/// Herkennen waar het naar KLINKT, niet waar het naar heet.
///
/// De vergelijking zelf is pure rekenkunde en dus exact te testen: geen bestanden, geen processen,
/// geen netwerk. Dat is met opzet zo gebouwd, want dit getal beslist straks of een bestand als
/// dubbel wordt aangeboden om weg te doen.
library;

import 'dart:io';

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
      expect(s, lessThan(maybeSameRecordingScore));
    });

    test('de twijfelband ligt tussen de duetversie en de echte dubbels', () {
      // Gemeten op de bibliotheek: Adele's "Easy On Me" tegen "Easy On Me (With Chris Stapleton)"
      // scoort 0,929 -- een ANDERE opname op dezelfde begeleiding. De echte dubbels begonnen pas bij
      // 0,951. Eén drempel zou die duetversie dus ter verwijdering hebben aangeboden.
      expect(maybeSameRecordingScore, lessThan(0.929));
      expect(sameRecordingScore, greaterThan(0.929));
      expect(sameRecordingScore, lessThan(0.951), reason: 'de laagste echte dubbel moet er nog onder');
    });

    test('dezelfde opname, andere codering, blijft boven de drempel', () {
      final a = reeks(400);
      final s = similarity(a, metRuis(a, 1));
      expect(s, greaterThan(sameRecordingScore),
          reason: 'een ander formaat van hetzelfde nummer hoort herkend te worden');
      expect(s, lessThan(1.0));
    });

    test('een verschoven opname wordt uitgelijnd', () {
      // Waar dit voor is: een herrip begint een fractie eerder of later. Zonder uitlijnen scoort
      // identieke audio dan als ruis, en precies dat maakte deze hele vergelijking waardeloos.
      final a = reeks(400);
      final verschoven = a.sublist(12); // twaalf frames later begonnen
      expect(similarity(a, verschoven), greaterThan(sameRecordingScore));
      expect(similarity(a, verschoven, maxOffset: 0), lessThan(0.62),
          reason: 'zonder uitlijnen is hetzelfde nummer niet van ruis te onderscheiden');
    });

    test('te weinig overlap geeft geen antwoord in plaats van een toevalstreffer', () {
      // Een handvol frames van een nummer van vier minuten vindt vroeg of laat een toevallige
      // gelijkenis, en een toevalstreffer met score 1,0 is erger dan geen antwoord.
      final a = reeks(400);
      expect(similarity(a, a.sublist(0, 10)), 0.0);
    });

    test('lijsten van verschillende lengte lopen niet van de rand', () {
      // De fout die de bibliotheekbrede ronde eruit gooide: de twee helften van het uitlijnen waren
      // geen spiegelbeeld, dus een positieve verschuiving las a[i+offset] terwijl de overlap voor b
      // was uitgerekend. Met bijna gelijke lengtes viel dat niet op; over de hele bibliotheek, waar
      // alles van 1 tot 20 minuten langs elkaar komt, viel het er meteen uit.
      final kort = reeks(60);
      final lang = reeks(900, zaad: 5);
      expect(() => similarity(kort, lang), returnsNormally);
      expect(() => similarity(lang, kort), returnsNormally);
      // En de uitkomst hoort dezelfde te zijn, welke kant je hem ook invoert.
      final a = reeks(400);
      final b = [...a.sublist(20), ...reeks(20, zaad: 9)];
      expect(similarity(a, b), closeTo(similarity(b, a), 1e-9));
    });

    test('leeg is geen gelijkenis', () {
      expect(similarity(const [], reeks(50)), 0.0);
      expect(similarity(reeks(50), const []), 0.0);
    });
  });

  group('gereedschap', () {
    setUp(Fingerprinter.resetLookup);
    tearDown(Fingerprinter.resetLookup);

    test('zonder fpcalc gebeurt er niets, en niets stort in', () async {
      final fp = Fingerprinter(toolPath: r'C:\bestaat\niet\fpcalc.exe');
      expect(fp.available, isFalse);
      expect(await fp.of(r'C:\ook\niet.flac'), isNull);
    });

    test('een opgegeven pad dat WEL bestaat wordt aangenomen', () {
      // De enige tak die zonder een echte fpcalc te toetsen is: het kalibratiescript geeft er een
      // mee, en dan hoort er niet gezocht te worden.
      final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}dm_fpcalc_toets');
      f.writeAsStringSync('geen echte fpcalc, maar hij bestaat');
      addTearDown(() => f.deleteSync());
      expect(Fingerprinter(toolPath: f.path).tool, f.path);
    });

    test('niet gevonden zegt WAAR er gekeken is', () {
      // **Waarom dit een toets waard is.** De uitleg bij `tool` beloofde dat PATH nagekeken werd, en
      // dat deed hij niet -- er stonden precies twee kandidaten, allebei naast de app. Wie fpcalc via
      // Homebrew had (op een Mac de gewone weg) kreeg "fpcalc ontbreekt" terwijl het programma
      // gewoon geïnstalleerd was, en het scherm zei niet waar er gezocht was.
      //
      // Deze toets doet geen uitspraak over of fpcalc gevonden WORDT -- op de bouwmachine kan hij er
      // staan of niet. Hij legt vast dat er bij een misser iets te lezen valt.
      Fingerprinter().tool;
      final fout = Fingerprinter.laatsteFout;
      if (fout == null) return; // fpcalc staat op deze machine; dan is er niets te melden
      expect(fout, contains('fpcalc'));
      expect(fout, contains('geprobeerd'));
      if (!Platform.isWindows) {
        expect(fout, contains('/opt/homebrew/bin/fpcalc'),
            reason: 'de plek waar Homebrew hem neerzet hoort erbij te staan');
      }
    });

    test('de kandidatenlijst begint naast de app en eindigt op PATH', () {
      // De volgorde IS de afspraak: wat de bouwstraat meelevert gaat vóór wat er toevallig op de
      // machine staat, want alleen van de eerste weten we welke versie het is -- en een andere
      // versie kan een ander vingerafdrukalgoritme hebben.
      final lijst = Fingerprinter.kandidaten();
      final naam = Platform.isWindows ? 'fpcalc.exe' : 'fpcalc';
      expect(lijst.first, startsWith(File(Platform.resolvedExecutable).parent.path));
      expect(lijst.last, naam, reason: 'een kale naam is de PATH-kandidaat');
      expect(lijst.toSet(), hasLength(lijst.length), reason: 'geen dubbele kandidaten');
    });
  });
}
