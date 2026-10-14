/// Wat een toestel als downloadbron mag meesturen.
///
/// **Waarom dit er is.** Een zoekresultaat dat een toestel terugstuurt (`/api/online/download`,
/// `/api/online/tracklist`, of een download uit de wachtrij in de cloud) draagt een `torrentUrl`. De
/// pc haalde die tot 14-10-2026 op met `curl`, **met je RuTracker-koekje erbij**, naar welk adres er
/// ook stond. Wie een sleutel had, kon de pc zo naar elk adres laten gaan — ook een adres op je
/// eigen netwerk — en het koekje naar een eigen server laten sturen. Nu gaat de pc alleen nog naar
/// de twee adressen die hij zelf ooit uitgeeft: het RuTracker-downloadadres van een onderwerp, en dat
/// van Redacted. Al het andere wordt geweigerd, met een zin.
library;

const _rutrackerHost = 'rutracker.org';
const _redactedHosts = {'redacted.sh', 'redacted.ch'};

/// Het enige RuTracker-adres waar de pc met je koekje heen gaat, opnieuw opgebouwd:
/// `https://rutracker.org/forum/dl.php?t=<cijfers>`. Null voor al het andere.
///
/// Opnieuw opbouwen en niet het meegestuurde teruggeven: zo telt alleen het onderwerpnummer, en kan
/// er niets meeliften (een gebruikersnaam voor de host, een tweede parameter, een andere poort).
String? rutrackerTorrentAdres(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !_alleenHttps(u) || u.host != _rutrackerHost) return null;
  if (u.path != '/forum/dl.php') return null;
  final q = u.queryParametersAll;
  final t = q['t'];
  if (q.length != 1 || t == null || t.length != 1 || !RegExp(r'^\d{1,12}$').hasMatch(t.single)) return null;
  return 'https://$_rutrackerHost/forum/dl.php?t=${t.single}';
}

/// Het Redacted-downloadadres (`https://redacted.sh/ajax.php?action=download&id=<cijfers>`),
/// opnieuw opgebouwd, of null.
String? redactedTorrentAdres(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !_alleenHttps(u) || !_redactedHosts.contains(u.host)) return null;
  if (u.path != '/ajax.php') return null;
  final q = u.queryParameters;
  final id = q['id'] ?? '';
  if (q.length != 2 || q['action'] != 'download' || !RegExp(r'^\d{1,12}$').hasMatch(id)) return null;
  return 'https://${u.host}/ajax.php?action=download&id=$id';
}

bool _alleenHttps(Uri u) =>
    u.scheme == 'https' && u.userInfo.isEmpty && u.fragment.isEmpty && (!u.hasPort || u.port == 443);

/// Een magneetlink zoals een torrentbron hem geeft: `magnet:?…`, zonder stuurtekens.
///
/// Een gewone spatie mag: een externe zoekbron (`magnetUrl` in search.dart) zet soms een
/// onvercijferde naam achter `dn=`, en aria2 en TorBox krijgen de magneet als tekst, niet op een
/// opdrachtregel.
bool geldigeMagneet(String m) =>
    m.length <= 8192 && m.startsWith('magnet:?') && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(m);

/// Null als een meegestuurd zoekresultaat bruikbaar is; anders de zin waarom de pc het weigert.
///
/// Wat leeg is, mag leeg zijn (een TorBox-resultaat heeft vaak geen `torrentUrl`); wat er staat,
/// moet kloppen.
String? downloadBronFout(Map<String, dynamic> body) {
  final t = body['torrentUrl'];
  final m = body['magnet'];
  final h = body['hash'];
  if (t != null && t is! String || m != null && m is! String || h != null && h is! String) {
    return 'Dat zoekresultaat is niet te lezen.';
  }
  final url = (t as String?)?.trim() ?? '';
  if (url.isNotEmpty && rutrackerTorrentAdres(url) == null && redactedTorrentAdres(url) == null) {
    return 'Dat torrentadres komt niet van RuTracker of Redacted; de pc haalt het niet op.';
  }
  final magneet = (m as String?)?.trim() ?? '';
  if (magneet.isNotEmpty && !geldigeMagneet(magneet)) {
    return 'Dat is geen magneetlink; de pc start hem niet.';
  }
  final hash = (h as String?)?.trim() ?? '';
  if (hash.isNotEmpty && !RegExp(r'^[A-Za-z0-9]{1,64}$').hasMatch(hash)) {
    return 'Die torrent-hash klopt niet; de pc start hem niet.';
  }
  return null;
}
