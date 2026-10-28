// Logregels langs een open bestand (28-10-2026). Saber: "ik merk soms happering". Elke regel opende, schreef,
// flushte en sloot zijn bestand op de tekendraad — gemeten ~5 ms per regel, met een open bestand 0,25 ms. Hier ligt
// vast dat het gedrag hetzelfde blijft: volgorde, weggehaald bestand, halveren boven de grens, meerdere WarmLogs.
import 'dart:io';

import 'package:debridmusic/haperlog.dart';
import 'package:debridmusic/rutracker.dart';
import 'package:debridmusic/warm_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory map;
  setUp(() {
    map = Directory.systemTemp.createTempSync('warmlog_');
    WarmLog.houdOpen = true;
  });
  tearDown(() {
    WarmLog.houdOpen = false;
    WarmLog.sluitAlles();
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<String> regels(String pad) => File(pad).readAsLinesSync().map((r) => r.substring(14)).toList();

  test('DE KERN: regels komen in volgorde aan en zijn meteen te lezen', () {
    final pad = '${map.path}${Platform.pathSeparator}a.log';
    final log = WarmLog(pad);
    for (var i = 0; i < 50; i++) {
      log.line('regel $i');
    }
    expect(regels(pad), [for (var i = 0; i < 50; i++) 'regel $i'],
        reason: 'zonder sluiten: een ander die meeleest, ziet alles al');
  });

  test('twee WarmLogs op hetzelfde bestand schrijven achter elkaar, zoals de app ze overal los maakt', () {
    final pad = '${map.path}${Platform.pathSeparator}b.log';
    WarmLog(pad).line('een');
    WarmLog(pad).line('twee');
    WarmLog(pad).line('drie');
    expect(regels(pad), ['een', 'twee', 'drie']);
  });

  test('een weggehaald logboek komt terug, en de regels verdwijnen niet in een bestand zonder naam', () {
    final pad = '${map.path}${Platform.pathSeparator}c.log';
    final log = WarmLog(pad)..line('voor');
    // Op Windows gaat een open bestand niet weg; elders wel, en dan moet WarmLog het zelf merken.
    if (Platform.isWindows) WarmLog.sluitAlles();
    File(pad).deleteSync();
    log.line('na');
    expect(regels(pad), ['na']);
  });

  test('DE GRENS: boven de maximale grootte wordt hij gehalveerd, zoals voorheen', () {
    final pad = '${map.path}${Platform.pathSeparator}d.log';
    final log = WarmLog(pad, maxBytes: 2000);
    for (var i = 0; i < 200; i++) {
      log.line('regel nummer $i met wat tekst erachter');
    }
    expect(File(pad).lengthSync(), lessThan(4000));
    expect(regels(pad).last, 'regel nummer 199 met wat tekst erachter', reason: 'de nieuwste regel blijft');
  });

  test('de haperlog schrijft niets zolang de app hem niet aanzet (toetsen raken de echte appmap nooit)', () {
    expect(haperlogAan, isFalse);
    expect(traagMeten('iets', () => 42, vanafMs: 0), 42);
  });

  test('RuTracker: de Cloudflare-controle wordt in de bytes gevonden, ook met hoofdletters', () {
    final gewoon = 'x' * 50000;
    expect(rutrackerPaginaKenmerk(200, '$gewoon<html>gewoon</html>'.codeUnits), '200, 50019 bytes');
    expect(rutrackerPaginaKenmerk(403, '<script>window._CF_CHL_OPT={}</script>'.codeUnits), contains('CONTROLE'));
    expect(rutrackerPaginaKenmerk(403, 'src="https://challenges.cloudflare.com/x"'.codeUnits), contains('CONTROLE'));
    expect(rutrackerPaginaKenmerk(200, 'a __cf_chl b'.codeUnits), contains('CONTROLE'));
  });
}
