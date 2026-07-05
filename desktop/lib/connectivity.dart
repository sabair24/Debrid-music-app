import 'dart:convert';
import 'package:http/http.dart' as http;

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
    try {
      final r = await http.get(
        Uri.parse('https://api.discogs.com/oauth/identity'),
        headers: {
          'Authorization': 'Discogs token=$tok',
          'User-Agent': 'DebridMusic/0.1 ( https://github.com/sabair24/Debrid-music-app )',
        },
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        final name = (jsonDecode(r.body)['username'] ?? '') as String;
        return ConnResult(ConnState.ok, name.isNotEmpty ? 'Ingelogd als $name' : 'Geldige token');
      }
      return const ConnResult(ConnState.fail, 'Ongeldige token');
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
