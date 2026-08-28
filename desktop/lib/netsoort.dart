/// Wifi of mobiele data, en wat de app daarmee doet.
///
/// **Waarom dit een eigen bestand is.** De keuze "welke stroomstand geldt nu" hangt van vier dingen
/// af — wat je thuis wilt, wat je onderweg wilt, of het automatisch mag, en waar je nu op zit — en
/// dat is precies het soort som dat je nergens tussen de schermcode wilt hebben staan. Hier staat
/// hij één keer, zuiver, en de bouwstraat kan hem nameten.
///
/// **Wat "adaptief" hier NIET is.** Er wordt geen bandbreedte gemeten en er wordt niet midden in een
/// nummer overgeschakeld — dat kan ook niet: het plafond staat in de URL en die wordt bij het openen
/// vastgelegd. Het zijn twee eenvoudige regels, en die staan hieronder uitgeschreven.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'lan/stroomstand.dart';
import 'settings.dart';

/// Waar dit toestel nu op zit.
///
/// `onbekend` is een volwaardig antwoord en geen fout: op een pc, op een Mac, en op elk toestel
/// waar de vraag niet beantwoord kon worden. Zie [welkeStand] voor waarom dat naar THUIS valt en
/// niet naar onderweg.
enum Netsoort { wifi, mobiel, onbekend }

/// Regel A: de netsoort kiest de sport.
///
/// **`onbekend` valt naar [thuis], en dat is met opzet de dure kant.** Een mislukte meting — een
/// kanaal dat nog niet klaar is, een platform zonder antwoord — mag je thuis nooit stilletjes je
/// hi-res kosten. Andersom kost een gemiste meting onderweg hooguit een keer meer data dan je wilde,
/// en dát merk je; een stille terugval naar cd-kwaliteit thuis merk je niet en zoek je nooit.
///
/// Staat [adaptief] uit, dan geldt [thuis] altijd — dan is er één stand en verder niets.
///
/// [noodstand] is regel B: één sport lager voor de rest van deze sessie, nadat het hapert. Zie
/// [eenSportLager].
Stroomstand welkeStand({
  required Stroomstand thuis,
  required Stroomstand onderweg,
  required bool adaptief,
  required Netsoort net,
  bool noodstand = false,
}) {
  final gekozen = (adaptief && net == Netsoort.mobiel) ? onderweg : thuis;
  return noodstand ? eenSportLager(gekozen) : gekozen;
}

/// Regel B: één sport omlaag, en nooit onder de onderste.
///
/// **En nooit vanzelf terug omhoog.** Een ladder die na een geslaagd nummer weer opklimt lokt precies
/// de hapering uit die hij net heeft opgelost, en dan zit je in een lus die om de twee nummers
/// stottert. De grendel gaat pas los als er iets verandert waar de gebruiker bij was: een andere
/// netsoort, een aangeraakte instelling, of een herstart.
Stroomstand eenSportLager(Stroomstand s) => switch (s) {
      Stroomstand.max => Stroomstand.hoog,
      Stroomstand.hoog => Stroomstand.cd,
      Stroomstand.cd => Stroomstand.cd,
    };

/// Hoeveel seconden vooruit er gelezen mag worden.
///
/// **Op wifi verandert er niets, en dat is een eis.** De driehonderd seconden zijn de reparatie van
/// 15-08-2026 voor draadloos Android Auto: hi-res FLAC over een wifi die tegelijk de autoverbinding
/// draagt. Een heel nummer vooruit hebben maakt een dip onhoorbaar. Daar mag niet aan getornd worden.
///
/// **Op mobiel is vooruitlezen niet gratis meer.** Driehonderd seconden op de cd-stand is ruwweg
/// vierendertig megabyte per nummer; skip je na twintig seconden door, dan gooi je tweeëndertig
/// megabyte weg waar je voor betaald hebt. Negentig seconden is een kleine tien megabyte en nog
/// altijd veel langer dan elke realistische dip in een 4G-verbinding.
int vooruitleesSeconden(Netsoort net) => net == Netsoort.mobiel ? 90 : 300;

