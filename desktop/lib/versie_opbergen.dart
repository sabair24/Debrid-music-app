/// Een kopie die binnenkomt: vervangt hij het nummer, of is hij een ANDERE versie ervan (versies.dart)?
///
/// Saber, 26-10-2026: *"Behoud ik alles e, cd, studio, en vinyl"*. Tot nu toe kende de app maar twee uitkomsten: bewezen
/// beter → vervangen (de vorige naar `_dubbel`), anders weggooien. Vandaag vervingen torrents zo minstens zeven cd-kopieën
/// door vinylrips — de cd's staan in `_dubbel`. Nu een derde: dezelfde opname in een andere soort of persing blijft,
/// in zijn eigen map naast het album.
///
/// * **Dezelfde versie** (twee cd-rips, twee vinylrips — welke persing ook): zoals altijd, de bewezen betere wint.
///   Per nummer hoogstens één studio, één cd en één vinyl (Saber, 27-10-2026: "enkel studio, cd of vinyl drie
///   soorten"); wat er al dubbel lag, ruimt [eenPerSoort] op.
/// * **Een andere versie, lager in de volgorde** (studio > cd > vinyl): bewaard als versie; het nummer blijft.
/// * **Een andere versie, hoger in de volgorde** (een echte studiokopie voor je cd): het nummer gaat opzij als versie
///   ("Spice (cd)"), de nieuwe neemt zijn plek in. Alleen als hij ook bewezen beter is — anders wordt hij gewoon een
///   versie, en blijft wat je had.
/// * **Al een versie van die soort**: de bewezen betere van die twee blijft.
///
/// Dat het DEZELFDE OPNAME is, beslist de vingerafdruk bij de aanroeper; hier wordt alleen nog gesorteerd.
library;

import 'dart:io';

import 'audioformaten.dart' show isVerliesvrij, soortVan;
import 'echtheid_meter.dart' show leesStreaminfo;
import 'flac_tags.dart' show readFlacRawFields, readFlacTags;
import 'kopiesoort.dart';
import 'organize.dart';
import 'versies.dart';
import 'vinyl.dart' show vinylUitTags;
import 'vinylspoor.dart';

enum Versiebesluit {
  /// Dezelfde versie als het nummer (of iets zonder soort): vervangen of weggooien, zoals altijd.
  gewoon,

  /// Bewaren als nieuwe versie; het nummer blijft.
  nieuweVersie,

  /// Dezelfde versie als een versie die er al is: de bewezen betere van die twee blijft.
  vervangVersie,

  /// Het nummer gaat opzij als versie; de nieuwe wordt het nummer.
  ankerOpzij,
}

/// Wat er met een binnenkomer van [soort] en [persing] gebeurt naast een nummer van [ankerSoort] en [ankerPersing] met
/// [bestaande] versies. Zonder soort aan een van beide kanten (verliesgevend, 16/48): [Versiebesluit.gewoon].
({Versiebesluit besluit, Versie? vervangt}) versiebesluit({
  required Kopiesoort? soort,
  required String persing,
  required Kopiesoort? ankerSoort,
  required String ankerPersing,
  List<Versie> bestaande = const [],
}) {
  if (soort == null || ankerSoort == null) return (besluit: Versiebesluit.gewoon, vervangt: null);
  if (zelfdeVersie(soort, persing, ankerSoort, ankerPersing)) return (besluit: Versiebesluit.gewoon, vervangt: null);
  for (final v in bestaande) {
    if (zelfdeVersie(soort, persing, v.soort, v.persing)) return (besluit: Versiebesluit.vervangVersie, vervangt: v);
  }
  return (
    besluit: soortRang(soort) < soortRang(ankerSoort) ? Versiebesluit.ankerOpzij : Versiebesluit.nieuweVersie,
    vervangt: null,
  );
}

/// Alles wat het opbergen als versie nodig heeft.
class Versieplan {
  const Versieplan({
    required this.besluit,
    required this.anker,
    required this.soort,
    required this.persing,
    required this.bron,
    required this.ankerSoort,
    required this.ankerPersing,
    this.vervangt,
  });

