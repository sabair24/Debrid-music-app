/// Een download die eerst een bron zoekt, hangt niet meer aan het scherm dat hem startte.
///
/// Saber op 04-10-2026: *"als ik bij soulseek op de download knop klik, en dan uit het venster ga, dan
/// wordt de download niet actief, ik moet in het venster blijven tot de download begint dit is
/// vervelend"*. Nagespeeld en in de code gevonden: de albumpagina zocht eerst zélf een bron (een
/// Soulseek-zoekopdracht van tien tot dertig seconden) en maakte pas daarna de download aan — met
/// `if (!mounted) return` ertussen. Wie de pagina verliet, gooide zijn klik weg: geen taak, geen
/// melding. Bij "Ontbrekende downloaden" viel bovendien elk volgend nummer om, want het zoeken vroeg
/// de Soulseek-dienst opnieuw aan de pagina die er niet meer was.
///
/// Gemeten, voor het onderscheid: de pijl in de bronnenlijst zelf (een aangeklikt bestand) maakte zijn
/// taak altijd al meteen aan — een klik en dan meteen terug gaf om 10:25:59 gewoon "VASTE KEUZE".
library;

import 'dart:async';
import 'dart:io';

import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart' show TrackTags;
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een downloadbeheer dat het starten OPSCHRIJFT in plaats van bij Soulseek in te loggen. Een toets
/// hoort nooit echt aan te melden: te veel aanmeldingen is precies waar een account voor geblokkeerd
/// wordt.
class _Schrijver extends DownloadManager {
  _Schrijver(AppSettings cfg) : super(OnlineService(cfg), SoulseekService(cfg), Directory.systemTemp.path, () async {});

  final gestart = <({List<SoulseekFile> kandidaten, String? key, TrackTags? authority})>[];

  @override
  Future<bool> enqueueSoulseekBest(List<SoulseekFile> candidates,
      {String? key, TrackTags? authority, SoulseekFile? exact, bool jouwKeuze = false, bool wachtOpAfloop = true}) async {
    gestart.add((kandidaten: candidates, key: key, authority: authority));
    jobs.insert(0, DownloadJob(candidates.first.displayName, key: key, status: 'queued'));
    notifyListeners();
    return true;
  }
}

SoulseekFile _f(String naam) => SoulseekFile(
      username: 'peer',
      filename: '@@peer\\Lil Kim\\$naam',
      size: 30 * 1024 * 1024,
      speed: 0,
      queueLength: 0,
      freeSlots: true,
      durationSec: 184,
    );

AppSettings _cfg() => AppSettings()
  ..soulseekUser = 'toets'
  ..soulseekPass = 'toets';

void main() {
  test('DE KERN: de taak staat er bij de klik al, vóór het zoeken klaar is', () async {
    final dm = _Schrijver(_cfg());
    final zoeken = Completer<List<SoulseekFile>>();
    final klaar = dm.zoekEnHaal(naam: 'Kimnotyze', key: 'k1', zoek: () => zoeken.future);

    expect(dm.jobs, hasLength(1), reason: 'zo zie je in Mijn downloads meteen dat er iets loopt');
    expect(dm.jobs.single.status, 'preparing');
    expect(dm.jobs.single.detail, 'bron zoeken…');
    expect(dm.jobs.single.busy, isTrue);
    expect(dm.gestart, isEmpty);

    zoeken.complete([_f('01 - Kimnotyze.flac')]);
    expect(await klaar, ZoekUitkomst.gestart);
    expect(dm.gestart.single.key, 'k1', reason: 'dezelfde sleutel, zodat de knop op de pagina doorloopt');
    expect(dm.jobs.where((j) => j.status == 'preparing'), isEmpty, reason: 'de plaatshouder is vervangen');
  });

  testWidgets('DE VAL: het scherm verlaten breekt het zoeken niet meer af', (tester) async {
    // Precies wat Saber deed: klikken, en weg voordat de bron gevonden was.
    final dm = _Schrijver(_cfg());
    final zoeken = Completer<List<SoulseekFile>>();
    late Future<ZoekUitkomst> klaar;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => TextButton(
              onPressed: () => klaar = dm.zoekEnHaal(naam: 'Kimnotyze', key: 'k1', zoek: () => zoeken.future),
              child: const Text('download'))),
    ));
    await tester.tap(find.text('download'));
    await tester.pumpWidget(const MaterialApp(home: Text('ergens anders'))); // de pagina is weg
    zoeken.complete([_f('01 - Kimnotyze.flac')]);
    await tester.runAsync(() => klaar);
    expect(dm.gestart, hasLength(1), reason: 'vroeger: geen taak, geen melding, niets');
  });

  test('geen bron: dat staat erbij, en er wordt niets gestart', () async {
    final dm = _Schrijver(_cfg());
    expect(await dm.zoekEnHaal(naam: 'Kimnotyze', key: 'k1', zoek: () async => const []), ZoekUitkomst.geenBron);
    expect(dm.gestart, isEmpty);
    expect(dm.jobs.single.status, 'failed');
    expect(dm.jobs.single.detail, 'geen Soulseek-bron gevonden');
  });

  test('een zoektocht die omvalt is "geen bron", geen uitzondering die niemand ziet', () async {
    final dm = _Schrijver(_cfg());
    expect(await dm.zoekEnHaal(naam: 'Kimnotyze', key: 'k1', zoek: () async => throw 'netwerk weg'),
        ZoekUitkomst.geenBron);
  });

  test('wat al loopt, start niet nog eens', () async {
    final dm = _Schrijver(_cfg());
    final zoeken = Completer<List<SoulseekFile>>();
    final eerste = dm.zoekEnHaal(naam: 'Kimnotyze', key: 'k1', zoek: () => zoeken.future);
    expect(await dm.zoekEnHaal(naam: 'Kimnotyze', key: 'k1', zoek: () async => [_f('x.flac')]), ZoekUitkomst.loopt);
    zoeken.complete([_f('01 - Kimnotyze.flac')]);
    await eerste;
    expect(dm.gestart, hasLength(1));
  });

  test('weggetikt tijdens het zoeken: dan ook niet starten', () async {
    final dm = _Schrijver(_cfg());
    final zoeken = Completer<List<SoulseekFile>>();
    final klaar = dm.zoekEnHaal(naam: 'Kimnotyze', key: 'k1', zoek: () => zoeken.future);
    dm.cancelJob(dm.jobs.single);
    zoeken.complete([_f('01 - Kimnotyze.flac')]);
    expect(await klaar, ZoekUitkomst.geannuleerd);
    expect(dm.gestart, isEmpty);
  });

  group("de albumpagina's gebruiken het", () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    String lijf(String kop) {
      final i = main.indexOf(kop);
      expect(i, greaterThan(0), reason: '$kop is weg');
      return main.substring(i, main.indexOf('\n  }\n', i));
    }

    for (final kop in [
      '  Future<void> _downloadMissing(',
      '  Future<void> _downloadAllMissing(',
      '  Future<void> _downloadTrack(',
    ]) {
      test(kop.trim(), () {
        final l = lijf(kop);
        expect(l, contains('.zoekEnHaal('), reason: 'de download hoort niet meer aan de pagina te hangen');
        expect(l, isNot(contains('enqueueSoulseekBest(')),
            reason: 'eerst zoeken op de pagina en dan pas starten is precies de fout');
      });
    }
  });
}