/// Hetzelfde kanaal dat `tv.dart` en `cloud/device_identity.dart` al gebruiken. Een MethodChannel is
/// alleen een naam, dus een tweede handvat kost niets.
const _kanaal = MethodChannel('debridmusic/device');

/// Wat het toestel zegt dat het nu is.
///
/// Alleen Android antwoordt; overal anders komt hier [Netsoort.onbekend] uit en dat is het juiste
/// antwoord — een pc en een Mac zitten niet op een databundel. Zie [welkeStand] voor wat er met
/// `onbekend` gebeurt.
///
/// Dezelfde vorm als [initDeviceName]: `audio_service` warmt een engine op vóór de activiteit het
/// kanaal geregistreerd heeft, dus een enkele `MissingPluginException` is geen fout maar "nog niet".
Future<Netsoort> leesNetsoort() async {
  if (!Platform.isAndroid) return Netsoort.onbekend;
  for (var poging = 0; poging < 20; poging++) {
    try {
      final soort = await _kanaal.invokeMethod<String>('netsoort');
      return switch (soort) {
        'wifi' => Netsoort.wifi,
        'mobiel' => Netsoort.mobiel,
        _ => Netsoort.onbekend,
      };
    } on MissingPluginException {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    } catch (e) {
      debugPrint('Netsoort onbekend: $e');
      return Netsoort.onbekend;
    }
  }
  return Netsoort.onbekend;
}

/// Waar dit toestel op zit, en welke stroomstand daar bij hoort.
///
/// **Waarom dit zo weinig vraagt.** Eén kanaalsprong, geen schijf en geen netwerk — maar de vraag
/// stellen kost wél iets, en hem elke seconde stellen zou precies de druk zijn die deze hele
/// voorziening moet wegnemen. Dus drie momenten en niet meer: bij de start, bij het terugkeren naar
/// de voorgrond, en een klok van dertig seconden die ALLEEN loopt terwijl er muziek speelt.
class NetsoortStore extends ChangeNotifier {
  Netsoort _net = Netsoort.onbekend;
  Netsoort get net => _net;

  /// De grendel van regel B — zie [eenSportLager]. Blijft staan tot de netsoort verandert, de
  /// gebruiker de instelling aanraakt, of de app herstart.
  bool _noodstand = false;
  bool get noodstand => _noodstand;

  Timer? _klok;

  /// Zet de grendel. Meer dan één hapering in dezelfde sessie zakt niet verder — één sport is één
  /// sport, en onder de cd-stand is er niets.
  void hapering() {
    if (_noodstand) return;
    _noodstand = true;
    notifyListeners();
  }

  /// Laat de grendel los. Hoort bij een verandering waar de gebruiker bij was.
  void grendelLos() {
    if (!_noodstand) return;
    _noodstand = false;
    notifyListeners();
  }

  Future<void> ververs() async {
    final nu = await leesNetsoort();
    if (nu == _net) return;
    _net = nu;
    // Een andere netsoort is een ander netwerk, en dus een nieuwe kans. De grendel gaat los.
    _noodstand = false;
    notifyListeners();
  }

  /// De klok loopt alleen terwijl er speelt: als er niets klinkt verandert er ook niets dat ertoe
  /// doet, en dan hoeft er niets gevraagd te worden.
  void volgHetSpelen({required bool speelt}) {
    if (speelt) {
      if (_klok != null) return;
      _klok = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(ververs()));
      unawaited(ververs());
    } else {
      _klok?.cancel();
      _klok = null;
    }
  }

  /// De stand die nu geldt, gegeven wat er in de instellingen staat.
  Stroomstand geldendeStand(AppSettings s) => welkeStand(
        thuis: standUitNaam(s.stroomThuis),
        onderweg: standUitNaam(s.stroomOnderweg, terugval: Stroomstand.cd),
        adaptief: s.stroomAdaptief,
        net: _net,
        noodstand: _noodstand,
      );

  @override
  void dispose() {
    _klok?.cancel();
    _klok = null;
    super.dispose();
  }
}
