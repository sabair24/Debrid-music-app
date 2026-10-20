// Twee wegen naar een uploader (soulseek.dart, `eersteVerbinding`): rechtstreeks met een voorsprong van
// een tel, daarna ook via de server — wie het eerst antwoordt wint.
//
// Gemeten op de pc (20-10-2026, 3.9.523): de winnaars bij de trage nummers stuurden allemaal na 9 à 10 s,
// want de app probeerde eerst rechtstreeks (tot 8 s) en vroeg pas daarna de server. Een uploader achter
// een firewall is alleen langs de server te bereiken.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/soulseek.dart';

void main() {
  const voorsprong = Duration(milliseconds: 150);

  test('rechtstreeks binnen de voorsprong: de server wordt niet eens gevraagd', () async {
    var serverGevraagd = false;
    final w = await eersteVerbinding<String>(
      rechtstreeks: () async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 'rechtstreeks';
      },
      viaServer: () async {
        serverGevraagd = true;
        return 'server';
      },
      sluit: (_) {},
      voorsprong: voorsprong,
    );
    expect(w, 'rechtstreeks');
    await Future<void>.delayed(voorsprong * 2);
    expect(serverGevraagd, isFalse, reason: 'wie rechtstreeks bereikbaar is, kost geen bericht aan de server');
  });

  test('rechtstreeks hangt (firewall): na de voorsprong ook de server, en die wint — niet 8 s wachten', () async {
    final hangt = Completer<String?>();
    final gesloten = <String>[];
    final klok = Stopwatch()..start();
    final w = await eersteVerbinding<String>(
      rechtstreeks: () => hangt.future,
      viaServer: () async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return 'server';
      },
      sluit: gesloten.add,
      voorsprong: voorsprong,
    );
    expect(w, 'server');
    expect(klok.elapsed, lessThan(const Duration(seconds: 1)), reason: 'de voorsprong plus de server, geen 8 s');
    expect(klok.elapsed, greaterThanOrEqualTo(voorsprong), reason: 'eerst krijgt rechtstreeks zijn kans');
    // Lukt de rechtstreekse alsnog, dan gaat die dicht: er is al een verbinding.
    hangt.complete('rechtstreeks, te laat');
    await Future<void>.delayed(Duration.zero);
    expect(gesloten, ['rechtstreeks, te laat']);
  });

  test('geen adres of meteen geweigerd: de server meteen, zonder op de voorsprong te wachten', () async {
    final klok = Stopwatch()..start();
    final w = await eersteVerbinding<String>(
      rechtstreeks: () async => null,
      viaServer: () async => 'server',
      sluit: (_) {},
      voorsprong: const Duration(seconds: 5),
    );
    expect(w, 'server');
    expect(klok.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('rechtstreeks faalt pas na de voorsprong: wachten op de server, die nog loopt', () async {
    final server = Completer<String?>();
    final uitslag = eersteVerbinding<String>(
      rechtstreeks: () async {
        await Future<void>.delayed(voorsprong * 2);
        return null;
      },
      viaServer: () => server.future,
      sluit: (_) {},
      voorsprong: voorsprong,
    );
    await Future<void>.delayed(voorsprong * 3);
    server.complete('server');
    expect(await uitslag, 'server');
  });

  test('beide wegen niets: null — en een fout telt als niets', () async {
    expect(
        await eersteVerbinding<String>(
          rechtstreeks: () async => throw const SocketException('geweigerd'),
          viaServer: () async => null,
          sluit: (_) {},
          voorsprong: voorsprong,
        ),
        isNull);
  });

  test('de server wint en rechtstreeks volgt toch: dicht, nooit twee verbindingen', () async {
    final rechtstreeks = Completer<String?>();
    final gesloten = <String>[];
    final w = await eersteVerbinding<String>(
      rechtstreeks: () => rechtstreeks.future,
      viaServer: () async => 'server',
      sluit: gesloten.add,
      voorsprong: Duration.zero,
    );
    expect(w, 'server');
    rechtstreeks.complete('rechtstreeks');
    await Future<void>.delayed(Duration.zero);
    expect(gesloten, ['rechtstreeks']);
  });

  test('aangesloten: het berichtkanaal van een overdracht gaat langs beide wegen, met een tel voorsprong', () {
    final bron = File('lib/soulseek.dart').readAsStringSync();
    expect(bron, contains('const kRechtstreeksVoorsprong = Duration(seconds: 1);'));
    final t = bron.substring(bron.indexOf('  Future<SlskResult> _transfer('));
    expect(t, contains('final weg = await eersteVerbinding<Object>('));
    expect(t, contains('viaServer: () => _reverseConnect(file.username),'));
    expect(t, contains('return await Socket.connect(ip, port, timeout: const Duration(seconds: 8));'));
    expect(t.indexOf('final weg = await eersteVerbinding<Object>('),
        lessThan(t.indexOf('psend(_message(43, (_W()..str(file.filename)).bytes())); // QueueUpload')));
    expect(t, isNot(contains('final rev = await _reverseConnect(file.username);')),
        reason: 'niet meer pas nadat rechtstreeks opgaf');
  });
}
