/// De oude kopieën in `_dubbel` nakijken, en wat een echt andere versie is terugzetten als versie (versies.dart).
///
/// Saber, 26-10-2026: "_dubbel nakijken en terugzetten" — daar stonden 411 kopieën (22 GB): wat ooit vervangen werd door
/// iets dat beter heette. Vandaag nog vervingen torrents zo minstens zeven cd's door vinylrips. Die cd's horen weer bij je
/// plaat: als versie, en volgens de vaste volgorde (studio > cd > vinyl) zelfs als het nummer — de vinylrip wordt dan de
/// versie.
///
/// Per bestand: zijn tags → het nummer in de bibliotheek → de vingerafdruk (minstens [maybeSameRecordingScore]: dezelfde
/// opname) → het besluit van versie_opbergen.dart. Wat dezelfde versie is als het nummer (twee cd-rips), of verliesgevend,
/// of nep, blijft in `_dubbel`. Niets wordt gewist: ook een kopie die verliest, blijft waar hij was.
///
/// Op de achtergrond, één bestand tegelijk; wat nagekeken is, wordt onthouden (`versies_dubbel.json`), zodat alleen nieuwe
/// kopieën in `_dubbel` een volgende keer aan de beurt komen.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'audioformaten.dart' show isVerliesvrij, soortVan;
import 'echtheid_oordelen.dart' show gemeten;
import 'fingerprint.dart';
import 'flac_tags.dart' show readFlacTags;
import 'vinyl.dart' show isVinylRip;
import 'kopiesoort.dart' show Kopiesoort, soortVoor, zetSoort;
import 'organize.dart' show TrackTags, parkeerAfgekeurd, parkeerMap, readTags;
import 'versie_opbergen.dart';
import 'versies.dart' show soortRang;
import 'warm_log.dart';

/// Wat de ronde deed.
typedef Terugzetuitslag = ({int bekeken, int versies, int nummers, int bleven});

class VersieTerugzetter {
  VersieTerugzetter({
    required this.wortel,
    required this.nummerVan,
    required this.klaar,
    required this.bestand,
    this.log,
    this.droog = false,
    this.bijBesluit,
    this.logboek,
    Fingerprinter? vingerafdruk,
  }) : _fp = vingerafdruk ?? Fingerprinter();

  /// Alleen kijken: zeggen wat er zou gebeuren, niets verplaatsen en niets onthouden (meten vóór het echt gebeurt).
  final bool droog;

  /// Per bestand wat er (zou) gebeuren.
  final void Function(String pad, String besluit)? bijBesluit;

  /// downloads.log: wat daar nog staat over een torrent die een nummer verving ([vinylUitLogboek]).
  final String? logboek;

  static final _vervangenDoorTorrent = RegExp(r'"(.+?) — (.+?)": vervangen door de kopie uit torrent "(.+)"\s*$');
  static final _diepteInNaam = RegExp(r'\b(16|24|32)[\s/_-]+(44|48|88|96|176|192|352|384)\b');

  /// Vandaag (26-10-2026) vervingen torrents cd's door vinylrips met alleen "[LP]" in hun naam, en dat herkende de app
  /// toen niet als vinyl. Wat [logboek] daarover nog weet, wordt alsnog onthouden — maar alleen als het bestand nog
  /// dezelfde diepte en frequentie heeft (anders werd het sindsdien vervangen), en nooit over een soort die je zelf
  /// koos. Geeft het aantal.
  int vinylUitLogboek() {
    final pad = logboek;
    if (pad == null) return 0;
    var n = 0;
    try {
      final f = File(pad);
      if (!f.existsSync()) return 0;
      for (final regel in f.readAsLinesSync()) {
        final m = _vervangenDoorTorrent.firstMatch(regel);
        if (m == null || !isVinylRip(m.group(3)!)) continue;
        final anker = nummerVan(m.group(1)!, m.group(2)!);
        if (anker == null || !File(anker).existsSync()) continue;
        final nu = soortVoor(anker);
        if (nu?.gekozen == true || nu?.soort == Kopiesoort.vinyl) continue;
        final d = _diepteInNaam.firstMatch(m.group(3)!);
        if (d != null) {
          final kop = readFlacTags(File(anker));
          final hz = int.parse(d.group(2)!);
          final kHz = (kop?.sampleRate ?? 0) ~/ 1000;
          if (kop == null || kop.bitsPerSample != int.parse(d.group(1)!) || kHz != hz) continue;
        }
        if (!droog) zetSoort(anker, Kopiesoort.vinyl);
        n++;
        log?.line('vinyl alsnog herkend uit downloads.log: ${m.group(1)} — ${m.group(2)} (${m.group(3)})');
      }
    } catch (_) {}
    return n;
  }

