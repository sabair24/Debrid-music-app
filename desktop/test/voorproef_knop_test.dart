// De voorproefknop (Saber, 23-11-2026): tik = 30 s horen (een fragment als er een is, anders Soulseek), nog eens =
// stoppen; ⬇ naast een lopende Soulseek-proef laat dezelfde download doorgaan.
import 'dart:async';
import 'dart:io';

import 'package:debridmusic/models.dart' show Track;
import 'package:debridmusic/radio.dart' show Radioplek;
import 'package:debridmusic/ui/voorproef_knop.dart';
import 'package:debridmusic/voorproef.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

void main() {
  late String? klinkt;
  late List<String> gespeeld;
  late Completer<Track?> landing;
  late int gestopt;

  Voorproef maak() {
    klinkt = null;
    gespeeld = [];
    landing = Completer<Track?>();
    gestopt = 0;
    return Voorproef(
      speel: (adres, sleutel, duur) async {
        klinkt = sleutel;
        gespeeld.add(adres);
        return true;
      },
      stopSpeler: (s) async => klinkt = null,
      klinktNog: (s) => klinkt == s,
      vergeet: (_) async {},
      wacht: const Duration(milliseconds: 10),
      haal: (plek, {alleen, required klinkt, required bijStop}) async {
        bijStop(() => gestopt++);
        klinkt('http://127.0.0.1/groei/1.flac');
        return landing.future;
      },
    );
  }

  Widget app(Voorproef v, Widget kind) => ChangeNotifierProvider<Voorproef>.value(
      value: v, child: MaterialApp(home: Scaffold(body: Center(child: kind))));

  testWidgets('DE KERN: met een fragment speelt hij dat (niets gedownload); nog eens tikken stopt', (tester) async {
    final v = maak();
    await tester.pumpWidget(app(v, const VoorproefKnop(sleutel: 'a', fragment: 'https://deezer/p.mp3')));
    expect(find.byIcon(Icons.hearing_rounded), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(gespeeld, ['https://deezer/p.mp3']);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(klinkt, isNull);
    expect(find.byIcon(Icons.hearing_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('zonder fragment een Soulseek-proef; ⬇ ernaast houdt hem in plaats van opnieuw te beginnen', (tester) async {
    final v = maak();
    var opnieuw = 0;
    await tester.pumpWidget(app(
        v,
        Builder(
            builder: (context) => Row(mainAxisSize: MainAxisSize.min, children: [
                  VoorproefKnop(sleutel: 'b', plek: Radioplek(artiest: 'Michael Jackson', titel: 'Jam')),
                  TextButton(
                      onPressed: () {
                        if (!houdLopendeProef(context, 'b')) opnieuw++;
                      },
                      child: const Text('⬇')),
                ]))));
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(gespeeld, ['http://127.0.0.1/groei/1.flac']);
    await tester.tap(find.text('⬇'));
    await tester.pump();
    expect(opnieuw, 0, reason: 'dezelfde download gaat door');
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    expect(gestopt, 0);
    landing.complete(null);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await v.stop('b');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('zonder fragment en zonder plek: geen knop', (tester) async {
    await tester.pumpWidget(app(maak(), const VoorproefKnop(sleutel: 'c')));
    expect(find.byType(IconButton), findsNothing);
  });

  test('aangesloten: bij zoekresultaten en bij elke FLAC-bron met artiest en titel, en ⬇ houdt de proef', () {
    final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(m, contains("                      sleutel: 'zoek:\${_zoekSleutel(t)}',\n                      fragment: t.preview,"));
    expect(m, contains("                    if (houdLopendeProef(context, 'zoek:\${_zoekSleutel(t)}')) return;"));
    expect(m, contains('        if (f.isFlac && authority != null && authority.artist.trim().isNotEmpty && authority.title.trim().isNotEmpty)'));
    expect(m, contains("          if (houdLopendeProef(context, 'bron:\${_slskKey(f)}')) return;"));
    expect(m, contains('        ChangeNotifierProvider<Voorproef>.value(value: voorproef),'));
    final c = File('lib/catalog.dart').readAsStringSync();
    expect(RegExp(r"preview: t\['preview'\] is String").allMatches(c).length, 2, reason: 'beide zoekpaden van Deezer');
  });
}
