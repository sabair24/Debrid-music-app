/// Na een overname volgt het oude toestel het nieuwe: wachtrij, nummer en plek, gepauzeerd; afspelen is terug overnemen.
///
/// Saber, 28-11-2026: hij speelde een shuffle op de gsm en nam op de pc over ("Hier verder"); op de pc speelde hij
/// verder en klikte Michael Jackson aan. Daarna stond de gsm nog op Oxley — Reason of pleasure, 0:11: *"het moet nu
/// hernemen waar de pc het achtergelaten heeft, want anders moet ik weer alle nummers herspelen die ik al gehoord of
/// gezien heb"*. Hij koos "Altijd waar de pc nu is": speelt de pc nog, dan neemt de gsm over zodra je op afspelen
/// drukt, en de pc pauzeert.
library;

import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart' show RepeatMode;
import 'package:debridmusic/verder_luisteren.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String id) => Track(path: 'http://pc.invalid/stream/$id.flac', title: 'Nummer $id', artist: 'X', album: 'A');
final _bib = {for (final id in ['a', 'b', 'c', 'd', 'e']) id: _t(id)};

Map<String, dynamic> _stand({
  String trackId = 'b',
  List<String> rij = const ['a', 'b', 'c'],
  int index = 1,
  bool playing = true,
  required int op,
  String van = 'pc-THUIS',
  int positie = 60000,
  String overname = '',
  Map<String, dynamic>? radio,
}) =>
    {
      'trackId': trackId,
      'positionMs': positie,
      'queue': rij,
      'index': index,
      'playing': playing,
      'updatedAt': op,
      'deviceId': van,
      'deviceName': van,
      'shuffle': true,
      'repeat': 'all',
      if (overname.isNotEmpty) 'overname': overname,
      if (radio != null) 'radio': radio,
    };

/// De gsm: speelt of niet, en wat er geladen werd (met of zonder spelen).
class _Gsm implements VerderBron {
  bool speelt = true;
  int pauzes = 0;
  final geladen = <({List<String> rij, int index, Duration positie, bool spelen})>[];

  @override
  String get mijnId => 'gsm-1';
  @override
  bool get ikSpeel => speelt;
  @override
  Track? nummer(String id) => _bib[id];
  @override
  Future<({Map<String, dynamic>? stand, Map<String, dynamic>? verzoek})?> haal() async => null;
  @override
  Future<void> speel(List<Track> rij, int index, Duration positie,
      {required bool spelen, required bool shuffle, required RepeatMode herhaal, String? radioArtiest}) async {
    geladen.add((rij: [for (final t in rij) t.title.substring(7)], index: index, positie: positie, spelen: spelen));
    speelt = spelen;
  }

  @override
  void pauzeer() {
    pauzes++;
    speelt = false;
  }
}

