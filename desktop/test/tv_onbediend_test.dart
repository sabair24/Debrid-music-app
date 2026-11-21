/// Een tv die voor zich uit speelt, bouwt de catalogus niet om de vijftien seconden opnieuw op (21-11-2026).
///
/// Een radio op de Shield, live gemeten: de tekendraad stond om de ~15 s 250–300 ms stil (fps.log, "WACHT OP START"),
/// 3 tot 6 keer per minuut, en vóór de radio nul keer. Tijdens een radio verandert de catalogus van de pc bij bijna elke
/// ronde: een nummer landt, zijn plaat wordt rechtgezet, de luidheid gemeten, een hoes gevonden. Elke keer haalde de
/// Shield de hele catalogus (3 MB, 2150 nummers) en bouwde hij alles opnieuw op. Saber: *"los dit op nu"*.
/// De toets met de nep-pc staat in `lan_client_test.dart` ("een tv die niemand bedient").
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/tv.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  tearDown(() => setTvModeForTest(false));

  group('onbediend', () {
    test('DE KERN: twee minuten zonder toets is onbediend; een toets maakt het ongedaan', () {
      setTvModeForTest(true);
      final nu = DateTime(2026, 11, 21, 9, 30);
      tvLaatstBediend = nu.subtract(const Duration(minutes: 3));
      expect(tvOnbediend(nu: nu), isTrue);
      tvLaatstBediend = nu.subtract(const Duration(seconds: 119));
      expect(tvOnbediend(nu: nu), isFalse);
      tvLaatstBediend = nu.subtract(kTvOnbediendNa);
      expect(tvOnbediend(nu: nu), isTrue, reason: 'precies de grens telt al');
    });

    test('alleen op een tv: een gsm of een Mac wordt nooit onbediend', () {
      setTvModeForTest(false);
      final nu = DateTime(2026, 11, 21, 9, 30);
      tvLaatstBediend = nu.subtract(const Duration(hours: 1));
      expect(tvOnbediend(nu: nu), isFalse);
    });

    test('de grenzen: twee minuten stil, en dan hoogstens om de tien minuten de hele catalogus', () {
      expect(kTvOnbediendNa, const Duration(minutes: 2));
      expect(LibraryStore.kCatalogusOnbediendElke, const Duration(minutes: 10));
    });
  });

  group('de DTO\'s op de andere isolate', () {
    test('een catalogus komt als DTO terug, met zijn nummers', () async {
      final json = {
        'artists': [
          {'id': 'a1', 'name': 'Nancy Wilson', 'albumCount': 1}
        ],
        'albums': [
          {'id': 'b1', 'artistId': 'a1', 'artistName': 'Nancy Wilson', 'title': 'Broadway', 'year': 1964}
        ],
        'tracks': [
          {
            'id': 't1',
            'albumId': 'b1',
            'artistId': 'a1',
            'title': "This Time The Dream's On Me",
            'artistName': 'Nancy Wilson',
            'albumTitle': 'Broadway',
            'trackNo': 2,
            'durationMs': 180000,
            'ext': 'flac',
            'streamPath': '/stream/t1.flac',
          }
        ],
        'generatedAt': 0,
      };
      final dto = await ontleedCatalogusDto(Uint8List.fromList(utf8.encode(jsonEncode(json))));
      expect(dto, isNotNull);
      expect(dto!.tracks.single.title, "This Time The Dream's On Me");
      expect(dto.albums.single.title, 'Broadway');
    });

    test('onleesbaar is geen bibliotheek: null, geen uitzondering uit de isolate', () async {
      expect(await ontleedCatalogusDto(Uint8List.fromList(utf8.encode('{niet json'))), isNull);
      expect(await ontleedCatalogusDto(Uint8List.fromList(utf8.encode('[1, 2]'))), isNull);
    });
  });

  group('aangesloten (gelezen uit de bron)', () {
    test('elke toets op de tv zet de klok, nog vóór de schermbeveiliging', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('  bool _tvVangnet(KeyEvent e) {\n'
          '    if (isTv && e is KeyDownEvent) tvLaatstBediend = DateTime.now();\n'
          '    if (isTv && mounted && _tvStilWekker(e)) return true;\n'));
      expect(m, contains('  library.onbediend = tvOnbediend;\n'));
    });

    test('de client ontleedt de DTO\'s niet meer op de tekendraad', () {
      final c = _bron('lib/lan/client.dart');
      expect(c, contains('    final dto = await ontleedCatalogusDto(res.bodyBytes);\n'));
      expect(c, isNot(contains('CatalogDto.fromJson(decoded)')));
    });

    test('op een Android-toestel schrijft het haperlogboek mee, zodat het op de Shield te meten valt', () {
      expect(_bron('lib/main.dart'), contains('  if (!mode.owner && Platform.isAndroid) haperlogAan = true;\n'));
      final m = _bron('lib/main.dart');
      final toestel = m.substring(m.indexOf('  if (!mode.owner) {\n    final ik = thisDevice();\n    Warmtemeter('));
      expect(toestel.substring(0, toestel.indexOf(').start();')), contains('      bijStilstand: haperVast,\n'),
          reason: 'ook elke stilstand op een toestel, met tijdstip');
      expect(_bron('lib/library.dart'),
          contains("    traagMeten('catalogus overnemen', () => _adoptCatalog(catalog, client), vanafMs: 5);\n"));
    });
  });
}
