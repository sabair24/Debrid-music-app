/// Zones zoals bij Roon (Saber, 21-10-2026: "als ik op de pc een liedje aan het spelen ben, dat de
/// ander devices dit zien en dat ik bevoorbeeld vanaf men gsm of ipad het volgende kan tikken").
///
/// **Wat een zone is.** Elk toestel met de app (de pc, een gsm, de iPad, de Mac, de Shield) en elke
/// speaker die de pc stuurt. Elk toestel ziet ze allemaal: wat er speelt, waar in het nummer, en of het
/// toestel bereikbaar is.
///
/// **Waar de waarheid staat: op de pc.** Elk toestel meldt al wat het speelt (de op `progress`, elke vijf
/// seconden zolang het speelt, en bij elke pauze of elk nieuw nummer). De pc bewaart dat sinds deze stap
/// per toestel ([LanStateStore.perToestel]) in plaats van alleen de laatste melding, en houdt bij welk
/// toestel er nu een stroom open heeft ([ZoneRegister]). Elk toestel krijgt elke wijziging meteen
/// doorgestuurd over `/api/zones/events`, in plaats van om de vier seconden te vragen.
///
/// Dit is deelstap 2.1: zien, en hier verder luisteren vanaf elke zone. Bedienen, overdragen en de
/// speakers als eigen zone komen erna.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audioformaten.dart' show isVerliesvrij;
import '../quality.dart' show depthRateLabel;
import 'state_store.dart';

/// Wat voor ding een zone is. Bepaalt het icoon, en straks wat je ermee kan.
enum ZoneSoort { pc, gsm, tablet, mac, tv, speaker }

/// Het soort toestel uit wat het van zichzelf zegt. Een iPad en een iPhone heten allebei `ios`; de
/// naam zegt het verschil ("iPad van Saber"). Een tv zegt het zelf ([tv]).
ZoneSoort zoneSoortVoor({required String platform, required String naam, bool tv = false}) {
  final n = naam.toLowerCase();
  if (tv || n.contains('shield') || n.contains(' tv')) return ZoneSoort.tv;
  switch (platform) {
    case 'windows':
    case 'linux':
      return ZoneSoort.pc;
    case 'macos':
      return ZoneSoort.mac;
    case 'ios':
      return n.contains('ipad') ? ZoneSoort.tablet : ZoneSoort.gsm;
  }
  if (n.contains('tab') || n.contains('ipad')) return ZoneSoort.tablet;
  return ZoneSoort.gsm;
}

/// Onder welk id een toestel met een open lijn in de zones staat: het id dat het zelf opgeeft
/// ([gevraagd], `thisDevice().id`), want daaronder meldt het ook wat het speelt; alleen zonder dat het
/// id uit zijn sleutel ([uitSleutel]).
///
/// **Waarom (gemeten op de S26, 21-10-2026).** Dit stond andersom: met een echte sleutel telde het id
/// van de koppeling. Bij de S26 is dat een ander id dan zijn eigen, dus stond de gsm er twee keer in —
/// één keer met wat hij speelde, één keer met de open lijn — en kwam een opdracht aan "de gsm" bij een
/// zone zonder lijn uit: "niet bereikbaar".
String zoneToestelVoor({String? gevraagd, String? uitSleutel}) =>
    (gevraagd ?? '').isNotEmpty ? gevraagd! : (uitSleutel ?? '');

/// Hoe lang een toestel zonder open stroom en zonder melding nog als bereikbaar geldt.
const kZoneBereikbaar = Duration(seconds: 30);

/// Wat een zone na zoveel stilte nog in de lijst houdt: wat er gisteren speelde, telt niet meer.
const kZoneTotEenDag = Duration(hours: 24);

/// Eén lid van een groep ([ZoneStaat.leden]): wie, en hoe luid. Voor "Los" en een schuif per lid op de kaart van de
/// groep (Saber, 23-10-2026: "Bij een groep één schuif, plus per lid apart").
@immutable
class ZoneLid {
  const ZoneLid({required this.id, required this.naam, required this.soort, this.volume = -1});

  /// Het zone-id van het lid (`dev:…` of `spk:…`): daarheen gaat zijn eigen volume.
  final String id;
  final String naam;
  final ZoneSoort soort;

  /// 0–100, of -1 als het lid het niet meldt.
  final int volume;

  Map<String, dynamic> toJson() => {'id': id, 'naam': naam, 'soort': soort.name, if (volume >= 0) 'volume': volume};

  static ZoneLid fromJson(Map<String, dynamic> m) => ZoneLid(
        id: '${m['id'] ?? ''}',
        naam: '${m['naam'] ?? ''}',
        soort: ZoneSoort.values.firstWhere((s) => s.name == m['soort'], orElse: () => ZoneSoort.gsm),
        volume: (m['volume'] as num?)?.toInt() ?? -1,
      );

  @override
  bool operator ==(Object other) =>
      other is ZoneLid && other.id == id && other.naam == naam && other.soort == soort && other.volume == volume;

  @override
  int get hashCode => Object.hash(id, naam, soort, volume);
}

/// Wat één zone doet, zoals de pc het weet.
@immutable
class ZoneStaat {
  const ZoneStaat({
    required this.id,
    required this.soort,
    required this.naam,
    this.online = false,
    this.playing = false,
    this.trackId = '',
    this.titel = '',
    this.artiest = '',
    this.album = '',
    this.positionMs = 0,
    this.durationMs = 0,
    this.opMs = 0,
    this.index = 0,
    this.lengte = 0,
    this.shuffle = false,
    this.repeat = 'off',
    this.radio = '',
    this.via = '',
    this.volume = -1,
    this.groep = const [],
    this.kanGroeperen = false,
    this.samenMs = 0,
    this.sonos = false,
    this.radioStatus = '',
    this.radioPast = '',
    this.radioGehaald = false,
    this.radioHouden = false,
    this.verplaatstNaar = '',
    this.verplaatstOp = 0,
    this.leden = const [],
    this.hierna = '',
    this.volgendeId = '',
    this.bronSoort = '',
    this.bronNaam = '',
    this.kwaliteit = '',
    this.omgezet = '',
  });

  /// Wat er na het spelende nummer komt: "Titel — Artiest", leeg als er niets komt (zones, stap 3; Saber, 23-10-2026:
  /// "Hierna: …").
  final String hierna;

  /// Het id van het nummer dat "volgende" opent (de wachtrij één verder, bij een radio wat hij klaar heeft), leeg als
  /// dat niet vaststaat. Zo staat het op het scherm van wie bedient vóór de zone het meldt (Saber, 26-10-2026: "op de
  /// shield klonk het volgende liedje, maar op de gsm duurde het echt paar seconden eer ik het zag").
  final String volgendeId;

  /// Waar de wachtrij vandaan komt ([bronVanRij]): 'radio', 'album', 'afspeellijst', 'artiest' of 'wachtrij', met de
  /// naam erbij ("Reckless", "Zomer", "23 nummers"). Leeg als het niet te zeggen is.
  final String bronSoort, bronNaam;

  /// Het bestand: "FLAC 24/96", "MP3" — leeg als de pc het niet weet ([kwaliteitLabel]).
  final String kwaliteit;

  /// Zet de pc het onderweg om: naar welke maat ("16/44.1"). Leeg: het origineel ([omgezetNaar]).
  final String omgezet;

