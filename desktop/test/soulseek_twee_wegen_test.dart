// Twee wegen naar een uploader (soulseek.dart, `_transfer`): eerst rechtstreeks met een korte kans
// (`kRechtstreeksGeduld`), daarna de server die de uploader ons laat bellen — na elkaar, niet tegelijk.
//
// Gemeten op de pc (20-10-2026): met 8 s rechtstreeks (tot 3.9.523) stuurden de winnaars bij de trage
// nummers pas na 9 à 10 s, want een uploader achter een firewall is alleen langs de server te bereiken.
// Beide wegen tegelijk na 1 s (3.9.524) leverde langs de server niets meer op: twee van de vier vroege
// wedlopen zonder één byte. Dus weer na elkaar, met 3 s.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final bron = File('lib/soulseek.dart').readAsStringSync();
  final t = bron.substring(bron.indexOf('  Future<SlskResult> _transfer('));

  test('een korte rechtstreekse kans: drie seconden, niet acht', () {
    expect(bron, contains('const kRechtstreeksGeduld = Duration(seconds: 3);'));
    expect(t, contains('peer = await Socket.connect(ip, port, timeout: kRechtstreeksGeduld);'));
    expect(t, isNot(contains('peer = await Socket.connect(ip, port, timeout: const Duration(seconds: 8));')));
  });

  test('na elkaar: de server pas als rechtstreeks niets gaf — nooit twee lijnen naar dezelfde uploader', () {
    final rechtstreeks = t.indexOf('peer = await Socket.connect(ip, port, timeout: kRechtstreeksGeduld);');
    final viaServer = t.indexOf('final rev = await _reverseConnect(file.username);');
    expect(rechtstreeks, greaterThan(0));
    expect(viaServer, greaterThan(rechtstreeks));
    expect(t.substring(rechtstreeks, viaServer), contains('} else {'),
        reason: 'de server alleen in de tak zonder rechtstreekse verbinding');
    expect(bron, isNot(contains('eersteVerbinding')), reason: 'beide tegelijk leverde langs de server niets op');
    expect(viaServer, lessThan(t.indexOf('psend(_message(43, (_W()..str(file.filename)).bytes())); // QueueUpload')));
  });
}
