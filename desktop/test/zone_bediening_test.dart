/// Een zone kiezen en bedienen, deelstap 2.2 (Saber, 21-10-2026: "dat ik bevoorbeeld vanaf men gsm of ipad
/// het volgende kan tikken, soort van remote").
///
/// Wat hier vastligt: welke zone er bij het openen gekozen is; dat wat je indrukt meteen op het scherm
/// staat en daarna door de zone zelf rechtgezet wordt; dat de volumeschuif de zone niet overspoelt; dat
/// een tik in de bibliotheek de juiste ids stuurt; wat een toestel met een opdracht doet; en dat een
/// opdracht over de lijn bij het juiste toestel aankomt.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart' show RepeatMode, Rijbediening, Speelbron;
import 'package:debridmusic/zone_lijst.dart';
import 'package:debridmusic/zone_opdracht.dart';
import 'package:debridmusic/zone_speler.dart';

Track _t(String id) => Track(path: 'http://pc.invalid/stream/$id.flac', title: 'Nummer $id', artist: 'X', album: 'A');

const _nu = 10000000;

ZoneStaat _pc({bool online = true, bool playing = true, int opMs = _nu, String trackId = 'b', int volume = 70}) =>
    ZoneStaat(
      id: 'dev:pc-THUIS',
      soort: ZoneSoort.pc,
      naam: 'THUIS',
      online: online,
      playing: playing,
      trackId: trackId,
      titel: 'Titel',
      positionMs: 60000,
      durationMs: 240000,
      opMs: opMs,
      index: 3,
      lengte: 10,
      volume: volume,
    );

ZoneLijst _lijst(List<ZoneStaat> zones, {int Function()? klok}) =>
    ZoneLijst(hier: 'dev:gsm-1', klok: klok ?? () => _nu)
      ..zet({'nu': _nu, 'zones': [for (final z in zones) z.toJson()]});

