/// De pc haalt nummers op voor de radio van een gekoppeld toestel.
///
/// **Wat hier wél en niet gebeurt.** De radio zélf draait op het toestel waar je naar kijkt: het plan,
/// de speelrij, hoeveel er vooruit moet staan. Dat is dezelfde verdeling als bij elke andere download
/// in deze app — de pc doet het werk dat alleen daar kan (zoeken op Soulseek, downloaden, opbergen) en
/// verder niets.
///
/// Eén ding houdt de pc wél zelf vast, en dat is de reden dat deze klasse bestaat in plaats van één
/// route: de Soulseek-AANMELDING. Soulseek staat vier aanmeldingen per tien minuten toe en sluit de
/// sessie na 120 seconden stilte. Zou elke haal zijn eigen sessie openen, dan is het account na een
/// half uur radio geblokkeerd — en `_searchOnce` slikt die fout, dus je zou het niet eens merken: de
/// radio speelt dan gewoon door met alleen wat je al hebt.
library;

import 'dart:async';

import '../library.dart';
import '../settings.dart';
import '../online.dart';

/// Hoe lang een afgelopen haal opvraagbaar blijft.
///
/// Ruim, want het toestel peilt om de paar seconden en mag er best een keer een overslaan. Maar niet
/// eeuwig: een radio van vijfhonderd nummers zou anders vijfhonderd antwoorden in het geheugen
/// houden tot de pc herstart.
const Duration _bewaartijd = Duration(minutes: 10);

/// Hoe lang een radio-leen blijft staan zonder dat er iets gevraagd wordt.
///
/// Het toestel laat de leen netjes los als je de radio afsluit, maar een telefoon die uit je hand
/// valt of een wifi die wegvalt doet dat niet. Dan hoort de aanmelding vanzelf af te lopen in plaats
/// van tot de volgende herstart open te blijven.
const Duration _leenverloop = Duration(minutes: 30);

/// Eén haal, zoals het toestel hem terugziet.
class Radiohaal {
  Radiohaal(this.id);
  final String id;
  String stand = 'onderweg';
  String? pad;
  DateTime? klaarOm;
}

/// De pc-kant van een radio op een gekoppeld toestel.
class Radiohaler {
  Radiohaler(this.downloads, this.soulseek, this.library, this.instellingen);

  final DownloadManager? downloads;
  final SoulseekService? soulseek;

  /// De bibliotheek van DEZE pc.
  ///
  /// **Zonder dit werkt de radio op een telefoon niet, en op een manier die je niet ziet.** Een haal
  /// landt hier keurig op schijf — maar de bibliotheek van de pc weet daar niets van tot de volgende
  /// volledige scan. De catalogus die de telefoon ophaalt is dus nog die van vóór de landing, het
  /// nummer staat er niet in, en de radio noteert de haal als MISLUKT. Het bestand ligt er dan wel,
  /// en niemand die het weet.
  final LibraryStore library;

  /// Om een hoes op te halen voor wat er net geland is. Null op een pc zonder instellingen (alleen
  /// in toetsen); dan komt de hoes er bij de volgende volledige scan alsnog.
  final AppSettings? instellingen;

  final Map<String, Radiohaal> _halen = {};
  void Function()? _los;
  Timer? _verloop;
  int _volgnummer = 0;

  /// Wat er in de weg staat, of null. Neemt bij succes meteen de aanmelding vast.
  String? begin() {
    final s = soulseek;
    if (s == null || downloads == null) return 'Deze pc kan niets ophalen.';
    if (!s.available) {
      return 'Op de pc staat geen Soulseek-login. Zonder die kan de radio niets ophalen wat je nog '
          'niet hebt.';
    }
    final waarom = s.whyNotLogin;
    if (waarom != null) return 'Soulseek doet even niet mee: $waarom';
    _los ??= s.leaseVoorRadio();
    _verloop?.cancel();
    _verloop = Timer(_leenverloop, einde);
    return null;
  }

