/// Suggesties terwijl je typt: wat er in het paneel staat, zonder één widget.
///
/// **Waarom dit bestaat.** Saber, 08-11-2026: *"ik wil bij zoeken ook direct suggesties zien, bij het typen van artiesten,
/// liedjes, album"*. Zijn keuzes staan bij [mengSuggesties] en [ZoekRecent]; het paneel zelf staat in `ui/zoek_paneel.dart`.
///
/// **Waar de suggesties vandaan komen.** Je eigen bibliotheek (meteen, ook zonder internet) en Deezer, zodra je even stopt
/// met typen. Nooit Soulseek of TIDAL: die zijn te traag om mee te typen, en elke letter zou afgaan van de zoekgrens die ook
/// de radio en de cd-jacht gebruiken (`zoekgrens.dart`). Deezers eigen `search/autocomplete` ook niet: gemeten op
/// 08-11-2026 0,3–0,8 s en 56 KB per vraag, tegen 0,17–0,27 s en 3,3 KB (gzip) voor de drie gewone vragen samen.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'models.dart';
import 'organize.dart';
import 'radiokeuze.dart' show eigenSleutel;

/// Zo lang na de laatste letter gaat de vraag naar Deezer. Korter dan een denkpauze, langer dan de tijd tussen twee letters.
const kSuggestieOnlinePauze = Duration(milliseconds: 220);

/// Zo lang na een letter wordt je eigen bibliotheek doorzocht: wie doortypt, krijgt één ronde in plaats van tien.
const kSuggestieEigenPauze = Duration(milliseconds: 40);

/// Vanaf zoveel letters gaat er een vraag naar Deezer. Eén letter zegt niets, en zou alleen data kosten.
const int kSuggestieMinOnline = 2;

/// Vanaf zoveel letters mag er één letter fout zijn. Bij "kha" is alles dat op één letter na lijkt, ruis.
const int kTypfoutVanaf = 4;

/// Hoeveel antwoorden van Deezer er bewaard blijven, zodat wissen en opnieuw typen niets kost.
const int kSuggestieGeheugen = 40;

enum SuggestieSoort { artiest, album, nummer }

/// Eén rij in het paneel.
class Suggestie {
  const Suggestie({
    required this.soort,
    required this.sleutel,
    required this.titel,
    required this.onder,
    required this.eigen,
    required this.score,
    this.album,
    this.track,
    this.onlineArtiest,
    this.onlineAlbum,
    this.onlineNummer,
    this.beeldUrl,
  });

  final SuggestieSoort soort;

  /// Dezelfde artiest, plaat of opname heeft dezelfde sleutel, uit je bibliotheek of van Deezer ([mengSuggesties]).
  final String sleutel;
  final String titel;
  final String onder;

  /// Staat in je bibliotheek.
  final bool eigen;

  /// Hoe goed dit past bij wat je typte; zie [trefScore].
  final double score;

  /// Uit je bibliotheek: de plaat, en bij een nummer ook het nummer.
  final Album? album;
  final Track? track;

  /// Van Deezer. Staat het ook in je bibliotheek, dan blijft hier toch de foto of hoes voor als jouw kopie er (nog) geen
  /// heeft, zoals op een gsm die de hoezen nog niet binnen heeft.
  final CatalogArtist? onlineArtiest;
  final CatalogAlbumHit? onlineAlbum;
  final CatalogTrackHit? onlineNummer;

  /// De kleine foto of hoes van Deezer, of null.
  final String? beeldUrl;

  Suggestie metOnline(Suggestie o, double nieuweScore) => Suggestie(
        soort: soort,
        sleutel: sleutel,
        titel: titel,
        onder: onder,
        eigen: eigen,
        score: nieuweScore,
        album: album,
        track: track,
        onlineArtiest: o.onlineArtiest,
        onlineAlbum: o.onlineAlbum,
        onlineNummer: o.onlineNummer,
        beeldUrl: o.beeldUrl,
      );
}

