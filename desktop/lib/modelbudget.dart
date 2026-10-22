/// Hoeveel de radio het taalmodel mag vragen — over alle radio's samen, ook na een herstart.
///
/// **Waarom.** Tot 22-10-2026 vroeg de radio het model twee dingen, allebei bij de start: één lijst
/// (`maakRadiolijst`, 25–30 s) en één sfeeroordeel over wat Deezer voorstelde. Vanaf nu vraagt hij ook
/// onderweg — een sfeeroordeel per bijvulronde, en een nieuwe lijst als de buurt op is (plan
/// "eindeloos en lerend", uitlevering 2). Elke vraag kost geld op Sabers sleutel; zonder grens kon een
/// radio die een nacht doorloopt er honderden stellen.
///
/// **De grenzen** (plan van 08-10-2026, door Saber goedgekeurd): lijsten hoogstens [kLijstenPerUur] per
/// uur over alle radio's, minstens [kLijstAdem] ertussen, en [kLijstenPerRadio] per radio; sfeervragen
/// hoogstens [kSfeerPerUur] per uur. De vraag bij een START (en bij afstemmen: daar vroeg je zelf om)
/// telt mee, maar mag altijd — een radio die niet mag beginnen is erger dan een dure radio.
///
/// Geteld wordt per API-AANROEP, niet per vraag: `maakRadiolijst` probeert het een tweede keer als de
/// eerste te weinig gaf, en die tweede kost evenveel.
library;

import 'dart:convert';
import 'dart:io';

const int kLijstenPerUur = 3;
const Duration kLijstAdem = Duration(minutes: 20);
const int kLijstenPerRadio = 12;
const int kSfeerPerUur = 12;

/// Mag het, en zo niet: waarom (voor het logboek).
typedef Budgetantwoord = ({bool mag, String? waarom});

class Modelbudget {
  Modelbudget({this.pad, DateTime Function()? klok}) : _klok = klok ?? DateTime.now {
    _laad();
  }

  /// Waar het op schijf staat (`modelbudget.json`), of null (toetsen, een toestel zonder model).
  final String? pad;
  final DateTime Function() _klok;

  /// De aanroepen van het laatste uur die voor de grens tellen (niet die van een start).
  final List<DateTime> _lijsten = [];
  final List<DateTime> _sfeer = [];

  /// Wanneer de laatste lijst onderweg gevraagd werd, voor [kLijstAdem].
  DateTime? _laatsteLijst;

  /// Lijsten per radio (`RadioBesturing.sessie`), de start meegeteld. Niet op schijf: een herstart is een
  /// nieuwe radio.
  final Map<int, int> _perRadio = {};

  static const _uur = Duration(hours: 1);

  void _snoei() {
    final grens = _klok().subtract(_uur);
    _lijsten.removeWhere((t) => !t.isAfter(grens));
    _sfeer.removeWhere((t) => !t.isAfter(grens));
  }

  static String _tijd(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Mag radio [radio] nu (onderweg) een lijst vragen?
  Budgetantwoord lijst(int radio) {
    _snoei();
    if ((_perRadio[radio] ?? 0) >= kLijstenPerRadio) {
      return (mag: false, waarom: '$kLijstenPerRadio lijsten voor deze radio');
    }
    if (_lijsten.length >= kLijstenPerUur) {
      return (mag: false, waarom: '$kLijstenPerUur per uur (volgende om ${_tijd(_lijsten.first.add(_uur))})');
    }
    final vorige = _laatsteLijst;
    if (vorige != null && _klok().difference(vorige) < kLijstAdem) {
      return (mag: false, waarom: 'minstens ${kLijstAdem.inMinutes} min ertussen (om ${_tijd(vorige.add(kLijstAdem))})');
    }
    return (mag: true, waarom: null);
  }

  /// Eén API-aanroep voor een lijst. [start]: bij het starten (of afstemmen) — telt voor de radio, niet voor
  /// de uurgrens.
  void lijstGevraagd(int radio, {bool start = false}) {
    _perRadio[radio] = (_perRadio[radio] ?? 0) + 1;
    if (start) return;
    final nu = _klok();
    _lijsten.add(nu);
    _laatsteLijst = nu;
    _bewaar();
  }

  /// Mag er nu (onderweg) een sfeervraag uit?
  Budgetantwoord sfeer() {
    _snoei();
    if (_sfeer.length >= kSfeerPerUur) {
      return (mag: false, waarom: '$kSfeerPerUur per uur (volgende om ${_tijd(_sfeer.first.add(_uur))})');
    }
    return (mag: true, waarom: null);
  }

  /// Eén sfeervraag; [start] zoals bij [lijstGevraagd].
  void sfeerGevraagd({bool start = false}) {
    if (start) return;
    _sfeer.add(_klok());
    _bewaar();
  }

  void _laad() {
    final p = pad;
    if (p == null) return;
    try {
      final f = File(p);
      if (!f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      List<DateTime> lees(Object? l) => [
            if (l is List)
              for (final ms in l)
                if (ms is int) DateTime.fromMillisecondsSinceEpoch(ms)
          ];
      _lijsten.addAll(lees(j['lijsten']));
      _sfeer.addAll(lees(j['sfeer']));
      final laatste = j['laatsteLijst'];
      if (laatste is int) _laatsteLijst = DateTime.fromMillisecondsSinceEpoch(laatste);
      _snoei();
    } catch (_) {/* een kapot bestand: dan begint de telling opnieuw — hoogstens één uur te ruim */}
  }

  void _bewaar() {
    final p = pad;
    if (p == null) return;
    _snoei();
    try {
      File(p).writeAsStringSync(jsonEncode({
        'lijsten': [for (final t in _lijsten) t.millisecondsSinceEpoch],
        'sfeer': [for (final t in _sfeer) t.millisecondsSinceEpoch],
        if (_laatsteLijst case final t?) 'laatsteLijst': t.millisecondsSinceEpoch,
      }));
    } catch (_) {/* dan telt alleen het geheugen; na een herstart hoogstens één uur te ruim */}
  }
}
