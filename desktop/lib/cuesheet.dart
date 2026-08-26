/// Een cuesheet lezen: waar begint welk nummer in dat ene grote bestand.
///
/// **Waarom dit moet bestaan.** Een groot deel van het lossless-aanbod op RuTracker is één
/// albumbestand — `.ape` of `.flac`, driehonderd megabyte — met een `.cue` ernaast. De app kende
/// `ape` alleen als woord in de kwaliteitsrangschikking en had nergens een cue-lezer. Een geslaagde
/// download leverde daarmee één blok in je bibliotheek in plaats van twaalf nummers, en er was geen
/// enkele weg om dat recht te zetten.
///
/// Dit bestand is met opzet ZUIVER: tekst in, gegevens uit. Geen bestandssysteem, geen ffmpeg, geen
/// netwerk. Daarmee is het knippen te toetsen zonder toestel en zonder ffmpeg — het enige wat er
/// vóór het uitgeven na te meten valt. Het draaien zelf staat apart.
///
/// **Wat een cuesheet is.** Regels met een woord vooraan:
///
/// ```
/// REM DATE 1998
/// PERFORMER "Artiest"
/// TITLE "Album"
/// FILE "album.ape" WAVE
///   TRACK 01 AUDIO
///     TITLE "Eerste nummer"
///     INDEX 01 00:00:00
///   TRACK 02 AUDIO
///     INDEX 00 04:32:10
///     INDEX 01 04:34:00
/// ```
///
/// Twee dingen die je fout kunt doen en die hier vastliggen:
///
/// * **`INDEX 00` is niet het begin van het nummer.** Dat is de aanloop — de stilte vóór het
///   nummer. `INDEX 01` is waar het nummer begint. Knip je op `INDEX 00`, dan plak je de stilte
///   vóór het volgende nummer in plaats van achter het vorige.
/// * **`mm:ss:ff` telt frames, geen honderdsten.** Een cd heeft er vijfenzeventig per seconde. Wie
///   `ff` als honderdsten leest zit er bij elk nummer een fractie naast, en dat hoor je: het begin
///   van het volgende nummer zit dan aan het eind van het vorige geplakt.
library;

import 'cp1251.dart';

/// Vijfenzeventig frames in een seconde. Dat is de cd, niet een keuze.
const framesPerSeconde = 75;

/// Eén nummer uit het blad.
class CueNummer {
  CueNummer({
    required this.nummer,
    required this.titel,
    required this.artiest,
    required this.bestand,
    required this.startFrames,
    this.eindeFrames,
  });

  /// Zoals het in de cue staat (`TRACK 07 AUDIO`), niet de plaats in de lijst — een blad mag bij een
  /// ander nummer beginnen dan 1.
  final int nummer;
  final String titel;
  final String artiest;

  /// Het bestand waar dit nummer in zit. Bij een dubbel-cd met twee images zijn dat er twee.
  final String bestand;

  final int startFrames;

  /// Waar het volgende nummer in DITZELFDE bestand begint, of null bij het laatste — dan loopt het
  /// tot het einde van het bestand, en dat weet alleen ffmpeg.
  final int? eindeFrames;

  double get startSeconden => startFrames / framesPerSeconde;
  double? get eindeSeconden =>
      eindeFrames == null ? null : eindeFrames! / framesPerSeconde;

  /// De duur in seconden, of null bij het laatste nummer van een bestand.
  double? get duurSeconden =>
      eindeFrames == null ? null : (eindeFrames! - startFrames) / framesPerSeconde;
}

/// Het hele blad.
class CueBlad {
  CueBlad({
    required this.album,
    required this.albumArtiest,
    required this.nummers,
    this.jaar,
    this.genre,
  });

  final String album;
  final String albumArtiest;
  final List<CueNummer> nummers;
  final String? jaar;
  final String? genre;

  /// De bestanden waar dit blad naar wijst, op volgorde en zonder herhaling.
  List<String> get bestanden {
    final uit = <String>[];
    for (final n in nummers) {
      if (!uit.contains(n.bestand)) uit.add(n.bestand);
    }
    return uit;
  }
}

/// `mm:ss:ff` naar frames, of null als het geen tijd is.
///
/// `mm` mag boven de negenenvijftig uitkomen: een cd loopt tot vierenzeventig minuten en een blad
/// schrijft dat gewoon als `74:30:00`, niet als uren.
int? framesUitTijd(String s) {
  final m = RegExp(r'^(\d+):([0-5]?\d):(\d{1,2})$').firstMatch(s.trim());
  if (m == null) return null;
  final mm = int.parse(m.group(1)!);
  final ss = int.parse(m.group(2)!);
  final ff = int.parse(m.group(3)!);
  if (ff >= framesPerSeconde) return null;
  return (mm * 60 + ss) * framesPerSeconde + ff;
}