void main() {
  late int nu;
  late _Gsm gsm;
  late VerderLuisteren v;
  late List<String?> bewaard;
  late List<({String nummer, Duration plek})> plekken;
  late int gevolgd;

  setUp(() {
    nu = 1000000;
    gsm = _Gsm();
    bewaard = [];
    plekken = [];
    gevolgd = 0;
    v = VerderLuisteren(gsm, klok: () => nu)
      ..bewaarVolgen = bewaard.add
      ..zetPlek = ((t, p) => plekken.add((nummer: t.title.substring(7), plek: p)))
      ..bijGevolgd = (() => gevolgd++);
  });

  test('DE KERN: de pc neemt over en speelt verder — de gsm staat daarna waar de pc is, gepauzeerd', () async {
    // De pc neemt de shuffle van de gsm over, midden in b.
    await v.opStand(_stand(op: nu, overname: 'gsm-1'));
    expect(gsm.pauzes, 1, reason: 'de gsm pauzeert, zoals altijd');
    expect(v.volgt, 'pc-THUIS');
    expect(bewaard, ['pc-THUIS'], reason: 'onthouden over een herstart van de app');
    expect(gsm.geladen, isEmpty, reason: 'de pc nam precies de stand van hier over: niets te laden');
    // De pc speelt verder: d, en Saber klikte er nog e bij.
    nu += 240000;
    await v.opStand(_stand(trackId: 'd', rij: const ['a', 'b', 'c', 'd', 'e'], index: 3, positie: 12000, op: nu));
    expect(gsm.geladen, hasLength(1));
    expect(gsm.geladen.single.rij, ['a', 'b', 'c', 'd', 'e']);
    expect(gsm.geladen.single.index, 3);
    expect(gsm.geladen.single.positie, const Duration(seconds: 12));
    expect(gsm.geladen.single.spelen, isFalse);
    expect(gsm.speelt, isFalse, reason: 'gepauzeerd: de gsm speelt niet zomaar');
    expect(v.aanbod, isNull, reason: 'geen balk voor wat hier al staat');
    expect(gevolgd, 1);
    // Dezelfde stand een paar seconden later (alleen de plek liep door): niet opnieuw laden.
    nu += 5000;
    await v.opStand(_stand(trackId: 'd', rij: const ['a', 'b', 'c', 'd', 'e'], index: 3, positie: 17000, op: nu));
    expect(gsm.geladen, hasLength(1));
    // De pc pauzeert op 1:30: de gsm zet alleen de plek.
    nu += 73000;
    await v.opStand(_stand(trackId: 'd', rij: const ['a', 'b', 'c', 'd', 'e'], index: 3, positie: 90000, playing: false, op: nu));
    expect(gsm.geladen, hasLength(1));
    expect(plekken, [(nummer: 'd', plek: const Duration(seconds: 90))]);
    await v.opStand(_stand(trackId: 'd', rij: const ['a', 'b', 'c', 'd', 'e'], index: 3, positie: 90000, playing: false, op: nu));
    expect(plekken, hasLength(1), reason: 'dezelfde pauze één keer');
  });

  test('melden: zolang de gsm volgt en stil is, alleen de zonelijst; de eerste keer spelen is terug overnemen', () async {
    await v.opStand(_stand(op: nu, overname: 'gsm-1'));
    nu += 10000;
    expect(v.meldNu(), (overname: null, alleenZone: true), reason: 'binnen het stilvenster na de overname');
    nu += 60000;
    expect(v.meldNu(speelt: false), (overname: null, alleenZone: true),
        reason: 'de stand van de pc blijft "waar je bent"');
    expect(v.meldNu(speelt: true), (overname: 'pc-THUIS', alleenZone: false), reason: 'de pc pauzeert');
    expect(v.volgt, isNull);
    expect(bewaard.last, isNull);
    expect(v.meldNu(speelt: true), (overname: null, alleenZone: false), reason: 'één keer');
  });

  test('afspelen terwijl de pc nog speelde: naar waar de pc nu is, niet waar hij was toen de gsm hem laadde', () async {
    await v.opStand(_stand(op: nu, overname: 'gsm-1'));
    nu += 60000;
    await v.opStand(_stand(trackId: 'c', index: 2, positie: 30000, op: nu));
    expect(gsm.geladen.single.positie, const Duration(seconds: 30));
    nu += 20000;
    gsm.speelt = true; // Saber drukt op de gsm op afspelen.
    v.spelerVeranderd();
    expect(plekken, [(nummer: 'c', plek: const Duration(seconds: 50))]);
    v.spelerVeranderd();
    expect(plekken, hasLength(1), reason: 'één keer');
  });

  test('speelt de gsm zelf iets, dan volgt hij niet; een radio op de pc neemt hij niet stil over (dan de balk)', () async {
    await v.opStand(_stand(op: nu, overname: 'gsm-1'));
    gsm.speelt = true;
    nu += 30000;
    await v.opStand(_stand(trackId: 'd', rij: const ['d'], index: 0, op: nu));
    expect(gsm.geladen, isEmpty);
    gsm.speelt = false;
    nu += 30000;
    await v.opStand(_stand(trackId: 'e', rij: const ['e'], index: 0, op: nu, radio: {'artiest': 'Sade'}));
    expect(gsm.geladen, isEmpty, reason: 'een radio zou hier gaan spelen');
    expect(v.aanbod?.radioArtiest, 'Sade', reason: 'de balk biedt hem aan');
  });

  test('nam een derde toestel het over (de Shield van de pc), dan volgt de gsm de Shield', () async {
    await v.opStand(_stand(op: nu, overname: 'gsm-1'));
    nu += 60000;
    await v.opStand(_stand(trackId: 'c', index: 2, op: nu, van: 'dev:shield', overname: 'pc-THUIS'));
    expect(v.volgt, 'dev:shield');
    expect(gsm.geladen.single.index, 2);
  });

  test('na een herstart van de app: teruggezet, en dan meteen de stand van wie gevolgd wordt', () async {
    final w = VerderLuisteren(gsm, klok: () => nu)..volg('pc-THUIS');
    gsm.speelt = false;
    expect(w.volgt, 'pc-THUIS');
    await w.opStand(_stand(trackId: 'd', rij: const ['a', 'b', 'c', 'd'], index: 3, playing: false, positie: 5000, op: nu));
    expect(gsm.geladen.single.index, 3);
    w.volg('gsm-1');
    expect(w.volgt, isNull, reason: 'jezelf volgen kan niet');
  });

  test('de app sluit het aan: bewaren in een bestandje, de plek alleen bij hetzelfde nummer, en spelen meldt het', () {
    final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(m, contains("  final volgBestand = appFile('verder_volgt.txt');"));
    expect(m, contains('    if (volgBestand.existsSync()) verder.volg(volgBestand.readAsStringSync().trim());'));
    expect(m, contains('    if (player.current?.path == t.path) player.seek(plek);'));
    expect(m, contains('  verder.bijGevolgd = player.vergeetOvergenomen;'));
    expect('verder.meldNu(speelt: playing)'.allMatches(m), hasLength(2));
    final p = File('lib/player.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final i = p.indexOf('  void vergeetOvergenomen() {');
    expect(p.substring(i, p.indexOf('\n  }\n', i)), contains('_overgenomenPad = null;'));
  });
}
