/// De radio van een gekoppeld toestel laat de pc halen.
///
/// De radio zélf draait hier — het plan, de speelrij, hoeveel er vooruit moet staan; zie
/// `radio.dart`. Alleen het werk dat alleen op de pc kan gaat over de draad, en dat is precies de
/// verdeling die deze app overal al aanhoudt: zoeken en downloaden gebeurt daar, kijken en luisteren
/// hier.
///
/// **Waarom halen twee vragen zijn en geen één.** Een haal duurt tot een minuut of vier — drie peers
/// van anderhalve minuut. Een HTTP-verzoek dat zo lang openstaat overleeft geen telefoon die intussen
/// op slot gaat, en dan weet niemand meer of er nog iets gebeurt. Dus: één vraag die het werk START en
/// meteen terugkeert, en daarna om de paar seconden een vraag hoe het ermee staat. Dezelfde reden
/// waarom `enqueueSoulseekBest` een `wachtOpAfloop` heeft.
library;

import 'dart:async';
import 'dart:io' show HttpStatus;

import '../library.dart';
import '../models.dart';
import '../radio.dart';
import '../radiovoorraad.dart' show RadioLaterOpnieuw;
import 'client.dart';

/// Hoe vaak er gevraagd wordt hoe het met een haal staat.
const Duration _peilritme = Duration(seconds: 3);

/// Wanneer we een haal opgeven ook al zegt de pc niets.
///
/// Ruimer dan wat de pc er zelf over doet (drie peers van anderhalve minuut plus zoeken), zodat het
/// niet dít getal is dat een haal afkapt. Dit is het vangnet voor een pc die halverwege verdwijnt.
const Duration _geduld = Duration(minutes: 8);

/// Hoe vaak de catalogus opnieuw geladen wordt als een net gehaald nummer er nog niet in staat.
const int kCatalogusPogingen = 3;

/// Welk antwoord van de pc een plek voor STRAKS is, en waarom — of null als het een antwoord over
/// dit ene nummer is, en die plek dus mag overslaan.
///
/// Niet bereikt (geen status), een pc die zich even verslikt (5xx), te druk (429) of te traag (408):
/// dat is over een minuut anders, en elke poging brandde zo acht plekken van het plan op. En een
/// koppeling die niet meer geldt (401/403) evenmin een mislukt nummer: dan faalt ELK nummer, en de
/// radio liep stil leeg zonder dat iemand zei waarom (eindbeoordeling van 26-09-2026). Nu pauzeert
/// het ophalen en staat de reden in het radiopaneel; na opnieuw koppelen gaat het vanzelf verder.
String? radioLaterBijStatus(int? status) {
  if (status == null) return 'de pc antwoordde niet';
  if (status == 401 || status == 403) return 'de koppeling met je pc geldt niet meer — koppel opnieuw';
  if (status >= 500 || status == 408 || status == 429) return 'de pc kan het even niet aan';
  return null;
}

class PcRadiobron implements Radiobron {
  PcRadiobron({
    required this.library,
    required this.clientOf,
    this.peilritme = _peilritme,
    this.catalogusRitme = const Duration(seconds: 2),
  });

  final LibraryStore library;
  final RemoteClient? Function() clientOf;

  /// Zie [_peilritme]; een toets zet ze korter.
  final Duration peilritme;

  /// Hoe lang tussen twee pogingen om een net gehaald nummer in de catalogus te vinden.
  final Duration catalogusRitme;

  bool _begonnen = false;

  /// Welke radio er nu loopt. Gaat omhoog bij elke [staak], en elke peiling in [haal] kijkt ernaar.
  ///
  /// Zonder dit blijft een haal die al gestart is nog acht minuten om de drie seconden aan de pc
  /// vragen hoe het ermee staat — terwijl daar allang niets meer gebeurt.
  int _ronde = 0;

