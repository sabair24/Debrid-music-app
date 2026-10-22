/// Waar een Sonos is, op enkele ms (groeperen, stap 3.3 — Saber, 21-10-2026: "pc + Sonos ongeveer, met
/// een schuif").
///
/// **Het probleem.** Een Sonos meldt zijn plek (`RelTime`) alleen in hele seconden, en laat zich niet
/// sneller of trager zetten; spoelen kan ook alleen op hele seconden, en na het spoelen buffert hij
/// eerst. Dus volgt de pc (of een ander toestel) de Sonos, en niet andersom: dat kan wel bijsturen
/// (`samen.dart`).
///
/// **De truc.** Elk antwoord "seconde N", gevraagd op t0 en binnen op t1 (pc-klok), zegt: het nummer
/// begon (E) ergens tussen `t0 − N·1000 − 1000` en `t1 − N·1000` ms. De doorsnede van al die vensters
/// wordt smal als er vragen vlak voor en vlak na een sprong naar de volgende seconde vallen — dus vraagt
/// de klok, zodra hij een schatting heeft, juist daar ([volgendeVraagOp]): elke seconde halveert het
/// venster ruwweg, tot de rondgang naar de speaker (een paar ms). Gemeten op de Move (22-10-2026, nog
/// zonder gericht vragen, om de 47 ms): 15 sprongen, nul tegenspraak, na 9 s 15 ms breed.
///
/// **Wat de doorsnede breekt.** Spoelen of een nieuw nummer: niets van vroeger past nog, dan begint de
/// reeks opnieuw ([PlekStand.onbekend] tot de eerste sprong). Een pauze: dezelfde seconde, steeds later
/// gevraagd ([PlekStand.stil]). Na stilte (de start, een pauze) telt alleen wat er vanaf de eerste sprong
/// gemeten is, plus de meting vlak daarvoor: wat de speaker zei terwijl hij nog bufferde of stilstond,
/// zou de schatting tot een seconde te vroeg trekken.
///
/// Wat overblijft is hoe lang de Sonos er zelf over doet om van die plek geluid te maken; dat zet je op
/// het oor bij met de schuif in "Samen laten spelen".
library;

import 'dart:async';
import 'dart:math';

/// Eén antwoord van de speaker: zijn plek in hele seconden, en wanneer de vraag vertrok en het antwoord
/// binnenkwam (µs, pc-klok).
typedef PlekMeting = ({int t0Us, int t1Us, int seconde});

/// Wat de metingen over de speaker zeggen.
enum PlekStand {
  /// Hij springt elke seconde een seconde verder.
  speelt,

  /// Zijn seconde staat stil (pauze, gestopt, of nog niet begonnen).
  stil,

  /// Net gespoeld of een ander nummer: nog geen sprong gezien. Niets melden: wie volgt, speelt door.
  onbekend,
}

/// Langer dan dit geen sprong naar de volgende seconde: dan speelt hij niet (µs). Ruim: bij gericht vragen
/// kan er anderhalve seconde tussen twee geziene sprongen zitten (de vraag bij de sprong valt er net voor);
/// een pauze ziet [Plekschatting.voegToe] al eerder, aan dezelfde seconde die te laat nog gemeld wordt.
const kGeenSprongNa = 2000000;

/// Zo lang na een breuk (spoelen, een nieuw nummer, de eerste meting) is de stand onbekend (µs).
const kOnbekendNaBreuk = 1500000;

/// De meting vlak voor de eerste sprong telt alleen mee als ze zo kort voor de sprong lag (µs).
const kRandHoogstens = 200000;

/// Zoveel mag een meting naast de doorsnede liggen en toch "de klok liep iets weg" zijn (µs). Meer is een
/// pauze, spoelen of een ander nummer. De Move stelt zijn klok soms in één keer ~30 ms bij (gemeten
/// 22-10-2026); met de oude vraagplanning en 30 ms speling las de klok dat als een pauze, en kreeg de Shield
/// een anker dat 227 ms verschoven was. Met de huidige planning (vlak bij en naast het venster) blijft elke
/// afwijking klein en volstaat in de nabootsing ook 30 ms; 150 is marge voor wat die niet kent. Spoelen gaat
/// per hele seconde.
const kKlokSpeling = 150000;

