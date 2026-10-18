/// "Verder op …" in de spelerbalk (Saber, 18-10-2026: de balk boven de inhoud stoorde, en na ✕ was hij
/// niet meer te vinden).
library;

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart' show VerderKnop;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart' show RepeatMode;
import 'package:debridmusic/verder_luisteren.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Track _t(String id) => Track(path: 'http://pc.invalid/stream/$id.flac', title: 'Nummer $id', artist: 'X', album: 'A');

final _bib = {for (final id in ['a', 'b']) id: _t(id)};

class _Bron implements VerderBron {
  int overgenomen = 0;

  @override
  String get mijnId => 'shield-1';

  @override
  bool get ikSpeel => false;

  @override
  Track? nummer(String id) => _bib[id];

  @override
  Future<({Map<String, dynamic>? stand, Map<String, dynamic>? verzoek})?> haal() async => null;

  @override
  Future<void> speel(List<Track> rij, int index, Duration positie,
      {bool spelen = true, bool shuffle = false, RepeatMode herhaal = RepeatMode.off, String? radioArtiest}) async {
    overgenomen++;
  }

  @override
  Future<void> pauzeer() async {}
}

Map<String, dynamic> _stand() => {
      'trackId': 'b',
      'positionMs': 131000,
      'queue': ['a', 'b'],
      'index': 1,
      'playing': false,
      'updatedAt': 1000000,
      'deviceId': 'gsm-S26',
      'deviceName': 'Saber ultra 26',
      'shuffle': false,
      'repeat': 'off',
    };

/// Zoals in de app: de providers boven MaterialApp, zodat ook een blad ze ziet.
Widget _app(VerderLuisteren v, {required bool smal}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<VerderLuisteren>.value(value: v),
      ],
      child: MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 280, child: VerderKnop(smal: smal)))),
      ),
    );

void main() {
  testWidgets('breed: het toestel en het nummer, één klik neemt over, en dan is hij weg', (t) async {
    final bron = _Bron();
    final v = VerderLuisteren(bron, klok: () => 1005000);
    await t.pumpWidget(_app(v, smal: false));
    expect(find.byKey(const ValueKey('verder-knop')), findsNothing, reason: 'zonder aanbod niets');

    await v.opStand(_stand());
    await t.pumpAndSettle();
    expect(find.text('Verder op Saber ultra 26'), findsOneWidget);
    expect(find.textContaining('Nummer b'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('verder-knop')));
    await t.pumpAndSettle();
    expect(bron.overgenomen, 1);
    expect(find.byKey(const ValueKey('verder-knop')), findsNothing);
  });

  testWidgets('smal: een icoon; tikken toont het aanbod als blad, en het blad gaat dicht na overnemen', (t) async {
    final bron = _Bron();
    final v = VerderLuisteren(bron, klok: () => 1005000);
    await v.opStand(_stand());
    await t.pumpWidget(_app(v, smal: true));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.devices_rounded), findsOneWidget);
    expect(find.textContaining('Nummer b'), findsNothing, reason: 'op de telefoon neemt hij geen ruimte in');
    await t.tap(find.byIcon(Icons.devices_rounded));
    await t.pumpAndSettle();
    expect(find.textContaining('Nummer b'), findsOneWidget, reason: 'het blad met het aanbod');
    await t.tap(find.byKey(const ValueKey('verder-knop')));
    await t.pumpAndSettle();
    expect(bron.overgenomen, 1);
    expect(find.textContaining('Nummer b'), findsNothing, reason: 'het blad ging vanzelf dicht');
  });
}
