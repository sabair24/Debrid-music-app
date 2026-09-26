/// De radio op een gekoppeld toestel: de telefoon plant, de pc haalt.
///
/// Tot de eindbeoordeling van 26-09-2026 had deze kant geen enkele toets, en daar zaten drie dingen
/// in die stil verkeerd gingen. Een pc die zich even verslikte (5xx) brandde bij elke poging acht
/// plekken van het plan op. Een verlopen koppeling (401) liet elk nummer mislukken zonder dat iemand
/// zei waarom. En een nummer dat klaar was maar nog niet in de catalogus stond, werd opgegeven —
/// terwijl het bestand op de pc bleef staan, nergens genoteerd voor het opruimen.
library;

import 'dart:io';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pc_radiobron.dart';
import 'package:debridmusic/lan/radiohaler.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een pc die antwoordt wat de toets wil.
class _Pc extends RemoteClient {
  _Pc(this.antwoord)
      : super(RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.2:47820'), token: 't'));
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> vraag) antwoord;

  @override
  Future<Map<String, dynamic>> ask(String path, Map<String, dynamic> body) => antwoord(body);
}

/// Een catalogus die pas na een paar keer laden bij is.
class _Catalogus extends LibraryStore {
  _Catalogus(this.perLading, this.ids);
  final List<List<Track>> perLading;
  final Map<String, String> ids;
  int geladen = 0;

  @override
  Future<bool> loadRemote({bool quiet = false, bool naEen304 = false}) async {
    final i = geladen < perLading.length ? geladen : perLading.length - 1;
    geladen++;
    tracks
      ..clear()
      ..addAll(perLading[i]);
    return true;
  }

  @override
  String? gedeeldId(String path) => ids[path];
}

/// Een catalogus die op artiest + titel antwoordt, zoals voor een oudere pc zonder id.
class _Eigen extends LibraryStore {
  _Eigen(this.t);
  final Track t;

  @override
  Future<bool> loadRemote({bool quiet = false, bool naEen304 = false}) async => true;

  @override
  Track? ownedTrack(String artist, String title) => t;
}

Track _nummer(String pad) => Track(path: pad, title: 'Freak Out', artist: '2 Fabiola', album: '');

PcRadiobron _bron(LibraryStore lib, _Pc pc) => PcRadiobron(
    library: lib, clientOf: () => pc, peilritme: Duration.zero, catalogusRitme: Duration.zero);

final _plek = Radioplek(artiest: '2 Fabiola', titel: 'Freak Out');

/// Een pc die de haal meteen start en bij de eerste peiling [stand] antwoordt.
_Pc _klaar(Map<String, dynamic> stand) =>
    _Pc((v) async => v['op'] == 'haal' ? {'id': 'r1'} : stand);

