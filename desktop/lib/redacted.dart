/// Redacted: een besloten tracker die alleen over muziek gaat, en bijna alles in lossless heeft.
///
/// **Waarom deze bron anders is dan de rest.** Pirate Bay, Knaben en BitSearch zijn open indexen met
/// verouderde tellers; gemeten op 24-08-2026 was van acht "seeded" treffers er één simpelweg dood.
/// Redacted is besloten: je hebt er een eigen account, elke uitgave is beschreven (formaat,
/// codering, bron) en de zwermen leven. Daar staat tegenover dat het account regels heeft, en die
/// staan hieronder bij [RedactedApi.seedWaarschuwing].
///
/// **Hoe de app erbij komt.** Niet door in te loggen of te schrapen, maar met de API-sleutel die je
/// zelf in je profiel aanmaakt (Settings → Access Settings → Create an API key, met de rechten
/// "Torrents" en "User"). Die sleutel gaat als `Authorization`-kop mee. Zo doet de app precies wat
/// jij met de hand ook zou doen, en niets meer.
///
/// Het uitpluizen van het antwoord staat los van het ophalen: dat is het stuk dat stil fout gaat, en
/// zo is het te toetsen zonder account en zonder net.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'search.dart';
import 'torbox.dart';

/// Wat Redacted over één uitgave vertelt, voor zover de app het gebruikt.
class RedUitgave {
  final int torrentId;
  final String artiest;
  final String album;
  final int jaar;

  /// `FLAC`, `MP3`, …
  final String formaat;

  /// `Lossless`, `24bit Lossless`, `320`, `V0 (VBR)`, …
  final String codering;

  /// `CD`, `WEB`, `Vinyl`, `SACD`, …
  final String bron;
  final int grootte;
  final int seeders;
  final int leechers;

  /// Heeft de tracker dit als "gouden" of "zilveren" uitgave gemerkt (perfecte rip)?
  final bool keurmerk;

  const RedUitgave({
    required this.torrentId,
    required this.artiest,
    required this.album,
    required this.jaar,
    required this.formaat,
    required this.codering,
    required this.bron,
    required this.grootte,
    required this.seeders,
    required this.leechers,
    this.keurmerk = false,
  });

  bool get isLossless => codering.toLowerCase().contains('lossless');
  bool get isHiRes => codering.toLowerCase().contains('24bit');

  /// De naam zoals hij in de trefferlijst komt te staan.
  ///
  /// Bewust in de vorm die de rest van de app al kent — artiest, album, jaartal, formaat — want de
  /// kwaliteitszeef en de ontdubbeling lezen die naam. Een eigen vorm zou hier stil doorwerken tot
  /// in de albumindeling.
  String get naam {
    final delen = [
      if (artiest.isNotEmpty) artiest,
      if (album.isNotEmpty) '- $album',
      if (jaar > 0) '($jaar)',
      if (formaat.isNotEmpty) formaat,
      if (codering.isNotEmpty) codering,
      if (bron.isNotEmpty) '[$bron]',
      if (keurmerk) '[keurmerk]',
    ];
    return delen.join(' ');
  }
}

class RedactedApi {
  RedactedApi(this.sleutel, {http.Client? client, String? basis})
      : _http = client ?? http.Client(),
        basis = basis ?? standaardBasis;

  final String Function() sleutel;
  final http.Client _http;
  final String basis;

  static const standaardBasis = 'https://redacted.sh';

  /// **Lees dit voordat je van Redacted haalt.**
  ///
  /// Een besloten tracker houdt bij wat je binnenhaalt en wat je teruggeeft. Deze app zet aria2 op
  /// `--seed-time=0` — klaar is klaar — en dat is op een open tracker beleefd genoeg, maar op
  /// Redacted levert het "hit and run" op, en daar staat verlies van je account op.
  ///
  /// Vandaar dat er bij een Redacted-download wél geseed wordt, zolang je dat in de instellingen
  /// laat staan. Zie `AppSettings.seedUren`.
  static const seedWaarschuwing =
      'Redacted is een besloten tracker: wat je binnenhaalt hoor je ook een tijd terug te delen. '
      'Zet je het seeden uit, dan riskeer je je account.';

  bool get ingesteld => sleutel().trim().isNotEmpty;

  Map<String, String> get _koppen => {
        // Redacted verwacht de sleutel kaal in deze kop, zonder "Bearer" ervoor.
        'Authorization': sleutel().trim(),
        'Accept': 'application/json',
      };

  Uri _adres(Map<String, String> vraag) =>
      Uri.parse('$basis/ajax.php').replace(queryParameters: vraag);

