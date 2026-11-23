// Geduld in de wachtrij (Saber, 23-11-2026: "Geduld in de wachtrij" — een betere kopie bij een uploader met een rij tot
// 24 uur afwachten). Tot dan hield één uploader met een rij de hele jacht vast tot het budget van tien minuten op was
// ("budget op — N peers niet meer geprobeerd"), en dan was het voorbij. Hier: nep-uploaders over een nep-sessie, en de
// echte jacht van de app ertussen (zoals cd_wedloop_test).
import 'dart:async';
import 'dart:io';

import 'package:debridmusic/blijvende_jacht.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart' show TrackTags;
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

enum _Gedrag {
  /// Zet ons in zijn rij (plaats 16) en houdt ons daar; de volgende keer levert hij na een korte wachtrij.
  rijDanLevert,

  /// Zet ons in zijn rij; bij het geduld verbreekt hij de rij één keer (een herstart), daarna levert hij.
  rijVerbreekt,

  /// Altijd in de rij, nooit een plaats vrij: het geduld wacht tot zijn budget op is.
  altijdRij,

  /// Onbereikbaar.
  firewall,
}

class _NepSessie implements SlskSession {
  _NepSessie(this.gedrag);
  final Map<String, _Gedrag> gedrag;
  final pogingen = <String, int>{};
  final wachttijd = <String, List<Duration>>{};
  final toon = File('test/fixtures/tone.flac').readAsBytesSync();

  @override
  String get user => 'u';
  @override
  String get pass => 'p';

  Future<SlskResult> _lever(File destFile, void Function(int, int) onProgress) async {
    onProgress(1, toon.length);
    await destFile.parent.create(recursive: true);
    await destFile.writeAsBytes(toon);
    onProgress(toon.length, toon.length);
    return SlskDone(destFile.path);
  }

  @override
  Future<SlskResult> download(SoulseekFile file, File destFile, void Function(int, int) onProgress,
      {void Function(SlskQueued)? onStatus,
      bool waitInQueue = true,
      Duration maxWait = const Duration(minutes: 30),
      SlskCancel? cancel}) async {
    final wie = file.username;
    final n = pogingen[wie] = (pogingen[wie] ?? 0) + 1;
    (wachttijd[wie] ??= []).add(maxWait);
    Future<SlskResult> inDeRij() async {
      onStatus?.call(SlskQueued(16));
      await Future.any([cancel?.whenCancelled ?? Completer<void>().future, Future<void>.delayed(maxWait)]);
      return (cancel?.isCancelled ?? false) ? SlskCancelled() : SlskQueued(16);
    }

    switch (gedrag[wie]!) {
      case _Gedrag.firewall:
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return SlskFail('Uploader niet bereikbaar (firewall)');
      case _Gedrag.altijdRij:
        return inDeRij();
      case _Gedrag.rijDanLevert:
        if (n == 1) return inDeRij();
        onStatus?.call(SlskQueued(3));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _lever(destFile, onProgress);
      case _Gedrag.rijVerbreekt:
        if (n == 1) return inDeRij();
        if (n == 2) {
          onStatus?.call(SlskQueued(2));
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return SlskQueued(2); // de uploader verbrak de rij
        }
        return _lever(destFile, onProgress);
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  late Directory map;
  late DownloadManager d;
  late int toonGrootte;

  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_geduld_');
    setAppDirForTest(map.path);
    toonGrootte = File('test/fixtures/tone.flac').lengthSync();
    d = DownloadManager(
        OnlineService(AppSettings()), SoulseekService(AppSettings()..soulseekUser = 'u'..soulseekPass = 'p'), map.path,
        () async {})
      ..geduldOpnieuwWachtrij = const Duration(milliseconds: 40)
      ..geduldOpnieuwWeg = const Duration(milliseconds: 40);
  });

  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  _NepSessie sessie(Map<String, _Gedrag> gedrag) {
    final s = _NepSessie(gedrag);
    d.soulseek.sessieVoorToets = s;
    return s;
  }

