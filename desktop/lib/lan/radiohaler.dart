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

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../groeistroom.dart';
import '../library.dart';
import '../settings.dart';
import '../online.dart';
import '../radiovoorraad.dart' show RadioAlGehad, RadioLaterOpnieuw;

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

  /// Het gedeelde id van het gelande bestand. Daarop zoekt het toestel het terug — niet op artiest +
  /// titel, want dan vond het soms je eigen exemplaar van hetzelfde nummer. Zie `PcRadiobron.haal`.
  String? trackId;

  /// Landde op muziek die je al had — zie [RadioAlGehad].
  bool eigen = false;
  DateTime? klaarOm;

  /// Klinkt al terwijl het binnenkomt (groeistroom.dart): het toestel kan het via de pc laten spelen
  /// zodra [Groei.kanKlinken] — zie [Radiohaler.stand]. Null als de proef op de pc uit staat.
  Groei? groei;

  /// ▶ op het toestel, geen radio: [Radiohaler.staak] laat hem staan.
  bool los = false;
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
      if (h.stand != 'onderweg' || h.los) continue;
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
  ///
  /// **Met de groeistroom, net als ▶ op de pc** (als de proef "Al spelen terwijl het binnenkomt" op de pc
  /// aan staat). Gemeten op 20-10-2026: zonder groei nam deze haal de oude weg — geen vroege start, geen
  /// wedloop, de uploaders één voor één, hoogstens drie — terwijl ▶ op de pc met dertig tegelijk begint en
  /// populaire nummers in 4 à 8 s laat klinken. Met een groei gaat elke haal van het toestel die snelle
  /// weg, ook als het toestel (nog) niet meeluistert. [zoekBeter]: na het landen op jacht naar een
  /// betere kopie — voor ▶ op het toestel, niet voor zijn radio. [luistertMee]: het toestel wil het horen
  /// zodra het kan (▶), dus ook in het geheugen als het binnen is vóór het toestel opent
  /// ([Groei.zalKlinken]).
  Radiohaal haal({
    required String artiest,
    required String titel,
    int? seconden,
    int? jaar,
    bool zoekBeter = false,
    bool luistertMee = false,
  }) {
    _ruimOp();
    // De leen kan verlopen zijn terwijl de radio nog loopt; hem hier opnieuw vastnemen is goedkoper
    // dan een radio die halverwege stil ophoudt met halen.
    begin();
    final haal = Radiohaal('r${++_volgnummer}')..los = luistertMee;
    _halen[haal.id] = haal;
    unawaited(() async {
      String? pad;
      var later = false;
      try {
        final g = (instellingen?.vroegLuisteren ?? false)
            ? await Groeistroom.gedeeld.nieuw('toestel: $artiest — $titel')
            : null;
        haal.groei = g;
        if (g != null) {
          // Gaat wachten tot het kan klinken: pas daarna zegt [stand] het het toestel ([Groei.kanKlinken]).
          unawaited(g.speelbaar);
          if (luistertMee) g.zalKlinken();
        }
        pad = g == null
            ? await downloads?.haalVoorRadio(artiest: artiest, titel: titel, seconden: seconden, jaar: jaar)
            : await downloads?.haalEnLaatHoren(
                artiest: artiest,
                titel: titel,
                seconden: seconden,
                jaar: jaar,
                vroeg: g,
                zoekDaarnaBeter: zoekBeter,
                losVanDeRadio: luistertMee);
      } on RadioLaterOpnieuw {
        later = true; // Soulseek op de pc doet even niet mee; het toestel probeert het straks weer
      } on RadioAlGehad catch (e) {
        // Geland op muziek die je al had: het toestel laat het klinken, maar als jouw nummer — zie
        // [RadioAlGehad]. Een eigen stand en geen 'klaar' met een vlag erbij: een ouder toestel
        // kende die vlag niet, zag 'klaar', en behandelde JOUW bestand als radionummer — met een duim
        // die het weggooit (tweede beoordeling van 26-09-2026). Alles wat niet 'klaar' is, is daar
        // een gemiste plek, en dat is veilig.
        pad = e.pad;
        haal.eigen = true;
      } catch (_) {
        pad = null;
      } finally {
        // Niets geland: wie (een toestel) op een volgende uploader wacht, hoort dat er geen komt.
        final g = haal.groei;
        if (g != null && g.geborgen == null) g.opgegeven();
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
      if (pad != null) haal.trackId = library.gedeeldId(pad);
      haal.stand = later ? 'later' : (pad == null ? 'mislukt' : (haal.eigen ? 'eigen' : 'klaar'));
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
    final g = h.groei;
    return {
      'stand': h.stand,
      if (h.pad != null) 'pad': h.pad,
      if (h.trackId != null) 'trackId': h.trackId,
      // Al te horen via de pc ([Radiohaler.groeiVoor]), terwijl het nog binnenkomt.
      if (g != null && h.stand == 'onderweg' && g.kanKlinken) 'groei': g.id,
    };
  }

  /// De groei achter een haal van een toestel, voor de LAN-server die hem doorgeeft. Alleen een groei die
  /// via [haal] gemaakt is: een toestel komt zo nooit bij wat de pc zelf aan het spelen is.
  Groei? groeiVoor(String groeiId) {
    for (final h in _halen.values) {
      final g = h.groei;
      if (g != null && g.id == groeiId) return g;
    }
    return null;
  }

  /// Voor de toetsen: een haal met deze groei, zonder te halen.
  @visibleForTesting
  Radiohaal haalVoorToets(Groei g) {
    final h = Radiohaal('r${++_volgnummer}')..groei = g;
    _halen[h.id] = h;
    return h;
  }

  void _ruimOp() {
    final nu = DateTime.now();
    _halen.removeWhere((_, h) {
      final k = h.klaarOm;
      return k != null && nu.difference(k) > _bewaartijd;
    });
  }
}