  /// De aanmelding weer loslaten. Mag vaker dan één keer.
  ///
  /// Staakt ook wat er loopt. Deze weg wordt niet alleen bewandeld als je zelf afsluit maar ook door
  /// [_leenverloop] — een telefoon die uit je hand valt — en juist dan is doorhalen het laatste wat
  /// er moet gebeuren: er kijkt niemand meer naar het antwoord.
  void einde() {
    _verloop?.cancel();
    _verloop = null;
    staak();
    final los = _los;
    _los = null;
    los?.call();
  }

  /// Alles wat nu loopt afbreken, maar de aanmelding vasthouden.
  ///
  /// Dat onderscheid is er omdat een NIEUWE radio op hetzelfde toestel de oude opruimt zonder de
  /// aanmelding kwijt te willen; zie `Radiobron.staak` aan de andere kant van de lijn.
  void staak() {
    downloads?.staakRadiohalen();
    // En de boekhouding meteen bij: het toestel peilt om de drie seconden, en een haal die
    // 'onderweg' blijft heten terwijl er niets meer gebeurt laat die peiling acht minuten doorgaan.
    for (final h in _halen.values) {
      if (h.stand != 'onderweg') continue;
      h.stand = 'mislukt';
      h.klaarOm = DateTime.now();
    }
  }

  /// Eén nummer gaan halen. Keert METEEN terug met een nummer om naar te vragen.
  ///
  /// Meteen terug en niet pas als het bestand er is, en dat is geen detail: een haal duurt tot drie
  /// keer `kMaxWacht`, oftewel een minuut of vier. Een HTTP-verzoek dat zo lang openstaat is op een
  /// telefoon die intussen op slot gaat gewoon weg — en dan weet niemand meer of er nog iets
  /// gebeurt. Precies dezelfde reden
  /// waarom `enqueueSoulseekBest` een `wachtOpAfloop` heeft.
  Radiohaal haal({
    required String artiest,
    required String titel,
    int? seconden,
    int? jaar,
  }) {
    _ruimOp();
    // De leen kan verlopen zijn terwijl de radio nog loopt; hem hier opnieuw vastnemen is goedkoper
    // dan een radio die halverwege stil ophoudt met halen.
    begin();
    final haal = Radiohaal('r${++_volgnummer}');
    _halen[haal.id] = haal;
    unawaited(() async {
      String? pad;
      try {
        pad = await downloads?.haalVoorRadio(
            artiest: artiest, titel: titel, seconden: seconden, jaar: jaar);
      } catch (_) {
        pad = null;
      }
      // Meteen de bibliotheek in, en niet wachten op een volledige scan: dat is wat de catalogus
      // die de telefoon ophaalt actueel maakt. Zie [LibraryStore.voegBestandToe].
      if (pad != null) {
        try {
          await library.voegBestandToe(pad);
          // En een hoes erbij: het verrijken hangt aan `scan()`, en die draait hier met opzet niet.
          final cfg = instellingen;
          if (cfg != null) unawaited(library.enrichFromWeb(cfg).catchError((_) {}));
        } catch (_) {/* het bestand ligt er; een scan vindt het later alsnog */}
      }
      haal.pad = pad;
      haal.stand = pad == null ? 'mislukt' : 'klaar';
      haal.klaarOm = DateTime.now();
    }());
    return haal;
  }

  /// De stand van één haal. Een onbekend nummer heet 'mislukt' en niet 'onbekend': voor de radio aan
  /// de andere kant is dat hetzelfde — deze plek levert niets op — en een derde antwoord zou daar een
  /// tak opleveren die nooit iets anders doet.
  Map<String, dynamic> stand(String id) {
    _ruimOp();
    final h = _halen[id];
    if (h == null) return {'stand': 'mislukt'};
    return {'stand': h.stand, if (h.pad != null) 'pad': h.pad};
  }

  void _ruimOp() {
    final nu = DateTime.now();
    _halen.removeWhere((_, h) {
      final k = h.klaarOm;
      return k != null && nu.difference(k) > _bewaartijd;
    });
  }
}