  final Versiebesluit besluit;

  /// Het nummer in de bibliotheek.
  final String anker;

  /// Wat de binnenkomer is.
  final Kopiesoort? soort;
  final String persing;

  /// Waar hij vandaan kwam (het pad bij de uploader, in de torrent, "TIDAL …").
  final String bron;
  final Kopiesoort? ankerSoort;
  final String ankerPersing;

  /// Bij [Versiebesluit.vervangVersie]: de versie die hij misschien vervangt.
  final Versie? vervangt;

  bool get isVersie => besluit != Versiebesluit.gewoon;

  /// Dezelfde soort en persing, maar met een ander besluit (een studiokopie die niet bewezen beter is wordt een versie
  /// in plaats van het nummer).
  Versieplan als(Versiebesluit b) => Versieplan(
      besluit: b,
      anker: anker,
      soort: soort,
      persing: persing,
      bron: bron,
      ankerSoort: ankerSoort,
      ankerPersing: ankerPersing,
      vervangt: vervangt);
}

/// De soort van het bestand op [pad], uit [bronpad] en zijn kop (kopiesoort.dart).
Kopiesoort? soortVanBestand(String pad, String bronpad) {
  try {
    final f = File(pad);
    final kop = readFlacTags(f);
    final soort = kopiesoortVan(
        bronpad: bronpad,
        bits: kop?.bitsPerSample ?? 0,
        hz: kop?.sampleRate ?? 0,
        verliesvrij: isVerliesvrij(soortVan(pad)));
    // Een vinylrip zonder teken in zijn pad: vaak staat het in zijn tags (MEDIA=Vinyl, het element in COMMENT).
    if (soort != null && soort != Kopiesoort.vinyl && kop != null && vinylUitTags(readFlacRawFields(f))) {
      return Kopiesoort.vinyl;
    }
    return soort;
  } catch (_) {
    return null;
  }
}

/// Is [pad] (van [soort]) een tweeling van [ander] (van [anderSoort]): dezelfde rip onder een ander etiket?
///
/// Gemeten 27-10-2026: de blijvende jacht haalde bij floresnico een "studio" 32/384 van Cutting Crew die de vinylrip van
/// Dymokust bleek — zonder zijn COMMENT-tag, en tot op het sample even lang als je vinylversie — en bij valentinchpx een
/// "studio" Voyager die bit voor bit je vinyl LP 2021 was. Allebei werden ze het nummer, en je cd ging opzij.
///
/// Dezelfde bemonstering, kanalen en diepte, tot op het sample dezelfde lengte, en dan nog: dezelfde controlesom van de
/// samples, of een van beide is vinyl. Dat laatste omdat een vinylrip nooit toevallig even lang is als iets anders. Een
/// studiokopie in 24/44,1 en de cd van dezelfde master zijn dat wél (25 paren in de bibliotheek) — maar die verschillen
/// in diepte, en twee digitale kopieën met dezelfde lengte en diepte zijn alleen bij een gelijke controlesom één rip.
bool isTweeling(String pad, Kopiesoort? soort, String ander, Kopiesoort? anderSoort) {
  final a = leesStreaminfo(pad), b = leesStreaminfo(ander);
  if (a == null || b == null || a.totaal <= 0) return false;
  if (a.sr != b.sr || a.kanalen != b.kanalen || a.bps != b.bps || a.totaal != b.totaal) return false;
  const leeg = '00000000000000000000000000000000';
  if (a.md5 != leeg && a.md5 == b.md5) return true;
  return soort == Kopiesoort.vinyl || anderSoort == Kopiesoort.vinyl;
}

/// De kopie van [anker] die vaststaat als digitaal — de cd, het nummer zelf of een versie — of null.
String? digitaleReferentie(String anker) {
  final ankerSoort = soortVoor(anker)?.soort ?? versies.groep(anker)?.soort ?? soortVanBestand(anker, anker);
  if (ankerSoort == Kopiesoort.cd) return anker;
  for (final v in versies.versiesVan(anker)) {
    if (v.soort == Kopiesoort.cd && File(v.pad).existsSync()) return v.pad;
  }
  return null;
}

