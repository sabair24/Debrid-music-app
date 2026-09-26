/// Een Soulseek-storing is geen mislukt nummer.
///
/// Gemeten op 26-09-2026: om 11:54 moest de verbinding opnieuw aanmelden en gaf de Soulseek-server
/// vijf keer op rij geen antwoord. Elke radiohaal faalde daarna binnen nul seconden met "Kan niet
/// inloggen bij Soulseek", elke plek werd afgeschreven, en de uploader kreeg de schuld. Nu is dat
/// een eigen uitkomst — [RadioLaterOpnieuw] — en blijft de plek staan voor straks.
library;

import 'dart:io';

import 'package:debridmusic/lan/radiohaler.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een pc waarvan Soulseek even niet meedoet — of die gewoon niets vindt.
class _Downloads extends DownloadManager {
  _Downloads(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged,
      {required this.storing});
  final bool storing;

  @override
  Future<String?> haalVoorRadio(
      {required String artiest, required String titel, int? seconden, int? jaar}) async {
    if (storing) throw const RadioLaterOpnieuw('Soulseek gaf geen antwoord');
    return null;
  }
}

Future<String> standNaAfloop(Radiohaler h) async {
  final haal = h.haal(artiest: 'Milk Inc.', titel: 'Never Again');
  for (var i = 0; i < 50; i++) {
    final s = h.stand(haal.id)['stand'];
    if (s != 'onderweg') return s as String;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return 'onderweg';
}

void main() {
  group('de rekensom', () {
    test('DE KERN: tijdens een storing wordt er niets nieuws gestart', () {
      final b = voorraadPlan([for (var i = 0; i < 10; i++) Haalstand.wacht],
          vooruitNu: 2, rust: true);
      expect(b.starten, isEmpty, reason: 'anders lopen er elke vijf seconden acht stuk');
    });

    test('DE VAL: wat al geland is gaat er tijdens de storing gewoon in', () {
      final b = voorraadPlan([Haalstand.geland, Haalstand.wacht, Haalstand.klaar],
          vooruitNu: 0, minVooruit: 2, rust: true);
      expect(b.inRij, [0, 2], reason: 'een storing mag de muziek die er al is niet tegenhouden');
      expect(b.starten, isEmpty);
    });

    test('DE GRENS: zonder storing start hij zoals altijd', () {
      final b = voorraadPlan([Haalstand.wacht, Haalstand.wacht], vooruitNu: 6);
      expect(b.starten, [0, 1]);
    });
  });

  group('de pc tegen de telefoon', () {
    late Directory wortel;
    setUp(() {
      wortel = Directory.systemTemp.createTempSync('dm_storing_');
      setAppDirForTest(wortel.path);
    });
    tearDown(() {
      try {
        wortel.deleteSync(recursive: true);
      } catch (_) {}
    });

    Radiohaler haler({required bool storing}) {
      final cfg = AppSettings();
      final d = _Downloads(OnlineService(cfg), SoulseekService(cfg), wortel.path, () async {},
          storing: storing);
      return Radiohaler(d, null, LibraryStore()..configDirOverride = wortel.path, null);
    }

    test('DE KERN: een storing heet "later", niet "mislukt"', () async {
      expect(await standNaAfloop(haler(storing: true)), 'later',
          reason: 'de telefoon moet deze plek straks opnieuw vragen, niet afschrijven');
    });

    test('DE GRENS: niets gevonden blijft gewoon "mislukt"', () async {
      expect(await standNaAfloop(haler(storing: false)), 'mislukt');
    });
  });
}