void main() {
  group('welke zone bij het openen', () {
    test('de laatst gekozen, als ze bereikbaar is en speelt of nog geen half uur stilstaat', () {
      expect(kiesBijStart('dev:pc-THUIS', [_pc()], nuMs: _nu, hier: 'dev:gsm-1'), 'dev:pc-THUIS');
      final tienMin = _nu - const Duration(minutes: 10).inMilliseconds;
      expect(kiesBijStart('dev:pc-THUIS', [_pc(playing: false, opMs: tienMin)], nuMs: _nu, hier: 'dev:gsm-1'),
          'dev:pc-THUIS');
    });

    test('anders dit toestel (Saber: "Uit, of langer dan 30 min stil")', () {
      final uurGeleden = _nu - const Duration(minutes: 31).inMilliseconds;
      expect(kiesBijStart('dev:pc-THUIS', [_pc(online: false)], nuMs: _nu, hier: 'dev:gsm-1'), isNull);
      expect(kiesBijStart('dev:pc-THUIS', [_pc(trackId: '')], nuMs: _nu, hier: 'dev:gsm-1'), isNull);
      expect(kiesBijStart('dev:pc-THUIS', [_pc(playing: false, opMs: uurGeleden)], nuMs: _nu, hier: 'dev:gsm-1'),
          isNull);
      expect(kiesBijStart('dev:weg', [_pc()], nuMs: _nu, hier: 'dev:gsm-1'), isNull);
      expect(kiesBijStart('', [_pc()], nuMs: _nu, hier: 'dev:gsm-1'), isNull);
    });
  });

  group('ids heen en terug', () {
    test('wat de pc niet kent valt weg, en de plek schuift mee', () {
      final r = idsVoor([_t('a'), _t('x'), _t('c')], 1, (t) => t.title == 'Nummer x' ? null : t.title);
      expect(r.ids, ['Nummer a', 'Nummer c']);
      expect(r.plek, 1, reason: 'het getikte nummer kan niet mee: het volgende');
      final terug = rijUitIds(['a', 'onbekend', 'c'], 2, (id) => id == 'onbekend' ? null : _t(id));
      expect([for (final t in terug.rij) t.title], ['Nummer a', 'Nummer c']);
      expect(terug.plek, 1);
    });
  });

  group('ZoneSpeler', () {
    test('toont de zone, en wat je indrukt staat er meteen; de zone zet het daarna recht', () {
      fakeAsync((fa) {
        var klok = _nu;
        final lijst = _lijst([_pc()], klok: () => klok);
        final gestuurd = <Map<String, dynamic>>[];
        final z = ZoneSpeler(
          lijst: lijst,
          zoneId: 'dev:pc-THUIS',
          nummer: _t,
          idVan: (t) => t.title,
          hoesVan: (_) => null,
          stuur: (op) async {
            gestuurd.add(op);
            return null;
          },
          klok: () => klok,
        );
        expect(z.current!.title, 'Nummer b');
        expect(z.playing, isTrue);
        expect(z.volume, 70);
        expect(z.hasNext, isTrue);

        z.pauzeer();
        expect(z.playing, isFalse, reason: 'meteen, zonder op de pc te wachten');
        fa.flushMicrotasks();
        expect(gestuurd.single, {'cmd': 'pause'});

        // Een gewone melding die net voor de druk vertrok: de knop springt niet terug.
        lijst.zet({'nu': klok + 10, 'zones': [_pc(opMs: klok + 10).toJson()]});
        expect(z.playing, isFalse, reason: 'pas terug als de zone het tegenspreekt na drie seconden');

        // De pc meldt nog niets: na drie seconden geldt weer wat de zone zelf zegt.
        klok += 3500;
        fa.elapse(const Duration(milliseconds: 3500));
        expect(z.playing, isTrue, reason: 'de pauze kwam niet aan: niet blijven doen alsof');

        // Nu meldt de pc echt gepauzeerd.
        lijst.zet({'nu': klok, 'zones': [_pc(playing: false, opMs: klok).toJson()]});
        expect(z.playing, isFalse);
        z.dispose();
      });
    });

    test('de volumeschuif stuurt hoogstens vier keer per seconde, en de laatste stand komt aan', () {
      fakeAsync((fa) {
        final gestuurd = <Map<String, dynamic>>[];
        final z = ZoneSpeler(
          lijst: _lijst([_pc()]),
          zoneId: 'dev:pc-THUIS',
          nummer: _t,
          idVan: (t) => t.title,
          hoesVan: (_) => null,
          stuur: (op) async {
            gestuurd.add(op);
            return null;
          },
        );
        for (var v = 10; v <= 60; v += 5) {
          z.setVolume(v.toDouble());
        }
        fa.flushMicrotasks();
        expect(gestuurd, [
          {'cmd': 'volume', 'waarde': 10}
        ]);
        fa.elapse(const Duration(milliseconds: 600));
        expect(gestuurd.length, 2);
        expect(gestuurd.last, {'cmd': 'volume', 'waarde': 60});
        expect(z.volume, 60);
        z.dispose();
      });
    });

    test('een tik in de bibliotheek: de ids en de plek; niet bereikbaar zegt het', () async {
      final gestuurd = <Map<String, dynamic>>[];
      final z = ZoneSpeler(
        lijst: _lijst([_pc(online: false)]),
        zoneId: 'dev:pc-THUIS',
        nummer: _t,
        idVan: (t) => t.title == 'Nummer x' ? null : t.title,
        hoesVan: (_) => null,
        stuur: (op) async {
          gestuurd.add(op);
          return null;
        },
      );
      await z.playQueue([_t('a'), _t('x'), _t('c')], 2);
      await z.shuffleAll([_t('a'), _t('c')]);
      z.speelHierna([_t('c')]);
      await z.speelNuMetRest(_t('a'));
      await Future<void>.delayed(Duration.zero);
      expect(gestuurd, [
        {'cmd': 'speel', 'ids': ['Nummer a', 'Nummer c'], 'plek': 1},
        {'cmd': 'speel', 'ids': ['Nummer a', 'Nummer c'], 'plek': 0, 'shuffle': true},
        {'cmd': 'hierna', 'ids': ['Nummer c']},
        {'cmd': 'nu', 'id': 'Nummer a'},
      ]);
      expect(z.speelFout, 'THUIS is niet bereikbaar');
      z.dispose();
    });

    test('een opdracht die niet aankomt, staat op het scherm', () async {
      final z = ZoneSpeler(
        lijst: _lijst([_pc()]),
        zoneId: 'dev:pc-THUIS',
        nummer: _t,
        idVan: (t) => t.title,
        hoesVan: (_) => null,
        stuur: (op) async => 'De gsm slaapt',
      );
      await z.next();
      expect(z.speelFout, 'De gsm slaapt');
      z.dispose();
    });
  });

  group('GekozenZone', () {
    test('kiezen, bewaren, terug naar dit toestel; een pc zonder zones zet hem terug', () {
      final lijst = _lijst([_pc()]);
      final bewaard = <String>[];
      final g = GekozenZone(
        lijst: lijst,
        bewaar: bewaard.add,
        maak: (id) => ZoneSpeler(
            lijst: lijst, zoneId: id, nummer: _t, idVan: (t) => t.title, hoesVan: (_) => null, stuur: (_) async => null),
      );
      expect(g.opAfstand, isNull);
      g.kies('dev:pc-THUIS');
      expect(g.opAfstand?.zoneId, 'dev:pc-THUIS');
      expect(g.gekozen, 'dev:pc-THUIS');
      g.kies('dev:gsm-1');
      expect(g.opAfstand, isNull);
      expect(bewaard, ['dev:pc-THUIS', '']);

      g.kies('dev:pc-THUIS');
      lijst.vergeet();
      expect(g.opAfstand, isNull, reason: 'een pc van vóór de zones: terug naar dit toestel');
      g.dispose();
    });

    test('bij het openen de laatst gekozen zone, als die nog speelt', () {
      final g = GekozenZone(
        lijst: _lijst([_pc()]),
        laatste: 'dev:pc-THUIS',
        bewaar: (_) {},
        maak: (id) => ZoneSpeler(
            lijst: _lijst([_pc()]), zoneId: id, nummer: _t, idVan: (t) => t.title, hoesVan: (_) => null, stuur: (_) async => null),
      );
      expect(g.opAfstand?.zoneId, 'dev:pc-THUIS');
      g.dispose();
    });
  });

  group('ZoneUitvoerder', () {
    test('elke opdracht op de speler van dit toestel; een herhaalde id maar één keer', () async {
      final s = _NepSpeler();
      var gemeld = 0;
      final u = ZoneUitvoerder(
        speler: s,
        rij: s,
        nummer: (id) => id == 'onbekend' ? null : _t(id),
        radio: (artiest, {zaad, titel, door}) async => s.log.add('radio $artiest ${zaad?.title} $titel'),
        naUitvoeren: () => gemeld++,
      );
      for (final op in <Map<String, dynamic>>[
        {'id': '1', 'cmd': 'pause'},
        {'id': '1', 'cmd': 'pause'},
        {'id': '2', 'cmd': 'play'},
        {'id': '3', 'cmd': 'seek', 'ms': 90000},
        {'id': '4', 'cmd': 'volume', 'waarde': 35},
        {'id': '5', 'cmd': 'shuffle', 'aan': true},
        {'id': '6', 'cmd': 'repeat', 'stand': 'one'},
        {'id': '7', 'cmd': 'next'},
        {'id': '8', 'cmd': 'jump', 'plek': 4},
        {'id': '9', 'cmd': 'speel', 'ids': ['a', 'onbekend', 'c'], 'plek': 2},
        {'id': '10', 'cmd': 'speel', 'ids': ['a', 'c'], 'plek': 0, 'shuffle': true},
        {'id': '11', 'cmd': 'hierna', 'ids': ['c']},
        {'id': '12', 'cmd': 'achteraan', 'ids': ['a']},
        {'id': '13', 'cmd': 'nu', 'id': 'c'},
        {'id': '14', 'cmd': 'radio', 'artiest': 'La Bouche', 'zaad': 'a'},
      ]) {
        await u.voerUit(op);
      }
      expect(s.log, [
        'pauzeer',
        'speelAf',
        'seek 90',
        'volume 35',
        'shuffle true',
        'herhaal one',
        'next',
        'spring 4',
        'playQueue Nummer a,Nummer c @1',
        'shuffleAll Nummer a,Nummer c',
        'hierna Nummer c',
        'achteraan Nummer a',
        'nu Nummer c',
        'radio La Bouche Nummer a null',
      ]);
      expect(gemeld, 14, reason: 'na elke uitgevoerde opdracht meteen melden, de dubbele niet');
      expect(await u.voerUit({'id': '15', 'cmd': 'speel', 'ids': ['onbekend']}), isNotNull);
      expect(await u.voerUit({'id': '16', 'cmd': 'iets'}), contains('Onbekende opdracht'));
    });
  });

  group('de wachtrij van een zone op afstand (stap 2.4)', () {
    test('een venster rond het spelende nummer, en het juiste nummer als de rij verschoof', () {
      final rij = [for (var i = 0; i < 1000; i++) 'n$i'];
      final w = rijVensterUit(rij, 500, voor: 100, na: 400);
      expect(w.van, 400);
      expect(w.rij.first, 'n400');
      expect(w.rij.last, 'n900');
      expect(rijVensterUit(rij, 3).van, 0);
      expect(rijVensterUit(const [], 0).rij, isEmpty);

      expect(plekVoorNummer(['a', 'b', 'c', 'b'], 1, 'b'), 1, reason: 'het staat er nog');
      expect(plekVoorNummer(['x', 'a', 'b', 'c', 'b'], 1, 'b'), 2, reason: 'een plek verschoven: het dichtstbij');
      expect(plekVoorNummer(['a', 'c'], 1, 'b'), -1, reason: 'het staat er niet meer');
      expect(plekVoorNummer(['a', 'c'], 1, ''), 1, reason: 'zonder nummer: de plek');
    });

    test('de ZoneSpeler haalt het venster, en springen, weghalen en verplaatsen tellen het begin mee', () async {
      final gestuurd = <Map<String, dynamic>>[];
      var gehaald = 0;
      final z = ZoneSpeler(
        lijst: _lijst([_pc()]), // index 3, lengte 10
        zoneId: 'dev:pc-THUIS',
        nummer: _t,
        idVan: (t) => t.title,
        hoesVan: (_) => null,
        stuur: (op) async {
          gestuurd.add(op);
          return null;
        },
        haalRij: () async {
          gehaald++;
          return {'index': 3, 'lengte': 10, 'van': 2, 'rij': ['a', 'b', 'c', 'd']};
        },
      );
      expect(z.queueTracks, isEmpty, reason: 'nog niet gehaald');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect([for (final t in z.queueTracks) t.title], ['Nummer a', 'Nummer b', 'Nummer c', 'Nummer d']);
      expect(z.currentIndex, 1, reason: 'plek 3 in de rij, 1 in het venster dat op 2 begint');
      expect(gehaald, 1, reason: 'niet opnieuw zolang de zone niets nieuws meldt');

      await z.springNaar(3);
      expect(gestuurd.last, {'cmd': 'jump', 'plek': 5, 'trackId': 'd'});
      expect(z.haalUitWachtrij(2), isTrue);
      expect([for (final t in z.queueTracks) t.title], ['Nummer a', 'Nummer b', 'Nummer d'], reason: 'meteen weg');
      await Future<void>.delayed(Duration.zero);
      expect(gestuurd.last, {'cmd': 'remove', 'plek': 4, 'trackId': 'c'});
      expect(z.verplaatsInWachtrij(2, 0), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(gestuurd.last, {'cmd': 'move', 'van': 4, 'naar': 2, 'trackId': 'd'});
      z.dispose();
    });

    test('de zone zoekt het nummer zelf op als haar rij intussen verschoof', () async {
      final s = _NepSpeler()..rij = [_t('x'), _t('a'), _t('b'), _t('c')];
      final u = ZoneUitvoerder(speler: s, rij: s, nummer: _t, idVan: (t) => t.title.replaceFirst('Nummer ', ''));
      await u.voerUit({'id': '1', 'cmd': 'jump', 'plek': 1, 'trackId': 'b'});
      await u.voerUit({'id': '2', 'cmd': 'remove', 'plek': 2, 'trackId': 'c'});
      await u.voerUit({'id': '3', 'cmd': 'move', 'van': 0, 'naar': 3, 'trackId': 'a'});
      expect(s.log, ['spring 2', 'weg 3', 'verplaats 1→3']);
      expect(await u.voerUit({'id': '4', 'cmd': 'remove', 'plek': 1, 'trackId': 'weg'}), isNotNull);
    });

    test('overnemen: de stand gaat naar "Hier verder"', () async {
      final s = _NepSpeler();
      final genomen = <Map<String, dynamic>>[];
      final u = ZoneUitvoerder(speler: s, rij: s, nummer: _t, neemOver: (stand) async {
        genomen.add(stand);
        return true;
      });
      expect(await u.voerUit({'id': '1', 'cmd': 'neemOver', 'stand': {'trackId': 'b'}}), isNull);
      expect(genomen.single['trackId'], 'b');
      final zonder = ZoneUitvoerder(speler: s, rij: s, nummer: _t);
      expect(await zonder.voerUit({'id': '2', 'cmd': 'neemOver', 'stand': {'trackId': 'b'}}), isNotNull);
    });

    test('stop: hier pauzeren (de pc zet de zone op "Speelt niets")', () async {
      final s = _NepSpeler();
      final u = ZoneUitvoerder(speler: s, rij: s, nummer: _t);
      expect(await u.voerUit({'id': '1', 'cmd': 'stop'}), isNull);
      expect(s.log, ['pauzeer']);
    });

    test('verplaatst: de muziek speelt nu elders, dus hier stoppen (Saber, 23-10-2026: "A stopt helemaal")', () async {
      final s = _NepSpeler();
      final naar = <String>[];
      final u = ZoneUitvoerder(speler: s, rij: s, nummer: _t, verplaatst: naar.add);
      expect(await u.voerUit({'id': '1', 'cmd': 'verplaatst', 'naar': 'iPad'}), isNull);
      expect(naar, ['iPad']);
      final zonder = ZoneUitvoerder(speler: s, rij: s, nummer: _t);
      expect(await zonder.voerUit({'id': '2', 'cmd': 'verplaatst', 'naar': 'iPad'}), isNotNull);
    });
  });

  group('aangesloten', () {
    String lees(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

    test('de balk en Nu speelt praten met de gekozen zone; de knoppen van dit toestel wijken', () {
      final main = lees('lib/main.dart');
      expect(main, contains('Speelbron get player => afstand ?? lokaal;'));
      expect(main, contains('bool get casting => afstand == null && speaker.isCasting;'));
      expect(main, contains('afstand = _misschien<GekozenZone>(context, luister: true)?.opAfstand;'));
      expect(main, contains('ChangeNotifierProvider<GekozenZone>.value(value: gekozenZone),'));
      // Speakerkeuze en de radioknop gaan over dit toestel: weg bij een zone op afstand. De wachtrijknop niet meer:
      // die toont sinds stap 2.4 de wachtrij van de zone. De radioduimen ook niet meer als op die zone de radio van
      // dit toestel speelt (22-10-2026, een radio van de pc op de KEF) — zie duimen_op_speaker_test. De afsluitknop ook
      // niet meer: de radio van de pc op een speaker sluit je af vanaf elk toestel (23-10-2026, speakerradio_v2_test).
      expect(
          RegExp(r'if \(_misschien<GekozenZone>\(context, luister: true\)\?\.opAfstand != null\) return const SizedBox\.shrink\(\);')
              .allMatches(main)
              .length,
          1);
      expect(main, contains('if (!_radioHier(context)) return const SizedBox.shrink();'));
      expect(main, contains('if (x.afstand case final zone? when zone.heeftVolume)'));
      expect(main, contains('final Speelbron p = _misschien<GekozenZone>(context, luister: true)?.opAfstand ?? lokaal;'),
          reason: 'het wachtrijpaneel toont de wachtrij van de gekozen zone');
      expect(main, contains('final Speelbron p = _misschien<GekozenZone>(context)?.opAfstand ?? context.read<PlayerStore>();'),
          reason: 'een tik in die wachtrij springt daar');
      expect(main, contains('idVan: (t) => library.gedeeldId(t.path),\n    // Een andere zone verplaatst'));
      expect(main, contains('neemOver: verder.neemOverUit,'), reason: 'overdragen naar dit toestel (stap 2.5)');
      expect(main, contains("key: ValueKey('zone-naar-\${zone.id}'),"), reason: '"Verplaats naar …" in het zoneblad');
    });

    test('een tik, een menu, een album en een radio gaan naar de gekozen zone', () {
      final main = lees('lib/main.dart');
      final tik = main.substring(main.indexOf('Future<void> speelGetikt('));
      expect(tik.substring(0, 900), contains('final Rijbediening p = afstand ?? lokaal;'));
      expect(RegExp(r'final p = rijVoor\(context\);').allMatches(main).length, greaterThanOrEqualTo(4),
          reason: 'nummermenu, albummenu, afspeellijst, favorieten');
      expect(main, contains(': () => rijVoor(context).playQueue(a.tracks, 0, cover: a.cover),'));
      final radio = main.substring(main.indexOf('Future<void> startRadio(BuildContext context, String artist,'));
      expect(radio.substring(0, 1200), contains('return afstand.startRadio(artist, zaad: zaad, titel: titel);'));
      expect(main, contains('await startRadio(ctx, radioArtiest, zaad: zaad, hier: true);'),
          reason: 'overnemen start de radio HIER, niet in de gekozen zone');
    });

    test('de pc voert opdrachten voor zijn eigen zone uit; een toestel die over zijn lijn', () {
      final main = lees('lib/main.dart');
      expect(main, contains('s.bijZoneOpdracht = zoneUitvoerder.voerUit;'));
      expect(main, contains('opOpdracht: (op) => unawaited(zoneUitvoerder.voerUit(op)),'));
      expect(main, contains("'volume': player.volume.round(),"));
      expect(main, contains('volume: player.volume.round(),\n          alleenZone: m.alleenZone);'));
      expect(main, contains("if (m.alleenZone) 'alleenZone': true,"));
      expect(main, contains('verplaatst: (_) => verder.isVerplaatst(),'));
      expect(lees('lib/settings.dart'), contains("'gekozen_zone': gekozenZone,"));
    });
  });

  group('over de lijn', () {
    late Directory map;
    late LanServer server;
    late RemoteClient c;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_zone_cmd_');
      server = LanServer(
        library: LibraryStore()..rootPath = map.path,
        token: 'sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
      );
      expect(await server.start(), isNull);
      c = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:${server.boundPort}'), token: 'sleutel'));
    });

    tearDown(() async {
      c.close();
      await server.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      map.deleteSync(recursive: true);
    });

    test('een opdracht voor de gsm komt over zijn lijn aan; zonder lijn: 409 met de reden', () async {
      final events = <SseEvent>[];
      final sub = c.zoneStroom(toestel: 'gsm-1', naam: 'Galaxy').listen(events.add);
      for (var i = 0; i < 50 && server.zones.bereikbareToestellen().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final antwoord = await c.ask('/api/zone/cmd', {'zone': 'dev:gsm-1', 'id': 'x1', 'cmd': 'pause'});
      expect(antwoord['bezorgd'], 1);
      for (var i = 0; i < 50 && !events.any((e) => e.event == 'cmd'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final cmd = jsonDecode(events.firstWhere((e) => e.event == 'cmd').data) as Map<String, dynamic>;
      expect(cmd['cmd'], 'pause');
      expect(cmd['id'], 'x1');
      await sub.cancel();

      await expectLater(
        c.ask('/api/zone/cmd', {'zone': 'dev:ipad-1', 'cmd': 'play'}),
        throwsA(isA<RemoteException>().having((e) => e.statusCode, 'status', 409)),
      );
    });

    test('overdragen (stap 2.5): het doel krijgt de hele stand van de bron; niets op de bron = 409', () async {
      // De iPad speelt iets (zijn melding staat op de pc); de gsm heeft een lijn open.
      await c.ask('/api/state/ops', {
        'ops': [
          {
            'type': 'progress',
            'trackId': 't2',
            'positionMs': 61000,
            'queue': ['t1', 't2', 't3'],
            'index': 1,
            'playing': true,
            'shuffle': true,
            'repeat': 'all',
            'at': DateTime.now().millisecondsSinceEpoch,
          }
        ],
        'deviceId': 'ipad-1',
        'deviceName': 'iPad',
      });
      final events = <SseEvent>[];
      final sub = c.zoneStroom(toestel: 'gsm-1', naam: 'Galaxy').listen(events.add);
      for (var i = 0; i < 50 && server.zones.bereikbareToestellen().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect((await c.ask('/api/zone/transfer', {'van': 'dev:ipad-1', 'naar': 'dev:gsm-1'}))['bezorgd'], 1);
      for (var i = 0; i < 50 && !events.any((e) => e.event == 'cmd'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final cmd = jsonDecode(events.firstWhere((e) => e.event == 'cmd').data) as Map<String, dynamic>;
      expect(cmd['cmd'], 'neemOver');
      final stand = (cmd['stand'] as Map).cast<String, dynamic>();
      expect(stand['queue'], ['t1', 't2', 't3']);
      expect(stand['index'], 1);
      expect(stand['shuffle'], isTrue);
      expect(stand['deviceId'], 'ipad-1', reason: 'zodat de iPad zichzelf ziet en pauzeert');
      await sub.cancel();

      await expectLater(
        c.ask('/api/zone/transfer', {'van': 'dev:gsm-1', 'naar': 'dev:ipad-1'}),
        throwsA(isA<RemoteException>().having((e) => e.statusCode, 'status', 409)),
        reason: 'op de gsm speelt niets',
      );
    });

    test('de stand van een speaker als melding, met de plek van nu', () {
      final s = speakerAlsStand(
        (id: 'uuid:amp', naam: 'Amp', trackId: 'x', index: 2, lengte: 5, speelt: true, positieMs: 10000, duurMs: 200000, opMs: 1000, volume: 30, radio: ''),
        ['a', 'b', 'x', 'c', 'd'],
        nuMs: 6000,
      );
      expect(s['positionMs'], 15000);
      expect(s['queue'], ['a', 'b', 'x', 'c', 'd']);
      expect(s['deviceId'], 'spk:uuid:amp');
    });

    test('een opdracht voor de pc zelf gaat naar zijn eigen speler', () async {
      final gekregen = <Map<String, dynamic>>[];
      server.bijZoneOpdracht = (op) async {
        gekregen.add(op);
        return null;
      };
      final pc = server.zones.lijst().first.id;
      expect((await c.ask('/api/zone/cmd', {'zone': pc, 'cmd': 'next'}))['bezorgd'], 1);
      expect(gekregen.single['cmd'], 'next');
    });
  });
}

/// Een speler die alleen opschrijft wat er gevraagd werd.
class _NepSpeler implements Speelbron, Rijbediening {
  final log = <String>[];

  @override
  void speelAf() => log.add('speelAf');
  @override
  void pauzeer() => log.add('pauzeer');
  @override
  Future<void> next() async => log.add('next');
  @override
  Future<void> prev() async => log.add('prev');
  @override
  void seek(Duration d) => log.add('seek ${d.inSeconds}');
  @override
  void setVolume(double v) => log.add('volume ${v.round()}');
  @override
  void zetShuffle(bool aan) => log.add('shuffle $aan');
  @override
  void zetHerhaal(RepeatMode m) => log.add('herhaal ${m.name}');
  @override
  Future<void> springNaar(int plek) async => log.add('spring $plek');
  @override
  Future<void> playQueue(List<Track> queue, int index, {Object? cover}) async =>
      log.add('playQueue ${queue.map((t) => t.title).join(',')} @$index');
  @override
  Future<void> shuffleAll(List<Track> tracks) async => log.add('shuffleAll ${tracks.map((t) => t.title).join(',')}');
  @override
  void speelHierna(List<Track> nummers) => log.add('hierna ${nummers.map((t) => t.title).join(',')}');
  @override
  void zetAchteraan(List<Track> nummers) => log.add('achteraan ${nummers.map((t) => t.title).join(',')}');
  @override
  Future<void> speelNuMetRest(Track t) async => log.add('nu ${t.title}');

  List<Track> rij = const [];
  @override
  List<Track> get queueTracks => rij;
  @override
  bool haalUitWachtrij(int plek) {
    log.add('weg $plek');
    return true;
  }

  @override
  bool verplaatsInWachtrij(int van, int naar) {
    log.add('verplaats $van→$naar');
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
