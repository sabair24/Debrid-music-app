/// Zeven nummers uit één torrent, tegelijk aangeklikt.
///
/// **Waarom dit bestaat.** Gemeld op 31-08-2026 en diezelfde dag nagespeeld met Beyoncé —
/// Dangerously In Love via RuTracker: zeven nummers aangevraagd, zes mislukt. Uit aria2's eigen
/// logboek:
///
///     21:59:17.951  torrent toegevoegd: gid=531295c6334b5a3a, kies=5,19
///     21:59:17.959  torrent toegevoegd: gid=9906543bd9c88472, kies=6,19
///     21:59:17.964  torrent toegevoegd: gid=0c29a60258121b6a, kies=10,19
///     ...
///     Exception: errorCode=12 InfoHash f4de10c2… is already registered.
///
/// Zeven aanmeldingen binnen acht duizendsten van een seconde. De app kéék wel of de torrent al
/// liep, maar dat kaartje wordt pas ingevuld nádat een aanmelding gelukt is — dus lazen alle zeven
/// hetzelfde lege kaartje. Kijken-en-dan-doen zonder slot ertussen.
///
/// Deze test praat met de ECHTE aria2, want het gaat om zíjn gedrag: `aria2.addTorrent` neemt een
/// tweede aanmelding aan, geeft netjes een gid terug, en wijst hem pas een tel later af. Een
/// nagebouwde motor zou juist dat detail wegpoetsen — en dat detail ís de bug.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/aria2.dart';
import 'package:debridmusic/paths.dart';

/// Een geldige torrent van zeventien bestanden, ter plekke gebencodeerd.
///
/// Niemand seedt hem, en dat hoeft ook niet: het gaat hier alleen over aanmelden. [naam] maakt de
/// infohash uniek per test, zodat een blijven hangende taak van de vorige test de volgende niet
/// stiekem laat slagen.
List<int> torrentBytes(String naam) {
  final uit = <int>[];
  void tekst(String s) {
    final b = utf8.encode(s);
    uit.addAll(utf8.encode('${b.length}:'));
    uit.addAll(b);
  }

  uit.addAll(utf8.encode('d4:info'));
  uit.addAll(utf8.encode('d5:files'));
  uit.addAll(utf8.encode('l'));
  for (var i = 1; i <= 17; i++) {
    uit.addAll(utf8.encode('d6:length'));
    uit.addAll(utf8.encode('i${1000 * i}e'));
    uit.addAll(utf8.encode('4:pathl'));
    tekst('${i.toString().padLeft(2, '0')} - nummer.flac');
    uit.addAll(utf8.encode('ee'));
  }
  uit.addAll(utf8.encode('e'));
  tekst('name');
  tekst(naam);
  uit.addAll(utf8.encode('12:piece lengthi262144e'));
  // Precies één stuk-hash, en daarom zijn de bestanden zo klein: samen 153000 bytes, ruim binnen
  // één stuk van 262144. aria2 rekent dat na en weigert een torrent waar dat niet klopt.
  uit.addAll(utf8.encode('6:pieces20:'));
  uit.addAll(List<int>.filled(20, 7));
  uit.addAll(utf8.encode('e')); // einde info
  uit.addAll(utf8.encode('e')); // einde torrent
  return uit;
}

/// Waar aria2 staat als je hem niet vanuit de app zoekt.
///
/// [Aria2.kandidaten] kijkt naast `Platform.resolvedExecutable`, en dat is in een test de
/// flutter_tester — daar staat niets. De motor zelf hoeft daar niet voor te veranderen: hier weten
/// we gewoon waar de geïnstalleerde app hem heeft neergezet.
String? aria2Pad() {
  final kandidaten = [
    if (Platform.environment['ARIA2'] != null) Platform.environment['ARIA2']!,
    if (Platform.isWindows)
      '${Platform.environment['LOCALAPPDATA']}\\Programs\\DebridMusic\\aria2c.exe',
    if (!Platform.isWindows) ...['/usr/bin/aria2c', '/usr/local/bin/aria2c', '/opt/homebrew/bin/aria2c'],
  ];
  for (final k in kandidaten) {
    if (File(k).existsSync()) return k;
  }
  return null;
}

