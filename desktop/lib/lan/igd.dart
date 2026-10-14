/// Met de modem praten over UPnP (Internet Gateway Device): een deur zetten, lezen en wissen.
///
/// Stap 7.1 van "verbinden zoals Roon ARC" (plan 14-10-2026). Wat de Sagemcom F3896LG van Saber doet,
/// gemeten met de poortproef van 14-10-2026 (`Bureaublad\poortproef\poortproef.log`):
/// * hij biedt `WANIPConnection:1`, en antwoordt op elke SOAP-vraag over een **nieuwe** verbinding;
/// * hij rondt elke tijdelijke lease af naar **900 s** (gevraagd 600 of 120), en een tweede
///   `AddPortMapping` op dezelfde deur zet de klok terug (VERLENGT);
/// * geen SNAT: wat binnenkomt, draagt het echte publieke adres van de afzender.
///
/// Bewust smal: alleen `GetSpecificPortMappingEntry`, nooit `GetGenericPortMappingEntry` (dat somt
/// elke deur van elk toestel in huis op). Een fout uit de modem komt als [IgdFout] met zijn
/// `errorCode`: 714 = die deur bestaat niet, 718 = de buitenpoort is al van iemand anders, 725 =
/// alleen vaste deuren, 606/501 = niet toegestaan of mislukt.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// De dienst in de modem waar de deuren gezet worden.
class IgdDienst {
  const IgdDienst({required this.controle, required this.soort, required this.lokaal});

  /// Het adres van de SOAP-ingang (`controlURL`).
  final Uri controle;

  /// `urn:schemas-upnp-org:service:WANIPConnection:1` (of :2, of WANPPPConnection:1).
  final String soort;

  /// Het adres van deze pc zoals de modem hem ziet: de `NewInternalClient` van elke deur.
  final String lokaal;
}

/// Een weigering van de modem, met zijn eigen code.
class IgdFout implements Exception {
  const IgdFout(this.code, [this.tekst = '']);
  final int code;
  final String tekst;
  @override
  String toString() => 'UPnP-fout $code${tekst.isEmpty ? '' : ' ($tekst)'}';
}

/// Een deur zoals de modem hem teruggeeft.
class IgdDeur {
  const IgdDeur({required this.internePoort, required this.client, required this.lease, required this.naam});
  final int internePoort;
  final String client;

  /// Wat er nog over is, in seconden. 0 = vast (geen lease).
  final int lease;
  final String naam;
}

/// Welke diensten we nemen, in deze volgorde.
const kIgdDiensten = [
  'urn:schemas-upnp-org:service:WANIPConnection:2',
  'urn:schemas-upnp-org:service:WANIPConnection:1',
  'urn:schemas-upnp-org:service:WANPPPConnection:1',
];

/// De `LOCATION` uit een SSDP-antwoord, of null.
Uri? ssdpLocatie(String antwoord) {
  final m = RegExp(r'^location:\s*(\S+)\s*$', caseSensitive: false, multiLine: true).firstMatch(antwoord);
  return m == null ? null : Uri.tryParse(m.group(1)!);
}

/// De beste dienst uit een apparaatbeschrijving, of null. `controlURL` relatief aan [locatie] (of aan
/// `URLBase` als die erin staat).
({Uri controle, String soort})? dienstUitBeschrijving(String xml, Uri locatie) {
  final basis = Uri.tryParse(RegExp(r'<URLBase>\s*([^<]+?)\s*</URLBase>').firstMatch(xml)?.group(1) ?? '') ?? locatie;
  final gevonden = <String, String>{};
  for (final m in RegExp(r'<service>([\s\S]*?)</service>').allMatches(xml)) {
    final blok = m.group(1)!;
    final soort = RegExp(r'<serviceType>\s*([^<]+?)\s*</serviceType>').firstMatch(blok)?.group(1);
    final ctl = RegExp(r'<controlURL>\s*([^<]+?)\s*</controlURL>').firstMatch(blok)?.group(1);
    if (soort != null && ctl != null) gevonden[soort] = ctl;
  }
  for (final s in kIgdDiensten) {
    final ctl = gevonden[s];
    if (ctl != null) return (controle: (basis.hasScheme ? basis : locatie).resolve(ctl), soort: s);
  }
  return null;
}

class Igd {
  Igd({this.wacht = const Duration(seconds: 5)});

  /// Hoe lang één SOAP-vraag mag duren.
  final Duration wacht;

  /// De modem zoeken: SSDP op het netwerk, of — in een toets — rechtstreeks een beschrijving.
  /// Null als er geen modem met UPnP antwoordt.
  Future<IgdDienst?> zoek({Duration zoektijd = const Duration(seconds: 3), Uri? locatie}) async {
    final locaties = locatie != null ? [locatie] : await _ssdp(zoektijd);
    for (final l in locaties) {
      try {
        final d = await dienstVan(l);
        if (d != null) return d;
      } catch (_) {/* de volgende */}
    }
    return null;
  }

  /// De dienst achter één beschrijving, met het lokale adres van deze pc ernaar toe.
  Future<IgdDienst?> dienstVan(Uri locatie) async {
    final c = HttpClient()..connectionTimeout = wacht;
    try {
      final req = await c.getUrl(locatie).timeout(wacht);
      req.persistentConnection = false;
      final res = await req.close().timeout(wacht);
      final xml = await utf8.decoder.bind(res).join().timeout(wacht);
      final d = dienstUitBeschrijving(xml, locatie);
      if (d == null) return null;
      // Welk adres van deze pc de modem ziet: dat van de socket ernaartoe, niet een raadsel uit de
      // lijst van netwerkkaarten (Tailscale, een VPN, een tweede kaart).
      final s = await Socket.connect(d.controle.host, d.controle.port, timeout: wacht);
      final lokaal = s.address.address;
      s.destroy();
      return IgdDienst(controle: d.controle, soort: d.soort, lokaal: lokaal);
    } finally {
      c.close(force: true);
    }
  }

