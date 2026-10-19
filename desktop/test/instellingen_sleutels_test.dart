// Instellingen (gsm, 18-10-2026): sleutels stonden onverhuld in beeld, en een gsm zei "Deze pc kan zelf
// geen torrents halen" terwijl de pc dat prima kon.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final hoofd = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

  test('elke sleutel en elk wachtwoord staat verborgen, met een oogje om hem te tonen', () {
    for (final veld in [
      "_field('TorBox API-sleutel', _torbox, obscure: true)",
      "_field('Discogs token', _discogs, obscure: true)",
      "_field('Last.fm API-sleutel', _lastfm, obscure: true)",
      "_field('AI-sleutel (Anthropic) — voor een radio uit een zin', _anthropic, obscure: true)",
      "_field('AcoustID APPLICATION-sleutel (herkennen op geluid)', _acoustid, obscure: true)",
      "_field('Soulseek wachtwoord', _slskPass, obscure: true)",
      "_field('RuTracker wachtwoord', _rtPass, obscure: true)",
    ]) {
      expect(hoofd, contains(veld));
    }
    expect(hoofd, contains('obscureText: verborgen,'));
    expect(hoofd, contains("tooltip: verborgen ? 'Tonen' : 'Verbergen',"));
  });

  test('de keuze voor torrents alleen op de pc, waar aria2c draait', () {
    expect(hoofd, contains('if (_isDesktop) const TorrentmotorKeuze(),'));
  });

  test('de zin naast "Op andere uitgaves" loopt niet over de rand', () {
    final i = hoofd.indexOf("Text('niet op jouw persing, wel op deze plaat',");
    expect(i, greaterThan(0));
    expect(hoofd.substring(i - 40, i), contains('Flexible('));
    expect(hoofd.substring(i, i + 160), contains('overflow: TextOverflow.ellipsis'));
  });
}
