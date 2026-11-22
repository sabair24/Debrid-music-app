/// Een scan die je zelf aanwijst, staat er meteen — ook op een toestel (Saber, 22-11-2026, de cd van Nicoletta —
/// *Visage* op de Mac: *"dit lukte echt moeizaam en wou niet direct aanpassen, hoe komt dit … dat moet echt voor goed
/// eens opgelost worden"*).
///
/// Wat er gebeurde: op een toestel kwam de rol eerst HIER te staan en pas daarna bij de pc. Het scherm laadde meteen
/// opnieuw, onder de sleutel van de nieuwe rol, en vroeg de pc om de scans — die de rol nog niet kende. Zijn antwoord
/// (de oude cd, "af") werd onder de nieuwe sleutel bewaard, en daarna vroeg het toestel niets meer. "Opslaan" wiste
/// bovendien eerst alles en zette dan elke rol apart: op een toestel elk een herlading van de catalogus. En wie "Uitgave
/// kiezen" opnieuw opende, zag bij die uitgave weer de gok van de app.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

/// De scan die Saber als cd aanwees.
const _visageCd = 'https://i.discogs.com/ODNVF-v4tT7biapI67Ki_jA0G7CmNhOIs5qVY-0YASU/rs:fit/g:sm/q:90/h:595/w:600/'
    'czM6Ly9kaXNjb2dz/LWRhdGFiYXNlLWlt/YWdlcy9SLTE0NTg2/Mjk1LTE1Nzc2NDc5/MzQtNzUzMS5qcGVn.jpeg';

Uint8List _plaatje(int waarde) => Uint8List.fromList(List.filled(800, waarde));

