/// "Speelt op: … ▾" en het blad met de zones (Saber, 21-10-2026). Deelstap 2.1: zien wat er overal
/// speelt, en hier verder luisteren vanaf elke zone.
library;

import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart' show ZoneKiesKnop;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart' show RepeatMode;
import 'package:debridmusic/verder_luisteren.dart';
import 'package:debridmusic/zone_lijst.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Bron implements VerderBron {
  final gespeeld = <String>[];

  @override
  String get mijnId => 'gsm-1';

  @override
  bool get ikSpeel => false;

  @override
  Track? nummer(String id) =>
      Track(path: 'http://pc.invalid/stream/$id.flac', title: 'Nummer $id', artist: 'X', album: 'A');

  @override
  Future<({Map<String, dynamic>? stand, Map<String, dynamic>? verzoek})?> haal() async => null;

  @override
  Future<void> speel(List<Track> rij, int index, Duration positie,
      {required bool spelen, required bool shuffle, required RepeatMode herhaal, String? radioArtiest}) async {
    gespeeld.add('${rij[index].title}@${positie.inSeconds}');
  }

  @override
  void pauzeer() {}
}

const _nu = 1000000;

Map<String, dynamic> _lijst({bool pcSpeelt = true}) => {
      'nu': _nu,
      'zones': [
        const ZoneStaat(id: 'dev:gsm-1', soort: ZoneSoort.gsm, naam: 'Galaxy', online: true).toJson(),
        ZoneStaat(
          id: 'dev:pc-THUIS',
          soort: ZoneSoort.pc,
          naam: 'THUIS',
          online: true,
          playing: pcSpeelt,
          trackId: 'b',
          titel: 'Be My Lover',
          artiest: 'La Bouche',
          positionMs: 60000,
          durationMs: 240000,
          opMs: _nu - 5000,
        ).toJson(),
        const ZoneStaat(id: 'dev:ipad-1', soort: ZoneSoort.tablet, naam: 'iPad').toJson(),
      ],
    };

Widget _app(ZoneLijst lijst, VerderLuisteren v) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<VerderLuisteren>.value(value: v),
        ChangeNotifierProvider<ZoneLijst>.value(value: lijst),
      ],
      child: const MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 360, child: ZoneKiesKnop())))),
    );

void main() {
  testWidgets('een pc zonder zones: geen knop', (t) async {
    final v = VerderLuisteren(_Bron(), klok: () => _nu);
    await t.pumpWidget(_app(ZoneLijst(hier: 'dev:gsm-1', klok: () => _nu), v));
    expect(find.byKey(const ValueKey('zone-kies')), findsNothing);
  });

  testWidgets('"Speelt op: dit toestel", het blad toont elke zone, en "Hier verder" neemt over', (t) async {
    final bron = _Bron();
    final v = VerderLuisteren(bron, klok: () => _nu);
    final lijst = ZoneLijst(hier: 'dev:gsm-1', klok: () => _nu)..zet(_lijst());
    final gevraagd = <String>[];
    lijst.haalStand = (zone) async {
      gevraagd.add(zone);
      return {
        'trackId': 'b',
        'positionMs': 60000,
        'queue': ['a', 'b'],
        'index': 1,
        'playing': true,
        'updatedAt': _nu - 5000,
        'deviceId': 'pc-THUIS',
        'deviceName': 'THUIS',
      };
    };
    await t.pumpWidget(_app(lijst, v));
    expect(find.text('Speelt op: Galaxy'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('zone-kies')));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Galaxy · dit toestel'), findsOneWidget);
    expect(find.text('Speelt niets'), findsOneWidget);
    expect(find.text('Nummer b — X'), findsOneWidget, reason: 'het nummer zoals dit toestel het kent');
    expect(find.textContaining('Speelt · 1:05 / 4:00'), findsOneWidget, reason: 'de plek schuift op sinds de melding');
    expect(find.text('Niet bereikbaar'), findsOneWidget, reason: 'de iPad is er niet');
    expect(find.text('Hier verder'), findsOneWidget, reason: 'alleen bij een ander toestel dat iets speelt');

    await t.tap(find.text('Hier verder'));
    await t.pump(const Duration(milliseconds: 400));
    expect(gevraagd, ['dev:pc-THUIS']);
    expect(bron.gespeeld, ['Nummer b@65']);
    await t.pump(const Duration(seconds: 1));
  });
}
