/// Een kopie die binnenkomt: vervangt hij het nummer, of is hij een ANDERE versie ervan (versies.dart)?
///
/// Saber, 26-10-2026: *"Behoud ik alles e, cd, studio, en vinyl"*. Tot nu toe kende de app maar twee uitkomsten: bewezen
/// beter → vervangen (de vorige naar `_dubbel`), anders weggooien. Vandaag vervingen torrents zo minstens zeven cd-kopieën
/// door vinylrips — de cd's staan in `_dubbel`. Nu een derde: dezelfde opname in een andere soort of persing blijft,
/// in zijn eigen map naast het album.
///
/// * **Dezelfde versie** (twee cd-rips, twee keer dezelfde vinylpersing): zoals altijd — de bewezen betere wint.
/// * **Een andere versie, lager in de volgorde** (studio > cd > vinyl): bewaard als versie; het nummer blijft.
/// * **Een andere versie, hoger in de volgorde** (een echte studiokopie voor je cd): het nummer gaat opzij als versie
///   ("Spice (cd)"), de nieuwe neemt zijn plek in. Alleen als hij ook bewezen beter is — anders wordt hij gewoon een
///   versie, en blijft wat je had.
/// * **Al een versie van die soort en persing**: de bewezen betere van die twee blijft.
///
/// Dat het DEZELFDE OPNAME is, beslist de vingerafdruk bij de aanroeper; hier wordt alleen nog gesorteerd.
library;

import 'dart:io';

import 'audioformaten.dart' show isVerliesvrij, soortVan;
import 'flac_tags.dart' show readFlacTags;
import 'kopiesoort.dart';
import 'organize.dart';
import 'versies.dart';

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
    final kop = readFlacTags(File(pad));
    return kopiesoortVan(
        bronpad: bronpad,
        bits: kop?.bitsPerSample ?? 0,
        hz: kop?.sampleRate ?? 0,
        verliesvrij: isVerliesvrij(soortVan(pad)));
  } catch (_) {
    return null;
  }
}

/// Wat [nieuw] (net binnen, van [bronpad]) is tegenover het nummer [anker]: zijn soort en persing, die van het nummer
/// (soorten.json, het register, en anders de kop), en het besluit.
Versieplan versieplanVoor(File nieuw, String anker, String bronpad) {
  // Wat er al over hem bekend is (een kopie die in _dubbel belandde, nam zijn soort mee), anders zijn kop en waar hij
  // vandaan kwam.
  final soort = soortVoor(nieuw.path)?.soort ?? soortVanBestand(nieuw.path, bronpad);
  final persing = soort == null ? '' : persingUit(bronpad, soort: soort);
  final g = versies.groep(anker);
  final ankerSoort = soortVoor(anker)?.soort ?? g?.soort ?? soortVanBestand(anker, anker);
  final ankerPersing = g?.persing ?? '';
  final b = versiebesluit(
      soort: soort,
      persing: persing,
      ankerSoort: ankerSoort,
      ankerPersing: ankerPersing,
      bestaande: versies.versiesVan(anker));
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

/// De albumnaam van een versie: "Spice (vinyl LP 1996)" — zo is hij in Roon en in de map een eigen album (Saber,
/// 26-10-2026: "een eigen album per versie"). Een single (zonder album) houdt een lege albumtag.
Future<void> _zetVersieAlbum(String pad, String? album, Kopiesoort soort, String persing) async {
  try {
    if (album == null || album.trim().isEmpty) return;
    final label = versieMapLabel(soort, persing);
    final naam = album.endsWith('($label)') ? album : '$album ($label)';
    await writeTagFields(File(pad), {'ALBUM': naam});
  } catch (_) {/* het bestand staat goed; alleen de albumnaam bleef die van het nummer */}
}

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
/// [nu]: voor de toets.
Future<Versieuitslag?> bergOpAlsVersie(File src, Versieplan plan,
    {required String root, TrackTags? tags, DateTime Function()? nu, bool laatVerliezerStaan = false}) async {
  final soort = plan.soort;
  if (soort == null || !plan.isVersie) return null;
  final sinds = (nu ?? DateTime.now)().millisecondsSinceEpoch;
  switch (plan.besluit) {
    case Versiebesluit.gewoon:
      return null;

    case Versiebesluit.nieuweVersie:
      final map = versieMap(_map(plan.anker), soort, plan.persing);
      final doel = _vrij(File('$map${Platform.pathSeparator}${_stam(_naam(plan.anker))}${_ext(_naam(src.path))}'));
      await Directory(map).create(recursive: true);
      final at = await moveWithRetry(src, doel);
      if (tags != null) await stampTags(File(at), tags);
      await _zetVersieAlbum(at, _albumVan(plan.anker), soort, plan.persing);
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
      if (!firstIsBetter(src, File(oud.pad))) {
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
          tags: tags, staatAl: (artist, title, {int? seconds}) => oud.pad, parkeerAltijd: true);
      if (uit.how != Placement.moved) return (pad: oud.pad, werdAnker: false, verloor: true);
      await _zetVersieAlbum(uit.path, _albumVan(plan.anker), soort, plan.persing);
      versies.voegToe(
          plan.anker,
          Versie(
              pad: uit.path,
              soort: soort,
              persing: plan.persing.isEmpty ? oud.persing : plan.persing,
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
      final map = versieMap(_map(plan.anker), ankerSoort, plan.ankerPersing);
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
      await _zetVersieAlbum(opzij, album, ankerSoort, plan.ankerPersing);
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
