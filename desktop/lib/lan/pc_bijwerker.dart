/// De pc die zichzelf bijwerkt omdat een gekoppeld toestel erom vroeg.
///
/// **Alle machinerie stond er al.** `updater.dart` zoekt de nieuwste uitgave, haalt de installer op
/// en start hem — en die installer sluit deze app zelf af (`/CLOSEAPPLICATIONS`) en start hem daarna
/// weer op (`/RESTARTAPPLICATIONS`). Wat ontbrak was de aanleiding: die knop zat alleen op de pc
/// zelf, en daar sta je niet altijd bij.
///
/// **Dit is met opzet geen ChangeNotifier.** Er is hier geen scherm om bij te werken; de pc heeft
/// zijn eigen updatevenster en dat loopt langs een andere weg. Wat hier gebeurt wordt uitsluitend
/// bevraagd door de telefoon, die om de paar seconden [stand] leest. Een winkel met luisteraars zou
/// een tweede plek zijn waar dit stuk kapot kan.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../updater.dart';
import 'bijwerkstand.dart';

class PcBijwerker {
  PcBijwerker({Updater updater = const Updater()}) : _updater = updater;

  final Updater _updater;

  Bijwerkfase _fase = Bijwerkfase.stil;
  double _voortgang = 0;
  String _fout = '';

  /// Wat er klaarstaat volgens de laatste keer dat we gekeken hebben.
  Uitgave? _klaar;
  DateTime? _gekeken;

  /// Niet vaker dan dit bij GitHub langs. De telefoon peilt om de paar seconden zolang het paneel
  /// openstaat, en dat mag geen verzoek per peiling worden — dat is precies het soort druk dat
  /// nergens toe leidt en waar je op een dag een 403 voor terugkrijgt.
  static const _versheid = Duration(minutes: 10);

  bool get bezig => _fase == Bijwerkfase.halen || _fase == Bijwerkfase.installeren;

  /// Wat de telefoon te zien krijgt. Zie [bijwerkbeeldVan] voor wat daar getekend wordt.
  ///
  /// [versieHier] is wat deze pc draait — de server weet dat al, dus het wordt doorgegeven in
  /// plaats van hier nog eens opgevraagd.
  Future<Map<String, dynamic>> stand(String versieHier, {bool opnieuw = false}) async {
    if (!bezig) await _kijk(opnieuw: opnieuw);
    return {
      'kan': Updater.kanHier,
      'versie': versieHier,
      'nieuw': _klaar?.versie ?? '',
      'bytes': _klaar?.bytes ?? 0,
      'fase': naamVanFase(_fase),
      'voortgang': _voortgang,
      'fout': _fout,
    };
  }

  /// Beginnen. Geeft dezelfde stand terug als [stand], zodat de telefoon meteen ziet wat er gebeurt
  /// zonder een tweede vraag te stellen.
  ///
  /// **Twee keer drukken doet niets extra's.** Een tweede verzoek terwijl er al iets loopt geeft
  /// gewoon de lopende stand terug: op een trage verbinding is dubbel drukken normaal, en twee
  /// installers naast elkaar op een pc waar niemand bij staat is het ergste wat hier kan gebeuren.
  Future<Map<String, dynamic>> start(String versieHier) async {
    if (bezig) return stand(versieHier);
    if (!Updater.kanHier) {
      _fase = Bijwerkfase.mislukt;
      _fout = 'Deze pc kan zichzelf niet bijwerken.';
      return stand(versieHier);
    }

    // Een nieuwe poging wist de vorige mislukking: anders blijft de melding staan naast een balk
    // die loopt, en dan weet je niet meer waar je naar kijkt.
    _fout = '';
    _voortgang = 0;

    // Vers kijken, ook als we tien minuten geleden al keken. Dit is het enige moment waarop het
    // antwoord ertoe doet — hierna wordt er iets geïnstalleerd.
    await _kijk(opnieuw: true);
    final u = _klaar;
    if (u == null) {
      _fase = Bijwerkfase.stil;
      return stand(versieHier);
    }

    _fase = Bijwerkfase.halen;
    unawaited(_doe(u));
    return stand(versieHier);
  }

  /// Kijken wat er klaarstaat, hoogstens eens per [_versheid].
  ///
  /// Stil bij elke storing, net als [Updater.zoek] zelf: "GitHub is even traag" is geen melding
  /// waard op een scherm dat je alleen opent om te zien of je bij bent.
  Future<void> _kijk({bool opnieuw = false}) async {
    final laatst = _gekeken;
    if (!opnieuw && laatst != null && DateTime.now().difference(laatst) < _versheid) return;
    _gekeken = DateTime.now();
    try {
      // `negeerOvergeslagen`: iemand die op zijn telefoon om een update vraagt, vraagt om déze
      // update. Dat op de pc ooit "overslaan" is aangetikt zegt daar niets over.
      _klaar = await _updater.zoek(negeerOvergeslagen: true);
    } catch (e) {
      debugPrint('Bijwerken: kon niet kijken wat er klaarstaat: $e');
    }
  }

  /// Binnenhalen en starten.
  ///
  /// **Na [Updater.installeer] leest niemand dit meer.** De installer sluit deze app af; het proces
  /// is dan weg, en met hem de server die de telefoon aan het peilen was. Dat wegvallen ÍS het
  /// signaal aan de andere kant dat het begonnen is — zie het paneel op de telefoon.
  Future<void> _doe(Uitgave u) async {
    try {
      final bestand = await _updater.haal(u, voortgang: (p) => _voortgang = p);
      _fase = Bijwerkfase.installeren;
      _voortgang = 1;
      await _updater.installeer(bestand);
    } catch (e) {
      _fase = Bijwerkfase.mislukt;
      _fout = 'De pc kon niet bijwerken: $e';
    }
  }
}
