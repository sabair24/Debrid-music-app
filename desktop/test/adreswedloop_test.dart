import 'dart:async';

import 'package:debridmusic/lan/adreswedloop.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stap 4 van "verbinden zoals Roon ARC" (14-10-2026): alle adressen tegelijk, de juiste pc wint,
/// en thuis gaat voor als het snel genoeg is. Alles in nep-tijd: de klok is van de toets.
final _thuis = Uri.parse('http://192.168.0.117:47820');
final _ts = Uri.parse('http://100.97.101.113:47820');
final _ander = Uri.parse('http://94.110.3.4:47821');

/// Een nep-pc per adres: na [ms] antwoordt hij met [id], of nooit (null).
Future<ServerHealth?> Function(Uri, Duration) _pcs(Map<Uri, (int ms, String? id)> wat, List<Uri> gevraagd) =>
    (u, limiet) {
      gevraagd.add(u);
      final w = wat[u];
      if (w == null || w.$2 == null) return Completer<ServerHealth?>().future; // hangt
      return Future.delayed(Duration(milliseconds: w.$1), () => ServerHealth(name: 'pc', serverId: w.$2!));
    };

void main() {
  test('adresSoort', () {
    expect(adresSoort(_thuis), AdresSoort.thuis);
    expect(adresSoort(Uri.parse('http://10.0.0.5:47820')), AdresSoort.thuis);
    expect(adresSoort(_ts), AdresSoort.tailscale);
    expect(adresSoort(Uri.parse('http://saber-pc.tail1234.ts.net:47820')), AdresSoort.tailscale);
    expect(adresSoort(_ander), AdresSoort.anders);
  });

  test('kandidaten: thuis meteen, Tailscale 400 ms later', () {
    final k = kandidatenVoor([_ts, _thuis]);
    expect(k.firstWhere((x) => x.adres == _thuis).start, Duration.zero);
    expect(k.firstWhere((x) => x.adres == _ts).start, const Duration(milliseconds: 400));
  });

  test('buiten: thuis antwoordt niet, Tailscale wint zonder op de volle poging van thuis te wachten', () {
    fakeAsync((t) {
      final gevraagd = <Uri>[];
      WedloopUitslag? u;
      adresWedloop(kandidatenVoor([_thuis, _ts]),
              vraag: _pcs({_thuis: (0, null), _ts: (120, 'pc-1')}, gevraagd), verwachtServerId: 'pc-1')
          .then((x) => u = x);
      t.elapse(const Duration(milliseconds: 519));
      expect(u, isNull, reason: 'Tailscale antwoordde op 520 ms, nog niet');
      t.elapse(const Duration(milliseconds: 2));
      expect(u?.winnaar, _ts, reason: 'binnen 0,6 s, niet pas na de 3 s van het thuisadres');
      expect(gevraagd, [_thuis, _ts]);
    });
  });

  test('thuis gaat voor als het binnen 500 ms antwoordt, ook als Tailscale eerder is', () {
    fakeAsync((t) {
      WedloopUitslag? u;
      // Tailscale begint op 400 en antwoordt op 410; thuis antwoordt op 480.
      adresWedloop(kandidatenVoor([_thuis, _ts]),
              vraag: _pcs({_thuis: (480, 'pc-1'), _ts: (10, 'pc-1')}, []), verwachtServerId: 'pc-1')
          .then((x) => u = x);
      t.elapse(const Duration(milliseconds: 600));
      expect(u?.winnaar, _thuis);
    });
  });

  test('antwoordt thuis pas na 500 ms, dan wint Tailscale op 500 ms', () {
    fakeAsync((t) {
      WedloopUitslag? u;
      adresWedloop(kandidatenVoor([_thuis, _ts]),
              vraag: _pcs({_thuis: (900, 'pc-1'), _ts: (10, 'pc-1')}, []), verwachtServerId: 'pc-1')
          .then((x) => u = x);
      t.elapse(const Duration(milliseconds: 499));
      expect(u, isNull);
      t.elapse(const Duration(milliseconds: 2));
      expect(u?.winnaar, _ts);
    });
  });

  test('een andere pc op hetzelfde adres (vreemd wifi) wint nooit', () {
    fakeAsync((t) {
      WedloopUitslag? u;
      adresWedloop(kandidatenVoor([_thuis, _ts]),
              vraag: _pcs({_thuis: (5, 'pc-van-de-buren'), _ts: (50, 'pc-1')}, []), verwachtServerId: 'pc-1')
          .then((x) => u = x);
      t.elapse(const Duration(seconds: 1));
      expect(u?.winnaar, _ts);
      expect(u?.verloop.join('\n'), contains('een andere pc (pc-van-de-buren)'));
    });
  });

  test('zonder bekende id telt elke pc die antwoordt (oude koppeling die hem nog leert)', () {
    fakeAsync((t) {
      WedloopUitslag? u;
      adresWedloop(kandidatenVoor([_thuis]), vraag: _pcs({_thuis: (5, 'pc-1')}, [])).then((x) => u = x);
      t.elapse(const Duration(milliseconds: 10));
      expect(u?.winnaar, _thuis);
      expect(u?.health?.serverId, 'pc-1');
    });
  });

  test('niets antwoordt: na 3 s per poging een duidelijk nee, met het verloop', () {
    fakeAsync((t) {
      WedloopUitslag? u;
      adresWedloop(kandidatenVoor([_thuis, _ts, _ander]), vraag: _pcs({}, [])).then((x) => u = x);
      t.elapse(const Duration(milliseconds: 3399));
      expect(u, isNull);
      t.elapse(const Duration(milliseconds: 2));
      expect(u?.winnaar, isNull);
      expect(u?.verloop, hasLength(3));
      expect(u?.verloop.every((r) => r.contains('geen antwoord')), isTrue);
    });
  });

  test('geen adressen: meteen nee', () async {
    final u = await adresWedloop(const [], vraag: (_, __) async => null);
    expect(u.winnaar, isNull);
  });
}
