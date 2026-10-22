/// De gekozen voorkant ook in een mp3, een AIFF, een WavPack en een Monkey's Audio — zie [HoesInBestandVeger].
///
/// Saber, 21-10-2026: *"Doe dit altijd bij allemaal."* De FLAC's kregen hun hoes op 21-10 (3.9.539); de
/// nummers in een ander formaat bleven over ("geen FLAC — die nog niet"). Gemeten op 22-10-2026 over de 22
/// niet-FLAC-bestanden van de bibliotheek: 6 mp3 (5× ID3v2.3/v2.4, 1× ID3v2.2), 7 AIFF (de tags in een
/// `ID3 `-chunk; één afgekapt), 7 WavPack en 1 Monkey's Audio (APEv2 achteraan, of nog geen tag), 1 m4a.
///
/// **Hoe, per soort.** Dezelfde regels als bij FLAC: de nieuwe voorkant wordt de eerste plaat (die leest de
/// bibliotheek), de oude voorkanten (soort 3 en 0) gaan weg, de andere platen en alle andere velden blijven
/// byte voor byte staan, en de audio wordt alleen gekopieerd, nooit herschreven.
/// - **mp3:** de ID3v2-kop vooraan (v2.3 of v2.4). Past de nieuwe kop in de oude plus zijn opvulling, dan
///   blijft het bestand even groot. Zonder kop krijgt het er een (v2.3).
/// - **AIFF:** dezelfde ID3v2-kop, in de `ID3 `-chunk; de FORM-grootte volgt. Geen chunk: één erbij, achteraan.
/// - **WavPack, Monkey's Audio:** het APEv2-blok achteraan (vóór een ID3v1), met `Cover Art (Front)` als eerste
///   item. Dat blok kent geen opvulling: het bestand verandert hier altijd van grootte.
///
/// **Weigeren in plaats van gokken**, zoals `mp3_tags.dart`: een indeling die hier niet helemaal begrepen wordt
/// — ID3v2.2, een kop met vlaggen, een frame dat voorbij zijn kop loopt, een FORM die langer is dan het
/// bestand, APEv1 — blijft onaangeroerd ([HoesUitkomst.nietTeLezen]). En vóór het vervangen leest dezelfde
/// lezer het nieuwe bestand terug: staat de nieuwe hoes er niet als eerste plaat in, dan blijft het oude.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'audioformaten.dart' show extensieVan;
import 'hoes_in_bestand.dart';

/// Welke schrijver bij een bestand hoort, op de extensie. Null: (nog) niet — m4a, ogg, wav, dsf, …
enum Hoesbak { flac, id3, aiff, ape }

Hoesbak? hoesbakVan(String pad) => switch (extensieVan(pad)) {
      '.flac' => Hoesbak.flac,
      '.mp3' => Hoesbak.id3,
      '.aif' || '.aiff' || '.aifc' => Hoesbak.aiff,
      '.wv' || '.ape' => Hoesbak.ape,
      _ => null,
    };

typedef _Uit = ({HoesUitkomst uitkomst, String? oud, String? reden});
typedef _Plaat = ({int soort, Uint8List beeld});

/// Wat een lezer in het bestand vond: de eerste plaat, of er een plaat is, en hoe het nieuwe bestand eruitziet
/// — stukken nieuwe bytes ([Uint8List]) en stukken van het origineel (`(van, tot)`), in volgorde.
typedef _Ontleed = ({String? fout, _Plaat? eerste, bool heeftPlaat, List<Object> Function()? stukken});

_Ontleed _fout(String reden) => (fout: reden, eerste: null, heeftPlaat: false, stukken: null);

int _be32(Uint8List d, int i) => (d[i] << 24) | (d[i + 1] << 16) | (d[i + 2] << 8) | d[i + 3];
int _le32(Uint8List d, int i) => d[i] | (d[i + 1] << 8) | (d[i + 2] << 16) | (d[i + 3] << 24);
int _ss(Uint8List d, int i) =>
    ((d[i] & 0x7F) << 21) | ((d[i + 1] & 0x7F) << 14) | ((d[i + 2] & 0x7F) << 7) | (d[i + 3] & 0x7F);