/// Eén kop in het paneel met zijn rijen.
class Suggestiegroep {
  const Suggestiegroep(this.soort, this.rijen);
  final SuggestieSoort soort;
  final List<Suggestie> rijen;

  String get naam => switch (soort) {
        SuggestieSoort.artiest => 'Artiesten',
        SuggestieSoort.album => 'Albums',
        SuggestieSoort.nummer => 'Nummers',
      };
}

/// De kleinste hoes die er scherp uitziet in een rij van 40 punten op een telefoon: 120×120 is 4,8 KB, de "medium" van
/// Deezer 15,4 KB (gemeten op 08-11-2026). Deezers beeldserver maakt elke maat; een ander adres blijft zoals het is.
String? kleinDeezerBeeld(String? url) {
  if (url == null || url.isEmpty) return url;
  if (!url.contains('dzcdn.net')) return url;
  return url.replaceFirst(RegExp(r'/\d+x\d+-'), '/120x120-');
}

/// Is [a] op hoogstens één letter na [b]: één erbij, één weg, één anders of twee omgewisseld?
bool opEenLetterNa(String a, String b) {
  if (a == b) return true;
  final la = a.length, lb = b.length;
  if ((la - lb).abs() > 1) return false;
  if (la == lb) {
    final anders = <int>[];
    for (var i = 0; i < la; i++) {
      if (a.codeUnitAt(i) != b.codeUnitAt(i)) {
        anders.add(i);
        if (anders.length > 2) return false;
      }
    }
    if (anders.length == 1) return true;
    return anders.length == 2 &&
        anders[1] == anders[0] + 1 &&
        a.codeUnitAt(anders[0]) == b.codeUnitAt(anders[1]) &&
        a.codeUnitAt(anders[1]) == b.codeUnitAt(anders[0]);
  }
  final kort = la < lb ? a : b, lang = la < lb ? b : a;
  var i = 0;
  while (i < kort.length && kort.codeUnitAt(i) == lang.codeUnitAt(i)) {
    i++;
  }
  return kort.substring(i) == lang.substring(i + 1);
}

/// Lijkt [q] op hoogstens één letter na op het begin van [woord]? Zo vindt "rihan" met een typfout ook "Rihanna" terwijl je
/// nog typt, en niet pas als het hele woord er staat.
bool beginLijktOp(String woord, String q) {
  if (q.length < kTypfoutVanaf || woord.length + 1 < q.length) return false;
  for (final lengte in [q.length - 1, q.length, q.length + 1]) {
    if (lengte > woord.length) continue;
    // Een tekst die maar één letter langer is dan het begin dat hij vervangt, heeft dat begin al als prefix getest; hier
    // alleen wat echt anders is. De eerste letter telt mee: wie de eerste letter fout heeft, zoekt zelden dit woord.
    if (woord.codeUnitAt(0) != q.codeUnitAt(0)) continue;
    if (opEenLetterNa(woord.substring(0, lengte), q)) return true;
  }
  return false;
}

/// Hoe goed past [naam] bij wat je typte? Beide al door [normKey] gehaald.
///
/// 1,0 precies · 0,9 begint ermee · 0,8 een woord begint ermee · 0,6 zonder leestekens ("backstreets" in "Backstreet's")
/// · 0,5 ergens midden in een woord (vanaf drie letters) · 0,4 op één letter na · 0 past niet.
double trefScore(String naam, String q, {bool typfout = true}) => _Vraag(q).score(naam, naam.replaceAll(' ', ''), typfout);

/// Wat je typte, klaargezet voor heel veel vergelijkingen. Gemeten op 08-11-2026 met 20.000 nummers: 300 ms per letter toen er
/// per naam nog tekst werd aangemaakt en elke treffer een eigen rij kreeg; dit draait op de hoofddraad, terwijl je typt.
class _Vraag {
  _Vraag(this.q)
      : spatieQ = ' $q',
        platQ = q.replaceAll(' ', '');
  final String q, spatieQ, platQ;