  @override
  Future<String?> begin() async {
    final c = clientOf();
    if (c == null) {
      return 'Je bent niet met je pc verbonden. Een radio haalt nummers op, en dat kan alleen je pc.';
    }
    try {
      final a = await c.ask('/api/radio', {'op': 'begin'});
      if (a['ok'] == true) {
        _begonnen = true;
        return null;
      }
      return (a['reden'] as String?) ?? 'Je pc kan nu geen nummers ophalen.';
    } on RemoteException catch (e) {
      // 404 betekent hier iets heel bepaalds: de pc kent deze weg nog niet, en dat is de enige
      // situatie waarin je precies weet wat je moet doen. "Je pc antwoordde met 404" zegt dat niet.
      if (e.statusCode == HttpStatus.notFound) {
        return 'Op je pc draait een oudere versie van de app, die de radio nog niet kent. '
            'Werk hem eerst bij — dan kan hij nummers voor je ophalen.';
      }
      if (e.isUnauthorized) {
        return 'De koppeling met je pc geldt niet meer. Koppel dit toestel opnieuw, dan kan hij weer '
            'nummers voor je ophalen.';
      }
      return 'Je pc antwoordde niet: ${e.message}';
    } catch (e) {
      return 'Je pc antwoordde niet: $e';
    }
  }

  @override
  void einde() {
    _ronde++;
    if (!_begonnen) return;
    _begonnen = false;
    final c = clientOf();
    // Niet afwachten en niet klagen: dit is opruimen. Blijft het hangen, dan laat de pc de
    // aanmelding vanzelf los — zie `_leenverloop` in `radiohaler.dart`.
    if (c != null) unawaited(c.ask('/api/radio', {'op': 'einde'}).catchError((_) => <String, dynamic>{}));
  }

  @override
  void staak() {
    // Hier eerst, want dit werkt ook als de pc niet antwoordt: de peilingen hieronder houden er
    // meteen mee op, wat er verder ook gebeurt.
    _ronde++;
    final c = clientOf();
    if (c != null) {
      unawaited(c.ask('/api/radio', {'op': 'staak'}).catchError((_) => <String, dynamic>{}));
    }
  }

