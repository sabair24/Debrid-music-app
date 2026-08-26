/// Eén groot albumbestand terugbrengen tot losse nummers.
///
/// **Waarom dit bestaat.** Een groot deel van het lossless-aanbod — op RuTracker bijna de helft —
/// is één bestand van een gigabyte met een `.cue` ernaast: `(image+.cue)`. Zonder dit bestand
/// levert zo'n download één blok van vijftig minuten op. Eén regel in je bibliotheek in plaats van
/// twaalf, geen nummernamen, en niet door te spoelen naar nummer zeven.
///
/// [leesCue] in `cuesheet.dart` kon dat blad al lezen — volledig, mét toetsen — maar niemand
/// riep hem aan. Dit is de andere helft: van een gelezen blad naar bestanden op schijf.
///
/// **De verdeling in dit bestand is met opzet.** [knipPlan] en [ffmpegArgumenten] zijn ZUIVER:
/// namen en getallen in, namen en getallen uit. Geen schijf, geen ffmpeg. Dat is precies het stuk
/// dat stil fout gaat — een bestand dat niet gevonden wordt, een `-ss` aan de verkeerde kant van
/// `-i` — en het enige dat hier, zonder toestel en zonder ffmpeg, na te meten valt. [Knipper]
/// eronder doet het vuile werk en is niet te toetsen; die houdt daarom zo min mogelijk denkwerk.
library;

import 'dart:io';

import 'cuesheet.dart';
import 'ffmpeg.dart';

/// Waar een albumbestand in kan staan.
///
/// `ape` en `tta` staan er nadrukkelijk bij: die kan de app zelf niet lezen, maar ffmpeg wel. Een
/// APE-image die hier langskomt wordt dus verliesloos FLAC, en daarmee voor het eerst afspeelbaar.
const kBeeldExtensies = {
  'flac', 'ape', 'wav', 'wv', 'tta', 'aiff', 'aif', 'alac', 'm4a', 'ogg', 'mp3',
};

/// Kleiner dan dit is geen nummer maar een mislukking van ffmpeg die niets zei.
const kMinimumBytes = 1024;

final _verbodenTekens = RegExp(r'[\\/:*?"<>|\x00-\x1f]');
final _teveelSpaties = RegExp(r'\s+');

/// Een naam waar Windows geen bezwaar tegen maakt.
///
/// Ook de staart: een naam die op een punt of een spatie eindigt is op Windows niet aan te maken,
/// en dat levert een fout op die niets zegt over de echte oorzaak.
String veiligeNaam(String s) {
  var uit = s.replaceAll(_verbodenTekens, '_').replaceAll(_teveelSpaties, ' ').trim();
  uit = uit.replaceAll(RegExp(r'[. ]+$'), '');
  return uit.isEmpty ? 'Naamloos' : uit;
}

/// Eén nummer dat uit een groot bestand gehaald moet worden.
///
/// Namen zonder pad: [knipPlan] weet niet in welke map hij werkt, en hoeft dat ook niet te weten.
class Knip {
  const Knip({
    required this.bronNaam,
    required this.doelNaam,
    required this.start,
    required this.duur,
    required this.titel,
    required this.artiest,
    required this.album,
    required this.albumArtiest,
    required this.nummer,
    required this.totaal,
    this.jaar,
    this.genre,
  });

  final String bronNaam;
  final String doelNaam;

  /// Seconden vanaf het begin van het grote bestand.
  final double start;

  /// Hoe lang dit nummer duurt, of null bij het laatste — dan loopt het tot het einde van het
  /// bestand, en die lengte weet alleen ffmpeg.
  final double? duur;

  final String titel, artiest, album, albumArtiest;
  final int nummer, totaal;
  final String? jaar, genre;
}

String _extensie(String naam) {
  final i = naam.lastIndexOf('.');
  return i < 0 ? '' : naam.substring(i + 1).toLowerCase();
}

String _stam(String naam) {
  final i = naam.lastIndexOf('.');
  return (i < 0 ? naam : naam.substring(0, i)).toLowerCase();
}

bool _isBeeld(String naam) => kBeeldExtensies.contains(_extensie(naam));

