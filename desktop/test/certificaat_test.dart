/// Het eigen certificaat van de pc: Darts TLS (BoringSSL) aanvaardt het, een toestel met de juiste pin
/// komt binnen, met een andere pin niet, en het blijft hetzelfde over een herstart heen.
///
/// Stap 5 van "verbinden zoals Roon ARC" (14-10-2026).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/certificaat.dart';

/// Een TLS-server op loopback die "ok" zegt en sluit.
Future<SecureServerSocket> _server(PcCertificaat c) async {
  final s = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, c.context());
  s.listen((sock) {
    sock.write('ok');
    unawaited(sock.close());
  }, onError: (_) {});
  return s;
}

/// Verbinden en alleen een server met [pin] aanvaarden. Null = handdruk geweigerd.
Future<String?> _vraag(int poort, String pin) async {
  try {
    final sock = await SecureSocket.connect(InternetAddress.loopbackIPv4, poort,
        onBadCertificate: (cert) => pinVan(cert.der) == pin, timeout: const Duration(seconds: 5));
    final antwoord = await utf8.decoder.bind(sock).join();
    sock.destroy();
    return antwoord;
  } on HandshakeException {
    return null;
  } on TlsException {
    return null;
  }
}

void main() {
  late Directory map;
  setUp(() => map = Directory.systemTemp.createTempSync('dm_cert_'));
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('BoringSSL aanvaardt het certificaat; de juiste pin komt binnen, een andere niet', () async {
    final c = PcCertificaat.maak();
    expect(c.certPem, startsWith('-----BEGIN CERTIFICATE-----'));
    expect(c.pin, hasLength(64));
    final s = await _server(c);
    addTearDown(s.close);
    expect(await _vraag(s.port, c.pin), 'ok');
    expect(await _vraag(s.port, 'a' * 64), isNull, reason: 'een tussenpersoon met een ander certificaat valt af');
  });

  test('wat het toestel ziet is precies de pin van de pc', () async {
    final c = PcCertificaat.maak();
    final s = await _server(c);
    addTearDown(s.close);
    String? gezien;
    final sock = await SecureSocket.connect(InternetAddress.loopbackIPv4, s.port, onBadCertificate: (cert) {
      gezien = pinVan(cert.der);
      return true;
    });
    sock.destroy();
    expect(gezien, c.pin);
  });

  test('geen pc-naam of gebruikersnaam in het certificaat', () {
    final c = PcCertificaat.maak();
    final tekst = latin1.decode(c.der);
    expect(tekst, contains('DebridMusic'));
    for (final naam in [Platform.localHostname, Platform.environment['USERNAME'] ?? '', Platform.environment['USER'] ?? '']) {
      if (naam.length >= 3) expect(tekst.toLowerCase(), isNot(contains(naam.toLowerCase())));
    }
  });

  test('bewaard: dezelfde pin na een herstart; een kapot bestand geeft een nieuw certificaat en een logregel', () async {
    final eerste = await PcCertificaat.laadOfMaak(map);
    final tweede = await PcCertificaat.laadOfMaak(map);
    expect(tweede.pin, eerste.pin);
    File('${map.path}${Platform.pathSeparator}tls_sleutel.pem').writeAsStringSync('kapot');
    final regels = <String>[];
    final derde = await PcCertificaat.laadOfMaak(map, log: regels.add);
    expect(derde.pin, isNot(eerste.pin));
    expect(regels.join('\n'), contains('certificaat onleesbaar'));
    expect((await PcCertificaat.laadOfMaak(map)).pin, derde.pin, reason: 'het nieuwe is ook bewaard');
  });

  test('twee certificaten hebben een ander volgnummer', () {
    final a = PcCertificaat.maak();
    final b = PcCertificaat.maak();
    expect(a.pin, isNot(b.pin));
  });
}