  /// Bij de leider van een groep: elk lid (de leider eerst) met zijn naam en volume. Leeg zonder groep.
  final List<ZoneLid> leden;

  /// De muziek van deze zone ging net naar een andere ([verplaatstNaar], de naam van die zone), op [verplaatstOp] (klok
  /// van de pc). Dan speelt deze zone niets meer — ook al meldde ze dat nog niet (Saber, 23-10-2026: "als ik ze
  /// verplaats blijft op de andere ook"). Zie [ZoneRegister.verplaatst]. Een lege naam met een [verplaatstOp]: iemand
  /// tikte "Stop" ([ZoneRegister.gestopt]). Allebei 0/leeg: geen van beide.
  final String verplaatstNaar;
  final int verplaatstOp;

  /// Speelt er een radio van de pc op deze speaker ([radio]): wat hij doet ("Zoekt het volgende nummer…"), leeg
  /// als er niets bijzonders is — zie `radioStatusTekst`. Voor een toestel dat de speaker kiest (speakerradio v2,
  /// 23-10-2026): die radio draait op de pc, en zonder dit zag je op je gsm niet waar hij mee bezig was.
  final String radioStatus;

  /// Het oordeel "past in deze radio" over het spelende nummer: 'past', 'pastNiet' of leeg.
  final String radioPast;

  /// Haalde deze radio het spelende nummer zelf (dan gaan "Houden" en "Weg" over het bestand)?
  final bool radioGehaald;

  /// Kreeg het spelende nummer "Houden" (👍)?
  final bool radioHouden;

  /// Een Sonos: die kan met andere Sonossen in één groep (stap 3.1). Toestellen kunnen met elke speaker
  /// meespelen ([kanGroeperen]).
  final bool sonos;

  /// Bij een speaker waarmee toestellen meespelen (stap 3.3): hoeveel later hij klinkt dan hij zegt (ms),
  /// zoals gezet met de schuif "Sonos gelijkzetten". Wie meespeelt, loopt zoveel achter op zijn plek.
  final int samenMs;

  /// Bij de leider van een groep (stap 3.1): alle zones die samen spelen, de leider erbij. Leeg zonder
  /// groep. De leden staan niet apart in de lijst: ze spelen wat de leider speelt.
  final List<String> groep;

  /// Kan deze zone met andere samen spelen? Elk toestel met de app, en elke speaker (toestellen volgen hem,
  /// stap 3.3). Speakers onderling: alleen Sonossen ([sonos]).
  final bool kanGroeperen;

  /// Het appvolume (0–100), of -1 als de zone het niet meldt.
  final int volume;

  /// `dev:<toestel-id>` voor een toestel (de pc: `dev:pc-<naam>`), `spk:<speaker-id>` voor een speaker.
  final String id;
  final ZoneSoort soort;
  final String naam;

  /// Heeft het toestel nu een stroom open, of meldde het zich de laatste [kZoneBereikbaar]? Een speaker:
  /// heeft de pc er een sessie mee.
  final bool online;
  final bool playing;

  /// Het nummer, als id van de pc. Leeg: er speelt niets (meer).
  final String trackId;

  /// Wat de pc over dat nummer weet, zodat een toestel het ook kan tonen als het nummer bij hem
  /// (nog) niet in de bibliotheek staat.
  final String titel, artiest, album;
  final int positionMs, durationMs;

  /// Wanneer [positionMs] gold, op de klok van de pc.
  final int opMs;

  /// Waar in de wachtrij, en hoe lang die is. De rij zelf reist niet mee: een geschudde bibliotheek is
  /// dertigduizend ids. Zie `/api/zones/stand`.
  final int index, lengte;
  final bool shuffle;

  /// 'off', 'all' of 'one'.
  final String repeat;

  /// Speelt er een radio: hoe hij heet. Leeg zonder radio.
  final String radio;

  /// Bij een speaker: welk toestel hem de muziek gaf ("via de pc"). Leeg bij een toestel.
  final String via;

  /// Het toestel-id achter een toestelzone, of null bij een speaker.
  String? get toestel => id.startsWith('dev:') ? id.substring(4) : null;

  bool get speeltIets => trackId.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'soort': soort.name,
        'naam': naam,
        'online': online,
        'playing': playing,
        if (trackId.isNotEmpty) ...{
          'trackId': trackId,
          'titel': titel,
          'artiest': artiest,
          'album': album,
          'positionMs': positionMs,
          'durationMs': durationMs,
          'opMs': opMs,
          'index': index,
          'lengte': lengte,
        },
        'shuffle': shuffle,
        'repeat': repeat,
        if (radio.isNotEmpty) 'radio': radio,
        if (via.isNotEmpty) 'via': via,
        if (volume >= 0) 'volume': volume,
        if (groep.isNotEmpty) 'groep': groep,
        if (kanGroeperen) 'kanGroeperen': true,
        if (samenMs != 0) 'samenMs': samenMs,
        if (sonos) 'sonos': true,
        if (radioStatus.isNotEmpty) 'radioStatus': radioStatus,
        if (radioPast.isNotEmpty) 'radioPast': radioPast,
        if (radioGehaald) 'radioGehaald': true,
        if (radioHouden) 'radioHouden': true,
        if (verplaatstOp > 0) ...{'verplaatstNaar': verplaatstNaar, 'verplaatstOp': verplaatstOp},
        if (leden.isNotEmpty) 'leden': [for (final l in leden) l.toJson()],
        if (hierna.isNotEmpty) 'hierna': hierna,
        if (volgendeId.isNotEmpty) 'volgendeId': volgendeId,
        if (bronSoort.isNotEmpty) ...{'bronSoort': bronSoort, 'bronNaam': bronNaam},
        if (kwaliteit.isNotEmpty) 'kwaliteit': kwaliteit,
        if (omgezet.isNotEmpty) 'omgezet': omgezet,
      };

  static ZoneStaat fromJson(Map<String, dynamic> m) => ZoneStaat(
        id: '${m['id'] ?? ''}',
        soort: ZoneSoort.values.firstWhere((s) => s.name == m['soort'], orElse: () => ZoneSoort.gsm),
        naam: '${m['naam'] ?? ''}',
        online: m['online'] == true,
        playing: m['playing'] == true,
        trackId: '${m['trackId'] ?? ''}',
        titel: '${m['titel'] ?? ''}',
        artiest: '${m['artiest'] ?? ''}',
        album: '${m['album'] ?? ''}',
        positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        opMs: (m['opMs'] as num?)?.toInt() ?? 0,
        index: (m['index'] as num?)?.toInt() ?? 0,
        lengte: (m['lengte'] as num?)?.toInt() ?? 0,
        shuffle: m['shuffle'] == true,
        repeat: '${m['repeat'] ?? 'off'}',
        radio: '${m['radio'] ?? ''}',
        via: '${m['via'] ?? ''}',
        volume: (m['volume'] as num?)?.toInt() ?? -1,
        groep: [for (final x in (m['groep'] as List? ?? const [])) '$x'],
        kanGroeperen: m['kanGroeperen'] == true,
        samenMs: (m['samenMs'] as num?)?.toInt() ?? 0,
        sonos: m['sonos'] == true,
        radioStatus: '${m['radioStatus'] ?? ''}',
        radioPast: '${m['radioPast'] ?? ''}',
        radioGehaald: m['radioGehaald'] == true,
        radioHouden: m['radioHouden'] == true,
        verplaatstNaar: '${m['verplaatstNaar'] ?? ''}',
        verplaatstOp: (m['verplaatstOp'] as num?)?.toInt() ?? 0,
        leden: [
          for (final x in (m['leden'] as List? ?? const []))
            if (x is Map) ZoneLid.fromJson(x.cast<String, dynamic>()),
        ],
        hierna: '${m['hierna'] ?? ''}',
        volgendeId: '${m['volgendeId'] ?? ''}',
        bronSoort: '${m['bronSoort'] ?? ''}',
        bronNaam: '${m['bronNaam'] ?? ''}',
        kwaliteit: '${m['kwaliteit'] ?? ''}',
        omgezet: '${m['omgezet'] ?? ''}',
      );

  @override
  bool operator ==(Object other) =>
      other is ZoneStaat &&
      other.id == id &&
      other.soort == soort &&
      other.naam == naam &&
      other.online == online &&
      other.playing == playing &&
      other.trackId == trackId &&
      other.titel == titel &&
      other.artiest == artiest &&
      other.positionMs == positionMs &&
      other.durationMs == durationMs &&
      other.opMs == opMs &&
      other.index == index &&
      other.lengte == lengte &&
      other.shuffle == shuffle &&
      other.repeat == repeat &&
      other.radio == radio &&
      other.via == via &&
      other.volume == volume &&
      listEquals(other.groep, groep) &&
      other.kanGroeperen == kanGroeperen &&
      other.samenMs == samenMs &&
      other.sonos == sonos &&
      other.radioStatus == radioStatus &&
      other.radioPast == radioPast &&
      other.radioGehaald == radioGehaald &&
      other.radioHouden == radioHouden &&
      other.verplaatstNaar == verplaatstNaar &&
      other.verplaatstOp == verplaatstOp &&
      listEquals(other.leden, leden) &&
      other.hierna == hierna &&
      other.volgendeId == volgendeId &&
      other.bronSoort == bronSoort &&
      other.bronNaam == bronNaam &&
      other.kwaliteit == kwaliteit &&
      other.omgezet == omgezet;

  @override
  int get hashCode => Object.hash(id, online, playing, trackId, positionMs, opMs, index, lengte);
}