void main() {
  group('op een toestel: de rol staat er meteen, wat de pc ook weet', () {
    late Directory wortel;
    setUp(() {
      wortel = Directory.systemTemp.createTempSync('dm_rollen_');
      setAppDirForTest(wortel.path);
    });
    tearDown(() {
      DiscogsArtwork.vanDePc = null;
      try {
        wortel.deleteSync(recursive: true);
      } catch (_) {}
    });

    final oud = _plaatje(1), nieuw = _plaatje(2), hoes = _plaatje(3), achter = _plaatje(4);

    /// Een pc die de rol nog niet kent: de oude cd, en "af".
    void pcZonderRol() => DiscogsArtwork.vanDePc = (a, b, {bool klein = false, String? plaat}) async =>
        (art: ReleaseArt(front: hoes, back: achter, disc: oud), klaar: true);

    Future<ReleaseArt?> haal(DiscogsService d, Map<String, String> rollen, {bool rolTeHalen = true}) => http.runWithClient(
        () => d.releaseArt('Nicoletta', 'Visage', pinned: 14282072, roles: rollen),
        () => MockClient((req) async => rolTeHalen && req.url.toString() == _visageCd
            ? http.Response.bytes(nieuw, 200)
            : http.Response('', 404)));

    test('DE KERN: de pc geeft nog de oude cd — het toestel legt de cd die je aanwees eroverheen, en onthoudt dat', () async {
      pcZonderRol();
      final d = DiscogsService(AppSettings());
      final rollen = {'disc': _visageCd};
      final a = await haal(d, rollen);
      expect(a?.disc, nieuw, reason: 'de cd die je aanwees, niet die van de pc');
      expect(a?.back, achter, reason: 'wat je niet aanwees, komt van de pc');
      final map = d.artMap('Nicoletta', 'Visage', 0, 14282072, null, rollen);
      expect(File('${map.path}${Platform.pathSeparator}disc').readAsBytesSync(), nieuw);
      expect(File('${map.path}${Platform.pathSeparator}rollen').existsSync(), isTrue);
      expect(File('${map.path}${Platform.pathSeparator}done').existsSync(), isTrue);
    });

    test('DE KERN: een map van vóór vandaag met de oude cd wordt één keer opnieuw gevuld', () async {
      pcZonderRol();
      final d = DiscogsService(AppSettings());
      final rollen = {'disc': _visageCd};
      final map = d.artMap('Nicoletta', 'Visage', 0, 14282072, null, rollen)..createSync(recursive: true);
      for (final (n, b) in [('front', hoes), ('back', achter), ('disc', oud)]) {
        File('${map.path}${Platform.pathSeparator}$n').writeAsBytesSync(b);
      }
      File('${map.path}${Platform.pathSeparator}done').writeAsStringSync('');
      final a = await haal(d, rollen);
      expect(a?.disc, nieuw, reason: 'zonder het briefje "rollen" geen afgerond antwoord');
      expect(File('${map.path}${Platform.pathSeparator}rollen').existsSync(), isTrue);
    });

    test('een rol die niet te halen is: wat de pc gaf, maar niet afgerond — de volgende keer opnieuw', () async {
      pcZonderRol();
      final d = DiscogsService(AppSettings());
      final rollen = {'disc': _visageCd};
      final a = await haal(d, rollen, rolTeHalen: false);
      expect(a?.disc, oud);
      final map = d.artMap('Nicoletta', 'Visage', 0, 14282072, null, rollen);
      expect(File('${map.path}${Platform.pathSeparator}done').existsSync(), isFalse);
      expect(File('${map.path}${Platform.pathSeparator}rollen').existsSync(), isFalse);
    });

    test('zonder rollen: wat de pc gaf, zoals altijd', () async {
      pcZonderRol();
      final d = DiscogsService(AppSettings());
      final a = await haal(d, const {});
      expect(a?.disc, oud);
    });

    test('op de pc zelf (geen vanDePc): een afgeronde map met rollen blijft het antwoord', () async {
      final d = DiscogsService(AppSettings());
      final rollen = {'disc': _visageCd};
      final map = d.artMap('Nicoletta', 'Visage', 0, 14282072, null, rollen)..createSync(recursive: true);
      for (final (n, b) in [('front', hoes), ('back', achter), ('disc', nieuw)]) {
        File('${map.path}${Platform.pathSeparator}$n').writeAsBytesSync(b);
      }
      File('${map.path}${Platform.pathSeparator}done').writeAsStringSync('');
      final a = await haal(d, rollen, rolTeHalen: false);
      expect(a?.disc, nieuw, reason: 'de pc past zijn eigen rollen toe; geen tweede ronde');
    });
  });

  group('alle rollen in één keer', () {
    late Directory wortel;
    setUp(() {
      wortel = Directory.systemTemp.createTempSync('dm_rollen_lib_');
      setAppDirForTest(wortel.path);
    });
    tearDown(() {
      try {
        wortel.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: wat in de lijst staat, en verder niets; leeg laat de app weer raden', () async {
      final lib = LibraryStore();
      await lib.setAlbumArtRole('Nicoletta', 'Visage', 'back', 'https://x.test/achter.jpg');
      await lib.zetAlbumArtRoles('Nicoletta', 'Visage', {'disc': _visageCd, 'front': ''});
      expect(lib.albumArtRoles('Nicoletta', 'Visage'), {'disc': _visageCd},
          reason: 'de achterkant van eerder is weg; een lege rol telt niet');
      await lib.zetAlbumArtRoles('Nicoletta', 'Visage', const {});
      expect(lib.albumArtRoles('Nicoletta', 'Visage'), isEmpty);
    });

    test('de pc neemt het aan als één bewerking, en kijkt van buiten elk adres na', () {
      final s = _bron('lib/lan/server.dart');
      expect(s, contains("        case 'albumArtRoles':"));
      expect(s, contains("        op != 'albumArtRoles' &&"), reason: 'rollen hangen aan artiest en titel, niet aan een album-id');
      expect(s, contains('            rolAdressen.any((a) => a.isNotEmpty && !adresVanBuitenMag(a)))) {'));
    });

    test('aangesloten: Scans toewijzen, Opslaan en een uitgave kiezen gaan elk in één bewerking', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('      await lib.zetAlbumArtRoles(widget.album.artist, widget.album.title, {..._rollen}, plaat: widget.album.plaat);'));
      expect(m, contains('      await lib.zetAlbumArtRoles(widget.album.artist, widget.album.title, rollen, plaat: widget.album.plaat);'));
      expect(m, contains('      await lib.zetAlbumArtRoles(widget.album.artist, widget.album.title, {..._eigenRollen}, plaat: widget.album.plaat);'));
      final l = _bron('lib/library.dart');
      expect(l, contains('    if (isRemote) _zetRemoteRollen(k, _albumArtRoles[k] ?? const {});'),
          reason: 'het toestel toont de rol meteen, niet pas na de volgende catalogus');
      expect(l, contains("      await _editOnPc({'op': 'albumArtRoles', ...basis, 'rollen': schoon});"));
    });
  });

  group('"Uitgave kiezen" toont je bewaarde keuze', () {
    ReleaseChoice dg(int id) => ReleaseChoice(source: EditionSource.discogs, releaseId: id, format: 'CD');

    test('DE KERN: een Discogs-scan draagt het nummer van zijn uitgave', () {
      expect(discogsUitgaveVanScan(_visageCd), 14586295);
      expect(discogsUitgaveVanScan('https://img.discogs.com/abc/R-1813844-1234.jpeg'), 1813844);
      expect(discogsUitgaveVanScan('https://coverartarchive.org/release/x/1.jpg'), isNull);
      expect(discogsUitgaveVanScan('https://i.discogs.com/abc/rs:fit/w:600/!!!.jpeg'), isNull);
      expect(discogsUitgaveVanScan('geen adres'), isNull);
    });

    test('DE KERN: de scan hoort bij de uitgave waar hij vandaan komt, en bij geen andere', () {
      expect(scanHoortBijUitgave(_visageCd, dg(14586295)), isTrue);
      expect(scanHoortBijUitgave(_visageCd, dg(4149312)), isFalse);
      final mb = ReleaseChoice(source: EditionSource.musicbrainz, releaseId: 0, mbid: 'abc-123', format: 'CD');
      expect(scanHoortBijUitgave('https://coverartarchive.org/release/abc-123/99.jpg', mb), isTrue);
      expect(scanHoortBijUitgave('https://coverartarchive.org/release/zzz/99.jpg', mb), isFalse);
      expect(scanHoortBijUitgave('', dg(14586295)), isFalse);
    });

    test('aangesloten: de rij legt de bewaarde keuze vóór de gok', () {
      final m = _bron('lib/main.dart');
      expect(m, contains("      _thumb(eigen?['disc'] ?? bewaard('disc') ?? c.disc, 'cd',"));
      expect(m, contains('          bewaardeRollen: bewaard,'));
    });
  });

  test('de spelerbalk: de gedempte vraag op de tweede regel, zodat titel en kwaliteit passen', () {
    final m = _bron('lib/main.dart');
    expect(m, contains('                          if (t != null && !isTv) _echtheidMerk(_klinktAls(context, t), metVraag: false),'));
    expect(m, contains('                          if (!isTv) _echtheidMerk(_klinktAls(context, t), alleenVraag: true),'));
  });
}
