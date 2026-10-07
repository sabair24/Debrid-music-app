/// Gelijk volume — het meten zelf, met echte ffmpeg, en de veger die de bibliotheek afloopt.
///
/// **Waarom dit bestaat.** Saber op 07-10-2026 wilde alle nummers even hard, "zonder enige verlies van
/// kwaliteit". De meting is waar dat op rust: een verkeerd gelezen piek laat een nummer afknippen,
/// een mono-opname die als stereo gemeten wordt komt 3 dB te stil uit, en een time-out die als
/// "mislukt" bewaard wordt komt nooit meer terug. Echte ffmpeg waar het kan (de bouwstraat heeft
/// /usr/bin/ffmpeg), anders overgeslagen, zoals cast_omzetten_test.dart.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/ffmpeg.dart';
import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/luidheid.dart';
import 'package:debridmusic/luidheid_veger.dart';
import 'package:debridmusic/luidheid_winkel.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/organize.dart' show moveWithRetry, voorVerplaatsen;
import 'package:debridmusic/paths.dart';

late Directory _map;

String? get _ffmpeg => Ffmpeg().pad;

/// Maak een geluidsbestand met ffmpeg uit een lavfi-bron.
Future<File> _maak(String naam, String bron, {List<String> extra = const []}) async {
  final f = File('${_map.path}${Platform.pathSeparator}$naam');
  final r = await Process.run(_ffmpeg!, [
    '-nostdin', '-hide_banner', '-loglevel', 'error', '-y', //
    '-f', 'lavfi', '-i', bron, ...extra, f.path,
  ]);
  if (r.exitCode != 0) throw StateError('ffmpeg maakte $naam niet: ${r.stderr}');
  return f;
}

Track _track(File f, {String titel = 'x', String album = 'Plaat', int no = 1}) {
  final st = f.statSync();
  return Track(
    path: f.path,
    title: titel,
    artist: 'Artiest',
    album: album,
    trackNo: no,
    duration: const Duration(seconds: 5),
    isFlac: f.path.endsWith('.flac'),
    sizeBytes: st.size,
    addedMs: st.modified.millisecondsSinceEpoch,
  );
}