  SoulseekFile f(String wie) => SoulseekFile(
      username: wie, filename: '@@$wie\\Dangerous (24bit)\\Jam.flac', size: toonGrootte, durationSec: 339);

  DownloadJob job() => DownloadJob('Michael Jackson — Jam')
    ..authority = const TrackTags(title: 'Jam', artist: 'Michael Jackson', album: 'Dangerous', trackNo: 1, seconds: 339);

  Future<String> log() async {
    final b = File('${map.path}/downloads.log');
    return b.existsSync() ? b.readAsStringSync() : '';
  }

  Future<void> totGeduldKlaar() async {
    final tot = DateTime.now().add(const Duration(seconds: 60));
    while (d.geduldigWachtend > 0 && DateTime.now().isBefore(tot)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(d.geduldigWachtend, 0, reason: 'het geduld is klaar');
  }

  test('DE KERN: een uploader met een rij houdt de jacht niet meer op — die kopie wacht apart, tot 24 uur', () async {
    final s = sessie({'rijman': _Gedrag.rijDanLevert, 'muur': _Gedrag.firewall});
    final klok = Stopwatch()..start();
    await d.jachtVoorToets([f('rijman'), f('muur')], job()).timeout(const Duration(seconds: 60));
    expect(klok.elapsed, lessThan(const Duration(seconds: 30)), reason: 'was tien minuten: het hele budget');
    expect(s.pogingen['muur'], 1, reason: 'de jacht ging meteen door naar de volgende uploader');
    await totGeduldKlaar();
    expect(s.pogingen['rijman'], 2, reason: 'één keer in de jacht, één keer geduldig');
    expect(s.wachttijd['rijman']!.first, lessThanOrEqualTo(const Duration(minutes: 10)), reason: 'de jacht: tien minuten');
    expect(s.wachttijd['rijman']!.last, greaterThan(const Duration(hours: 23)), reason: 'het geduld: tot 24 uur');
    final l = await log();
    expect(l, contains('rijman: wachtrij — de jacht gaat verder, deze kopie wacht geduldig tot 24 u (1 wachtend)'));
    // Wat na het wachten binnenkomt, gaat door de keuring van elke kopie. Hier is er geen nummer om tegen te meten
    // (geen bibliotheek): dan nooit als nieuw nummer opbergen.
    expect(l, contains('rijman leverde na het wachten, maar je nummer is er niet meer — weggegooid'));
    expect(map.listSync(recursive: true).whereType<File>().where((x) => x.path.endsWith('Jam.flac')), isEmpty,
        reason: 'niets opgeborgen, niets achtergelaten');
  });

  test('verbreekt de uploader de rij, dan vraagt het geduld opnieuw', () async {
    final s = sessie({'herstart': _Gedrag.rijVerbreekt});
    await d.jachtVoorToets([f('herstart')], job()).timeout(const Duration(seconds: 60));
    await totGeduldKlaar();
    expect(s.pogingen['herstart'], 3, reason: 'de jacht, het geduld dat verbroken werd, en het geduld opnieuw');
    expect(await log(), contains('herstart leverde na het wachten'));
  });

  test('aangesloten: de grenzen en de regels', () {
    expect(kJachtWachtrijGeduld, const Duration(hours: 24));
    expect(kWachtrijGeduldHoogstens, 20);
    expect(kGeduldOpnieuwWachtrij, const Duration(minutes: 3));
    expect(kGeduldOpnieuwWeg, const Duration(minutes: 30));
    final online = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(online, contains("_geduldig.length < kWachtrijGeduldHoogstens && !_geduldig.contains('\${f.username}|\${f.filename}'.toLowerCase());"));
    expect(online, contains('              if (geduldig || naarWachtrij || !_magGeduldig(f)) return;\n'
        '              naarWachtrij = true;\n'
        '              c.cancel();\n'));
    expect(online, contains('            budget: kJachtWachtrijGeduld,\n            geduldig: true)'));
    expect(online, contains('            if (geduldig && bestaand == null) {'));
  });
}
