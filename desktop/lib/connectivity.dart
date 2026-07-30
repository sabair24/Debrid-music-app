import 'package:http/http.dart' as http;

import 'json_body.dart';
import 'online.dart';
import 'rutracker.dart';
import 'settings.dart';
import 'torbox.dart';

enum ConnState { unknown, checking, ok, fail, absent }

class ConnResult {
  final ConnState state;
  final String detail;
  const ConnResult(this.state, [this.detail = '']);
}

/// Verifies the user's own service logins (TorBox / Discogs / Soulseek) so the
/// Settings panel can confirm "logged in with the right credentials".
class ConnectionChecker {
  final AppSettings settings;
  final TorBox torbox;
  final SoulseekService soulseek;
  final RuTrackerService rutracker;
  ConnectionChecker(this.settings, this.torbox, this.soulseek, this.rutracker);

  Future<ConnResult> torboxCheck() async {
    if (settings.torboxToken.trim().isEmpty) return const ConnResult(ConnState.absent, 'Geen sleutel ingevuld');
    try {
      return await torbox.verify()
          ? const ConnResult(ConnState.ok, 'Geldige API-sleutel')
          : const ConnResult(ConnState.fail, 'Ongeldige sleutel');
    } catch (_) {
      return const ConnResult(ConnState.fail, 'Geen verbinding');
    }
  }

  Future<ConnResult> discogsCheck() async {
    final tok = settings.discogsToken.trim();
    if (tok.isEmpty) return const ConnResult(ConnState.absent, 'Geen token ingevuld');
    const ua = 'DebridMusic/0.1 ( https://github.com/sabair24/Debrid-music-app )';
    final headers = {'Authorization': 'Discogs token=$tok', 'User-Agent': ua};

    // Checked against the endpoint the app ACTUALLY uses, not /oauth/identity.
    //
    // Identity is the obvious thing to test and the wrong one: it is a different service, and when
    // it was down with a 502 this check called a perfectly good token invalid while searching and
    // fetching releases both worked fine. A test that fails for something the app never does is
    // worse than no test — it sends you off replacing a key that was never the problem.
    try {
      final r = await http
          .get(
            Uri.parse('https://api.discogs.com/database/search?q=a&type=release&per_page=1'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        // The username is a nicety on top. If identity is having a bad day, say so plainly rather
        // than let it downgrade a working token.
        try {
          final id = await http
              .get(Uri.parse('https://api.discogs.com/oauth/identity'), headers: headers)
              .timeout(const Duration(seconds: 8));
          if (id.statusCode == 200) {
            final name = (jsonBody(id)['username'] ?? '') as String;
            if (name.isNotEmpty) return ConnResult(ConnState.ok, 'Ingelogd als $name');
          }
        } catch (_) {/* the token works; the name is decoration */}
        return const ConnResult(ConnState.ok, 'Token werkt');
      }
      return ConnResult(
        ConnState.fail,
        switch (r.statusCode) {
          401 => 'Token geweigerd. Discogs wil een PERSONAL ACCESS TOKEN — niet de Consumer Key '
              'of Secret. Instellingen → Developers → Generate new token.',
          403 => 'Discogs weigert de toegang (403). Meestal het verkeerde soort sleutel: het moet '
              'een personal access token zijn.',
          429 => 'Even te veel verzoeken (429). Je token is in orde; wacht een minuut.',
          >= 500 => 'Discogs zelf heeft een storing (${r.statusCode}). Je token is hier niet de '
              'oorzaak; later opnieuw proberen.',
          _ => 'Discogs antwoordde met ${r.statusCode}.',
        },
      );
    } catch (_) {
      return const ConnResult(ConnState.fail, 'Geen verbinding');
    }
  }

  Future<ConnResult> soulseekCheck() async {
    if (!soulseek.available) return const ConnResult(ConnState.absent, 'Geen login ingevuld');
    try {
      return await soulseek.verify()
          ? ConnResult(ConnState.ok, 'Ingelogd als ${settings.soulseekUser}')
          : const ConnResult(ConnState.fail, 'Login geweigerd');
    } catch (_) {
      return const ConnResult(ConnState.fail, 'Geen verbinding');
    }
  }

  /// RuTracker: valid only when a live session cookie authenticates. Returns
  /// [ConnState.fail] with a hint to log in (via the RuTracker "Inloggen" button)
  /// when credentials exist but there's no working session yet.
  Future<ConnResult> rutrackerCheck() async {
    if (!rutracker.configured) return const ConnResult(ConnState.absent, 'Geen login ingevuld');
    try {
      return await rutracker.verify()
          ? ConnResult(ConnState.ok, 'Ingelogd als ${settings.rutrackerUser}')
          : const ConnResult(ConnState.fail, 'Nog niet ingelogd — klik Inloggen');
    } catch (_) {
      return const ConnResult(ConnState.fail, 'Geen verbinding');
    }
  }
}