void main() {
  late Aria2 motor;
  late Directory werk;
  final gids = <String>[];
  final exe = aria2Pad();

  setUp(() async {
    werk = Directory.systemTemp.createTempSync('dm_zelfde_');
    // aria2 krijgt `--log=$logDir/aria2.log`, en `logDir` leunt op path_provider — dat heeft in een
    // test geen platformkant. Zonder deze regel start aria2 op een onbruikbaar logpad en komt hij
    // nooit omhoog; de meting wachtte dan vijf seconden op een poort waar niemand zat.
    setAppDirForTest(werk.path);
    motor = Aria2(pad: exe);
  });

  tearDown(() async {
    for (final g in gids) {
      try {
        await motor.verwijder(g);
      } catch (_) {}
    }
    gids.clear();
    await motor.stop();
    try {
      werk.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('ZONDER SLOT: zes van de zeven worden afgewezen', () async {
    if (motor.pad == null) {
      markTestSkipped('aria2 staat niet op deze machine');
      return;
    }
    expect(await motor.start(downloadMap: werk.path), isTrue, reason: 'aria2 moet starten');
    final bytes = torrentBytes('zonder-slot');

    // Precies wat zeven klikken deden: alle zeven tegelijk aanmelden.
    final uit = await Future.wait([
      for (final n in [5, 6, 10, 13, 11, 7, 17])
        motor.voegTorrentToe(bytes, map: werk.path, kies: [n]),
    ]);
    gids.addAll(uit.whereType<String>());

    // aria2 GEEFT ze allemaal een gid — daar zat de val. Pas in zijn eigen lus valt het om.
    await Future<void>.delayed(const Duration(seconds: 2));
    var levend = 0;
    for (final g in uit.whereType<String>()) {
      final s = await motor.stand(g);
      if (s != null && !s.stuk) levend++;
    }
    expect(levend, 1,
        reason: 'dit IS de klacht: zeven aanmeldingen, één taak, zes stille afwijzingen');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('DE REPARATIE: één aanmelding, en de rest kiest erbij', () async {
    if (motor.pad == null) {
      markTestSkipped('aria2 staat niet op deze machine');
      return;
    }
    expect(await motor.start(downloadMap: werk.path), isTrue);
    final bytes = torrentBytes('met-slot');
    final gevraagd = [5, 6, 10, 13, 11, 7, 17];

    // Hetzelfde slot als in `online.dart`: wie er als eerste is meldt aan, de rest wacht en haakt
    // aan op diezelfde taak.
    String? gedeeld;
    Future<void> slot = Future<void>.value();
    Future<void> vraag(int n) {
      slot = slot.then((_) async {
        final lopend = gedeeld;
        if (lopend != null && await motor.kiesErbij(lopend, [n])) return;
        gedeeld = await motor.voegTorrentToe(bytes, map: werk.path, kies: [n]);
      });
      return slot;
    }

    await Future.wait([for (final n in gevraagd) vraag(n)]);
    expect(gedeeld, isNotNull, reason: 'de eerste aanmelding hoort gewoon te lukken');
    gids.add(gedeeld!);

    await Future<void>.delayed(const Duration(seconds: 2));
    final s = await motor.stand(gedeeld!);
    expect(s, isNotNull);
    expect(s!.stuk, isFalse, reason: 'er is er maar één aangemeld, dus niets om af te wijzen');

    // En alle zeven staan er echt in — aanhaken mag nummer één niet uit de selectie duwen.
    final gekozen = s.gekozen.map((b) => b.index).toSet();
    expect(gekozen, containsAll(gevraagd),
        reason: 'select-file hoort samengevoegd te zijn, niet overschreven');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