// ── Op de kaart: hierna, de bron en de kwaliteit (zones, stap 3) ─────────────

/// Het id na [index] in [rij], zoals de speler verdergaat: bij 'one' hetzelfde, aan het eind bij 'all' weer het
/// eerste. Leeg als er niets komt.
String volgendInRij(List<String> rij, int index, String repeat) {
  if (rij.isEmpty || index < 0 || index >= rij.length) return '';
  if (repeat == 'one') return rij[index];
  if (index + 1 < rij.length) return rij[index + 1];
  return repeat == 'all' ? rij.first : '';
}

/// Het id dat "volgende" opent: de wachtrij één verder, ook bij herhalen van één nummer. Aan het eind leeg: daar
/// begint bij herhalen een nieuwe trekking (`PlayerStore.next`), en die kent alleen de zone.
String volgendeOpdracht(List<String> rij, int index) => index >= 0 && index + 1 < rij.length ? rij[index + 1] : '';

/// Waar een wachtrij vandaan komt.
typedef ZoneBron = ({String soort, String naam});

/// Waar [rij] vandaan komt, zonder dat het toestel het hoeft te zeggen (Saber, 23-10-2026: "de bron (radio, album,
/// afspeellijst)"): een radio, een afspeellijst uit [lijsten] (ook geschud: dezelfde nummers), één album, één
/// artiest, of anders "N nummers". Een rij van één nummer zegt niets: null.
///
/// Album en artiest alleen bij een rij tot 300 nummers: een geschudde bibliotheek is dertigduizend ids, en daar is
/// het antwoord toch "wachtrij".
ZoneBron? bronVanRij(List<String> rij,
    {String radio = '',
    ZoneNummer? Function(String id)? nummer,
    Iterable<({String naam, List<String> ids})> lijsten = const []}) {
  if (radio.isNotEmpty) return (soort: 'radio', naam: radio);
  final ids = [for (final id in rij) if (id.isNotEmpty) id];
  if (ids.length < 2) return null;
  final hier = ids.toSet();
  for (final l in lijsten) {
    final lijst = l.ids.toSet();
    if (lijst.length < 2) continue;
    if (hier.length >= lijst.length * .8 && lijst.containsAll(hier)) return (soort: 'afspeellijst', naam: l.naam);
  }
  if (ids.length <= 300 && nummer != null) {
    String? album, artiest, albumSleutel, artiestSleutel;
    var zelfdeAlbum = true, zelfdeArtiest = true, bekend = 0;
    for (final id in ids) {
      final n = nummer(id);
      if (n == null) continue;
      bekend++;
      final a = n.album.trim().toLowerCase(), ar = n.artiest.trim().toLowerCase();
      if (albumSleutel == null) {
        albumSleutel = a;
        artiestSleutel = ar;
        album = n.album.trim();
        artiest = n.artiest.trim();
      }
      if (a.isEmpty || a != albumSleutel) zelfdeAlbum = false;
      if (ar.isEmpty || ar != artiestSleutel) zelfdeArtiest = false;
    }
    if (bekend >= 2 && zelfdeAlbum) return (soort: 'album', naam: album!);
    if (bekend >= 2 && zelfdeArtiest) return (soort: 'artiest', naam: artiest!);
  }
  return (soort: 'wachtrij', naam: '${ids.length} nummers');
}

/// Het bestand als "FLAC 24/96" (verliesvrij met bekende maat) of "MP3"; leeg zonder formaat.
String kwaliteitLabel({required String ext, int rate = 0, int bits = 0}) {
  final e = ext.toLowerCase().replaceAll('.', '');
  if (e.isEmpty) return '';
  if (isVerliesvrij(e) && rate > 0 && bits > 0) {
    return '${e.toUpperCase()} ${depthRateLabel(sampleRate: rate, bitsPerSample: bits)}';
  }
  return e.toUpperCase();
}

/// Naar welke maat het onderweg omgezet wordt ("16/44.1"), of leeg als het het origineel is. [stroomBits] 0 laat de
/// diepte van het bestand staan, zoals `stroomGrens` op een toestel.
String omgezetNaar({required int bestandRate, required int bestandBits, required int stroomRate, required int stroomBits}) {
  if (stroomRate <= 0 && stroomBits <= 0) return '';
  final rate = stroomRate > 0 && (bestandRate <= 0 || stroomRate < bestandRate) ? stroomRate : bestandRate;
  final bits = stroomBits > 0 && (bestandBits <= 0 || stroomBits < bestandBits) ? stroomBits : bestandBits;
  if (rate <= 0 || bits <= 0 || (rate == bestandRate && bits == bestandBits)) return '';
  return depthRateLabel(sampleRate: rate, bitsPerSample: bits);
}

