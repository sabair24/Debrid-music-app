/// Nummers waarvan een mp3 speelt en de FLAC nog moet komen.
///
/// De app deed dit als één jacht van tien minuten na de download, en gaf het daarna definitief op.
/// Gemeten waarom dat niet werkt: op één dag was de enige lossless bron voor een nummer een peer die
/// het account geband had, dus de jacht was in twintig seconden voorbij met negen en een halve minuut
/// budget over. Een dag later stond er een andere peer online die hem in twee seconden leverde.
///
/// Peers wisselen dus per dag, en daar hoort geen eenmalige poging bij maar een WENS die blijft staan:
/// op schijf, een herstart overlevend, met een steeds ruimer wordend ritme. Dat is ook wat de native
/// client doet -- die blijft in de wachtrij staan tot het bestand komt.
///
/// Deze file is met opzet vrij van netwerk en van Flutter: wat hier staat is te testen zonder één
/// peer aan te spreken.
library;

import 'dart:convert';
import 'dart:io';

import 'organize.dart' show TrackTags, normKey;

/// Eén openstaande wens.
class LosslessWant {
  const LosslessWant({
    required this.artist,
    required this.title,
    this.album = '',
    this.sinceMs = 0,
    this.tries = 0,
    this.lastTryMs = 0,
    this.refused = const {},
    this.authority,
  });

  final String artist, title, album;

  /// De tags waarmee de mp3 destijds is opgeborgen, meegegeven aan de FLAC die hem vervangt.
  ///
  /// Zonder dit landde de eerste echte vondst als `Singles\Onbekende artiest\Daft Punk - One More Time
  /// (club mix).flac`: de peer had een bestand zónder tags, en er was niets om op terug te vallen. De
  /// eenmalige jacht geeft hierom al `job.authority` mee -- "dezelfde autoriteit als de eerste
  /// landing" -- en een wens die dagen later uitkomt heeft dat net zo hard nodig.
  final TrackTags? authority;

  /// Wanneer de wens ontstond, en hoe vaak er al gezocht is. Samen bepalen ze het ritme.
  final int sinceMs, tries, lastTryMs;

  /// Peers die deze wens niet kunnen vervullen, met de reden erbij: `banned`, `firewall`.
  ///
  /// Onthouden omdat de enige lossless bron voor een nummer er één kan zijn. Zonder dit verbrandt
  /// elke ronde zijn poging op dezelfde peer die het account geband heeft -- wat precies is wat er
  /// gemeten is.
  final Map<String, String> refused;

  /// Stabiele naam van de wens. Niet het pad: het bestand verhuist zodra de tags kloppen.
  String get key => '${normKey(artist)}|${normKey(title)}';

  /// Waar de app naar zoekt. Dezelfde vorm als wat de gebruiker zelf zou typen.
  String get query => '$artist $title'.trim();

  LosslessWant met({int? tries, int? lastTryMs, Map<String, String>? refused}) => LosslessWant(
        artist: artist,
        title: title,
        album: album,
        sinceMs: sinceMs,
        tries: tries ?? this.tries,
        lastTryMs: lastTryMs ?? this.lastTryMs,
        refused: refused ?? this.refused,
        authority: authority,
      );

  Map<String, dynamic> toJson() => {
        'artist': artist,
        'title': title,
        if (album.isNotEmpty) 'album': album,
        'sinceMs': sinceMs,
        'tries': tries,
        'lastTryMs': lastTryMs,
        if (refused.isNotEmpty) 'refused': refused,
        if (authority != null) 'authority': authority!.toJson(),
      };

  static LosslessWant? fromJson(Map<String, dynamic> j) {
    final a = (j['artist'] ?? '').toString().trim();
    final t = (j['title'] ?? '').toString().trim();
    if (a.isEmpty || t.isEmpty) return null; // zonder naam valt er niets te zoeken
    final auth = j['authority'];
    return LosslessWant(
      artist: a,
      title: t,
      album: (j['album'] ?? '').toString(),
      authority: auth is Map<String, dynamic> ? TrackTags.fromJson(auth) : null,
      sinceMs: (j['sinceMs'] as num?)?.toInt() ?? 0,
      tries: (j['tries'] as num?)?.toInt() ?? 0,
      lastTryMs: (j['lastTryMs'] as num?)?.toInt() ?? 0,
      refused: {
        for (final e in (j['refused'] as Map?)?.entries ?? const <MapEntry>[])
          '${e.key}': '${e.value}',
      },
    );
  }
}

