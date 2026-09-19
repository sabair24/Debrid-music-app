/// Je klikt een nummer aan en krijgt een ander.
///
/// **Waarom dit bestaat.** Saber op 19-09-2026, met een schermafdruk van de nummerkeuze van een
/// RuTracker-torrent (Stevie Wonder — Talking Book, 24/96 LP): *"ik kreeg telkens de verkeerde songs
/// binnen?"* Nagespeeld op zijn scherm: "06 - Superstition" aangeklikt, en de app maakte
/// "09 - Lookin For Another Pure Love.flac" aan. Eerder die middag: "01 - You Are The Sunshine Of My
/// Life" aangeklikt, "02 - Maybe Your Baby" binnengekregen.
///
/// **De oorzaak: twee nummeringen van één torrent.** Voor een `.torrent` komt de nummerkeuze uit het
/// bestand zelf, en die nummert naar de plaats in dat bestand, vanaf 1 (`TorrentInhoud`, zoals aria2
/// het wil). Staat de torrent bij TorBox in de cache ("Instant"), dan gaat het downloaden via TorBox —
/// en TorBox deelt eigen nummers uit. Het nummer uit de lijst werd bij TorBox opgezocht. Superstition
/// staat in het torrentbestand op plaats 5, en TorBox' nummer 5 is Lookin For.
///
/// En het ▶-knopje in datzelfde venster gaf bij zo'n lijst altijd "Lege download-URL": het vroeg
/// TorBox om torrent 0, het nummer dat een lijst uit het bestand zelf draagt.
///
/// De lijsten hieronder zijn de ECHTE: die van TorBox opgevraagd bij Sabers account, die van het
/// torrentbestand afgelezen uit zijn nummerkeuze (die toont ze in bestandsvolgorde, ongesorteerd).
library;

import 'dart:io';

import 'package:debridmusic/torbox.dart';
import 'package:flutter_test/flutter_test.dart';

const _map = '(Funk, Soul) [LP] [2496] Stevie Wonder - Talking Book (1972) - 2011, FLAC (tracks+.cue)';

/// Zoals TorBox hem teruggaf: [id, bestandsnaam, bytes]. In TorBox' eigen volgorde van nummers.
const _torbox = [
  [0, '1972 - Stevie Wonder - Talking Book.cue', 1433],
  [1, '1972 - Stevie Wonder - Talking Book.jpg', 424582],
  [2, '08 - Blame It On The Sun.flac', 78081219],
  [3, '03 - You And I.flac', 101015886],
  [4, '07 - Big Brother.flac', 80942992],
  [5, '09 - Lookin For Another Pure Love.flac', 105640094],
  [6, '01 - You Are The Sunshine Of My Life.flac', 67009628],
  [7, '04 - Tuesday Heartbreak.flac', 70404792],
  [8, '10 - I Believe (When I Fall In Love It Will Be Forever).flac', 108034178],
  [9, '06 - Superstition.flac', 102991331],
  [10, '02 - Maybe Your Baby.flac', 161657213],
  [11, "05 - You've Got It Bad Girl.flac", 111954039],
  [12, '1972 - Stevie Wonder - Talking Book.txt', 6557],
  [13, 'Talking Book - Cover Front.jpg', 2661984],
  [14, 'Talking Book - Cover Rear.jpg', 2512031],
  [15, 'Talking Book - Label Side 1.jpg', 315332],
  [16, 'Talking Book - Label Side 2.jpg', 306834],
  [17, 'Talking Book - Gatefold.jpg', 3347219],
];

/// De nummers zoals de keuzelijst ze toonde, in de volgorde van het torrentbestand — nummer = plaats.
const _uitHetBestand = [
  '02 - Maybe Your Baby.flac',
  "05 - You've Got It Bad Girl.flac",
  '10 - I Believe (When I Fall In Love It Will Be Forever).flac',
  '09 - Lookin For Another Pure Love.flac',
  '06 - Superstition.flac',
  '03 - You And I.flac',
  '07 - Big Brother.flac',
  '08 - Blame It On The Sun.flac',
  '04 - Tuesday Heartbreak.flac',
  '01 - You Are The Sunshine Of My Life.flac',
];

