/// Een bestand zonder tags houdt zijn speelduur.
///
/// **De klacht, op 31-08-2026, met twee schermafdrukken.** Twee tegels met "Single · Onbekende
/// artiest · 1 nummers", een titel die de bestandsnaam ís ("05 - Restless", "03 Showdown"), en
/// achteraan `FLAC 0:00`. *"En wat zijn al die nummers met 0:00 min??? denk van torrents?? maar wat
/// is het?"*
///
/// **Wat het zijn.** Bestanden waar de tagontleder niets uit kreeg. Sinds de France Gall-ronde
/// verdwijnen die niet meer stilletjes — ze komen de bibliotheek in onder hun bestandsnaam, want
/// muziek die je hebt en niet kunt vinden is erger dan een lelijke regel. Dat deel klopt.
///
/// **Wat er fout was.** Ook de SPEELDUUR werd weggegooid, en die is helemaal geen tag. Bij een FLAC
/// staat hij in het STREAMINFO-blok: het blok dat de decoder nodig heeft om het geluid te kunnen
/// afspelen. Bemonstering en bitdiepte staan daar naast. Die drie zijn er dus altijd, ook in een rip
/// waar verder geen letter in geschreven is — en `readFlacTags` las ze al netjes uit. Ze werden
/// alleen niet bewaard zodra er geen naam bij stond.
///
/// **Waarom dat meer is dan lelijk.** `fileOfRecording` gebruikt de duur om twee nummers met dezelfde
/// naam uit elkaar te houden, en `firstIsBetter` om te kiezen welke versie de betere is. Nul is daar
/// niet "onbekend" maar "nul", en dat stuurt allebei die beslissingen de verkeerde kant op.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/library.dart';
import 'package:flutter_test/flutter_test.dart';

/// Het STREAMINFO-blok, 34 bytes, zoals de FLAC-norm het pakt.
///
/// Alleen de bytes 10 t/m 17 doen ertoe: 20 bits bemonstering, 3 bits (kanalen − 1), 5 bits
/// (bitdiepte − 1) en 36 bits totaal aantal monsters, alles achter elkaar door de bytegrenzen heen.
/// De blokgroottes ervoor blijven nul — daar kijkt niemand hier naar.
List<int> streaminfo({
  required int sampleRate,
  required int channels,
  required int bits,
  required int totalSamples,
}) {
  final d = List<int>.filled(34, 0);
  d[10] = (sampleRate >> 12) & 0xFF;
  d[11] = (sampleRate >> 4) & 0xFF;
  d[12] = ((sampleRate & 0x0F) << 4) | (((channels - 1) & 0x07) << 1) | (((bits - 1) >> 4) & 0x01);
  d[13] = (((bits - 1) & 0x0F) << 4) | ((totalSamples >> 32) & 0x0F);
  d[14] = (totalSamples >> 24) & 0xFF;
  d[15] = (totalSamples >> 16) & 0xFF;
  d[16] = (totalSamples >> 8) & 0xFF;
  d[17] = totalSamples & 0xFF;
  return d;
}

