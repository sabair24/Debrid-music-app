/// Een `.torrent` zelf lezen: welke bestanden zitten erin, en hoe groot zijn ze.
///
/// **Waarom de app dit zelf doet.** De nummerkeuze wachtte tot TorBox de torrent had opgehaald —
/// eerst de metadata, dan de bestandslijst. Dat kostte in het gunstige geval een halve minuut, en op
/// 23-08-2026 kostte het niets minder dan alles: TorBox' API lag eruit en er kwam nooit een lijst.
/// Terwijl die lijst gewoon IN het torrentbestand staat dat we op dat moment al op de schijf hadden.
///
/// Bencode is klein genoeg om hier te lezen en te groot om te gokken: een half gelezen lijst geeft
/// een nummerkeuze die het verkeerde bestand aanvinkt, en `--select-file` bij aria2 telt op dezelfde
/// volgorde. Vandaar de toetsen ernaast.
library;

import 'dart:convert';

/// Eén bestand in een torrent.
class TorrentBestand {
  /// De plaats in de torrent, **vanaf 1 geteld** — dat is de nummering die aria2 gebruikt voor
  /// `--select-file`, en de reden dat dit veld hier zit in plaats van in de lus die het opvraagt.
  final int index;

  /// Het pad binnen de torrent, met `/` ertussen, zoals het in het bestand staat.
  final String pad;
  final int grootte;

  const TorrentBestand(this.index, this.pad, this.grootte);

  /// De laatste stap van het pad — wat je in een lijstje wil zien.
  String get naam {
    final i = pad.lastIndexOf('/');
    return i < 0 ? pad : pad.substring(i + 1);
  }

  String get _ext {
    final i = naam.lastIndexOf('.');
    return i < 0 ? '' : naam.substring(i + 1).toLowerCase();
  }

  bool get isAudio => const {'flac', 'mp3', 'm4a', 'aac', 'ogg', 'opus', 'wav', 'alac', 'ape', 'wv'}
      .contains(_ext);
}

/// Wat er in een torrent zit.
class TorrentInhoud {
  final String naam;
  final List<TorrentBestand> bestanden;
  const TorrentInhoud(this.naam, this.bestanden);

  int get totaleGrootte => bestanden.fold(0, (s, f) => s + f.grootte);
  List<TorrentBestand> get audio => bestanden.where((f) => f.isAudio).toList();

  /// Lees een `.torrent`. Geeft null als het er geen is — een ingelogde-pagina, een foutmelding of
  /// een halve download komen hier langs, en die mogen niet als lege torrent doorgaan.
  static TorrentInhoud? lees(List<int> bytes) {
    try {
      final wortel = _Bencode(bytes).lees();
      if (wortel is! Map) return null;
      final info = wortel['info'];
      if (info is! Map) return null;
      final naam = _tekst(info['name']) ?? 'torrent';

      final lijst = info['files'];
      if (lijst is! List) {
        // Eén bestand: de torrentnaam ís de bestandsnaam.
        final lengte = info['length'];
        if (lengte is! int) return null;
        return TorrentInhoud(naam, [TorrentBestand(1, naam, lengte)]);
      }

      final uit = <TorrentBestand>[];
      for (var i = 0; i < lijst.length; i++) {
        final f = lijst[i];
        if (f is! Map) continue;
        final delen = (f['path'] as List?) ?? const [];
        final pad = delen.map((d) => _tekst(d) ?? '').where((s) => s.isNotEmpty).join('/');
        final lengte = f['length'];
        if (pad.isEmpty || lengte is! int) continue;
        // Doortellen op i + 1 en niet op uit.length: aria2 telt de bestanden zoals ze in de torrent
        // staan, ook de rare. Zou een overgeslagen regel de nummering opschuiven, dan haalt
        // `--select-file` stilzwijgend het verkeerde nummer binnen.
        uit.add(TorrentBestand(i + 1, pad, lengte));
      }
      return uit.isEmpty ? null : TorrentInhoud(naam, uit);
    } catch (_) {
      return null;
    }
  }

  /// Bencode-tekst is een rij bytes zonder beloofde codering. RuTracker zet er windows-1251 in;
  /// `allowMalformed` maakt daar een vraagteken van in plaats van een uitzondering, want een
  /// vreemde letter in een titel is geen reden om een hele plaat te laten vallen.
  static String? _tekst(dynamic v) => v is List<int> ? utf8.decode(v, allowMalformed: true) : null;
}

/// De lezer zelf. Vier vormen: getal, tekst, lijst, woordenboek.
class _Bencode {
  _Bencode(this._b);
  final List<int> _b;
  int _i = 0;

  static const _i0 = 0x69; // 'i'
  static const _l = 0x6c; // 'l'
  static const _d = 0x64; // 'd'
  static const _e = 0x65; // 'e'
  static const _dubbelePunt = 0x3a; // ':'

  dynamic lees() {
    if (_i >= _b.length) throw const FormatException('leeg');
    final c = _b[_i];
    if (c == _i0) return _getal();
    if (c == _l) return _lijst();
    if (c == _d) return _woordenboek();
    return _tekst();
  }

  int _getal() {
    _i++; // i
    final eind = _b.indexOf(_e, _i);
    if (eind < 0) throw const FormatException('getal zonder einde');
    final n = int.parse(String.fromCharCodes(_b.sublist(_i, eind)));
    _i = eind + 1;
    return n;
  }

  List<int> _tekst() {
    final punt = _b.indexOf(_dubbelePunt, _i);
    if (punt < 0) throw const FormatException('tekst zonder lengte');
    final lengte = int.parse(String.fromCharCodes(_b.sublist(_i, punt)));
    final start = punt + 1;
    if (start + lengte > _b.length) throw const FormatException('tekst loopt buiten het bestand');
    _i = start + lengte;
    return _b.sublist(start, start + lengte);
  }

  List<dynamic> _lijst() {
    _i++; // l
    final uit = <dynamic>[];
    while (_i < _b.length && _b[_i] != _e) {
      uit.add(lees());
    }
    _i++; // e
    return uit;
  }

  Map<String, dynamic> _woordenboek() {
    _i++; // d
    final uit = <String, dynamic>{};
    while (_i < _b.length && _b[_i] != _e) {
      final sleutel = utf8.decode(_tekst(), allowMalformed: true);
      uit[sleutel] = lees();
    }
    _i++; // e
    return uit;
  }
}