/// De regel onder de titel op een zonekaart: waar het vandaan komt en hoe het klinkt — "Album: Reckless · FLAC
/// 16/44.1", of "… · FLAC 24/96, omgezet naar 16/44.1". Leeg als er niets te zeggen is.
String zoneBronRegel(ZoneStaat z) {
  final bron = switch (z.bronSoort) {
    'radio' => 'Radio: ${z.bronNaam}',
    'album' => 'Album: ${z.bronNaam}',
    'afspeellijst' => 'Afspeellijst: ${z.bronNaam}',
    'artiest' => 'Artiest: ${z.bronNaam}',
    'wachtrij' => 'Wachtrij: ${z.bronNaam}',
    _ => '',
  };
  final klank = z.kwaliteit.isEmpty
      ? ''
      : z.omgezet.isEmpty
          ? z.kwaliteit
          : '${z.kwaliteit}, omgezet naar ${z.omgezet}';
  return [bron, klank].where((s) => s.isNotEmpty).join(' · ');
}

/// Hoe lang "Verplaatst naar …" op de kaart van de oude zone staat (Saber, 23-10-2026: "Ja, een paar seconden").
const kVerplaatstZichtbaar = Duration(seconds: 5);

/// Hoe lang een gepauzeerde zone nog als spelend telt (Saber, 23-10-2026: "Na 10 minuten bij 'niets'"). Verder spelen
/// vanaf waar je was blijft kunnen; ze staat alleen niet meer bij wat speelt.
const kGepauzeerdTeltAlsSpelend = Duration(minutes: 10);

/// "Verplaatst naar …" voor [z] nu, of null als die melding er (niet meer) hoort — zie [kVerplaatstZichtbaar].
String? verplaatstMelding(ZoneStaat z, {required int nuMs}) {
  if (z.verplaatstNaar.isEmpty) return null;
  return nuMs - z.verplaatstOp < kVerplaatstZichtbaar.inMilliseconds ? 'Verplaatst naar ${z.verplaatstNaar}' : null;
}

/// Telt [z] als een zone die speelt — bovenaan in de lijst, met haar nummer? Ze speelt, of ze staat korter dan
/// [kGepauzeerdTeltAlsSpelend] gepauzeerd; en haar muziek ging niet naar een andere zone, en niemand tikte "Stop".
bool speeltNu(ZoneStaat z, {required int nuMs}) {
  if (!z.speeltIets || z.verplaatstOp > 0) return false;
  if (z.playing) return true;
  return z.opMs > 0 && nuMs - z.opMs < kGepauzeerdTeltAlsSpelend.inMilliseconds;
}

/// Waar het nummer van [z] nu is: de gemelde plek, plus de tijd sindsdien als het speelde, nooit
/// voorbij het einde. [nuMs] op de klok van de pc (zie [ZoneLijstStand.nuOpPc]).
Duration positieNu(ZoneStaat z, {required int nuMs}) {
  var ms = z.positionMs;
  if (z.playing && z.opMs > 0) ms += (nuMs - z.opMs).clamp(0, 6 * 60 * 60 * 1000);
  if (z.durationMs > 0 && ms > z.durationMs) ms = z.durationMs;
  return Duration(milliseconds: ms < 0 ? 0 : ms);
}

/// Bereikbaar: een open stroom, of een melding die nog geen [kZoneBereikbaar] oud is.
bool zoneBereikbaar({required bool stroomOpen, required int? laatstGezienMs, required int nuMs}) =>
    stroomOpen || (laatstGezienMs != null && nuMs - laatstGezienMs <= kZoneBereikbaar.inMilliseconds);

/// De volgorde in de lijst: dit toestel eerst, dan wat speelt, dan wat bereikbaar is, dan de rest; op
/// naam binnen elke groep.
List<ZoneStaat> ordenZones(Iterable<ZoneStaat> zones, {required String hier}) {
  int rang(ZoneStaat z) => z.id == hier
      ? 0
      : z.playing && z.online
          ? 1
          : z.online
              ? 2
              : 3;
  return zones.toList()
    ..sort((a, b) {
      final r = rang(a).compareTo(rang(b));
      return r != 0 ? r : a.naam.toLowerCase().compareTo(b.naam.toLowerCase());
    });
}

/// De volgorde op het scherm van [hier] (Saber, 23-10-2026: "Alles altijd, spelend bovenaan" en "Dit toestel eerst, dan
/// de rest"): dit toestel, dan wat speelt ([speeltNu], ook kort gepauzeerd), dan wat bereikbaar is, dan wat weg is.
/// Daarbinnen op naam. De pc zet zichzelf vooraan ([ordenZones]); elk toestel ordent opnieuw voor zichzelf.
List<ZoneStaat> ordenVoorHier(Iterable<ZoneStaat> zones, {required String hier, required int nuMs}) {
  int rang(ZoneStaat z) => z.id == hier
      ? 0
      : z.online && speeltNu(z, nuMs: nuMs)
          ? 1
          : z.online
              ? 2
              : 3;
  return zones.toList()
    ..sort((a, b) {
      final r = rang(a).compareTo(rang(b));
      return r != 0 ? r : a.naam.toLowerCase().compareTo(b.naam.toLowerCase());
    });
}

/// Eén server-sent event: de naam (`message` zonder `event:`-regel) en de gegevens.
typedef SseEvent = ({String event, String data});

/// Leest server-sent events regel voor regel (zonder de regeleinden). Geeft een event terug bij de lege
/// regel die het afsluit; commentaar (`: ping`) en onbekende velden slaat hij over.
class SseLezer {
  String _event = '';
  final _data = StringBuffer();
  var _heeftData = false;

  SseEvent? regel(String r) {
    if (r.isEmpty) {
      if (!_heeftData) {
        _event = '';
        return null;
      }
      final e = (event: _event.isEmpty ? 'message' : _event, data: _data.toString());
      _event = '';
      _data.clear();
      _heeftData = false;
      return e;
    }
    if (r.startsWith(':')) return null;
    final dp = r.indexOf(':');
    final veld = dp < 0 ? r : r.substring(0, dp);
    var waarde = dp < 0 ? '' : r.substring(dp + 1);
    if (waarde.startsWith(' ')) waarde = waarde.substring(1);
    switch (veld) {
      case 'event':
        _event = waarde;
      case 'data':
        if (_heeftData) _data.write('\n');
        _data.write(waarde);
        _heeftData = true;
    }
    return null;
  }
}

/// Wat de pc over een nummer weet, voor in de zonelijst.
typedef ZoneNummer = ({String titel, String artiest, String album, int duurMs});

/// De radio van de pc op een speaker, voor in de zone — zie [ZoneStaat.radioStatus] en verder.
typedef RadioOpSpeaker = ({String status, String past, bool gehaald, bool houden});

/// Wat de pc van een speaker weet die hij de muziek gaf. Zie `CastManager.laatsteStand`.
typedef SpeakerStand = ({
  String id,
  String naam,
  String? trackId,
  int index,
  int lengte,
  bool speelt,
  int positieMs,
  int duurMs,
  int opMs,

  /// Het volume van de speaker (0–100), of -1 als hij het niet meldt.
  int volume,

  /// Speelt er een radio van de pc op (`speaker_radio.dart`): hoe hij heet. Leeg zonder radio.
  String radio,
});

