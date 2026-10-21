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

/// Hoe lang een toestel zonder open stroom en zonder melding nog als bereikbaar geldt.
const kZoneBereikbaar = Duration(seconds: 30);

/// Wat een zone na zoveel stilte nog in de lijst houdt: wat er gisteren speelde, telt niet meer.
const kZoneTotEenDag = Duration(hours: 24);

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
  });

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
      other.volume == volume;

  @override
  int get hashCode => Object.hash(id, online, playing, trackId, positionMs, opMs, index, lengte);
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
  void zetSpeakers(List<SpeakerStand> actief, {List<({String id, String naam})>? bekend}) {
    _speakers = actief;
    if (bekend != null) _bekend = bekend;
    _meld();
  }

  List<({String id, String naam})> _bekend = const [];

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
    for (final id in ids) {
      if (id.isEmpty) continue;
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
      uit.add(_zoneUit(id: 'dev:$id', soort: soort, naam: naam, online: online, p: vers ? p : null));
    }
    for (final s in _speakers) {
      final n = s.trackId == null ? null : nummer?.call(s.trackId!);
      uit.add(ZoneStaat(
        id: 'spk:${s.id}',
        soort: ZoneSoort.speaker,
        naam: s.naam,
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
      ));
    }
    final actief = {for (final s in _speakers) s.id};
    for (final b in _bekend) {
      if (actief.contains(b.id)) continue;
      uit.add(ZoneStaat(id: 'spk:${b.id}', soort: ZoneSoort.speaker, naam: b.naam, online: true, via: pcNaam));
    }
    return ordenZones(uit, hier: 'dev:$pcId');
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
    return ZoneStaat(
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

  Future<void> dispose() async {
    _tik.cancel();
    await _sub.cancel();
    await _veranderd.close();
  }
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
