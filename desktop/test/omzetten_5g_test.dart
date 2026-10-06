/// Hi-res naar cd-kwaliteit voor de telefoon op 5G: alleen als het moet, en dan ook echt 16/44.1.
///
/// **Waarom dit bestaat.** Saber op 06-10-2026: het omzetten van lossless hi-res naar cd-kwaliteit
/// voor 5G "is nog traag en niet altijd juist of doet hij het niet". Gemeten die ochtend:
///
///  * **Niet juist.** Zeventien FLAC's in de catalogus van de pc hadden geen bitdiepte en een
///    verzonnen frequentie (48000, 22050, 12000, 11025 Hz). Het waren volwaardige FLAC's met een
///    ID3-blok vóór `fLaC`; de eigen lezer gaf het op en de terugval las er een mp3 in. In de
///    cd-stand werd een 16/44.1 daardoor "omgezet" — en omdat de diepte onbekend was ging er geen
///    `maxBits` mee en maakte de pc er 24 bit van: wachten vooraf, en méér data dan het origineel.
///  * **Traag.** Een 24/192 van 325 s kostte met swr (`filter_size=256`) 2,5–3,3 s voor er één
///    byte vertrok; soxr doet hetzelfde in 0,9 s, met een verschil van −82 dB RMS.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/lan/transcode.dart';
import 'package:debridmusic/lan/upnp.dart';
import 'package:debridmusic/library.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een minimale FLAC: STREAMINFO met [rate] en [bits], en één Vorbis-commentaar.
Uint8List _flac({int rate = 44100, int bits = 16, String titel = 'Te Amo'}) {
  final b = BytesBuilder()..add(ascii.encode('fLaC'));
  b.add([0x00, 0x00, 0x00, 0x22]);
  final si = Uint8List(34);
  const kanalen = 2, monsters = 441000;
  si[10] = (rate >> 12) & 0xFF;
  si[11] = (rate >> 4) & 0xFF;
  si[12] = ((rate & 0x0F) << 4) | ((kanalen - 1) << 1) | (((bits - 1) >> 4) & 0x01);
  si[13] = (((bits - 1) & 0x0F) << 4) | ((monsters >> 32) & 0x0F);
  si[14] = (monsters >> 24) & 0xFF;
  si[15] = (monsters >> 16) & 0xFF;
  si[16] = (monsters >> 8) & 0xFF;
  si[17] = monsters & 0xFF;
  b.add(si);
  final v = BytesBuilder();
  List<int> le32(int x) => [x & 0xFF, (x >> 8) & 0xFF, (x >> 16) & 0xFF, (x >> 24) & 0xFF];
  final verkoper = utf8.encode('toets'), commentaar = utf8.encode('TITLE=$titel');
  v
    ..add(le32(verkoper.length))
    ..add(verkoper)
    ..add(le32(1))
    ..add(le32(commentaar.length))
    ..add(commentaar);
  final vb = v.takeBytes();
  b.add([0x84, (vb.length >> 16) & 0xFF, (vb.length >> 8) & 0xFF, vb.length & 0xFF]);
  b.add(vb);
  return b.takeBytes();
}

