/// Wat er gebeurt als de binnengehaalde kopie zélf betrapt wordt.
///
/// Vóór het binnenhalen valt er niets te weten — dat is op 06-08-2026 gemeten en verworpen, zie de
/// aantekening bij `_rankSlsk`. Maar zodra het bestand er ligt is het geen vermoeden meer, en dan
/// mag de app wél iets doen: iets ánders proberen, en de winnaar laten beslissen door de meting.
///
/// Twee schakels moeten daarvoor kloppen, en die legt deze test vast.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/soulseek.dart';

SoulseekFile _f(String naam, {int size = 30 * 1024 * 1024, int dur = 200, String user = 'peer'}) =>
    SoulseekFile(
      username: user,
      filename: r'music\Stromae\' + naam,
      size: size,
      speed: 0,
      queueLength: 0,
      freeSlots: true,
      durationSec: dur,
    );

Echtheidsoordeel get _afgekapt => const Echtheidsoordeel(
      bits: Bitdiepte.spreektNietTegen,
      boven: Bovenband.onbekend,
      band: Bandbreedte.afgekapt,
      afkapHz: 17200,
      wandDb: 49,
      vensters: 32,
    );

Echtheidsoordeel get _schoon => const Echtheidsoordeel(
      bits: Bitdiepte.spreektNietTegen,
      boven: Bovenband.onbekend,
      band: Bandbreedte.doorlopend,
      vensters: 32,
    );

void main() {
  group('welke kandidaten nog zin hebben', () {
    final genomen = _f('01 - Ta fete.flac', size: 64 * 1024 * 1024, user: 'kromsam2');

    test('dezelfde upload bij een andere peer valt af', () {
      // Honderd mensen delen hetzelfde bestand. Dat nog eens halen geeft hetzelfde oordeel en kost
      // alleen bandbreedte — dit is de reden dat de jacht niet oneindig doorgaat.
      final zelfde = _f('01 - Ta fete.flac', size: 64 * 1024 * 1024, user: 'iemandanders');
      expect(DownloadManager.andereKopieDan([zelfde], genomen), isEmpty);
    });

    test('een andere kopie blijft staan', () {
      final ander = _f('01 - Ta fete.flac', size: 37 * 1024 * 1024, user: 'toad');
      expect(DownloadManager.andereKopieDan([ander], genomen), hasLength(1));
    });

    test('een mp3 halen is geen vooruitgang als de FLAC uit een mp3 kwam', () {
      final mp3 = _f('01 - Ta fete.mp3', size: 7 * 1024 * 1024, user: 'x');
      expect(DownloadManager.andereKopieDan([mp3], genomen), isEmpty);
    });

    test('meerkanaals valt af — wordt teruggemengd en kost tien keer de ruimte', () {
      // Bewijs uit de getallen: 24/96 stereo kan onbewerkt niet boven 4608 kbit/s uitkomen.
      final surround = SoulseekFile(
        username: 'y',
        filename: r'music\Stromae\01 - Ta fete.flac',
        size: 300 * 1024 * 1024,
        speed: 0,
        queueLength: 0,
        freeSlots: true,
        durationSec: 175,
        sampleRate: 96000,
        bitDepth: 24,
      );
      expect(DownloadManager.andereKopieDan([surround], genomen), isEmpty);
    });
  });

  group('en wie wint er als de tweede kopie landt', () {
    late Directory root;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('dm_betrapt_');
      setAppDirForTest(root.path);
      resetEchtheidVoorTest();
      await laadEchtheid();
    });

    tearDown(() {
      resetEchtheidVoorTest();
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    File schrijf(String naam, int mb) {
      final f = File('${root.path}${Platform.pathSeparator}$naam');
      f.writeAsBytesSync(List.filled(mb * 1024 * 1024, 7));
      return f;
    }

    test('de schone kopie wint van de betrapte, ook al is die GROTER', () async {
      // Dit is de hele reden dat de jacht mag bestaan. Een uit mp3 omgezette FLAC is vaak groter
      // dan het origineel — gemeten 64 MB tegen 37 MB op Stromae — dus op grootte vergelijken koos
      // stelselmatig de nep. Zonder deze regel zou de jacht de betere kopie weer weggooien.
      final nep = schrijf('nep.flac', 64);
      final echt = schrijf('echt.flac', 37);
      await onthoudOordeel(nep.path, _afgekapt);
      await onthoudOordeel(echt.path, _schoon);

      expect(firstIsBetter(echt, nep), isTrue, reason: 'de schone hoort te winnen');
      expect(firstIsBetter(nep, echt), isFalse, reason: 'en de betrapte te verliezen');
    });

    test('zonder oordeel beslist de grootte, zoals altijd', () async {
      // De meting mag alleen iets veranderen als ze er IS. Een ongemeten paar hoort zich precies te
      // gedragen als vóór dit alles bestond.
      final groot = schrijf('groot.flac', 60);
      final klein = schrijf('klein.flac', 30);
      expect(firstIsBetter(groot, klein), isTrue);
      expect(firstIsBetter(klein, groot), isFalse);
    });

    test('twee betrapte kopieën vallen terug op de grootte', () async {
      // Geen van beide is beter op grond van de meting, dus mag de oude regel het weer beslissen —
      // en niet stilzwijgend de eerste of de laatste winnen.
      final a = schrijf('a.flac', 60);
      final b = schrijf('b.flac', 30);
      await onthoudOordeel(a.path, _afgekapt);
      await onthoudOordeel(b.path, _afgekapt);
      expect(firstIsBetter(a, b), isTrue);
    });
  });
}
