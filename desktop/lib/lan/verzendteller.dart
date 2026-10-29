/// Wat de pc werkelijk naar elk toestel stuurt — per adres, per soort verkeer, elk kwartier samengevat in `verbruik.log`.
///
/// **Waarom.** Saber, 27-10-2026: *"data verbruik buitenshuis … is echt nog veel. ik wil een volledige analyse"*.
/// `stroom.log` noemde per gestart nummer de grootte van het bestand — wat de pc AANBOOD. Of dat ook over de lijn ging,
/// stond nergens: een speler die na een seconde afhaakt en een telefoon die een heel nummer vooruit binnenhaalt, gaven
/// dezelfde regel. Gemeten in stroom.log die dag: Giorgio by Moroder (54 MB) tien keer vanaf een mobiel adres, Foreigner
/// vier keer binnen vijf seconden. Hier staat wat er werkelijk de deur uit ging.
///
/// Een nummer krijgt een eigen regel met zijn naam zodra er meer dan 1 MB van verstuurd is; de rest (hoezen, de
/// catalogus, de aanvragen) staat in de samenvatting per kwartier.
library;

import 'dart:async';
import 'dart:io' show InternetAddress;

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../dataverbruik.dart' show Verkeerssoort, bytesZin, dagSleutel;
import 'tokens.dart' show bronIsThuis, toestelWeg;

/// Langs welke weg [adres] binnenkomt: 'thuis', 'tailscale' of 'buiten' ([toestelWeg]). Je eigen publieke adres
/// ([publiek]) telt als thuis — zo praat de Mac thuis via de eigen deur (21-10-2026), en dat is geen mobiele data.
String wegVanAdres(String adres, {String? publiek}) {
  final a = InternetAddress.tryParse(adres.startsWith('::ffff:') ? adres.substring(7) : adres);
  if (a == null) return 'buiten';
  if (bronIsThuis(a, publiek)) return 'thuis';
  return toestelWeg(a) == 'Tailscale' ? 'tailscale' : 'buiten';
}

class Verzendteller {
  Verzendteller({required this.log, this.publiek, DateTime Function()? klok}) : _klok = klok ?? DateTime.now;

  final void Function(String regel) log;

  /// Het publieke adres van thuis (de modem), of null — zie [wegVanAdres].
  final String? Function()? publiek;
  final DateTime Function() _klok;
  Timer? _kwartier;

  /// Per adres, per soort: bytes en aantal antwoorden, sinds de vorige samenvatting.
  final Map<String, Map<Verkeerssoort, ({int bytes, int keer})>> _per = {};

  /// Een eigen regel vanaf deze grootte.
  static const int kEigenRegel = 1 << 20;

  /// Wat de pc VANDAAG stuurde, per weg ([wegVanAdres]) en soort — voor Instellingen › Info op de pc. De sleutel is
  /// "weg|soort"; om middernacht leeg.
  static final ValueNotifier<Map<String, int>> vandaag = ValueNotifier(const {});
  static String _vandaagDag = '';

  void start() => _kwartier ??= Timer.periodic(const Duration(minutes: 15), (_) => kwartier());

  void stop() {
    _kwartier?.cancel();
    _kwartier = null;
  }

  /// [bytes] van soort [soort] gingen naar [adres]. [wat]: het nummer; [totaal]: hoe groot het hele bestand is; [vraag]:
  /// de Range-kop en de omzetting, voor de eigen regel.
  void tel(String adres, Verkeerssoort soort, int bytes, {String? wat, int? totaal, String? vraag, String? pad}) {
    if (bytes <= 0) return;
    final m = _per.putIfAbsent(adres, () => {});
    final oud = m[soort] ?? (bytes: 0, keer: 0);
    m[soort] = (bytes: oud.bytes + bytes, keer: oud.keer + 1);
    // Muziek en hoezen tellen per nummer al mee; het gaat om de kleine vragen die zich opstapelen.
    if (pad != null && soort != Verkeerssoort.muziek && soort != Verkeerssoort.hoezen) {
      final p = _paden.putIfAbsent(adres, () => {});
      p[pad] = (p[pad] ?? 0) + 1;
    }
    final dag = dagSleutel(_klok());
    final weg = wegVanAdres(adres, publiek: publiek?.call());
    final k = '$weg|${soort.name}';
    final v = dag == _vandaagDag ? vandaag.value : const <String, int>{};
    _vandaagDag = dag;
    vandaag.value = {...v, k: (v[k] ?? 0) + bytes};
    if (bytes >= kEigenRegel) {
      log('${_dag()}  $adres ($weg)  ${soort.name} ${bytesZin(bytes)}'
          '${totaal != null && totaal > 0 ? ' van ${bytesZin(totaal)}' : ''}'
          '${wat == null ? '' : '  "$wat"'}${vraag == null || vraag.isEmpty ? '' : '  ($vraag)'}');
    }
  }

  /// De samenvatting per adres, en leeg daarna.
  void kwartier() {
    for (final e in _per.entries) {
      final delen = [
        for (final s in Verkeerssoort.values)
          if (e.value[s] case final x?) '${s.name} ${bytesZin(x.bytes)} (${x.keer}×)',
      ];
      final som = e.value.values.fold(0, (a, b) => a + b.bytes);
      final drukst = drukstePaden(_paden[e.key] ?? const {});
      log('${_dag()}  kwartier  ${e.key} (${wegVanAdres(e.key, publiek: publiek?.call())})  ${bytesZin(som)}: '
          '${delen.join(', ')}${drukst.isEmpty ? '' : ' · meest: $drukst'}');
    }
    _per.clear();
    _paden.clear();
  }

  /// Per adres: hoe vaak elk pad gevraagd werd (behalve muziek en hoezen), sinds de vorige samenvatting.
  ///
  /// **Waarom (29-10-2026).** Op een zwakke wifi vroeg de gsm in een kwartier 505 keer iets van soort "zones" (~elke
  /// 2 s), en welk pad dat was stond nergens.
  final Map<String, Map<String, int>> _paden = {};

  /// De drie drukste paden vanaf 20 keer, als "pad 300×, pad 120×". Leeg als er geen is.
  static String drukstePaden(Map<String, int> paden) {
    final rij = paden.entries.where((e) => e.value >= 20).toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in rij.take(3)) '${e.key} ${e.value}×'].join(', ');
  }

  String _dag() {
    final t = _klok();
    return '${t.day.toString().padLeft(2, '0')}-${t.month.toString().padLeft(2, '0')}';
  }
}