/// Welk bestand op schijf bedoelt de cue met deze naam?
///
/// Drie wegen, want een cue en de map waar hij in ligt komen geregeld niet overeen:
///
/// 1. gewoon dezelfde naam;
/// 2. dezelfde stam, andere extensie — een blad dat bij het rippen gemaakt is zegt `album.wav`
///    terwijl er `album.flac` ligt. Dat is eerder regel dan uitzondering;
/// 3. wijst het blad naar één bestand en ligt er precies één albumbestand, dan is dát het. De
///    naam kan onderweg gesaneerd zijn (`P!nk` wordt `P_nk` als er een `?` in stond), en dan
///    matcht geen van beide andere wegen terwijl er geen enkele twijfel is.
String? zoekBronbestand(String uitCue, List<String> inMap) {
  final laag = uitCue.toLowerCase();
  for (final b in inMap) {
    if (b.toLowerCase() == laag) return b;
  }
  final stam = _stam(uitCue);
  for (final b in inMap) {
    if (_stam(b) == stam && _isBeeld(b)) return b;
  }
  return null;
}

/// Wat er uit dit blad te knippen valt, gegeven wat er in de map ligt.
///
/// Leeg betekent: hier valt niets te doen. Dat is geen fout — een cue naast twaalf losse bestanden
/// is precies wat je wil hebben, en die hoort met rust gelaten te worden.
List<Knip> knipPlan({required CueBlad blad, required List<String> bestandenInMap}) {
  final beelden = bestandenInMap.where(_isBeeld).toList();
  final uitCue = blad.bestanden;

  // Welk bestand op schijf hoort bij welke naam in het blad.
  final vertaling = <String, String>{};
  for (final naam in uitCue) {
    final gevonden = zoekBronbestand(naam, bestandenInMap);
    if (gevonden != null) {
      vertaling[naam] = gevonden;
    } else if (uitCue.length == 1 && beelden.length == 1) {
      vertaling[naam] = beelden.single;
    }
  }

  // Per bronbestand de nummers die erin zitten, op volgorde van het blad.
  final perBron = <String, List<CueNummer>>{};
  for (final n in blad.nummers) {
    final bron = vertaling[n.bestand];
    if (bron == null) continue;
    perBron.putIfAbsent(bron, () => []).add(n);
  }

  final uit = <Knip>[];
  final gebruikteNamen = <String>{for (final b in bestandenInMap) b.toLowerCase()};
  for (final entry in perBron.entries) {
    final nummers = entry.value;
    // Eén nummer in een bestand is geen image maar gewoon een nummer met een blad ernaast. Daar
    // valt niets te winnen, en het zou een geldig bestand door ffmpeg halen voor niets.
    if (nummers.length < 2) continue;

    for (final n in nummers) {
      final basis = '${n.nummer.toString().padLeft(2, '0')} - ${veiligeNaam(n.titel)}';
      var doel = '$basis.flac';
      // Twee nummers met dezelfde titel op één plaat komt voor (een reprise, een hidden track).
      // Zonder deze lus overschrijft de tweede de eerste, en dan is er stilletjes een nummer weg.
      var n2 = 2;
      while (gebruikteNamen.contains(doel.toLowerCase())) {
        doel = '$basis ($n2).flac';
        n2++;
      }
      gebruikteNamen.add(doel.toLowerCase());

      uit.add(Knip(
        bronNaam: entry.key,
        doelNaam: doel,
        start: n.startSeconden,
        duur: n.duurSeconden,
        titel: n.titel,
        artiest: n.artiest.isNotEmpty ? n.artiest : blad.albumArtiest,
        album: blad.album,
        albumArtiest: blad.albumArtiest,
        nummer: n.nummer,
        totaal: nummers.length,
        jaar: blad.jaar,
        genre: blad.genre,
      ));
    }
  }
  return uit;
}

/// De opdracht voor ffmpeg. Zuiver, want hier zit de fout die je niet ziet.
///
/// **`-ss` staat vóór `-i`, en dat is een keuze.** Erachter laat ffmpeg het hele bestand
/// decoderen en gooit alles vóór het startpunt weg: op een image van een gigabyte is dat bij nummer
/// twaalf een paar minuten wachten, twaalf keer achter elkaar. Ervoor springt hij er meteen heen, en
/// bij FLAC is dat samplenauwkeurig — precies waarom de tijd hier in seconden met zes cijfers gaat
/// en niet in hele seconden.
///
/// **`-t` en niet `-to`.** Met een `-ss` vóór de invoer telt `-to` in sommige ffmpeg-versies vanaf
/// het begin van het bestand en in andere vanaf het startpunt. Dat verschil hoor je pas als het
/// laatste nummer een halve seconde lang is. `-t` is een duur, en dat betekent overal hetzelfde.
///
/// **`-map_metadata -1`** gooit de labels van het grote bestand weg. Die zeggen dat dit
/// "Beautiful Trauma" heet — de plaat — en zonder dit heten alle twaalf de nummers zo.
List<String> ffmpegArgumenten(Knip k, {required String bronPad, required String doelPad}) => [
      '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
      '-ss', k.start.toStringAsFixed(6),
      '-i', bronPad,
      if (k.duur != null) ...['-t', k.duur!.toStringAsFixed(6)],
      '-map_metadata', '-1',
      '-c:a', 'flac', '-compression_level', '5',
      '-metadata', 'TITLE=${k.titel}',
      '-metadata', 'ARTIST=${k.artiest}',
      '-metadata', 'ALBUM=${k.album}',
      if (k.albumArtiest.isNotEmpty) ...['-metadata', 'ALBUMARTIST=${k.albumArtiest}'],
      '-metadata', 'TRACKNUMBER=${k.nummer}',
      '-metadata', 'TRACKTOTAL=${k.totaal}',
      if (k.jaar != null && k.jaar!.isNotEmpty) ...['-metadata', 'DATE=${k.jaar}'],
      if (k.genre != null && k.genre!.isNotEmpty) ...['-metadata', 'GENRE=${k.genre}'],
      doelPad,
    ];