  @override
  Future<Track?> haal(Radioplek plek) async {
    // Geen pc is geen mislukte plek maar een plek voor straks: op de sportschool valt de pc anderhalf
    // tot vijf minuten weg (zie `sportschool-pc-onbereikbaar`), en elke keer werd zo het plan
    // opgebrand — acht plekken per poging. Zie [RadioLaterOpnieuw].
    final c = clientOf();
    if (c == null) throw const RadioLaterOpnieuw('de pc is niet bereikbaar');
    final ronde = _ronde;
    final String id;
    try {
      final a = await c.ask('/api/radio', {
        'op': 'haal',
        'artiest': plek.artiest,
        'titel': plek.titel,
        if (plek.seconden != null) 'seconden': plek.seconden,
        if (plek.jaar != null) 'jaar': plek.jaar,
      });
      final gekregen = a['id'];
      if (gekregen is! String || gekregen.isEmpty) return null;
      id = gekregen;
    } on RemoteException catch (e) {
      final later = radioLaterBijStatus(e.statusCode);
      if (later == null) return null;
      throw RadioLaterOpnieuw(later);
    } catch (_) {
      throw const RadioLaterOpnieuw('de pc antwoordde niet');
    }

    if (ronde != _ronde) return null;

    final tot = DateTime.now().add(_geduld);
    while (DateTime.now().isBefore(tot)) {
      await Future<void>.delayed(peilritme);
      if (ronde != _ronde) return null; // de radio is intussen afgesloten
      Map<String, dynamic> a;
      try {
        a = await c.ask('/api/radio', {'op': 'stand', 'id': id});
      } on RemoteException catch (e) {
        // Een koppeling die onderweg verloopt is geen gemiste peiling: dan hoort de pc ons niet meer,
        // en bleef deze plek acht minuten bezet (tweede beoordeling van 26-09-2026).
        if (e.isUnauthorized) throw RadioLaterOpnieuw(radioLaterBijStatus(e.statusCode)!);
        continue; // een gemiste peiling is geen mislukte haal
      } catch (_) {
        continue;
      }
      final stand = a['stand'];
      if (stand == 'onderweg') continue;
      // Soulseek op de pc doet even niet mee: geen mislukte plek, straks opnieuw. Een oudere pc kent
      // dit antwoord niet en zegt 'mislukt', en dan is het zoals het altijd was.
      if (stand == 'later') throw const RadioLaterOpnieuw('Soulseek op de pc doet even niet mee');
      // 'eigen': geland op muziek die je al had — zie `RadioAlGehad` aan de kant van de pc. Klinken
      // wel, opruimen nooit: zie [AlVanJou].
      final eigen = stand == 'eigen';
      if (stand != 'klaar' && !eigen) return null;

      // Het bestand staat op de PC, dus komt het hierheen via de catalogus. Stil verversen: dit
      // gebeurt terwijl je luistert, en een scanbalk over het scherm hoort daar niet bij.
      //
      // Opzoeken op het ID dat de pc noemt, en NIET op artiest + titel. Dat laatste deed dit eerst, en
      // het vond dan het eerste nummer met die naam: bij een album-versie die je al had en een single
      // die de radio net ophaalde was dat JOUW album-versie — die dan als "door de radio gehaald"
      // gold, met een duim omlaag en een plek in het opruimoverzicht. Gevonden in de review van
      // 26-09-2026. Een oudere pc noemt geen id; dan blijft het zoals het was.
      final trackId = a['trackId'];
      if (trackId is! String || trackId.isEmpty) {
        try {
          await library.loadRemote(quiet: true);
        } catch (_) {
          return null;
        }
        // Een oudere pc noemt geen id, en dan is op naam niet te zeggen of dit het gehaalde bestand
        // is of JOUW exemplaar met dezelfde naam — een oudere pc haalt juist wanneer je een ANDERE
        // lengte hebt (Move On Baby: jouw album van 4:51, de single van 3:40). Dus klinken wel, maar
        // als van jou: nooit een duim die het weggooit, nooit in het opruimoverzicht (derde
        // beoordeling van 26-09-2026 — eerst ging zo je albumversie standaard naar de prullenbak).
        final t = library.ownedTrack(plek.artiest, plek.titel);
        if (t != null) throw AlVanJou(t);
        return null;
      }
      // Een paar keer, en niet één: staat het er nog niet, dan is dat een catalogus die achterloopt,
      // en een plek die dan opgeeft laat een bestand op de pc achter dat nergens meer genoteerd staat
      // — geen duim, geen opruimen (eindbeoordeling van 26-09-2026).
      for (var poging = 0; poging < kCatalogusPogingen; poging++) {
        if (poging > 0) await Future<void>.delayed(catalogusRitme);
        if (ronde != _ronde) return null;
        try {
          await library.loadRemote(quiet: true);
        } catch (_) {
          continue;
        }
        for (final t in library.tracks) {
          if (library.gedeeldId(t.path) != trackId) continue;
          if (eigen) throw AlVanJou(t);
          return t;
        }
      }
      return null; // het staat er nog steeds niet — liever een gemiste plek dan een verkeerd bestand
    }
    return null;
  }

  @override
  Future<bool> vergeet(
      {required String pad, required String artiest, required String titel}) async {
    // Twee dingen, en de eerste kan de telefoon zelf: [LibraryStore.removeTracks] stuurt op een
    // gekoppeld toestel een `removeTracks` naar de pc, met het stream-adres vertaald naar het id dat
    // de pc kent. Het bestand gaat daar van de schijf en de catalogus is meteen bij.
    await library.removeTracks([pad], fromDisk: true, naarPrullenbak: true);
    // De catalogus is na het verzoek opnieuw geladen: staat het er nog, dan kon de pc het niet weg.
    final weg = !library.tracks.any((t) => t.path == pad);
    if (!weg) return false;
    // En dan de verlanglijst, want die staat óók op de pc. Zonder dit haalt `sweepLosslessWants`
    // straks alsnog de FLAC van een nummer dat je zojuist hebt weggegooid. Stil bij een fout: het
    // bestand is dan al weg, en daar hoort geen melding meer bij.
    final c = clientOf();
    if (c == null) return true;
    try {
      await c.ask('/api/radio', {'op': 'vergeetwens', 'artiest': artiest, 'titel': titel});
    } catch (_) {/* een oudere pc kent deze op nog niet; het wissen zelf is al gebeurd */}
    return true;
  }
}
