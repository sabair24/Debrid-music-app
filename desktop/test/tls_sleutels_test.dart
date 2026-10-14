/// HTTP-sleutels en TLS-sleutels in `grants.json`: wat waar geldt, de eenmalige ruil, en wat het
/// samenvoegen van twee kopieën ermee doet.
///
/// Stap 5 van "verbinden zoals Roon ARC" (14-10-2026). Een HTTP-sleutel reisde ooit onversleuteld en
/// geldt alleen op 47820; een TLS-sleutel wordt alleen over vastgepinde TLS uitgegeven en geldt alleen op
/// 47822 en 47821.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/tokens.dart';

void main() {
  late Directory map;
  late File bestand;
  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_tls_');
    bestand = File('${map.path}/grants.json');
  });
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  GrantStore winkel() => GrantStore(file: bestand);

  test('de ruil: een TLS-sleutel die alleen versleuteld geldt; de HTTP-sleutel blijft op 47820', () {
    final g = winkel();
    final http = g.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26').token;
    final r = g.ruil(http);
    expect(r.status, 200);
    final tls = r.tls!;
    expect(tls, isNot(http));
    expect(g.acceptsTls(tls), isTrue);
    expect(g.accepts(tls), isFalse, reason: 'een TLS-sleutel geldt nooit op 47820');
    expect(g.isTlsSleutel(tls), isTrue);
    expect(g.accepts(http), isTrue, reason: 'de HTTP-sleutel blijft geldig op 47820');
    expect(g.acceptsTls(http), isFalse, reason: 'een HTTP-sleutel geldt nooit op 47822 of 47821');
    expect(g.grantFor(tls)?.deviceId, 'gsm-van-saber-01');
  });

  test('één keer: een tweede ruil geeft 409', () {
    final g = winkel();
    final http = g.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26').token;
    expect(g.ruil(http).status, 200);
    expect(g.ruil(http).status, 409);
  });

  test('niet met de gedeelde sleutel, niet met een oudere sleutel, niet met iets onbekends', () {
    final g = winkel();
    g.adoptLegacyToken('de-gedeelde-sleutel-uit-elke-cast-url');
    expect(g.ruil('de-gedeelde-sleutel-uit-elke-cast-url').status, 403);
    final eerste = g.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26').token;
    g.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26');
    expect(g.accepts(eerste), isTrue, reason: 'de vorige sleutel blijft geldig in oudereTokens');
    expect(g.ruil(eerste).status, 403, reason: 'alleen de HUIDIGE sleutel van een echte rij');
    expect(g.ruil('nooit-gezien').status, 401);
    expect(g.ruil('').status, 401);
    expect(g.byDevice('legacy')?.tlsToken, isNull);
  });

  test('bewaard en weer ingelezen', () async {
    final g = winkel();
    final http = g.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26').token;
    final tls = g.ruil(http).tls!;
    await g.save();
    final opnieuw = winkel();
    await opnieuw.load();
    expect(opnieuw.acceptsTls(tls), isTrue);
    expect(opnieuw.accepts(http), isTrue);
    expect(opnieuw.accepts(tls), isFalse);
    expect(opnieuw.ruil(http).status, 409, reason: 'ook na een herstart maar één keer');
  });

  test('twee kopieën met elk een andere TLS-sleutel: de jongste geldt, de andere niet; oudereTokens blijven', () async {
    final a = winkel();
    final http = a.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26').token;
    await a.save();
    // Een tweede kopie leest dezelfde koppeling en ruilt ook (bv. een pc-app die twee keer draaide).
    final b = winkel();
    await b.load();
    final tlsOud = a.ruil(http).tls!;
    await a.save();
    final metOudeTls = bestand.readAsStringSync();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final tlsNieuw = b.ruil(http).tls!;
    await b.save();
    await a.save(); // a voegt samen met wat b schreef
    final c = winkel();
    await c.load();
    expect(c.acceptsTls(tlsNieuw), isTrue);
    expect(c.acceptsTls(tlsOud), isFalse);
    expect(a.acceptsTls(tlsOud), isFalse, reason: 'ook in het geheugen van de verliezer');
    expect(c.byDevice('gsm-van-saber-01')!.oudereTokens, isNot(contains(tlsOud)),
        reason: 'een TLS-sleutel komt nooit in oudereTokens');
    expect(c.accepts(http), isTrue);
    expect(c.isIngetrokken(tlsOud), isTrue, reason: 'de verliezer staat ingetrokken, ook op schijf');
    // Een oudere momentopname met alleen de verliezer komt terug (een tweede kopie van de app).
    bestand.writeAsStringSync(metOudeTls);
    final d = winkel();
    await d.load();
    expect(d.acceptsTls(tlsOud), isFalse, reason: 'een verloren TLS-sleutel komt via een oude kopie niet terug');
  });

  test('één TLS-sleutel intrekken blijft ingetrokken, ook na samenvoegen met een kopie die hem nog heeft', () async {
    final a = winkel();
    final http = a.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26').token;
    final tls = a.ruil(http).tls!;
    await a.save();
    final oudeKopie = bestand.readAsStringSync();
    expect(a.trekSleutelIn(tls), isTrue);
    await a.save();
    // Een oudere momentopname komt terug op schijf (een tweede kopie van de app).
    bestand.writeAsStringSync(oudeKopie);
    await a.save();
    final b = winkel();
    await b.load();
    expect(b.acceptsTls(tls), isFalse);
    expect(b.accepts(http), isTrue, reason: 'alleen die ene sleutel');
  });

  test('opnieuw koppelen zonder TLS: samenvoegen met schijf haalt de oude TLS-sleutel niet terug', () async {
    final g = winkel();
    final http = g.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26').token;
    final tls1 = g.ruil(http).tls!;
    await g.save(); // schijf heeft tls1
    final nieuw = g.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26');
    await g.save(); // samenvoegen met de schijf, waar tls1 nog staat
    expect(g.acceptsTls(tls1), isFalse);
    final h = winkel();
    await h.load();
    expect(h.acceptsTls(tls1), isFalse);
    expect(h.ruil(nieuw.token).status, 200);
  });

  test('opnieuw koppelen: de vorige TLS-sleutel vervalt; met TLS komt er meteen een nieuwe bij', () {
    final g = winkel();
    final http = g.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26').token;
    final tls1 = g.ruil(http).tls!;
    final metTls = g.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26', metTls: true);
    expect(metTls.tlsToken, isNotNull);
    expect(g.acceptsTls(metTls.tlsToken!), isTrue);
    expect(g.acceptsTls(tls1), isFalse);
    // Zonder TLS (de zes cijfers, over 47820): geen TLS-sleutel meer, en de ruil mag dan weer.
    final zonder = g.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26');
    expect(zonder.tlsToken, isNull);
    expect(g.acceptsTls(metTls.tlsToken!), isFalse);
    expect(g.ruil(zonder.token).status, 200, reason: 'een herinstalleerde app stuit anders op 409');
  });

  test('een toestel intrekken neemt zijn TLS-sleutel mee', () {
    final g = winkel();
    final http = g.nieuweSleutel(deviceId: 'gsm-van-saber-01', deviceName: 'S26').token;
    final tls = g.ruil(http).tls!;
    expect(g.revoke('gsm-van-saber-01'), isTrue);
    expect(g.acceptsTls(tls), isFalse);
    expect(g.isTlsSleutel(tls), isFalse);
  });

  test('de rij legacy krijgt nooit een TLS-sleutel, ook niet van schijf', () async {
    bestand.writeAsStringSync(jsonEncode([
      {'deviceId': 'legacy', 'deviceName': 'x', 'token': 'gedeeld', 'platform': '', 'grantedAt': 0, 'legacy': true, 'tlsToken': 'ingesmokkeld', 'tlsAt': 5},
    ]));
    final g = winkel();
    await g.load();
    expect(g.acceptsTls('ingesmokkeld'), isFalse);
    expect(g.byDevice('legacy')?.tlsToken, isNull);
  });
}