/// Een Vorbis-commentaarblok met precies deze regels erin.
List<int> vorbis(List<String> regels) {
  final uit = <int>[];
  void u32(int v) => uit.addAll([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  const vendor = 'toets';
  u32(vendor.length);
  uit.addAll(vendor.codeUnits);
  u32(regels.length);
  for (final r in regels) {
    final b = r.codeUnits;
    u32(b.length);
    uit.addAll(b);
  }
  return uit;
}

/// Een blokkop: type, lengte, en of dit het laatste blok is.
List<int> kop(int type, int len, {required bool laatste}) =>
    [(laatste ? 0x80 : 0) | type, (len >> 16) & 0xFF, (len >> 8) & 0xFF, len & 0xFF];

void main() {
  late Directory map;

  setUp(() => map = Directory.systemTemp.createTempSync('kaleflac'));
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Schrijft een bestand en geeft de tagrij terug die de scan eruit zou halen.
  Map<String, dynamic>? rij(String naam, List<int> bytes) {
    final f = File('${map.path}${Platform.pathSeparator}$naam')
      ..writeAsBytesSync(Uint8List.fromList(bytes));
    return tagrijVoorBestand(f, addedMs: 1, sizeBytes: bytes.length);
  }

  /// Een FLAC met de gegeven commentaarregels; geen enkele regel = helemaal geen commentaarblok.
  List<int> flac({
    List<String> regels = const [],
    int sampleRate = 44100,
    int bits = 16,
    int totalSamples = 9393300, // 213 seconden bij 44,1 kHz
  }) {
    final si = streaminfo(
        sampleRate: sampleRate, channels: 2, bits: bits, totalSamples: totalSamples);
    final uit = <int>[...'fLaC'.codeUnits];
    if (regels.isEmpty) {
      uit.addAll(kop(0, si.length, laatste: true));
      uit.addAll(si);
    } else {
      uit.addAll(kop(0, si.length, laatste: false));
      uit.addAll(si);
      final vc = vorbis(regels);
      uit.addAll(kop(4, vc.length, laatste: true));
      uit.addAll(vc);
    }
    return uit;
  }

  group('een FLAC zonder één naam erin', () {
    test('komt de bibliotheek in onder zijn bestandsnaam', () {
      final r = rij('05 - Restless.flac', flac());
      expect(r, isNotNull, reason: 'wegdoen is hoe muziek "verdwijnt"');
      expect(r!['title'], '05 - Restless');
      expect(r['artist'], 'Onbekende artiest');
      expect(r['album'], '', reason: 'een albumnaam raden zet hem bij vreemde buren');
    });

    test('maar houdt zijn speelduur', () {
      // Dit is de gemelde fout: 0:00 achter een nummer van drie en een halve minuut.
      expect(rij('05 - Restless.flac', flac())!['durationMs'], 213000);
    });

    test('en zijn bemonstering en bitdiepte', () {
      final r = rij('los.flac', flac(sampleRate: 96000, bits: 24, totalSamples: 192000))!;
      expect(r['sampleRate'], 96000);
      expect(r['bitsPerSample'], 24);
      expect(r['durationMs'], 2000);
    });

    test('ook als er wél een commentaarblok is, maar zonder naam erin', () {
      // Het geval dat je van een ripper krijgt: alles gewist behalve wat de codeersoftware
      // achterliet. Er is een blok, het is leeg aan alles waar wij naar kijken.
      final r = rij('03 Showdown.flac', flac(regels: ['ENCODER=flac 1.4.3']))!;
      expect(r['title'], '03 Showdown');
      expect(r['durationMs'], 213000);
    });
  });

  group('wat er niet verandert', () {
    test('een FLAC mét tags leest zoals hij altijd las', () {
      final r = rij(
          '01 - iets.flac',
          flac(regels: [
            'TITLE=Showdown',
            'ARTIST=The Isley Brothers',
            'ALBUM=Showdown',
            'TRACKNUMBER=3',
          ]))!;
      expect(r['title'], 'Showdown');
      expect(r['artist'], 'The Isley Brothers');
      expect(r['album'], 'Showdown');
      expect(r['trackNo'], 3);
      expect(r['durationMs'], 213000, reason: 'de duur kwam altijd al uit STREAMINFO');
    });

    test('een bestand dat helemaal geen FLAC is blijft op 0:00 staan', () {
      // Eerlijk over de grens van deze reparatie: zonder kop is er niets te lezen, en een duur
      // verzinnen is erger dan hem niet weten. Het bestand verdwijnt wél niet.
      final r = rij('kapot.flac', 'dit is geen muziek maar staat wel in je map'.codeUnits);
      expect(r, isNotNull);
      expect(r!['durationMs'], 0);
      expect(r['sampleRate'], 0);
    });
  });

  group('een SACD-rip', () {
    /// Een DSF: de DSD-brok van 28 bytes, dan de fmt-brok van 52, dan een lege data-brok.
    List<int> dsf({
      int sampleRate = 2822400, // DSD64
      int channels = 2,
      int bits = 1,
      required int sampleCount,
      String magie = 'DSD ',
    }) {
      final uit = <int>[];
      void u32(int v) => uit.addAll([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
      void u64(int v) {
        u32(v & 0xFFFFFFFF);
        u32(v ~/ 0x100000000);
      }

      uit.addAll(magie.codeUnits);
      u64(28); // grootte van deze brok
      u64(80); // totale bestandsgrootte
      u64(0); // geen metadata-blok
      uit.addAll('fmt '.codeUnits);
      u64(52);
      u32(1); // versie
      u32(0); // format id: DSD raw
      u32(channels == 2 ? 2 : 7); // channel type
      u32(channels);
      u32(sampleRate);
      u32(bits);
      u64(sampleCount);
      u32(4096); // block size per kanaal
      u32(0); // gereserveerd
      return uit;
    }

    test('krijgt zijn speelduur uit de kop', () {
      // Drie minuten DSD64. Geen enkele tagontleder in deze app kent DSD, dus zonder dit stond hier
      // 0:00 — en tot vandaag stond de plaat er niet eens.
      final r = rij('01 - Take Five.dsf', dsf(sampleCount: 2822400 * 180))!;
      expect(r['durationMs'], 180000);
      expect(r['sampleRate'], 2822400);
      expect(r['bitsPerSample'], 1);
      expect(r['title'], '01 - Take Five', reason: 'de naam komt nog uit de bestandsnaam');
    });

    test('ook als hij langer duurt dan vier miljard monsters', () {
      // Het aantal monsters is een getal van acht bytes en loopt bij DSD ver over de vier miljard
      // heen: twee uur is er al twintig miljard. Alleen de onderste vier bytes lezen zou hier een
      // duur van elf minuten opleveren.
      expect(rij('lang.dsf', dsf(sampleCount: 2822400 * 7200))!['durationMs'], 7200000);
    });

    test('een kop die niet klopt levert geen verzonnen duur op', () {
      final r = rij('nep.dsf', dsf(sampleCount: 100, magie: 'XXXX'));
      expect(r, isNotNull, reason: 'het bestand verdwijnt niet');
      expect(r!['durationMs'], 0);
    });
  });
}
