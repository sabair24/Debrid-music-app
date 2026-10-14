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

  group('versleuteld gaat voor (stap 8.1)', () {
    final thuisTls = Uri.parse('https://192.168.0.117:47822');
    final tsTls = Uri.parse('https://100.97.101.113:47822');
    // 'NEE' = weigert na zoveel ms (poort dicht); null = hangt.
    Future<ServerHealth?> Function(Uri, Duration) pcs(Map<Uri, (int ms, String? id)> wat) => (u, limiet) {
          final w = wat[u];
          if (w == null || w.$2 == null) return Completer<ServerHealth?>().future;
          return Future.delayed(
              Duration(milliseconds: w.$1), () => w.$2 == 'NEE' ? null : ServerHealth(name: 'pc', serverId: w.$2!));
        };

    test('thuis: 47820 is sneller, toch wint 47822', () {
      fakeAsync((t) {
        WedloopUitslag? u;
        adresWedloop(kandidatenVoor([_thuis, thuisTls]),
                vraag: pcs({_thuis: (2, 'pc-1'), thuisTls: (40, 'pc-1')}), verwachtServerId: 'pc-1')
            .then((x) => u = x);
        t.elapse(const Duration(milliseconds: 30));
        expect(u, isNull, reason: 'niet onversleuteld winnen zolang de versleutelde nog open staat');
        t.elapse(const Duration(milliseconds: 20));
        expect(u?.winnaar, thuisTls);
        expect(u?.verloop.join('\n'), contains('versleuteld 192.168.0.117:47822'));
      });
    });

    test('versleuteld via Tailscale wint van onversleuteld thuis', () {
      fakeAsync((t) {
        WedloopUitslag? u;
        adresWedloop(kandidatenVoor([_thuis, thuisTls, tsTls]),
                vraag: pcs({_thuis: (2, 'pc-1'), thuisTls: (3, 'NEE'), tsTls: (30, 'pc-1')}), verwachtServerId: 'pc-1')
            .then((x) => u = x);
        t.elapse(const Duration(milliseconds: 600));
        expect(u?.winnaar, tsTls);
      });
    });

    test('de noodrem op de pc (47822 dicht): dan pas 47820, zodra de versleutelde geweigerd is', () {
      fakeAsync((t) {
        WedloopUitslag? u;
        adresWedloop(kandidatenVoor([_thuis, thuisTls]),
                vraag: pcs({_thuis: (2, 'pc-1'), thuisTls: (15, 'NEE')}), verwachtServerId: 'pc-1')
            .then((x) => u = x);
        t.elapse(const Duration(milliseconds: 14));
        expect(u, isNull);
        t.elapse(const Duration(milliseconds: 2));
        expect(u?.winnaar, _thuis);
      });
    });

    test('een versleutelde die hangt: onversleuteld pas na de volle poging', () {
      fakeAsync((t) {
        WedloopUitslag? u;
        adresWedloop(kandidatenVoor([_thuis, thuisTls]),
                vraag: pcs({_thuis: (2, 'pc-1'), thuisTls: (0, null)}), verwachtServerId: 'pc-1')
            .then((x) => u = x);
        t.elapse(const Duration(milliseconds: 2990));
        expect(u, isNull);
        t.elapse(const Duration(milliseconds: 20));
        expect(u?.winnaar, _thuis);
      });
    });

    test('een onversleuteld thuisadres dat hangt, houdt versleuteld Tailscale niet op', () {
      fakeAsync((t) {
        WedloopUitslag? u;
        // Thuis is 47822 dicht en hangt 47820; Tailscale versleuteld antwoordt op 430 ms. Wachten op een
        // thuisadres dat hoe dan ook zou verliezen, is tijd voor niets.
        adresWedloop(kandidatenVoor([_thuis, thuisTls, tsTls]),
                vraag: pcs({_thuis: (0, null), thuisTls: (3, 'NEE'), tsTls: (30, 'pc-1')}), verwachtServerId: 'pc-1')
            .then((x) => u = x);
        t.elapse(const Duration(milliseconds: 440));
        expect(u?.winnaar, tsTls, reason: 'meteen, niet pas na de thuisvoorrang van 500 ms');
      });
    });

    test('thuis versleuteld blijft voorgaan op Tailscale versleuteld', () {
      fakeAsync((t) {
        WedloopUitslag? u;
        adresWedloop(kandidatenVoor([thuisTls, tsTls]),
                vraag: pcs({thuisTls: (480, 'pc-1'), tsTls: (10, 'pc-1')}), verwachtServerId: 'pc-1')
            .then((x) => u = x);
        t.elapse(const Duration(milliseconds: 600));
        expect(u?.winnaar, thuisTls);
      });
    });
  });

  test('geen adressen: meteen nee', () async {
    final u = await adresWedloop(const [], vraag: (_, __) async => null);
    expect(u.winnaar, isNull);
  });
}
