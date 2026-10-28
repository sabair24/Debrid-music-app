// Geen nep-studio (Saber, 28-10-2026). Lil' Kim — How Many Licks? kwam als FLAC 24/44,1 van Soulseek LGSONE en werd als
// studioversie aangeboden naast zijn cd. Gemeten: een muur van 64 dB op 20,85 kHz en een trede op 16 kHz — een mp3 die
// naar 24 bit was omgezet; zijn cd loopt door tot 22 kHz. "Ik wil geen fake enkel echt dus dan moet de app gewoon
// wegsmijten. Je mag van mij die andere fakes ook weggooien, en download ze weer in echte formaat, liever cd kwaliteit
// dan fake studio!"
//
// De oordelen hieronder staan letterlijk zo in zijn echtheid_oordelen.json van 28-10-2026.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/keuring.dart';
import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart' show firstIsBetter, whyBetter;
import 'package:debridmusic/versie_opbergen.dart';
import 'package:debridmusic/versies.dart';
import 'package:debridmusic/vinylspoor.dart' show stilteVan;
import 'package:flutter_test/flutter_test.dart';

Echtheidsoordeel _o(String json) => Echtheidsoordeel.fromJson(jsonDecode(json) as Map<String, dynamic>)!;

/// De kopie van LGSONE (24/44,1).
final _licksKandidaat = _o('{"v":2,"bits":"spreektNietTegen","boven":"onbekend","band":"vermoedelijk","gebruikteBits":24,'
    '"afkapHz":20850,"wandDb":63.69158075987881,"vensters":700,"integriteit":"klopt"}');

/// Zijn cd (16/44,1): de steilste val is een zachte 5,8 dB op 14,7 kHz, verder loopt hij door.
final _licksCd = _o('{"v":2,"bits":"onbekend","boven":"onbekend","band":"doorlopend","gebruikteBits":16,"afkapHz":14700,'
    '"wandDb":5.8298838551029055,"vensters":700,"integriteit":"klopt"}');

/// Haddaway — What Is Love, als "studio" 24/96: boven 24,5 kHz leeg, op 22 kHz een klif.
final _haddawayOpgeschaald = _o('{"v":2,"bits":"spreektNietTegen","boven":"leeg","band":"doorlopend","gebruikteBits":24,'
    '"afkapHz":21500,"wandDb":7.378503840305322,"vensters":700,"integriteit":"klopt","ultraDb":-61.41638893058781}');

/// 2 Unlimited — Here I Go: een 24-bitkop met 16 bits in gebruik.
final _opgeblazen = _o('{"v":2,"bits":"opgeblazen","boven":"onbekend","band":"doorlopend","gebruikteBits":16,'
    '"afkapHz":21150,"wandDb":17.152395609023177,"vensters":700,"integriteit":"klopt"}');

/// Jorja Smith — Burn, de cd: dezelfde muur rond 20,7 kHz als de studiokopie ernaast. Die muur zit in de master.
final _cdMetMuur = _o('{"v":2,"bits":"onbekend","boven":"onbekend","band":"vermoedelijk","gebruikteBits":16,'
    '"afkapHz":20650,"wandDb":31.023713281678987,"vensters":700,"integriteit":"klopt"}');

/// Een eerlijke 24/44,1 (Ellie Goulding — Close To Me van TIDAL, 23-10-2026).
const _echteStudio = Echtheidsoordeel(
    bits: Bitdiepte.spreektNietTegen,
    boven: Bovenband.onbekend,
    band: Bandbreedte.doorlopend,
    gebruikteBits: 24,
    afkapHz: 21100,
    integriteit: Integriteit.klopt);

const _mp3 = Echtheidsoordeel(
    bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.afgekapt, afkapHz: 16000, wandDb: 60);

Kwaliteit _flacK(int rate, Echtheidsoordeel? o) => kwaliteitUit(verliesvrij: true, kopRate: rate, formaat: 4, oordeel: o);