List<TbFile> torboxLijst() => [
      for (final r in _torbox)
        TbFile(r[0] as int, '$_map/${r[1]}', r[1] as String, r[2] as int, null),
    ];

/// Zoals `_lokaleTracklist` ze maakt: nummer = plaats + 1, naam = pad in de torrent, zonder de map.
List<TbFile> eigenLijst() {
  final grootte = {for (final r in _torbox) r[1] as String: r[2] as int};
  return [
    for (var i = 0; i < _uitHetBestand.length; i++)
      TbFile(i + 1, _uitHetBestand[i], _uitHetBestand[i], grootte[_uitHetBestand[i]]!, null),
  ];
}

TbFile _in(List<TbFile> l, String naam) => l.firstWhere((f) => f.label == naam);

void main() {
  group('1 — hetzelfde bestand in de lijst van TorBox', () {
    test('DE VAL: op nummer koppelen geeft precies de twee verkeerde liedjes die Saber kreeg', () {
      final torbox = torboxLijst();
      final eigen = eigenLijst();
      TbFile opNummer(String naam) => torbox.firstWhere((f) => f.id == _in(eigen, naam).id);

      expect(opNummer('06 - Superstition.flac').label, '09 - Lookin For Another Pure Love.flac',
          reason: 'nagespeeld op zijn scherm op 19-09-2026');
      expect(opNummer('01 - You Are The Sunshine Of My Life.flac').label, '02 - Maybe Your Baby.flac',
          reason: 'zijn eigen poging van 17:13 die middag');
    });

    test('DE KERN: op naam en grootte komt elk nummer op zichzelf uit', () {
      final torbox = torboxLijst();
      for (final bedoeld in eigenLijst()) {
        final bij = zelfdeBestandIn(torbox, bedoeld);
        expect(bij, isNotNull, reason: '${bedoeld.label} niet gevonden');
        expect(bij!.label, bedoeld.label);
        expect(bij.size, bedoeld.size);
      }
      expect(zelfdeBestandIn(torbox, _in(eigenLijst(), '06 - Superstition.flac'))!.id, 9,
          reason: 'TorBox nummert Superstition als 9, niet als 5');
    });

    test('DE KERN: ook de andere kant op — een lijst van TorBox zelf blijft kloppen', () {
      // Kwam de keuzelijst van TorBox, dan is naam en grootte net zo goed als het nummer.
      final torbox = torboxLijst();
      final superstition = _in(torbox, '06 - Superstition.flac');
      expect(zelfdeBestandIn(torbox, superstition), same(superstition));
    });

    test('DE GRENS: twee keer dezelfde naam en grootte — het pad beslist', () {
      // Een box met schijfmappen: "01 - Intro.flac" in CD1 én CD2, en toevallig even groot.
      final torbox = [
        TbFile(4, 'Box/CD1/01 - Intro.flac', '01 - Intro.flac', 1000, null),
        TbFile(9, 'Box/CD2/01 - Intro.flac', '01 - Intro.flac', 1000, null),
      ];
      final bedoeld = TbFile(2, 'CD2/01 - Intro.flac', '01 - Intro.flac', 1000, null);
      expect(zelfdeBestandIn(torbox, bedoeld)!.id, 9);
    });

    test('DE GRENS: niets eenduidigs te kiezen — dan niets, en geen gok', () {
      // Liever "staat niet bij TorBox" dan het verkeerde liedje: dat was precies de klacht.
      final torbox = [
        TbFile(1, 'A/x.flac', 'x.flac', 500, null),
        TbFile(2, 'A/y.flac', 'y.flac', 500, null),
      ];
      expect(zelfdeBestandIn(torbox, TbFile(7, 'z.flac', 'z.flac', 500, null)), isNull,
          reason: 'twee even grote bestanden en geen naam die past');
      expect(zelfdeBestandIn(torbox, TbFile(7, 'z.flac', 'z.flac', 999, null)), isNull,
          reason: 'naam en grootte passen allebei nergens');
    });

    test('DE GRENS: een naam die onderweg gesaneerd is, vindt hij op zijn grootte terug', () {
      final torbox = [
        TbFile(3, 'P!nk/01 - So What.flac', '01 - So What.flac', 777, null),
        TbFile(4, 'P!nk/02 - Sober.flac', '02 - Sober.flac', 888, null),
      ];
      expect(zelfdeBestandIn(torbox, TbFile(1, '01 - So What_.flac', '01 - So What_.flac', 777, null))!.id, 3);
    });
  });

  group('2 — de app gebruikt die koppeling ook werkelijk', () {
    // De download- en afspeelweg lopen via TorBox en het net; die zijn hier niet te draaien. Deze
    // toetsen kijken naar de brontekst, zodat een verhuizing of opschoning de reparatie niet stil
    // kan laten verdwijnen.
    String lees(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    final online = lees('lib/online.dart');
    final main = lees('lib/main.dart');
    final server = lees('lib/lan/server.dart');
    final remote = lees('lib/lan/remote_services.dart');

    String lijf(String bron, String begin) {
      final i = bron.indexOf(begin);
      expect(i, greaterThan(0), reason: '"$begin" niet gevonden');
      return bron.substring(i, bron.indexOf('\n  }\n', i));
    }

    test('DE KERN: de TorBox-weg van het downloaden koppelt op naam en grootte', () {
      final r = lijf(online, 'Future<(TbTorrent, List<TbFile>)> resolveForDownload(');
      // Alleen de code: het commentaar citeert de oude regel juist om te zeggen waarom hij weg is.
      final code = r.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(code, contains('zelfdeBestandIn('));
      expect(code, isNot(contains('item.files.where((f) => f.id == fileId)')),
          reason: 'het nummer uit de keuzelijst bij TorBox opzoeken gaf het verkeerde liedje');
      expect(r, contains('_uitEigenLijst('),
          reason: 'een oud toestel stuurt alleen het nummer; dat moet eerst vertaald worden');
    });

    test('DE KERN: het keuzevenster geeft het bestand zelf mee en speelt via speelUrl', () {
      expect(main, contains('enqueue(widget.result, fileId: f.id, bestand: f, klaar: _torrent)'));
      expect(main, contains('speelUrl(widget.result, _torrent!, f)'),
          reason: 'resolveTrackUrl(_torrent!.id, …) vroeg TorBox om torrent 0: "Lege download-URL"');
    });

    test('DE VAL: ook het toestel stuurt naam en grootte mee, en de pc neemt ze aan', () {
      expect(remote, contains("'fileSize': bestand.size"));
      final s = lijf(server, 'void startTorrentDownload(');
      expect(s, contains("body['fileSize']"));
      expect(s, contains('bestand: bestand'));
    });

    test('DE VAL: een download die nog schrijft wordt niet opgeborgen', () {
      // Nagemeten op Sabers schijf: een afgekapte "02 - Maybe Your Baby.flac" van 71,5 MB (3:00 van
      // de 6:50) in _dubbel. Twee nummers uit één torrent, en wie eerst klaar was borg ook het
      // bestand op dat de ander nog schreef.
      final d = lijf(online, 'Future<void> _download(int torrentId, TbFile f, Directory destDir, DownloadJob job)');
      final erbij = d.indexOf('_inAanmaak.add(gelandPad)');
      final vast = d.indexOf('await _jouwKeuze(gelandPad)');
      final eraf = d.lastIndexOf('_inAanmaak.remove(gelandPad)');
      expect(erbij, greaterThan(0), reason: 'het halve bestand moet gemarkeerd zijn zolang het groeit');
      expect(eraf, greaterThan(vast),
          reason: 'pas vrijgeven NA de vaste keuze, anders kan een ander hem onbeschermd opbergen');
      final berg = lijf(online, 'Future<void> _bergTorrentOp(');
      expect(berg, contains('slaOver: _inAanmaak.contains'));
    });

    test('DE VAL: ook wat aria2 nog kopieert telt als "nog niet af"', () {
      final v = lijf(online, 'Future<String?> _verhuisNaar(');
      expect(v.indexOf('_inAanmaak.add(doel.path)'), lessThan(v.indexOf('await bron.copy(doel.path)')),
          reason: 'tijdens het kopiëren staat er een half bestand in de map');
    });
  });
}
