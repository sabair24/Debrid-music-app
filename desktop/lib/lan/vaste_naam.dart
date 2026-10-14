/// Eén vaste naam voor een nummer van de pc, los van het adres waarlangs je hem bereikt.
///
/// **Waarom.** Op een toestel was het pad van een nummer de stream-URL van de pc, mét zijn adres:
/// `http://192.168.0.117:47820/stream/<id>.flac`. Datzelfde pad is de sleutel van je offline kopie,
/// je wachtrij en je speelplek. Wissel je van adres — thuis de deur uit naar Tailscale, of straks
/// naar de eigen deur van de pc — dan heet elk nummer opeens anders: het offline album "staat er
/// niet", de wachtrij vindt zijn nummers niet terug. Stap 3 van "verbinden zoals Roon ARC"
/// (plan 14-10-2026).
///
/// Nu heet een nummer overal `http://pc.invalid/stream/<id>.<ext>`. Pas op het moment van afspelen
/// of ophalen wordt dat het echte adres van dat moment (`RemoteClient.authorized`). `.invalid` kan
/// nergens heen (RFC 2606): een pad dat per ongeluk niet vertaald wordt, faalt zichtbaar in plaats
/// van ergens anders te belanden.
library;

const kPcHost = 'pc.invalid';

/// De vaste naam voor een stream-pad uit de catalogus (`/stream/<id>.<ext>`).
String vastePcNaam(String streamPath) =>
    Uri(scheme: 'http', host: kPcHost, path: streamPath.startsWith('/') ? streamPath : '/$streamPath')
        .toString();

bool isVastePcNaam(String pad) => Uri.tryParse(pad)?.host == kPcHost;

/// Een pad zoals het vóór 14-10-2026 bewaard werd (met het adres van de pc erin) omgezet naar de
/// vaste naam. Al het andere — een bestand, een radiostroom, een TorBox-adres — blijft zoals het is.
///
/// "Van de pc" betekent: precies `/stream/<id>.<ext>`, en óf poort 47820, óf een adres dat alleen
/// de pc kan zijn (thuis, Tailscale, loopback). Een internetradio met `/stream/radio1.mp3` op poort
/// 80 valt daar buiten.
String normaliseerPcPad(String pad) {
  final u = Uri.tryParse(pad);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https') || u.host == kPcHost) return pad;
  final s = u.pathSegments;
  if (s.length != 2 || s[0] != 'stream' || !RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9]{1,6}$').hasMatch(s[1])) {
    return pad;
  }
  if (u.port != 47820 && !_isPcAdres(u.host)) return pad;
  return vastePcNaam(u.path);
}

bool _isPcAdres(String host) {
  if (host == 'localhost') return true;
  final d = host.split('.').map(int.tryParse).toList();
  if (d.length != 4 || d.any((x) => x == null || x < 0 || x > 255)) return false;
  final (a, b) = (d[0]!, d[1]!);
  return a == 127 ||
      a == 10 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      (a == 100 && b >= 64 && b <= 127);
}
