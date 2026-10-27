/// Het vergrendelscherm en de volumeknoppen van de gsm voor de gekozen zone (stap 2.6, Saber 21-10-2026:
/// "wat de gsm zelf speelt gaat voor; pas als hij zelf niets speelt, de gekozen zone").
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/now_playing.dart';
import 'package:debridmusic/player.dart' show NowPlayingSource, RepeatMode;
import 'package:debridmusic/volgbron.dart';
import 'package:debridmusic/zone_lijst.dart';
import 'package:debridmusic/zone_speler.dart';

class _Lokaal extends ChangeNotifier implements NowPlayingSource {
  @override
  Track? current;
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(seconds: 200);
  @override
  Uint8List? currentCover;
  @override
  bool shuffle = false;
  @override
  RepeatMode repeat = RepeatMode.off;
  bool gedempt = false;
  final log = <String>[];

  @override
  void zetShuffle(bool aan) => shuffle = aan;
  @override
  void zetHerhaal(RepeatMode m) => repeat = m;
  @override
  void zetDemping(bool aan) => gedempt = aan;
  @override
  void playPause() => log.add('playPause');
  @override
  void speelAf() => log.add('speelAf');
  @override
  void pauzeer() => log.add('pauzeer');
  @override
  bool get speeltErgens => playing;
  @override
  Duration get positieErgens => position;
  @override
  Duration get duurErgens => duration;
  @override
  Future<void> next() async => log.add('next');
  @override
  Future<void> prev() async => log.add('prev');
  @override
  void seek(Duration d) => log.add('seek');
}

Track _t(String id) => Track(path: 'http://pc.invalid/stream/$id.flac', title: 'Nummer $id', artist: 'X', album: 'A');