  /// Zoekt uitgaven. Alleen wat de app kan gebruiken komt terug.
  Future<List<SearchResult>> zoek(String vraag, {Duration limiet = const Duration(seconds: 11)}) async {
    if (!ingesteld) return const [];
    final r = await _http
        .get(_adres({'action': 'browse', 'searchstr': vraag}), headers: _koppen)
        .timeout(limiet);
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw 'Redacted wees de API-sleutel af (${r.statusCode}). Klopt hij nog, en heeft hij het '
          'recht "Torrents"?';
    }
    if (r.statusCode != 200) throw 'Redacted antwoordde met ${r.statusCode}';
    return leesZoekantwoord(utf8.decode(r.bodyBytes, allowMalformed: true), basis: basis);
  }

  /// Het `.torrent`-bestand van één uitgave. Draagt jouw passkey — dus niet doorgeven.
  Future<List<int>?> torrentBestand(int torrentId,
      {Duration limiet = const Duration(seconds: 30)}) async {
    if (!ingesteld) return null;
    try {
      final r = await _http
          .get(_adres({'action': 'download', 'id': '$torrentId'}), headers: _koppen)
          .timeout(limiet);
      if (r.statusCode != 200) return null;
      // Een torrent begint met `d` (bencode). Komt er JSON terug, dan is dat een foutmelding en
      // geen bestand — en die mag niet als lege torrent doorgaan.
      final bytes = r.bodyBytes;
      if (bytes.isEmpty || bytes.first != 0x64) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Werkt de sleutel? Geeft de zin die in Instellingen op het scherm komt.
  Future<({bool ok, String reden})> proef() async {
    if (!ingesteld) return (ok: false, reden: 'Vul eerst je API-sleutel in.');
    try {
      final r = await _http
          .get(_adres({'action': 'index'}), headers: _koppen)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 401 || r.statusCode == 403) {
        return (ok: false, reden: 'Redacted wees de sleutel af (${r.statusCode}).');
      }
      if (r.statusCode != 200) return (ok: false, reden: 'Redacted antwoordde met ${r.statusCode}.');
      final j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
      if (j is! Map || j['status'] != 'success') {
        return (ok: false, reden: 'Redacted gaf geen geldig antwoord op de proef.');
      }
      final naam = '${(j['response'] as Map?)?['username'] ?? ''}';
      return (ok: true, reden: naam.isEmpty ? 'Verbonden.' : 'Verbonden als $naam.');
    } on TimeoutException {
      return (ok: false, reden: 'Geen antwoord binnen vijftien seconden.');
    } catch (e) {
      return (ok: false, reden: '$e');
    }
  }
}

/// De `browse`-uitkomst uitpluizen.
///
/// Redacted geeft groepen (een album) met daarin `torrents` (de uitgaven ervan: FLAC, MP3, vinyl,
/// web). Elke uitgave wordt een eigen treffer, want dat is de keuze die de gebruiker maakt.
///
/// Zuiver: tekst in, treffers uit. Zo valt dit te toetsen op een bewaard antwoord — het enige dat
/// hier vóór het uitgeven na te meten valt, want de tracker is besloten.
List<SearchResult> leesZoekantwoord(String lichaam, {String basis = RedactedApi.standaardBasis}) {
  final uit = <SearchResult>[];
  dynamic j;
  try {
    j = jsonDecode(lichaam);
  } catch (_) {
    return uit;
  }
  if (j is! Map || j['status'] != 'success') return uit;
  final resultaten = ((j['response'] as Map?)?['results'] as List?) ?? const [];

  for (final g in resultaten) {
    if (g is! Map) continue;
    final artiest = '${g['artist'] ?? ''}';
    final album = '${g['groupName'] ?? ''}';
    final jaar = int.tryParse('${g['groupYear'] ?? 0}') ?? 0;

    for (final t in (g['torrents'] as List?) ?? const []) {
      if (t is! Map) continue;
      final id = int.tryParse('${t['torrentId'] ?? 0}') ?? 0;
      if (id <= 0) continue;
      final u = RedUitgave(
        torrentId: id,
        artiest: artiest,
        album: album,
        jaar: jaar,
        formaat: '${t['format'] ?? ''}',
        codering: '${t['encoding'] ?? ''}',
        bron: '${t['media'] ?? ''}',
        grootte: int.tryParse('${t['size'] ?? 0}') ?? 0,
        seeders: int.tryParse('${t['seeders'] ?? 0}') ?? 0,
        leechers: int.tryParse('${t['leechers'] ?? 0}') ?? 0,
        keurmerk: t['hasLog'] == true && t['logScore'] == 100,
      );
      uit.add(SearchResult(
        name: u.naam,
        size: u.grootte,
        seeders: u.seeders,
        leechers: u.leechers,
        // Redacted geeft de infohash niet in `browse`. Dat hoeft ook niet: het torrentbestand komt
        // hier vandaan, en dáár staat hij in. De app leest hem straks uit het bestand zelf.
        hash: '',
        magnet: '',
        source: 'Redacted',
        torrentUrl: '$basis/ajax.php?action=download&id=$id',
      ));
    }
  }
  return uit;
}

/// Is dit een adres van Redacted? Dan moet de API-sleutel mee, en kan curl er niet zomaar heen.
bool isRedactedAdres(String url) =>
    url.contains('redacted.sh/ajax.php') || url.contains('redacted.ch/ajax.php');

/// Het torrent-id uit zo'n adres.
int redactedIdUit(String url) =>
    int.tryParse(RegExp(r'[?&]id=(\d+)').firstMatch(url)?.group(1) ?? '') ?? 0;

/// De bron zoals de zoekverdeler hem kent.
class RedactedSource implements SearchSource {
  RedactedSource(this.api);
  final RedactedApi api;

  @override
  String get id => 'redacted';

  @override
  Future<List<SearchResult>> search(String query) async {
    if (!api.ingesteld) return const [];
    return api.zoek(query);
  }
}
