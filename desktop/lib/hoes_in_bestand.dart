/// De hoes die de app toont, ook IN het bestand.
///
/// Saber, 21-10-2026, na Jordy — Dur Dur D'être Bébé: de app toonde Pochette Surprise, maar het bestand
/// droeg nog de hoes van de Foute CD van de uploader. *"Doe dit altijd bij allemaal, want dat is
/// verwarrend anders. Je hebt mijn toestemming en geef de app ook toestemming om dit altijd te doen."*
///
/// **Wat.** Op de pc legt [HoesInBestandVeger] de voorkant die de bibliotheek zeker weet — jouw eigen keuze
/// of die van een herkende uitgave ([Album.correctedCover], [Album.resolvedCover]) — als eerste PICTURE
/// (soort 3, voorkant) in elke FLAC van dat album — en sinds 22-10-2026 ook in mp3, AIFF, WavPack en Monkey's
/// Audio (`hoes_in_bestand_anders.dart`) — en opnieuw als die keuze verandert. Een gok op naam
/// ([Album.enriched]) gaat er niet in: die kan fout zijn, en dan zat de fout voortaan in je bestanden. Een
/// album zonder zekere hoes maar met een eigen ingebedde hoes geeft die aan zijn nummers die er geen
/// hebben. De andere platen (achterkant, cd) blijven staan.
///
/// **Zonder dat er iets anders verschuift.** Gemeten op 21-10-2026 over 1723 FLAC's: 1660 hebben
/// opvulruimte (gemiddeld 166 KB) en 1208 een ingebedde hoes (gemiddeld 710 KB). Past de nieuwe hoes in
/// de ruimte van de oude plus de opvulling, dan blijft het bestand precies even groot; de wijzigingsdatum
/// gaat altijd terug naar wat ze was. Zo blijven "recent toegevoegd", de luidheid, de heelheidscontrole en
/// de vingerafdrukken — allemaal op grootte en datum — gewoon geldig. Past hij niet, dan groeit het
/// bestand (met ruimte voor een volgende keer) en meet de luidheidsveger het opnieuw.
///
/// **Veilig.** De audio wordt byte voor byte gekopieerd, naar een bestand ernaast dat pas na een controle
/// (juiste lengte, het origineel onveranderd) over het origineel gaat — net als [writeFlacFields]. Wat
/// speelt, kapot is of door een andere veger open staat, wacht. De oude voorkant gaat eerst naar
/// `hoes_oud/` (één keer per beeld), zodat het altijd terug kan.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'artwork.dart' show verkleindeHoesBuitenDeTekendraad;
import 'cachesleutel.dart' show fnv1aBytes, fnv1aVan;
import 'flac_tags.dart' show flacBegin;
import 'hoes_in_bestand_anders.dart';
import 'integriteit.dart' show bekendKapot;
import 'lan/transcode.dart' show Transcoder;
import 'library.dart';
import 'models.dart';
import 'warm_log.dart';

/// Groter dan dit gaat een hoes verkleind ([kHoesInBestandZijde]) in elk nummer: een scan van 15 MB in
/// elk van twaalf nummers is 180 MB voor één plaatje. Gemeten: 14 van ~1200 gekozen hoezen zijn groter.
const kHoesInBestandMax = 2 * 1024 * 1024;
const kHoesInBestandZijde = 1600;

/// Ruimte die erbij komt als de nieuwe hoes niet in de oude ruimte past — voor een volgende keer.
const kHoesInBestandRuimte = 64 * 1024;

enum HoesUitkomst {
  /// Geschreven; het bestand is even groot gebleven.
  zelfdeGrootte,

  /// Geschreven; het bestand is gegroeid of gekrompen.
  andereGrootte,

  /// De eerste plaat in het bestand is deze hoes al.
  alGelijk,

  /// Er zit al een plaat in, en er mocht alleen in een bestand zonder plaat geschreven worden.
  heeftAlEen,

  /// Geen bestand dat we veilig herschrijven (geen `fLaC`, een verminkt blok, een ID3-kop of APE-blok dat we
  /// niet helemaal kennen).
  nietTeLezen,

