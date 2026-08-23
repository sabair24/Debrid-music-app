import 'dart:convert';
import 'package:http/http.dart' as http;

import 'settings.dart';
import 'torbox.dart';

/// A CAPTCHA challenge RuTracker returned during login — shown to the user
/// (an image + a text answer), then submitted back with the login.
class RtCaptcha {
  final String imageUrl;
  final String sid;
  final String codeField; // e.g. cap_code_<hash>
  final String cookies; // cookies from the challenge response, resent with the answer
  const RtCaptcha(this.imageUrl, this.sid, this.codeField, this.cookies);
}

class RtLogin {
  final bool ok;
  final String? error;
  final RtCaptcha? captcha;
  const RtLogin.success()
      : ok = true,
        error = null,
        captcha = null;
  const RtLogin.failed(this.error)
      : ok = false,
        captcha = null;
  const RtLogin.needCaptcha(this.captcha)
      : ok = false,
        error = null;
}

/// RuTracker torrent source: form login (with CAPTCHA when asked) → cookie →
/// tracker.php search (scraped). The bb_session cookie is cached in settings.
class RuTrackerService {
  final AppSettings settings;
  RuTrackerService(this.settings);

  static const _base = 'https://rutracker.org/forum';
  static const _host = 'rutracker.org';
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) DebridMusic/0.1';

  bool get configured =>
      settings.rutrackerUser.trim().isNotEmpty && settings.rutrackerPass.isNotEmpty;

  /// Eén teken naar zijn byte in windows-1251, of null als die codetabel het niet kent.
  ///
  /// RuTracker is een cp1251-site: `login.php` leest wat je stuurt als windows-1251. Deze app
  /// stuurde UTF-8, en dat is op twee manieren fout. De knopwaarde `вход` kwam aan als twaalf bytes
  /// onzin in plaats van vier, en een wachtwoord met één letter met een accent erin werd verstuurd
  /// als andere bytes dan je intikte — waarna het nooit klopt, hoe zeker je ook van je wachtwoord
  /// bent.
  static int? cp1251Byte(int teken) {
    if (teken < 0x80) return teken; // ASCII is in beide tabellen hetzelfde
    if (teken >= 0x410 && teken <= 0x44F) return 0xC0 + (teken - 0x410); // А..я aaneengesloten
    if (teken == 0x401) return 0xA8; // Ё
    if (teken == 0x451) return 0xB8; // ё
    return null;
  }

  /// Een waarde klaar voor een formulier, op cp1251-bytes. Null als er een teken in staat dat die
  /// codetabel niet kent — dan is er niets te versturen en hoort dat gezegd te worden.
  ///
  /// Alles behalve de onbelaste tekens gaat er procentgecodeerd in, ook de spatie (`%20` en niet
  /// `+`, zodat een wachtwoord met een echte `+` erin niet stiekem een spatie wordt).
  static String? cp1251Form(String waarde) {
    const vrij = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~';
    final uit = StringBuffer();
    for (final teken in waarde.runes) {
      final b = cp1251Byte(teken);
      if (b == null) return null;
      final c = String.fromCharCode(teken);
      if (teken < 0x80 && vrij.contains(c)) {
        uit.write(c);
      } else {
        uit.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return uit.toString();
  }
  bool get loggedIn => settings.rutrackerCookie.isNotEmpty;

  Future<RtLogin> login({String? captchaAnswer, RtCaptcha? captcha}) async {
    if (!configured) return const RtLogin.failed('Geen RuTracker-login ingevuld');
    try {
      final naam = cp1251Form(settings.rutrackerUser.trim());
      final woord = cp1251Form(settings.rutrackerPass);
      if (naam == null || woord == null) {
        return const RtLogin.failed(
            'Je gebruikersnaam of wachtwoord bevat een teken dat RuTracker niet kent (hij werkt '
            'met de Russische codetabel). Alleen gewone letters, cijfers en leestekens komen daar '
            'ongeschonden aan.');
      }
      var body = 'login_username=$naam&login_password=$woord'
          '&login=${cp1251Form('вход')}';
      final headers = <String, String>{
        // Zonder charset: het lichaam is al procentgecodeerd op cp1251-bytes. Zou hier
        // `; charset=utf-8` bij komen — en dat gebeurt vanzelf als je `..body =` gebruikt in
        // plaats van `..bodyBytes =` — dan vertel je een cp1251-site het tegenovergestelde van
        // wat je stuurt.
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': _ua,
        // Een formulier dat van de site zelf komt heeft deze twee. Ze ontbraken.
        'Referer': '$_base/login.php',
        'Origin': 'https://$_host',
      };
      if (captcha != null && captchaAnswer != null) {
        final antwoord = cp1251Form(captchaAnswer) ?? '';
        body += '&cap_sid=${cp1251Form(captcha.sid) ?? ''}&${captcha.codeField}=$antwoord';
        if (captcha.cookies.isNotEmpty) headers['Cookie'] = captcha.cookies;
      }
      final req = http.Request('POST', Uri.parse('$_base/login.php'))
        ..followRedirects = false
        ..headers.addAll(headers)
        ..bodyBytes = ascii.encode(body);
      final client = http.Client();
      final resp = await http.Response.fromStream(await client.send(req))
          .timeout(const Duration(seconds: 20));
      client.close();

      final setCookie = resp.headers['set-cookie'] ?? '';
      final sess = RegExp(r'bb_session=([^;,\s]+)').firstMatch(setCookie);
      if (sess != null && sess.group(1)!.length > 8) {
        settings.rutrackerCookie = 'bb_session=${sess.group(1)}';
        await settings.save();
        return const RtLogin.success();
      }

      final html = latin1.decode(resp.bodyBytes, allowInvalid: true);
      final img = RegExp(r'src="((?:https?:)?//[^"]*captcha[^"]*)"').firstMatch(html);
      final sid = RegExp(r'name="cap_sid"\s+value="([^"]+)"').firstMatch(html);
      final field = RegExp(r'name="(cap_code_[^"]+)"').firstMatch(html);
      if (img != null && sid != null && field != null) {
        var url = img.group(1)!;
        if (url.startsWith('//')) url = 'https:$url';
        return RtLogin.needCaptcha(
            RtCaptcha(url, sid.group(1)!, field.group(1)!, _cookiesFrom(setCookie)));
      }
      // Hieronder stond één zin — "controleer je gegevens" — voor drie totaal verschillende
      // oorzaken: een fout wachtwoord, een blokkadepagina van je provider, en een RuTracker die
      // iets anders terugstuurt dan vroeger. Dat stuurt je precies de verkeerde kant op: je gaat je
      // wachtwoord zitten controleren terwijl de site niet eens bereikt is.
      //
      // Kregen we werkelijk RuTracker aan de lijn? Zijn eigen pagina's noemen zichzelf. Een
      // blokkadepagina van een provider doet dat niet.
      final lijktRuTracker = html.toLowerCase().contains('rutracker') ||
          resp.headers['set-cookie']?.contains('bb_') == true;
      if (!lijktRuTracker) {
        return RtLogin.failed(
            'Er antwoordde iets op $_host, maar het was RuTracker niet (${resp.statusCode}). '
            'Waarschijnlijk blokkeert je provider of je netwerk die site. Kun je '
            'https://$_host in je browser openen? Lukt dat ook niet, dan ligt het daar en niet '
            'aan je wachtwoord.');
      }
      return RtLogin.failed(
          'RuTracker wees de aanmelding af (${resp.statusCode}). Als je gebruikersnaam en '
          'wachtwoord kloppen, vraagt hij mogelijk om iets nieuws dat deze app nog niet meestuurt.');
    } catch (e) {
      // De uitzondering ZELF, en niet "geen verbinding". Het verschil tussen een naam die niet
      // opgezocht kan worden, een certificaat dat niet deugt en een verbinding die na twintig
      // seconden opgeeft is precies wat je wil weten, en dat werd hier weggegooid.
      return RtLogin.failed('Geen verbinding met $_host: $e');
    }
  }

  String _cookiesFrom(String setCookie) {
    final parts = <String>[];
    for (final m in RegExp(r'(bb_[a-z_]+)=([^;,\s]+)').allMatches(setCookie)) {
      parts.add('${m.group(1)}=${m.group(2)}');
    }
    return parts.join('; ');
  }

  /// True if the cached cookie still authenticates (tracker.php returns 200, not a 302 to login).
  Future<bool> verify() async {
    if (settings.rutrackerCookie.isEmpty) return false;
    try {
      final req = http.Request('GET', Uri.parse('$_base/tracker.php'))
        ..followRedirects = false
        ..headers['Cookie'] = settings.rutrackerCookie
        ..headers['User-Agent'] = _ua;
      final client = http.Client();
      final streamed = await client.send(req).timeout(const Duration(seconds: 12));
      await streamed.stream.drain<void>();
      client.close();
      return streamed.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Set when the session died and logging back in needs a human — a captcha.
  ///
  /// Read by the search UI so it can say so. Without it an expired session is indistinguishable
  /// from "RuTracker has nothing", which is exactly what it looked like: you search, you get
  /// nothing, and nowhere does it say you are logged out.
  RtCaptcha? pendingCaptcha;
  String lastError = '';

  Future<List<SearchResult>> search(String query, {bool allowRelogin = true}) async {
    if (!configured || settings.rutrackerCookie.isEmpty) return [];
    try {
      final req = http.Request(
          'GET', Uri.parse('$_base/tracker.php?nm=${Uri.encodeComponent(query)}'))
        ..followRedirects = false
        ..headers['Cookie'] = settings.rutrackerCookie
        ..headers['User-Agent'] = _ua;
      final client = http.Client();
      final resp =
          await http.Response.fromStream(await client.send(req)).timeout(const Duration(seconds: 15));
      client.close();
      if (resp.statusCode == 302) {
        // The session expired. RuTracker's cookie does not last forever, and nothing renewed it:
        // login() had exactly two callers, the button in Settings and a test. So the cookie was
        // dropped, an empty list came back, and the whole thing read as "it forgot my login".
        //
        // We hold the username and the password, so log in again and do the search over. Once —
        // `allowRelogin` stops a broken login from bouncing between the two forever.
        settings.rutrackerCookie = '';
        await settings.save(); // in memory only left a dead cookie on disk until some other save
        if (!allowRelogin) return [];

        final again = await login();
        if (again.ok) {
          pendingCaptcha = null;
          lastError = '';
          return search(query, allowRelogin: false);
        }
        // A captcha cannot be answered from here — but it CAN be said out loud.
        pendingCaptcha = again.captcha;
        lastError = again.captcha != null
            ? 'RuTracker vraagt om een captcha — log opnieuw in bij Instellingen.'
            : (again.error ?? 'RuTracker-login mislukt.');
        return [];
      }
      final html = latin1.decode(resp.bodyBytes, allowInvalid: true);
      final rows = _parseRows(html);
      // Fill missing infohashes from the topic page (top results only, concurrently).
      final need = rows.where((r) => r.hash == null).take(12).toList();
      await Future.wait(need.map((r) async => r.hash = await _hashFromTopic(r.topicId)));
      return rows
          .where((r) => r.hash != null)
          .map((r) => SearchResult(
                name: r.title,
                size: r.size,
                seeders: r.seeders,
                hash: r.hash!,
                magnet:
                    'magnet:?xt=urn:btih:${r.hash}&dn=${Uri.encodeComponent(r.title)}',
                source: 'RuTracker',
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<_Row> _parseRows(String html) {
    final out = <_Row>[];
    for (final m in RegExp(r'<tr[^>]*class="[^"]*hl-tr[^"]*"[\s\S]*?</tr>').allMatches(html)) {
      final h = m.group(0)!;
      final tid = RegExp(r'data-topic_id="(\d+)"').firstMatch(h)?.group(1);
      final title = RegExp(r'class="med tLink[^"]*"[^>]*>([\s\S]*?)</a>').firstMatch(h)?.group(1);
      if (tid == null || title == null) continue;
      final size = int.tryParse(
              RegExp(r'tor-size"[^>]*data-ts_text="(-?\d+)"').firstMatch(h)?.group(1) ?? '') ??
          0;
      final seed =
          int.tryParse(RegExp(r'class="seedmed"[^>]*>(\d+)').firstMatch(h)?.group(1) ?? '') ?? 0;
      final hash =
          RegExp(r'urn:btih:([a-fA-F0-9]{40})').firstMatch(h)?.group(1)?.toLowerCase();
      out.add(_Row(tid, _clean(title), size, seed, hash));
    }
    return out;
  }

  Future<String?> _hashFromTopic(String topicId) async {
    try {
      final r = await http.get(
        Uri.parse('$_base/viewtopic.php?t=$topicId'),
        headers: {'Cookie': settings.rutrackerCookie, 'User-Agent': _ua},
      ).timeout(const Duration(seconds: 12));
      final html = latin1.decode(r.bodyBytes, allowInvalid: true);
      return RegExp(r'urn:btih:([a-fA-F0-9]{40})').firstMatch(html)?.group(1)?.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  String _clean(String s) => s
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&nbsp;', ' ')
      .trim();
}

class _Row {
  final String topicId;
  final String title;
  final int size;
  final int seeders;
  String? hash;
  _Row(this.topicId, this.title, this.size, this.seeders, this.hash);
}
