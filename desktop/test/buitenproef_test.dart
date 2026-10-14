/// "Test buitenverbinding" (stap 8.2 van "verbinden zoals Roon ARC", 14-10-2026): welke deur, welke
/// doelen, en wat de uitslag zegt. Het verzoek over mobiele data zelf zit in Kotlin (`Buitenproef.kt`)
/// en wordt aan de kabel nagemeten.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/buitenproef.dart';
import 'package:debridmusic/lan/verbindingsstand.dart';

void main() {
  final deur = Uri.parse('https://81.82.83.84:47821');
  final d = buitenDoelen(deur);

  test('de deur: https naar het internet, niet thuis en niet Tailscale', () {
    expect(publiekeDeur(['http://192.168.0.117:47820', 'https://192.168.0.117:47822', 'http://100.97.101.113:47820', '$deur']), deur);
    expect(publiekeDeur(['https://100.97.101.113:47822', 'http://81.82.83.84:47820']), isNull,
        reason: 'Tailscale is geen deur, en onversleuteld nooit');
  });

  test('de doelen: de deur, en 47820 en 47822 op hetzelfde publieke adres', () {
    expect(d.deur, 'https://81.82.83.84:47821/health');
    expect(d.http, 'http://81.82.83.84:47820/health');
    expect(d.tls, 'https://81.82.83.84:47822/health');
  });

  test('gelukt alleen als de deur antwoordt en 47820/47822 zwijgen', () {
    expect(buitenUitslag({d.deur: 'antwoordt', d.http: 'geen', d.tls: 'geen'}, d).gelukt, isTrue);
    final open = buitenUitslag({d.deur: 'antwoordt', d.http: 'status:401', d.tls: 'geen'}, d);
    expect(open.gelukt, isFalse);
    expect(open.rood, isTrue, reason: 'ook een 401 op 47820 betekent: die poort is van buiten bereikbaar');
    expect(open.zin, contains('47820'));
    expect(buitenUitslag({d.deur: 'antwoordt', d.http: 'geen', d.tls: 'ander-certificaat'}, d).rood, isTrue);
  });

  test('van buitenaf = versleuteld langs de eigen deur; thuis en Tailscale niet', () {
    expect(vanBuitenaf(deur), isTrue);
    expect(vanBuitenaf(Uri.parse('https://192.168.0.117:47822')), isFalse);
    expect(vanBuitenaf(Uri.parse('https://100.97.101.113:47822')), isFalse);
    expect(vanBuitenaf(Uri.parse('http://81.82.83.84:47820')), isFalse, reason: 'onversleuteld van buiten bestaat niet');
    expect(vanBuitenaf(null), isFalse);
  });

  test('de andere uitslagen in gewone taal', () {
    expect(buitenUitslag({'fout': 'geen-mobiel'}, d).zin, contains('mobiele data'));
    expect(buitenUitslag({d.deur: 'geen', d.http: 'geen', d.tls: 'geen'}, d).zin, contains('Bereikbaar van buitenaf'));
    expect(buitenUitslag({d.deur: 'ander-certificaat', d.http: 'geen', d.tls: 'geen'}, d).rood, isTrue);
  });
}