/// Een kleine maar echte FLAC (zoals in versie_opbergen_test.dart): STREAMINFO met [hz], [bits] en [sec], en de tags.
Uint8List _flac({required int hz, required int bits, int sec = 233, Map<String, String> tags = const {}}) {
  final out = BytesBuilder()..add(ascii.encode('fLaC'));
  void blok(int type, List<int> body, bool laatste) {
    out.add([(laatste ? 0x80 : 0) | type, (body.length >> 16) & 0xFF, (body.length >> 8) & 0xFF, body.length & 0xFF]);
    out.add(body);
  }

  final si = Uint8List(34);
  final totaal = hz * sec;
  si[10] = (hz >> 12) & 0xFF;
  si[11] = (hz >> 4) & 0xFF;
  si[12] = ((hz & 0x0F) << 4) | (1 << 1) | (((bits - 1) >> 4) & 1);
  si[13] = (((bits - 1) & 0x0F) << 4) | ((totaal >> 32) & 0x0F);
  si[14] = (totaal >> 24) & 0xFF;
  si[15] = (totaal >> 16) & 0xFF;
  si[16] = (totaal >> 8) & 0xFF;
  si[17] = totaal & 0xFF;
  blok(0, si, false);
  final b = BytesBuilder();
  void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  final ven = utf8.encode('reference libFLAC 1.4.3');
  u32(ven.length);
  b.add(ven);
  u32(tags.length);
  for (final e in tags.entries) {
    final c = utf8.encode('${e.key}=${e.value}');
    u32(c.length);
    b.add(c);
  }
  blok(4, b.toBytes(), false);
  blok(1, List.filled(64, 0), true);
  out.add(List.filled(8192, 0x5A));
  return out.toBytes();
}

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('de soort zoals de meter hem laat staan', () {
    const licksPad = r"music\Lil' Kim\The Notorious KIM (2000)\07 - How Many Licks.flac";

    test('DE KERN: Lil\' Kim — een 24/44,1 met een mp3-muur is geen studio; zonder meting bleef hij het', () {
      expect(kopiesoortVan(bronpad: licksPad, bits: 24, hz: 44100, oordeel: _licksKandidaat), isNull);
      expect(kopiesoortVan(bronpad: licksPad, bits: 24, hz: 44100), Kopiesoort.studio,
          reason: 'een meting die niet kon draaien, bewijst niets');
    });

    test('een eerlijke 24/44,1 blijft studio', () {
      expect(kopiesoortVan(bronpad: 'TIDAL 568446924', bits: 24, hz: 44100, oordeel: _echteStudio), Kopiesoort.studio);
    });

    test('opgeschaald, opgeblazen en uit een mp3 omgezet: geen studio', () {
      expect(kopiesoortVan(bronpad: 'x.flac', bits: 24, hz: 96000, oordeel: _haddawayOpgeschaald), isNull);
      expect(kopiesoortVan(bronpad: 'x.flac', bits: 24, hz: 44100, oordeel: _opgeblazen), isNull);
      expect(kopiesoortVan(bronpad: 'x.flac', bits: 24, hz: 44100, oordeel: _mp3), isNull);
    });

    test('een cd met de muur van zijn master blijft een cd; een cd uit een mp3 niet', () {
      expect(kopiesoortVan(bronpad: 'x.flac', bits: 16, hz: 44100, oordeel: _cdMetMuur), Kopiesoort.cd);
      expect(kopiesoortVan(bronpad: 'x.flac', bits: 16, hz: 44100, oordeel: _mp3), isNull);
    });

    test('een vinylrip met de muur van zijn omzetter blijft vinyl; opgeschaald, opgeblazen of uit een mp3 niet', () {
      // Saber, 28-10-2026, over een vinylrip die 24/192 zegt maar opgeschaald is uit 44,1: "Weggooien".
      const vinyl = r'@@x\Daft Punk - Discovery (Vinyl 24-96)\06.flac';
      expect(kopiesoortVan(bronpad: vinyl, bits: 24, hz: 44100, oordeel: _licksKandidaat), Kopiesoort.vinyl);
      expect(kopiesoortVan(bronpad: vinyl, bits: 16, hz: 44100, oordeel: _licksCd), Kopiesoort.vinyl);
      expect(kopiesoortVan(bronpad: vinyl, bits: 24, hz: 96000, oordeel: _haddawayOpgeschaald), isNull);
      expect(kopiesoortVan(bronpad: vinyl, bits: 24, hz: 44100, oordeel: _opgeblazen), isNull);
      expect(kopiesoortVan(bronpad: vinyl, bits: 24, hz: 44100, oordeel: _mp3), isNull);
    });

    test('je NUMMER: opgeschaald is wat hij draagt (een cd), een muur rond 20 kHz laat het staan, uit een mp3 niets', () {
      expect(ankerSoortGemeten(Kopiesoort.studio, _haddawayOpgeschaald), Kopiesoort.cd);
      expect(ankerSoortGemeten(Kopiesoort.studio, _opgeblazen), Kopiesoort.cd);
      expect(ankerSoortGemeten(Kopiesoort.studio, _licksKandidaat), Kopiesoort.studio,
          reason: 'niet bewezen — anders wordt een vinyl die binnenkomt geen versie meer');
      expect(ankerSoortGemeten(Kopiesoort.cd, _mp3), isNull);
      expect(ankerSoortGemeten(Kopiesoort.vinyl, _cdMetMuur), Kopiesoort.vinyl);
      expect(ankerSoortGemeten(Kopiesoort.studio, null), Kopiesoort.studio);
    });
  });

  group('de keuring: een eerlijke kopie wint van een kop die liegt', () {
    test('DE KERN: Haddaway — je echte cd wint van de opgeschaalde 24/96', () {
      expect(vergelijkKwaliteit(_flacK(44100, _licksCd), _flacK(96000, _haddawayOpgeschaald)), greaterThan(0));
      expect(vergelijkKwaliteit(_flacK(96000, _haddawayOpgeschaald), _flacK(44100, _licksCd)), lessThan(0));
    });

    test('een opgeblazen 24-bitkop verliest van de cd', () {
      expect(vergelijkKwaliteit(_flacK(44100, _opgeblazen), _flacK(44100, _licksCd)), lessThan(0));
    });

    test('tegen een kopie met een muur rond 20 kHz blijft het gelijk — die kan een mp3 zijn', () {
      expect(vergelijkKwaliteit(_flacK(44100, _cdMetMuur), _flacK(96000, _haddawayOpgeschaald)), 0);
    });

    test('tegen een ongemeten kopie blijft het gelijk — ongemeten bewijst niets', () {
      expect(vergelijkKwaliteit(_flacK(48000, null), _flacK(96000, _haddawayOpgeschaald)), 0);
    });

    test('twee die liegen: gelijk', () {
      expect(vergelijkKwaliteit(_flacK(44100, _opgeblazen), _flacK(96000, _haddawayOpgeschaald)), 0);
    });

    test('Lil\' Kim: de 24-bitkopie met de muur is niet beter dan de cd', () {
      expect(vergelijkKwaliteit(_flacK(44100, _licksKandidaat), _flacK(44100, _licksCd)), 0);
    });
  });

  group('met echte bestanden', () {
    late Directory root;
    late String sep;
    File schrijf(String pad, Uint8List bytes) {
      final f = File(pad);
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes);
      return f;
    }

    setUp(() {
      root = Directory.systemTemp.createTempSync('dm_nep_studio_');
      sep = Platform.pathSeparator;
      versies.wis();
      resetSoortenVoorToets();
      resetEchtheidVoorTest();
    });
    tearDown(() {
      versies.wis();
      resetSoortenVoorToets();
      resetEchtheidVoorTest();
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: Lil\' Kim — geen studioversie, niet beter: weg, met de reden in het logboek', () {
      final cd = schrijf('${root.path}${sep}Albums${sep}Lil\' Kim${sep}The Notorious KIM${sep}07 - How Many Licks-.flac',
          _flac(hz: 44100, bits: 16));
      final binnen = schrijf('${root.path}$sep${'_keuring'}${sep}a${sep}07 - How Many Licks.flac', _flac(hz: 44100, bits: 24));
      onthoudOordeelVanPc(cd.path, _licksCd);
      const bron = r"music\Lil' Kim\The Notorious KIM (2000)\07 - How Many Licks.flac";
      // Zonder de meting: studio naast je cd, dus een versie — wat Saber te zien kreeg.
      expect(versieplanVoor(binnen, cd.path, bron).isVersie, isTrue);
      onthoudOordeelVanPc(binnen.path, _licksKandidaat);
      final plan = versieplanVoor(binnen, cd.path, bron);
      expect(plan.soort, isNull);
      expect(plan.besluit, Versiebesluit.gewoon);
      expect(firstIsBetter(binnen, cd), isFalse);
      expect(DownloadManager.nepStudioZin(binnen),
          'nep-studio: 24/44,1 volgens de kop, maar muur op 20,9 kHz — past bij mp3 320 of Opus, maar ook bij een 20 '
          'kHz-filter in de master; niet zeker');
      expect(DownloadManager.nepStudioZin(cd), isNull, reason: 'een cd belooft geen studio');
    });

    test('DE KERN: Haddaway — je nummer is een opgeschaalde "studio": de echte cd vervangt hem, geen versie ernaast', () {
      final nummer = schrijf('${root.path}${sep}Albums${sep}Haddaway${sep}The Album${sep}01 - What Is Love.flac',
          _flac(hz: 96000, bits: 24));
      zetSoort(nummer.path, Kopiesoort.studio);
      onthoudOordeelVanPc(nummer.path, _haddawayOpgeschaald);
      final binnen = schrijf('${root.path}$sep${'_keuring'}${sep}b${sep}01 What Is Love.flac', _flac(hz: 44100, bits: 16));
      onthoudOordeelVanPc(binnen.path, _licksCd);
      final plan = versieplanVoor(binnen, nummer.path, r'x\Haddaway - The Album (1993)\01 What Is Love.flac');
      expect(plan.ankerSoort, Kopiesoort.cd, reason: 'wat hij draagt');
      expect(plan.besluit, Versiebesluit.gewoon, reason: 'als "studio" werd de cd een versie, en bleef de nep het nummer');
      expect(firstIsBetter(binnen, nummer), isTrue);
      expect(whyBetter(binnen, nummer), startsWith('een eerlijke kopie boven een kop die liegt (boven 24,5 kHz'));
      expect(DownloadManager.nepStudioZin(nummer), startsWith('nep-studio: 24/96 volgens de kop, maar boven 24,5 kHz'));
    });

    test('het vinylspoor kijkt nog naar wat de kop belooft: een studio met de muur van zijn omzetter wordt vinyl', () async {
      final cd = schrijf('${root.path}${sep}Albums${sep}Spice Girls${sep}Spice${sep}01 - Wannabe.flac',
          _flac(hz: 44100, bits: 16, sec: 200));
      zetSoort(cd.path, Kopiesoort.cd);
      final binnen = schrijf('${root.path}$sep${'_keuring'}${sep}c${sep}01.flac', _flac(hz: 44100, bits: 24, sec: 200));
      onthoudOordeelVanPc(binnen.path, _licksKandidaat);
      stilteVan = (p) async => (stilste: p == cd.path ? -200.0 : -55.0, seconden: 200.0);
      addTearDown(() => stilteVan = null);
      const bron = r'valentinchpx\Spice [24-44]\01.flac';
      expect(await merkVinylspoor(binnen.path, cd.path, bron), isTrue);
      expect(versieplanVoor(binnen, cd.path, bron).soort, Kopiesoort.vinyl);
    });
  });

  test('aangesloten: betrapte nummers vanzelf op de verlanglijst, en de reden in beide wegen', () {
    final main = _bron('lib/main.dart');
    expect(main, contains('    downloads.nepInBibliotheek = () => [for (final r in library.teVervangenBestanden()) r.track];\n'));
    expect(main, contains('    downloads.gezagVoorVervanger = library.tagsVoorVervanger;\n'));
    final online = _bron('lib/online.dart');
    final veeg = online.substring(online.indexOf('  Future<int> sweepLosslessWants() async {'));
    final nep = veeg.indexOf('      if (nep != null && nep.isNotEmpty) await wensEchteVersies(nep, gezag: gezagVoorVervanger);\n');
    expect(nep, greaterThan(0));
    expect(nep, lessThan(veeg.indexOf('_wants.due(nu)')), reason: 'eerst erop, dan pas wie aan de beurt is');
    expect(online, contains('    final nep = nietBeter && !(plan?.isVersie ?? false) ? nepStudioZin(staged) : null;\n'));
    expect(online, contains("              _log.line('   \${job.name}: \${f.username}: \$nep — weggegooid');\n"
        '              bijUitslag?.call(f, Kopieuitslag.nep);\n'
        '              await _discardStaged(staged.path);\n'
        '              // Telt als een kopie die niet beter was, zoals vóór 28-10-2026 (toen verloor hij bij het opbergen).\n'
        '              if (++nietBeter < kJachtKopieen) continue;\n'));
    expect(online, contains('    if (soort != v.soort) return weg(nepStudioZin(staged) ?? '));
    expect(_bron('lib/lan/catalog.dart'), contains('          soort: echteSoort(soortVoor(t.path)?.soort, gemeten(t.path))?.naam,\n'));
  });
}