  /// Het bestand staat op alleen-lezen: iemand heeft het zo gewild, dus blijft het zoals het is. Gezien op
  /// 21-10-2026: zeven FLAC's (Alizée, Twarres, Âme) — elke ronde opnieuw proberen had geen zin.
  alleenLezen,

  /// Het schrijven of het vervangen lukte niet (staat open, alleen-lezen, onderweg veranderd).
  mislukt,
}

/// MIME en maten van een JPEG of PNG, of null als het geen van beide is.
({String mime, int breedte, int hoogte})? beeldKenmerk(Uint8List b) {
  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    final w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
    final h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
    return w > 0 && h > 0 ? (mime: 'image/png', breedte: w, hoogte: h) : null;
  }
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var o = 2;
  while (o + 9 < b.length) {
    if (b[o] != 0xFF) {
      o++;
      continue;
    }
    final m = b[o + 1];
    if (m == 0xFF) {
      o++;
      continue;
    }
    if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
      o += 2;
      continue;
    }
    final len = (b[o + 2] << 8) | b[o + 3];
    // SOF0–SOF15, behalve DHT (C4), JPG (C8) en DAC (CC).
    if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
      final h = (b[o + 5] << 8) | b[o + 6];
      final w = (b[o + 7] << 8) | b[o + 8];
      return w > 0 && h > 0 ? (mime: 'image/jpeg', breedte: w, hoogte: h) : null;
    }
    if (len < 2) return null;
    o += 2 + len;
  }
  return null;
}

/// Het lijf van een FLAC-PICTURE-blok: soort 3 (voorkant), MIME, geen omschrijving, maten, het beeld.
Uint8List pictureLijf(Uint8List beeld, ({String mime, int breedte, int hoogte}) k) {
  final mime = ascii.encode(k.mime);
  final b = BytesBuilder(copy: false);
  void be32(int v) => b.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  be32(3);
  be32(mime.length);
  b.add(mime);
  be32(0); // omschrijving
  be32(k.breedte);
  be32(k.hoogte);
  be32(24); // kleurdiepte
  be32(0); // geen palet
  be32(beeld.length);
  b.add(beeld);
  return b.toBytes();
}

int _be32(Uint8List d, int i) => (d[i] << 24) | (d[i + 1] << 16) | (d[i + 2] << 8) | d[i + 3];

/// Soort en beeldbytes van een PICTURE-lijf, of null als het verminkt is.
({int soort, Uint8List beeld})? _leesPicture(Uint8List d) {
  if (d.length < 8) return null;
  final soort = _be32(d, 0);
  var p = 4;
  final mimeLen = _be32(d, p);
  if (mimeLen < 0 || mimeLen > 1024) return null;
  p += 4 + mimeLen;
  if (d.length < p + 4) return null;
  final descLen = _be32(d, p);
  if (descLen < 0 || descLen > 65536) return null;
  p += 4 + descLen + 16;
  if (d.length < p + 4) return null;
  final n = _be32(d, p);
  p += 4;
  if (n <= 0 || d.length < p + n) return null;
  return (soort: soort, beeld: Uint8List.sublistView(d, p, p + n));
}