/// Alle zones, op de pc. Eén per server.
///
/// Leest wat de toestellen melden uit [state] (per toestel), en houdt zelf bij wie er een stroom open
/// heeft. [veranderd] vuurt bij elke wijziging; de server stuurt dan de hele lijst rond (een handvol
/// zones van een paar honderd bytes: kleiner dan bijhouden wat elk toestel al weet).
class ZoneRegister {
  ZoneRegister({
    required this.state,
    required this.pcId,
    required this.pcNaam,
    this.nummer,
    this.bestandVan,
    int Function()? klok,
    Duration tik = const Duration(seconds: 10),
  }) : _klok = klok {
    _sub = state.zoneChanges.listen((_) => _meld());
    // Wie stil valt, wordt na een halve minuut onbereikbaar: dat moet ook rondgaan als er niets gemeld
    // wordt. Alleen sturen als het echt veranderde.
    _tik = Timer.periodic(tik, (_) {
      final nu = _bereikbaarNu();
      if (!setEquals(nu, _laatstBereikbaar)) _meld();
    });
  }

  final LanStateStore state;

  /// Het toestel-id van de pc zelf (`LanSharing.mijnId`), en hoe hij heet.
  final String pcId;
  final String pcNaam;

  /// Een id van de pc als nummer, of null.
  final ZoneNummer? Function(String id)? nummer;

  /// Het bestand achter een nummer-id: extensie, frequentie en diepte — voor [ZoneStaat.kwaliteit].
  final ({String ext, int rate, int bits})? Function(String id)? bestandVan;

  /// Welke versie er op een speaker klinkt (versies.dart, `CastManager.versieVan`): voor de kwaliteit op de kaart.
  String? Function(String speaker)? versieOpSpeaker;

  /// Zet de pc het nummer voor deze speaker om: naar welke maat ("16/48"), of leeg. Gezet door de server, uit de
  /// plafonds van de speaker (`CastManager.plafondVan`).
  String Function(String speakerId, String trackId)? omzettingOpSpeaker;

  /// De bron per zone, onthouden zolang de rij en de afspeellijsten dezelfde zijn ([bronVanRij] kost bij een lange rij
  /// een paar duizend opzoekingen, en de lijst wordt bij elke melding opnieuw gemaakt).
  final Map<String, ({String sleutel, ZoneBron? bron})> _bronGeheugen = {};

  ZoneBron? _bronVoor(String zoneId, List<String> rij, String radio) {
    final sleutel = '${state.rev}|$radio|${rij.length}|${rij.isEmpty ? '' : rij.first}|${rij.isEmpty ? '' : rij.last}';
    final al = _bronGeheugen[zoneId];
    if (al != null && al.sleutel == sleutel) return al.bron;
    final bron = bronVanRij(rij,
        radio: radio,
        nummer: nummer,
        lijsten: [
          for (final l in state.playlists.values)
            if (l.deletedAt == null) (naam: l.name, ids: l.trackIds),
        ]);
    _bronGeheugen[zoneId] = (sleutel: sleutel, bron: bron);
    return bron;
  }

  String _hiernaVan(List<String> rij, int index, String repeat) => _naamVan(volgendInRij(rij, index, repeat));

  /// "Titel — Artiest" van een nummer-id, of leeg.
  String _naamVan(String id) {
    final n = id.isEmpty ? null : nummer?.call(id);
    if (n == null || n.titel.isEmpty) return '';
    return n.artiest.isEmpty ? n.titel : '${n.titel} — ${n.artiest}';
  }

  final int Function()? _klok;
  int get nu => _klok?.call() ?? DateTime.now().millisecondsSinceEpoch;

  late final StreamSubscription<String> _sub;
  late final Timer _tik;
  Set<String> _laatstBereikbaar = const {};

  final Map<String, int> _stromen = {};
  final Map<String, ({String naam, ZoneSoort soort})> _wie = {};
  final Map<String, int> _gezien = {};
  List<SpeakerStand> _speakers = const [];

  final _veranderd = StreamController<void>.broadcast();
  Stream<void> get veranderd => _veranderd.stream;

  void _meld() {
    _laatstBereikbaar = _bereikbaarNu();
    if (!_veranderd.isClosed) _veranderd.add(null);
  }

  Set<String> _bereikbaarNu() {
    final t = nu;
    return {
      for (final id in {..._stromen.keys, ..._gezien.keys})
        if (zoneBereikbaar(stroomOpen: (_stromen[id] ?? 0) > 0, laatstGezienMs: _gezien[id], nuMs: t)) id,
    };
  }

  /// De toestellen van soort [soort] die zich ooit meldden (met of zonder open lijn) — voor een overzicht dat naar
  /// "de gsm" moet (`radio.overzicht` met `voor: 'gsm'`).
  List<String> toestellenVanSoort(ZoneSoort soort) => [
        for (final e in _wie.entries)
          if (e.value.soort == soort) e.key,
      ];

  /// Een toestel opende `/api/zones/events`.
  void stroomOpen(String toestel, {required String naam, required ZoneSoort soort}) {
    if (toestel.isEmpty) return;
    _stromen[toestel] = (_stromen[toestel] ?? 0) + 1;
    _wie[toestel] = (naam: naam, soort: soort);
    _gezien[toestel] = nu;
    _meld();
  }

  /// En sloot hem weer (of de verbinding viel weg).
  void stroomDicht(String toestel) {
    final n = (_stromen[toestel] ?? 0) - 1;
    if (n > 0) {
      _stromen[toestel] = n;
    } else {
      _stromen.remove(toestel);
    }
    _gezien[toestel] = nu;
    _meld();
  }

  /// Een toestel liet van zich horen zonder stroom (een oude app die `/api/state` vraagt).
  void gezien(String toestel, {String? naam, ZoneSoort? soort}) {
    if (toestel.isEmpty) return;
    final was = zoneBereikbaar(stroomOpen: (_stromen[toestel] ?? 0) > 0, laatstGezienMs: _gezien[toestel], nuMs: nu);
    _gezien[toestel] = nu;
    if (naam != null || soort != null) {
      final w = _wie[toestel];
      _wie[toestel] = (naam: naam ?? w?.naam ?? toestel, soort: soort ?? w?.soort ?? ZoneSoort.gsm);
    }
    if (!was) _meld();
  }

  /// De speakers waar de pc nu muziek naartoe stuurt.
  /// De speakers waar de pc nu muziek naartoe stuurt ([actief]), en alle speakers die hij op het netwerk
  /// kent ([bekend]): die staan er ook, zonder muziek, zodat je er iets naartoe kunt sturen.
  void zetSpeakers(List<SpeakerStand> actief,
      {List<({String id, String naam, bool sonos})>? bekend, List<({String leider, List<String> leden})>? groepen}) {
    _speakers = actief;
    if (bekend != null) _bekend = bekend;
    if (groepen != null) _groepen = groepen;
    _meld();
  }

  List<({String id, String naam, bool sonos})> _bekend = const [];

  /// Toestellen die samen spelen (stap 3.2): per leider de volgers (toestel-ids). Zie `samen.dart`. De
  /// leider is een toestel-id, of `spk:<speaker-id>` als toestellen met een speaker meespelen (stap 3.3):
  /// die kan niet bijsturen, dus volgen de toestellen hem.
  final Map<String, List<String>> toestelGroepen = {};

  /// Waar een speaker is voor wie met hem meespeelt (`CastManager.ankerVan`). Gezet door de server.
  Map<String, dynamic>? Function(String speaker)? speakerAnker;

