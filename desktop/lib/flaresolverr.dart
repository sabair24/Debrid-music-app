/// Cloudflare laten oplossen door FlareSolverr.
///
/// **Waarom dit bestaat.** RuTracker staat achter een Cloudflare-uitdaging. De app komt daar langs
/// met een `cf_clearance`-koekje, en dat koekje kwam tot nu toe uit Chrome: Saber opende de
/// netwerktab, koos "Kopieer als cURL" en plakte de hele regel in de instellingen. Dat werkt, maar
/// het koekje verloopt — gebonden aan IP én User-Agent — en dan begint dat plakwerk opnieuw, meestal
/// midden in iets anders.
///
/// FlareSolverr is een programmaatje met een echte Chromium erin dat precies één ding doet: een
/// pagina ophalen en de uitdaging onderweg oplossen. Wat eruit komt zijn de koekjes van die sessie,
/// inclusief `cf_clearance`, plus de User-Agent die erbij hoort. Draait op deze pc, op poort 8191.
///
/// **Wat het NIET doet.** Inloggen. Er komt geen `bb_session` uit — dat koekje zegt dat jíj het bent
/// en dat weet FlareSolverr niet. Vandaar dat de app het nieuwe `cf_clearance` samenvoegt met wat er
/// al stond in plaats van alles te vervangen; zie `RuTrackerService.voegKoekjesSamen`.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Wat FlareSolverr terugbracht van een pagina.
class FsUitkomst {
  /// Alle koekjes op één regel, zoals een browser ze stuurt.
  final String cookie;

  /// De User-Agent van de Chromium die het opgehaald heeft. **Hoort bij het koekje**: Cloudflare
  /// bindt `cf_clearance` aan de UA die hem kreeg, dus wie een ander kenmerk meestuurt heeft er
  /// niets aan.
  final String ua;

  /// De HTTP-status die de pagina zelf gaf.
  final int status;

  const FsUitkomst(this.cookie, this.ua, this.status);

  bool get heeftClearance => cookie.contains('cf_clearance=');
}

class FlareSolverr {
  FlareSolverr(this.adres, {http.Client? client}) : _http = client ?? http.Client();

  /// Waar hij luistert, bijvoorbeeld `http://127.0.0.1:8191`.
  final String adres;
  final http.Client _http;

  static const standaardAdres = 'http://127.0.0.1:8191';

  bool get ingesteld => adres.trim().isNotEmpty;

  Uri get _endpoint {
    var b = adres.trim();
    if (!b.startsWith('http://') && !b.startsWith('https://')) b = 'http://$b';
    b = b.replaceFirst(RegExp(r'/+$'), '');
    // Wat de gebruiker er zelf al bij plakte niet twee keer zetten.
    if (b.endsWith('/v1')) return Uri.parse(b);
    return Uri.parse('$b/v1');
  }

  /// Draait hij? Eén korte vraag, zodat het scherm het verschil kan zeggen tussen "niet
  /// geïnstalleerd" en "wel geïnstalleerd maar hij doet niets".
  Future<bool> leeft() async {
    if (!ingesteld) return false;
    try {
      final basis = _endpoint.toString().replaceFirst(RegExp(r'/v1$'), '/');
      final r = await _http.get(Uri.parse(basis)).timeout(const Duration(seconds: 5));
      return r.statusCode == 200 && r.body.contains('FlareSolverr');
    } catch (_) {
      return false;
    }
  }

  /// Haal [url] op mét opgeloste uitdaging.
  ///
  /// De wachttijd is ruim: een uitdaging oplossen kost een echte browser seconden, en een te krappe
  /// klok levert precies dan niets op wanneer je het nodig hebt.
  Future<FsUitkomst?> haal(String url, {Duration limiet = const Duration(seconds: 75)}) async {
    if (!ingesteld) return null;
    try {
      final r = await _http
          .post(_endpoint,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'cmd': 'request.get',
                'url': url,
                'maxTimeout': limiet.inMilliseconds,
              }))
          .timeout(limiet + const Duration(seconds: 10));
      return leesAntwoord(utf8.decode(r.bodyBytes, allowMalformed: true));
    } catch (_) {
      return null;
    }
  }

  /// Het antwoord uitpakken. Apart en openbaar: dit is het stuk dat stil verkeerd kan gaan — één
  /// veld dat anders heet en de app bewaart een leeg koekje over een werkend heen.
  static FsUitkomst? leesAntwoord(String lichaam) {
    try {
      final j = jsonDecode(lichaam);
      if (j is! Map) return null;
      if ((j['status'] ?? '') != 'ok') return null;
      final s = j['solution'];
      if (s is! Map) return null;

      final koekjes = <String>[];
      for (final c in (s['cookies'] as List?) ?? const []) {
        if (c is! Map) continue;
        final naam = '${c['name'] ?? ''}';
        final waarde = '${c['value'] ?? ''}';
        if (naam.isEmpty || waarde.isEmpty) continue;
        koekjes.add('$naam=$waarde');
      }
      return FsUitkomst(
        koekjes.join('; '),
        '${s['userAgent'] ?? ''}',
        int.tryParse('${s['status'] ?? 0}') ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