  Future<List<Uri>> _ssdp(Duration zoektijd) async {
    // **Nooit vanuit een toets.** Een toets mag de echte modem niet vinden, laat staan er een deur in
    // zetten: dat opent Sabers pc voor het internet. Op 14-10-2026 haalde een mutatie de bewaking in
    // `sharing.dart` weg, en toen zocht een toets op het echte netwerk (nagekeken: er kwam geen deur).
    // Toetsen geven de nep-modem met `locatie` mee; zonder die zoekt er niets.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return const [];
    final gevonden = <Uri>{};
    RawDatagramSocket? s;
    try {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final sock = s;
      sock.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = sock.receive();
        if (d == null) return;
        final l = ssdpLocatie(utf8.decode(d.data, allowMalformed: true));
        if (l != null) gevonden.add(l);
      });
      for (final st in const [
        'urn:schemas-upnp-org:device:InternetGatewayDevice:2',
        'urn:schemas-upnp-org:device:InternetGatewayDevice:1',
      ]) {
        final m = 'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 2\r\nST: $st\r\n\r\n';
        sock.send(utf8.encode(m), InternetAddress('239.255.255.250'), 1900);
      }
      await Future<void>.delayed(zoektijd);
    } catch (_) {
      // Geen netwerk of geen multicast: dan geen modem gevonden.
    } finally {
      s?.close();
    }
    return gevonden.toList();
  }

  /// Eén SOAP-vraag, over een eigen verbinding (de F3896LG wil dat zo). Geeft de velden van het
  /// antwoord; een fout van de modem wordt een [IgdFout].
  Future<Map<String, String>> vraag(IgdDienst d, String actie, Map<String, String> args) async {
    final lijf = '<?xml version="1.0"?>\r\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
        '<u:$actie xmlns:u="${d.soort}">'
        '${args.entries.map((e) => '<${e.key}>${_xml(e.value)}</${e.key}>').join()}'
        '</u:$actie></s:Body></s:Envelope>';
    final c = HttpClient()..connectionTimeout = wacht;
    try {
      final req = await c.postUrl(d.controle).timeout(wacht);
      req.persistentConnection = false;
      req.headers
        ..set(HttpHeaders.contentTypeHeader, 'text/xml; charset="utf-8"')
        ..set('SOAPAction', '"${d.soort}#$actie"');
      final bytes = utf8.encode(lijf);
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close().timeout(wacht);
      final xml = await utf8.decoder.bind(res).join().timeout(wacht);
      final code = int.tryParse(RegExp(r'<errorCode>\s*(\d+)\s*</errorCode>').firstMatch(xml)?.group(1) ?? '');
      if (code != null) {
        throw IgdFout(code, RegExp(r'<errorDescription>([^<]*)</errorDescription>').firstMatch(xml)?.group(1) ?? '');
      }
      if (res.statusCode != 200) throw IgdFout(res.statusCode, 'HTTP');
      return {
        for (final m in RegExp(r'<(New\w+)>([^<]*)</\1>').allMatches(xml)) m.group(1)!: _vanXml(m.group(2)!),
      };
    } finally {
      c.close(force: true);
    }
  }

  /// Een deur zetten: buiten [extern] → [intern] op deze pc.
  Future<void> zet(IgdDienst d, {required int extern, required int intern, required int lease, required String naam}) =>
      vraag(d, 'AddPortMapping', {
        'NewRemoteHost': '',
        'NewExternalPort': '$extern',
        'NewProtocol': 'TCP',
        'NewInternalPort': '$intern',
        'NewInternalClient': d.lokaal,
        'NewEnabled': '1',
        'NewPortMappingDescription': naam,
        'NewLeaseDuration': '$lease',
      });

  /// De deur op buitenpoort [extern], of null als er geen is (714).
  Future<IgdDeur?> lees(IgdDienst d, int extern) async {
    try {
      final v = await vraag(d, 'GetSpecificPortMappingEntry',
          {'NewRemoteHost': '', 'NewExternalPort': '$extern', 'NewProtocol': 'TCP'});
      return IgdDeur(
        internePoort: int.tryParse(v['NewInternalPort'] ?? '') ?? 0,
        client: v['NewInternalClient'] ?? '',
        lease: int.tryParse(v['NewLeaseDuration'] ?? '') ?? 0,
        naam: v['NewPortMappingDescription'] ?? '',
      );
    } on IgdFout catch (f) {
      if (f.code == 714) return null;
      rethrow;
    }
  }

  /// De deur wissen. Er was er geen (714): ook goed.
  Future<void> wis(IgdDienst d, int extern) async {
    try {
      await vraag(d, 'DeletePortMapping', {'NewRemoteHost': '', 'NewExternalPort': '$extern', 'NewProtocol': 'TCP'});
    } on IgdFout catch (f) {
      if (f.code != 714) rethrow;
    }
  }

  Future<String?> publiekAdres(IgdDienst d) async =>
      (await vraag(d, 'GetExternalIPAddress', const {}))['NewExternalIPAddress'];

  /// Hoe lang de modem al verbonden is. Daalt dat getal, dan is hij herstart.
  Future<int?> uptime(IgdDienst d) async => int.tryParse((await vraag(d, 'GetStatusInfo', const {}))['NewUptime'] ?? '');

  static String _xml(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  static String _vanXml(String s) =>
      s.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&amp;', '&');
}
