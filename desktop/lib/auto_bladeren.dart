/// Wat je in de auto te zien krijgt als je DebridMusic openslaat.
///
/// **Waarom dit een losse laag is.** Android Auto praat met de `MediaBrowserService` die
/// `audio_service` al draait: het vraagt "wat zit er onder deze knoop" en "speel dit id". Meer niet.
/// De hele boom is dus een pure functie van de bibliotheek naar een lijst items, en dat is precies
/// wat je wilt kunnen toetsen zonder een auto, een telefoon of een draaiende speler.
///
/// **De regels van de weg bepalen de vorm.** Dit is geen tweede bibliotheekscherm:
///
/// * Een handvol knopen op het eerste niveau, en niet dieper dan nodig. Wie rijdt kijkt in stukjes
///   van een halve seconde.
/// * Het meest gebruikte bovenaan. "Verder waar je was" en "Recent toegevoegd" staan boven de
///   volledige alfabetische lijst — die tweede is voor thuis.
/// * Wat speelbaar is, speelt met één tik. Een album openen om dan nóg een nummer te moeten kiezen
///   is een handeling te veel achter het stuur.
/// * Lijsten worden afgekapt. Een hoofdunit toont er toch maar een stuk of wat, en duizend items
///   over de Binder duwen is hoe je hem laat haperen.
library;

import 'package:audio_service/audio_service.dart';

import 'models.dart';

/// De vaste knopen. Als string, want Auto vraagt ze zo terug.
class AutoId {
  static const wortel = 'wortel';
  static const verder = 'verder';
  static const recent = 'recent';
  static const albums = 'albums';
  static const artiesten = 'artiesten';
  static const favorieten = 'favorieten';
  static const afspeellijsten = 'afspeellijsten';

  /// Alle nummers, los van hun album.
  static const nummers = 'nummers';

  /// De hele bibliotheek, geschud. Speelbaar, geen knoop.
  static const schudAlles = 'schud-alles';

  /// `album:<artiest><scheider><titel>`
  static const albumVoorvoegsel = 'album:';

  /// `artiest:<naam>`
  static const artiestVoorvoegsel = 'artiest:';

  /// `lijst:<id>`
  static const lijstVoorvoegsel = 'lijst:';

  /// `nummer:<pad>`
  static const nummerVoorvoegsel = 'nummer:';

  /// Een stuurteken, met opzet geen spatie of streepje.
  ///
  /// Bijna elke artiest en elke albumtitel bevat spaties, dus splitsen op een spatie haalt het id
  /// bij het teruglezen op de verkeerde plek uit elkaar — en dan opent "Vaya Con Dios · The Best Of"
  /// niets. Een stuurteken komt in geen enkele naam voor.
  static const scheider = '\u0001';
}

/// Hoeveel er per lijst hoogstens meegaat.
const int autoMaxPerLijst = 100;

/// Wat de bladeraar van de rest van de app nodig heeft.
///
/// Een record en geen klasse: dit is puur een greep naar bestaande lijsten, en een nepversie in een
/// toets moet één regel zijn.
typedef AutoBron = ({
  List<Album> Function() albums,
  List<Track> Function() recent,
  List<Track> Function() favorieten,
  List<Track> Function() verder,
  List<({String id, String naam})> Function() afspeellijsten,
  List<Track> Function(String lijstId) nummersVanLijst,

  /// Alle nummers, los van hun album — dezelfde lijst als het Tracks-scherm in de app.
  List<Track> Function() alleNummers,

  /// De hoes van een nummer of album, als URI die Android Auto kan openen. Null = geen hoes.
  ///
  /// Een functie en geen veld op [Track]: het maken van die URI schrijft een bestand, en dat hoort
  /// niet in een model te zitten. Zie auto_hoezen.dart voor waarom een `file:`-pad hier niet werkt.
  Uri? Function(Track) hoesVanNummer,
  Uri? Function(Album) hoesVanAlbum,
});

/// Een album-id terug uit elkaar halen, op het EERSTE stuurteken.
///
/// Op het eerste, want een titel mag er in theorie nog een bevatten; een artiest niet, en die staat
/// vooraan. Null als het geen album-id is of als de scheider ontbreekt.
({String artiest, String titel})? splitsAlbumId(String id) {
  if (!id.startsWith(AutoId.albumVoorvoegsel)) return null;
  final rest = id.substring(AutoId.albumVoorvoegsel.length);
  final i = rest.indexOf(AutoId.scheider);
  if (i <= 0) return null;
  return (artiest: rest.substring(0, i), titel: rest.substring(i + 1));
}