  double score(String naam, String plat, bool typfout, [List<String>? woorden]) {
    if (q.isEmpty || naam.isEmpty) return 0;
    if (naam == q) return 1;
    if (naam.startsWith(q)) return .9;
    if (naam.contains(spatieQ)) return .8;
    if (platQ.length >= 3 && plat.startsWith(platQ)) return .6;
    if (q.length >= 3 && naam.contains(q)) return .5;
    if (typfout && q.length >= kTypfoutVanaf) {
      for (final w in woorden ?? naam.split(' ')) {
        if (beginLijktOp(w, q)) return .4;
      }
      // "rihana" tegen "rihanna" zit hierboven al; dit is de hele naam met spaties erin ("daftpunk", "daft punc").
      if (beginLijktOp(naam, q)) return .4;
    }
    return 0;
  }
}

/// Past [q] op een nummer of plaat, als je er ook de artiest bij typt ("daft get", "rihanna umbrella")? Elk woord van [q] moet
/// het begin zijn van een woord in de titel of de artiest. 0,7: minder dan de titel zelf, meer dan een nummer van wie je
/// alleen de naam typte.
double woordenPassen(String titel, String artiest, String q) {
  if (!q.contains(' ')) return 0;
  final woorden = '$titel $artiest'.split(' ');
  for (final d in q.split(' ')) {
    if (d.isEmpty) continue;
    if (!woorden.any((w) => w.startsWith(d))) return 0;
  }
  return .7;
}

/// Eén nummer of plaat met zijn voorgerekende tekst, zodat een letter niet elke keer alles opnieuw hoeft te vouwen.
class _Regel {
  _Regel(this.soort, this.titel, this.artiest, this.album, this.track)
      : nTitel = normKey(titel),
        nArtiest = artistKey(artiest) {
    pTitel = nTitel.replaceAll(' ', '');
    pArtiest = nArtiest.replaceAll(' ', '');
  }
  final SuggestieSoort soort;
  final String titel, artiest;
  final Album? album;
  final Track? track;
  final String nTitel, nArtiest;
  late final String pTitel, pArtiest;
  late final List<String> wTitel = nTitel.split(' ');
  late final List<String> wArtiest = nArtiest.split(' ');

  late final String sleutel = switch (soort) {
        SuggestieSoort.artiest => 'a:$nArtiest',
        SuggestieSoort.album => 'p:$nArtiest|$nTitel',
        SuggestieSoort.nummer => 'n:${eigenSleutel(artiest, titel)}',
      };
}

/// Je bibliotheek, klaar om doorzocht te worden. Eén keer per stand van de bibliotheek opgebouwd ([van]).
class EigenIndex {
  EigenIndex._(this.bron, this._artiesten, this._albums, this._nummers);

  static final leeg = EigenIndex._(const [], const [], const [], const []);

  /// De lijst waaruit dit gebouwd is: `albums` van de bibliotheek krijgt bij elke herbouw een nieuwe lijst.
  final List<Album> bron;
  final List<_Regel> _artiesten, _albums, _nummers;

  factory EigenIndex.van(List<Album> albums) {
    final artiesten = <String, _Regel>{};
    final platen = <_Regel>[];
    final nummers = <_Regel>[];
    for (final a in albums) {
      final naam = a.artist.trim();
      if (naam.isNotEmpty) artiesten.putIfAbsent(artistKey(naam), () => _Regel(SuggestieSoort.artiest, naam, naam, a, null));
      // Een losse single is hier geen plaat: hij staat al als nummer in de lijst.
      if (!a.isSingle && a.title.trim().isNotEmpty) platen.add(_Regel(SuggestieSoort.album, a.title, a.artist, a, null));
      for (final t in a.tracks) {
        if (t.title.trim().isEmpty) continue;
        nummers.add(_Regel(SuggestieSoort.nummer, t.title, t.artist, a, t));
      }
    }
    return EigenIndex._(albums, artiesten.values.toList(growable: false), platen, nummers);
  }
}

