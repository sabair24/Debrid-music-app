// Berichten van uploaders tonen en zelf beantwoorden (Saber, 25-10-2026: "ja bouw maar berichten tonen en antwoorden").
// De teksten hieronder komen uit zijn schermafdrukken van SoulseekQt (thisisphyne, messiestgaze, paradox1977).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/lan/server.dart' show weigerVanBuiten;
import 'package:debridmusic/soulseek.dart' show bevestigPrivebericht, leesPrivebericht, priveberichtAan;
import 'package:debridmusic/ui/berichten_scherm.dart';
import 'package:debridmusic/uploaderberichten.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
Uint8List _str(String s) {
  final b = utf8.encode(s);
  return Uint8List.fromList([..._u32(b.length), ...b]);
}

const _proveIt = 'ProveIt: To prove you are a human downloading these files, please type "download" in this chat to be '
    'added to my whitelist.';

Uploaderbericht _b(String van, String tekst, {int id = 1, int ms = 1000, bool mij = false}) =>
    Uploaderbericht(id: id, ms: ms, uploader: van, tekst: tekst, vanMij: mij);

void main() {
  group('het protocol', () {
    test('DE KERN: een privébericht van de server lezen, en het nummer bevestigen', () {
      final naCode = Uint8List.fromList(
          [..._u32(7), ..._u32(1761410359), ..._str('thisisphyne'), ..._str(_proveIt), 1]);
      final b = leesPrivebericht(naCode)!;
      expect(b.id, 7);
      expect(b.van, 'thisisphyne');
      expect(b.tekst, _proveIt);
      expect(b.op, DateTime.fromMillisecondsSinceEpoch(1761410359 * 1000));
      // MessageAcked: lengte 8, code 23, het nummer.
      expect(bevestigPrivebericht(7), [8, 0, 0, 0, 23, 0, 0, 0, 7, 0, 0, 0]);
    });

    test('een antwoord is code 22 met ontvanger en tekst', () {
      expect(priveberichtAan('paradox1977', 'BEST'),
          [...[4 + 4 + 11 + 4 + 4], 0, 0, 0, 22, 0, 0, 0, ..._str('paradox1977'), ..._str('BEST')]);
    });

    test('te kort of zonder afzender: niets', () {
      expect(leesPrivebericht(Uint8List(8)), isNull);
      expect(leesPrivebericht(Uint8List.fromList([..._u32(1), ..._u32(2), ..._str(''), ..._str('x')])), isNull);
    });
  });

  group('de lijst', () {
    test('DE KERN: wat de server na een login opnieuw bezorgt, staat er één keer', () {
      final l = Uploaderberichten();
      expect(l.voegToe(_b('thisisphyne', _proveIt, id: 7)), isTrue);
      expect(l.voegToe(_b('thisisphyne', _proveIt, id: 7)), isFalse, reason: 'zelfde afzender, zelfde nummer');
      expect(l.voegToe(_b('thisisphyne', _proveIt, id: 9, ms: 5000)), isTrue, reason: 'een tweede vraag');
      expect(l.alle, hasLength(2));
    });

    test('ongelezen per gesprek, het laatst bijgewerkte bovenaan, en gelezen als het openstaat', () {
      final l = Uploaderberichten()
        ..voegToe(_b('thisisphyne', _proveIt, id: 1, ms: 1000))
        ..voegToe(_b('messiestgaze', 'type the word between these brackets: [ messy ]', id: 2, ms: 3000))
        ..voegToe(_b('thisisphyne', _proveIt, id: 3, ms: 2000));
      expect(l.ongelezen, 3);
      expect([for (final g in l.gesprekken) g.uploader], ['messiestgaze', 'thisisphyne']);
      expect(l.gesprekken.last.ongelezen, 2);
      l.gelezen('thisisphyne');
      expect(l.ongelezen, 1);
      expect(l.ongelezenVan('thisisphyne'), 0);
      l.voegToe(_b('thisisphyne', 'download', id: 0, ms: 4000, mij: true));
      expect(l.ongelezenVan('thisisphyne'), 0, reason: 'jouw eigen antwoord is nooit ongelezen');
    });

    test('alleen een uploader meldt zich, en hoogstens kBerichtenBewaard', () {
      final l = Uploaderberichten();
      l.voegToe(_b('x', 'download', mij: true, id: 0));
      expect(l.nieuw.value, isNull);
      l.voegToe(_b('x', 'vraag', id: 5, ms: 2000));
      expect(l.nieuw.value?.tekst, 'vraag');
      for (var i = 0; i < kBerichtenBewaard + 10; i++) {
        l.voegToe(_b('veel', 'm$i', id: 100 + i, ms: 10000 + i), melden: false);
      }
      expect(l.alle, hasLength(kBerichtenBewaard));
      expect(l.alle.first.tekst, 'm10', reason: 'de oudste gaan eerst');
    });

    test('bewaren en inlezen, ook wat je las', () async {
      final map = Directory.systemTemp.createTempSync('dm_berichten_');
      addTearDown(() => map.deleteSync(recursive: true));
      final f = File('${map.path}/soulseek_berichten.json');
      final l = Uploaderberichten(bestand: f)
        ..voegToe(_b('paradox1977', 'Reply only with this word: BEST.', id: 4, ms: 1000))
        ..gelezen('paradox1977');
      await l.bewaarNu();
      final terug = Uploaderberichten(bestand: f);
      await terug.laad();
      expect(terug.alle.single.tekst, 'Reply only with this word: BEST.');
      expect(terug.ongelezen, 0);
    });
  });

  group('een toestel', () {
    test('DE KERN: dezelfde versie = geen lijst; een nieuwe versie = de lijst, en alleen nieuwe berichten melden zich', () {
      final pc = Uploaderberichten()..voegToe(_b('thisisphyne', _proveIt, id: 7, ms: 1000));
      final toestel = Uploaderberichten();
      final v1 = berichtenVanPc(jsonDecode(jsonEncode(pc.voorToestel(null))), eerste: true, lijst: toestel);
      expect(toestel.alle, hasLength(1));
      expect(toestel.nieuw.value, isNull, reason: 'de eerste lading meldt zich niet bericht voor bericht');
      expect(pc.voorToestel(v1).containsKey('berichten'), isFalse, reason: 'om de 15 s: alleen de versie');
      // Een vraag van vrijdag die de server zondag opnieuw bezorgt: een OUDE tijd, toch komt hij aan.
      pc.voegToe(_b('messiestgaze', '[ messy ]', id: 8, ms: 10));
      final v2 = berichtenVanPc(jsonDecode(jsonEncode(pc.voorToestel(v1))), eerste: false, lijst: toestel);
      expect(v2, isNot(v1));
      expect(toestel.alle, hasLength(2));
      expect(toestel.nieuw.value?.uploader, 'messiestgaze');
    });

    test('een pc die opnieuw startte noemt nooit een oude versie', () async {
      final eerder = Uploaderberichten().versie;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(Uploaderberichten().versie, isNot(eerder));
    });
  });

  group('antwoorden', () {
    test('DE KERN: verstuurd = in het gesprek, als jij; niet verstuurd = niets', () async {
      final l = Uploaderberichten()..voegToe(_b('paradox1977', 'Reply only with this word: BEST.', id: 4));
      final gestuurd = <String>[];
      final b = await verstuurAntwoord((aan, t) async {
        gestuurd.add('$aan:$t');
        return true;
      }, 'paradox1977', '  BEST \n', lijst: l);
      expect(gestuurd, ['paradox1977:BEST']);
      expect(b!.vanMij, isTrue);
      expect(l.gesprek('paradox1977').last.tekst, 'BEST');
      expect(l.ongelezen, 0, reason: 'wie antwoordt, heeft gelezen');
      expect(await verstuurAntwoord((_, __) async => false, 'paradox1977', 'BEST', lijst: l), isNull);
      expect(l.gesprek('paradox1977'), hasLength(2));
    });

    test('leeg wordt niet verstuurd; één regel, en niet eindeloos lang', () async {
      var geroepen = false;
      expect(await verstuurAntwoord((_, __) async => geroepen = true, 'x', '   ', lijst: Uploaderberichten()), isNull);
      expect(geroepen, isFalse);
      expect(antwoordVoorUploader(' mes\nsy '), 'mes sy');
      expect(antwoordVoorUploader('a' * 900)!.length, kAntwoordHoogstens);
    });

    test('ook van buiten (Tailscale): het antwoord gaat langs de pc', () {
      expect(weigerVanBuiten('/api/soulseek/berichten', 'POST'), isNull);
      expect(weigerVanBuiten('/api/soulseek/bericht', 'POST'), isNull);
    });
  });

  group('het scherm', () {
    testWidgets('DE KERN: de gesprekken, een gesprek openen, en jouw antwoord versturen', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final l = Uploaderberichten()
        ..voegToe(_b('thisisphyne', _proveIt, id: 7, ms: DateTime.now().millisecondsSinceEpoch));
      final verstuurd = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: BerichtenScherm(
              lijst: l,
              verstuur: (aan, t) async {
                verstuurd.add('$aan:$t');
                l.voegToe(_b(aan, t, id: 0, ms: DateTime.now().millisecondsSinceEpoch, mij: true));
                return null;
              })));
      expect(find.text('thisisphyne'), findsOneWidget);
      expect(find.text('1'), findsOneWidget, reason: 'één ongelezen');
      await tester.tap(find.byKey(const ValueKey('gesprek-thisisphyne')));
      await tester.pumpAndSettle();
      expect(find.text(_proveIt), findsOneWidget);
      expect(l.ongelezen, 0, reason: 'open = gelezen');
      await tester.enterText(find.byKey(const ValueKey('antwoord-veld')), 'download');
      await tester.tap(find.byKey(const ValueKey('antwoord-stuur')));
      await tester.pumpAndSettle();
      expect(verstuurd, ['thisisphyne:download']);
      expect(find.text('download'), findsOneWidget, reason: 'als ballon van jou, het vak is weer leeg');
    });

    testWidgets('lukt het niet, dan staat erbij waarom, en blijft je tekst staan', (tester) async {
      final l = Uploaderberichten()..voegToe(_b('paradox1977', 'BEST?', id: 4));
      await tester.pumpWidget(MaterialApp(
          home: GesprekScherm(
              uploader: 'paradox1977', lijst: l, verstuur: (_, __) async => 'De pc is nu niet ingelogd.')));
      await tester.enterText(find.byKey(const ValueKey('antwoord-veld')), 'BEST');
      await tester.tap(find.byKey(const ValueKey('antwoord-stuur')));
      await tester.pumpAndSettle();
      expect(find.text('De pc is nu niet ingelogd.'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('antwoord-veld'))).controller!.text, 'BEST');
    });

    test('de tijd zoals SoulseekQt: dag en uur deze week, anders de datum', () {
      final nu = DateTime(2026, 10, 25, 19, 0); // een zondag
      expect(berichtTijd(DateTime(2026, 10, 25, 18, 39).millisecondsSinceEpoch, nu: nu), 'zo 18:39');
      expect(berichtTijd(DateTime(2026, 10, 23, 9, 37).millisecondsSinceEpoch, nu: nu), 'vr 09:37');
      expect(berichtTijd(DateTime(2026, 10, 12, 8, 5).millisecondsSinceEpoch, nu: nu), '12-10 08:05');
    });
  });

  test('aangesloten: de pc bevestigt en geeft door, toestellen halen op, en het scherm is te vinden', () {
    final s = _bron('lib/soulseek.dart');
    expect(s, contains('        if (code == 22) {\n'));
    expect(s, contains('          c.send(bevestigPrivebericht(b.id));\n'), reason: 'anders bezorgt de server hem opnieuw');
    expect(s, contains('          client.bijBericht?.call(b.id, b.op, b.van, b.tekst);\n'));
    final m = _bron('lib/main.dart');
    expect(m, contains('    soulseek.client.bijBericht = (id, op, van, tekst) => uploaderberichten\n'));
    expect(m, contains('    uploaderberichten.nieuw.addListener(_bijNieuwBericht);\n'));
    expect(m, contains("key: const ValueKey('berichten-knop'),"));
    expect(m, contains("final a = await c.ask('/api/soulseek/bericht', {'aan': aan, 'tekst': tekst});"));
    final srv = _bron('lib/lan/server.dart');
    expect(srv, contains("      case '/api/soulseek/berichten':\n        return _berichten(req);"));
    expect(srv, contains("      case '/api/soulseek/bericht':\n        return _berichtSturen(req);"));
    final cs = _bron('lib/lan/client_session.dart');
    expect(cs, contains('      if (library.geenVerbinding == null) unawaited(_haalBerichten());\n'));
    // Niets in de app stuurt een bericht behalve jouw antwoord: één plek met code 22 naar buiten.
    expect(RegExp(r'priveberichtAan\(').allMatches(s).length, 2, reason: 'de functie en stuurBericht');
  });
}