List<int> _be(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _le(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
List<int> _syncsafe(int v) => [(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F];

// ---------------------------------------------------------------------------------------------------- ID3v2

/// Eén frame van een ID3v2-kop: zijn naam, de bytes (kop meegerekend), en de plaat als het een leesbare APIC is.
typedef Id3Frame = ({String id, Uint8List bytes, ({int soort, Uint8List beeld})? plaat});

/// De frames van een ID3v2.3- of v2.4-kop ([tag] begint met "ID3"), en hoe lang die kop is — of null als we hem
/// niet helemaal begrijpen: v2.2 (andere frames: `PIC`, drie letters), een vlag in de kop (unsynchronisatie,
/// een uitgebreide kop, een voet), een frame dat voorbij de kop loopt, of iets anders dan nullen als opvulling.
@visibleForTesting
({int versie, int revisie, int lengte, List<Id3Frame> frames})? id3Frames(Uint8List tag) {
  if (tag.length < 10 || tag[0] != 0x49 || tag[1] != 0x44 || tag[2] != 0x33) return null;
  final versie = tag[3];
  if (versie != 3 && versie != 4) return null;
  if (tag[5] != 0) return null;
  final eind = 10 + _ss(tag, 6);
  if (eind > tag.length) return null;
  final frames = <Id3Frame>[];
  final naam = RegExp(r'^[A-Z0-9]{4}$');
  var i = 10;
  while (i + 10 <= eind && tag[i] != 0) {
    final id = String.fromCharCodes(tag, i, i + 4);
    if (!naam.hasMatch(id)) return null;
    // v2.3: vier gewone bytes; v2.4: syncsafe. Verwarren landt midden in een frame.
    final n = versie == 4 ? _ss(tag, i + 4) : _be32(tag, i + 4);
    if (i + 10 + n > eind) return null;
    final bytes = Uint8List.sublistView(tag, i, i + 10 + n);
    // Het tweede vlaggenbyte zegt hoe de inhoud bewaard is (gecomprimeerd, versleuteld, …): dan lezen we de
    // plaat niet, maar het frame gaat wel mee.
    final gewoon = tag[i + 9] == 0;
    frames.add((id: id, bytes: bytes, plaat: id == 'APIC' && gewoon ? _leesApic(Uint8List.sublistView(bytes, 10)) : null));
    i += 10 + n;
  }
  for (var j = i; j < eind; j++) {
    if (tag[j] != 0) return null;
  }
  return (versie: versie, revisie: tag[4], lengte: eind, frames: frames);
}

/// Soort en beeld van een APIC-lijf: tekstcodering, MIME (latin-1, met een nul), soort, omschrijving (in die
/// codering, met een nul — twee bij UTF-16), dan het beeld.
_Plaat? _leesApic(Uint8List d) {
  if (d.isEmpty || d[0] > 3) return null;
  final codering = d[0];
  var p = 1;
  while (p < d.length && d[p] != 0) {
    p++;
  }
  p++;
  if (p >= d.length) return null;
  final soort = d[p++];
  if (codering == 1 || codering == 2) {
    while (p + 1 < d.length && (d[p] != 0 || d[p + 1] != 0)) {
      p += 2;
    }
    p += 2;
  } else {
    while (p < d.length && d[p] != 0) {
      p++;
    }
    p++;
  }
  if (p >= d.length) return null;
  return (soort: soort, beeld: Uint8List.sublistView(d, p));
}

/// Een APIC-frame: latin-1, [mime], soort 3 (voorkant), geen omschrijving, het beeld.
Uint8List _apic(int versie, Uint8List beeld, String mime) {
  final lengte = 1 + mime.length + 1 + 1 + 1 + beeld.length;
  return (BytesBuilder(copy: false)
        ..add('APIC'.codeUnits)
        ..add(versie == 4 ? _syncsafe(lengte) : _be(lengte))
        ..add(const [0, 0, 0])
        ..add(ascii.encode(mime))
        ..add(const [0, 3, 0])
        ..add(beeld))
      .toBytes();
}

/// De nieuwe ID3v2-kop: de nieuwe voorkant op de plek van de eerste plaat (of achteraan), de oude voorkanten
/// (soort 3 en 0) weg, de rest byte voor byte en in volgorde, en opvulling tot precies [doel] bytes als dat past
/// — anders ruimte voor een volgende keer. Pure functie — zie de toetsen.
@visibleForTesting
Uint8List nieuweId3(
    {required int versie, required int revisie, required List<Id3Frame> frames, required Uint8List apic, required int doel}) {
  final kern = BytesBuilder(copy: false);
  var geplaatst = false;
  for (final f in frames) {
    if (f.id == 'APIC') {
      if (!geplaatst) {
        kern.add(apic);
        geplaatst = true;
      }
      final p = f.plaat;
      if (p != null && (p.soort == 3 || p.soort == 0)) continue;
    }
    kern.add(f.bytes);
  }
  if (!geplaatst) kern.add(apic);
  final k = kern.toBytes();
  final lengte = 10 + k.length <= doel ? doel : 10 + k.length + kHoesInBestandRuimte;
  return Uint8List(lengte)
    ..setAll(0, [0x49, 0x44, 0x33, versie, revisie, 0, ..._syncsafe(lengte - 10)])
    ..setAll(10, k);
}

_Plaat? _eerstePlaat(List<Id3Frame> frames) {
  for (final f in frames) {
    if (f.plaat != null) return f.plaat;
  }
  return null;
}

_Ontleed _leesMp3(RandomAccessFile raf, int grootte, Uint8List beeld, String mime) {
  final kop = raf.readSync(10);
  if (kop.length < 10) return _fout('te kort');
  if (kop[0] == 0x49 && kop[1] == 0x44 && kop[2] == 0x33) {
    final lengte = 10 + _ss(kop, 6);
    if (lengte > grootte) return _fout('de ID3-kop is langer dan het bestand');
    raf.setPositionSync(0);
    final t = id3Frames(raf.readSync(lengte));
    if (t == null) return _fout(kop[3] == 2 ? 'ID3v2.2' : 'een ID3-kop die we niet helemaal kennen');
    return (
      fout: null,
      eerste: _eerstePlaat(t.frames),
      heeftPlaat: t.frames.any((f) => f.id == 'APIC'),
      stukken: () => [
            nieuweId3(
                versie: t.versie, revisie: t.revisie, frames: t.frames, apic: _apic(t.versie, beeld, mime), doel: lengte),
            (lengte, grootte),
          ],
    );
  }
  // Zonder kop moet het met een mp3-frame beginnen (elf bits sync); anders weten we niet wat dit is.
  if (kop[0] != 0xFF || (kop[1] & 0xE0) != 0xE0) return _fout('geen ID3 en geen mp3-frame vooraan');
  return (
    fout: null,
    eerste: null,
    heeftPlaat: false,
    stukken: () => [
          nieuweId3(versie: 3, revisie: 0, frames: const [], apic: _apic(3, beeld, mime), doel: 0),
          (0, grootte),
        ],
  );
}

// ---------------------------------------------------------------------------------------------------- AIFF

_Ontleed _leesAiff(RandomAccessFile raf, int grootte, Uint8List beeld, String mime) {
  final kop = raf.readSync(12);
  if (kop.length < 12 || String.fromCharCodes(kop, 0, 4) != 'FORM') return _fout('geen FORM');
  final soort = String.fromCharCodes(kop, 8, 12);
  if (soort != 'AIFF' && soort != 'AIFC') return _fout('geen AIFF');
  final formEind = 8 + _be32(kop, 4);
  // Gezien op 22-10-2026 (Bow Wow): de FORM belooft 2,6 KB meer dan er staat — de ID3-chunk is afgekapt.
  if (formEind > grootte) return _fout('afgekapt: de FORM is langer dan het bestand');
  final chunks = <({String id, int van, int lengte, int tot})>[];
  var i = 12;
  while (i < formEind) {
    if (i + 8 > formEind) return _fout('een chunk-kop is afgekapt');
    raf.setPositionSync(i);
    final h = raf.readSync(8);
    final n = _be32(h, 4);
    final tot = i + 8 + n + (n & 1);
    if (tot > formEind) return _fout('een chunk loopt voorbij de FORM');
    chunks.add((id: String.fromCharCodes(h, 0, 4), van: i, lengte: n, tot: tot));
    i = tot;
  }
  final id3 = chunks.where((c) => c.id == 'ID3 ' || c.id == 'id3 ').toList();
  if (id3.length > 1) return _fout('twee ID3-chunks');

  Uint8List chunk(String id, Uint8List tag) => (BytesBuilder(copy: false)
        ..add(id.codeUnits)
        ..add(_be(tag.length))
        ..add(tag)
        ..add(tag.length.isOdd ? const [0] : const []))
      .toBytes();
  List<int> form(int lengte) => [...'FORM'.codeUnits, ..._be(lengte), ...soort.codeUnits];

  if (id3.isEmpty) {
    return (
      fout: null,
      eerste: null,
      heeftPlaat: false,
      stukken: () {
        final c = chunk('ID3 ', nieuweId3(versie: 3, revisie: 0, frames: const [], apic: _apic(3, beeld, mime), doel: 0));
        return [Uint8List.fromList(form(formEind - 8 + c.length)), (12, formEind), c, (formEind, grootte)];
      },
    );
  }
  final c = id3.single;
  raf.setPositionSync(c.van + 8);
  final data = raf.readSync(c.lengte);
  final t = id3Frames(data);
  if (t == null) return _fout('een ID3-kop die we niet helemaal kennen');
  // Na de kop, binnen de chunk: alleen nullen — anders zou het herschrijven iets weggooien.
  for (var j = t.lengte; j < data.length; j++) {
    if (data[j] != 0) return _fout('iets onbekends na de ID3-kop');
  }
  return (
    fout: null,
    eerste: _eerstePlaat(t.frames),
    heeftPlaat: t.frames.any((f) => f.id == 'APIC'),
    stukken: () {
      final nieuw = chunk(c.id,
          nieuweId3(versie: t.versie, revisie: t.revisie, frames: t.frames, apic: _apic(t.versie, beeld, mime), doel: c.lengte));
      return [
        Uint8List.fromList(form(formEind - 8 - (c.tot - c.van) + nieuw.length)),
        (12, c.van),
        nieuw,
        (c.tot, grootte),
      ];
    },
  );
}

// ---------------------------------------------------------------------------------------------------- APEv2

typedef _ApeItem = ({String sleutel, int vlaggen, Uint8List bytes, Uint8List waarde});

bool _isHoesItem(_ApeItem it) => (it.vlaggen >> 1) & 3 == 1 && it.sleutel.toLowerCase().startsWith('cover art');

/// Soort zoals in FLAC/ID3 — 3 voorkant, 4 achterkant, 6 de cd, 0 "Other" — en het beeld na de naam en zijn nul.
/// Een andere soort (`Cover Art (Artist)`, …) krijgt 20: die blijft altijd staan.
_Plaat? _apePlaat(_ApeItem it) {
  final s = it.sleutel.toLowerCase();
  final nul = it.waarde.indexOf(0);
  final beeld = Uint8List.sublistView(it.waarde, nul + 1);
  if (beeld.isEmpty) return null;
  final soort = s.contains('front')
      ? 3
      : s.contains('back')
          ? 4
          : s.contains('media')
              ? 6
              : s.contains('other')
                  ? 0
                  : 20;
  return (soort: soort, beeld: beeld);
}

/// Een oude voorkant (soort 3 of 0) die voor de nieuwe plaats maakt.
bool _oudeVoorkant(_ApeItem it) {
  if (!_isHoesItem(it)) return false;
  final s = _apePlaat(it)?.soort;
  return s == 3 || s == 0;
}

Uint8List _apeItem(String sleutel, int vlaggen, Uint8List waarde) => (BytesBuilder(copy: false)
      ..add(_le(waarde.length))
      ..add(_le(vlaggen))
      ..add(ascii.encode(sleutel))
      ..addByte(0)
      ..add(waarde))
    .toBytes();

/// Een APEv2-blok met kop en voet om [items] heen.
@visibleForTesting
Uint8List apeBlok(List<Uint8List> items) {
  final lijf = BytesBuilder(copy: false);
  for (final it in items) {
    lijf.add(it);
  }
  final l = lijf.toBytes();
  List<int> rand(int vlaggen) =>
      [...'APETAGEX'.codeUnits, ..._le(2000), ..._le(l.length + 32), ..._le(items.length), ..._le(vlaggen), 0, 0, 0, 0, 0, 0, 0, 0];
  return (BytesBuilder(copy: false)
        ..add(rand(0xA0000000)) // heeft een kop, dit is de kop
        ..add(l)
        ..add(rand(0x80000000))) // heeft een kop
      .toBytes();
}

_Ontleed _leesApe(RandomAccessFile raf, int grootte, Uint8List beeld, String mime) {
  var eind = grootte;
  if (grootte >= 128) {
    raf.setPositionSync(grootte - 128);
    if (String.fromCharCodes(raf.readSync(3)) == 'TAG') eind -= 128; // ID3v1 blijft achteraan
  }
  var tagVan = eind;
  final items = <_ApeItem>[];
  if (eind >= 32) {
    raf.setPositionSync(eind - 32);
    final voet = raf.readSync(32);
    if (String.fromCharCodes(voet, 0, 8) == 'APETAGEX') {
      if (_le32(voet, 8) != 2000) return _fout('APEv1');
      final lengte = _le32(voet, 12), aantal = _le32(voet, 16), vlaggen = _le32(voet, 20);
      final itemsVan = eind - lengte;
      final metKop = vlaggen & 0x80000000 != 0;
      tagVan = itemsVan - (metKop ? 32 : 0);
      if (lengte < 32 || tagVan < 0) return _fout('een APE-voet die niet klopt');
      if (metKop) {
        raf.setPositionSync(tagVan);
        if (String.fromCharCodes(raf.readSync(8)) != 'APETAGEX') return _fout('de APE-kop ontbreekt');
      }
      raf.setPositionSync(itemsVan);
      final d = raf.readSync(lengte - 32);
      var p = 0;
      for (var k = 0; k < aantal; k++) {
        if (p + 9 > d.length) return _fout('de APE-items kloppen niet');
        final n = _le32(d, p), v = _le32(d, p + 4);
        var q = p + 8;
        while (q < d.length && d[q] != 0) {
          q++;
        }
        if (q >= d.length || q == p + 8 || q + 1 + n > d.length) return _fout('de APE-items kloppen niet');
        items.add((
          sleutel: latin1.decode(Uint8List.sublistView(d, p + 8, q)),
          vlaggen: v,
          bytes: Uint8List.sublistView(d, p, q + 1 + n),
          waarde: Uint8List.sublistView(d, q + 1, q + 1 + n),
        ));
        p = q + 1 + n;
      }
      if (p != d.length) return _fout('de APE-items kloppen niet');
    }
  }
  // Wat de bibliotheek leest (audio_metadata_reader): het eerste "Cover Art …"-item.
  _Plaat? eerste;
  for (final it in items.where(_isHoesItem)) {
    eerste = _apePlaat(it);
    if (eerste != null) break;
  }
  return (
    fout: null,
    eerste: eerste,
    heeftPlaat: items.any(_isHoesItem),
    stukken: () {
      final naam = ascii.encode('Cover Art (Front)${mime == 'image/png' ? '.png' : '.jpg'}');
      final nieuw = <Uint8List>[
        _apeItem('Cover Art (Front)', 2, Uint8List.fromList([...naam, 0, ...beeld])), // 2 = binair
        for (final it in items)
          if (!_oudeVoorkant(it)) it.bytes,
      ];
      return [(0, tagVan), apeBlok(nieuw), (eind, grootte)];
    },
  );
}

// ---------------------------------------------------------------------------------------------------- schrijven

/// Leest met [lees], schrijft het nieuwe bestand ernaast, leest het met dezelfde lezer terug, en zet het pas dan
/// over het origineel — met de oude datum. Zelfde controles als [schrijfVoorkantInFlac].
_Uit _herschrijf(String pad, Uint8List beeld, bool alleenAlsLeeg, String? bewaarOud,
    _Ontleed Function(RandomAccessFile raf, int grootte, Uint8List beeld, String mime) lees) {
  final k = beeldKenmerk(beeld);
  if (k == null) return (uitkomst: HoesUitkomst.nietTeLezen, oud: null, reden: 'geen JPEG of PNG');
  final f = File(pad);
  RandomAccessFile? raf;
  File? tmp;
  try {
    final st = f.statSync();
    if (st.mode & 0x92 == 0) return (uitkomst: HoesUitkomst.alleenLezen, oud: null, reden: null);
    raf = f.openSync();
    final grootte = raf.lengthSync();
    final o = lees(raf, grootte, beeld, k.mime);
    if (o.fout != null) return (uitkomst: HoesUitkomst.nietTeLezen, oud: null, reden: o.fout);
    final eerste = o.eerste;
    if (eerste != null && listEquals(eerste.beeld, beeld)) return (uitkomst: HoesUitkomst.alGelijk, oud: null, reden: null);
    if (alleenAlsLeeg && o.heeftPlaat) return (uitkomst: HoesUitkomst.heeftAlEen, oud: null, reden: null);
    final oud = bewaarOud != null && eerste != null && (eerste.soort == 3 || eerste.soort == 0)
        ? bewaarOudeVoorkant(eerste.beeld, bewaarOud)
        : null;

    tmp = File('$pad.hoes');
    var verwacht = 0;
    final uit = tmp.openSync(mode: FileMode.write);
    try {
      for (final s in o.stukken!()) {
        if (s is Uint8List) {
          uit.writeFromSync(s);
          verwacht += s.length;
          continue;
        }
        final (van, tot) = s as (int, int);
        raf.setPositionSync(van);
        var rest = tot - van;
        while (rest > 0) {
          final stuk = raf.readSync(rest < 8 << 20 ? rest : 8 << 20);
          if (stuk.isEmpty) throw const FileSystemException('audio korter dan verwacht');
          uit.writeFromSync(stuk);
          rest -= stuk.length;
        }
        verwacht += tot - van;
      }
      uit.flushSync();
    } finally {
      uit.closeSync();
    }
    raf.closeSync();
    raf = null;

    // Terug lezen met dezelfde lezer: de nieuwe hoes moet de eerste plaat zijn.
    final terug = tmp.openSync();
    _Ontleed t;
    try {
      t = lees(terug, terug.lengthSync(), beeld, k.mime);
    } finally {
      terug.closeSync();
    }
    final nu = f.statSync();
    if (t.fout != null || t.eerste == null || !listEquals(t.eerste!.beeld, beeld)) {
      tmp.deleteSync();
      return (uitkomst: HoesUitkomst.mislukt, oud: oud, reden: 'controle: de nieuwe hoes staat er niet goed in');
    }
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

/// Legt [beeld] als voorkant in de mp3 op [pad] (ID3v2) — zie de uitleg bovenaan. Synchroon, voor een isolate.
({HoesUitkomst uitkomst, String? oud, String? reden}) schrijfVoorkantInMp3(String pad, Uint8List beeld,
        {bool alleenAlsLeeg = false, String? bewaarOud}) =>
    _herschrijf(pad, beeld, alleenAlsLeeg, bewaarOud, _leesMp3);

/// Legt [beeld] als voorkant in de AIFF op [pad] (de `ID3 `-chunk) — zie de uitleg bovenaan.
({HoesUitkomst uitkomst, String? oud, String? reden}) schrijfVoorkantInAiff(String pad, Uint8List beeld,
        {bool alleenAlsLeeg = false, String? bewaarOud}) =>
    _herschrijf(pad, beeld, alleenAlsLeeg, bewaarOud, _leesAiff);

/// Legt [beeld] als voorkant in de WavPack of Monkey's Audio op [pad] (APEv2) — zie de uitleg bovenaan.
({HoesUitkomst uitkomst, String? oud, String? reden}) schrijfVoorkantInApe(String pad, Uint8List beeld,
        {bool alleenAlsLeeg = false, String? bewaarOud}) =>
    _herschrijf(pad, beeld, alleenAlsLeeg, bewaarOud, _leesApe);