String _leegLabel(String id) => switch (id) {
      AutoId.verder => 'Nog niets afgespeeld',
      AutoId.recent => 'Nog niets toegevoegd',
      AutoId.favorieten => 'Nog geen favorieten',
      AutoId.afspeellijsten => 'Nog geen afspeellijsten',
      _ => 'Niets gevonden',
    };

MediaItem _map(String id, String titel) => MediaItem(id: id, title: titel, playable: false);

MediaItem _nummer(Track t, AutoBron bron) => MediaItem(
      id: '${AutoId.nummerVoorvoegsel}${t.path}',
      title: t.title,
      album: t.album,
      artist: t.artist,
      duration: t.duration,
      artUri: bron.hoesVanNummer(t),
      playable: true,
    );

/// Een album is speelbaar, niet bladerbaar.
///
/// Auto laat er maar één van de twee toe per item. Wie in de auto een album aantikt wil dat het gaat
/// spelen; het losse nummer zoeken is een thuisbezigheid, en die kan nog via Artiesten.
MediaItem _album(Album a, AutoBron bron) => MediaItem(
      id: '${AutoId.albumVoorvoegsel}${a.artist}${AutoId.scheider}${a.title}',
      title: a.title,
      album: a.title,
      artist: a.artist,
      artUri: bron.hoesVanAlbum(a),
      playable: true,
    );

/// De naam waaronder Android Auto de wortel opvraagt.
///
/// **Dit kostte de eerste poging.** `audio_service` geeft de wortel uit als `'root'`
/// (`AudioService.browsableRootId`), en dát is wat Auto terugvraagt — niet onze eigen naam. De app
/// stond keurig in de app-lijst van de auto, opende, en toonde "Niets gevonden": mijn eigen
/// leegmelding, omdat `'root'` door de hele switch viel. Dertien groene toetsen en een leeg scherm in
/// de auto.
///
/// Hier en niet in de handler, zodat er een toets op kan staan.
const autoWortelVanHetSysteem = 'root';

String _alsWortel(String id) =>
    id == autoWortelVanHetSysteem || id == AutoId.wortel ? AutoId.wortel : id;

/// De kinderen van een knoop. Lege lijst als het id niets betekent.
List<MediaItem> autoKinderen(String parentIdRuw, AutoBron bron) {
  final parentId = _alsWortel(parentIdRuw);
  List<MediaItem> nummers(List<Track> ts) =>
      [for (final t in ts.take(autoMaxPerLijst)) _nummer(t, bron)];

  switch (parentId) {
    case AutoId.wortel:
      // Deze volgorde IS de navigatie, en niet zomaar. Android Auto zet de eerste drie als tabblad
      // bovenaan en propt de rest onder "Meer" — wat op de vierde plek staat kost dus een tik
      // extra. Nummers staat daarom vóór Favorieten en Afspeellijsten.
      return [
        _map(AutoId.verder, 'Verder waar je was'),
        _map(AutoId.recent, 'Recent toegevoegd'),
        _map(AutoId.nummers, 'Nummers'),
        _map(AutoId.favorieten, 'Favorieten'),
        _map(AutoId.afspeellijsten, 'Afspeellijsten'),
        _map(AutoId.albums, 'Albums'),
        _map(AutoId.artiesten, 'Artiesten'),
      ];
    case AutoId.nummers:
      // "Alles schudden" bovenaan, want dat is waar een lijst van honderden nummers achter het
      // stuur voor gebruikt wordt. Doorbladeren kan daarna nog steeds.
      final alle = bron.alleNummers();
      if (alle.isEmpty) return const [];
      return [
        MediaItem(
          id: AutoId.schudAlles,
          title: 'Alles schudden',
          artist: '${alle.length} nummers',
          playable: true,
        ),
        ...nummers(alle),
      ];
    case AutoId.verder:
      return nummers(bron.verder());
    case AutoId.recent:
      return nummers(bron.recent());
    case AutoId.favorieten:
      return nummers(bron.favorieten());
    case AutoId.afspeellijsten:
      return [
        for (final l in bron.afspeellijsten().take(autoMaxPerLijst))
          _map('${AutoId.lijstVoorvoegsel}${l.id}', l.naam),
      ];
    case AutoId.albums:
      return [for (final a in bron.albums().take(autoMaxPerLijst)) _album(a, bron)];
    case AutoId.artiesten:
      // Uit de albums, zodat er geen tweede waarheid over "welke artiesten heb ik" ontstaat.
      final gezien = <String>{};
      final uit = <MediaItem>[];
      for (final a in bron.albums()) {
        if (a.artist.trim().isEmpty || !gezien.add(a.artist)) continue;
        uit.add(_map('${AutoId.artiestVoorvoegsel}${a.artist}', a.artist));
        if (uit.length >= autoMaxPerLijst) break;
      }
      return uit;
  }

  if (parentId.startsWith(AutoId.artiestVoorvoegsel)) {
    final naam = parentId.substring(AutoId.artiestVoorvoegsel.length);
    return [
      for (final a in bron.albums())
        if (a.artist == naam) _album(a, bron),
    ].take(autoMaxPerLijst).toList();
  }

  final paar = splitsAlbumId(parentId);
  if (paar != null) {
    for (final a in bron.albums()) {
      if (a.artist == paar.artiest && a.title == paar.titel) return nummers(a.tracks);
    }
    return const [];
  }

  if (parentId.startsWith(AutoId.lijstVoorvoegsel)) {
    return nummers(bron.nummersVanLijst(parentId.substring(AutoId.lijstVoorvoegsel.length)));
  }

  return const [];
}