/// Na een bijstelling die het venster breed maakte: onbekend tot het weer zo smal is (µs).
const kHerstelBreed = 30000;

/// Hoe ver buiten het venster de klok in de smalle stand ook vraagt (µs): zie [volgendeVraagOp].
const kProefNaast = 8000;

typedef _Grens = ({int t0Us, int t1Us, int seconde, int lo, int hi});

/// De schatting van het beginmoment van het nummer uit een rij [PlekMeting]en. Zuiver, voor toetsen.
class Plekschatting {
  Plekschatting({this.venster = const Duration(seconds: 20)});

  /// Hoe lang een meting meetelt: de klok van de Sonos loopt een fractie anders dan die van de pc
  /// (tientallen ppm, een paar ms per minuut), dus oude metingen gaan eruit.
  final Duration venster;

  final List<_Grens> _grenzen = [];
  _Grens? _laatste;
  int? _sprongOpUs;
  int? _breukOpUs;
  bool _gepauzeerd = false;

  /// Een bijstelling liet het venster ineens breed achter (alle smalle grenzen spraken de nieuwe meting
  /// tegen): het midden ervan kan honderden ms naast de waarheid liggen (nagespeeld met de wandelende
  /// Move: 239 ms). Onbekend tot het weer smal is ([kHerstelBreed]).
  bool _herstel = false;
  int _sprongen = 0;
  int _lo = 0, _hi = 0;
  int _halveRondgangUs = 5000;

  /// Het beginmoment van het nummer (µs, pc-klok), het midden van de doorsnede; null zolang er in deze
  /// reeks geen sprong gezien is.
  int? get beginUs => _sprongen == 0 ? null : (_lo + _hi) ~/ 2;

  /// Hoe breed de doorsnede is (µs), of null.
  int? get breedteUs => _sprongen == 0 ? null : _hi - _lo;

  /// Hoeveel secondesprongen er in de huidige reeks gezien zijn.
  int get sprongen => _sprongen;

  /// De laatst gemelde seconde, of null.
  int? get laatsteSeconde => _laatste?.seconde;

  /// Hoe lang een vraag ongeveer onderweg is tot de speaker antwoordt (µs): de helft van de rondgang.
  int get halveRondgangUs => _halveRondgangUs;

  /// Hoe lang er al geen sprong meer was (µs), of sinds de laatste breuk als er nog geen was.
  int stilUs(int nuUs) => nuUs - (_sprongOpUs ?? _breukOpUs ?? nuUs);

  /// Wanneer de volgende vraag vertrekt (µs), na een antwoord dat op [nuUs] binnenkwam: [volgendeVraagOp] met
  /// wat deze schatting weet. Ook tijdens herstel gericht ([richtStandOp]): nagespeeld na een jump van 30–60
  /// ms duurde "onbekend" zo 3–4 s (ergst 5,9), en met gewoon druk vragen 5–9 s (ergst 19).
  int volgendeVraag(int nuUs, Random toeval) => volgendeVraagOp(
        stand: richtStandOp(nuUs),
        beginUs: beginUs,
        breedteUs: breedteUs,
        stilUs: stilUs(nuUs),
        nuUs: nuUs,
        toeval: toeval,
        halveRondgangUs: halveRondgangUs,
      );

  /// De stand om de volgende vraag op te richten: ook bij herstel gericht, want juist dan beslist een vraag
  /// bij de sprong waar hij is.
  PlekStand richtStandOp(int nuUs) {
    final stand = standOp(nuUs);
    if (stand != PlekStand.onbekend || _sprongen == 0 || _sprongOpUs == null) return stand;
    return nuUs - _sprongOpUs! < kGeenSprongNa ? PlekStand.speelt : stand;
  }

