/// Halve torrents die bleven liggen omdat de app dichtging terwijl ze liepen.
///
/// **Waarom.** aria2 start zonder sessiebestand, dus na een herstart hoort er niets meer bij wat onder
/// `_torrentwerk` ligt. De werkmap bleef staan "tot de volgende download van dezelfde plaat hem
/// overneemt", en die kwam nooit: op 11-10-2026 lagen er zes, samen zo'n 900 MB, de oudste van 30-08
/// (Oasis, "Wonderwall" 78 MB binnen toen de app om 09:41 dichtging).
library;

import 'dart:io';

import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory wortel;

  setUpAll(() => setAppDirForTest(Directory.systemTemp.createTempSync('dm_twerk_app_').path));
  setUp(() => wortel = Directory.systemTemp.createTempSync('dm_twerk_'));
  tearDown(() {
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  DownloadManager manager(String root) {
    final cfg = AppSettings();
    return DownloadManager(OnlineService(cfg), SoulseekService(cfg), root, () async {});
  }

  File maak(String relatief, [int bytes = 16]) {
    final f = File('${wortel.path}${Platform.pathSeparator}DebridMusic Downloads${Platform.pathSeparator}$relatief')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.filled(bytes, 1));
    return f;
  }

  String werk(String naam) => '$torrentWerkMap${Platform.pathSeparator}$naam';

  test('DE KERN: wat een vorige keer half bleef liggen, gaat weg — de rest van de downloads niet', () async {
    maak('${werk('86e99afd')}/Oasis - Morning Glory/03. Oasis - Wonderwall (Remastered).flac', 4096);
    maak('${werk('86e99afd')}/Oasis - Morning Glory.aria2');
    maak('${werk('4ce9cd14')}/Nirvana - Nevermind/01 - Smells Like Teen Spirit.flac', 4096);
    final plaat = maak('Albums/Oasis/Morning Glory/03 - Wonderwall.flac', 4096);

    expect(await manager(wortel.path).ruimDodeTorrentwerkOp(), 2);

    final werkmap = Directory('${wortel.path}${Platform.pathSeparator}DebridMusic Downloads'
        '${Platform.pathSeparator}$torrentWerkMap');
    expect(werkmap.listSync(), isEmpty);
    expect(plaat.existsSync(), isTrue, reason: 'alleen de werkmap, nooit de plaat zelf');
  });

  test('DE GRENS: een torrent die nu loopt, houdt zijn werkmap', () async {
    final loopt = maak('${werk('abcdef12')}/Plaat/01.flac');
    maak('${werk('86e99afd')}/Oud/01.flac');
    final d = manager(wortel.path)..torrentLooptVoorToets('ABCDEF1234567890abcdef1234567890abcdef12');
    expect(await d.ruimDodeTorrentwerkOp(), 1);
    expect(loopt.existsSync(), isTrue);
  });

  test('zonder werkmap is er niets te doen', () async {
    expect(await manager(wortel.path).ruimDodeTorrentwerkOp(), 0);
  });

  test('de app ruimt bij het opstarten op, naast het inlezen van de hervattingen', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main.contains("await fase('torrentwerk', () => downloads.ruimDodeTorrentwerkOp());"), isTrue);
    expect(File('lib/lan/remote_services.dart').readAsStringSync(),
        contains('Future<int> ruimDodeTorrentwerkOp() async => 0;'),
        reason: 'een toestel heeft geen torrents; die draaien op de pc');
  });
}