/// De waarde achter een commando: tussen aanhalingstekens, of anders de rest van de regel.
///
/// `FILE "album.ape" WAVE` levert `album.ape` — het woord erachter is het soort en hoort er niet
/// bij. Zonder aanhalingstekens (dat komt voor) is het de rest, en dan moet dat soortwoord er wél
/// afgehaald worden.
String cueWaarde(String rest, {Set<String> zonderStaart = const {}}) {
  final t = rest.trim();
  if (t.startsWith('"')) {
    final eind = t.indexOf('"', 1);
    if (eind > 0) return t.substring(1, eind);
    return t.substring(1).trim();
  }
  if (zonderStaart.isEmpty) return t;
  final delen = t.split(RegExp(r'\s+'));
  if (delen.length > 1 && zonderStaart.contains(delen.last.toUpperCase())) {
    return delen.sublist(0, delen.length - 1).join(' ');
  }
  return t;
}

/// Lees het blad. Null als er geen enkel nummer in staat — dan is het geen cuesheet.
CueBlad? leesCue(String tekst) {
  var albumTitel = '';
  var albumArtiest = '';
  String? jaar;
  String? genre;

  var bestand = '';
  final ruw = <_Ruw>[];
  _Ruw? bezig;

  for (final regel in tekst.split(RegExp(r'\r\n|\r|\n'))) {
    final t = regel.trim();
    if (t.isEmpty) continue;
    final spatie = t.indexOf(RegExp(r'\s'));
    final woord = (spatie < 0 ? t : t.substring(0, spatie)).toUpperCase();
    final rest = spatie < 0 ? '' : t.substring(spatie + 1);

    switch (woord) {
      case 'REM':
        final r = rest.trim();
        final s = r.indexOf(RegExp(r'\s'));
        if (s < 0) break;
        final soort = r.substring(0, s).toUpperCase();
        final waarde = cueWaarde(r.substring(s + 1));
        if (soort == 'DATE') jaar = waarde;
        if (soort == 'GENRE') genre = waarde;
      case 'FILE':
        // WAVE, MP3, AIFF, BINARY — het soort zegt niets wat we hier nodig hebben.
        bestand = cueWaarde(rest, zonderStaart: const {'WAVE', 'MP3', 'AIFF', 'BINARY', 'MOTOROLA'});
      case 'TITLE':
        if (bezig == null) {
          albumTitel = cueWaarde(rest);
        } else {
          bezig.titel = cueWaarde(rest);
        }
      case 'PERFORMER':
        if (bezig == null) {
          albumArtiest = cueWaarde(rest);
        } else {
          bezig.artiest = cueWaarde(rest);
        }
      case 'TRACK':
        final delen = rest.trim().split(RegExp(r'\s+'));
        final nr = int.tryParse(delen.isEmpty ? '' : delen.first);
        if (nr == null) break;
        bezig = _Ruw(nr, bestand);
        ruw.add(bezig);
      case 'INDEX':
        if (bezig == null) break;
        final delen = rest.trim().split(RegExp(r'\s+'));
        if (delen.length < 2) break;
        final soort = int.tryParse(delen[0]);
        final frames = framesUitTijd(delen[1]);
        if (frames == null) break;
        // Alleen INDEX 01 telt als begin. INDEX 00 is de aanloop en hoort bij het VORIGE nummer;
        // zie de uitleg bovenaan.
        if (soort == 1) bezig.start = frames;
    }
  }

  final metStart = ruw.where((r) => r.start != null).toList();
  if (metStart.isEmpty) return null;

  final nummers = <CueNummer>[];
  for (var i = 0; i < metStart.length; i++) {
    final r = metStart[i];
    // Het einde is waar het volgende nummer begint — maar alleen als dat in HETZELFDE bestand zit.
    // Bij een dubbel-cd als twee images loopt het laatste nummer van schijf één tot het einde van
    // zijn eigen bestand, niet tot een tijdstip uit het bestand van schijf twee.
    final volgende = i + 1 < metStart.length ? metStart[i + 1] : null;
    final einde = volgende != null && volgende.bestand == r.bestand ? volgende.start : null;
    nummers.add(CueNummer(
      nummer: r.nummer,
      titel: r.titel.isNotEmpty ? r.titel : 'Nummer ${r.nummer}',
      artiest: r.artiest.isNotEmpty ? r.artiest : albumArtiest,
      bestand: r.bestand,
      startFrames: r.start!,
      eindeFrames: einde,
    ));
  }

  return CueBlad(
    album: albumTitel,
    albumArtiest: albumArtiest,
    nummers: nummers,
    jaar: jaar,
    genre: genre,
  );
}

/// Hetzelfde, maar vanaf de bytes zoals ze op schijf staan.
///
/// Een cue van een Russische persing is cp1251 en niet UTF-8, en dat is precies het bestand waar de
/// nummernamen in staan. Zie [tekstUitOnbekend] voor waarom er geen latin-1-vangnet onder ligt.
CueBlad? leesCueBytes(List<int> bytes) => leesCue(tekstUitOnbekend(bytes));

class _Ruw {
  _Ruw(this.nummer, this.bestand);
  final int nummer;
  final String bestand;
  String titel = '';
  String artiest = '';
  int? start;
}