  /// Wat de radio van de pc op speaker [speaker] doet, en wat er over het spelende nummer [trackId] gezegd is — of
  /// null als het niet de radio van de pc is. Gezet door main; zie [ZoneStaat.radioStatus]. Verandert dat, dan
  /// roept main [herzie].
  RadioOpSpeaker? Function(String speaker, String trackId)? radioOpSpeaker;

  /// Opnieuw rondsturen: iets buiten de zones veranderde wat erin staat (de radio op een speaker).
  void herzie() => _meld();

  /// Per speaker hoeveel later hij klinkt dan hij zegt (ms; de schuif "Sonos gelijkzetten").
  final Map<String, int> speakerVertraging = {};

  void zetSpeakerVertraging(String speaker, int ms) {
    if (ms == 0) {
      speakerVertraging.remove(speaker);
    } else {
      speakerVertraging[speaker] = ms;
    }
    _meld();
  }

  /// [leider] met precies [volgers] (toestel-ids; leeg = geen groep). Geeft de volgers terug die
  /// eruit gingen. Een toestel zit in hoogstens één groep, en een leider is geen volger.
  List<String> zetToestelGroep(String leider, List<String> volgers) {
    final weg = <String>[...?toestelGroepen[leider]];
    final nieuw = [for (final v in volgers.toSet()) if (v != leider && v.isNotEmpty) v];
    // Een leider volgt niemand: weg uit een groep waar hij volger was.
    if (nieuw.isNotEmpty) {
      for (final e in toestelGroepen.entries.toList()) {
        if (e.key == leider) continue;
        e.value.remove(leider);
        if (e.value.isEmpty) toestelGroepen.remove(e.key);
      }
    }
    // Wie elders volgde of leidde, komt daar weg.
    for (final v in nieuw) {
      for (final e in toestelGroepen.entries.toList()) {
        if (e.key == leider) continue;
        e.value.remove(v);
        if (e.value.isEmpty) toestelGroepen.remove(e.key);
      }
      final eigen = toestelGroepen.remove(v);
      if (eigen != null) weg.addAll(eigen);
    }
    if (nieuw.isEmpty) {
      toestelGroepen.remove(leider);
    } else {
      toestelGroepen[leider] = nieuw;
    }
    _meld();
    return [for (final w in weg.toSet()) if (!nieuw.contains(w) && w != leider) w];
  }

  /// De leider van [toestel] als het volgt, of null.
  String? leiderVan(String toestel) =>
      toestelGroepen.entries.where((e) => e.value.contains(toestel)).map((e) => e.key).firstOrNull;

  /// Het anker van de groep van [leider]: wat de leider het laatst meldde. Null zonder melding.
  Map<String, dynamic>? ankerVan(String leider) {
    if (leider.startsWith('spk:')) {
      final id = leider.substring(4);
      final a = speakerAnker?.call(id);
      if (a == null) return null;
      // Klinkt de speaker later dan hij zegt, dan horen de volgers ook zoveel later te zijn.
      final ms = ((a['positieMs'] as num?)?.toInt() ?? 0) - (speakerVertraging[id] ?? 0);
      return {...a, 'positieMs': ms < 0 ? 0 : ms};
    }
    final p = state.perToestel[leider];
    if (p == null || p.trackId.isEmpty) return null;
    return {
      'groep': 'dev:$leider',
      'trackId': p.trackId,
      'rij': p.queue,
      'index': p.index,
      'positieMs': p.positionMs,
      'pcMs': p.updatedAt,
      'speelt': p.playing,
    };
  }
  List<({String leider, List<String> leden})> _groepen = const [];

  /// De toestellen met een open stroom: wie "Speel op …" van de pc kan krijgen.
  List<({String id, String naam})> bereikbareToestellen() => [
        for (final z in lijst())
          if (z.online && z.toestel != null && z.toestel != pcId) (id: z.toestel!, naam: z.naam),
      ];