Suggestie _rijVan(_Regel r, double score) => Suggestie(
      soort: r.soort,
      sleutel: r.sleutel,
      titel: r.titel,
      onder: switch (r.soort) {
        SuggestieSoort.artiest => 'Artiest · in je bibliotheek',
        SuggestieSoort.album => r.artiest + (r.album?.year == null ? '' : ' · ${r.album!.year}'),
        SuggestieSoort.nummer => r.artiest,
      },
      eigen: true,
      score: score,
      album: r.album,
      track: r.track,
    );

double _scoreVan(_Regel r, _Vraag v, bool typfout) {
  final eigen = v.score(r.nTitel, r.pTitel, typfout, r.wTitel);
  if (r.soort == SuggestieSoort.artiest || eigen >= .7) return eigen;
  final samen = woordenPassen(r.nTitel, r.nArtiest, v.q);
  if (samen > eigen) return samen;
  // Een nummer of plaat van de artiest die je typt: lager dan wat zelf zo heet, want "halo" is eerst het nummer Halo.
  final vanArtiest = v.score(r.nArtiest, r.pArtiest, typfout, r.wArtiest) * .7;
  return vanArtiest > eigen ? vanArtiest : eigen;
}

/// Wat er in je bibliotheek past bij [tekst], per soort, de beste eerst.
///
/// Hoogstens [perSoort] per soort, want meer past niet in een paneel; dat scheelt ook het sorteren van een bibliotheek vol
/// "Khaled"-nummers bij elke letter. Eén letter fout mag ([kTypfoutVanaf]), maar alleen als het precies zoeken te weinig
/// vond: anders staat er bij "halo" opeens "hallo" tussen, en het kost per letter de hele bibliotheek opnieuw.
List<Suggestie> eigenSuggesties(EigenIndex index, String tekst, {int perSoort = 8}) {
  final q = normKey(tekst);
  if (q.isEmpty) return const [];
  final vraag = _Vraag(q);
  final uit = <Suggestie>[];
  for (final lijst in [index._artiesten, index._albums, index._nummers]) {
    final raak = <(_Regel, double)>[];
    void ronde(bool typfout) {
      raak.clear();
      for (final r in lijst) {
        final s = _scoreVan(r, vraag, typfout);
        if (s > 0) raak.add((r, s));
      }
    }

    ronde(false);
    if (raak.length < 3 && q.length >= kTypfoutVanaf) ronde(true);
    raak.sort((a, b) => b.$2.compareTo(a.$2));
    // Pas nu de rijen, en alleen wat in het paneel past: dubbele komen hier pas aan bod.
    final gezien = <String>{};
    for (final (r, s) in raak) {
      if (!gezien.add(r.sleutel)) continue;
      uit.add(_rijVan(r, s));
      if (gezien.length >= perSoort) break;
    }
  }
  return uit;
}

