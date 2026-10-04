/// Wat [vulVensterNaEersteBeeld] in start.log zet — en dat het gedrag van de oude lus gelijk bleef.
///
/// **Waarom dit bestaat.** Op 04-10-2026 opende de app na twee updates klein (1240x820 midden op het
/// scherm), en de lus die na het eerste beeld om maximaliseren vraagt zweeg over wat hij zag. Deze
/// regels zijn de meting die bij de volgende update moet zeggen wat er gebeurt. Een meting die het
/// geval waar het om draait niet ziet, is erger dan geen meting: dan lees je de stilte als "niets
/// aan de hand". Vandaar vooral de tweede toets: het venster is gevuld als de lus stopt, en springt
/// pas dáárna terug. Precies dat moment moet in het logboek staan.
library;

import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/venster_start.dart';

const _herstelmaat = Rect.fromLTWH(660, 310, 1240, 820);
const _gevuld = Rect.fromLTWH(-8, -8, 2576, 1456);

/// Een venster met een eigen klok. Wachten laat de klok lopen en vuurt af wat er "van buiten"
/// gebeurt — zoals de runner die bij het eerste beeld SW_SHOWNORMAL doet.
class _NepVenster {
  Duration nu = Duration.zero;
  bool gemaximaliseerd = false;
  Rect maat = _herstelmaat;
  bool maximaliserenLukt = true;
  int verzoeken = 0;
  final gebeurtenissen = <Duration, void Function()>{};
  final regels = <String>[];

  Future<bool> isMax() async => gemaximaliseerd;

  Future<void> maximaliseer() async {
    verzoeken++;
    if (!maximaliserenLukt) return;
    gemaximaliseerd = true;
    maat = _gevuld;
  }

  void herstel() {
    gemaximaliseerd = false;
    maat = _herstelmaat;
  }

  Future<void> wacht(Duration d) async {
    final eind = nu + d;
    final momenten = gebeurtenissen.keys.where((t) => t > nu && t <= eind).toList()..sort();
    for (final t in momenten) {
      gebeurtenissen[t]!();
    }
    nu = eind;
  }

  Future<void> vul({Future<Rect> Function()? maten}) => vulVensterNaEersteBeeld(
        isGemaximaliseerd: isMax,
        maximaliseer: maximaliseer,
        maten: maten ?? () async => maat,
        log: regels.add,
        verstreken: () => nu,
        wacht: wacht,
      );
}

void main() {
  test('gevuld en gevuld gebleven: twee pogingen, geen verandering, eindstand ja', () async {
    final v = _NepVenster();
    await v.vul();

    expect(v.regels, [
      'venster: poging 1 (+0 ms): gemaximaliseerd=nee, 660,310 1240x820',
      'venster: poging 2 (+100 ms): gemaximaliseerd=ja, -8,-8 2576x1456',
      'venster: nagekeken tot +8000 ms, eindstand: gemaximaliseerd=ja, -8,-8 2576x1456',
    ]);
    expect(v.verzoeken, 1);
  });

  test('terugspringen ná de pogingen staat in het logboek, met tijd en herstelmaat', () async {
    final v = _NepVenster();
    // De lus stopt op +100 ms omdat het venster dan gevuld is. Op +300 ms zet iets anders het terug.
    v.gebeurtenissen[const Duration(milliseconds: 300)] = v.herstel;
    await v.vul();

    expect(v.regels, contains('venster: poging 2 (+100 ms): gemaximaliseerd=ja, -8,-8 2576x1456'));
    expect(v.regels,
        contains('venster: veranderd na de pogingen (+500 ms): gemaximaliseerd=nee, 660,310 1240x820'));
    expect(v.regels.last,
        'venster: nagekeken tot +8000 ms, eindstand: gemaximaliseerd=nee, 660,310 1240x820');
    // Alleen kijken: er wordt niet opnieuw gemaximaliseerd. Dat is een meting, geen reparatie.
    expect(v.verzoeken, 1);
  });

  test('maximaliseren dat nooit lukt: zes pogingen, zes verzoeken, en een regel die het zegt', () async {
    final v = _NepVenster()..maximaliserenLukt = false;
    await v.vul();

    final pogingen = v.regels.where((r) => r.startsWith('venster: poging ')).toList();
    expect(pogingen, hasLength(6));
    expect(pogingen.last, 'venster: poging 6 (+500 ms): gemaximaliseerd=nee, 660,310 1240x820');
    expect(v.verzoeken, 6);
    expect(v.regels, contains('venster: na 6 pogingen nog altijd niet gemaximaliseerd'));
    expect(v.regels.where((r) => r.contains('veranderd')), isEmpty);
  });

  test('zichtbaar en voorgrond komen in de regel als ze gevraagd kunnen worden', () async {
    final regels = <String>[];
    await vulVensterNaEersteBeeld(
      isGemaximaliseerd: () async => true,
      maximaliseer: () async {},
      maten: () async => _gevuld,
      isZichtbaar: () async => true,
      heeftVoorgrond: () async => false,
      log: regels.add,
      verstreken: () => Duration.zero,
      wacht: (_) async {},
    );
    expect(regels.first,
        'venster: poging 1 (+0 ms): gemaximaliseerd=ja, zichtbaar=ja, voorgrond=nee, -8,-8 2576x1456');
  });

  test('een fout wordt een regel en breekt het opstarten niet', () async {
    final v = _NepVenster();
    await v.vul(maten: () async => throw StateError('geen venster'));

    expect(v.regels.single, 'venster: meten of vullen mislukte: Bad state: geen venster');
  });

  test('de maat wordt afgerond tot hele punten', () {
    expect(vensterMaat(const Rect.fromLTWH(659.6, 310.2, 1240.4, 819.5)), '660,310 1240x820');
  });
}