/// Hetzelfde, maar met een regel "nog niets" in plaats van een leeg scherm.
///
/// Een lege lijst leest in een auto als "kapot": je hebt aangetikt, er gebeurde niets, en je kijkt
/// nog een keer terwijl je zou moeten rijden.
List<MediaItem> autoKinderenMetLeegmelding(String parentIdRuw, AutoBron bron) {
  final parentId = _alsWortel(parentIdRuw);
  final kinderen = autoKinderen(parentId, bron);
  if (kinderen.isNotEmpty || parentId == AutoId.wortel) return kinderen;
  return [MediaItem(id: 'leeg:$parentId', title: _leegLabel(parentId), playable: false)];
}

/// Wat er moet spelen als iemand dit id aantikt, in de volgorde waarin het moet spelen.
///
/// Leeg betekent "hier valt niets te spelen" — dan hoort er niets te gebeuren, in plaats van dat de
/// vorige wachtrij doorloopt en je denkt dat je iets anders gekozen hebt.
List<Track> autoSpeellijstVoor(String mediaId, AutoBron bron) {
  if (mediaId.startsWith(AutoId.nummerVoorvoegsel)) {
    final pad = mediaId.substring(AutoId.nummerVoorvoegsel.length);
    // Met zijn album eromheen, zodat "volgende" doet wat je verwacht.
    for (final a in bron.albums()) {
      final i = a.tracks.indexWhere((t) => t.path == pad);
      if (i >= 0) return [...a.tracks.skip(i), ...a.tracks.take(i)];
    }
    // Zijn album eerst, want daar hoort "volgende" bij. Daarna de lijsten waar hij uit aangetikt kan
    // zijn — [alleNummers] hoort daar ook bij, anders doet een tik in de nummerlijst niets voor elk
    // nummer waarvan het album niet (meer) in de bibliotheek staat.
    for (final lijst in [
      bron.verder(),
      bron.recent(),
      bron.favorieten(),
      bron.alleNummers(),
    ]) {
      final i = lijst.indexWhere((t) => t.path == pad);
      if (i >= 0) return [...lijst.skip(i), ...lijst.take(i)];
    }
    return const [];
  }

  final paar = splitsAlbumId(mediaId);
  if (paar != null) {
    for (final a in bron.albums()) {
      if (a.artist == paar.artiest && a.title == paar.titel) return a.tracks;
    }
    return const [];
  }

  if (mediaId.startsWith(AutoId.lijstVoorvoegsel)) {
    return bron.nummersVanLijst(mediaId.substring(AutoId.lijstVoorvoegsel.length));
  }

  return switch (mediaId) {
    AutoId.verder => bron.verder(),
    AutoId.recent => bron.recent(),
    AutoId.favorieten => bron.favorieten(),
    // Beide de hele bibliotheek. Het schudden zelf gebeurt niet hier: deze functie is puur en moet
    // bij dezelfde invoer hetzelfde teruggeven, anders is er niets aan te toetsen. Wie
    // [AutoId.schudAlles] aantikt zet shuffle aan in de speler — zie de afhandeling in
    // now_playing.dart.
    AutoId.nummers || AutoId.schudAlles => bron.alleNummers(),
    _ => const [],
  };
}