/// Wat Deezer antwoordde, als rijen. Staat een rij hoog bij Deezer, dan past hij beter: bij gelijke tekst wint de volgorde
/// van Deezer, en dat is vooral wie het meest beluisterd wordt.
List<Suggestie> onlineSuggesties(OnlineTreffers t, String tekst) {
  final q = normKey(tekst);
  double score(String titel, String artiest, int plek) {
    final a = artistKey(artiest), n = normKey(titel);
    final s = [trefScore(n, q), woordenPassen(n, a, q), trefScore(a, q) * .7, .3].reduce((x, y) => x > y ? x : y);
    return s - plek * .002;
  }

  return [
    for (final (i, a) in t.artiesten.indexed)
      Suggestie(
        soort: SuggestieSoort.artiest,
        sleutel: 'a:${artistKey(a.name)}',
        titel: a.name,
        onder: 'Artiest',
        eigen: false,
        score: () {
          final n = artistKey(a.name);
          final s = trefScore(n, q);
          return (s > .3 ? s : .3) - i * .002;
        }(),
        onlineArtiest: a,
        beeldUrl: kleinDeezerBeeld(a.picture),
      ),
    for (final (i, h) in t.albums.indexed)
      Suggestie(
        soort: SuggestieSoort.album,
        sleutel: 'p:${artistKey(h.artist)}|${normKey(h.album.title)}',
        titel: h.album.title,
        onder: h.artist + (jaarVan(h.album.releaseDate) == null ? '' : ' · ${jaarVan(h.album.releaseDate)}'),
        eigen: false,
        score: score(h.album.title, h.artist, i),
        onlineAlbum: h,
        beeldUrl: kleinDeezerBeeld(h.album.cover),
      ),
    for (final (i, n) in t.nummers.indexed)
      Suggestie(
        soort: SuggestieSoort.nummer,
        sleutel: 'n:${eigenSleutel(n.artist, n.title)}',
        titel: n.title,
        onder: n.artist,
        eigen: false,
        score: score(n.title, n.artist, i),
        onlineNummer: n,
        beeldUrl: kleinDeezerBeeld(n.cover),
      ),
  ];
}

String? jaarVan(String? datum) => datum == null || datum.length < 4 ? null : datum.substring(0, 4);

/// Je bibliotheek en Deezer tot de groepen in het paneel.
///
/// **Beste treffer eerst.** Saber koos op 08-11-2026 "Beste treffer eerst" en niet "Eerst wat je hebt": wat het best bij je
/// letters past staat bovenaan, of je het nu hebt of niet. Dat geldt binnen een groep, en ook voor de groepen: bij "halo" gaan
/// de nummers boven de artiesten. Alleen bij gelijke stand gaat jouw kopie voor.
///
/// Wat in allebei zit, is één rij: met een vinkje, want het is van jou, en met de hoes van Deezer erbij voor als jouw kopie
/// er geen heeft.
List<Suggestiegroep> mengSuggesties(
  List<Suggestie> eigen,
  List<Suggestie> online, {
  int maxArtiesten = 4,
  int maxAlbums = 3,
  int maxNummers = 4,
}) {
  final samen = <String, Suggestie>{for (final e in eigen) e.sleutel: e};
  for (final o in online) {
    final al = samen[o.sleutel];
    if (al == null) {
      samen[o.sleutel] = o;
    } else if (al.eigen) {
      samen[o.sleutel] = al.metOnline(o, al.score > o.score ? al.score : o.score);
    }
  }
  int beste(Suggestie a, Suggestie b) {
    final s = b.score.compareTo(a.score);
    if (s != 0) return s;
    if (a.eigen != b.eigen) return a.eigen ? -1 : 1;
    return 0;
  }

  Suggestiegroep groep(SuggestieSoort soort, int max) =>
      Suggestiegroep(soort, (samen.values.where((s) => s.soort == soort).toList()..sort(beste)).take(max).toList());

  final groepen = [
    groep(SuggestieSoort.artiest, maxArtiesten),
    groep(SuggestieSoort.album, maxAlbums),
    groep(SuggestieSoort.nummer, maxNummers),
  ].where((g) => g.rijen.isNotEmpty).toList();
  // Stabiel: bij gelijke stand blijft de volgorde Artiesten, Albums, Nummers. `sort` op een List is dat niet.
  final metPlek = groepen.indexed.toList()
    ..sort((x, y) {
      final s = y.$2.rijen.first.score.compareTo(x.$2.rijen.first.score);
      return s != 0 ? s : x.$1.compareTo(y.$1);
    });
  return [for (final g in metPlek) g.$2];
}

