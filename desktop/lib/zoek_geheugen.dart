/// Wat het zoekscherm al gevonden had, over een schermwissel heen.
///
/// **Het gemelde geval.** Zoek op "rihanna", tik een nummer aan om te downloaden, ga naar de speler
/// om te horen of het goed is, en kom terug: alles weg. De zoekterm, de resultaten, hoe ver je
/// gescrold was. Opnieuw typen, opnieuw wachten, opnieuw scrollen — en dat elke keer dat je iets
/// wilt controleren.
///
/// **Waarom dat gebeurde, en het was geen toeval.** De schil bouwt zijn secties in een
/// `AnimatedSwitcher` met een sleutel per sectie. Wissel je van sectie, dan gaat de oude sectie de
/// boom UIT en wordt hij weggegooid; de staat van het zoekscherm begon daarna elke keer leeg.
///
/// Erger nog: een zoekopdracht die nog liep was óók weg. Elke terugroep was bewaakt met `mounted`,
/// en dat is na de wissel onwaar — de resultaten kwamen dus wél binnen van Soulseek, maar er was
/// niemand meer die ze aannam. Precies in het scenario waar de klacht over ging, want een
/// Soulseek-ronde duurt ruim acht seconden en je bent in die tijd naar de speler.
///
/// **Bewust alleen de gevonden LIJSTEN en niet de widgetboom.** Dat laatste (een `IndexedStack`)
/// houdt verborgen schermen in de boom, en dan blijven ze meeluisteren en hertekenen. Zelfde
/// afweging als bij het startscherm, waar dit eerder zo opgelost is.
///
/// **Alleen binnen één sessie.** Niets hiervan gaat naar schijf: Soulseek-peers van een uur geleden
/// zijn offline, en een lijst die niet meer klopt is erger dan een leeg scherm.
///
/// Los bestand en openbaar, want statisch en zonder widget — daarmee is dit na te meten zonder
/// toestel en zonder netwerk, net als `zoekladder.dart` en `slsk_groepen.dart`.
library;

import 'catalog.dart';
import 'quality.dart';
import 'soulseek.dart';
import 'tidal.dart';
import 'torbox.dart';

/// Welk tabblad er open stond. Dezelfde nummers als `_mode` op het scherm.
class ZoekTab {
  static const bladeren = 0;
  static const direct = 1;
  static const tidal = 2;
}

/// Het geheugen zelf: alleen statische velden, geen widget.
class ZoekGeheugen {
  /// Welk tabblad open stond, en wat er in het zoekveld stond.
  static int tab = ZoekTab.bladeren;
  static String vraag = '';

  // ── Bladeren ──────────────────────────────────────────────────────────────
  static List<CatalogArtist> artiesten = const [];
  static List<CatalogAlbumHit> albums = const [];
  static List<CatalogTrackHit> nummers = const [];
  static int? nummerOpen;

  // ── Direct zoeken ─────────────────────────────────────────────────────────
  static List<SearchResult> torrents = const [];
  static List<SoulseekFile> slsk = const [];

  /// Wat er letterlijk getypt is, en waar Soulseek uiteindelijk op gezocht heeft.
  static String? getypt;
  static String? gezochtDirect;
  static String? status;
  static QFilter filter = QFilter.all;

  /// Welke Soulseek-gebruikers je had opengeklapt.
  ///
  /// Op naam en niet op plaats in de lijst: de volgorde verandert terwijl er resultaten
  /// binnenstromen, dus een nummer zou na terugkomst een ándere gebruiker openzetten.
  static final Set<String> slskOpen = <String>{};

  /// En wie je juist dicht klapte. Twee verzamelingen, want de bovenste gebruikers staan vanzelf
  /// open: met één was "niet opengeklapt" niet te onderscheiden van "dichtgeklapt".
  static final Set<String> slskDicht = <String>{};

  // ── TIDAL ─────────────────────────────────────────────────────────────────
  static List<TidalTrack> tidalNummers = const [];
  static List<TidalAlbum> tidalAlbums = const [];
  static int? tidalNummerOpen;
  static int? tidalAlbumOpen;

  /// Het volgnummer van de zoekopdracht.
  ///
  /// **Statisch, en dat is een reparatie op zichzelf.** Dit stond als veld in de staat van het
  /// scherm, en daarmee begon het bij elke schermwissel weer bij nul — een oudere, nog lopende
  /// zoekopdracht werd daardoor per ongeluk weer geldig verklaard en kon over een nieuwere heen
  /// vallen. Het volgnummer gaat over de zoekopdracht, niet over het scherm, dus hoort het hier.
  static int gen = 0;

  /// Een nieuwe zoekopdracht: geef het volgnummer terug waarmee zijn uitkomsten getoetst worden.
  static int nieuweRonde() => ++gen;

  /// Hoort een uitkomst met dit volgnummer nog bij de laatste vraag?
  static bool geldig(int ronde) => ronde == gen;

  /// Alles terug naar leeg. Alleen voor toetsen — de app doet dit nooit, want een leeg geheugen is
  /// precies wat er niet moet gebeuren.
  static void wis() {
    tab = ZoekTab.bladeren;
    vraag = '';
    artiesten = const [];
    albums = const [];
    nummers = const [];
    nummerOpen = null;
    torrents = const [];
    slsk = const [];
    getypt = null;
    gezochtDirect = null;
    status = null;
    filter = QFilter.all;
    slskOpen.clear();
    slskDicht.clear();
    tidalNummers = const [];
    tidalAlbums = const [];
    tidalNummerOpen = null;
    tidalAlbumOpen = null;
    gen = 0;
  }
}