/// De eerste zinvolle regel uit ffmpegs foutuitvoer, kort genoeg voor een regel op het scherm.
///
/// Null als er niets bruikbaars in staat — dan is het getal van de afsluitcode alles wat er is, en
/// dat is nog altijd meer dan zwijgen.
String? _eersteRegel(Object? stderr) {
  final tekst = stderr is String ? stderr : '';
  for (final r in tekst.split(RegExp(r'\r\n|\r|\n'))) {
    final t = r.trim();
    if (t.isEmpty) continue;
    return t.length > 120 ? '${t.substring(0, 119)}…' : t;
  }
  return null;
}

/// Wat het knippen opleverde. Nooit stil: `melding` zegt altijd iets, ook als er niets gebeurd is.
class KnipUitkomst {
  const KnipUitkomst({this.nummers = 0, this.platen = 0, this.melding = ''});

  /// Hoeveel losse nummers er nu staan.
  final int nummers;

  /// Hoeveel grote bestanden er opgeknipt zijn.
  final int platen;

  /// Wat er te melden valt — leeg als er niets te knippen was.
  final String melding;

  bool get iets => nummers > 0;
}

/// Het knippen zelf: ffmpeg aansturen en opruimen.
///
/// Deze klasse is niet te toetsen zonder ffmpeg en zonder schijf, en houdt daarom zo min mogelijk
/// denkwerk vast: het plannen doet [knipPlan], de opdracht bouwt [ffmpegArgumenten].
class Knipper {
  Knipper({String? ffmpegPad}) : _ff = Ffmpeg(pad: ffmpegPad);

  final Ffmpeg _ff;

  bool get beschikbaar => _ff.available;