void main() {
  setUp(() {
    _map = Directory.systemTemp.createTempSync('dm_luid_');
    setAppDirForTest(_map.path);
    resetLuidheidVoorTest();
  });

  tearDown(() async {
    voorVerplaatsen = null;
    for (var i = 0; i < 10; i++) {
      try {
        _map.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  group('meten met echte ffmpeg', () {
    final geen = Ffmpeg().pad == null;

    test('DE KERN: een stereo-sinus van −6 dBFS meet −6 LUFS, met de piek erbij', () async {
      final f = await _maak('s.flac', 'aevalsrc=0.5*sin(2*PI*997*t)|0.5*sin(2*PI*997*t):s=44100:d=5',
          extra: ['-sample_fmt', 's16']);
      final u = await meetLuidheid(f.path);
      final m = (u.uitslag as Gemeten).meting;
      expect(m.lufs, closeTo(-6.0, 0.3));
      expect(m.piek, closeTo(-6.0, 0.3));
    }, skip: geen ? 'geen ffmpeg' : false);

    test('DE VAL: een mono-opname meet zoals mpv hem afspeelt — 3 dB zachter, geen dualmono', () async {
      // mpv mengt mono via libswresample op −3,01 dB per kant. Met dualmono zou hij −6 meten en dus
      // 3 dB te veel verlaagd worden.
      final f = await _maak('m.flac', 'aevalsrc=0.5*sin(2*PI*997*t):s=44100:d=5', extra: ['-sample_fmt', 's16']);
      final m = ((await meetLuidheid(f.path)).uitslag as Gemeten).meting;
      expect(m.lufs, closeTo(-9.0, 0.3));
    }, skip: geen ? 'geen ffmpeg' : false);

    test('DE KERN: meer dan twee kanalen bewaart geen getallen', () async {
      final kanaal = '0.5*sin(2*PI*997*t)';
      final f = await _maak('51.flac', 'aevalsrc=${List.filled(6, kanaal).join('|')}:c=5.1:s=48000:d=3',
          extra: ['-sample_fmt', 's16']);
      final u = await meetLuidheid(f.path);
      expect(u.uitslag, isA<Meerkanaals>(), reason: 'de terugmix naar stereo tilt de piek tot ~7,6 dB');
    }, skip: geen ? 'geen ffmpeg' : false);

    // De kanaalherkenning leest de streamregel van ffmpeg, en die ziet er per formaat anders uit
    // ("stereo, fltp, 128 kb/s", "stereo, s32p (24 bit)"). Een regel die hij niet herkent telt als
    // 99 kanalen — veilig, maar dan krijgt een gewoon stereonummer nooit een bijstelling. Dus met
    // echte bestanden in elk formaat dat in de bibliotheek staat. APE kan ffmpeg niet maken; die
    // regel staat letterlijk uit een echt bestand in luidheid_test.dart.
    for (final (naam, extra) in <(String, List<String>)>[
      ('s.wv', ['-c:a', 'wavpack']),
      ('s.mp3', ['-c:a', 'libmp3lame', '-b:a', '256k']),
      ('s.m4a', ['-c:a', 'aac', '-b:a', '256k']),
      ('a.m4a', ['-c:a', 'alac']),
      ('s.aiff', ['-c:a', 'pcm_s16be']),
      ('s.ogg', ['-c:a', 'libvorbis']),
      ('s.opus', ['-c:a', 'libopus', '-b:a', '160k']),
      ('s.wav', ['-c:a', 'pcm_s24le']),
    ]) {
      test('DE GRENS: stereo als $naam is gewoon stereo, en meet −6 LUFS', () async {
        final File f;
        try {
          f = await _maak(naam, 'aevalsrc=0.5*sin(2*PI*997*t)|0.5*sin(2*PI*997*t):s=48000:d=5', extra: extra);
        } on StateError {
          markTestSkipped('deze ffmpeg kan geen $naam maken');
          return;
        }
        final u = await meetLuidheid(f.path);
        expect(u.uitslag, isA<Gemeten>(), reason: '${u.uitslag}');
        expect((u.uitslag as Gemeten).meting.lufs, closeTo(-6.0, 0.5));
        expect(u.erfbaar, isNull, reason: 'alleen een FLAC met een MD5 in de kop is erfbaar');
      }, skip: geen ? 'geen ffmpeg' : false);
    }

    test('DE KERN: 5.1 als WavPack is ook meerkanaals', () async {
      final kanaal = '0.5*sin(2*PI*997*t)';
      final f = await _maak('51.wv', 'aevalsrc=${List.filled(6, kanaal).join('|')}:c=5.1:s=48000:d=3',
          extra: ['-c:a', 'wavpack']);
      expect((await meetLuidheid(f.path)).uitslag, isA<Meerkanaals>());
    }, skip: geen ? 'geen ffmpeg' : false);

    test('DE VAL: 192 kHz — de piek telt ook na herbemonstering naar 48 kHz', () async {
      // Een blokgolf: op 192 kHz is de ware piek van ffmpeg gewoon de monsterpiek (−6,0 dBFS); na de
      // herbemonstering naar 48 kHz, wat mpv op Windows en Android doet, rinkelt hij tot −4,6.
      // Zonder de tweede gang zou een ophoging "tot −1 dBTP" daar op −0,1 uitkomen.
      final f = await _maak('blok192.flac',
          'aevalsrc=0.5*sgn(sin(2*PI*1000*t))|0.5*sgn(sin(2*PI*1000*t)):s=192000:d=4',
          extra: ['-sample_fmt', 's32']);
      final u = await meetLuidheid(f.path);
      final m = (u.uitslag as Gemeten).meting;
      expect(m.piek, greaterThan(-6.0 + 0.05 + 1.0), reason: 'de piek na 48 kHz moet meetellen');
      expect(u.erfbaar, isNotNull, reason: 'de MD5 komt nog steeds uit de eerste gang');
    }, skip: geen ? 'geen ffmpeg' : false);

    test('DE VAL: 88,2 en 96 kHz krijgen de tweede gang evengoed — niet pas vanaf 176,4', () {
      // Nagemeten door de audiobeoordelaar op echte muziek: Bob Marley, "Could You Be Loved" (96/24),
      // eigen piek −0,1, na 48 kHz +0,5 — mpv haalt ook daar alles boven 24 kHz weg. (Een kunstmatig
      // signaal laat het op 96 kHz niet zien: ffmpeg's eigen ware-piekfilter dempt dan al mee.)
      expect(tweedeGangNodig(88200), isTrue);
      expect(tweedeGangNodig(96000), isTrue);
      expect(tweedeGangNodig(192000), isTrue);
      expect(tweedeGangNodig(2822400), isTrue, reason: 'DSD');
      expect(tweedeGangNodig(48000), isFalse, reason: 'dat is de mengfrequentie zelf');
      expect(tweedeGangNodig(44100), isFalse);
      expect(tweedeGangNodig(null), isFalse);
    });

    test('DE GRENS: een vergrendeld bestand is tijdelijk, een kapot bestand niet', () {
      expect(isTijdelijkeFout('D:\\Muziek\\a.flac: Permission denied'), isTrue);
      expect(isTijdelijkeFout('The process cannot access the file because it is being used by another process'), isTrue);
      expect(isTijdelijkeFout('a.flac: Invalid data found when processing input'), isFalse);
      expect(isTijdelijkeFout('Error while filtering: Invalid argument'), isFalse,
          reason: 'dat geeft ffmpeg ook op een echt kapot bestand; dan zou het nooit "kon niet meten" worden');
    });

    test('DE GRENS: op 48 kHz verandert er niets — geen tweede gang nodig', () async {
      final f = await _maak('blok48.flac', 'aevalsrc=0.5*sin(2*PI*997*t)|0.5*sin(2*PI*997*t):s=48000:d=4',
          extra: ['-sample_fmt', 's16']);
      final m = ((await meetLuidheid(f.path)).uitslag as Gemeten).meting;
      expect(m.piek, closeTo(-6.0 + 0.05, 0.15));
    }, skip: geen ? 'geen ffmpeg' : false);

    test('DE VAL: een kapot bestand is een uitslag, geen uitzondering', () async {
      final f = File('${_map.path}${Platform.pathSeparator}kapot.flac')
        ..writeAsBytesSync(List.generate(5000, (i) => Random(1).nextInt(256)));
      final u = await meetLuidheid(f.path);
      expect(u.uitslag, isA<Mislukt>());
      expect(u.erfbaar, isNull);
    }, skip: geen ? 'geen ffmpeg' : false);

    test('DE KERN: een volledige FLAC is erfbaar — de gedecodeerde MD5 klopt met de kop', () async {
      for (final (fmt, naam) in [('s16', 'z16.flac'), ('s32', 'z24.flac')]) {
        final f = await _maak(naam, 'aevalsrc=0.3*sin(2*PI*440*t)|0.3*sin(2*PI*660*t):s=48000:d=4',
            extra: ['-sample_fmt', fmt, if (fmt == 's32') ...['-bits_per_raw_sample', '24']]);
        final kern = leesFlacKern(f)!;
        expect(kern.md5, isNot('00000000000000000000000000000000'));
        final u = await meetLuidheid(f.path);
        expect(u.erfbaar, isNotNull, reason: '$naam: ${kern.diepte} bit hoort erfbaar te zijn');
        expect(await controleerFlacMd5(f.path, kern), isTrue);
      }
    }, skip: geen ? 'geen ffmpeg' : false);

    test('DE VAL: een halverwege afgekapte FLAC wordt gemeten maar is NIET erfbaar', () async {
      final f = await _maak('heel.flac', 'aevalsrc=0.3*sin(2*PI*440*t)|0.3*sin(2*PI*440*t):s=44100:d=6',
          extra: ['-sample_fmt', 's16']);
      final bytes = f.readAsBytesSync();
      final kort = File('${_map.path}${Platform.pathSeparator}kort.flac')
        ..writeAsBytesSync(bytes.sublist(0, (bytes.length * 0.6).round()));
      final u = await meetLuidheid(kort.path);
      expect(u.erfbaar, isNull,
          reason: 'de kop belooft het hele nummer; een vervanger mag deze meting nooit erven');
    }, skip: geen ? 'geen ffmpeg' : false);
  });

  group('de snelweg', () {
    FlacKern kern({String md5 = '0123456789abcdef0123456789abcdef', int audio = 100000}) =>
        (monsters: 441000, frequentie: 44100, kanalen: 2, diepte: 16, md5: md5, audioBytes: audio);
    const m = Gemeten(Luidheidsmeting(lufs: -9, piek: -1));

    test('DE KERN: dezelfde audio wordt herkend', () {
      onthoudLuidheid('k1', pad: '/a.flac', uitslag: m, erfbaar: kern());
      expect(erfbareLuidheid(kern())?.sleutel, 'k1');
    });

    test('DE VAL: een andere audiogrootte is andere audio', () {
      onthoudLuidheid('k1', pad: '/a.flac', uitslag: m, erfbaar: kern());
      expect(erfbareLuidheid(kern(audio: 100001)), isNull,
          reason: 'zelfde kop, maar andere bytes: een afgekapte of opgevulde kopie');
    });

    test('DE VAL: een MD5 van nullen bewijst niets', () {
      const nul = '00000000000000000000000000000000';
      onthoudLuidheid('k1', pad: '/a.flac', uitslag: m, erfbaar: kern(md5: nul));
      expect(erfbareLuidheid(kern(md5: nul)), isNull, reason: 'een encoder die geen MD5 schreef');
    });
  });

  group('de veger', () {
    late LibraryStore bib;
    setUp(() {
      bib = LibraryStore()
        ..rootPath = _map.path
        ..configDirOverride = _map.path;
    });

    File bestand(String naam, [int grootte = 4000]) => File('${_map.path}${Platform.pathSeparator}$naam')
      ..writeAsBytesSync(List.filled(grootte, 7));

    LuidheidVeger veger(Future<MeetUitkomst> Function(String pad, void Function(Process p) opStart) meet,
            {Duration leeftijd = Duration.zero, DateTime Function()? nu}) =>
        LuidheidVeger(
          library: bib,
          meet: meet,
          controleer: (_, __, ___) async => false,
          leesKern: (_) => null,
          ffmpegAanwezig: () => true,
          startNa: const Duration(hours: 1),
          tussenpoos: Duration.zero,
          leeftijd: leeftijd,
          nu: nu,
        );

    MeetUitkomst gemeten(double i) =>
        (uitslag: Gemeten(Luidheidsmeting(lufs: i, piek: -3)), erfbaar: null, tijdOp: false);

    test('DE KERN: elk nummer één keer, nooit twee tegelijk, en daarna klaar', () async {
      await laadLuidheid();
      final a = bestand('a.flac'), b = bestand('b.flac', 5000);
      bib.tracks.addAll([_track(a, titel: 'A'), _track(b, titel: 'B')]);
      bib.rebuildAlbums();
      var tegelijk = 0, max = 0, keer = 0;
      final v = veger((pad, _) async {
        tegelijk++;
        keer++;
        if (tegelijk > max) max = tegelijk;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        tegelijk--;
        return gemeten(-10);
      });
      await v.ronde();
      await v.ronde();
      expect(keer, 2, reason: 'een tweede ronde meet niets opnieuw');
      expect(max, 1);
      expect(luidheidKlaar, isTrue);
      expect(gepubliceerdeLuidheid(bib.tracks.first), {'i': -10.0, 'tp': -3.0});
      expect(File('${_map.path}${Platform.pathSeparator}luidheid.json').existsSync(), isTrue);
    });

    test('DE GRENS: een lege bibliotheek maakt de eerste ronde niet klaar', () async {
      await laadLuidheid();
      await veger((_, __) async => gemeten(-10)).ronde();
      expect(luidheidKlaar, isFalse, reason: 'D: even weg mag geen "klaar" zonder metingen geven');
    });

    test('DE VAL: wacht zolang de bibliotheek scant', () async {
      await laadLuidheid();
      bib.tracks.add(_track(bestand('a.flac')));
      bib.scanning = true;
      var keer = 0;
      final v = veger((_, __) async {
        keer++;
        return gemeten(-10);
      });
      final klaar = v.ronde();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(keer, 0);
      bib.scanning = false;
      await klaar.timeout(const Duration(seconds: 10));
      expect(keer, 1);
    });

    test('DE VAL: een time-out is de eerste keer niet mislukt, de tweede keer wel — en klaar komt toch', () async {
      await laadLuidheid();
      final t = _track(bestand('lang.flac'));
      bib.tracks.add(t);
      var keer = 0;
      Future<MeetUitkomst> lang(String _, void Function(Process) __) async {
        keer++;
        return (uitslag: const Mislukt('te lang'), erfbaar: null, tijdOp: true);
      }

      final v = veger(lang);
      await v.ronde();
      expect(luidheidKlaar, isTrue, reason: 'één lang bestand mag de functie niet voorgoed uitzetten');
      expect(luidheidBekend(luidheidSleutel(t)!), isFalse);
      await v.ronde();
      expect(keer, 1,
          reason: 'één poging per sessie: rondes komen snel (10 s na een wijziging), en anders was een '
              'tijdelijke traagheid binnen minuten "te lang" voor altijd');
      expect(luidheidBekend(luidheidSleutel(t)!), isFalse);
      // De volgende sessie (de app opnieuw gestart): nu wel definitief.
      await veger(lang).ronde();
      expect(luidheidBekend(luidheidSleutel(t)!), isTrue, reason: 'bij de tweede sessie definitief');
      expect(gepubliceerdeLuidheid(t), {'f': 1});
    });

    test('DE KERN: een bibliotheek die al lang staat wordt in de EERSTE ronde gemeten', () async {
      // Met de leeftijd van productie (60 s). Eerst telde alleen "60 s ongewijzigd gezien", en de veger
      // zag in zijn eerste ronde elk bestand voor het eerst: hij sloeg alle 1437 nummers over, zette
      // toch "klaar" en publiceerde een lege kaart.
      await laadLuidheid();
      final oud = DateTime.now().subtract(const Duration(days: 3));
      final a = bestand('a.flac')..setLastModifiedSync(oud);
      final b = bestand('b.flac', 5000)..setLastModifiedSync(oud);
      bib.tracks.addAll([_track(a, titel: 'A'), _track(b, titel: 'B')]);
      var keer = 0;
      final v = veger((_, __) async {
        keer++;
        return gemeten(-10);
      }, leeftijd: const Duration(seconds: 60));
      await v.ronde();
      v.stop();
      expect(keer, 2);
      expect(luidheidKlaar, isTrue);
      expect(gepubliceerdeLuidheid(bib.tracks.first), {'i': -10.0, 'tp': -3.0}, reason: 'klaar mét kaart');
    });

    test('DE VAL: ffmpeg die niet start breekt de ronde af en bewaart niets', () async {
      await laadLuidheid();
      bib.tracks.addAll([_track(bestand('a.flac'), titel: 'A'), _track(bestand('b.flac', 5000), titel: 'B')]);
      var keer = 0;
      final v = veger((_, __) async {
        keer++;
        return (uitslag: const Mislukt('ffmpeg start niet: weg', tijdelijk: true), erfbaar: null, tijdOp: false);
      });
      await v.ronde();
      v.stop();
      expect(keer, 1, reason: 'niet de rest van de ronde laten eindigen als "kon niet meten"');
      for (final t in bib.tracks) {
        expect(luidheidBekend(luidheidSleutel(t)!), isFalse, reason: '${t.title}: dat zegt niets over het bestand');
      }
      expect(luidheidKlaar, isFalse, reason: 'een afgebroken eerste ronde is niet klaar');
    });

    test('DE VAL: een vergrendeld bestand is geen kapot bestand', () async {
      await laadLuidheid();
      final a = _track(bestand('a.flac'), titel: 'A'), b = _track(bestand('b.flac', 5000), titel: 'B');
      bib.tracks.addAll([a, b]);
      final v = veger((pad, _) async => pad == a.path
          ? (uitslag: const Mislukt('a.flac: Permission denied', tijdelijk: true), erfbaar: null, tijdOp: false)
          : gemeten(-10));
      await v.ronde();
      v.stop();
      expect(luidheidBekend(luidheidSleutel(a)!), isFalse, reason: 'de volgende ronde opnieuw');
      expect(luidheidBekend(luidheidSleutel(b)!), isTrue);
      expect(luidheidKlaar, isTrue);
    });

    test('DE GRENS: een opgegeven ffmpeg die niet bestaat geeft een tijdelijke fout', () async {
      final u = await meetLuidheid(bestand('x.flac').path, ffmpeg: '${_map.path}${Platform.pathSeparator}geen-ffmpeg.exe');
      expect(u.uitslag, isA<Mislukt>());
      expect((u.uitslag as Mislukt).tijdelijk, isTrue);
    });

    test('DE VAL: laatLos terwijl ffmpeg nog opstart breekt hem alsnog af', () async {
      final exe = _ffmpeg;
      if (exe == null) return;
      await laadLuidheid();
      final a = bestand('a.flac');
      bib.tracks.add(_track(a));
      final poort = Completer<void>();
      final v = veger((pad, opStart) async {
        await poort.future; // laatLos komt vóór het proces er is
        final p = await Process.start(
            exe, ['-nostdin', '-re', '-f', 'lavfi', '-i', 'anullsrc', '-t', '60', '-f', 'null', '-']);
        opStart(p);
        final code = await p.exitCode;
        return (uitslag: Mislukt('gestopt met $code'), erfbaar: null, tijdOp: false);
      });
      final ronde = v.ronde();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await v.laatLos([a.path]);
      poort.complete();
      await ronde.timeout(const Duration(seconds: 15),
          onTimeout: () => fail('ffmpeg liep door en hield het bestand vast'));
      expect(luidheidBekend(luidheidSleutel(bib.tracks.first)!), isFalse);
    });

    test('DE GRENS: te jong wordt overgeslagen zonder te wachten; een mtime in de toekomst blokkeert niet', () async {
      await laadLuidheid();
      final f = bestand('nieuw.flac')
        ..setLastModifiedSync(DateTime.now().add(const Duration(days: 30)));
      final t = _track(f);
      bib.tracks.add(t);
      var nu = DateTime(2026, 10, 7, 12);
      var keer = 0;
      final v = veger((_, __) async {
        keer++;
        return gemeten(-9);
      }, leeftijd: const Duration(seconds: 60), nu: () => nu);
      await v.ronde().timeout(const Duration(seconds: 5));
      expect(keer, 0, reason: 'eerst 60 s ongewijzigd gezien');
      expect(luidheidKlaar, isTrue, reason: 'de ronde is doorgelopen; het nummer blijft 0 dB tot later');
      nu = nu.add(const Duration(seconds: 61));
      await v.ronde();
      expect(keer, 1, reason: 'een mtime in de toekomst telt niet; "gezien" wel');
    });

    test('DE VAL: een bestand dat tijdens de meting verdwijnt wordt niet als mislukt bewaard', () async {
      await laadLuidheid();
      final f = bestand('weg.flac');
      final t = _track(f);
      bib.tracks.add(t);
      await veger((pad, _) async {
        File(pad).deleteSync();
        return (uitslag: const Mislukt('No such file'), erfbaar: null, tijdOp: false);
      }).ronde();
      expect(luidheidBekend(luidheidSleutel(t)!), isFalse,
          reason: 'een verhuisd bestand is geen kapot bestand; anders komt het nooit meer terug');
    });

    test('DE VAL: laatLos breekt een lopende meting af en bewaart niets', () async {
      await laadLuidheid();
      final f = bestand('los.flac');
      final t = _track(f);
      bib.tracks.add(t);
      final bezig = Completer<void>(), door = Completer<MeetUitkomst>();
      final v = veger((_, __) {
        bezig.complete();
        return door.future;
      });
      final ronde = v.ronde();
      await bezig.future;
      await v.laatLos([f.path]);
      door.complete(gemeten(-10));
      await ronde;
      expect(luidheidBekend(luidheidSleutel(t)!), isFalse);
    });

    test('DE KERN: verplaatsen wacht eerst op voorVerplaatsen', () async {
      final f = bestand('van.flac');
      final volgorde = <String>[];
      voorVerplaatsen = (paden) async => volgorde.add('los ${paden.single.endsWith('van.flac')}');
      await moveWithRetry(f, File('${_map.path}${Platform.pathSeparator}naar.flac'));
      volgorde.add('verplaatst');
      expect(volgorde, ['los true', 'verplaatst']);
    });

    test('DE KERN: dezelfde audio na een tagbewerking wordt overgenomen zonder opnieuw te meten', () async {
      if (_ffmpeg == null) return;
      await laadLuidheid();
      final f = await _maak('tag.flac', 'aevalsrc=0.3*sin(2*PI*440*t)|0.3*sin(2*PI*440*t):s=44100:d=3',
          extra: ['-sample_fmt', 's16']);
      final t1 = _track(f);
      bib.tracks.add(t1);
      var echteMetingen = 0;
      final v = LuidheidVeger(
        library: bib,
        meet: (pad, opStart) {
          echteMetingen++;
          return meetLuidheid(pad, opStart: opStart);
        },
        ffmpegAanwezig: () => true,
        startNa: const Duration(hours: 1),
        tussenpoos: Duration.zero,
        leeftijd: Duration.zero,
      );
      await v.ronde();
      expect(echteMetingen, 1);
      // Tags herschrijven: de audiobytes blijven, grootte en tijd veranderen.
      expect(writeFlacFields(f, {'TITLE': 'Andere titel met een veel langere naam'}), isTrue);
      f.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
      final t2 = _track(f, titel: 'Andere titel');
      expect(luidheidSleutel(t2), isNot(luidheidSleutel(t1)));
      bib.tracks
        ..clear()
        ..add(t2);
      await v.ronde();
      expect(echteMetingen, 1, reason: 'zelfde audio (md5, monsters, formaat, audiolengte) → overgenomen');
      expect(luidheidBekend(luidheidSleutel(t2)!), isTrue);
    });
  });
}
