/// Welke bestanden uit een Soulseek-zoekopdracht één bepaald nummer van de plaat zijn — buiten de
/// UI-draad als het er veel zijn.
///
/// **Waarom dit apart staat.** "Ontbrekende downloaden" op de albumpagina zocht één keer voor de
/// hele plaat en zeefde die lijst daarna per ontbrekend nummer met [fileOffersTitle]. Op de S26 stond
/// de UI-draad daarbij 2078 ms stil (warmte.log, 11-10-2026, *Morning Glory*, elf nummers). Gemeten op
/// de pc: 5,3 µs per bestand, dus elf nummers over 4400 bestanden is 254 ms, en een telefoon doet er
/// een veelvoud over. Dat het één blok werd en geen elf kleine, kwam doordat het albumbrede resultaat
/// na het eerste nummer klaarligt: elke volgende beurt liep als microtaak door zonder de draad ooit
/// vrij te geven.
library;

import 'dart:isolate';

import 'organize.dart' show baseName, fileOffersTitle, fileWords, gastWoorden, titelZonderGast;
import 'soulseek.dart' show SoulseekFile;

/// De zeef zelf, zonder isolate. Voor wie hem op één titel tegelijk nodig heeft en het resultaat
/// onthoudt, zoals de telling naast elke rij op de catalogusalbumpagina.
///
/// Vindt de strenge zeef niets bij een titel met een gast, dan [zonderGast].
List<SoulseekFile> zeefKandidatenNu(List<SoulseekFile> files,
    {required String titel, int? seconden, required String artiest, String? album}) {
  final streng = [
    for (final f in files)
      if (f.isAudio &&
          fileOffersTitle(titel, seconden, artiest, f.filename, f.durationSec, album: album) &&
          !algemeneTitelZonderAlbum(titel, album, f.filename))
        f
  ];
  if (streng.isNotEmpty) return streng;
  return zonderGast(files, titel: titel, seconden: seconden, artiest: artiest, album: album);
}

/// Titels die op duizenden platen staan. Daar zegt de titel samen met de lengte niet welk nummer het is.
const _algemeen = {
  'intro', 'introduction', 'outro', 'interlude', 'skit', 'prelude', 'prologue', 'epilogue', 'overture',
  'intermission', 'segue', 'opening', 'finale', 'coda', 'untitled', 'hidden track', 'bonus track',
};

final _nietWoord = RegExp(r'[^a-z0-9]+');

List<String> _woorden(String s) => s.toLowerCase().split(_nietWoord).where((w) => w.isNotEmpty).toList();

/// Is [titel] een titel als "Intro", en noemen de mappen boven [pad] het [album] niet?
///
/// **Gemeld op 15-10-2026:** op *V* van Live stonden naast "Intro" (0:37) 16 bronnen, en de meeste
/// waren intro's van live-albums van anderen: de titel klopt, de lengte valt binnen 12 seconden, en de
/// artiest wordt in het pad niet gecontroleerd — bij de band Live staat "live" bovendien overal. Bij
/// zo'n titel telt een bestand dus alleen als zijn mappen alle woorden van het album noemen, ook een
/// woord van één letter ("V"). Liever geen bron dan het intro van een andere plaat.
bool algemeneTitelZonderAlbum(String titel, String? album, String pad) {
  if (!_algemeen.contains(_woorden(titel).join(' '))) return false;
  final a = _woorden((album ?? '').replaceAll(RegExp(r'\s*[\[(][^\])]*[\])]\s*$'), ''));
  if (a.isEmpty) return false;
  final mappen = _woorden(_map(pad)).toSet();
  return !mappen.containsAll(a);
}

String _map(String pad) {
  final i = pad.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? '' : pad.substring(0, i);
}

/// De terugval voor een titel met een gast die de bestandsnamen niet noemen.
///
/// **Het gemelde geval, 15-10-2026.** Amel Bent, *À 20 ans* (2007), nummer 3: Deezer noemt het "À 20
/// ans (feat. Diam's)", en bij elke peer heet het bestand "03. A 20 Ans.flac" — 231 seconden, precies
/// de 3:51 van de plaat. [fileOffersTitle] eist alle woorden van de titel, dus ook "feat" en "diam", en
/// hield van de drie woorden er één over: geen enkele bron, terwijl de andere nummers er 13 tot 16 hadden.
///
/// **Waarom niet gewoon de gast laten vallen.** Een gast kan het verschil zíjn: "Easy On Me" van Adele
/// bestaat solo én als duet. Daarom alleen als de strenge zeef niets vond, en dan alleen een bestand
///
/// * in een map die het ALBUM noemt — het is nummer zoveel van deze plaat, en op deze plaat is het het
///   duet;
/// * met een lengte binnen 3 seconden van de officiële, en beide lengtes bekend;
/// * in een map waarin géén ander bestand de gast wél noemt — staat daar een aparte versie mét de gast,
///   dan is het kale bestand de solo.
List<SoulseekFile> zonderGast(List<SoulseekFile> files,
    {required String titel, int? seconden, required String artiest, String? album}) {
  final kaal = titelZonderGast(titel);
  final a = album?.trim() ?? '';
  if (kaal == null || a.isEmpty || seconden == null || seconden <= 0) return const [];
  final albumWoorden = fileWords(a.replaceAll(RegExp(r'\s*[\[(][^\])]*[\])]\s*$'), ''));
  if (albumWoorden.isEmpty) return const [];
  final gast = gastWoorden(titel);
  final mappenMetGast = {
    for (final f in files)
      if (f.isAudio && gast.isNotEmpty && fileWords(baseName(f.filename)).containsAll(gast)) _map(f.filename)
  };
  return [
    for (final f in files)
      if (f.isAudio &&
          f.durationSec != null &&
          (f.durationSec! - seconden).abs() <= 3 &&
          !mappenMetGast.contains(_map(f.filename)) &&
          fileWords(_map(f.filename).replaceAll(RegExp(r'[\\/]'), ' ')).containsAll(albumWoorden) &&
          fileOffersTitle(kaal, seconden, artiest, f.filename, f.durationSec, album: album))
        f
  ];
}

/// Dezelfde zeef in een eigen isolate. Altijd, ook voor een korte lijst: een isolate opstarten kost
/// een paar milliseconden, en dit draait midden in een download die er seconden over doet.
///
/// Hier op het hoogste niveau en niet in een methode van de pagina: een sluiting die `this` vangt,
/// sleept de hele `State` mee naar de isolate, en dat weigert Dart.
Future<List<SoulseekFile>> zeefKandidaten(List<SoulseekFile> files,
        {required String titel, int? seconden, required String artiest, String? album}) =>
    Isolate.run(() =>
        zeefKandidatenNu(files, titel: titel, seconden: seconden, artiest: artiest, album: album));