void main() {
  test('wie het vergrendelscherm krijgt', () {
    expect(volgAfstand(lokaalSpeelt: false, afstandGekozen: true), isTrue);
    expect(volgAfstand(lokaalSpeelt: true, afstandGekozen: true), isFalse, reason: 'wat de gsm zelf speelt gaat voor');
    expect(volgAfstand(lokaalSpeelt: false, afstandGekozen: false), isFalse);
  });

  group('Volgbron en de handler', () {
    late _Lokaal lokaal;
    late ZoneLijst lijst;
    late GekozenZone gekozen;
    late Volgbron volg;
    late List<Map<String, dynamic>> gestuurd;

    setUp(() {
      lokaal = _Lokaal();
      gestuurd = [];
      lijst = ZoneLijst(hier: 'dev:gsm-1', klok: () => 1000000)
        ..zet({
          'nu': 1000000,
          'zones': [
            const ZoneStaat(
              id: 'dev:pc-THUIS',
              soort: ZoneSoort.pc,
              naam: 'THUIS',
              online: true,
              playing: true,
              trackId: 'b',
              positionMs: 1000,
              durationMs: 200000,
              opMs: 1000000,
              index: 0,
              lengte: 3,
              volume: 70,
            ).toJson(),
          ],
        });
      gekozen = GekozenZone(
        lijst: lijst,
        bewaar: (_) {},
        maak: (id) => ZoneSpeler(
          lijst: lijst,
          zoneId: id,
          nummer: _t,
          idVan: (t) => t.title,
          hoesVan: (_) => null,
          stuur: (op) async {
            gestuurd.add(op);
            return null;
          },
        ),
      );
      volg = Volgbron(lokaal: lokaal, gekozen: gekozen);
    });

    tearDown(() {
      volg.dispose();
      gekozen.dispose();
    });

    test('de gsm speelt niets en de pc is gekozen: het vergrendelscherm is de pc', () async {
      expect(volg.current, isNull, reason: 'nog niets gekozen: dit toestel');
      gekozen.kies('dev:pc-THUIS');
      expect(volg.current?.title, 'Nummer b');
      expect(volg.afstandsvolume, 70);
      volg.pauzeer();
      await Future<void>.delayed(Duration.zero);
      expect(gestuurd.single, {'cmd': 'pause'});
      expect(lokaal.log, isEmpty, reason: 'de gsm zelf blijft ongemoeid');

      volg.zetDemping(true);
      expect(lokaal.gedempt, isTrue, reason: 'een navigatiestem gaat over wat HIER klinkt');
    });

    test('in de achtergrond begint de zone te spelen door een ander toestel: eerst nog "gepauzeerd"', () {
      var voor = false;
      var nu = 1000000;
      final v = Volgbron(lokaal: lokaal, gekozen: gekozen, opVoorgrond: () => voor, klok: () => nu);
      gekozen.kies('dev:pc-THUIS'); // de pc speelt al, maar de gsm toonde nog niets
      expect(v.speeltErgens, isFalse,
          reason: 'de mediadienst mag nu niet vanuit de achtergrond starten (Android 12+)');
      v.speelAf(); // een druk van hier, op het vergrendelscherm
      expect(v.speeltErgens, isTrue, reason: 'na een eigen druk mag het wel');
      // De pc bevestigt dat hij speelt.
      lijst.zet({
        'nu': nu,
        'zones': [
          ZoneStaat(id: 'dev:pc-THUIS', soort: ZoneSoort.pc, naam: 'THUIS', online: true, playing: true, trackId: 'b', opMs: nu)
              .toJson()
        ],
      });
      nu += 60000;
      expect(v.speeltErgens, isTrue, reason: 'de dienst draait al: gewoon blijven spelen');
      // Pauze op afstand, en later play van een ander toestel, in de achtergrond.
      lijst.zet({
        'nu': nu,
        'zones': [
          ZoneStaat(id: 'dev:pc-THUIS', soort: ZoneSoort.pc, naam: 'THUIS', online: true, trackId: 'b', opMs: nu)
              .toJson()
        ],
      });
      nu += 4000;
      expect(v.speeltErgens, isFalse);
      lijst.zet({
        'nu': nu,
        'zones': [
          ZoneStaat(id: 'dev:pc-THUIS', soort: ZoneSoort.pc, naam: 'THUIS', online: true, playing: true, trackId: 'b', opMs: nu)
              .toJson()
        ],
      });
      nu += 20000;
      expect(v.speeltErgens, isFalse, reason: 'de dienst lag stil en niemand hier drukte');
      voor = true;
      expect(v.speeltErgens, isTrue, reason: 'de app in beeld: nu wel');
      v.dispose();
    });

    test('speelt de gsm zelf, dan is hij het weer', () {
      gekozen.kies('dev:pc-THUIS');
      lokaal
        ..current = _t('eigen')
        ..playing = true
        ..notifyListeners();
      expect(volg.current?.title, 'Nummer eigen');
      expect(volg.afstandsvolume, isNull, reason: 'de volumeknoppen gaan weer naar de gsm');
    });

    test('de volumeknoppen regelen de zone, één stap per druk (Saber, 27-10-2026)', () async {
      gekozen.kies('dev:pc-THUIS');
      final h = NowPlayingHandler(volg, null);
      final info = h.androidPlaybackInfo.value;
      expect(info, isA<RemoteAndroidPlaybackInfo>());
      expect((info as RemoteAndroidPlaybackInfo).volume, 70);
      await h.androidAdjustRemoteVolume(AndroidVolumeDirection.raise);
      await Future<void>.delayed(Duration.zero);
      expect(gestuurd.last, {'cmd': 'volume', 'waarde': 71});
      await h.androidSetRemoteVolume(30);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(gestuurd.last, {'cmd': 'volume', 'waarde': 30});

      // De gsm begint zelf te spelen: zijn eigen volume weer.
      lokaal
        ..current = _t('eigen')
        ..playing = true
        ..notifyListeners();
      expect(h.androidPlaybackInfo.value, isA<LocalAndroidPlaybackInfo>());
      unawaited(h.stop());
    });
  });
}
