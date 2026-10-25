/// Het schudlogboek: elke shuffle van de hele bibliotheek, en wat er daarna met elk nummer gebeurde.
///
/// **Waarom (Saber, 25-10-2026).** *"hou vanaf nu ook een log bij van alle shuffels die ik doe van de hele bibliotheek,
/// dan kunnen we oordelen wat goed gaat en wat niet, of minder goed"* — na "hierna 400 ????", waar de wachtrij in orde
/// bleek (1769 nummers, geen dubbel) en alleen het scherm het venster telde. Over een shuffle oordelen kan alleen met wat
/// er werkelijk in zat en wat je ermee deed.
///
/// **Wat er in staat.** Per shuffle een kop: hoeveel nummers van hoeveel, of er dubbele in zitten, hoeveel nooit
/// gehoord (en hoeveel daarvan vooraan), hoeveel van de eerste honderd ook vooraan stonden bij de vorige shuffle ("niet
/// altijd dezelfde"), hoe vaak dezelfde artiest direct na elkaar komt, en de eerste dertig. Daarna per nummer dat
/// voorbijkomt: gehoord, of na hoeveel overgeslagen. Bij de volgende shuffle een slotregel van de vorige.
///
/// **Waar het landt** beslist [SchudLogboek.schrijf]: op de pc in `schud.log`, op een toestel naar de pc
/// (`/api/diag/schud`, via [SchudZender]) — zo staat alles op één plek.
library;

import 'dart:async';

import 'models.dart';
import 'organize.dart' show artistKey;
import 'schudvolgorde.dart' show Speelstand, telMeeAlsGespeeld;

/// Vanaf welk deel van de bibliotheek een shuffle "de hele bibliotheek" is: een album of artiest schudden telt niet.
const double kHeleBibliotheek = .9;

/// Hoeveel nummers de kop bij naam noemt.
const int kSchudKopNamen = 30;

/// Over hoeveel nummers vooraan de kop telt en vergelijkt met de vorige shuffle.
const int kSchudVooraan = 100;

/// Over hoeveel nummers de kop telt hoe vaak dezelfde artiest direct na elkaar komt.
const int kSchudNaastElkaar = 500;

/// Is een rij van [n] nummers de hele bibliotheek van [bibliotheek]?
bool isHeleBibliotheek(int n, int bibliotheek) => bibliotheek > 0 && n >= bibliotheek * kHeleBibliotheek;

/// Hoe vaak dezelfde artiest direct na de vorige komt.
int zelfdeArtiestNaElkaar(List<Track> rij) {
  var n = 0;
  for (var i = 1; i < rij.length; i++) {
    if (artistKey(rij[i].artist) == artistKey(rij[i - 1].artist)) n++;
  }
  return n;
}

