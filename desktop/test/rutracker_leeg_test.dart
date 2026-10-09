/// Een lege RuTracker-uitslag is geen storing, en een nummer zit in een album.
///
/// **Waarom.** Op 09-10-2026 stond er bij "Bazart Goud" in oranje: "RuTracker deed niet mee —
/// RuTracker antwoordde (200, 169571 bytes) maar er stond geen enkele resultaatrij in de pagina".
/// Gemeten in dezelfde app, dezelfde minuut: "Pink Floyd Wish You Were Here" gaf 50 treffers, en
/// "Bazart" alleen 2 ("Bazart - Onderweg - 2021, FLAC" en een discografie 2015–2021). Er was niets
/// stuk: RuTracker zoekt in torrentnamen, en daar staat het album, niet elk nummer.
///
/// Twee dingen liggen hier vast: de zin zegt dan waarnaar gezocht is in plaats van een storing te
/// melden, en de app probeert zelf het begin van de zoekterm — meestal de artiest.
library;

import 'dart:io';

import 'package:debridmusic/cp1251.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/rutracker.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// De zoekpagina zonder treffers, in de vorm die RuTracker (TorrentPier) gebruikt: het zoekformulier
/// en de resultatentabel staan er altijd, met één rij "Не найдено" als er niets is.
String _pagina(String rijen) => '<html><head><title>RuTracker.org</title></head><body>'
    '<form id="tr-form" method="post" action="tracker.php?nm=x">'
    '<input id="title-search" type="text" name="nm" value=""></form>'
    '<table class="forumline tablesorter" id="tor-tbl"><thead><tr><th>Тема</th></tr></thead>'
    '<tbody>$rijen</tbody></table></body></html>';

final _leeg = _pagina('<tr><td class="row1 tCenter pad_8" colspan="10">Не найдено</td></tr>');

String _rij(String tid, String titel, String hash) =>
    '<tr id="trs-tr-$tid" class="tCenter hl-tr" data-topic_id="$tid">'
    '<td class="row4 med tLeft t-title-col tt"><a data-topic_id="$tid" '
    'class="med tLink tt-text ts-text hl-tags bold" href="viewtopic.php?t=$tid">$titel</a></td>'
    '<td class="row4 small nowrap tor-size" data-ts_text="123456789">'
    '<a class="small tr-dl dl-stub" href="dl.php?t=$tid">117 MB</a></td>'
    '<td class="row4 nowrap" data-ts_text="2"><b class="seedmed">2</b></td>'
    '<td><a href="magnet:?xt=urn:btih:$hash">m</a></td></tr>';

final _bazart = _pagina(_rij('6101', 'Bazart - Onderweg - 2021, FLAC (tracks), lossless', 'a' * 40) +
    _rij('6102', 'Bazart - Дискография: 4 Релиза - 2015-2021, MP3, 320 kbps', 'b' * 40));

const _controle = '<html><head><title>Even geduld...</title></head><body><script>'
    "window._cf_chl_opt = {cFPWv: 'b'};</script></body></html>";

/// Zoals RuTracker het stuurt: windows-1251.
List<int> _cp1251(String s) => [for (final c in s.runes) cp1251Byte(c) ?? 0x3F];