  /// De muziekmap (waar `_dubbel` in staat).
  final String wortel;

  /// Het nummer in de bibliotheek voor deze tags, of null (`LibraryStore.fileOfRecording`).
  final String? Function(String artiest, String titel, {int? seconden}) nummerVan;

  /// Na een ronde met iets teruggezet: de bibliotheek opnieuw inlezen.
  final Future<void> Function() klaar;

  /// Waar onthouden wordt wat er al nagekeken is.
  final String bestand;
  final WarmLog? log;
  final Fingerprinter _fp;

  bool _bezig = false;

  Future<Set<String>> _gedaan() async {
    try {
      final f = File(bestand);
      if (!await f.exists()) return {};
      final j = jsonDecode(await f.readAsString());
      return j is List ? {for (final x in j) '$x'} : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _bewaar(Set<String> gedaan) async {
    try {
      final f = File(bestand);
      await f.parent.create(recursive: true);
      await File('$bestand.tmp').writeAsString(jsonEncode(gedaan.toList()));
      await File('$bestand.tmp').rename(bestand);
    } catch (_) {}
  }

  /// Eén ronde over `_dubbel` (ook `_dubbel/binnengekomen`, niet `_dubbel/afgekeurd`: kapot is kapot).
  Future<Terugzetuitslag> ronde() async {
    if (_bezig) return (bekeken: 0, versies: 0, nummers: 0, bleven: 0);
    _bezig = true;
    var bekeken = 0, alsVersie = 0, alsNummer = 0, bleven = 0;
    try {
      final sep = Platform.pathSeparator;
      final dubbel = Directory('$wortel$sep$parkeerMap');
      if (!await dubbel.exists()) return (bekeken: 0, versies: 0, nummers: 0, bleven: 0);
      vinylUitLogboek();
      final gedaan = await _gedaan();
      final kapot = '$sep$parkeerAfgekeurd$sep'.toLowerCase();
      final bestanden = <File>[
        await for (final e in dubbel.list(recursive: true, followLinks: false))
          if (e is File && isVerliesvrij(soortVan(e.path)) && !e.path.toLowerCase().contains(kapot) && !gedaan.contains(e.path))
            e,
      ];
      for (final f in bestanden) {
        bekeken++;
        final uit = await _kijk(f);
        bijBesluit?.call(f.path, uit);
        if (droog) {
          if (!uit.startsWith('zou ')) {
            bleven++;
          } else if (uit.startsWith('zou het nummer')) {
            alsNummer++;
          } else {
            alsVersie++;
          }
          continue;
        }
        gedaan.add(f.path);
        switch (uit) {
          case 'versie':
            alsVersie++;
          case 'nummer':
            alsNummer++;
          default:
            bleven++;
        }
        if (bekeken % 20 == 0) await _bewaar(gedaan);
      }
      if (!droog) await _bewaar(gedaan);
      if (!droog && alsVersie + alsNummer > 0) await klaar();
      log?.line('_dubbel nagekeken: $bekeken bekeken, $alsVersie als versie terug, $alsNummer weer het nummer, '
          '$bleven bleven staan');
      return (bekeken: bekeken, versies: alsVersie, nummers: alsNummer, bleven: bleven);
    } finally {
      _bezig = false;
    }
  }

  /// Wat er met [f] gebeurde: 'versie', 'nummer', of waarom hij bleef.
  Future<String> _kijk(File f) async {
    try {
      // Nep (opgeschaald, uit een mp3) komt niet terug.
      if (gemeten(f.path)?.isNep ?? false) return 'nep';
      final tags = readTags(f);
      if (tags == null || tags.title.trim().isEmpty) return 'geen tags';
      final anker = nummerVan(tags.artist, tags.title, seconden: tags.seconds) ??
          nummerVan(tags.artist, tags.title);
      if (anker == null || !File(anker).existsSync()) return 'geen nummer';
      final a = await _fp.of(anker), b = await _fp.of(f.path);
      if (a == null || b == null || a.raw.isEmpty || b.raw.isEmpty) return 'geen vingerafdruk';
      final score = similarity(a.raw, b.raw, maxOffset: 120);
      if (score < maybeSameRecordingScore) return 'andere opname (${score.toStringAsFixed(2)})';
      // Alleen de bestandsnaam als bron: de mappen erboven ("D:\Flac music 2024\…\_dubbel") zeggen niets over de persing.
      // Wat de nultoets als je cd zag (bewerkt, of gedecodeerd), komt niet terug als eigen soort ([isNulTweeling]).
      await bereidNultoets(f.path, anker);
      await merkVinylspoor(f.path, anker, f.uri.pathSegments.last);
      var plan = versieplanVoor(f, anker, f.uri.pathSegments.last);
      if (!plan.isVersie) return 'dezelfde versie';
      // Wie hoger staat dan het nummer en tóch in _dubbel belandde, verloor met een reden — een "studiokopie" die van een
      // cd verloor, was opgeschaald (gemeten 26-10-2026: 18 van zulke in _dubbel). Die komt niet terug. Behalve tegenover
      // een vinylrip: die won alleen op zijn 24 bit, en de vaste volgorde is studio > cd > vinyl. Een cd mag dan weer het
      // nummer worden; een studiokopie alleen als de meting zegt dat hij echt is.
      final soort = plan.soort, ankerSoort = plan.ankerSoort;
      if (soort != null && ankerSoort != null && soortRang(soort) < soortRang(ankerSoort)) {
        final echt = gemeten(f.path) != null && !gemeten(f.path)!.isNep;
        final mag = ankerSoort == Kopiesoort.vinyl && (soort == Kopiesoort.cd || echt);
        if (!mag) return 'verloor eerder (${soort.name} tegen ${ankerSoort.name})';
      }
      plan = Versieplan(
          besluit: plan.besluit,
          anker: plan.anker,
          soort: plan.soort,
          persing: plan.persing,
          bron: '_dubbel',
          ankerSoort: plan.ankerSoort,
          ankerPersing: plan.ankerPersing,
          vervangt: plan.vervangt);
      if (droog) {
        return 'zou ${plan.besluit == Versiebesluit.ankerOpzij ? 'het nummer worden' : plan.besluit == Versiebesluit.vervangVersie ? 'een versie vervangen' : 'een versie worden'}: '
            '${plan.soort?.name} ${plan.persing} naast ${plan.ankerSoort?.name} (vingerafdruk ${score.toStringAsFixed(2)}) — $anker';
      }
      final uit = await bergOpAlsVersie(f, plan,
          root: wortel, tags: TrackTags(title: tags.title, artist: tags.artist, album: tags.album, trackNo: tags.trackNo),
          laatVerliezerStaan: true);
      if (uit == null || uit.verloor) return 'niet beter dan de versie die er al is';
      log?.line('_dubbel: ${tags.artist} — ${tags.title}: ${uit.werdAnker ? 'weer het nummer' : 'als versie terug'} '
          '(${plan.soort?.name}${plan.persing.isEmpty ? '' : ' ${plan.persing}'}, vingerafdruk ${score.toStringAsFixed(2)})');
      return uit.werdAnker ? 'nummer' : 'versie';
    } catch (e) {
      log?.line('_dubbel: ${f.path} — $e');
      return 'fout';
    }
  }
}
