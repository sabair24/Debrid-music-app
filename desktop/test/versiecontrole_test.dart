/// Is een binnengekomen bestand de gevraagde VERSIE? Het bestand tegen het Deezer-fragment (Saber,
/// 21-10-2026: "acousticid werkt langs geen kanten").
///
/// Geijkt op dertig nummers uit Sabers bibliotheek: de gevraagde versie 0,935–0,987, een andere opname
/// 0,53–0,72. "Light Switch (Acoustic)" van de Sabrina-radio was de albumversie: 0,642 tegen het
/// akoestische fragment, 0,945 tegen dat van het origineel.
library;

import 'dart:io';
import 'dart:math';

import 'package:debridmusic/ffmpeg.dart';
import 'package:debridmusic/fingerprint.dart';
import 'package:debridmusic/integriteit.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/versiecontrole.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> dz(int id, String artiest, String titel, int duur) =>
    {'id': id, 'title': titel, 'artist': {'name': artiest}, 'duration': duur, 'preview': 'https://x/$id.mp3'};

void main() {
  group('het fragment over het hele nummer', () {
    final r = Random(21);
    final heel = [for (var i = 0; i < 1500; i++) r.nextInt(1 << 32)];

    test('een stuk van het nummer zelf, waar dan ook: gelijk', () {
      expect(fragmentOvereenkomst(heel, heel.sublist(340, 580)), closeTo(1.0, 1e-9));
      expect(fragmentOvereenkomst(heel, heel.sublist(1260, 1500)), closeTo(1.0, 1e-9), reason: 'ook aan het eind');
    });

    test('iets anders: toeval, rond de helft', () {
      final ander = [for (var i = 0; i < 240; i++) r.nextInt(1 << 32)];
      final s = fragmentOvereenkomst(heel, ander);
      expect(s, lessThan(kAndereVersieOnder));
      expect(s, greaterThan(0.4));
    });

    test('te kort om iets te zeggen: nul', () {
      expect(fragmentOvereenkomst(heel, heel.sublist(0, 10)), 0);
      expect(fragmentOvereenkomst(const [], heel.sublist(0, 240)), 0);
    });
  });

  group('het juiste Deezer-nummer', () {
    // Zoals Deezer "Charlie Puth Light Switch" beantwoordt (21-10-2026).
    final data = [dz(1, 'Charlie Puth', 'Light Switch (Acoustic)', 186), dz(2, 'Charlie Puth', 'Light Switch', 185)];

    test('DE KERN: de akoestische versie en het origineel zijn twee nummers', () {
      expect(kiesDeezerNummer(data, 'Charlie Puth', 'Light Switch (Acoustic)', 188)?['id'], 1);
      expect(kiesDeezerNummer(data, 'Charlie Puth', 'Light Switch', 185)?['id'], 2);
    });

    test('een andere artiest of een andere lengte is het niet', () {
      expect(kiesDeezerNummer(data, 'Karaoke Hits', 'Light Switch', 185), isNull);
      expect(kiesDeezerNummer(data, 'Charlie Puth', 'Light Switch', 240), isNull);
      expect(kiesDeezerNummer(data, 'Charlie Puth', 'Light Switch', null)?['id'], 2, reason: 'zonder lengte: op naam');
    });

    test('een gastrol in de titel, of een samenwerking in de artiest', () {
      final tyla = [dz(3, 'Tyla', 'SHE DID IT AGAIN (feat. Zara Larsson)', 214)];
      expect(kiesDeezerNummer(tyla, 'Tyla', 'SHE DID IT AGAIN', 213)?['id'], 3);
      expect(kiesDeezerNummer(tyla, 'Tyla & Zara Larsson', 'SHE DID IT AGAIN (feat. Zara Larsson)', 213)?['id'], 3);
    });

    test('zonder fragment valt er niets te vergelijken', () {
      final zonder = [
        {'id': 4, 'title': 'Light Switch', 'artist': {'name': 'Charlie Puth'}, 'duration': 185, 'preview': ''}
      ];
      expect(kiesDeezerNummer(zonder, 'Charlie Puth', 'Light Switch', 185), isNull);
    });
  });

  group('in de keuring van elke download', () {
    final ffmpeg = Ffmpeg().pad;
    late Directory map;
    final teWissen = <Directory>[];
    tearDownAll(() async {
      for (var ronde = 0; ronde < 30 && teWissen.any((d) => d.existsSync()); ronde++) {
        for (final d in teWissen) {
          try {
            if (d.existsSync()) d.deleteSync(recursive: true);
          } catch (_) {}
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_versie_');
      teWissen.add(map);
      setAppDirForTest(map.path);
      resetIntegriteitVoorTest();
    });
    tearDown(() {
      DownloadManager.versiecontrole = null;
      resetIntegriteitVoorTest();
    });

    test('DE KERN: een andere versie is een mislukte poging, de race gaat door', () async {
      final f = File('${map.path}${Platform.pathSeparator}binnen.flac');
      final r = await Process.run(ffmpeg!, [
        '-nostdin', '-v', 'error', '-f', 'lavfi', '-i', 'anoisesrc=d=20:c=pink:r=44100:a=0.3:seed=5',
        '-c:a', 'flac', f.path,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      const gevraagd = (artiest: 'Charlie Puth', titel: 'Light Switch (Acoustic)');
      final gevraagdeTitels = <String>[];
      double? score = 0.642;
      DownloadManager.versiecontrole = (pad, {required artiest, required titel, seconden}) async {
        gevraagdeTitels.add(titel);
        return score;
      };
      final regels = <String>[];

      final ander = await DownloadManager.keurOverdracht(SlskDone(f.path), spoor: regels.add, gevraagd: gevraagd);
      expect(ander, isA<SlskFail>());
      expect((ander as SlskFail).reason, contains('andere versie'));
      expect(regels.last, contains('andere versie binnengekomen'));
      expect(gevraagdeTitels, ['Light Switch (Acoustic)']);

      score = 0.945;
      expect(await DownloadManager.keurOverdracht(SlskDone(f.path), gevraagd: gevraagd), isA<SlskDone>());
      score = 0.85;
      expect(await DownloadManager.keurOverdracht(SlskDone(f.path), spoor: regels.add, gevraagd: gevraagd), isA<SlskDone>(),
          reason: 'twijfel: gehouden');
      expect(regels.last, contains('twijfel over de versie'));
      score = null;
      expect(await DownloadManager.keurOverdracht(SlskDone(f.path), gevraagd: gevraagd), isA<SlskDone>(),
          reason: 'geen oordeel is ja');
      gevraagdeTitels.clear();
      expect(await DownloadManager.keurOverdracht(SlskDone(f.path)), isA<SlskDone>());
      expect(gevraagdeTitels, isEmpty, reason: 'zonder gevraagde versie (je eigen keuze) geen controle');
    }, skip: ffmpeg == null ? 'geen ffmpeg op deze machine' : false);
  });

  test('aangesloten: elke overdracht zegt welke versie gevraagd werd, en de pc controleert', () {
    final o = File('lib/online.dart').readAsStringSync();
    final raw = o.substring(o.indexOf('  Future<SlskResult> _rawTransfer('));
    final lijf = raw.substring(0, raw.indexOf('\n  }\n'));
    expect(lijf, contains('gevraagd: job.exact == null && !job.jouwKeuze && job.authority != null'),
        reason: 'niet bij een bestand dat je zelf koos');
    final m = File('lib/main.dart').readAsStringSync();
    expect(m, contains('if (mode.owner) DownloadManager.versiecontrole = Versiecontrole().score;'));
    expect(File('lib/fingerprint.dart').readAsStringSync(), contains("if (heel) ...['-length', '0'],"),
        reason: 'het hele nummer: het fragment kan na de eerste twee minuten liggen');
  });
}