  PlekStand standOp(int nuUs) {
    if (_gepauzeerd) return PlekStand.stil;
    if (_herstel) return PlekStand.onbekend;
    if (_sprongOpUs != null && nuUs - _sprongOpUs! < kGeenSprongNa) return PlekStand.speelt;
    if (_breukOpUs != null && nuUs - _breukOpUs! < kOnbekendNaBreuk) return PlekStand.onbekend;
    return PlekStand.stil;
  }

  /// Een nieuwe meting. Geeft true terug als de reeks brak (spoelen, een ander nummer).
  bool voegToe(PlekMeting m) {
    final _Grens g = (
      t0Us: m.t0Us,
      t1Us: m.t1Us,
      seconde: m.seconde,
      lo: m.t0Us - m.seconde * 1000000 - 1000000,
      hi: m.t1Us - m.seconde * 1000000,
    );
    final vorige = _laatste;
    _laatste = g;
    final rt = m.t1Us - m.t0Us;
    if (rt >= 0) _halveRondgangUs = (_halveRondgangUs * 7 + rt ~/ 2) ~/ 8;
    if (vorige == null) {
      // De eerste meting: wat hij doet, weten we pas bij de eerste sprong.
      _breukOpUs = m.t1Us;
      _grenzen.add(g);
      _herreken();
      return false;
    }
    final sprong = m.seconde > vorige.seconde;
    final naStilte = sprong && (_gepauzeerd || _sprongOpUs == null || m.t1Us - _sprongOpUs! >= kGeenSprongNa);
    if (naStilte) {
      // De eerste sprong na de start, een pauze of een breuk: alleen de sprong zelf, en de meting vlak
      // ervoor als die kort genoeg ervoor lag (die geeft de ondergrens).
      _grenzen.clear();
      if (vorige.seconde == m.seconde - 1 && m.t1Us - vorige.t0Us <= kRandHoogstens) _grenzen.add(vorige);
      _grenzen.add(g);
      if (!_herreken()) {
        _grenzen
          ..clear()
          ..add(g);
        _herreken();
      }
      _sprongen = 1;
      _sprongOpUs = m.t1Us;
      _gepauzeerd = false;
      _herstel = false;
      return false;
    }
    final grens = m.t1Us - venster.inMicroseconds;
    final breedVoor = _hi - _lo;
    _grenzen.removeWhere((x) => x.t1Us < grens);
    _grenzen.add(g);
    if (!_herreken()) {
      final teLaat = g.lo - _hi, teVroeg = _lo - g.hi;
      if (max(teLaat, teVroeg) <= kKlokSpeling) {
        // Een fractie ernaast: de klok van de speaker liep iets weg. De oudste eruit tot het weer past.
        while (_grenzen.length > 1 && !_herreken()) {
          _grenzen.removeAt(0);
        }
        if (_hi - _lo > max(kHerstelBreed, breedVoor * 3)) _herstel = true;
      } else {
        _grenzen
          ..clear()
          ..add(g);
        _herreken();
        _sprongen = 0;
        _herstel = false;
        if (m.seconde == vorige.seconde) {
          // Dezelfde seconde, maar veel later dan hij zou moeten: hij staat stil (pauze, of hij hapert).
          // Meteen stil, en de schatting niet meer gebruiken: in de eerste seconde van een pauze zou ze
          // anders nog wegschuiven terwijl hij "speelt".
          _gepauzeerd = true;
          return false;
        }
        // Terug, of veel te ver vooruit: gespoeld, of een ander nummer.
        _sprongOpUs = null;
        _gepauzeerd = false;
        _breukOpUs = m.t1Us;
        return true;
      }
    }
    if (sprong) {
      _sprongen++;
      _sprongOpUs = m.t1Us;
    }
    if (_herstel && _hi - _lo <= kHerstelBreed) _herstel = false;
    return false;
  }

