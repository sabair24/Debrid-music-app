/// De MP3-schrijver op KOPIEËN van elke echte mp3 in de bibliotheek.
///
/// Dit is de test waar het om draait. De app weigerde jarenlang mp3-tags te schrijven, en terecht:
/// de pakketten die er zijn herbouwen de tag en gooien daarmee weg wat ze niet modelleren. In deze
/// tien bestanden zit APIC (vijf hoezen), Serato-cuepunten, ReplayGain, iTunes' gapless-data, UFID en
/// PRIV. Als één daarvan sneuvelt is de schrijver niet goed genoeg.
///
/// Slaat zichzelf over als de bibliotheek er niet is, dus hij mag in de gewone run mee.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/mp3_tags.dart';

/// Alles wat na de tag komt: de audio zelf. Die mag geen byte veranderen.
Uint8List _audioNa(File f) {
  final h = readId3Header(f);
  final raf = f.openSync();
  try {
    final start = h == null ? 0 : 10 + h.size;
    raf.setPositionSync(start);
    return raf.readSync(raf.lengthSync() - start);
  } finally {
    raf.closeSync();
  }
}

/// De ruwe inhoud van elk frame dat wij NIET aanraken, per id, zodat we byte voor byte kunnen
/// vergelijken. Bewust op de ruwe bytes en niet op een uitgelezen waarde.
Map<String, List<int>> _vreemdeFrames(File f) {
  final h = readId3Header(f);
  if (h == null) return {};
  final raf = f.openSync();
  Uint8List body;
  try {
    raf.setPositionSync(10);
    body = raf.readSync(h.size);
  } finally {
    raf.closeSync();
  }
  final ons = {'TIT2', 'TPE1', 'TALB', 'TPE2', 'TRCK', 'TYER', 'TDRC'};
  final out = <String, List<int>>{};
  var i = 0;
  var n = 0;
  while (i + 10 <= body.length) {
    if (body[i] == 0) break;
    final id = String.fromCharCodes(body.sublist(i, i + 4));
    if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) break;
    final size = h.major == 4
        ? ((body[i + 4] & 0x7F) << 21) |
            ((body[i + 5] & 0x7F) << 14) |
            ((body[i + 6] & 0x7F) << 7) |
            (body[i + 7] & 0x7F)
        : (body[i + 4] << 24) | (body[i + 5] << 16) | (body[i + 6] << 8) | body[i + 7];
    if (size < 0 || i + 10 + size > body.length) break;
    if (!ons.contains(id)) out['$id#${n++}'] = body.sublist(i, i + 10 + size);
    i += 10 + size;
  }
  return out;
}

void main() {
  test('elke echte mp3 overleeft een schrijfactie met alles erop en eraan', () {
    final root = Directory(r'D:\Flac music 2024');
    if (!root.existsSync()) {
      markTestSkipped('bibliotheek niet aanwezig');
      return;
    }
    final mp3s = root
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.mp3'))
        .toList();
    expect(mp3s, isNotEmpty, reason: 'er horen mp3s in deze bibliotheek te staan');

    final dir = Directory.systemTemp.createTempSync('mp3w');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    var geschreven = 0, geweigerd = 0;
    for (var i = 0; i < mp3s.length; i++) {
      final kopie = mp3s[i].copySync('${dir.path}${Platform.pathSeparator}$i.mp3');
      final audioVoor = _audioNa(kopie);
      final vreemdVoor = _vreemdeFrames(kopie);

      final redenen = <String>[];
      final ok = writeMp3Fields(kopie, {
        'ARTIST': 'Petra',
        'TITLE': 'Jij bent zo mooi',
      }, trace: redenen.add);

      final naam = mp3s[i].path.split(Platform.pathSeparator).last;
      if (!ok) {
        geweigerd++;
        // Een weigering hoort een reden te hebben die we kennen -- en het bestand ongemoeid te laten.
        expect(redenen, isNotEmpty, reason: '$naam: een weigering hoort een reden te geven');
        print('   geweigerd: $naam -- ${redenen.join("; ")}');
        expect(_audioNa(kopie), audioVoor, reason: '$naam: geweigerd, dus niets veranderd');
        continue;
      }
      geschreven++;

      final na = readMp3RawFields(kopie);
      expect(na['artist'], 'Petra', reason: naam);
      expect(na['title'], 'Jij bent zo mooi', reason: naam);

      // De audio, byte voor byte.
      expect(_audioNa(kopie), audioVoor, reason: '$naam: de audio mag niet veranderen');

      // En alles wat niet van ons is: hoes, Serato, ReplayGain, gapless, UFID, PRIV.
      final vreemdNa = _vreemdeFrames(kopie);
      expect(vreemdNa.keys.toSet(), vreemdVoor.keys.toSet(),
          reason: '$naam: er is een vreemd frame verdwenen of bijgekomen');
      for (final k in vreemdVoor.keys) {
        expect(vreemdNa[k], vreemdVoor[k], reason: '$naam: $k is niet byte-identiek gebleven');
      }
    }
    print('geschreven: $geschreven, geweigerd: $geweigerd van ${mp3s.length}');
    expect(geschreven, greaterThan(0), reason: 'als alles geweigerd wordt is er niets bewezen');
  });
}
