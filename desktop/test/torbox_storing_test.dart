/// Het verschil tussen "deze torrent kan niet" en "TorBox ligt eruit".
///
/// **Waarom dit bestaat.** Op 23-08-2026 stond er in de app "Mislukt" bij een album dat op datzelfde
/// moment in µTorrent op 6 MB/s binnenkwam. De melding luidde "TorBox antwoordde niet binnen vijftien
/// seconden" — waar in werkelijkheid TorBox' eigen API verstoord was: `createtorrent` gaf 504 na een
/// minuut, daarna een 302 naar `status.torbox.app`, `user/me` antwoordde `DATABASE_ERROR`, en hun
/// statuspagina meldde "Some services are degraded — API".
///
/// Een melding die de verkeerde schuldige aanwijst is erger dan geen melding: je gaat je eigen bron,
/// je eigen koekje en je eigen code zitten controleren. Deze test legt vast waaraan de app een
/// storing herkent — inclusief de gevallen die juist géén storing zijn, want als álles een storing
/// heet komt er nooit meer een echte reden op het scherm.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:debridmusic/torbox.dart';

void main() {
  group('wanneer ligt het aan TorBox zelf', () {
    test('een gateway-fout is van hen', () {
      expect(const TbToevoeging(false, null, null, 'HTTP 504', 504).storing, isTrue);
      expect(const TbToevoeging(false, null, null, 'HTTP 502', 502).storing, isTrue);
    });

    test('en zo ook: helemaal geen antwoord', () {
      // Status 0 = de time-out of de netwerkfout. Dit is precies het geval dat op het scherm stond.
      expect(
          const TbToevoeging(false, null, null, 'TimeoutException after 0:00:40.000000', 0).storing,
          isTrue);
    });

    test('een omleiding naar hun statuspagina zegt het letterlijk', () {
      expect(
          const TbToevoeging(false, null, null, 'omleiding naar status.torbox.app', 302).storing,
          isTrue);
    });

    test('en hun eigen DATABASE_ERROR ook', () {
      expect(const TbToevoeging(false, null, null, 'DATABASE_ERROR', 200).storing, isTrue);
    });

    test('te veel verzoeken is óók niet iets van deze torrent', () {
      expect(const TbToevoeging(false, null, null, 'rate limited', 429).storing, isTrue);
    });

    test('maar een echte weigering blijft een echte weigering', () {
      // Deze horen wél als reden op het scherm te komen, niet weggemoffeld als "storing".
      expect(const TbToevoeging(false, null, null, 'ACTIVE_LIMIT', 400).storing, isFalse);
      expect(const TbToevoeging(false, null, null, 'BAD_TOKEN', 401).storing, isFalse);
      expect(const TbToevoeging(false, null, null, 'Found Cached Torrent', 200).storing, isFalse);
    });
  });

  group('het antwoord uitpakken', () {
    test('een geslaagde toevoeging geeft id en hash', () {
      final t = TorBox.leesToevoeging(http.Response(
          '{"success":true,"detail":"Found Cached Torrent",'
          '"data":{"torrent_id":42,"hash":"73812ba4ac3bb331e8deff00689575cfe2193c73"}}',
          200));

      expect(t.gelukt, isTrue);
      expect(t.id, 42);
      expect(t.hash, '73812ba4ac3bb331e8deff00689575cfe2193c73');
      expect(t.storing, isFalse);
    });

    test('HTML in plaats van JSON wordt de status, niet een parseerfout', () {
      // Wat er werkelijk terugkwam. `jsonDecode` gooit hier "Unexpected character (at character 1)"
      // overheen, en dát stond dan als reden op het scherm.
      final t = TorBox.leesToevoeging(http.Response('error code: 504', 504));

      expect(t.gelukt, isFalse);
      expect(t.reden, 'HTTP 504');
      expect(t.reden, isNot(contains('Unexpected character')));
      expect(t.storing, isTrue);
    });

    test('een omleiding naar de statuspagina wordt bij naam genoemd', () {
      final t = TorBox.leesToevoeging(http.Response('<html>302 Found</html>', 302,
          headers: {'location': 'https://status.torbox.app/i'}));

      expect(t.reden, contains('status.torbox.app'));
      expect(t.storing, isTrue);
    });

    test('een gewone weigering van TorBox blijft leesbaar', () {
      final t = TorBox.leesToevoeging(
          http.Response('{"success":false,"error":"ACTIVE_LIMIT","detail":"Te veel actief"}', 400));

      expect(t.gelukt, isFalse);
      expect(t.reden, 'Te veel actief');
      expect(t.storing, isFalse, reason: 'dit gaat wél over jouw account, niet over hun storing');
    });

    test('torrent_id 0 telt niet als id', () {
      // TorBox stuurt 0 als hij niets aanmaakte; dat mag niet als geldig id verderop belanden.
      final t = TorBox.leesToevoeging(
          http.Response('{"success":true,"data":{"torrent_id":0,"hash":"aa"}}', 200));

      expect(t.id, isNull);
      expect(t.hash, 'aa');
    });
  });

  group('de sleutelcontrole wijst niet de verkeerde schuldige aan', () {
    test('een goede sleutel bij een gezonde TorBox', () {
      expect(TorBox.beoordeel(200, '{"success":true,"data":{"plan":1}}'), TbControle.ok);
    });

    test('geen sleutel meegestuurd is een sleutelprobleem', () {
      // Letterlijk het antwoord van TorBox op een verzoek zonder Authorization-kop.
      expect(TorBox.beoordeel(401, '{"detail":"Not authenticated"}'), TbControle.sleutelOngeldig);
      expect(TorBox.beoordeel(200, '{"success":false,"error":"BAD_TOKEN"}'),
          TbControle.sleutelOngeldig);
    });

    test('maar hún AUTH_ERROR is een storing, geen verkeerde sleutel', () {
      // Dit kwam op 23-08-2026 terug op een sleutel die een half uur eerder gewoon werkte. Als de
      // app dit "Ongeldige sleutel" noemt, ga je een goede sleutel vervangen.
      expect(
          TorBox.beoordeel(403,
              '{"success":false,"error":"AUTH_ERROR","detail":"An error occurred while verifying your token. Please try again."}'),
          TbControle.storing);
    });

    test('en zo ook een gateway-fout, een omleiding of stilte', () {
      expect(TorBox.beoordeel(504, 'error code: 504'), TbControle.storing);
      expect(TorBox.beoordeel(302, '', locatie: 'https://status.torbox.app/i'), TbControle.storing);
      expect(TorBox.beoordeel(0, ''), TbControle.storing, reason: 'time-out: er kwam niets');
      expect(TorBox.beoordeel(200, '{"success":false,"error":"DATABASE_ERROR"}'),
          TbControle.storing);
    });
  });
}