  bool _herreken() {
    var lo = -1 << 62, hi = 1 << 62;
    for (final g in _grenzen) {
      lo = max(lo, g.lo);
      hi = min(hi, g.hi);
    }
    if (lo > hi) return false;
    _lo = lo;
    _hi = hi;
    return true;
  }

  /// Helemaal opnieuw (een opdracht die de plek verzet: spoelen, pauze, play).
  void wis(int nuUs) {
    _grenzen.clear();
    _laatste = null;
    _sprongen = 0;
    _sprongOpUs = null;
    _gepauzeerd = false;
    _herstel = false;
    _breukOpUs = nuUs;
  }
}

/// Wanneer de volgende vraag vertrekt (µs, pc-klok).
///
/// - Hij speelt en er is een schatting: gericht. Elke seconde één vraag midden in de seconde (die zegt
///   zeker of hij nog doorloopt) en vragen bij de verwachte sprong: boven 100 ms twee, op een kwart aan
///   weerszijden (dichter bij elkaar passen ze niet: tussen twee vragen zit minstens 25 ms); tot 15 ms
///   één, rond het midden van het venster — het antwoord valt voor of na de sprong en halveert het; daarna
///   om de beurt één binnen het venster (dat houdt het smal), één [kProefNaast] ervoor en één erna. Die
///   laatste twee zijn nodig: verschuift de sprong (de Move stelt zijn klok bij), dan zeggen vragen
///   binnen het venster alleen nog "nog niet gesprongen" en spreken ze het oude venster nooit tegen; een
///   vraag ernaast doet dat wel, en dan gaan de oudste metingen eruit. Aan BEIDE kanten, vast om de beurt
///   en niet willekeurig: een te laat venster spreekt alleen een vraag aan de vroege kant tegen (nagespeeld
///   met de wandelende Move: 7 s lang geen vroege vraag, en de schatting liep 57 ms weg). Eén per seconde:
///   twee vlak na elkaar passen niet (tussen twee vragen zit minstens 25 ms plus de rondgang).
/// - Anders druk (om de ~100 ms) zolang het kort geleden is: dan valt er snel een vraag vlak bij een
///   sprong. Na tien seconden stilte rustiger, na een minuut heel rustig (een speaker op pauze hoeft
///   niet tien keer per seconde gevraagd te worden).
///
/// Altijd een beetje willekeurig, zodat de vragen niet steeds op dezelfde plek vallen.
int volgendeVraagOp({
  required PlekStand stand,
  required int? beginUs,
  required int? breedteUs,
  required int stilUs,
  required int nuUs,
  required Random toeval,
  int halveRondgangUs = 5000,
}) {
  if (stand != PlekStand.speelt || beginUs == null || breedteUs == null) {
    if (stilUs > 60000000) return nuUs + (800 + toeval.nextInt(200)) * 1000;
    if (stilUs > 10000000) return nuUs + (150 + toeval.nextInt(100)) * 1000;
    return nuUs + (70 + toeval.nextInt(60)) * 1000;
  }
  final w = max(breedteUs, 2000);
  final vroegst = nuUs + 25000;
  int? beste;
  final k0 = (vroegst - beginUs) ~/ 1000000;
  for (var k = k0; k <= k0 + 2; k++) {
    final rand = beginUs + k * 1000000;
    final doelen = [
      rand + 500000,
      if (w > 100000) ...[
        rand - w ~/ 4,
        rand + w ~/ 4,
      ] else if (w > 15000)
        rand - w ~/ 8 + toeval.nextInt(w ~/ 4 + 1)
      else
        switch (k % 3) {
          0 => rand - w ~/ 2 + toeval.nextInt(w + 1),
          1 => rand - w ~/ 2 - kProefNaast,
          _ => rand + w ~/ 2 + kProefNaast,
        },
    ];
    for (final d in doelen) {
      // Zo vertrekken dat het antwoord op het doel valt.
      final start = d - halveRondgangUs;
      if (start >= vroegst && (beste == null || start < beste)) beste = start;
    }
  }
  return beste ?? vroegst;
}