/// Het vinylspoor bij binnenkomst ([klinktAlsVinyl]): is [kandidaat] studio volgens pad ([bronpad]) en tags, maar houdt
/// hij groefruis waar je cd van [anker] stil wordt, dan wordt hij als vinyl genoteerd — [versieplanVoor] neemt dat over.
/// Waar als het zo is. Zonder meter ([stilteVan]) of zonder cd: niets.
Future<bool> merkVinylspoor(String kandidaat, String anker, String bronpad, {void Function(String regel)? log}) async {
  final meet = stilteVan;
  if (meet == null) return false;
  final soort = soortVoor(kandidaat)?.soort ?? soortVanBestand(kandidaat, bronpad);
  if (soort != Kopiesoort.studio) return false;
  final cd = digitaleReferentie(anker);
  if (cd == null) return false;
  final ref = await meet(cd);
  if (ref == null || ref.stilste >= kDigitaalStil) return false;
  final k = await meet(kandidaat);
  if (k == null || !klinktAlsVinyl(k, ref)) return false;
  zetSoort(kandidaat, Kopiesoort.vinyl);
  log?.call('   klinkt als vinyl: groefruis op ${k.stilste.toStringAsFixed(0)} dB waar je cd stil wordt '
      '(${ref.stilste.toStringAsFixed(0)} dB) — telt als vinyl');
  return true;
}

/// Wat [nieuw] (net binnen, van [bronpad]) is tegenover het nummer [anker]: zijn soort en persing, die van het nummer
/// (soorten.json, het register, en anders de kop), en het besluit.
Versieplan versieplanVoor(File nieuw, String anker, String bronpad) {
  // Wat er al over hem bekend is (een kopie die in _dubbel belandde, nam zijn soort mee), anders zijn kop en waar hij
  // vandaan kwam.
  var soort = soortVoor(nieuw.path)?.soort ?? soortVanBestand(nieuw.path, bronpad);
  var persing = soort == null ? '' : persingUit(bronpad, soort: soort);
  final g = versies.groep(anker);
  final ankerSoort = soortVoor(anker)?.soort ?? g?.soort ?? soortVanBestand(anker, anker);
  final ankerPersing = g?.persing ?? '';
  final bestaande = versies.versiesVan(anker);
  // Een tweeling van het nummer of van een versie IS die, met haar soort en persing ([isTweeling]): dan beslist de
  // keuring binnen die soort, en verliest hij — want hij is niet beter dan zichzelf.
  if (isTweeling(nieuw.path, soort, anker, ankerSoort)) {
    soort = ankerSoort;
    persing = ankerPersing;
  } else {
    for (final v in bestaande) {
      if (!isTweeling(nieuw.path, soort, v.pad, v.soort)) continue;
      soort = v.soort;
      persing = v.persing;
      break;
    }
  }
  final b = versiebesluit(
      soort: soort,
      persing: persing,
      ankerSoort: ankerSoort,
      ankerPersing: ankerPersing,
      bestaande: bestaande);
  return Versieplan(
      besluit: b.besluit,
      anker: anker,
      soort: soort,
      persing: persing,
      bron: bronpad,
      ankerSoort: ankerSoort,
      ankerPersing: ankerPersing,
      vervangt: b.vervangt);
}

String _naam(String pad) => pad.split(RegExp(r'[\\/]')).last;
String _map(String pad) {
  final i = pad.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? '' : pad.substring(0, i);
}

String _stam(String naam) => naam.contains('.') ? naam.substring(0, naam.lastIndexOf('.')) : naam;
String _ext(String naam) => naam.contains('.') ? naam.substring(naam.lastIndexOf('.')) : '';

/// De albumnaam van een versie: "Spice (vinyl)" — zo is hij in Roon en in de map een eigen album (Saber, 26-10-2026: "een
/// eigen album per versie"), één per soort ([versieMap]). Een single (zonder album) houdt een lege albumtag.
Future<void> _zetVersieAlbum(String pad, String? album, Kopiesoort soort) async {
  try {
    if (album == null || album.trim().isEmpty) return;
    final naam = _versieAlbumnaam(album, soort);
    await writeTagFields(File(pad), {'ALBUM': naam});
  } catch (_) {/* het bestand staat goed; alleen de albumnaam bleef die van het nummer */}
}

