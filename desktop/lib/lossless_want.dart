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

/// Namen die geen artiest zijn maar "dit is een verzamelaar".
///
/// Ze horen niet in een zoekvraag: een peer noemt zijn bestand naar de uitvoerder en nooit naar
/// "Various Artists". Bewust een korte, letterlijke lijst en geen slimme regel -- iets wat zelf
/// beslist wat "verdacht" is, gooit ooit een echte artiestennaam weg.
final _verzamelnaam = RegExp(
    r'^\s*(various(\s*artists?)?|v\.?\s*a\.?|diverse(\s+artiesten)?|verschillende\s+artiesten|'
    r'unknown(\s+artist)?|onbekende?\s+artiest)\s*$',
    caseSensitive: false);

/// Staat hier "de plaat is van meer dan één artiest" in plaats van een naam?
bool isVerzamelnaam(String s) => _verzamelnaam.hasMatch(s);

/// De uitvoerder uit een bestandsnaam van de vorm `NN - Uitvoerder - Titel.ext`.
///
/// De enige bron die op het juiste moment wél beschikbaar is. Een verzamelaar-mp3 heeft "Various
/// Artists" in de ARTIST-tag en geen PERFORMER-veld (dat bestaat in ID3 niet), maar de peer noemt zijn
/// bestand vrijwel altijd naar de echte artiest -- daar zoeken andere mensen immers op.
///
/// Alleen als het STAARTSTUK de titel is. Zonder die eis is het middenstuk net zo goed een deel van de
/// titel, en dan gaat de app zoeken op een woord dat niemand als artiest kent -- een vergiftigde
/// zoekvraag met een geloofwaardig gezicht, wat erger is dan geen.
String? performerFromFilename(String filename, String title) {
  var naam = filename.replaceAll('\\', '/');
  naam = naam.substring(naam.lastIndexOf('/') + 1);
  final punt = naam.lastIndexOf('.');
  if (punt > 0) naam = naam.substring(0, punt);
  // Het nummer vooraan eraf: "5-03", "13", "215" of "01." horen niet bij de naam.
  naam = naam.replaceFirst(RegExp(r'^\s*\d+([-.]\d+)?\s*[-.]?\s*'), '');
  final delen = naam.split(RegExp(r'\s+-\s+'));
  if (delen.length < 2) return null;
  if (normKey(delen.last) != normKey(title)) return null; // het staartstuk is de titel niet
  final uitvoerder = delen.sublist(0, delen.length - 1).join(' - ').trim();
  if (uitvoerder.isEmpty || isVerzamelnaam(uitvoerder)) return null;
  return uitvoerder;
}

/// Eén bepaald bestand bij één bepaalde peer.
///
/// **Waarom een wens dit moet kunnen onthouden.** Wie zelf een regel uit de lijst aanklikt, doet dat
/// omdat de automatische keuze de verkeerde was — een andere opname, een andere persing. Kwam die
/// kopie niet binnen, dan is "dan zoeken we morgen wel iets anders van dat nummer" precies de
/// overrule die de gebruiker net had weggeklikt. Dus wordt de bron zelf bewaard en morgen opnieuw
/// gevraagd, bij dezelfde peer.
///
/// Genoeg velden om er weer een zoekresultaat van te maken: de overdracht vraagt om naam, pad en
/// grootte, en de rest is wat het scherm erover zei.
class VasteBron {
  const VasteBron({
    required this.username,
    required this.filename,
    required this.size,
    this.bitrate,
    this.durationSec,
    this.sampleRate,
    this.bitDepth,
  });

  final String username, filename;
  final int size;
  final int? bitrate, durationSec, sampleRate, bitDepth;

  Map<String, dynamic> toJson() => {
        'username': username,
        'filename': filename,
        'size': size,
        if (bitrate != null) 'bitrate': bitrate,
        if (durationSec != null) 'durationSec': durationSec,
        if (sampleRate != null) 'sampleRate': sampleRate,
        if (bitDepth != null) 'bitDepth': bitDepth,
      };

  static VasteBron? fromJson(Map<String, dynamic> j) {
    final u = (j['username'] ?? '').toString();
    final f = (j['filename'] ?? '').toString();
    if (u.isEmpty || f.isEmpty) return null;
    return VasteBron(
      username: u,
      filename: f,
      size: (j['size'] as num?)?.toInt() ?? 0,
      bitrate: (j['bitrate'] as num?)?.toInt(),
      durationSec: (j['durationSec'] as num?)?.toInt(),
      sampleRate: (j['sampleRate'] as num?)?.toInt(),
      bitDepth: (j['bitDepth'] as num?)?.toInt(),
    );
  }
}

/// De zoekvraag voor één nummer, zoals een mens hem zou typen.
///
/// De ARTIEST-tag is niet altijd de artiest. Op een verzamelaar staat er "Various Artists", en dat
/// woord in de vraag stoppen maakt hem juist SLECHTER: gemeten gaf "Various Artists Jij Bent Zo
/// Mooi" precies één treffer, terwijl de titel alleen door tientallen mappen heen zoekt. Peers
/// noemen hun bestanden naar de uitvoerder, nooit naar "Various Artists".
///
/// Dus: [performer] als die bekend is, anders de artiest zolang dat een echte naam is, en anders de
/// titel alleen. Een matige zoekvraag is beter dan een vergiftigde.
///
/// Stond eerst als `LosslessWant.query` en is eruit getild toen het menu er "Zoeken met Soulseek"
/// bij kreeg: dezelfde valkuil, en één plek waar hij opgelost is.
String zoekvraagVoorNummer(String title, {String? performer, String? artist}) {
  for (final naam in [performer, artist]) {
    final n = (naam ?? '').trim();
    if (n.isNotEmpty && !isVerzamelnaam(n)) return '$n $title'.trim();
  }
  return title.trim();
}

