// Live — V (2001), gemeld op 15-10-2026: de app crashte op de albumpagina, en "Overcome" had één bron.
//
// Drie oorzaken, alle drie gemeten via /api/soulseek/search:
// - "Live V" is voor Soulseek "live" (een woord van één letter telt niet): 60.143 bestanden, waarvan
//   1381 met "v" als woord in het pad. De pc stond 6,4 s stil om ze te versturen.
// - Er was geen bovengrens; de gsm kreeg 18 MB en zeefde die per nummer.
// - De zeef las de bandnaam in "Live - V - 13 - Overcome.flac" als een live-opname.
import 'dart:io';

import 'package:debridmusic/organize.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/zoekplafond.dart';
import 'package:flutter_test/flutter_test.dart';

SoulseekFile f(String pad) => SoulseekFile(
    username: 'peer', filename: pad, size: 30000000, speed: 1000000, queueLength: 0, freeSlots: true);

void main() {
  group('albumZoekvraag', () {
    test('een titel van één letter krijgt het jaar erbij', () {
      expect(albumZoekvraag('Live', 'V', jaar: 2001), 'Live V 2001');
      expect(albumZoekvraag('Weezer', 'X', jaar: 2019), 'Weezer X 2019');
    });

    test('een titel die Soulseek wél meetelt blijft zoals hij is', () {
      expect(albumZoekvraag('Adele', '21', jaar: 2011), 'Adele 21', reason: 'twee tekens tellen');
      expect(albumZoekvraag('Live', 'Throwing Copper', jaar: 1994), 'Live Throwing Copper');
      expect(albumZoekvraag('Prince', '1999', jaar: 1982), 'Prince 1999');
    });

    test('zonder jaar valt er niets toe te voegen', () {
      expect(albumZoekvraag('Live', 'V'), 'Live V');
      expect(albumZoekvraag('Live', 'V', jaar: 0), 'Live V');
    });
  });

  group('beperkZoekuitslag', () {
    test('onder het plafond verandert er niets, ook de volgorde niet', () {
      final lijst = [f(r'a\Live\V\01 - Intro.flac'), f(r'b\Iemand\Live at X\01 Intro.flac')];
      expect(beperkZoekuitslag('Live V 2001', lijst, plafond: 2), same(lijst));
    });

    test('erboven blijven de bestanden die de meeste woorden van de vraag noemen', () {
      final lijst = [
        f(r'a\Iemand\Live at Wembley\01 Intro.flac'), // live
        f(r'b\Live\V (2001)\13 - Overcome.flac'), // live, v, 2001
        f(r'c\Ander\Live 2001\03 Song.flac'), // live, 2001
        f(r'd\Live\V\13 Overcome.flac'), // live, v
        f(r'e\Nog iemand\Live\05 Song.flac'), // live
      ];
      final uit = beperkZoekuitslag('Live V 2001', lijst, plafond: 3);
      expect([for (final x in uit) x.filename[0]], ['b', 'c', 'd']);
    });

    test('bij gelijke stand blijft de volgorde die er was (lossless en snel eerst)', () {
      final lijst = [for (final c in ['a', 'b', 'c', 'd']) f('$c\\Live\\Live at $c\\01.flac')];
      expect([for (final x in beperkZoekuitslag('Live', lijst, plafond: 2)) x.filename[0]], ['a', 'b']);
    });

    test('het plafond ligt ruim boven een gewone albumvraag', () {
      expect(kZoekPlafond, greaterThanOrEqualTo(4400), reason: 'een volledig album gaf 4400 bestanden');
    });
  });

  group('fileOffersTitle: de band heet Live', () {
    bool overcome(String pad, [int? sec = 256]) => fileOffersTitle('Overcome', 255, 'Live', pad, sec, album: 'V');

    test('de bandnaam in de bestandsnaam is geen live-opname', () {
      expect(overcome(r'Music\Live\V (2001)\Live - V - 13 - Overcome.flac'), isTrue);
      expect(overcome(r'music\Live\V\13-live-overcome.flac'), isTrue);
      expect(overcome(r'music\Live\V\Live_V_13_Overcome.flac'), isTrue);
      expect(overcome(r'tidaldownloads\Albums\Live - V\13. Live - Overcome.flac'), isTrue);
    });

    test('de gewone naam bleef al werken', () {
      expect(overcome(r'music\Live\V (2001)\13 - Overcome.flac'), isTrue);
    });

    test('"(Live)" tussen haakjes blijft een live-opname, ook van deze band', () {
      expect(overcome(r'music\Live\V\13 - Overcome (Live).flac'), isFalse);
      expect(overcome(r'music\Live\Paradiso\12. Overcome [Live].flac'), isFalse);
    });

    test('bij een andere artiest blijft "live" een live-opname', () {
      expect(fileOffersTitle('Uprising', 304, 'Muse', r'm\Muse\Uprising\Muse - Uprising - Live.flac', 304),
          isFalse);
      expect(fileOffersTitle('We Shall Overcome', 285, 'Joan Baez', r'm\Joan Baez\Joan Baez - We Shall Overcome Live.flac', 285),
          isFalse);
    });

    test('de lengte beslist nog steeds', () {
      expect(overcome(r'Music\Live\V (2001)\Live - V - 13 - Overcome.flac', 300), isFalse);
    });
  });

  test('aangesloten: elke zoekvraag begrensd, en de albumpagina\'s vragen met het jaar', () {
    final online = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    // Sinds 24-10-2026 met de 24bit-zoekopdracht erbij samengevoegd (samen), en dan pas begrensd.
    expect(online, contains('return beperkZoekuitslag(query, samen);'));
    expect(online, contains('onPartial(beperkZoekuitslag(query, p))'));
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains('soulseek.search(_albumVraag, onPartial:'));
    expect(main, contains('SourcesView(query: _albumVraag, authority: _release)'));
    expect(main, contains('soulseek.search(albumZoekvraag(album.artist, album.title, jaar: album.year))'));
    expect(main, contains("SourcesView(query: albumZoekvraag(widget.name, w.title, jaar: int.tryParse(w.year ?? '')))"));
  });
}