/// Welke delen van [tekst] oplichten voor wat je typte: per woord van [getypt] het eerste woordbegin dat ermee begint, of
/// anders de eerste plek waar het staat. Op de letters van de tekst zoals hij er staat, ook met accenten ("Beyoncé").
List<(int, int)> oplichtDelen(String tekst, String getypt) {
  final q = normKey(getypt);
  if (q.isEmpty || tekst.isEmpty) return const [];
  // Per letter van de tekst vouwen: normKey haalt leestekens weg, en dan loopt de plek anders niet meer gelijk.
  final buf = StringBuffer();
  final plek = <int>[];
  for (var i = 0; i < tekst.length; i++) {
    final c = normKey(tekst[i]);
    for (var k = 0; k < c.length; k++) {
      buf.write(c[k]);
      plek.add(i);
    }
    if (c.isEmpty) {
      buf.write(' ');
      plek.add(i);
    }
  }
  final vlak = buf.toString();
  final delen = <(int, int)>[];
  for (final d in q.split(' ')) {
    if (d.isEmpty) continue;
    var p = -1;
    for (var i = vlak.indexOf(d); i >= 0; i = vlak.indexOf(d, i + 1)) {
      if (i == 0 || vlak[i - 1] == ' ') {
        p = i;
        break;
      }
      if (p < 0) p = i;
    }
    if (p < 0) continue;
    delen.add((plek[p], plek[p + d.length - 1] + 1));
  }
  delen.sort((a, b) => a.$1.compareTo(b.$1));
  return delen;
}

/// De laatste zoekopdrachten, op dit toestel. Saber koos op 08-11-2026 de laatste vijf, elk met een kruisje.
class ZoekRecent extends ChangeNotifier {
  ZoekRecent({this.bestand, this.max = 5});

  /// Waar het bewaard wordt; null: alleen in het geheugen, voor toetsen.
  final String Function()? bestand;
  final int max;

  List<String>? _lijst;

  List<String> get lijst {
    _laad();
    return List.unmodifiable(_lijst!);
  }

  void _laad() {
    if (_lijst != null) return;
    _lijst = [];
    final pad = bestand?.call();
    if (pad == null) return;
    try {
      final f = File(pad);
      if (!f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync());
      if (j is List) _lijst = [for (final s in j.take(max)) if (s is String && s.trim().isNotEmpty) s];
    } catch (_) {/* een kapot bestand is gewoon een lege lijst */}
  }

  void _bewaar() {
    final pad = bestand?.call();
    if (pad == null) return;
    try {
      File(pad).writeAsStringSync(jsonEncode(_lijst));
    } catch (_) {/* niet bewaard is geen ramp: dit is een gemak */}
  }

  /// Bovenaan zetten. Dezelfde woorden in een andere schrijfwijze zijn dezelfde zoekopdracht; de laatste schrijfwijze blijft.
  void voegToe(String tekst) {
    final t = tekst.trim();
    if (normKey(t).length < 2) return;
    _laad();
    _lijst!
      ..removeWhere((s) => normKey(s) == normKey(t))
      ..insert(0, t);
    if (_lijst!.length > max) _lijst!.removeRange(max, _lijst!.length);
    _bewaar();
    notifyListeners();
  }

  void wis(String tekst) {
    _laad();
    final was = _lijst!.length;
    _lijst!.removeWhere((s) => s == tekst);
    if (_lijst!.length == was) return;
    _bewaar();
    notifyListeners();
  }
}

/// Houdt bij wat er in het paneel hoort terwijl je typt.
///
/// Je eigen bibliotheek komt bijna meteen, Deezer na een korte pauze. Een antwoord op iets wat je allang niet meer typt,
/// wordt weggegooid ([_ronde]): trage netwerken antwoorden niet op volgorde.
class SuggestieBron extends ChangeNotifier {
  SuggestieBron({
    required this.albums,
    required this.online,
    this.maxArtiesten = 4,
    this.maxAlbums = 3,
    this.maxNummers = 4,
    this.eigenPauze = kSuggestieEigenPauze,
    this.onlinePauze = kSuggestieOnlinePauze,
  });

