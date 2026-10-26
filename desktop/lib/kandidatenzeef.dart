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
///
/// Met [albumTitels] (de hele tracklijst van de plaat): staat het duet maar één keer op de plaat, dan telt alleen de
/// titel, ook als de strenge zeef al iets vond ([alleenDeTitel]).
List<SoulseekFile> zeefKandidatenNu(List<SoulseekFile> files,
    {required String titel, int? seconden, required String artiest, String? album, Iterable<String>? albumTitels}) {
  // Eerst de titel, dan de lengte: zo kan de lengte van de kopieën zelf meetellen ([lengteVanDeMeerderheid]) zonder dat
  // elk bestand twee keer langs [fileOffersTitle] moet.
  List<SoulseekFile> zeef(String t, {bool metMeerderheid = false}) {
    final metTitel = [
      for (final f in files)
        if (f.isAudio &&
            fileOffersTitle(t, null, artiest, f.filename, null, album: album) &&
            !algemeneTitelZonderAlbum(t, album, f.filename))
          f
    ];
    final lengte = (metMeerderheid ? lengteVanDeMeerderheid(metTitel, seconden) : null) ?? seconden;
    return [for (final f in metTitel) if (binnenLengteMarge(lengte, f.durationSec)) f];
  }

  final streng = zeef(titel, metMeerderheid: true);
  final kaal = albumTitels == null ? null : alleenDeTitel(titel, albumTitels);
  if (kaal != null) {
    // Een kaal bestand in een map waar een ander bestand de gast wél noemt, is daar de solo.
    final gast = gastWoorden(titel);
    bool noemtGast(SoulseekFile f) => gast.isNotEmpty && fileWords(baseName(f.filename)).containsAll(gast);
    final mappenMetGast = {for (final f in files) if (f.isAudio && noemtGast(f)) _map(f.filename)};
    final al = streng.toSet();
    return [
      ...streng,
      for (final f in zeef(kaal))
        if (!al.contains(f) && (noemtGast(f) || !mappenMetGast.contains(_map(f.filename)))) f,
    ];
  }
  if (streng.isNotEmpty) return streng;
  return zonderGast(files, titel: titel, seconden: seconden, artiest: artiest, album: album);
}

/// De lengtekeuring van [fileOffersTitle]: binnen 12 s, of een van beide onbekend.
bool binnenLengteMarge(int? verwacht, int? bestand) {
  final a = verwacht ?? 0, b = bestand ?? 0;
  return a <= 0 || b <= 0 || (a - b).abs() <= 12;
}

/// Zoveel uploaders moeten dezelfde andere lengte hebben voor [lengteVanDeMeerderheid].
const int kMeerderheidStemmen = 8;

/// Hebben zoveel uploaders de officiële lengte (±2 s), dan blijft die gelden — ook als de meeste een andere hebben.
const int kOfficieelBevestigd = 3;

/// Zo breed is een groep lengtes die als één lengte telt. Stond op 4 s. Gemeten op 26-10-2026 over 30 nummers uit
/// Sabers bibliotheek (12 waar zijn bestand en Deezer meer dan 12 s verschillen, 18 waar ze gelijk zijn): Foreigner, "I
/// Want to Know What Love Is" — Deezer 3:20, 1006 kopieën met de titel, geen enkele van 3:20, maar verspreid over
/// 4:56–5:08 (rips van verschillende persingen). Binnen 4 s haalde geen groep de helft, dus bleef 3:20 gelden en paste
/// er niets. Met 8 s grijpt de regel daar terecht in, en verder nergens anders dan met 4 s: geen enkele onterechte.
/// Met 12 s hetzelfde, maar dan kan een radio-edit vlak naast de albumversie meetellen.
const int kMeerderheidVenster = 8;

/// De lengte die de kopieën zelf noemen, als die duidelijk afwijkt van [officieel]; anders null, en dan geldt de
/// officiële.
///
/// **Saber, 25-10-2026, bij Jonas Brothers — "Kids Of The Future":** de uitgave op de albumpagina zegt 2:55, en in
/// SoulseekQt stonden tientallen FLAC's van 3:18–3:19 (Deezer: 198 s), ook in mappen als "Jonas Brothers (2007)". De
/// zeef hield er één over, de bronnenlijst zette de rest onder de mp3's, en na de overdracht zou de keuring (±12 s) een
/// goede kopie zelfs weigeren — *"is de filter ergens niet te streng ????"*.
///
/// [metTitel]: de bestanden met de juiste titel, de lengte nog niet gekeurd. Elke uploader stemt één keer per lengte die
/// hij heeft. De grootste groep (binnen [kMeerderheidVenster] s) moet minstens [kMeerderheidStemmen] stemmen en de helft van alle stemmen
/// hebben, en meer dan 12 s van [officieel] liggen; en minder dan [kOfficieelBevestigd] uploaders mogen de officiële
/// lengte hebben. Een radio-edit naast een albumversie blijft zo bij de officiële, zolang een paar mensen hem hebben.
/// Geeft het midden van de groep.
int? lengteVanDeMeerderheid(Iterable<SoulseekFile> metTitel, int? officieel) {
  if (officieel == null || officieel <= 0) return null;
  final perUploader = <String, List<int>>{};
  for (final f in metTitel) {
    final d = f.durationSec;
    if (d == null || d <= 0) continue;
    final al = perUploader.putIfAbsent(f.username, () => []);
    if (!al.any((x) => (x - d).abs() <= 2)) al.add(d);
  }
  final stemmen = [for (final l in perUploader.values) ...l]..sort();
  if (stemmen.length < kMeerderheidStemmen) return null;
  final bevestigd = {
    for (final e in perUploader.entries)
      if (e.value.any((d) => (d - officieel).abs() <= 2)) e.key
  };
  if (bevestigd.length >= kOfficieelBevestigd) return null;
  var van = 0, tot = 0;
  for (var i = 0, j = 0; i < stemmen.length; i++) {
    while (stemmen[i] - stemmen[j] > kMeerderheidVenster) {
      j++;
    }
    if (i + 1 - j > tot - van) {
      van = j;
      tot = i + 1;
    }
  }
  final groep = stemmen.sublist(van, tot);
  if (groep.length < kMeerderheidStemmen || groep.length * 2 < stemmen.length) return null;
  final midden = groep[groep.length ~/ 2];
  return (midden - officieel).abs() <= 12 ? null : midden;
}

