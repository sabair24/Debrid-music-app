/// Beschrijvingen in het Nederlands, één keer per tekst vertaald en bewaard.
///
/// **Waarom.** Saber, 16-10-2026: de beschrijving bij een album is vaak Engels ("V is the fifth album
/// by the band Live…"). TheAudioDB heeft soms een Nederlandse (`strDescriptionNL`), meestal niet. Hij
/// koos: vertalen op de pc met de AI, één keer per album, en daarna meteen.
///
/// **Waar het gebeurt.** Op de pc zit de sleutel; daar vertaalt [vraag] rechtstreeks via `AiService`.
/// Een toestel vraagt het de pc (`/api/vertaal`) — dezelfde afspraak als de radio uit een zin. Beide
/// kanten bewaren de vertaling: in het geheugen en in `vertalingen/` naast de andere caches, onder een
/// sleutel van de tekst zelf. Een gewijzigde beschrijving is dus vanzelf een nieuwe vraag.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class Vertaler {
  Vertaler._();

  /// Eén voor de hele app; wordt bij het opstarten ingericht.
  static final instantie = Vertaler._();

  /// Hoe een tekst vertaald wordt: op de pc via de AI, op een toestel via de pc. Null = niet mogelijk.
  Future<String?> Function(String tekst)? vraag;

  /// Waar vertalingen op schijf staan. Null = alleen in het geheugen (toetsen).
  String? map;

  final _geheugen = <String, String>{};
  final _bezig = <String, Future<String?>>{};

  /// De vertaling als die er al is (geheugen), zonder te wachten. Voor het eerste beeld.
  String? alKlaar(String tekst) => _geheugen[vertaalSleutel(tekst)];

  /// [tekst] in het Nederlands, of null als dat niet lukt. Een tekst die al Nederlands is, komt
  /// ongewijzigd terug; dezelfde vraag die al loopt, wordt niet een tweede keer gesteld.
  Future<String?> naarNederlands(String tekst) {
    final t = tekst.trim();
    if (t.isEmpty || lijktNederlands(t)) return Future.value(t);
    final k = vertaalSleutel(t);
    final klaar = _geheugen[k];
    if (klaar != null) return Future.value(klaar);
    // Met accolades: `() => _bezig.remove(k)` geeft de future van whenComplete zelf terug, en dan
    // wacht hij op zichzelf en komt hij nooit klaar.
    return _bezig[k] ??= _haal(k, t).whenComplete(() {
      _bezig.remove(k);
    });
  }

  Future<String?> _haal(String k, String t) async {
    final m = map;
    final bestand = m == null ? null : File('$m${Platform.pathSeparator}$k.txt');
    try {
      if (bestand != null && await bestand.exists()) {
        final op = await bestand.readAsString();
        if (op.trim().isNotEmpty) return _geheugen[k] = op;
      }
    } catch (_) {/* dan opnieuw vragen */}
    final v = vraag;
    if (v == null) return null;
    String? uit;
    try {
      uit = (await v(t))?.trim();
    } catch (_) {
      return null;
    }
    if (uit == null || uit.isEmpty) return null;
    _geheugen[k] = uit;
    if (bestand != null) {
      try {
        await bestand.parent.create(recursive: true);
        await bestand.writeAsString(uit, flush: true);
      } catch (_) {/* niet bewaard is niet erg: hij staat in het geheugen */}
    }
    return uit;
  }
}

/// De sleutel waaronder een vertaling bewaard wordt: FNV-1a over de tekst, 64 bits in hex.
String vertaalSleutel(String tekst) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(tekst.trim())) {
    h ^= b;
    h *= 0x100000001b3; // loopt rond op 64 bits, zoals FNV hoort
  }
  String half(int x) => (x & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return 'v1-${half(h >> 32)}${half(h)}';
}

final _woordRe = RegExp(r"[a-zà-ÿ']+");

const _nl = {
  'de', 'het', 'een', 'en', 'van', 'is', 'op', 'met', 'voor', 'die', 'dat', 'zijn', 'werd', 'door', 'als',
  'ook', 'uit', 'naar', 'bij', 'om', 'maar', 'hun', 'haar', 'deze', 'nummer', 'nummers', 'album',
};
const _en = {
  'the', 'a', 'an', 'and', 'of', 'is', 'on', 'with', 'for', 'that', 'was', 'by', 'as', 'it', 'from', 'to',
  'in', 'which', 'their', 'his', 'her', 'released', 'single', 'singles', 'band', 'record',
};

/// Is [tekst] al Nederlands? Telt veelvoorkomende woorden van beide talen.
///
/// Geen taaldetectie maar genoeg voor dit doel: een beschrijving van een plaat heeft er tientallen,
/// en een Engelse heeft veel meer "the", "of" en "was" dan "de", "het" en "werd".
bool lijktNederlands(String tekst) {
  var nl = 0, en = 0;
  for (final m in _woordRe.allMatches(tekst.toLowerCase())) {
    final w = m[0]!;
    if (_nl.contains(w)) nl++;
    if (_en.contains(w)) en++;
  }
  return nl > en;
}