/// Volgt één speaker met [Plekschatting] zolang er toestellen met hem meespelen.
class SpeakerKlok {
  SpeakerKlok({
    required this.vraag,
    required this.bijVerandering,
    this.bijBreuk,
    int Function()? klokUs,
    Random? toeval,
  }) : _klokUs = klokUs ?? (() => DateTime.now().microsecondsSinceEpoch),
       _toeval = toeval ?? Random();

  /// Vraag de speaker zijn plek in hele seconden, of null als hij niet antwoordt.
  final Future<int?> Function() vraag;

  /// De schatting veranderde genoeg om de volgers te laten weten, of hij speelt niet meer (of weer).
  final void Function() bijVerandering;

  /// De reeks brak (spoelen, een nieuw nummer): de cast kan dan meteen kijken welk nummer er speelt.
  final void Function()? bijBreuk;

  final int Function() _klokUs;
  final Random _toeval;
  final Plekschatting schatting = Plekschatting();

  Timer? _tik;
  bool _aan = false;
  int? _gemeldBegin;
  PlekStand? _gemeld;
  int _gemeldOp = 0;

  /// Nu, op de klok van de pc (µs).
  int get nuUs => _klokUs();

  /// Wat er nu over de speaker te zeggen is: speelt hij, en waar is hij (ms; bij stilstand het midden van
  /// zijn stilstaande seconde). Null zolang er niets te melden valt ([PlekStand.onbekend], of nog nooit
  /// een sprong of een stilstand gezien).
  ({bool speelt, int positieMs})? get plekNu {
    final nu = _klokUs();
    switch (schatting.standOp(nu)) {
      case PlekStand.speelt:
        final b = schatting.beginUs;
        return b == null ? null : (speelt: true, positieMs: (nu - b) ~/ 1000);
      case PlekStand.stil:
        final s = schatting.laatsteSeconde;
        return s == null ? null : (speelt: false, positieMs: s * 1000 + 500);
      case PlekStand.onbekend:
        return null;
    }
  }

  bool get aan => _aan;

  void start() {
    if (_aan) return;
    _aan = true;
    _gemeld = null;
    _gemeldBegin = null;
    schatting.wis(_klokUs());
    _plan(Duration.zero);
  }

  void stop() {
    _aan = false;
    _tik?.cancel();
    _tik = null;
  }

  /// Iets verzette de plek (spoelen, pauze, play): opnieuw meten, druk.
  void verstoord() {
    schatting.wis(_klokUs());
    if (_aan) _plan(Duration.zero);
  }

  void _plan(Duration na) {
    _tik?.cancel();
    _tik = Timer(na, () => unawaited(_meet()));
  }

  Future<void> _meet() async {
    if (!_aan) return;
    final t0 = _klokUs();
    int? s;
    try {
      s = await vraag();
    } catch (_) {
      s = null;
    }
    final t1 = _klokUs();
    if (!_aan) return;
    if (s != null && schatting.voegToe((t0Us: t0, t1Us: t1, seconde: s))) bijBreuk?.call();
    _misschienMelden(t1);
    final volgende = schatting.volgendeVraag(t1, _toeval);
    _plan(Duration(microseconds: max(0, volgende - _klokUs())));
  }

  void _misschienMelden(int nuUs) {
    final stand = schatting.standOp(nuUs);
    if (stand == PlekStand.onbekend) return;
    if (stand == PlekStand.stil) {
      if (_gemeld == PlekStand.stil || schatting.laatsteSeconde == null) return;
      _gemeld = stand;
      _gemeldBegin = null;
      _gemeldOp = nuUs;
      bijVerandering();
      return;
    }
    final begin = schatting.beginUs;
    if (begin == null) return;
    final verschoven = _gemeldBegin == null || (begin - _gemeldBegin!).abs() > 3000;
    if (_gemeld != PlekStand.speelt || (verschoven && nuUs - _gemeldOp > 300000)) {
      _gemeld = stand;
      _gemeldBegin = begin;
      _gemeldOp = nuUs;
      bijVerandering();
    }
  }
}