String _mmss(Duration d) {
  final s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String _datum(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}-${t.month.toString().padLeft(2, '0')}-${t.year} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

class SchudLogboek {
  SchudLogboek({required this.schrijf, required this.bibliotheek, this.speelstand, DateTime Function()? klok})
      : _klok = klok ?? DateTime.now;

  /// Waar de regels heen gaan.
  final void Function(List<String> regels) schrijf;

  /// Hoeveel nummers de bibliotheek op dit toestel heeft.
  final int Function() bibliotheek;

  /// Hoe vaak en wanneer een nummer klonk (voor "nooit gehoord" en de kop).
  final Speelstand? Function(Track t)? speelstand;

  final DateTime Function() _klok;

  /// De shuffle die nu loopt (zijn nummer in het logboek), en bij welke trekking van de speler hij hoort.
  String? _id;
  int? _generatie;
  int _gehoord = 0, _overgeslagen = 0;
  Duration _luistertijd = Duration.zero;
  DateTime? _begon;

  /// Wat er bij de vorige shuffle vooraan stond (in dit proces).
  Set<String> _vorigeVooraan = const {};

  String? get sessie => _id;

  /// Een nieuwe geschudde volgorde. Alleen de hele bibliotheek telt ([isHeleBibliotheek]); de eerste [vanaf] stonden al
  /// vast (het shuffle-icoontje houdt wat al klonk vooraan). [generatie] is de trekking van de speler: nummers die
  /// daarna voorbijkomen ([voorbij]) horen alleen bij deze shuffle als ze dezelfde dragen.
  void geschud(List<Track> volgorde, {required String hoe, int vanaf = 0, required int generatie}) {
    final bib = bibliotheek();
    if (!isHeleBibliotheek(volgorde.length, bib)) return;
    final nu = _klok();
    final regels = <String>[if (_id != null) _slot(nu)];
    _id = (nu.millisecondsSinceEpoch ~/ 1000).toRadixString(36);
    _generatie = generatie;
    _gehoord = _overgeslagen = 0;
    _luistertijd = Duration.zero;
    _begon = nu;

    final staart = volgorde.sublist(vanaf.clamp(0, volgorde.length));
    final uniek = {for (final t in staart) t.path}.length;
    bool nooit(Track t) => (speelstand?.call(t)?.aantal ?? 0) <= 0;
    final vooraan = staart.take(kSchudVooraan).toList();
    final vooraanPaden = {for (final t in vooraan) t.path};
    final overlap = _vorigeVooraan.isEmpty ? null : vooraanPaden.intersection(_vorigeVooraan).length;
    _vorigeVooraan = vooraanPaden;
    regels.add([
      'SCHUD ${_datum(nu)} #$_id ($hoe): ${volgorde.length} van $bib nummers in de bibliotheek',
      if (vanaf > 0) 'de eerste $vanaf blijven staan',
      '$uniek verschillend, ${staart.length - uniek} dubbel',
      'nooit gehoord ${staart.where(nooit).length} (in de eerste ${vooraan.length}: ${vooraan.where(nooit).length})',
      overlap == null
          ? 'eerste shuffle sinds de start'
          : 'van de eerste ${vooraan.length} stonden er $overlap ook vooraan bij de vorige shuffle',
      'zelfde artiest direct na elkaar in de eerste $kSchudNaastElkaar: '
          '${zelfdeArtiestNaElkaar(staart.take(kSchudNaastElkaar).toList())}',
    ].join(' · '));
    regels.add('  #$_id eerste $kSchudKopNamen: ${[
      for (var i = 0; i < staart.length && i < kSchudKopNamen; i++) '${i + 1}. ${_naam(staart[i])} ${_stand(staart[i], nu)}',
    ].join(' · ')}');
    schrijf(regels);
  }

  /// Een nummer is voorbij: [geluisterd] lang gehoord, op [plek] van [lengte], en hoorde bij trekking [generatie]. Alleen
  /// als het bij de lopende shuffle hoort.
  void voorbij(Track t,
      {required int plek,
      required int lengte,
      required bool shuffle,
      required int generatie,
      required Duration geluisterd,
      Duration? duur}) {
    if (_id == null || !shuffle || generatie != _generatie || !isHeleBibliotheek(lengte, bibliotheek())) return;
    final gehoord = telMeeAlsGespeeld(geluisterd: geluisterd, duur: duur);
    if (gehoord) {
      _gehoord++;
    } else {
      _overgeslagen++;
    }
    _luistertijd += geluisterd;
    final van = duur != null && duur > Duration.zero ? ' van ${_mmss(duur)}' : '';
    schrijf([
      '  #$_id ${plek + 1}/$lengte ${_naam(t)}: ${gehoord ? 'gehoord ${_mmss(geluisterd)}$van' : 'overgeslagen na ${_mmss(geluisterd)}$van'}',
    ]);
  }

  String _slot(DateTime nu) {
    final samen = _gehoord + _overgeslagen;
    final deel = samen == 0 ? 0 : (_overgeslagen * 100 / samen).round();
    final duurde = _begon == null ? '' : ', ${nu.difference(_begon!).inMinutes} min';
    return '  #$_id klaar: $samen nummers voorbij, $_gehoord gehoord, $_overgeslagen overgeslagen ($deel %), '
        '${_luistertijd.inMinutes} min geluisterd$duurde';
  }

  String _naam(Track t) => '${t.artist} — ${t.title}';

  String _stand(Track t, DateTime nu) {
    final s = speelstand?.call(t);
    if (s == null || s.aantal <= 0) return '[nooit]';
    final dagen = s.laatstMs <= 0 ? null : nu.difference(DateTime.fromMillisecondsSinceEpoch(s.laatstMs)).inDays;
    return '[${s.aantal}×${dagen == null ? '' : ', $dagen d'}]';
  }
}

/// Stuurt de regels van een toestel in bundels naar de pc: na vijf seconden, of meteen bij veel. Mislukt het (geen pc),
/// dan blijven ze bewaard en gaat het een minuut later opnieuw. Hoogstens [kSchudWachtrij] regels: wat er langer niet weg
/// kan, valt vooraan af.
class SchudZender {
  SchudZender(this.stuur);

  final Future<void> Function(List<String> regels) stuur;
  final _wacht = <String>[];
  Timer? _klok;
  bool _bezig = false;

  void voegToe(List<String> regels) {
    _wacht.addAll(regels);
    if (_wacht.length > kSchudWachtrij) _wacht.removeRange(0, _wacht.length - kSchudWachtrij);
    _klok ??= Timer(kSchudBundel, _verstuur);
  }

  Future<void> _verstuur() async {
    _klok = null;
    if (_bezig || _wacht.isEmpty) return;
    _bezig = true;
    final deze = List.of(_wacht.take(kSchudPerZending));
    try {
      await stuur(deze);
      _wacht.removeRange(0, deze.length);
      if (_wacht.isNotEmpty) _klok ??= Timer(kSchudBundel, _verstuur);
    } catch (_) {
      _klok ??= Timer(kSchudOpnieuw, _verstuur);
    } finally {
      _bezig = false;
    }
  }

  /// Wat er nog niet bij de pc is.
  int get wachtend => _wacht.length;

  void dispose() => _klok?.cancel();
}

const kSchudBundel = Duration(seconds: 5);
const kSchudOpnieuw = Duration(minutes: 1);
const kSchudWachtrij = 2000;
const kSchudPerZending = 200;

/// Hoe groot schud.log op de pc mag worden: genoeg voor weken luisteren (een nummer is één regel, een shuffle een paar
/// kilobyte), om over te kunnen oordelen.
const kSchudLogBytes = 4 * 1024 * 1024;
