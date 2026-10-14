/// Remmen waar het mag, en nooit waar het pijn doet.
///
/// Stap 2.5 van "verbinden zoals Roon ARC" (plan 14-10-2026). Twee dingen, en allebei bewust smal:
///
/// * [Remming]: wie een **verkeerde** sleutel aanbiedt, krijgt zijn weigering per adres steeds later.
///   Een verzoek met een geldige sleutel wordt NOOIT afgeremd — een mobiel netwerk zet veel gsm's
///   achter hetzelfde adres, en een toestel van jou hoort nooit te wachten op een vreemde.
/// * [KoppelBudget]: hoe vaak `/pair-cloud` Google mag vragen van wie een inlogsleutel is. Dat is de
///   enige deur zonder sleutel die werk bij een ander kost.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Oplopende wachttijd voor mislukte sleutels, per adres.
class Remming {
  Remming({
    this.venster = const Duration(minutes: 10),
    this.vrij = 3,
    this.basis = const Duration(milliseconds: 250),
    this.plafond = const Duration(seconds: 10),
    this.maxAdressen = 1000,
    DateTime Function()? klok,
  }) : _klok = klok ?? DateTime.now;

  /// Hoe lang een mislukte poging meetelt.
  final Duration venster;

  /// Zoveel mislukte pogingen per venster kosten niets: een toestel met een oude sleutel dat even
  /// aanklopt voor het zich herstelt, merkt er niets van.
  final int vrij;
  final Duration basis;
  final Duration plafond;

  /// Begrensd geheugen: anders is de remming zelf de manier om de pc vol te laten lopen.
  final int maxAdressen;
  final DateTime Function() _klok;
  final _mislukt = <String, List<DateTime>>{};

  /// Een mislukte sleutel van [adres]. Geeft terug hoe lang het antwoord moet wachten.
  Duration naMislukt(String adres) {
    final nu = _klok();
    final rij = _mislukt.remove(adres) ?? <DateTime>[];
    rij
      ..removeWhere((t) => nu.difference(t) > venster)
      ..add(nu);
    _mislukt[adres] = rij; // achteraan: de map is zo op volgorde van laatste poging
    while (_mislukt.length > maxAdressen) {
      _mislukt.remove(_mislukt.keys.first);
    }
    final n = rij.length;
    if (n <= vrij) return Duration.zero;
    final stap = n - vrij - 1;
    final ms = basis.inMilliseconds * (1 << (stap > 20 ? 20 : stap));
    return ms >= plafond.inMilliseconds ? plafond : Duration(milliseconds: ms);
  }

  /// Een geldige sleutel van [adres]: wat er stond, telt niet meer.
  void gelukt(String adres) => _mislukt.remove(adres);

  @visibleForTesting
  int get aantalAdressen => _mislukt.length;
}

/// Hoe vaak `/pair-cloud` een inlogsleutel bij Google mag laten nakijken: hoogstens [perMinuut] in
/// de laatste minuut en [perDag] in de laatste 24 uur, voor de hele pc samen.
///
/// Alleen sleutels die de eerste blik (`inlogsleutelFout`) doorstaan tellen mee; rommel kost niets.
/// Saber koppelt een paar keer per maand een toestel; dertig per dag is ruim voor hem en krap voor
/// wie het als ingang probeert.
class KoppelBudget {
  KoppelBudget({this.perMinuut = 10, this.perDag = 30, DateTime Function()? klok})
      : _klok = klok ?? DateTime.now;
  final int perMinuut;
  final int perDag;
  final DateTime Function() _klok;
  final _gebruikt = <DateTime>[];

  /// Null als er nog ruimte is (en dan telt deze mee); anders vanaf wanneer weer.
  DateTime? neem() {
    final nu = _klok();
    _gebruikt.removeWhere((t) => nu.difference(t) >= const Duration(days: 1));
    final laatsteMinuut = _gebruikt.where((t) => nu.difference(t) < const Duration(minutes: 1)).toList();
    if (laatsteMinuut.length >= perMinuut) return laatsteMinuut.first.add(const Duration(minutes: 1));
    if (_gebruikt.length >= perDag) return _gebruikt.first.add(const Duration(days: 1));
    _gebruikt.add(nu);
    return null;
  }
}