/// De titel zonder gast, als alleen die titel moet tellen: [titel] noemt een gast, en geen ander nummer van de plaat
/// ([albumTitels]) heeft dezelfde titel zonder gast. Anders null.
///
/// Saber, 24-10-2026, bij Céline Dion *D'eux*: "J'irai où tu iras (with Jean-Jacques Goldman)" had 14 bronnen, de
/// andere nummers rond de 230 — "dat mag er zeker bij staan, maar voor soulseek resultaten … hij moet enkel de titel
/// zien". De gast blijft in de titel; de zeef kijkt naar de titel zonder hem. Behalve als dezelfde titel ook solo op
/// de plaat staat, zoals Adele's "Easy On Me" naast het duet met Chris Stapleton: dan is de gast het verschil.
String? alleenDeTitel(String titel, Iterable<String> albumTitels) {
  final kaal = titelZonderGast(titel);
  if (kaal == null) return null;
  final sleutel = _woorden(kaal).join(' ');
  for (final t in albumTitels) {
    if (t == titel) continue;
    if (_woorden(titelZonderGast(t) ?? t).join(' ') == sleutel) return null;
  }
  return kaal;
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

/// Voor elke titel van een plaat welke bestanden uit [files] het zijn — alle titels in één isolate, met één kopie van
/// de lijst. Per titel de plekken in [files], in de volgorde van [zeefKandidatenNu].
///
/// **Waarom (Saber, 23-10-2026: "als ik op de download pagina kom van de album hapert hij … ik wil niet inboeten in
/// het aantal sources").** De albumpagina zeefde voor het getal naast elke rij de hele albumbrede lijst, per rij, in
/// `build` en dus op de UI-draad. Elke nieuwe lijst wiste het geheugen, en dan rekenden alle zichtbare rijen in
/// hetzelfde beeld: op de Mac beelden van 1,2, 3,6 en 6,2 seconden (warmte.log, 23-10-2026). Nu rekent dit
/// erbuiten, en gaan alleen de plekken terug — geen duizenden bestanden heen en weer.
Future<List<List<int>>> zeefPerTitel(List<SoulseekFile> files, List<({String titel, int? seconden})> titels,
        {required String artiest, String? album}) =>
    Isolate.run(() => zeefPerTitelNu(files, titels, artiest: artiest, album: album));

/// Dezelfde zeef per titel, zonder isolate.
List<List<int>> zeefPerTitelNu(List<SoulseekFile> files, List<({String titel, int? seconden})> titels,
    {required String artiest, String? album}) {
  final plek = Map<SoulseekFile, int>.identity();
  for (var i = 0; i < files.length; i++) {
    plek[files[i]] = i;
  }
  // De hele tracklijst, zodat een duet dat maar één keer op de plaat staat op zijn titel alleen gezeefd wordt.
  final albumTitels = [for (final t in titels) t.titel];
  return [
    for (final t in titels)
      [
        for (final f in zeefKandidatenNu(files,
            titel: t.titel, seconden: t.seconden, artiest: artiest, album: album, albumTitels: albumTitels))
          plek[f]!,
      ],
  ];
}

/// Dezelfde zeef in een eigen isolate. Altijd, ook voor een korte lijst: een isolate opstarten kost
/// een paar milliseconden, en dit draait midden in een download die er seconden over doet.
///
/// Hier op het hoogste niveau en niet in een methode van de pagina: een sluiting die `this` vangt,
/// sleept de hele `State` mee naar de isolate, en dat weigert Dart.
Future<List<SoulseekFile>> zeefKandidaten(List<SoulseekFile> files,
        {required String titel, int? seconden, required String artiest, String? album, List<String>? albumTitels}) =>
    Isolate.run(() => zeefKandidatenNu(files,
        titel: titel, seconden: seconden, artiest: artiest, album: album, albumTitels: albumTitels));
