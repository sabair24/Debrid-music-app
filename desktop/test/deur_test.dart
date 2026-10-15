/// De deur naar buiten (stap 7 van "verbinden zoals Roon ARC", 14-10-2026), tegen een NEP-modem op
/// loopback. Nooit tegen de echte: een poort in de modem is Sabers beveiligingsinstelling, en een
/// toets die er per ongeluk een zet, opent zijn pc voor het internet (zie de poortproef van 14-10).
///
/// De nep-modem doet na wat de F3896LG deed in de poortproef (lease afgerond naar 900 s, verlengt bij
/// een tweede Add), plus wat andere modems doen: niet verlengen, alleen vaste deuren (725), een bezette
/// buitenpoort (718), een verbroken verbinding, een herstart.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/deur.dart';
import 'package:debridmusic/lan/igd.dart';
import 'package:debridmusic/lan/tokens.dart';

class _Deur {
  _Deur(this.intern, this.client, this.naam, this.lease, this.t0);
  final int intern;
  final String client;
  final String naam;
  final int lease;
  int t0;
}

/// Een UPnP-modem op 127.0.0.1. De klok ([nu], in seconden) is van de toets.
class _NepModem {
  late HttpServer server;
  var nu = 0;
  final deuren = <int, _Deur>{};
  final acties = <String>[];
  String publiek = '81.82.83.84';
  int uptime = 5000;
  int maxLease = 0; // > 0: de modem geeft nooit meer dan dit
  int minLease = 0; // > 0: korte leases worden zoveel (F3896LG: 900)
  bool verlengtNiet = false;
  bool alleenVast = false;
  final bezet = <int>{}; // AddPortMapping op deze buitenpoort geeft 718
  final verbreekEenKeer = <String>{}; // deze actie verbreekt één keer de verbinding
  bool overschrijftAnderen = false; // sommige modems laten een Add over de deur van een ander toestel heen gaan

  Uri get locatie => Uri.parse('http://127.0.0.1:${server.port}/beschrijving.xml');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handel);
  }

  Future<void> stop() => server.close(force: true);

  _Deur? levend(int p) {
    final d = deuren[p];
    if (d == null) return null;
    if (d.lease > 0 && nu - d.t0 >= d.lease) {
      deuren.remove(p);
      return null;
    }
    return d;
  }

  Future<void> _handel(HttpRequest req) async {
    final lijf = await utf8.decoder.bind(req).join();
    final res = req.response;
    if (req.method == 'GET') {
      res.headers.contentType = ContentType('text', 'xml');
      res.write('<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0"><device>'
          '<deviceType>urn:schemas-upnp-org:device:InternetGatewayDevice:1</deviceType><deviceList><device>'
          '<deviceList><device><serviceList><service>'
          '<serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType>'
          '<controlURL>/ctl/IPConn</controlURL></service></serviceList></device></deviceList>'
          '</device></deviceList></device></root>');
      return res.close();
    }
    final actie = RegExp(r'#(\w+)"?$').firstMatch(req.headers.value('soapaction') ?? '')?.group(1) ?? '?';
    acties.add(actie);
    if (verbreekEenKeer.remove(actie)) {
      final s = await res.detachSocket(writeHeaders: false);
      s.destroy();
      return;
    }
    String? veld(String n) => RegExp('<$n>([^<]*)</$n>').firstMatch(lijf)?.group(1);
    final p = int.tryParse(veld('NewExternalPort') ?? '') ?? 0;
    switch (actie) {
      case 'GetStatusInfo':
        return _goed(res, actie, '<NewConnectionStatus>Connected</NewConnectionStatus><NewUptime>$uptime</NewUptime>');
      case 'GetExternalIPAddress':
        return _goed(res, actie, '<NewExternalIPAddress>$publiek</NewExternalIPAddress>');
      case 'GetSpecificPortMappingEntry':
        final d = levend(p);
        if (d == null) return _fout(res, 714);
        final rest = d.lease > 0 ? d.lease - (nu - d.t0) : 0;
        return _goed(res, actie,
            '<NewInternalPort>${d.intern}</NewInternalPort><NewInternalClient>${d.client}</NewInternalClient>'
            '<NewEnabled>1</NewEnabled><NewPortMappingDescription>${d.naam}</NewPortMappingDescription>'
            '<NewLeaseDuration>$rest</NewLeaseDuration>');
      case 'AddPortMapping':
        var lease = int.parse(veld('NewLeaseDuration') ?? '0');
        if (alleenVast && lease > 0) return _fout(res, 725);
        if (bezet.contains(p)) return _fout(res, 718);
        final oud = levend(p);
        final client = veld('NewInternalClient') ?? '';
        if (oud != null && oud.client != client && !overschrijftAnderen) return _fout(res, 718);
        if (lease > 0 && minLease > 0 && lease < minLease) lease = minLease;
        if (lease > 0 && maxLease > 0 && lease > maxLease) lease = maxLease;
        if (oud != null && verlengtNiet) return _goed(res, actie, '');
        deuren[p] = _Deur(int.parse(veld('NewInternalPort') ?? '0'), client, veld('NewPortMappingDescription') ?? '', lease, nu);
        return _goed(res, actie, '');
      case 'DeletePortMapping':
        if (levend(p) == null) return _fout(res, 714);
        deuren.remove(p);
        return _goed(res, actie, '');
    }
    return _fout(res, 401);
  }

  Future<void> _goed(HttpResponse res, String actie, String inhoud) {
    res.headers.contentType = ContentType('text', 'xml');
    res.write('<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
        '<u:${actie}Response xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:1">$inhoud</u:${actie}Response>'
        '</s:Body></s:Envelope>');
    return res.close();
  }

  Future<void> _fout(HttpResponse res, int code) {
    res.statusCode = 500;
    res.headers.contentType = ContentType('text', 'xml');
    res.write('<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>'
        '<detail><UPnPError><errorCode>$code</errorCode><errorDescription>nep</errorDescription></UPnPError></detail>'
        '</s:Fault></s:Body></s:Envelope>');
    return res.close();
  }
}