void main() {
  group('welk antwoord van de pc een plek voor straks is', () {
    test('DE KERN: niet bereikt, verslikt of te druk is later', () {
      expect(radioLaterBijStatus(null), isNotNull);
      expect(radioLaterBijStatus(500), isNotNull);
      expect(radioLaterBijStatus(503), isNotNull, reason: 'eerst brandde dit acht plekken op');
      expect(radioLaterBijStatus(429), isNotNull);
      expect(radioLaterBijStatus(408), isNotNull);
    });

    test('DE VAL: een verlopen koppeling zegt wat je moet doen', () {
      expect(radioLaterBijStatus(401), contains('koppel opnieuw'));
      expect(radioLaterBijStatus(403), contains('koppel opnieuw'));
    });

    test('DE GRENS: een antwoord over dit ene nummer slaat de plek over', () {
      expect(radioLaterBijStatus(400), isNull);
      expect(radioLaterBijStatus(404), isNull);
    });

    test('DE KERN: zo gooit de haal het ook', () async {
      final lib = _Catalogus([[]], {});
      Future<Object?> uitkomst(int? status) async {
        final pc = _Pc((v) async => throw RemoteException('nee', statusCode: status));
        try {
          return await _bron(lib, pc).haal(_plek);
        } catch (e) {
          return e;
        }
      }

      expect(await uitkomst(503), isA<RadioLaterOpnieuw>());
      expect(await uitkomst(null), isA<RadioLaterOpnieuw>());
      final koppeling = await uitkomst(401);
      expect(koppeling, isA<RadioLaterOpnieuw>());
      expect((koppeling as RadioLaterOpnieuw).waarom, contains('koppel opnieuw'));
      expect(await uitkomst(404), isNull);
    });
  });

  group('een net gehaald nummer terugvinden', () {
    test('DE KERN: een catalogus die achterloopt krijgt een paar kansen', () async {
      final t = _nummer('http://pc/stream/1');
      final lib = _Catalogus([
        [],
        [t]
      ], {
        t.path: 'id-1'
      });
      final pc = _klaar({'stand': 'klaar', 'trackId': 'id-1'});
      expect(await _bron(lib, pc).haal(_plek), same(t),
          reason: 'eerst gaf de eerste lading die hem niet had meteen op');
      expect(lib.geladen, 2);
    });

    test('DE VAL: nooit een ander bestand, ook niet na de laatste poging', () async {
      final eigen = _nummer('http://pc/stream/album');
      final lib = _Catalogus([
        [eigen]
      ], {
        eigen.path: 'id-album'
      });
      final pc = _klaar({'stand': 'klaar', 'trackId': 'id-single'});
      expect(await _bron(lib, pc).haal(_plek), isNull,
          reason: 'je eigen albumversie is niet wat de radio ophaalde');
      expect(lib.geladen, kCatalogusPogingen);
    });

    test('DE KERN: wat op je eigen muziek landde, komt terug als van jou', () async {
      final t = _nummer('http://pc/stream/1');
      final lib = _Catalogus([
        [t]
      ], {
        t.path: 'id-1'
      });
      final pc = _klaar({'stand': 'eigen', 'trackId': 'id-1'});
      Object? fout;
      try {
        await _bron(lib, pc).haal(_plek);
      } catch (e) {
        fout = e;
      }
      expect(fout, isA<AlVanJou>());
      expect((fout as AlVanJou).nummer, same(t));
    });

    test('DE VAL: een oudere pc zonder id — dan is niets van de radio', () async {
      final lib = _Eigen(_nummer('http://pc/stream/album'));
      final pc = _klaar({'stand': 'klaar'});
      await expectLater(_bron(lib, pc).haal(_plek), throwsA(isA<AlVanJou>()),
          reason: 'elke pc die nu buiten staat noemt geen id, en op naam vond dit JOUW albumversie — '
              'die dan met een duim of het opruimoverzicht naar de prullenbak ging');
      await expectLater(_bron(lib, _klaar({'stand': 'eigen'})).haal(_plek), throwsA(isA<AlVanJou>()));
    });

    test('DE VAL: een koppeling die tijdens het peilen verloopt, is een pauze', () async {
      final lib = _Catalogus([[]], {});
      final pc = _Pc((v) async => v['op'] == 'haal'
          ? {'id': 'r1'}
          : throw const RemoteException('verlopen', statusCode: 401));
      await expectLater(_bron(lib, pc).haal(_plek), throwsA(isA<RadioLaterOpnieuw>()),
          reason: 'eerst werd dit acht minuten lang genegeerd');
    });

    test('DE GRENS: Soulseek op de pc doet even niet mee', () async {
      final lib = _Catalogus([[]], {});
      final pc = _klaar({'stand': 'later'});
      await expectLater(_bron(lib, pc).haal(_plek), throwsA(isA<RadioLaterOpnieuw>()));
    });
  });

  group('de pc meldt een landing op je eigen muziek', () {
    late Directory wortel;
    setUp(() {
      wortel = Directory.systemTemp.createTempSync('dm_pcradio_');
      setAppDirForTest(wortel.path);
    });
    tearDown(() {
      try {
        wortel.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: een eigen stand, zodat ook een ouder toestel het niet opruimt', () async {
      final cfg = AppSettings();
      final d = _AlGehad(OnlineService(cfg), SoulseekService(cfg), wortel.path, () async {});
      final h = Radiohaler(d, null, LibraryStore()..configDirOverride = wortel.path, null);
      final haal = h.haal(artiest: '2 Fabiola', titel: 'Freak Out');
      Map<String, dynamic> s = const {};
      for (var i = 0; i < 100; i++) {
        s = h.stand(haal.id);
        if (s['stand'] != 'onderweg') break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(s['stand'], 'eigen',
          reason: 'een ouder toestel zag "klaar" en behandelde jouw bestand als radionummer; alles '
              'wat niet "klaar" is, is daar een gemiste plek');
    });
  });
}

/// Een pc waar de haal op muziek landt die je al had.
class _AlGehad extends DownloadManager {
  _AlGehad(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged);

  @override
  Future<String?> haalVoorRadio(
      {required String artiest, required String titel, int? seconden, int? jaar}) async {
    throw RadioAlGehad('${Directory.systemTemp.path}${Platform.pathSeparator}Freak Out.flac');
  }
}