bool _gelijk(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// De nieuwe blokken: STREAMINFO voorop, de nieuwe voorkant vóór elke andere plaat (de bibliotheek leest
/// de EERSTE plaat), de oude voorkanten (soort 3 en 0) weg, en één opvulblok achteraan zodat de kop even
/// lang blijft als [oudeLengte] (de bytes na `fLaC`) als dat kan. Pure functie — zie de toetsen.
@visibleForTesting
List<({int soort, Uint8List lijf})> nieuweBlokken(
    List<({int soort, Uint8List lijf})> oud, Uint8List nieuwePlaat, int oudeLengte) {
  final uit = <({int soort, Uint8List lijf})>[];
  var geplaatst = false;
  for (final b in oud) {
    if (b.soort == 1) continue; // opvulling: straks één nieuw blok
    if (b.soort == 6) {
      if (!geplaatst) {
        uit.add((soort: 6, lijf: nieuwePlaat));
        geplaatst = true;
      }
      final p = _leesPicture(b.lijf);
      if (p == null || p.soort == 3 || p.soort == 0) continue;
    }
    uit.add(b);
  }
  if (!geplaatst) uit.add((soort: 6, lijf: nieuwePlaat));
  var kern = 0;
  for (final b in uit) {
    kern += 4 + b.lijf.length;
  }
  final over = oudeLengte - kern;
  if (over == 0) return uit;
  final ruimte = over >= 4 && over - 4 <= 0xFFFFFF ? over - 4 : kHoesInBestandRuimte;
  uit.add((soort: 1, lijf: Uint8List(ruimte)));
  return uit;
}

/// Bewaart een oude voorkant in [map] als `<merk>.jpg` (`.png`, `.gif`), één keer per beeld; geeft de naam.
String bewaarOudeVoorkant(Uint8List b, String map) {
  final soort = beeldKenmerk(b)?.mime == 'image/png'
      ? '.png'
      : b.length > 3 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46
          ? '.gif'
          : '.jpg';
  final naam = '${fnv1aBytes(b, fnv1aVan(b.length.toString())).toRadixString(16)}$soort';
  final doel = File('$map${Platform.pathSeparator}$naam');
  if (!doel.existsSync()) {
    Directory(map).createSync(recursive: true);
    doel.writeAsBytesSync(b, flush: true);
  }
  return naam;
}

/// Legt [beeld] als voorkant in de FLAC op [pad] — zie de uitleg bovenaan. Synchroon, voor een isolate.
///
/// [alleenAlsLeeg]: alleen in een bestand zonder enige plaat. [bewaarOud]: een map waar de oude voorkant
/// heen gaat (als `<sha>.jpg`, één keer per beeld); de naam komt terug in `oud`.
({HoesUitkomst uitkomst, String? oud, String? reden}) schrijfVoorkantInFlac(String pad, Uint8List beeld,
    {bool alleenAlsLeeg = false, String? bewaarOud}) {
  final k = beeldKenmerk(beeld);
  if (k == null) return (uitkomst: HoesUitkomst.nietTeLezen, oud: null, reden: 'geen JPEG of PNG');
  final f = File(pad);
  RandomAccessFile? raf;
  File? tmp;
  try {
    final st = f.statSync();
    // Geen schrijfrechten in de modus (Windows: het kenmerk alleen-lezen) — vóór er iets gekopieerd wordt.
    if (st.mode & 0x92 == 0) return (uitkomst: HoesUitkomst.alleenLezen, oud: null, reden: null);
    raf = f.openSync();
    final grootte = raf.lengthSync();
    // Een ID3-kop vóór de FLAC (niet volgens de regels, maar het komt voor: gezien op 21-10-2026 bij o.a.
    // Janet Jackson, Cher en Real McCoy) gaat byte voor byte mee; alleen de FLAC-kop erachter verandert.
    final begin = grootte < 8 ? -1 : flacBegin(raf);
    if (begin < 0) return (uitkomst: HoesUitkomst.nietTeLezen, oud: null, reden: 'geen fLaC');
    final voorvoegsel = begin == 0 ? Uint8List(0) : (raf..setPositionSync(0)).readSync(begin);
    raf.setPositionSync(begin + 4);
    final blokken = <({int soort, Uint8List lijf})>[];
    var laatste = false;
    for (var i = 0; i < 128 && !laatste; i++) {
      final h = raf.readSync(4);
      if (h.length < 4) return (uitkomst: HoesUitkomst.nietTeLezen, oud: null, reden: 'kop afgekapt');
      laatste = (h[0] & 0x80) != 0;
      final len = (h[1] << 16) | (h[2] << 8) | h[3];
      final lijf = raf.readSync(len);
      if (lijf.length < len) return (uitkomst: HoesUitkomst.nietTeLezen, oud: null, reden: 'blok afgekapt');
      blokken.add((soort: h[0] & 0x7F, lijf: lijf));
    }
    if (!laatste || blokken.isEmpty || blokken.first.soort != 0) {
      return (uitkomst: HoesUitkomst.nietTeLezen, oud: null, reden: 'geen geldige kop');
    }
    final audioBegin = raf.positionSync();

    // Wat de bibliotheek leest: de eerste plaat met beeld.
    ({int soort, Uint8List beeld})? eerste;
    for (final b in blokken) {
      if (b.soort != 6) continue;
      final p = _leesPicture(b.lijf);
      if (p != null) {
        eerste = p;
        break;
      }
    }
    if (eerste != null && _gelijk(eerste.beeld, beeld)) return (uitkomst: HoesUitkomst.alGelijk, oud: null, reden: null);
    if (alleenAlsLeeg && blokken.any((b) => b.soort == 6)) {
      return (uitkomst: HoesUitkomst.heeftAlEen, oud: null, reden: null);
    }

    // De oude voorkant bewaren, één keer per beeld.
    final oud = bewaarOud != null && eerste != null && (eerste.soort == 3 || eerste.soort == 0)
        ? bewaarOudeVoorkant(eerste.beeld, bewaarOud)
        : null;

    final nieuw = nieuweBlokken(blokken, pictureLijf(beeld, k), audioBegin - begin - 4);
    final kop = BytesBuilder(copy: false)
      ..add(voorvoegsel)
      ..add(const [0x66, 0x4C, 0x61, 0x43]);
    for (var i = 0; i < nieuw.length; i++) {
      final l = nieuw[i].lijf.length;
      if (l > 0xFFFFFF) return (uitkomst: HoesUitkomst.nietTeLezen, oud: null, reden: 'plaat te groot voor een blok');
      kop.add([(i == nieuw.length - 1 ? 0x80 : 0) | nieuw[i].soort, (l >> 16) & 0xFF, (l >> 8) & 0xFF, l & 0xFF]);
      kop.add(nieuw[i].lijf);
    }
    final kopBytes = kop.toBytes();

    // Ernaast schrijven: de kop, dan de audio in stukken van 8 MB — byte voor byte.
    tmp = File('$pad.hoes');
    final uit = tmp.openSync(mode: FileMode.write);
    try {
      uit.writeFromSync(kopBytes);
      raf.setPositionSync(audioBegin);
      var rest = grootte - audioBegin;
      while (rest > 0) {
        final stuk = raf.readSync(rest < 8 << 20 ? rest : 8 << 20);
        if (stuk.isEmpty) throw const FileSystemException('audio korter dan verwacht');
        uit.writeFromSync(stuk);
        rest -= stuk.length;
      }
      uit.flushSync();
    } finally {
      uit.closeSync();
    }
    raf.closeSync();
    raf = null;

    // Controle vóór het vervangen: juiste lengte, en het origineel is intussen niet veranderd.
    final verwacht = kopBytes.length + (grootte - audioBegin);
    final nu = f.statSync();
    if (tmp.lengthSync() != verwacht || nu.size != st.size || nu.modified != st.modified) {
      tmp.deleteSync();
      return (uitkomst: HoesUitkomst.mislukt, oud: oud, reden: 'onderweg veranderd');
    }
    tmp.renameSync(pad);
    tmp = null;
    try {
      f.setLastModifiedSync(st.modified);
    } catch (_) {/* de hoes staat erin; alleen "recent toegevoegd" schuift dan */}
    return (
      uitkomst: verwacht == grootte ? HoesUitkomst.zelfdeGrootte : HoesUitkomst.andereGrootte,
      oud: oud,
      reden: null
    );
  } catch (e) {
    return (
      uitkomst: HoesUitkomst.mislukt,
      oud: null,
      reden: e is PathAccessException ? 'staat open of op alleen-lezen' : '$e'
    );
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
    try {
      if (tmp != null && tmp.existsSync()) tmp.deleteSync();
    } catch (_) {}
  }
}

/// Legt [beeld] als voorkant in het bestand op [pad], naar zijn soort ([hoesbakVan]): FLAC hierboven, mp3, AIFF,
/// WavPack en Monkey's Audio in `hoes_in_bestand_anders.dart`. Synchroon, voor een isolate.
({HoesUitkomst uitkomst, String? oud, String? reden}) schrijfVoorkant(String pad, Uint8List beeld,
        {bool alleenAlsLeeg = false, String? bewaarOud}) =>
    switch (hoesbakVan(pad)) {
      Hoesbak.flac => schrijfVoorkantInFlac(pad, beeld, alleenAlsLeeg: alleenAlsLeeg, bewaarOud: bewaarOud),
      Hoesbak.id3 => schrijfVoorkantInMp3(pad, beeld, alleenAlsLeeg: alleenAlsLeeg, bewaarOud: bewaarOud),
      Hoesbak.aiff => schrijfVoorkantInAiff(pad, beeld, alleenAlsLeeg: alleenAlsLeeg, bewaarOud: bewaarOud),
      Hoesbak.ape => schrijfVoorkantInApe(pad, beeld, alleenAlsLeeg: alleenAlsLeeg, bewaarOud: bewaarOud),
      null => (uitkomst: HoesUitkomst.nietTeLezen, oud: null, reden: 'dit formaat nog niet'),
    };

/// [schrijfVoorkant] in een eigen isolate.
///
/// **Een functie op het hoogste niveau, en dat is geen smaak.** Een closure die IN een methode van de veger
/// gemaakt wordt, neemt de context van die methode mee naar de isolate — en daarmee de veger zelf, met zijn
/// timers. Gemeten op de pc (21-10-2026, 3.9.538): de eerste ronde brak meteen af met "object is unsendable
/// — _Timer", vóór er één bestand geschreven was. Hier draagt de closure alleen deze vier waarden.
Future<({HoesUitkomst uitkomst, String? oud, String? reden})> schrijfVoorkantApart(
        String pad, Uint8List beeld, bool alleenAlsLeeg, String? bewaarOud) =>
    Isolate.run(() => schrijfVoorkant(pad, beeld, alleenAlsLeeg: alleenAlsLeeg, bewaarOud: bewaarOud));

/// Wat er per album in de bestanden hoort: het beeld, en of het alleen in bestanden zonder plaat mag.
/// Null als er niets zekers is (zie de uitleg bovenaan).
({Uint8List beeld, bool alleenAlsLeeg})? hoesVoorBestanden(Album a) {
  final zeker = a.correctedCover ?? a.resolvedCover;
  if (zeker != null && zeker.length >= 100) return (beeld: zeker, alleenAlsLeeg: false);
  final eigen = a.embeddedCover;
  if (eigen != null && eigen.length >= 100 && !a.embeddedIsVanEenAndere) return (beeld: eigen, alleenAlsLeeg: true);
  return null;
}

/// Legt op de pc de gekozen voorkant in de bestanden — zie de uitleg bovenaan. Zelfde gedrag als
/// [EchtheidVeger]: pas na een paar minuten, wachten zolang er gescand, omgezet of gemeten wordt, en een
/// bestand loslaten als het gewist of verplaatst wordt.
class HoesInBestandVeger {
  HoesInBestandVeger({
    required this.library,
    this.enabled = true,
    this.bezigElders,
    this.speeltNu,
    this.startNa = const Duration(minutes: 4),
    this.rust = const Duration(seconds: 30),
    this.tussenpoos = const Duration(milliseconds: 200),
  });

  final LibraryStore library;
  final bool enabled;
  final bool Function()? bezigElders;
  final bool Function(String pad)? speeltNu;
  final Duration startNa, rust, tussenpoos;

  /// Voor de hartslag: wat de veger nu doet.
  static final ValueNotifier<String> voortgang = ValueNotifier<String>('');

  late final WarmLog _log = WarmLog('${library.configDir}${Platform.pathSeparator}hoes_in_bestand.log');
  String get _oudMap => '${library.configDir}${Platform.pathSeparator}hoes_oud';

  bool _gestart = false, _gestopt = false, _bezig = false, _nogEens = false;
  bool get bezig => _bezig;
  Timer? _start, _herstart, _later;
  final Map<String, DateTime> _geblokkeerd = {};

  /// Wat overgeslagen werd (het speelde, een andere veger had het open), komt na deze tijd opnieuw aan de
  /// beurt — ook als er intussen niets verandert.
  static const kOpnieuw = Duration(minutes: 10);

  /// Merk en verkleinde versie per hoes, op identiteit: een volgende ronde rekent niets opnieuw.
  final Expando<String> _merkVan = Expando();
  final Expando<Uint8List> _verkleindVan = Expando();

  /// Per pad (kleine letters) "merk|grootte|datum": met welke hoes het bestand klaar is, en welk bestand
  /// dat toen was. Ook over herstarts heen (`hoes_in_bestand.json`). Klopt dat nog, dan hoeft het niet open.
  ///
  /// **Met grootte en datum, en niet alleen het merk.** Gemeten op 21-10-2026: na een herstart keek de veger
  /// alle 1586 al goede nummers opnieuw na (609 s); en Alanis Morissette — Perfect, deze sessie "niet te
  /// herschrijven" (een kapotte kop), bleef dat ook nadat Saber hem opnieuw downloadde — het nieuwe, gave
  /// bestand kwam pas na een herstart aan de beurt. Een ander bestand op hetzelfde pad is nu een nieuwe vraag.
  Map<String, String>? _opSchijf;
  bool _opSchijfVeranderd = false;
  String get _indexPad => '${library.configDir}${Platform.pathSeparator}hoes_in_bestand.json';

  Map<String, String> _laadOpSchijf() {
    final al = _opSchijf;
    if (al != null) return al;
    final uit = <String, String>{};
    try {
      final f = File(_indexPad);
      if (f.existsSync()) {
        for (final e in (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>).entries) {
          if (e.value is String) uit[e.key] = e.value as String;
        }
      }
    } catch (_) {/* dan kijkt deze ronde alles na, en schrijft het opnieuw */}
    return _opSchijf = uit;
  }

  /// Onthoud dat [pad] klaar is met [merk], met zijn grootte en datum van nu.
  void _onthoud(String pad, String merk) {
    try {
      final st = File(pad).statSync();
      _laadOpSchijf()[pad.toLowerCase()] = '$merk|${st.size}|${st.modified.millisecondsSinceEpoch}';
      _opSchijfVeranderd = true;
    } catch (_) {}
  }

  void _bewaarOpSchijf() {
    if (!_opSchijfVeranderd) return;
    try {
      File(_indexPad).writeAsStringSync(jsonEncode(_opSchijf));
      _opSchijfVeranderd = false;
    } catch (e) {
      _log.line('hoes_in_bestand.json niet bewaard: $e');
    }
  }

  String? _nuPad;
  Future<void>? _nu;

  Future<void> start() async {
    if (!enabled || library.isRemote || _gestart) return;
    _gestart = true;
    library.addListener(_veranderd);
    _start = Timer(startNa, () => unawaited(ronde()));
  }

  void stop() {
    _gestopt = true;
    _start?.cancel();
    _herstart?.cancel();
    _later?.cancel();
    library.removeListener(_veranderd);
  }

  void _veranderd() {
    if (_gestopt || !_gestart || (_start?.isActive ?? false)) return;
    _herstart?.cancel();
    _herstart = Timer(rust, () => unawaited(ronde()));
  }

  /// Wacht tot een lopende schrijfbeurt op [paden] klaar is, en laat die paden ~10 s met rust.
  Future<void> laatLos(List<String> paden) async {
    final tot = DateTime.now().add(const Duration(seconds: 10));
    final weg = {for (final p in paden) p.toLowerCase()};
    for (final p in weg) {
      _geblokkeerd[p] = tot;
    }
    final nu = _nu, pad = _nuPad;
    if (nu != null && pad != null && weg.contains(pad.toLowerCase())) await nu;
  }

  bool _isGeblokkeerd(String pad) {
    final tot = _geblokkeerd[pad.toLowerCase()];
    return tot != null && DateTime.now().isBefore(tot);
  }

  Future<bool> _wachtOpRust() async {
    while (!_gestopt && (library.scanning || (bezigElders?.call() ?? false) || Transcoder.bezig)) {
      voortgang.value = library.scanning ? 'hoezen wachten: bibliotheek scant' : 'hoezen wachten';
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return !_gestopt;
  }

  /// Is [t] al klaar met [merk]? Eerst wat de bibliotheek van het bestand weet; loopt die achter (het
  /// bestand groeide door ons, en dat ziet ze pas bij een volgende scan), dan het bestand zelf.
  bool _isKlaar(Track t, String merk) {
    final al = _laadOpSchijf()[t.path.toLowerCase()];
    if (al == null || !al.startsWith('$merk|')) return false;
    if (al == '$merk|${t.sizeBytes}|${t.addedMs}') return true;
    try {
      final st = File(t.path).statSync();
      return al == '$merk|${st.size}|${st.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return false;
    }
  }

  static String _merk(Uint8List b) => fnv1aBytes(b, fnv1aVan(b.length.toString())).toRadixString(16);

  Future<void> ronde() async {
    if (_gestopt) return;
    if (_bezig) {
      _nogEens = true;
      return;
    }
    _bezig = true;
    try {
      final werk = <({Album album, Uint8List beeld, bool alleenAlsLeeg, String merk, List<Track> nummers})>[];
      var nogNiet = 0;
      for (final a in library.albums) {
        final h = hoesVoorBestanden(a);
        if (h == null) continue;
        var beeld = h.beeld;
        if (beeld.length > kHoesInBestandMax) {
          beeld = _verkleindVan[h.beeld] ??=
              await verkleindeHoesBuitenDeTekendraad(h.beeld, kHoesInBestandZijde) ?? h.beeld;
        }
        final merk = _merkVan[beeld] ??= _merk(beeld);
        // Even loslaten: 800 albums met elk ~200 KB hashen is anders één blok op de tekendraad.
        await Future<void>.delayed(Duration.zero);
        final nummers = <Track>[];
        for (final t in a.tracks) {
          if (t.path.isEmpty) continue;
          if (hoesbakVan(t.path) == null) {
            nogNiet++;
            continue;
          }
          if (_isKlaar(t, merk)) continue;
          nummers.add(t);
        }
        if (nummers.isNotEmpty) {
          werk.add((album: a, beeld: beeld, alleenAlsLeeg: h.alleenAlsLeeg, merk: merk, nummers: nummers));
        }
      }
      if (werk.isEmpty) return;
      final totaal = werk.fold<int>(0, (n, w) => n + w.nummers.length);
      final start = DateTime.now();
      _log.line('ronde: $totaal nummers in ${werk.length} albums na te kijken'
          '${nogNiet > 0 ? ' ($nogNiet in een formaat dat nog niet kan, zoals m4a)' : ''}');
      var gedaan = 0, zelfde = 0, ander = 0, gelijk = 0, overgeslagen = 0, mis = 0, overslaanVast = 0;
      final oud = <String, String>{};
      for (final w in werk) {
        for (final t in w.nummers) {
          if (_gestopt || !await _wachtOpRust()) return;
          gedaan++;
          voortgang.value = 'hoezen $gedaan/$totaal';
          final pad = t.path;
          final waarom = _isGeblokkeerd(pad)
              ? 'wordt verplaatst of gewist'
              : (speeltNu?.call(pad) ?? false)
                  ? 'speelt'
                  : bekendKapot(pad)
                      ? 'bekend kapot'
                      : !File(pad).existsSync()
                          ? 'staat er niet meer'
                          : null;
          if (waarom != null) {
            overgeslagen++;
            _log.line('even overgeslagen ($waarom): $pad');
            continue;
          }
          final beeld = w.beeld;
          final klus = schrijfVoorkantApart(pad, beeld, w.alleenAlsLeeg, _oudMap);
          _nuPad = pad;
          _nu = klus.then((_) {});
          final r = await klus;
          _nu = null;
          _nuPad = null;
          switch (r.uitkomst) {
            case HoesUitkomst.zelfdeGrootte:
            case HoesUitkomst.andereGrootte:
              if (r.uitkomst == HoesUitkomst.zelfdeGrootte) {
                zelfde++;
              } else {
                ander++;
              }
              _onthoud(pad, w.merk);
              if (r.oud != null) oud[pad] = r.oud!;
              _werkHoescacheBij(w.album, pad, beeld);
              _log.line('geschreven${r.uitkomst == HoesUitkomst.andereGrootte ? ' (bestand groeide)' : ''}: $pad');
              // Alleen na een echte schrijfbeurt even ademhalen: nakijken kost niets aan de schijf.
              await Future<void>.delayed(tussenpoos);
            case HoesUitkomst.alGelijk:
            case HoesUitkomst.heeftAlEen:
              gelijk++;
              _onthoud(pad, w.merk);
            case HoesUitkomst.alleenLezen:
              overslaanVast++;
              _onthoud(pad, w.merk);
              _log.line('alleen-lezen, niet aangeraakt: $pad');
            case HoesUitkomst.nietTeLezen:
              mis++;
              _onthoud(pad, w.merk); // niet opnieuw proberen — tenzij er een ander bestand komt te staan
              _log.line('niet te herschrijven (${r.reden}): $pad');
            case HoesUitkomst.mislukt:
              mis++;
              _log.line('MISLUKT (${r.reden}) — volgende ronde opnieuw: $pad');
          }
          if (gedaan % 100 == 0) _bewaarOpSchijf();
        }
      }
      _bewaarOpSchijf();
      if (oud.isNotEmpty) _bewaarOudIndex(oud);
      if ((overgeslagen > 0 || mis > 0) && !_gestopt) {
        _later?.cancel();
        _later = Timer(kOpnieuw, () => unawaited(ronde()));
      }
      final s = DateTime.now().difference(start).inSeconds;
      _log.line('klaar in $s s: ${zelfde + ander} geschreven ($zelfde even groot, $ander gegroeid), '
          '$gelijk hadden hem al, $overgeslagen even overgeslagen (speelt, kapot of bezet), '
          '$overslaanVast op alleen-lezen, $mis niet gelukt');
    } catch (e) {
      _log.line('ronde MISLUKT: $e');
    } finally {
      _bezig = false;
      voortgang.value = '';
      if (_nogEens && !_gestopt) {
        _nogEens = false;
        unawaited(ronde());
      }
    }
  }

  /// De cache van ingebedde hoezen ([hoesSleutel]) bijwerken: met dezelfde grootte en datum las de
  /// bibliotheek anders bij de volgende start de OUDE plaat uit haar cache.
  void _werkHoescacheBij(Album album, String pad, Uint8List beeld) {
    try {
      final st = File(pad).statSync();
      final sleutel = hoesSleutel(pad, st.modified.millisecondsSinceEpoch, st.size);
      final map = Directory(library.hoesCacheMap);
      if (!map.existsSync()) map.createSync(recursive: true);
      File('${map.path}${Platform.pathSeparator}$sleutel').writeAsBytesSync(beeld);
      final geen = File('${map.path}${Platform.pathSeparator}$sleutel.geen');
      if (geen.existsSync()) geen.deleteSync();
      if (album.tracks.isNotEmpty && album.tracks.first.path == pad) album.embeddedCover = beeld;
    } catch (_) {/* dan leest de volgende start het bestand zelf opnieuw */}
  }

  /// Welk oud beeld bij welk pad hoorde (`hoes_oud/index.json`) — het eerste dat er ooit in zat blijft staan.
  void _bewaarOudIndex(Map<String, String> erbij) {
    try {
      final f = File('$_oudMap${Platform.pathSeparator}index.json');
      final index = <String, dynamic>{};
      if (f.existsSync()) index.addAll(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
      for (final e in erbij.entries) {
        index.putIfAbsent(e.key, () => e.value);
      }
      f.writeAsStringSync(jsonEncode(index));
    } catch (e) {
      _log.line('index van de oude hoezen niet bijgewerkt: $e');
    }
  }
}
