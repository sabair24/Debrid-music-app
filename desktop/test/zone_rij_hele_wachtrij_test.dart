// De wachtrij van een zone op afstand, helemaal (Saber, 25-10-2026, op de gsm die de Shield bedient: "shuffle heel men
// bibliotheek, hierna 400 ???? Ik heb meer dan 400 liedjes ... meer dan 5000, 10000 liedjes shuffelen, zonder dat hij
// liedje herhaald"). Gemeten op de pc: de Shield had alle 1769 nummers in zijn wachtrij, geen enkele dubbel. Het paneel
// telde het venster dat de pc meegeeft (400 na het spelende nummer), en de lijst hield daar op.
import 'dart:io';

import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/zone_lijst.dart';
import 'package:debridmusic/zone_speler.dart';
import 'package:flutter_test/flutter_test.dart';

const _nu = 10000000;

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

ZoneStaat _tv({int index = 0, int lengte = 1769}) => ZoneStaat(
      id: 'dev:tv',
      soort: ZoneSoort.pc,
      naam: 'Tv in woonkamer',
      online: true,
      playing: true,
      trackId: 'n$index',
      titel: 'Titel',
      positionMs: 1000,
      durationMs: 240000,
      opMs: _nu,
      index: index,
      lengte: lengte,
      volume: 50,
    );

void main() {
  final alles = [for (var i = 0; i < 1769; i++) 'n$i'];
  late List<int> gevraagd;

  ZoneSpeler speler({int index = 0}) {
    gevraagd = [];
    final lijst = ZoneLijst(hier: 'dev:gsm', klok: () => _nu)
      ..zet({'nu': _nu, 'zones': [_tv(index: index).toJson()]});
    return ZoneSpeler(
      lijst: lijst,
      zoneId: 'dev:tv',
      nummer: (id) => Track(path: 'zone:$id', title: id, artist: 'X', album: 'A'),
      idVan: (t) => t.title,
      hoesVan: (_) => null,
      stuur: (_) async => null,
      // Zoals de pc (`ZoneRegister.rijVenster`).
      haalRij: (na) async {
        gevraagd.add(na);
        final w = rijVensterUit(alles, index, na: na);
        return {'index': index, 'lengte': alles.length, 'van': w.van, 'rij': w.rij};
      },
      klok: () => _nu,
    );
  }

  Future<void> wacht() => Future<void>.delayed(const Duration(milliseconds: 250));

  test('DE KERN: "Hierna" is de hele wachtrij, ook als het venster er 400 meegeeft', () async {
    final z = speler();
    z.queueTracks;
    await wacht();
    expect(z.queueTracks.length, 401, reason: 'het venster: het spelende nummer en 400 erna');
    expect(z.hiernaInRij, 1768, reason: 'niet 400');
    expect(gevraagd, [kZoneRijNa]);
    z.dispose();
  });

  test('DE KERN: scrollen naar het einde haalt er telkens meer bij, tot alle 1769 er staan — elk één keer', () async {
    final z = speler();
    z.queueTracks;
    await wacht();
    for (var i = 0; i < 10 && z.queueTracks.length < 1769; i++) {
      z.meerHierna();
      await wacht();
    }
    expect(z.queueTracks.length, 1769);
    expect({for (final t in z.queueTracks) t.title}.length, 1769, reason: 'geen enkele dubbel');
    expect(gevraagd.first, 400);
    expect(gevraagd[1], 800, reason: 'telkens ${kZoneRijStap} erbij');
    final keren = gevraagd.length;
    z.meerHierna();
    await wacht();
    expect(gevraagd.length, keren, reason: 'alles staat er: niet meer vragen');
    z.dispose();
  });

  test('DE GRENS: twee keer meer vragen voor hetzelfde stuk is één keer halen', () async {
    final z = speler();
    z.queueTracks;
    await wacht();
    z
      ..meerHierna()
      ..meerHierna();
    await wacht();
    expect(gevraagd, [400, 800]);
    z.dispose();
  });

  test('DE VAL: een pc die "na" niet kent (een oudere) geeft steeds 400 — dan één keer meer vragen, geen stroom', () async {
    gevraagd = [];
    final lijst = ZoneLijst(hier: 'dev:gsm', klok: () => _nu)
      ..zet({'nu': _nu, 'zones': [_tv().toJson()]});
    final z = ZoneSpeler(
      lijst: lijst,
      zoneId: 'dev:tv',
      nummer: (id) => Track(path: 'zone:$id', title: id, artist: 'X', album: 'A'),
      idVan: (t) => t.title,
      hoesVan: (_) => null,
      stuur: (_) async => null,
      haalRij: (na) async {
        gevraagd.add(na);
        final w = rijVensterUit(alles, 0); // negeert na
        return {'index': 0, 'lengte': alles.length, 'van': w.van, 'rij': w.rij};
      },
      klok: () => _nu,
    );
    z.queueTracks;
    await wacht();
    // Elke regel aan het einde die gebouwd wordt, vraagt het: vijf keer.
    for (var i = 0; i < 5; i++) {
      z.meerHierna();
      await wacht();
    }
    expect(gevraagd, [400, 800], reason: 'niet bij elke regel opnieuw');
    z.dispose();
  });

  test('"Eerder gespeeld" telt ook de hele wachtrij', () async {
    final z = speler(index: 500);
    z.queueTracks;
    await wacht();
    expect(z.eerderInRij, 500);
    expect(z.currentIndex, 100, reason: 'in het venster staan er 100 voor');
    z.dispose();
  });

  test('aangesloten: de pc geeft op vraag meer, en het paneel telt en haalt bij', () {
    final server = _bron('lib/lan/server.dart');
    expect(server, contains("final na = int.tryParse(req.uri.queryParameters['na'] ?? '')?.clamp(1, kZoneRijHoogstens) ?? kZoneRijNa;"));
    expect(server, contains("final v = zones.rijVenster(req.uri.queryParameters['zone'] ?? '', na: na);"));
    expect(_bron('lib/lan/client.dart'), contains("if (na != null) 'na': '\$na'"));
    final main = _bron('lib/main.dart');
    expect(main, contains("zoneKop('Hierna', extra: '\$hiernaTotaal')"));
    expect(main, contains("zoneKop('Eerder gespeeld', extra: '\$eerderTotaal')"));
    expect(main, contains('      if (j >= hierna - kZoneRijBijhalen) zoneOpAfstand?.meerHierna();'));
    expect('bijHetEinde(j);'.allMatches(main).length, 2, reason: 'in de lijst en in de sleeplijst');
    expect(main, contains(': (na) async => library.remote?.zoneRij(zone, na: na),'));
  });
}