/// Hoe lang er gewacht wordt voor de volgende poging, naar het aantal pogingen.
///
/// Oplopend omdat de reden dat het niet lukt langzaam beweegt: een peer die vandaag offline is, is
/// dat over vijf minuten ook. Maar niet eindeloos oplopend -- na een dag blijft het een dag, want
/// "over een maand" is hetzelfde als opgeven, en opgeven is precies wat hier niet mag.
Duration wachtVoor(int tries) => switch (tries) {
      <= 0 => Duration.zero,
      1 => const Duration(minutes: 20),
      2 => const Duration(hours: 2),
      3 => const Duration(hours: 8),
      _ => const Duration(days: 1),
    };

/// Is deze wens aan de beurt?
bool wensIsAanDeBeurt(LosslessWant w, int nowMs) =>
    nowMs - w.lastTryMs >= wachtVoor(w.tries).inMilliseconds;

/// De lijst met openstaande wensen, op schijf naast de andere staatbestanden.
///
/// Zelfde vorm als pending_downloads.json: opschrijven vóór het iets doet, want het hele punt is dat
/// het overleeft dat de app geen kans krijgt om af te ronden.
class LosslessWants {
  LosslessWants(this._path);
  final String _path;

  final Map<String, LosslessWant> _byKey = {};

  int get count => _byKey.length;
  List<LosslessWant> get all => _byKey.values.toList();

  /// De wensen die nu gezocht mogen worden, oudste wens eerst -- wie het langst wacht is eerst.
  List<LosslessWant> due(int nowMs) => (_byKey.values.where((w) => wensIsAanDeBeurt(w, nowMs)).toList()
    ..sort((a, b) => a.sinceMs.compareTo(b.sinceMs)));

  Future<void> load() async {
    try {
      final f = File(_path);
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! List) return;
      _byKey.clear();
      for (final e in j) {
        if (e is! Map) continue;
        final w = LosslessWant.fromJson(Map<String, dynamic>.from(e));
        if (w != null) _byKey[w.key] = w;
      }
    } catch (_) {/* een onleesbare lijst is geen reden om de app niet te starten */}
  }

  Future<void> save() async {
    try {
      final f = File(_path);
      if (_byKey.isEmpty) {
        if (await f.exists()) await f.delete();
        return;
      }
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode([for (final w in _byKey.values) w.toJson()]));
    } catch (_) {/* de wens gaat verloren bij een herstart; niet erger dan dat */}
  }

  /// Een wens toevoegen, of een bestaande laten staan zoals hij is.
  ///
  /// Laten staan en niet vervangen: anders zet elke nieuwe mp3 van hetzelfde nummer de teller en het
  /// ritme terug op nul, en dan zoekt de app elke twintig minuten opnieuw bij een peer die hem toch
  /// niet gaat geven.
  bool want(LosslessWant w) {
    if (_byKey.containsKey(w.key)) return false;
    _byKey[w.key] = w;
    return true;
  }

  void update(LosslessWant w) => _byKey[w.key] = w;

  bool forget(String key) => _byKey.remove(key) != null;

  /// Wensen laten vallen waarvan de FLAC er inmiddels is -- ook als hij van buiten de app kwam.
  ///
  /// Nodig gebleken uit een echt geval: de gebruiker haalde de FLAC met de native client binnen, in
  /// een map die naar de peer heet en onder een andere albumnaam. Zonder deze controle blijft de app
  /// eeuwig jagen op iets wat al op schijf staat -- en biedt hij het ook nog aan om te downloaden.
  List<String> forgetWhatWeHave(bool Function(String artist, String title) haveLossless) {
    final weg = <String>[];
    for (final w in _byKey.values.toList()) {
      if (haveLossless(w.artist, w.title)) {
        _byKey.remove(w.key);
        weg.add(w.key);
      }
    }
    return weg;
  }
}