  /// Alle zones, geordend ([ordenZones], met de pc vooraan).
  List<ZoneStaat> lijst() {
    final t = nu;
    final ids = <String>{pcId, ..._stromen.keys, ..._gezien.keys};
    for (final e in state.perToestel.entries) {
      if (t - e.value.updatedAt <= kZoneTotEenDag.inMilliseconds) ids.add(e.key);
    }
    final uit = <ZoneStaat>[];
    final volgers = {for (final v in toestelGroepen.values) ...v};
    for (final id in ids) {
      if (id.isEmpty || volgers.contains(id)) continue;
      final p = state.perToestel[id];
      final wie = _wie[id];
      final pc = id == pcId;
      final online = pc || zoneBereikbaar(stroomOpen: (_stromen[id] ?? 0) > 0, laatstGezienMs: _gezien[id], nuMs: t);
      // Een melding van gisteren is geen zone meer, tenzij het toestel er nu is.
      final vers = p != null && t - p.updatedAt <= kZoneTotEenDag.inMilliseconds;
      if (!pc && !online && !vers) continue;
      final naam = pc
          ? pcNaam
          : (wie?.naam.isNotEmpty ?? false)
              ? wie!.naam
              : (p?.deviceName.isNotEmpty ?? false)
                  ? p!.deviceName
                  : 'Toestel';
      final soort = pc ? ZoneSoort.pc : wie?.soort ?? zoneSoortVoor(platform: '', naam: naam);
      final groep = toestelGroepen[id];
      final z = _zoneUit(
          id: 'dev:$id',
          soort: soort,
          naam: groep == null ? naam : [naam, for (final v in groep) _naamVanToestel(v)].join(' + '),
          online: online,
          p: vers ? p : null);
      uit.add(ZoneStaat.fromJson({
        ...z.toJson(),
        // Elk toestel met de app kan met andere samen spelen (stap 3.2).
        'kanGroeperen': true,
        if (groep != null) 'groep': ['dev:$id', for (final v in groep) 'dev:$v'],
        if (groep != null)
          'leden': [
            ZoneLid(id: 'dev:$id', naam: naam, soort: soort, volume: vers ? p.volume : -1).toJson(),
            for (final v in groep) _toestelLid(v).toJson(),
          ],
      }));
    }
    // Groepen (stap 3.1): de leider draagt de namen van allemaal; de leden staan er niet apart in.
    final namen = {for (final b in _bekend) b.id: b.naam, for (final s in _speakers) s.id: s.naam};
    final sonos = {for (final b in _bekend) if (b.sonos) b.id};
    final groepVan = {for (final g in _groepen) if (g.leden.length > 1) g.leider: g.leden};
    final leden = {for (final g in groepVan.entries) ...g.value.where((l) => l != g.key)};
    String naamVan(String id, String eigen) {
      final g = groepVan[id];
      if (g == null) return eigen;
      return [eigen, for (final l in g) if (l != id) namen[l] ?? l].join(' + ');
    }

    List<String> groepIds(String id) {
      final volgers = toestelGroepen['spk:$id'] ?? const <String>[];
      final sonos = groepVan[id] ?? (volgers.isEmpty ? const <String>[] : [id]);
      return [for (final l in sonos) 'spk:$l', for (final v in volgers) 'dev:$v'];
    }

    final volumeVan = {for (final s in _speakers) s.id: s.volume};
    List<ZoneLid> ledenVan(String id) {
      final ids = groepIds(id);
      if (ids.isEmpty) return const [];
      // De leider eerst, zoals bij een toestelgroep.
      return [
        for (final g in ['spk:$id', ...ids.where((g) => g != 'spk:$id')])
          if (g.startsWith('spk:'))
            ZoneLid(
                id: g,
                naam: namen[g.substring(4)] ?? g.substring(4),
                soort: ZoneSoort.speaker,
                volume: volumeVan[g.substring(4)] ?? -1)
          else
            _toestelLid(g.substring(4)),
      ];
    }

    String naamMetVolgers(String id, String eigen) => [
          naamVan(id, eigen),
          for (final v in toestelGroepen['spk:$id'] ?? const <String>[]) _naamVanToestel(v),
        ].join(' + ');
    for (final s in _speakers) {
      if (leden.contains(s.id)) continue;
      final n = s.trackId == null ? null : nummer?.call(s.trackId!);
      final r = s.radio.isEmpty ? null : radioOpSpeaker?.call(s.id, s.trackId ?? '');
      final rij = speakerRij?.call(s.id);
      final bron = rij == null ? (s.radio.isEmpty ? null : (soort: 'radio', naam: s.radio)) : _bronVoor('spk:${s.id}', rij.rij, s.radio);
      final b = s.trackId == null ? null : bestandVan?.call(versieOpSpeaker?.call(s.id) ?? s.trackId!);
      uit.add(ZoneStaat(
        hierna: rij == null ? '' : _hiernaVan(rij.rij, rij.index, 'off'),
        volgendeId: rij == null ? '' : volgendeOpdracht(rij.rij, rij.index),
        bronSoort: bron?.soort ?? '',
        bronNaam: bron?.naam ?? '',
        kwaliteit: b == null ? '' : kwaliteitLabel(ext: b.ext, rate: b.rate, bits: b.bits),
        omgezet: s.trackId == null ? '' : omzettingOpSpeaker?.call(s.id, s.trackId!) ?? '',
        radioStatus: r?.status ?? '',
        radioPast: r?.past ?? '',
        radioGehaald: r?.gehaald ?? false,
        radioHouden: r?.houden ?? false,
        id: 'spk:${s.id}',
        soort: ZoneSoort.speaker,
        naam: naamMetVolgers(s.id, s.naam),
        groep: groepIds(s.id),
        leden: ledenVan(s.id),
        kanGroeperen: true,
        sonos: sonos.contains(s.id),
        samenMs: toestelGroepen.containsKey('spk:${s.id}') ? speakerVertraging[s.id] ?? 0 : 0,
        online: true,
        playing: s.speelt,
        trackId: s.trackId ?? '',
        titel: n?.titel ?? '',
        artiest: n?.artiest ?? '',
        album: n?.album ?? '',
        positionMs: s.positieMs,
        durationMs: s.duurMs > 0 ? s.duurMs : (n?.duurMs ?? 0),
        opMs: s.opMs,
        index: s.index,
        lengte: s.lengte,
        via: pcNaam,
        volume: s.volume,
        radio: s.radio,
      ));
    }
    final actief = {for (final s in _speakers) s.id};
    for (final b in _bekend) {
      if (actief.contains(b.id) || leden.contains(b.id)) continue;
      uit.add(ZoneStaat(
        id: 'spk:${b.id}',
        soort: ZoneSoort.speaker,
        naam: naamMetVolgers(b.id, b.naam),
        groep: groepIds(b.id),
        leden: ledenVan(b.id),
        kanGroeperen: true,
        sonos: b.sonos,
        samenMs: toestelGroepen.containsKey('spk:${b.id}') ? speakerVertraging[b.id] ?? 0 : 0,
        online: true,
        via: pcNaam,
      ));
    }
    return ordenZones([for (final z in uit) _metVerplaatst(z, t)], hier: 'dev:$pcId');
  }

  /// Zones waarvan de muziek net naar een andere ging: naar welke (de naam), en wanneer. Zie [ZoneStaat.verplaatstNaar].
  final Map<String, ({String naar, int op})> _verplaatst = {};

  /// De muziek van [zoneId] ging naar [naar] (de naam van die zone) — gezet door de overdracht op de pc.
  void verplaatst(String zoneId, String naar) => _verplaatst[zoneId] = (naar: naar, op: nu);

  /// Iemand tikte "Stop" op [zoneId]: ze telt meteen als "Speelt niets", ook al meldde ze haar pauze nog niet.
  void gestopt(String zoneId) => _verplaatst[zoneId] = (naar: '', op: nu);

  /// [zoneId] kreeg iets om te spelen (`play`, `speel`, …): weg met "verplaatst" of "gestopt".
  void speeltWeer(String zoneId) => _verplaatst.remove(zoneId);

  /// Ging de muziek van [zoneId] de laatste [binnen] al ergens heen? Dan hoeft dat niet nog eens.
  bool netVerplaatst(String zoneId, {Duration binnen = const Duration(seconds: 15)}) {
    final v = _verplaatst[zoneId];
    return v != null && nu - v.op < binnen.inMilliseconds;
  }

  /// [z] met [ZoneStaat.verplaatstNaar], tot ze weer zelf speelt. Een melding "speelt" van ná het verplaatsen —
  /// met wat marge voor de bron die het nog niet wist — haalt het weg. Na "Stop" is die marge kort: wie stopt, pauzeert
  /// meteen.
  ZoneStaat _metVerplaatst(ZoneStaat z, int t) {
    final v = _verplaatst[z.id];
    if (v == null) return z;
    final marge = v.naar.isEmpty ? 1500 : 6000;
    if ((z.playing && z.opMs > v.op + marge) || t - v.op > const Duration(hours: 12).inMilliseconds) {
      _verplaatst.remove(z.id);
      return z;
    }
    return ZoneStaat.fromJson({...z.toJson(), 'verplaatstNaar': v.naar, 'verplaatstOp': v.op});
  }

  /// Een toestel als lid van een groep: zijn naam, zijn soort en zijn appvolume uit zijn laatste melding.
  ZoneLid _toestelLid(String id) {
    final naam = _naamVanToestel(id);
    return ZoneLid(
      id: 'dev:$id',
      naam: naam,
      soort: id == pcId ? ZoneSoort.pc : _wie[id]?.soort ?? zoneSoortVoor(platform: '', naam: naam),
      volume: state.perToestel[id]?.volume ?? -1,
    );
  }

  String _naamVanToestel(String id) {
    if (id == pcId) return pcNaam;
    final w = _wie[id];
    if (w != null && w.naam.isNotEmpty) return w.naam;
    final p = state.perToestel[id];
    return p != null && p.deviceName.isNotEmpty ? p.deviceName : 'Toestel';
  }