/// Hetzelfde voor een hele plaat.
///
/// Een verzamelaar heeft geen artiest om mee te zoeken, en dan is de albumtitel alleen het beste wat
/// er is — er is hier geen bestandsnaam om op terug te vallen zoals bij een nummer.
String zoekvraagVoorAlbum(String artist, String album) {
  final n = artist.trim();
  return n.isEmpty || isVerzamelnaam(n) ? album.trim() : '$n $album'.trim();
}

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
    this.performer,
    this.exact,
  });

  /// Precies dit bestand bij precies deze peer, of null voor "zoek het beste dat je vindt".
  ///
  /// Is dit gevuld, dan wordt er NIET gezocht en NIETS vervangen: er wordt opnieuw bij die ene peer
  /// aangeklopt. Zie [VasteBron].
  final VasteBron? exact;

  final String artist, title, album;

  /// Wie het nummer werkelijk uitvoert, als dat iets anders is dan de artiest-tag.
  ///
  /// Op een verzamelaar zegt ARTIST "Various Artists" en staat de echte naam in PERFORMER -- precies
  /// waar de splitser hem zelf neerzet. Alleen deze naam maakt een zoekvraag die iets vindt.
  final String? performer;

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
  ///
  /// Een wens om één bepaald bestand heet naar dat bestand. Anders zou hij botsen met de gewone wens
  /// om hetzelfde nummer — en dan zou de ene de andere overschrijven, wat afhankelijk van de
  /// volgorde ofwel de eigen keuze ofwel de jacht op een FLAC laat verdwijnen.
  String get key =>
      exact != null ? 'bron|${exact!.username}|${normKey(exact!.filename)}' : '${normKey(artist)}|${normKey(title)}';

  /// Waar de app naar zoekt. Dezelfde vorm als wat de gebruiker zelf zou typen.
  ///
  /// De ARTIEST-tag is hier niet altijd de artiest. Op een verzamelaar staat er "Various Artists", en
  /// dat woord in de zoekvraag stoppen maakt hem juist slechter: gemeten gaf "Various Artists Jij Bent
  /// Zo Mooi" precies één treffer, terwijl de titel alleen door tientallen mappen heen zoekt. Peers
  /// noemen hun bestanden naar de UITVOERDER, nooit naar "Various Artists".
  ///
  /// Dus: [performer] als die bekend is, anders de artiest zolang dat een echte naam is, en anders de
  /// titel alleen. Een matige zoekvraag is beter dan een vergiftigde.
  String get query => zoekvraagVoorNummer(title, performer: performer, artist: artist);

  LosslessWant met({int? tries, int? lastTryMs, Map<String, String>? refused}) => LosslessWant(
        artist: artist,
        title: title,
        album: album,
        sinceMs: sinceMs,
        tries: tries ?? this.tries,
        lastTryMs: lastTryMs ?? this.lastTryMs,
        refused: refused ?? this.refused,
        authority: authority,
        performer: performer,
        exact: exact,
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
        if (performer != null && performer!.isNotEmpty) 'performer': performer,
        if (exact != null) 'exact': exact!.toJson(),
      };

  static LosslessWant? fromJson(Map<String, dynamic> j) {
    final a = (j['artist'] ?? '').toString().trim();
    final t = (j['title'] ?? '').toString().trim();
    final ex = j['exact'];
    final bron = ex is Map ? VasteBron.fromJson(Map<String, dynamic>.from(ex)) : null;
    // Zonder naam valt er niets te ZOEKEN — maar een wens om één bepaald bestand zoekt niet: die
    // klopt opnieuw aan bij een peer, en daar is genoeg aan een naam en een pad. Een download die
    // mislukte voordat er ook maar één tag gelezen kon worden heeft vaak niets anders.
    if (bron == null && (a.isEmpty || t.isEmpty)) return null;
    final auth = j['authority'];
    return LosslessWant(
      exact: bron,
      artist: a,
      title: t,
      album: (j['album'] ?? '').toString(),
      authority: auth is Map<String, dynamic> ? TrackTags.fromJson(auth) : null,
      performer: (j['performer'] as String?)?.trim(),
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
  /// Ook de UITVOERDER telt mee, niet alleen de artiest-tag.
  ///
  /// Op een verzamelaar staat in die tag "Various Artists", en dat is geen naam waar iets mee te
  /// vinden is. De echte uitvoerder staat dan in [LosslessWant.performer] — uit de bestandsnaam van
  /// de peer, want daar noemen mensen hem wél bij naam. Zonder deze tweede vraag bleef zo'n wens
  /// eeuwig staan terwijl de FLAC allang op schijf stond, gefiled onder de artiest zelf.
  List<String> forgetWhatWeHave(bool Function(String artist, String title) haveLossless) {
    final weg = <String>[];
    for (final w in _byKey.values.toList()) {
      // Zonder titel valt er niets op te zoeken in de bibliotheek, en twee lege namen matchen van
      // alles. Een wens om één bepaald bestand zonder tags blijft dus gewoon staan.
      if (w.title.trim().isEmpty) continue;
      final namen = <String>[
        if (w.artist.trim().isNotEmpty && !isVerzamelnaam(w.artist)) w.artist,
        if ((w.performer ?? '').trim().isNotEmpty) w.performer!,
      ];
      if (namen.any((n) => haveLossless(n, w.title))) {
        _byKey.remove(w.key);
        weg.add(w.key);
      }
    }
    return weg;
  }
}