void main() {
  group('wat een pagina zonder herkende rij is', () {
    test('de zoekpagina zonder treffers: niets gevonden, geen storing', () {
      expect(rutrackerLeegSoort(_leeg), RtLeeg.niets);
    });

    test('alleen het zoekveld, of alleen het formulier, is ook de zoekpagina', () {
      expect(rutrackerLeegSoort('<form><input name="nm" value=""></form>'), RtLeeg.niets);
      expect(rutrackerLeegSoort('<form method="post" action="tracker.php"></form>'), RtLeeg.niets);
    });

    test('DE GRENS: torrents die de app niet meer herkent zijn wél een storing', () {
      // Een RuTracker die zijn rijen anders noemt: de topic-ids staan er nog, de klasse hl-tr niet.
      final anders = _pagina('<tr class="tCenter row-nieuw" data-topic_id="6101"><td>x</td></tr>');
      expect(rutrackerLeegSoort(anders), RtLeeg.vormVeranderd);
    });

    test('een pagina zonder zoekformulier en zonder torrents is onbekend', () {
      expect(
          rutrackerLeegSoort('<html><title>RuTracker.org</title><a href="tracker.php">Tracker</a></html>'),
          RtLeeg.onbekend);
    });

    test('het kenmerk voor het logboek noemt de vorm, nooit de inhoud', () {
      final k = rutrackerLeegKenmerk(_leeg);
      expect(k, 'tor-tbl ja, zoekveld ja, formulier ja, topic-ids 0, titellinks 0');
    });
  });

  group('de kortere zoektermen', () {
    test('DE KERN: "Bazart Goud" wordt "Bazart"', () {
      expect(rutrackerKortereVragen('Bazart Goud'), ['Bazart']);
    });

    test('de langste eerst, hoogstens drie woorden', () {
      expect(rutrackerKortereVragen('Niels Destadsbader Vuur en vlam'),
          ['Niels Destadsbader Vuur', 'Niels Destadsbader', 'Niels']);
    });

    test('een streepje is geen woord', () {
      expect(rutrackerKortereVragen('Bazart - Goud'), ['Bazart']);
    });

    test('één woord heeft geen korter begin', () {
      expect(rutrackerKortereVragen('Bazart'), isEmpty);
      expect(rutrackerKortereVragen('   '), isEmpty);
    });

    test('een lidwoord of twee letters alleen vraagt de halve tracker op', () {
      expect(rutrackerKortereVragen('The Weeknd'), isEmpty);
      expect(rutrackerKortereVragen('U2 One'), isEmpty);
      expect(rutrackerKortereVragen('Sia Chandelier'), ['Sia']);
    });
  });

  group('de zin onder de zoekresultaten', () {
    test('een storing blijft een storing', () {
      expect(rutrackerStandZin(reden: 'de sessie is verlopen', aantal: 0, doorZeef: -1),
          'RuTracker deed niet mee — de sessie is verlopen');
    });

    test('niet bevraagd en nul treffers zonder zoekterm blijven zoals ze waren', () {
      expect(rutrackerStandZin(reden: '', aantal: -1, doorZeef: -1), 'RuTracker: niet bevraagd.');
      expect(rutrackerStandZin(reden: '', aantal: 0, doorZeef: -1),
          'RuTracker: bevraagd, nul treffers.');
    });

    test('DE KERN: niets gevonden zegt waarnaar, en wat er korter geprobeerd is', () {
      final zin = rutrackerStandZin(
          reden: '', aantal: 0, doorZeef: -1, vraag: 'Bazart Goud', geprobeerd: const ['Bazart']);
      expect(zin, 'RuTracker: niets voor „Bazart Goud“, ook niet voor „Bazart“ — hij zoekt alleen in '
          'torrentnamen.');
      expect(zin.contains('deed niet mee'), isFalse);
    });

    test('treffers uit een kortere zoekterm zeggen dat erbij', () {
      expect(
          rutrackerStandZin(reden: '', aantal: 2, doorZeef: 2, vraag: 'Bazart Goud', ruimer: 'Bazart'),
          'RuTracker: 2 treffers voor „Bazart“ (niets voor „Bazart Goud“ zelf).');
    });

    test('de zeef en de gewone treffers', () {
      expect(rutrackerStandZin(reden: '', aantal: 7, doorZeef: 2), 'RuTracker: 7 treffers, 2 door de zeef.');
      expect(rutrackerStandZin(reden: '', aantal: 7, doorZeef: 7), 'RuTracker: 7 treffers.');
    });
  });

  group('DE KERN: het hele zoekpad, met een nagemaakt venster', () {
    late Directory map;
    final gevraagd = <String>[];
    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_rtleeg_');
      setAppDirForTest(map.path);
      gevraagd.clear();
      RuTrackerService.curlBeschikbaarVoorTest = false;
      RuTrackerService.curlDichtTot = null;
    });
    tearDown(() {
      RuTrackerService.viaVenster = null;
      RuTrackerService.curlBeschikbaarVoorTest = null;
      RuTrackerService.curlDichtTot = null;
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    RuTrackerService dienst() => RuTrackerService(AppSettings()
      ..rutrackerCookie = 'bb_session=s'
      ..flaresolverrUrl = '');

    /// Het venster: per zoekterm een pagina. Wat er niet in staat, is een lege zoekpagina.
    void venster(Map<String, String> paginas) => RuTrackerService.viaVenster = (url, {referer}) async {
          final nm = Uri.decodeComponent(Uri.parse(url).queryParameters['nm'] ?? '');
          gevraagd.add(nm);
          return (status: 200, bytes: _cp1251(paginas[nm] ?? _leeg));
        };

    test('DE KERN: niets voor "Bazart Goud", wel voor "Bazart" — en geen storing', () async {
      venster({'Bazart': _bazart});
      final rt = dienst();
      final uit = await rt.search('Bazart Goud');
      expect(gevraagd, ['Bazart Goud', 'Bazart']);
      expect(uit.map((r) => r.name), [
        'Bazart - Onderweg - 2021, FLAC (tracks), lossless',
        'Bazart - Дискография: 4 Релиза - 2015-2021, MP3, 320 kbps',
      ]);
      expect(uit.first.hash, 'a' * 40);
      expect(rt.lastError, isEmpty);
      expect(rt.laatsteAantal, 2);
      expect(rt.laatsteVraag, 'Bazart Goud');
      expect(rt.laatsteRuimer, 'Bazart');
      expect(rt.laatstGeprobeerd, isEmpty);
    });

    test('de hele zoekterm met treffers probeert niets korters', () async {
      venster({'Bazart Goud': _bazart});
      final rt = dienst();
      expect(await rt.search('Bazart Goud'), hasLength(2));
      expect(gevraagd, ['Bazart Goud']);
      expect(rt.laatsteRuimer, isEmpty);
    });

    test('nergens iets: nul treffers, geen storing, en wat er geprobeerd is', () async {
      venster(const {});
      final rt = dienst();
      expect(await rt.search('Niels Destadsbader Vuur en vlam'), isEmpty);
      expect(gevraagd, [
        'Niels Destadsbader Vuur en vlam',
        'Niels Destadsbader Vuur',
        'Niels Destadsbader',
        'Niels',
      ]);
      expect(rt.lastError, isEmpty, reason: 'een lege uitslag is geen storing');
      expect(rt.laatsteAantal, 0);
      expect(rt.laatstGeprobeerd, ['Niels Destadsbader Vuur', 'Niels Destadsbader', 'Niels']);
    });

    test('DE GRENS: een veranderde pagina is een storing, en korter zoeken helpt dan niet', () async {
      venster({
        'Bazart Goud': _pagina('<tr class="tCenter row-nieuw" data-topic_id="6101"><td>x</td></tr>'),
        'Bazart': _bazart,
      });
      final rt = dienst();
      expect(await rt.search('Bazart Goud'), isEmpty);
      expect(gevraagd, ['Bazart Goud']);
      expect(rt.lastError, contains('pagina veranderd'));
    });

    test('een pagina die geen zoekpagina is, blijft een melding', () async {
      venster({'Bazart Goud': '<html><title>RuTracker.org</title><a href="tracker.php">T</a></html>'});
      final rt = dienst();
      expect(await rt.search('Bazart Goud'), isEmpty);
      expect(gevraagd, ['Bazart Goud']);
      expect(rt.lastError, contains('geen zoekpagina'));
    });

    test('komt bij het korter zoeken de controle, dan stopt het daar', () async {
      venster({'Niels Destadsbader': _controle});
      final rt = dienst();
      expect(await rt.search('Niels Destadsbader Vuur'), isEmpty);
      expect(gevraagd, ['Niels Destadsbader Vuur', 'Niels Destadsbader'],
          reason: 'achter de controle valt niets meer te vinden; elke vraag erna is verspild');
    });
  });

  test('het scherm gebruikt de nieuwe zin', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('final rutracker = rutrackerStandZin('), isTrue,
        reason: 'anders blijft op het scherm de oude zin staan');
    for (final veld in const [
      'vraag: rt.laatsteVraag,',
      'ruimer: rt.laatsteRuimer,',
      'geprobeerd: rt.laatstGeprobeerd,',
    ]) {
      expect(main.contains(veld), isTrue, reason: 'zonder "$veld" weet de zin niet waarnaar gezocht is');
    }
    final server = File('lib/lan/server.dart').readAsStringSync();
    expect(server.contains("'ruimer': rt.laatsteRuimer"), isTrue,
        reason: 'de telefoon zoekt via de pc en hoort dezelfde zin te krijgen');
  });
}