  /// Elk `.cue` in deze map nalopen en knippen wat er te knippen valt.
  ///
  /// [onVoortgang] krijgt (gedaan, totaal) na elk nummer, zodat de downloadlijst een balk kan tonen
  /// in plaats van minutenlang niets.
  Future<KnipUitkomst> knipMap(Directory map, {void Function(int, int)? onVoortgang}) async {
    List<FileSystemEntity> inhoud;
    try {
      inhoud = map.listSync();
    } catch (e) {
      return KnipUitkomst(melding: 'Kon de downloadmap niet lezen: $e');
    }
    final bestanden = [
      for (final e in inhoud.whereType<File>()) e.uri.pathSegments.last,
    ];
    final cueNamen = bestanden.where((b) => _extensie(b) == 'cue').toList()..sort();
    if (cueNamen.isEmpty) return const KnipUitkomst();

    // Eerst uitrekenen wat er te doen valt, en pas daarna naar ffmpeg vragen.
    //
    // Andersom was fout op een manier die je pas op het toestel ziet: een cue naast twaalf losse
    // nummers is de GOEDE situatie, en dan hoort er niets te gebeuren en niets gemeld te worden. Wie
    // hier eerst op ffmpeg controleert, plakt "ffmpeg staat niet op deze pc" onder elke download die
    // toevallig een blad meebracht.
    final plannen = <String, List<Knip>>{};
    for (final cueNaam in cueNamen) {
      CueBlad? blad;
      try {
        blad = leesCueBytes(
            await File('${map.path}${Platform.pathSeparator}$cueNaam').readAsBytes());
      } catch (_) {
        blad = null;
      }
      if (blad == null) continue;
      final plan = knipPlan(blad: blad, bestandenInMap: bestanden);
      if (plan.isNotEmpty) plannen[cueNaam] = plan;
    }
    if (plannen.isEmpty) return const KnipUitkomst();

    final exe = _ff.pad;
    if (exe == null) {
      // Hier wél melden, want hier valt er écht iets te knippen en gebeurt het niet. Het grote
      // bestand blijft gewoon staan en speelt af als één blok — maar dan moet iemand vertellen
      // waarom er geen twaalf nummers staan.
      return const KnipUitkomst(
          melding: 'Dit is één albumbestand met een cue, maar ffmpeg staat niet op deze pc — '
              'niet in nummers geknipt.');
    }

    var nummers = 0;
    var platen = 0;
    final klachten = <String>[];
    final teDoen = plannen.values.fold<int>(0, (n, p) => n + p.length);

    for (final cueNaam in plannen.keys) {
      final cueBestand = File('${map.path}${Platform.pathSeparator}$cueNaam');
      final plan = plannen[cueNaam]!;

      // Per bronbestand afhandelen: een dubbel-cd is één blad met twee images, en als schijf twee
      // stukloopt hoort schijf één toch gewoon geknipt te blijven.
      final perBron = <String, List<Knip>>{};
      for (final k in plan) {
        perBron.putIfAbsent(k.bronNaam, () => []).add(k);
      }

      var mislukt = false;
      for (final entry in perBron.entries) {
        final bronPad = '${map.path}${Platform.pathSeparator}${entry.key}';
        // Een uitgave met twee bladen die naar hetzelfde bestand wijzen komt voor. Het eerste blad
        // heeft het dan al geknipt en opgeruimd; zonder deze regel loopt het tweede stuk op een
        // bestand dat er niet meer is, en staat er een foutmelding onder een download die klopte.
        if (!File(bronPad).existsSync()) continue;
        final gemaakt = <File>[];
        var stuk = '';

        for (final k in entry.value) {
          final doel = File('${map.path}${Platform.pathSeparator}${k.doelNaam}');
          try {
            final r = await Process.run(
                exe, ffmpegArgumenten(k, bronPad: bronPad, doelPad: doel.path));
            if (r.exitCode != 0) {
              // Zijn eigen woorden erbij. `-loglevel error` houdt het kort, en zonder deze regel
              // staat er alleen een getal op het scherm waar niemand iets mee kan.
              stuk = 'nummer ${k.nummer}: ${_eersteRegel(r.stderr) ?? "ffmpeg gaf ${r.exitCode}"}';
            } else if (!doel.existsSync() || doel.lengthSync() < kMinimumBytes) {
              stuk = 'nummer ${k.nummer} kwam er leeg uit';
            } else {
              gemaakt.add(doel);
            }
          } catch (e) {
            stuk = 'ffmpeg liep vast op nummer ${k.nummer}: $e';
          }
          if (stuk.isNotEmpty) break;
          onVoortgang?.call(nummers + gemaakt.length, teDoen);
        }

        if (stuk.isNotEmpty) {
          // Alles terugdraaien wat van dit bestand gemaakt is. Een half opgeknipte plaat is erger
          // dan een niet-opgeknipte: dan staat er zes van de twaalf nummers in je bibliotheek én
          // het hele album er nog een keer naast.
          for (final f in gemaakt) {
            try {
              f.deleteSync();
            } catch (_) {}
          }
          klachten.add(stuk);
          mislukt = true;
          continue;
        }

        // Pas nu weg, en geen byte eerder: elk nummer bestaat, elk nummer heeft inhoud. Het
        // origineel is het enige waar dit nog uit te halen valt als er iets misging.
        try {
          File(bronPad).deleteSync();
        } catch (_) {/* in gebruik — dan blijft hij staan, en dat is niet erg */}
        nummers += gemaakt.length;
        platen++;
      }

      // De cue kan weg zodra alles waar HIJ naar wees geknipt is; hij wijst nu nergens meer heen.
      //
      // Per blad kijken en niet naar de klachtenlijst als geheel: bij twee bladen in één map zou
      // een mislukking in het eerste ook het tweede blad laten staan, naast nummers die er wél
      // netjes uit gekomen zijn.
      if (!mislukt) {
        try {
          cueBestand.deleteSync();
        } catch (_) {}
      }
    }

    if (nummers == 0) {
      return KnipUitkomst(
          melding: klachten.isEmpty ? '' : 'Knippen mislukt: ${klachten.first}');
    }
    return KnipUitkomst(
      nummers: nummers,
      platen: platen,
      melding: klachten.isEmpty
          ? 'In $nummers nummers geknipt'
          : 'In $nummers nummers geknipt, maar: ${klachten.first}',
    );
  }
}