  ZoneStaat _zoneUit({
    required String id,
    required ZoneSoort soort,
    required String naam,
    required bool online,
    required PlaybackProgress? p,
  }) {
    if (p == null || p.trackId.isEmpty) return ZoneStaat(id: id, soort: soort, naam: naam, online: online);
    final n = nummer?.call(p.trackId);
    final radio = '${p.radio?['naam'] ?? ''}';
    final bron = _bronVoor(id, p.queue, radio);
    // De kwaliteit van wat klinkt: een versie (versies.dart) heeft haar eigen.
    final b = bestandVan?.call(p.versie.isNotEmpty ? p.versie : p.trackId);
    final stroom = p.stroom;
    return ZoneStaat(
      // Een radio meldt wat erna komt apart ([PlaybackProgress.volgend]); de rij noemt dan alleen het spelende nummer.
      hierna: p.volgend.isNotEmpty ? _naamVan(p.volgend) : _hiernaVan(p.queue, p.index, p.repeat),
      volgendeId: p.volgend.isNotEmpty ? p.volgend : volgendeOpdracht(p.queue, p.index),
      bronSoort: bron?.soort ?? '',
      bronNaam: bron?.naam ?? '',
      kwaliteit: b == null ? '' : kwaliteitLabel(ext: b.ext, rate: b.rate, bits: b.bits),
      omgezet: b == null || stroom == null
          ? ''
          : omgezetNaar(
              bestandRate: b.rate,
              bestandBits: b.bits,
              stroomRate: (stroom['rate'] as num?)?.toInt() ?? 0,
              stroomBits: (stroom['bits'] as num?)?.toInt() ?? 0),
      id: id,
      soort: soort,
      naam: naam,
      online: online,
      // Een toestel dat weg is, speelt niet meer — ook al was dat het laatste wat het zei.
      playing: p.playing && online,
      trackId: p.trackId,
      titel: n?.titel ?? '',
      artiest: n?.artiest ?? '',
      album: n?.album ?? '',
      positionMs: p.positionMs,
      durationMs: n?.duurMs ?? 0,
      opMs: p.updatedAt,
      index: p.index,
      lengte: p.queue.length,
      shuffle: p.shuffle,
      repeat: p.repeat,
      radio: '${p.radio?['naam'] ?? ''}',
      volume: p.volume,
    );
  }

  /// Alles in één bericht: de zones, en hoe laat het op de pc is (zodat een toestel met een andere klok
  /// toch de juiste plek in het nummer toont).
  Map<String, dynamic> snapshot() => {
        'nu': nu,
        'zones': [for (final z in lijst()) z.toJson()],
      };

  /// De volledige melding van een toestelzone, met de wachtrij: wat "Hier verder luisteren" nodig heeft.
  /// Null als die zone niets meldde (of een speaker is).
  PlaybackProgress? standVan(String zoneId) {
    if (!zoneId.startsWith('dev:')) return null;
    return state.perToestel[zoneId.substring(4)];
  }

  /// De wachtrij van een speaker die de pc stuurt (ids en de plek van het spelende nummer), of null.
  /// Gezet door de server, uit `CastManager.rijVan`.
  ({List<String> rij, int index})? Function(String speakerId)? speakerRij;

  /// Een venster op de wachtrij van een zone, rond het spelende nummer: [voor] ervoor en [na] erna. Een
  /// geschudde bibliotheek is dertigduizend ids; die horen niet bij elk nieuw nummer over mobiele data.
  /// Null als de zone geen wachtrij meldt. [na] groeit als je in het paneel naar het einde scrolt
  /// (`ZoneSpeler.meerHierna`).
  Map<String, dynamic>? rijVenster(String zoneId, {int voor = 100, int na = kZoneRijNa}) {
    final List<String> rij;
    final int index;
    if (zoneId.startsWith('spk:')) {
      final r = speakerRij?.call(zoneId.substring(4));
      if (r == null) return null;
      rij = r.rij;
      index = r.index;
    } else {
      final p = standVan(zoneId);
      if (p == null) return null;
      rij = p.queue;
      index = p.index;
    }
    final w = rijVensterUit(rij, index, voor: voor, na: na);
    return {'zone': zoneId, 'index': index, 'lengte': rij.length, 'van': w.van, 'rij': w.rij};
  }

  Future<void> dispose() async {
    _tik.cancel();
    await _sub.cancel();
    await _veranderd.close();
  }
}

/// Hoeveel nummers ná het spelende het venster op de wachtrij van een zone eerst meegeeft.
const kZoneRijNa = 400;

/// Hoeveel er bij komen als je in het paneel het einde nadert.
const kZoneRijStap = 400;

/// Meer dan dit geeft de pc in één keer niet: ook een geschudde bibliotheek van dertigduizend past erin.
const kZoneRijHoogstens = 50000;

/// Het stuk van [rij] van [voor] plekken vóór [index] tot [na] erna, en waar het begint.
({int van, List<String> rij}) rijVensterUit(List<String> rij, int index, {int voor = 100, int na = kZoneRijNa}) {
  if (rij.isEmpty) return (van: 0, rij: const []);
  final i = index.clamp(0, rij.length - 1);
  final van = (i - voor).clamp(0, rij.length);
  final tot = (i + na + 1).clamp(van, rij.length);
  return (van: van, rij: rij.sublist(van, tot));
}

/// Wat een speaker speelt als melding zoals een toestel ze geeft (`PlaybackProgress`): om de muziek van
/// een speaker naar een andere zone te verplaatsen. [nuMs] op de klok van de pc.
Map<String, dynamic> speakerAlsStand(SpeakerStand s, List<String> rij, {required int nuMs}) {
  final pos = s.speelt ? s.positieMs + (nuMs - s.opMs).clamp(0, 6 * 60 * 60 * 1000) : s.positieMs;
  return {
    'trackId': s.trackId ?? '',
    'positionMs': s.duurMs > 0 && pos > s.duurMs ? s.duurMs : pos,
    'queue': rij,
    'index': s.index,
    'playing': s.speelt,
    'updatedAt': nuMs,
    'deviceId': 'spk:${s.id}',
    'deviceName': s.naam,
    'shuffle': false,
    'repeat': 'off',
  };
}

/// Waar [trackId] nu staat, met [plek] als voorkeur: daar als het er nog staat, anders het dichtstbij
/// gelegen exemplaar (de rij kan intussen verschoven zijn: een nummer begon, iemand anders voegde iets
/// toe). -1 als het er niet meer in staat.
int plekVoorNummer(List<String> rij, int plek, String trackId) {
  if (trackId.isEmpty) return plek >= 0 && plek < rij.length ? plek : -1;
  if (plek >= 0 && plek < rij.length && rij[plek] == trackId) return plek;
  var beste = -1;
  for (var i = 0; i < rij.length; i++) {
    if (rij[i] != trackId) continue;
    if (beste < 0 || (i - plek).abs() < (beste - plek).abs()) beste = i;
  }
  return beste;
}

/// Wat een toestel van de zones weet: de lijst zoals de pc hem het laatst stuurde, en hoe zijn klok
/// afwijkt van die van de pc.
@immutable
class ZoneLijstStand {
  const ZoneLijstStand({required this.zones, required this.pcNuMs, required this.ontvangenMs});

  final List<ZoneStaat> zones;

  /// De klok van de pc toen hij de lijst stuurde, en die van dit toestel toen ze aankwam.
  final int pcNuMs, ontvangenMs;

  static ZoneLijstStand uitJson(Map<String, dynamic> m, {required int ontvangenMs}) => ZoneLijstStand(
        zones: [
          for (final z in (m['zones'] as List? ?? const []))
            if (z is Map) ZoneStaat.fromJson(z.cast<String, dynamic>()),
        ],
        pcNuMs: (m['nu'] as num?)?.toInt() ?? ontvangenMs,
        ontvangenMs: ontvangenMs,
      );

  /// Hoe laat het nu op de pc is, gerekend vanaf de laatste lijst.
  int nuOpPc(int hierNuMs) => pcNuMs + (hierNuMs - ontvangenMs);
}