/// Een ID3v2.3-blok van [n] bytes inhoud (opvulling), met de lengte syncsafe in de kop.
List<int> _id3(int n) => [
      0x49, 0x44, 0x33, 0x03, 0x00, 0x00, //
      (n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F,
      ...List<int>.filled(n, 0),
    ];

File _schrijf(List<int> bytes, String naam) {
  final map = Directory.systemTemp.createTempSync('dm_5g_');
  addTearDown(() => map.deleteSync(recursive: true));
  return File('${map.path}${Platform.pathSeparator}$naam')..writeAsBytesSync(bytes);
}

void main() {
  group('een FLAC met een ID3-blok ervoor', () {
    test('DE KERN: frequentie, diepte en titel worden gewoon gelezen', () {
      // 602 851 bytes ID3 is wat "Te Amo" van Rihanna in deze bibliotheek vooraan heeft.
      final f = _schrijf([..._id3(602851), ..._flac(rate: 44100, bits: 16)], 'te_amo.flac');
      final t = readFlacTags(f);
      expect(t, isNotNull, reason: 'de lezer gaf het op bij ID3 vooraan; de terugval las er een mp3 in');
      expect(t!.sampleRate, 44100, reason: 'anders blijft de verzonnen 48000 Hz staan');
      expect(t.bitsPerSample, 16, reason: 'zonder diepte maakte de cd-stand er 24 bit van');
      expect(t.title, 'Te Amo');
    });

    test('ook de ruwe velden en de hoes vallen niet meer om', () {
      final f = _schrijf([..._id3(4316), ..._flac()], 'son_of_a_gun.flac');
      expect(readFlacRawFields(f)['title'], 'Te Amo');
      expect(readFlacPicture(f).gelezen, isTrue,
          reason: 'gelezen: false liet de hoes terugvallen op het pakket — vier sprongen per album');
    });

    test('DE GRENS: zonder ID3 blijft alles zoals het was, en geen FLAC blijft geen FLAC', () {
      expect(readFlacTags(_schrijf(_flac(rate: 96000, bits: 24), 'kaal.flac'))!.sampleRate, 96000);
      expect(readFlacTags(_schrijf(_flac(rate: 96000, bits: 24), 'kaal2.flac'))!.bitsPerSample, 24);
      // Een echte mp3 met ID3 ervoor: achter de tag staat een MPEG-frame, geen fLaC.
      final mp3 = _schrijf([..._id3(64), 0xFF, 0xFB, 0x90, 0x64, ...List<int>.filled(200, 0)], 'nep.flac');
      expect(readFlacTags(mp3), isNull, reason: 'een mp3 met een .flac-naam is geen FLAC');
    });
  });

  group('de tag-cache leest verkeerd gelezen rijen opnieuw', () {
    test('DE KERN: een .flac zonder diepte gaat opnieuw door de lezer', () {
      expect(moetOpnieuwGelezen(r'D:\m\Rihanna\07 - Te Amo.flac', {'bitsPerSample': 0, 'sampleRate': 48000}),
          isTrue, reason: 'anders blijft de foute rij van vóór de reparatie voor altijd in de cache');
      expect(moetOpnieuwGelezen(r'D:\m\x.FLAC', {'sampleRate': 48000}), isTrue);
    });

    test('DE GRENS: een goede rij, of een ander formaat, blijft uit de cache komen', () {
      expect(moetOpnieuwGelezen(r'D:\m\x.flac', {'bitsPerSample': 16}), isFalse,
          reason: 'elke scan zou anders alle FLAC\'s opnieuw openen');
      expect(moetOpnieuwGelezen(r'D:\m\x.mp3', {'bitsPerSample': 0}), isFalse,
          reason: 'een mp3 heeft geen diepte; die opnieuw lezen levert niets op');
    });
  });

  group('omzetten in de cd-stand', () {
    test('DE KERN: een onbekende diepte wordt bij omzetten 16, niet 24', () {
      final g = castGrenzen(sampleRate: 48000, bits: 0, maxSampleRate: 44100, maxBitDepth: 16);
      expect(g.omzetten, isTrue);
      expect(g.rate, 44100);
      expect(g.bits, 16,
          reason: 'met 0 ging er geen maxBits mee en maakte de pc er 24 bit van: méér data dan het origineel');
    });

    test('DE GRENS: zonder omzetten blijft een onbekende diepte onbekend', () {
      final g = castGrenzen(sampleRate: 44100, bits: 0, maxSampleRate: 44100, maxBitDepth: 16);
      expect(g.omzetten, isFalse, reason: 'een onbekende diepte is op zich geen reden om om te zetten');
      expect(g.bits, 0);
      final sonos = castGrenzen(sampleRate: 96000, bits: 0, maxSampleRate: 48000, maxBitDepth: 0);
      expect(sonos.bits, 0, reason: 'zonder plafond in de diepte valt er niets in te vullen');
    });
  });

  group('soxr', () {
    List<String> metSoxr(bool soxr) => omzetArgumenten(
        bronPad: '/m/a.flac',
        doelPad: '/c/a.tmp',
        maxSampleRate: 44100,
        maxBits: 16,
        recept: receptStroom,
        soxr: soxr);
    String af(List<String> a) => a[a.indexOf('-af') + 1];

    test('DE KERN: met soxr de snelle herbemonsteraar op hoogste precisie, en de dither blijft', () {
      final a = af(metSoxr(true));
      expect(a, startsWith('aresample=44100:resampler=soxr:precision=28'));
      expect(a, contains('dither_method=triangular_hp'), reason: 'naar 16 bit hoort er geditherd te worden');
      expect(a, isNot(contains('filter_size')));
    });

    test('DE GRENS: zonder soxr het swr-filter van hiervoor', () {
      expect(af(metSoxr(false)), startsWith('aresample=44100:filter_size=256'));
    });
  });
}