/// "Spice" → "Spice (vinyl)" ([_zetVersieAlbum]).
String _versieAlbumnaam(String album, Kopiesoort soort) =>
    album.endsWith('(${soort.naam})') ? album : '$album (${soort.naam})';

/// De albumnaam van het nummer op [pad], of null.
String? _albumVan(String pad) {
  try {
    final a = readTags(File(pad))?.album;
    return a == null || a.trim().isEmpty ? null : a;
  } catch (_) {
    return null;
  }
}

/// De albumnaam terug zoals die van het nummer (een anker dat opzij ging en terugkwam).
Future<void> _zetAlbumTerug(String pad, String? album) async {
  if (album == null || album.trim().isEmpty) return;
  try {
    await writeTagFields(File(pad), {'ALBUM': album});
  } catch (_) {}
}

/// Een vrije plek in de map van [doel]: "(2)", "(3)" erachter als er al iets staat.
File _vrij(File doel) {
  if (!doel.existsSync()) return doel;
  final map = _map(doel.path), naam = _naam(doel.path);
  for (var n = 2;; n++) {
    final f = File('$map${Platform.pathSeparator}${_stam(naam)} ($n)${_ext(naam)}');
    if (!f.existsSync()) return f;
  }
}

/// Wat het opbergen als versie deed: het pad waar hij staat, of het nummer werd ([werdAnker]), en of hij verloor van een
/// betere versie die er al was ([verloor]: dan is hij weg).
typedef Versieuitslag = ({String pad, bool werdAnker, bool verloor});

