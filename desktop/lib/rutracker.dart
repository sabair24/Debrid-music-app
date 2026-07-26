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
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) DebridMusic/0.1';

  bool get configured =>
      settings.rutrackerUser.trim().isNotEmpty && settings.rutrackerPass.isNotEmpty;
  bool get loggedIn => settings.rutrackerCookie.isNotEmpty;

  Future<RtLogin> login({String? captchaAnswer, RtCaptcha? captcha}) async {
    if (!configured) return const RtLogin.failed('Geen RuTracker-login ingevuld');
    try {
      var body = 'login_username=${Uri.encodeQueryComponent(settings.rutrackerUser.trim())}'
          '&login_password=${Uri.encodeQueryComponent(settings.rutrackerPass)}'
          '&login=${Uri.encodeQueryComponent('вход')}';
      final headers = <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': _ua,
      };
      if (captcha != null && captchaAnswer != null) {
        body += '&cap_sid=${Uri.encodeQueryComponent(captcha.sid)}'
            '&${captcha.codeField}=${Uri.encodeQueryComponent(captchaAnswer)}';
        if (captcha.cookies.isNotEmpty) headers['Cookie'] = captcha.cookies;
      }
      final req = http.Request('POST', Uri.parse('$_base/login.php'))
        ..followRedirects = false
        ..headers.addAll(headers)
        ..body = body;
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
      return const RtLogin.failed('Login geweigerd — controleer je gegevens.');
    } catch (_) {
      return const RtLogin.failed('Geen verbinding met RuTracker.');
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