  /// De albums van de bibliotheek, op het moment van vragen.
  final List<Album> Function() albums;

  /// De vraag aan Deezer. Geeft null als die niet lukte: dan blijft je eigen bibliotheek gewoon staan.
  final Future<OnlineTreffers?> Function(String tekst) online;
  final int maxArtiesten, maxAlbums, maxNummers;
  final Duration eigenPauze, onlinePauze;

  String _tekst = '';
  int _ronde = 0;
  Timer? _eigenKlok, _onlineKlok;
  EigenIndex _index = EigenIndex.leeg;
  List<Suggestie> _eigen = const [];
  List<Suggestie> _online = const [];
  final _antwoorden = <String, OnlineTreffers>{};

  List<Suggestiegroep> groepen = const [];

  /// Er loopt een vraag naar Deezer.
  bool onlineBezig = false;

  bool _dicht = false;

  /// Alvast opbouwen, als het veld focus krijgt: dan hapert de eerste letter niet.
  void warmOp() => _indexNu();

  EigenIndex _indexNu() {
    final a = albums();
    if (!identical(_index.bron, a)) _index = EigenIndex.van(a);
    return _index;
  }

  /// Er staat nu [tekst] in het veld.
  void zet(String tekst) {
    final t = tekst.trim();
    if (t == _tekst) return;
    _tekst = t;
    final ronde = ++_ronde;
    _eigenKlok?.cancel();
    _onlineKlok?.cancel();
    if (normKey(t).isEmpty) {
      _eigen = const [];
      _online = const [];
      groepen = const [];
      onlineBezig = false;
      notifyListeners();
      return;
    }
    // Het oude online-antwoord blijft staan tot het nieuwe er is, maar alleen wat nog ergens op lijkt: de rest zou knipperen
    // tussen twee letters. Wat niet meer past, gaat er nu al uit.
    _online = _online.where((s) => _pastNog(s, t)).toList(growable: false);
    _eigenKlok = Timer(eigenPauze, () {
      if (ronde != _ronde) return;
      _eigen = eigenSuggesties(_indexNu(), t);
      _meng();
    });
    if (normKey(t).length < kSuggestieMinOnline) {
      onlineBezig = false;
      return;
    }
    final bewaard = _antwoorden[normKey(t)];
    if (bewaard != null) {
      _online = onlineSuggesties(bewaard, t);
      onlineBezig = false;
      return;
    }
    onlineBezig = true;
    _onlineKlok = Timer(onlinePauze, () => unawaited(_vraag(t, ronde)));
  }

  bool _pastNog(Suggestie s, String tekst) {
    final q = normKey(tekst);
    return trefScore(normKey(s.titel), q) > 0 || trefScore(artistKey(s.onder), q) > 0;
  }

  Future<void> _vraag(String t, int ronde) async {
    OnlineTreffers? antwoord;
    try {
      antwoord = await online(t);
    } catch (_) {
      antwoord = null;
    }
    if (_dicht || ronde != _ronde) return;
    onlineBezig = false;
    if (antwoord != null) {
      if (_antwoorden.length >= kSuggestieGeheugen) _antwoorden.remove(_antwoorden.keys.first);
      _antwoorden[normKey(t)] = antwoord;
      _online = onlineSuggesties(antwoord, t);
    }
    _meng();
  }

  void _meng() {
    groepen = mengSuggesties(_eigen, _online, maxArtiesten: maxArtiesten, maxAlbums: maxAlbums, maxNummers: maxNummers);
    notifyListeners();
  }

  @override
  void dispose() {
    _dicht = true;
    _eigenKlok?.cancel();
    _onlineKlok?.cancel();
    super.dispose();
  }
}