/// [src] opbergen volgens [plan] (niet [Versiebesluit.gewoon]). [tags]: het gezag van de download (titel, nummer,
/// album), zoals [placeFileDetailed] het krijgt. Null: het lukte niet — dan staat alles zoals het stond en [src] er nog.
///
/// [nu]: voor de toets. [dwing]: bij [Versiebesluit.vervangVersie] zonder keuring — jij koos deze kopie (een twijfel die je
/// bewaarde, terwijl er al een van zijn soort was).
Future<Versieuitslag?> bergOpAlsVersie(File src, Versieplan plan,
    {required String root,
    TrackTags? tags,
    DateTime Function()? nu,
    bool laatVerliezerStaan = false,
    bool dwing = false}) async {
  final soort = plan.soort;
  if (soort == null || !plan.isVersie) return null;
  final sinds = (nu ?? DateTime.now)().millisecondsSinceEpoch;
  switch (plan.besluit) {
    case Versiebesluit.gewoon:
      return null;

    case Versiebesluit.nieuweVersie:
      final map = versieMap(_map(plan.anker), soort);
      final doel = _vrij(File('$map${Platform.pathSeparator}${_stam(_naam(plan.anker))}${_ext(_naam(src.path))}'));
      await Directory(map).create(recursive: true);
      final at = await moveWithRetry(src, doel);
      if (tags != null) await stampTags(File(at), tags);
      await _zetVersieAlbum(at, _albumVan(plan.anker), soort);
      versies.voegToe(
          plan.anker, Versie(pad: at, soort: soort, persing: plan.persing, bron: plan.bron, sindsMs: sinds),
          ankerSoort: plan.ankerSoort, ankerPersing: plan.ankerPersing);
      zetSoort(at, soort);
      return (pad: at, werdAnker: false, verloor: false);

    case Versiebesluit.vervangVersie:
      final oud = plan.vervangt;
      if (oud == null) return null;
      if (!File(oud.pad).existsSync()) {
        // De versie staat er niet meer: deze komt in haar plaats.
        versies.verwijder(oud.pad);
        return bergOpAlsVersie(src, plan.als(Versiebesluit.nieuweVersie),
            root: root, tags: tags, nu: nu, laatVerliezerStaan: laatVerliezerStaan);
      }
      if (!dwing && !firstIsBetter(src, File(oud.pad))) {
        // [laatVerliezerStaan]: een oude kopie uit _dubbel die terug zou komen — die is van jou, en blijft waar hij was.
        if (!laatVerliezerStaan) {
          try {
            await src.delete();
          } catch (_) {}
        }
        return (pad: oud.pad, werdAnker: false, verloor: true);
      }
      // Bewezen beter dan de versie die er was: die gaat naar _dubbel (zoals bij een gewone vervanging), deze komt op
      // haar plek — en blijft een versie.
      final uit = await placeFileDetailed(src, root,
          tags: tags, staatAl: (artist, title, {int? seconds}) => oud.pad, parkeerAltijd: true, vervangAltijd: dwing);
      if (uit.how != Placement.moved) return (pad: oud.pad, werdAnker: false, verloor: true);
      await _zetVersieAlbum(uit.path, _albumVan(plan.anker), soort);
      versies.voegToe(
          plan.anker,
          Versie(
              pad: uit.path,
              soort: soort,
              persing: _zonderAndereKopie(plan.persing.isEmpty ? oud.persing : plan.persing),
              bron: plan.bron,
              sindsMs: sinds),
          ankerSoort: plan.ankerSoort,
          ankerPersing: plan.ankerPersing);
      zetSoort(uit.path, soort);
      return (pad: uit.path, werdAnker: false, verloor: false);

    case Versiebesluit.ankerOpzij:
      final ankerSoort = plan.ankerSoort;
      final anker = File(plan.anker);
      if (ankerSoort == null || !anker.existsSync()) return null;
      final album = readTags(anker)?.album;
      final map = versieMap(_map(plan.anker), ankerSoort);
      final doel = _vrij(File('$map${Platform.pathSeparator}${_naam(plan.anker)}'));
      await Directory(map).create(recursive: true);
      // Het nummer opzij, en alleen door hernoemen: houdt een speler het open, dan liever niets dan een kopie naast een
      // origineel dat blijft staan. Het verplaatsen neemt de groep in het register mee (het anker verhuist).
      final opzij = await verplaatsZonderKopie(anker, doel);
      if (opzij == null) return null;
      final uit = await placeFileDetailed(src, root,
          tags: tags, staatAl: (artist, title, {int? seconds}) => plan.anker, parkeerAltijd: true);
      if (uit.how != Placement.moved) {
        // De nieuwe landde niet op de plek van het nummer: het nummer terug.
        try {
          await moveWithRetry(File(opzij), File(plan.anker));
        } catch (_) {/* dan staat het in zijn versiemap; de volgende scan maakt het weer het nummer */}
        return null;
      }
      await _zetVersieAlbum(opzij, album, ankerSoort);
      versies.verhuisAnker(opzij, uit.path, soort: soort, persing: plan.persing);
      versies.voegToe(
          uit.path,
          Versie(
              pad: opzij,
              soort: ankerSoort,
              persing: plan.ankerPersing,
              bron: 'was het nummer',
              sindsMs: sinds),
          ankerSoort: soort,
          ankerPersing: plan.persing);
      zetSoort(uit.path, soort);
      zetSoort(opzij, ankerSoort);
      // De albumnaam van het nummer blijft die van het album (de buren); [placeFileDetailed] nam hem over.
      if (album != null && readTags(File(uit.path))?.album != album) await _zetAlbumTerug(uit.path, album);
      return (pad: uit.path, werdAnker: true, verloor: false);
  }
}

/// "andere kopie" uit een persing: met één kopie per soort is er geen andere meer.
String _zonderAndereKopie(String persing) =>
    persing.replaceAll(RegExp(r'\s*andere kopie\s*', caseSensitive: false), ' ').trim();

/// Een map die leeg achterbleef (een versie verhuisde naar de map van zijn soort).
void _ruimLegeMapOp(String map) {
  try {
    final d = Directory(map);
    if (d.existsSync() && d.listSync().isEmpty) d.deleteSync();
  } catch (_) {/* dan blijft er een lege map staan */}
}

