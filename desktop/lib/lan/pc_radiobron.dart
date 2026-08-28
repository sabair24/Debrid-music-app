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
import 'client.dart';

/// Hoe vaak er gevraagd wordt hoe het met een haal staat.
const Duration _peilritme = Duration(seconds: 3);

/// Wanneer we een haal opgeven ook al zegt de pc niets.
///
/// Ruimer dan wat de pc er zelf over doet (drie peers van anderhalve minuut plus zoeken), zodat het
/// niet dít getal is dat een haal afkapt. Dit is het vangnet voor een pc die halverwege verdwijnt.
const Duration _geduld = Duration(minutes: 8);

class PcRadiobron implements Radiobron {
  PcRadiobron({required this.library, required this.clientOf});

  final LibraryStore library;
  final RemoteClient? Function() clientOf;

  bool _begonnen = false;

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
      return 'Je pc antwoordde niet: ${e.message}';
    } catch (e) {
      return 'Je pc antwoordde niet: $e';
    }
  }

  @override
  void einde() {
    if (!_begonnen) return;
    _begonnen = false;
    final c = clientOf();
    // Niet afwachten en niet klagen: dit is opruimen. Blijft het hangen, dan laat de pc de
    // aanmelding vanzelf los — zie `_leenverloop` in `radiohaler.dart`.
    if (c != null) unawaited(c.ask('/api/radio', {'op': 'einde'}).catchError((_) => <String, dynamic>{}));
  }

  @override
  Future<Track?> haal(Radioplek plek) async {
    final c = clientOf();
    if (c == null) return null;
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
    } catch (_) {
      return null;
    }

    final tot = DateTime.now().add(_geduld);
    while (DateTime.now().isBefore(tot)) {
      await Future<void>.delayed(_peilritme);
      Map<String, dynamic> a;
      try {
        a = await c.ask('/api/radio', {'op': 'stand', 'id': id});
      } catch (_) {
        continue; // een gemiste peiling is geen mislukte haal
      }
      final stand = a['stand'];
      if (stand == 'onderweg') continue;
      if (stand != 'klaar') return null;

      // Het bestand staat op de PC, dus komt het hierheen via de catalogus. Stil verversen: dit
      // gebeurt terwijl je luistert, en een scanbalk over het scherm hoort daar niet bij.
      try {
        await library.loadRemote(quiet: true);
      } catch (_) {
        return null;
      }
      // Opzoeken op artiest+titel en niet op het pad dat de pc noemde: op een gekoppeld toestel is
      // `Track.path` een stream-adres en geen bestandsnaam. Dat het nummer er niet al stond is
      // hierboven al gegarandeerd — `haalVoorRadio` geeft alleen een pad terug voor een bestand dat
      // écht nieuw is — dus wat hier gevonden wordt, is wat er net geland is.
      return library.ownedTrack(plek.artiest, plek.titel);
    }
    return null;
  }

  @override
  Future<void> vergeet(
      {required String pad, required String artiest, required String titel}) async {
    // Twee dingen, en de eerste kan de telefoon zelf: [LibraryStore.removeTracks] stuurt op een
    // gekoppeld toestel een `removeTracks` naar de pc, met het stream-adres vertaald naar het id dat
    // de pc kent. Het bestand gaat daar van de schijf en de catalogus is meteen bij.
    await library.removeTracks([pad], fromDisk: true);
    // En dan de verlanglijst, want die staat óók op de pc. Zonder dit haalt `sweepLosslessWants`
    // straks alsnog de FLAC van een nummer dat je zojuist hebt weggegooid. Stil bij een fout: het
    // bestand is dan al weg, en daar hoort geen melding meer bij.
    final c = clientOf();
    if (c == null) return;
    try {
      await c.ask('/api/radio', {'op': 'vergeetwens', 'artiest': artiest, 'titel': titel});
    } catch (_) {/* een oudere pc kent deze op nog niet; het wissen zelf is al gebeurd */}
  }
}