void main() {
  late _NepModem modem;
  late DeurNaarBuiten deur;
  final regels = <String>[];
  var klok = DateTime(2026, 10, 14, 22);

  /// De tijd laten lopen, voor de deur én de modem.
  void verder(int seconden) {
    klok = klok.add(Duration(seconds: seconden));
    modem.nu += seconden;
  }

  setUp(() async {
    regels.clear();
    klok = DateTime(2026, 10, 14, 22);
    modem = _NepModem();
    await modem.start();
    deur = DeurNaarBuiten(
      zoekModem: () => Igd(wacht: const Duration(seconds: 2)).zoek(locatie: modem.locatie),
      igd: Igd(wacht: const Duration(seconds: 2)),
      log: regels.add,
      klok: () => klok,
    );
  });

  tearDown(() async {
    deur.dispose();
    await modem.stop();
  });

  group('regels', () {
    test('publiek adres: geen privé-reeks en geen CGNAT', () {
      expect(isPubliekAdres('81.82.83.84'), isTrue);
      for (final ip in ['192.168.0.1', '10.0.0.1', '172.20.1.1', '100.64.0.1', '100.127.255.1', '127.0.0.1', '169.254.1.1', '0.0.0.0', '']) {
        expect(isPubliekAdres(ip), isFalse, reason: ip);
      }
      expect(maskeerAdres('178.1.2.3'), '178.x.x.x');
    });

    test('SSDP en de beschrijving: LOCATION lezen, WANIPConnection:2 boven :1, URLBase telt', () {
      expect(ssdpLocatie('HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=120\r\nLocation: http://192.168.0.1:5000/rootDesc.xml\r\n\r\n'),
          Uri.parse('http://192.168.0.1:5000/rootDesc.xml'));
      final xml = '<root><URLBase>http://192.168.0.1:5001/</URLBase>'
          '<service><serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType><controlURL>/een</controlURL></service>'
          '<service><serviceType>urn:schemas-upnp-org:service:WANIPConnection:2</serviceType><controlURL>/twee</controlURL></service></root>';
      final d = dienstUitBeschrijving(xml, Uri.parse('http://192.168.0.1:5000/rootDesc.xml'))!;
      expect(d.soort, endsWith(':2'));
      expect(d.controle, Uri.parse('http://192.168.0.1:5001/twee'));
    });

    test('de zinnen op de pc', () {
      expect(deurTekst(aan: false, stand: DeurStand.uit), contains('zoals Roon ARC'));
      expect(deurTekst(aan: true, stand: DeurStand.open, poort: 47821), contains('Nog geen toestel'));
      expect(deurTekst(aan: true, stand: DeurStand.open, poort: 47821, laatstVanBuiten: DateTime(2026, 10, 15, 8, 14)),
          contains('om 08:14'));
      expect(deurTekst(aan: true, stand: DeurStand.open, poort: 47831), contains('47821 was bezet'));
      expect(deurTekst(aan: true, stand: DeurStand.mislukt, waarom: 'CGNAT'), 'CGNAT');
      expect(deurMetDeHand('192.168.0.117'), contains('buiten 47821 → binnen 47821, naar 192.168.0.117'));
      expect(deurMetDeHand(null), contains('Nooit 47820 of 47822'));
    });

    test('"laatst via het publieke adres": alleen wat langs de deur binnenkwam', () {
      final t1 = DateTime(2026, 10, 15, 8, 14);
      final t2 = DateTime(2026, 10, 15, 9, 30);
      final lijst = [
        DeviceGrant(deviceId: 'gsm-van-saber-01', deviceName: 'S26', platform: 'android', token: 'a', grantedAt: 0,
            lastSeenAt: t1.millisecondsSinceEpoch, lastSeenVia: 'buiten'),
        DeviceGrant(deviceId: 'ipad-van-saber-1', deviceName: 'iPad', platform: 'ios', token: 'b', grantedAt: 0,
            lastSeenAt: t2.millisecondsSinceEpoch, lastSeenVia: 'thuis'),
      ];
      expect(laatstVanBuiten(lijst), t1, reason: 'het iPad thuis om 09:30 telt niet');
      expect(laatstVanBuiten(const []), isNull);
    });

    test('het eigen adres naar de modem: dat van het eigen netwerk, nooit dat van de modem zelf', () {
      // Sabers pc op 15-10-2026: Ethernet, Tailscale en een VirtualBox-kaart. `Socket.address` gaf hier
      // 192.168.0.1 — de modem; de deur zou naar de modem gewezen hebben.
      final eigen = [
        InternetAddress('100.97.101.113'),
        InternetAddress('192.168.56.1'),
        InternetAddress('192.168.0.117'),
      ];
      expect(eigenAdresNaar('192.168.0.1', eigen), '192.168.0.117', reason: 'hetzelfde /24 gaat voor');
      expect(eigenAdresNaar('192.168.0.1', [InternetAddress('192.168.0.1'), ...eigen]), '192.168.0.117',
          reason: 'het adres van de modem zelf is nooit het eigen adres');
      expect(eigenAdresNaar('10.0.0.1', eigen), isNull, reason: 'geen eigen adres op dat netwerk: dan geen deur');
      expect(eigenAdresNaar('127.0.0.1', eigen), '127.0.0.1', reason: 'de nep-modem in een toets');
      expect(eigenAdresNaar('192.168.5.1', [InternetAddress('100.100.5.2'), InternetAddress('192.168.0.117')]),
          '192.168.0.117', reason: 'anders hetzelfde /16, en Tailscale nooit');
    });

    test('de zoektocht gaat alleen langs het eigen netwerk: niet via Tailscale, loopback of link-local', () {
      expect(lanAdresVoorSsdp(InternetAddress('192.168.0.117')), isTrue);
      expect(lanAdresVoorSsdp(InternetAddress('10.1.2.3')), isTrue);
      expect(lanAdresVoorSsdp(InternetAddress('172.20.0.5')), isTrue);
      for (final a in ['100.97.101.113', '127.0.0.1', '169.254.3.4', '81.82.83.84']) {
        expect(lanAdresVoorSsdp(InternetAddress(a)), isFalse, reason: a);
      }
    });

    test('nooit 47820 of 47822 als buitenpoort', () {
      expect(kUitwijkPoorten, isNot(contains(47820)));
      expect(kUitwijkPoorten, isNot(contains(47822)));
    });
  });

  test('aan: deur 47821 → deze pc:47821, met naam en lease, en het adres voor de toestellen', () async {
    await deur.zetAan();
    expect(deur.stand, DeurStand.open, reason: deur.waarom);
    final d = modem.deuren[47821]!;
    expect(d.intern, 47821);
    expect(d.client, '127.0.0.1', reason: 'het adres van de socket naar de modem');
    expect(d.naam, kDeurNaam);
    expect(d.lease, kDeurLease);
    expect(deur.adresVoorToestellen, Uri.parse('https://81.82.83.84:47821'));
    expect(regels.join('\n'), isNot(contains('81.82.83.84')), reason: 'het publieke adres gemaskeerd in het logboek');
    expect(modem.acties, isNot(contains('GetGenericPortMappingEntry')), reason: 'nooit de deuren van anderen opsommen');
  });

  test('zoals de F3896LG: hij geeft 900 s, dus vernieuwen vóór de helft daarvan; verlengen lukt', () async {
    modem.maxLease = 900;
    await deur.zetAan();
    expect(deur.toegekend, 900);
    expect(deur.tussenpoos, const Duration(seconds: 450), reason: 'op de lease die hij geeft, niet op 3600');
    verder(450);
    await deur.nuEenRonde();
    expect(modem.levend(47821)?.t0, 450, reason: 'de tweede Add zette de klok terug');
    expect(regels.join('\n'), isNot(contains('niet verlengd')));
    verder(500);
    expect(modem.levend(47821), isNotNull, reason: 'na 950 s staat hij er nog, omdat hij op 450 verlengd werd');
  });

  test('een modem die niet verlengt: gezien bij het nalezen, gewist en opnieuw gezet', () async {
    modem.maxLease = 900;
    modem.verlengtNiet = true;
    await deur.zetAan();
    verder(450);
    await deur.nuEenRonde();
    expect(regels.join('\n'), contains('niet verlengd'));
    expect(modem.levend(47821)?.t0, 450, reason: 'opnieuw gezet, dus een verse lease');
  });

  test('47821 al van iets anders: een uitwijkpoort, en die gaat naar de toestellen', () async {
    modem.deuren[47821] = _Deur(55002, '192.168.0.33', 'Roon', 0, 0);
    // Een modem die er gewoon overheen zou gaan: dan moet de app het zelf laten.
    modem.overschrijftAnderen = true;
    await deur.zetAan();
    expect(deur.externePoort, kUitwijkPoorten.first);
    expect(modem.deuren[47821]!.naam, 'Roon', reason: 'van een ander blijft de app af');
    expect(deur.adresVoorToestellen?.port, kUitwijkPoorten.first);
  });

  test('718 op het zetten zelf: de volgende buitenpoort', () async {
    modem.bezet.add(47821);
    await deur.zetAan();
    expect(deur.stand, DeurStand.open);
    expect(deur.externePoort, kUitwijkPoorten.first);
  });

  test('alleen vaste deuren (725): lease 0, en uitzetten wist hem dan toch', () async {
    modem.alleenVast = true;
    await deur.zetAan();
    expect(deur.vast, isTrue);
    expect(modem.deuren[47821]!.lease, 0);
    await deur.zetUit();
    expect(modem.deuren, isEmpty);
  });

  test('een eigen deur van vroeger naar een oud adres van deze pc: weg, en opnieuw naar nu', () async {
    modem.deuren[47821] = _Deur(47821, '192.168.0.50', kDeurNaam, 3600, 0);
    await deur.zetAan();
    expect(deur.externePoort, 47821);
    expect(modem.deuren[47821]!.client, '127.0.0.1');
  });

  test('de modem herstart: elke deur weg, de uptime daalt — de volgende ronde zet hem terug', () async {
    await deur.zetAan();
    modem.deuren.clear();
    modem.uptime = 30;
    // Na een herstart vaak een nieuw adres: dat moet meteen mee, niet pas na de vijf minuten.
    modem.publiek = '81.82.83.99';
    verder(60);
    await deur.nuEenRonde();
    expect(regels.join('\n'), contains('modem herstart'));
    expect(deur.adresVoorToestellen?.host, '81.82.83.99');
    expect(modem.levend(47821), isNotNull);
    expect(deur.stand, DeurStand.open);
  });

  test('CGNAT of een tweede router: geen deur, en een zin waarom', () async {
    modem.publiek = '100.70.1.2';
    await deur.zetAan();
    expect(deur.stand, DeurStand.mislukt);
    expect(deur.waarom, contains('CGNAT'));
    expect(modem.deuren, isEmpty);
    expect(deur.adresVoorToestellen, isNull);
  });

  test('een deur naar 47820 of 47822 in de modem: rood', () async {
    modem.deuren[47820] = _Deur(47820, '192.168.0.117', 'iets', 0, 0);
    await deur.zetAan();
    expect(deur.rodeMelding, contains('poort 47820'));
    modem.deuren.remove(47820);
    verder(600);
    await deur.nuEenRonde();
    expect(deur.rodeMelding, isNull, reason: 'weg is weg');
  });

  test('uit: de deur meteen weg, en nagekeken', () async {
    await deur.zetAan();
    expect(modem.deuren, contains(47821));
    await deur.zetUit();
    expect(modem.deuren, isEmpty);
    expect(deur.stand, DeurStand.uit);
    expect(regels.join('\n'), contains('714 bevestigd'));
  });

  test('een verbroken verbinding: deze ronde mislukt, de volgende lukt', () async {
    modem.verbreekEenKeer.add('GetSpecificPortMappingEntry');
    await deur.zetAan();
    expect(deur.stand, DeurStand.mislukt);
    expect(deur.waarom, contains('antwoordt niet'));
    verder(60);
    await deur.nuEenRonde();
    expect(deur.stand, DeurStand.open);
  });

  test('de modem komt na een storing op een andere poort terug: opnieuw zoeken, niet vastzitten', () async {
    await deur.zetAan();
    await modem.stop();
    final deuren = Map.of(modem.deuren);
    modem = _NepModem()..deuren.addAll(deuren);
    await modem.start();
    verder(600);
    await deur.nuEenRonde();
    expect(deur.stand, DeurStand.mislukt, reason: 'de oude ingang is weg');
    verder(60);
    await deur.nuEenRonde();
    expect(deur.stand, DeurStand.open, reason: 'opnieuw gezocht, en gevonden op zijn nieuwe poort');
  });

  test('het adres van de modem onthouden: de volgende start zonder zoektocht', () async {
    // Zonder `zoekModem`: dan de echte weg — eerst het onthouden adres, dan pas SSDP (die onder een toets
    // nooit zoekt, zie igd_nooit_echt_test). Zo bewijst dit dat het onthouden adres alleen al volstaat.
    Uri? bewaard = modem.locatie;
    final d = DeurNaarBuiten(
      igd: Igd(wacht: const Duration(seconds: 2)),
      log: regels.add,
      klok: () => klok,
      onthouden: (lees: () => bewaard, bewaar: (l) => bewaard = l),
    );
    addTearDown(d.dispose);
    await d.zetAan();
    expect(d.stand, DeurStand.open, reason: d.waarom);
    expect(bewaard, modem.locatie, reason: 'en hij onthoudt waar hij hem vond');
  });

  test('niets onthouden en geen zoektocht: geen modem, en het onthouden adres blijft leeg', () async {
    Uri? bewaard;
    final d = DeurNaarBuiten(log: regels.add, onthouden: (lees: () => bewaard, bewaar: (l) => bewaard = l));
    addTearDown(d.dispose);
    await d.zetAan();
    expect(d.stand, DeurStand.mislukt);
    expect(bewaard, isNull);
  });

  test('na een mislukking sneller opnieuw: 30 s, dan 1 min; na een gelukte ronde weer gewoon', () async {
    var gevonden = false;
    final d = DeurNaarBuiten(
      zoekModem: () async => gevonden ? Igd(wacht: const Duration(seconds: 2)).zoek(locatie: modem.locatie) : null,
      igd: Igd(wacht: const Duration(seconds: 2)),
      log: regels.add,
      klok: () => klok,
    );
    addTearDown(d.dispose);
    await d.zetAan();
    expect(d.tussenpoos, const Duration(seconds: 30));
    await d.nuEenRonde();
    expect(d.tussenpoos, const Duration(minutes: 1));
    gevonden = true;
    await d.nuEenRonde();
    expect(d.stand, DeurStand.open);
    expect(d.tussenpoos, d.ronde, reason: 'lease 3600: de gewone tien minuten');
    // Weer een storing na een gelukte ronde: opnieuw vanaf 30 s, niet verder waar de vorige reeks stopte.
    await modem.stop();
    verder(600);
    await d.nuEenRonde();
    expect(d.stand, DeurStand.mislukt);
    expect(d.tussenpoos, const Duration(seconds: 30));
    await modem.start();
  });

  test('wat de zoektocht vond, wordt onthouden voor de volgende start', () async {
    Uri? bewaard;
    final d = DeurNaarBuiten(
      zoekModem: () => Igd(wacht: const Duration(seconds: 2)).zoek(locatie: modem.locatie),
      igd: Igd(wacht: const Duration(seconds: 2)),
      log: regels.add,
      klok: () => klok,
      onthouden: (lees: () => bewaard, bewaar: (l) => bewaard = l),
    );
    addTearDown(d.dispose);
    await d.zetAan();
    expect(bewaard, modem.locatie);
  });

  test('geen modem met UPnP: een zin met wat te doen', () async {
    final zonder = DeurNaarBuiten(zoekModem: () async => null, log: regels.add);
    addTearDown(zonder.dispose);
    await zonder.zetAan();
    expect(zonder.stand, DeurStand.mislukt);
    expect(zonder.waarom, contains('met de hand'));
  });
}