/// Wat [eenPerSoort] deed: kopieën naar `_dubbel`, tweelingen die het nummer waren, versies naar de map van hun soort,
/// versies waarvan alleen de albumnaam nog een persing droeg, en nummers die bleven omdat er iets speelde.
typedef Soortopruiming = ({int naarDubbel, int tweelingen, int vinylspoor, int verhuisd, int albumnaam, int overgeslagen});

/// Per nummer hoogstens één kopie van elke soort: studio, cd en vinyl (Saber, 27-10-2026, bij Discovery met negen
/// versies: *"Das teveel, enkel studio, cd of vinyl drie soorten"*). Wat er nieuw binnenkomt, houdt zich daar al aan
/// ([zelfdeVersie]); dit ruimt op wat er al lag. Bij de start op de pc.
///
/// * **Het nummer is een tweeling van een versie** ([isTweeling]; 27-10-2026: Cutting Crew, Voyager): het is dezelfde rip
///   als die versie, onder een ander etiket. Het nummer gaat naar `_dubbel`; de versie met de beste soort komt op zijn
///   plek — de cd die er voor de tweeling stond.
/// * **Twee van dezelfde soort**: de bewezen betere blijft ([firstIsBetter]). Bij gelijkspel blijft wat er al zat: het
///   nummer, dan de versie die je koos, dan de oudste. De rest gaat naar `_dubbel` (na 30 dagen de prullenbak).
/// * **Een studio die als vinyl klinkt** ([klinktAlsVinyl], [stilte]; 27-10-2026: zes op Discovery): hij telt als vinyl
///   — en heb je er al een, dan blijft de bewezen betere.
/// * **Een versie in een map met een persing** ("Discovery (vinyl LP 2001)"): naar de map van haar soort
///   ("Discovery (vinyl)"), met die albumnaam; "andere kopie" valt weg uit het label.
///
/// [dubbel]: de map `_dubbel`. [inGebruik]: speelt of leest iets dit bestand — dan blijft dat nummer tot de volgende
/// start. [log]: één regel per ingreep.
Future<Soortopruiming> eenPerSoort(
    {required String dubbel,
    bool Function(String pad)? inGebruik,
    void Function(String regel)? log,
    Future<Stilte?> Function(String pad)? stilte}) async {
  var naarDubbel = 0, tweelingen = 0, vinylspoor = 0, verhuisd = 0, albumnaam = 0, overgeslagen = 0;
  final meet = stilte ?? stilteVan;
  final sep = Platform.pathSeparator;
  for (final g in versies.groepen.toList()) {
    final anker = g.anker;
    final lijst = [for (final v in versies.versiesVan(anker)) if (File(v.pad).existsSync()) v];
    if (lijst.isEmpty || !File(anker).existsSync()) continue;
    if (inGebruik != null && (inGebruik(anker) || lijst.any((v) => inGebruik(v.pad)))) {
      overgeslagen++;
      continue;
    }
    final naam = _stam(_naam(anker));
    final geregistreerd = soortVoor(anker)?.soort ?? g.soort ?? soortVanBestand(anker, anker);
    var ankerSoort = geregistreerd;
    // Wat elke versie werkelijk is: twee versies die tweelingen zijn, zijn één soort — vinyl als een van beide vinyl is
    // (dat is wat [isTweeling] dan vroeg), anders die van de oudste.
    final soortVan = <String, Kopiesoort>{for (final v in lijst) v.pad: v.soort};
    for (var i = 0; i < lijst.length; i++) {
      for (var j = i + 1; j < lijst.length; j++) {
        final a = lijst[i], b = lijst[j];
        if (soortVan[a.pad] == soortVan[b.pad] || !isTweeling(a.pad, a.soort, b.pad, b.soort)) continue;
        final s = a.soort == Kopiesoort.vinyl || b.soort == Kopiesoort.vinyl
            ? Kopiesoort.vinyl
            : (a.sindsMs <= b.sindsMs ? a.soort : b.soort);
        soortVan[a.pad] = s;
        soortVan[b.pad] = s;
      }
    }
    // Het vinylspoor: een studio met groefruis waar je cd stil wordt, is vinyl ([klinktAlsVinyl]).
    final cd = ankerSoort == Kopiesoort.cd
        ? anker
        : lijst.where((v) => soortVan[v.pad] == Kopiesoort.cd).firstOrNull?.pad;
    final ref = meet == null || cd == null ? null : await meet(cd);
    if (meet != null && ref != null && ref.stilste < kDigitaalStil) {
      final studio = [
        if (ankerSoort == Kopiesoort.studio) anker,
        for (final v in lijst)
          if (soortVan[v.pad] == Kopiesoort.studio) v.pad,
      ];
      for (final p in studio) {
        final k = await meet(p);
        if (k == null || !klinktAlsVinyl(k, ref)) continue;
        if (p == anker) {
          ankerSoort = Kopiesoort.vinyl;
        } else {
          soortVan[p] = Kopiesoort.vinyl;
        }
        vinylspoor++;
        log?.call('"$naam": ${p == anker ? 'het nummer' : 'je studio-versie'} klinkt als vinyl — groefruis op '
            '${k.stilste.toStringAsFixed(0)} dB waar je cd stil wordt (${ref.stilste.toStringAsFixed(0)} dB): nu vinyl');
      }
    }
    final tweelingVan = ankerSoort == null
        ? null
        : lijst.where((v) => isTweeling(anker, ankerSoort, v.pad, v.soort)).firstOrNull;
    final keuze = versies.speelVersie(anker, ankerSoort: ankerSoort);

    // Per soort de kopieën; het nummer telt mee, behalve als het een tweeling is (dan gaat het hoe dan ook weg).
    final perSoort = <Kopiesoort, List<({String pad, Versie? v})>>{
      if (ankerSoort != null && tweelingVan == null) ankerSoort: [(pad: anker, v: null)],
    };
    for (final v in lijst) {
      perSoort.putIfAbsent(soortVan[v.pad]!, () => []).add((pad: v.pad, v: v));
    }
    int zittend(({String pad, Versie? v}) x) => x.v == null ? 0 : (identical(x.v, keuze) ? 1 : 2);
    var ankerWeg = tweelingVan != null;
    Versie? opvolger;
    final blijven = <Versie>[], verliezers = <Versie>[];
    for (final MapEntry(key: soort, value: kopieen) in perSoort.entries) {
      kopieen.sort((a, b) {
        final r = zittend(a).compareTo(zittend(b));
        return r != 0 ? r : (a.v?.sindsMs ?? 0).compareTo(b.v?.sindsMs ?? 0);
      });
      var best = kopieen.first;
      for (final x in kopieen.skip(1)) {
        final beter = firstIsBetter(File(x.pad), File(best.pad));
        final verliezer = beter ? best : x;
        if (beter) best = x;
        if (verliezer.v == null) {
          ankerWeg = true;
        } else {
          verliezers.add(verliezer.v!);
        }
      }
      final b = best.v;
      if (b == null) continue;
      blijven.add(b);
      if (soort == ankerSoort && ankerWeg && tweelingVan == null) opvolger = b;
    }
    if (tweelingVan != null) {
      blijven.sort((a, b) => soortRang(soortVan[a.pad]!).compareTo(soortRang(soortVan[b.pad]!)));
      opvolger = blijven.firstOrNull;
    }

    // 1. Wat het aflegt naar _dubbel (het verplaatsen haalt het uit het register: versies.herNoem).
    for (final v in verliezers) {
      try {
        await parkeer(File(v.pad), dubbel);
        _ruimLegeMapOp(_map(v.pad));
        naarDubbel++;
        log?.call('"$naam": ${versieLabel(v.soort, v.persing)} naar _dubbel — er is al een '
            '${soortVan[v.pad]!.naam}-kopie die minstens zo goed is (één per soort)');
      } catch (e) {
        log?.call('"$naam": ${versieLabel(v.soort, v.persing)} naar _dubbel lukte niet — $e');
      }
    }

    // 2. Het nummer: weg als het een tweeling was of verloor van zijn soortgenoot; de opvolger op zijn plek.
    var nu = anker;
    final album = _albumVan(anker);
    final o = opvolger;
    if (ankerWeg && o != null && File(o.pad).existsSync()) {
      final soort = soortVan[o.pad]!;
      final doel = File('${_map(anker)}$sep$naam${_ext(_naam(o.pad))}');
      String? opzij;
      try {
        opzij = await parkeer(File(anker), dubbel);
        final at = await moveWithRetry(File(o.pad), doel);
        // Zijn versiemap bleef leeg achter ("Cutting Crew (cd)", 27-10-2026).
        _ruimLegeMapOp(_map(o.pad));
        versies.verhuisAnker(anker, at, soort: soort, persing: _zonderAndereKopie(o.persing));
        zetSoort(at, soort);
        if (album != null) await _zetAlbumTerug(at, album);
        nu = at;
        naarDubbel++;
        if (tweelingVan != null) {
          tweelingen++;
          log?.call('"$naam": het nummer was dezelfde rip als je ${versieLabel(tweelingVan.soort, tweelingVan.persing)} '
              'onder een ander etiket — naar _dubbel; ${versieLabel(soort, o.persing)} is weer het nummer');
        } else {
          log?.call('"$naam": je ${versieLabel(soort, o.persing)} is bewezen beter dan het nummer van dezelfde soort — '
              'nu het nummer, het vorige naar _dubbel');
        }
      } catch (e) {
        // Het nummer terug, als het al opzij stond: liever twee kopieën van één soort dan een gat in het album.
        if (opzij != null && !File(anker).existsSync()) {
          try {
            await moveWithRetry(File(opzij), File(anker));
          } catch (_) {/* staat in _dubbel; niets is weg */}
        }
        log?.call('"$naam": het nummer vervangen lukte niet — $e');
        continue;
      }
    }

    // Het nummer bleef, maar is vinyl (het vinylspoor): zo in het register en in soorten.json.
    if (nu == anker && ankerSoort != null && ankerSoort != geregistreerd && File(anker).existsSync()) {
      versies.verhuisAnker(anker, anker, soort: ankerSoort, persing: '');
      zetSoort(anker, ankerSoort);
    }

    // 3. Wat blijft naar de map van zijn soort, zonder "andere kopie" in het label.
    for (final v in versies.versiesVan(nu)) {
      if (!File(v.pad).existsSync()) continue;
      final soort = soortVan[v.pad] ?? v.soort;
      final persing = _zonderAndereKopie(v.persing);
      final map = versieMap(_map(nu), soort);
      var pad = v.pad;
      if (_map(v.pad).toLowerCase() != map.toLowerCase()) {
        final oudeMap = _map(v.pad);
        try {
          await Directory(map).create(recursive: true);
          pad = await moveWithRetry(File(v.pad), _vrij(File('$map$sep${_stam(_naam(nu))}${_ext(_naam(v.pad))}')));
          await _zetVersieAlbum(pad, album, soort);
          _ruimLegeMapOp(oudeMap);
          verhuisd++;
        } catch (e) {
          log?.call('"$naam": ${versieLabel(soort, persing)} naar "${_naam(map)}" lukte niet — $e');
          continue;
        }
      } else if (album != null && _albumVan(pad) != _versieAlbumnaam(album, soort)) {
        // Al in de map van zijn soort, maar met de albumnaam van zijn persing: Voyager stond in "Discovery (vinyl)" als
        // "Discovery (vinyl LP 2022)" — in Roon een album van één nummer naast "Discovery (vinyl)" (27-10-2026).
        await _zetVersieAlbum(pad, album, soort);
        albumnaam++;
      }
      if (soort != v.soort || persing != v.persing) {
        versies.voegToe(
            nu,
            Versie(
                pad: pad,
                soort: soort,
                persing: persing,
                bron: v.bron,
                sindsMs: v.sindsMs,
                verschuivingMs: v.verschuivingMs,
                snelheid: v.snelheid));
        zetSoort(pad, soort);
      }
    }
  }
  return (
    naarDubbel: naarDubbel,
    tweelingen: tweelingen,
    vinylspoor: vinylspoor,
    verhuisd: verhuisd,
    albumnaam: albumnaam,
    overgeslagen: overgeslagen
  );
}
