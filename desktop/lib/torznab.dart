/// Je eigen indexers, via Torznab (Jackett of Prowlarr).
///
/// **Waarom dit bestaat.** De bronnen in deze app staan vast in de code: PirateBay, BitSearch,
/// Knaben, RuTracker. Valt er een om — en dat gebeurt met trackers om de paar maanden — dan is er
/// een nieuwe bouw nodig om hem te vervangen. Dat is de verkeerde volgorde: jij merkt het, en jij
/// moet wachten tot iemand anders iets doet.
///
/// Torznab is de standaard die Jackett en Prowlarr spreken. Zo'n programma draait op je eigen pc, jij
/// zet er de indexers in die op dát moment werken, en deze app praat met één adres. Valt er een site
/// om, dan vervang je hem daar. Er komt geen bouw meer aan te pas.
///
/// **Wat er terugkomt.** Torznab is RSS met een eigen naamruimte erin:
///
/// ```xml
/// <item>
///   <title>P!nk - Beautiful Trauma (2017) FLAC 24-96</title>
///   <size>1148903424</size>
///   <enclosure url="magnet:?xt=urn:btih:abc…" type="application/x-bittorrent" />
///   <torznab:attr name="seeders" value="47" />
///   <torznab:attr name="infohash" value="abc…" />
/// </item>
/// ```
///
/// Niet elke indexer vult hetzelfde in — de een geeft een magneet, de ander alleen een infohash, de
/// derde een link naar een `.torrent`. Daarom wordt hier alles geprobeerd en telt wat er is.
///
/// Het uitpluizen staat met opzet los van het ophalen: dat is het stuk dat stil fout kan gaan, en
/// zo is het te toetsen zonder Jackett en zonder net.
library;

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'search.dart';
import 'settings.dart';
import 'torbox.dart';

/// De categorie voor geluid in de Torznab-indeling. 3000 is Audio; 3010 lossless, 3040 los nummer.
///
/// **Niet meer meegestuurd aan Jackett, en dat is een meting waard.** Gevraagd naar "Robert Miles
/// Dreamland" op 24-08-2026, met acht indexers ingesteld:
///
///     met cat=3000 : 22 treffers — LimeTorrents 10, Pirate Bay 7, Knaben 5
///     zonder cat   : 49 treffers — daarbij RuTor 8 en Byrutor 12
///
/// RuTor levert precies waar het om gaat (Dreamland FLAC, WavPack, MP3) maar zet dat onder
/// categorie **8000, "Overig"**. Wie op 3000 filtert gooit die tracker dus in zijn geheel weg — en
/// laat daarmee juist de bron liggen die het meest oplevert. Byrutor, aan de andere kant, gaf
/// twaalf GAMES terug ("Dreamland Farm", categorie 4050).
///
/// Vandaar: alles ophalen, en hier beslissen met [torznabIsMuziek]. De categorie telt waar hij iets
/// zegt, en de titel beslist waar de indexer "overig" zegt.
const kTorznabAudio = '3000';

/// Categorieën waarvan we zeker weten dat het geen muziek is: film, pc/games, tv, xxx, boeken.
const _nietMuziek = [2000, 4000, 5000, 6000, 7000];

/// Woorden die van een titel een plaat maken. Bewust over de vorm en niet over het genre: een
/// indexer die "overig" zegt vertelt in zijn titel altijd wél in welk formaat het staat.
final _muziekWoorden = RegExp(
    r'\b(flac|mp3|m4a|aac|alac|ape|wav|wavpack|ogg|opus|dsd|dsf|dff|lossless|'
    r'\d{3}\s*kbps|320|v0|24\s*bit|16\s*bit|vinyl|discography|дискография)\b',
    caseSensitive: false);

/// Is dit een muziektreffer?
///
/// [categorieen] zijn de Torznab-categorieën van het item (de eigen nummers van een indexer, die
/// boven de 100000 liggen, tellen niet mee). [titel] beslist alleen waar de categorie zwijgt.
///
/// Zuiver en apart omdat dit de zeef is die bepaalt wat je wél en niet te zien krijgt — en een zeef
/// die te fijn staat is precies waarom RuTor eerst helemaal ontbrak.
bool torznabIsMuziek(Iterable<int> categorieen, String titel) {
  final echte = categorieen.where((c) => c > 0 && c < 100000).toList();
  if (echte.any((c) => c >= 3000 && c < 4000)) return true;
  if (echte.any((c) => _nietMuziek.any((n) => c >= n && c < n + 1000))) return false;
  // Niets bruikbaars gezegd (8000 "overig", of helemaal geen categorie): dan de titel.
  return _muziekWoorden.hasMatch(titel);
}

/// Een infohash is veertig tekens hex (of tweeëndertig in base32).
final _hex40 = RegExp(r'^[0-9a-fA-F]{40}$');
final _urnHash = RegExp(r'urn:btih:([0-9a-fA-F]{40})', caseSensitive: false);

/// Het adres waar de zoekopdracht heen gaat.
///
/// Apart, want hier gaat het mis op manieren die je niet ziet: een schuine streep te veel, een pad
/// dat de gebruiker er zelf al bij typte, of een sleutel die niet meegaat.
///
/// Jackett heeft één adres dat álle indexers tegelijk bevraagt die je erin gezet hebt — `all`. Dat
/// is precies wat hier nodig is: één bron in de app, zoveel trackers erachter als jij wil.
Uri torznabZoekAdres(String basis, String sleutel, String vraag) {
  var b = basis.trim();
  if (b.isEmpty) return Uri();
  if (!b.startsWith('http://') && !b.startsWith('https://')) b = 'http://$b';
  // Wat de gebruiker er zelf al bij plakte weghalen: mensen kopiëren het hele adres uit Jackett,
  // inclusief pad en sleutel. Twee keer een pad geeft een 404 en verder geen enkele aanwijzing.
  b = b.replaceFirst(RegExp(r'/+$'), '');
  final knip = b.indexOf('/api/');
  if (knip > 0) b = b.substring(0, knip);
  // Zonder `cat`: zie [kTorznabAudio] voor de meting. Het zeven gebeurt hier, niet bij Jackett,
  // want een indexer die zijn muziek onder "overig" zet valt daar anders volledig weg.
  return Uri.parse('$b/api/v2.0/indexers/all/results/torznab/api').replace(queryParameters: {
    'apikey': sleutel.trim(),
    't': 'search',
    'q': vraag,
  });
}

/// De `<item>`-lijst uit een Torznab-antwoord naar treffers.
///
/// Zuiver: tekst in, treffers uit. Geen net, geen Jackett — en daarmee te toetsen op een opgeslagen
/// antwoord, wat het enige is dat hier vóór het uitgeven na te meten valt.
List<SearchResult> leesTorznab(String xml, {String bron = 'Torznab'}) {
  final uit = <SearchResult>[];
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException {
    return uit;
  }

  for (final item in doc.findAllElements('item')) {
    String tekstVan(String naam) {
      for (final e in item.childElements) {
        if (e.name.local == naam) return e.innerText.trim();
      }
      return '';
    }

    /// De eigen velden van Torznab staan als `<torznab:attr name="…" value="…"/>`.
    String attr(String naam) {
      for (final e in item.childElements) {
        if (e.name.local != 'attr') continue;
        if (e.getAttribute('name')?.toLowerCase() == naam) {
          return e.getAttribute('value')?.trim() ?? '';
        }
      }
      return '';
    }

    final titel = tekstVan('title');
    if (titel.isEmpty) continue;

    // De categorieën staan als losse `<torznab:attr name="category" …>`-regels; een item heeft er
    // meestal twee (de Torznab-categorie en het eigen nummer van de indexer).
    final categorieen = <int>[
      for (final e in item.childElements)
        if (e.name.local == 'attr' && e.getAttribute('name')?.toLowerCase() == 'category')
          int.tryParse(e.getAttribute('value')?.trim() ?? '') ?? 0,
    ];
    if (!torznabIsMuziek(categorieen, titel)) continue;

    // De magneet kan op drie plekken staan, afhankelijk van de indexer.
    var magneet = attr('magneturl');
    if (magneet.isEmpty) {
      for (final e in item.childElements) {
        if (e.name.local != 'enclosure') continue;
        final u = e.getAttribute('url') ?? '';
        if (u.startsWith('magnet:')) magneet = u;
      }
    }
    if (magneet.isEmpty) {
      final link = tekstVan('link');
      if (link.startsWith('magnet:')) magneet = link;
    }

    // En de infohash: als eigen veld, of anders uit de magneet.
    var hash = attr('infohash').toLowerCase();
    if (!_hex40.hasMatch(hash)) {
      hash = _urnHash.firstMatch(magneet)?.group(1)?.toLowerCase() ?? '';
    }
    // Zonder infohash valt er niets op te halen: TorBox kent een torrent bij zijn hash, en de
    // zoekverdeler ontdubbelt erop. Een rij zonder hash is dus geen halve treffer maar geen treffer.
    if (!_hex40.hasMatch(hash)) continue;

    final grootte = int.tryParse(tekstVan('size')) ?? int.tryParse(attr('size')) ?? 0;
    final seeders = int.tryParse(attr('seeders')) ?? 0;
    final peers = int.tryParse(attr('peers')) ?? 0;

    uit.add(SearchResult(
      name: titel,
      size: grootte,
      seeders: seeders,
      // Torznab telt in `peers` alle deelnemers, seeders inbegrepen. Wie dat als leechers overneemt
      // laat een torrent met 40 seeders er drukker uitzien dan hij is.
      leechers: peers > seeders ? peers - seeders : 0,
      hash: hash,
      // Ook hier de openbare trackers erbij als de indexer er zelf geen meegaf: een magneet met
      // alleen een infohash moet zijn zwerm via DHT zien te vinden, en dat is precies waar het bij
      // Knaben en Pirate Bay op stukliep.
      magnet: metTrackers(magneet.isNotEmpty
          ? magneet
          : 'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(titel)}'),
      source: bron,
    ));
  }
  return uit;
}

/// De bron zoals de zoekverdeler hem ziet.
///
/// Staat er geen adres in de instellingen, dan doet hij niets en zegt dat ook — zie [BronStand].
class TorznabSource implements SearchSource {
  TorznabSource(this.settings, {http.Client? client}) : _http = client ?? http.Client();

  final AppSettings settings;
  final http.Client _http;

  @override
  String get id => 'torznab';

  bool get ingesteld =>
      settings.torznabUrl.trim().isNotEmpty && settings.torznabKey.trim().isNotEmpty;

  @override
  Future<List<SearchResult>> search(String query) async {
    // Niet ingesteld is geen fout. Een lege lijst is hier het eerlijke antwoord; de bronnenregel op
    // het scherm laat zien dat hij nul gaf, en Instellingen zegt waarom.
    if (!ingesteld) return const [];
    final adres = torznabZoekAdres(settings.torznabUrl, settings.torznabKey, query);
    if (adres.toString().isEmpty) return const [];
    // Elf seconden: één onder de kap van twaalf die de zoekverdeler aanhoudt, zodat een trage
    // Jackett zijn eigen melding nog kan afleveren voordat de bron weggegooid wordt.
    final r = await _http.get(adres).timeout(const Duration(seconds: 11));
    if (r.statusCode != 200) {
      throw 'Jackett antwoordde met ${r.statusCode}'
          '${r.statusCode == 401 ? ' — klopt de API-sleutel?' : ''}';
    }
    return leesTorznab(r.body);
  }

  /// Eén keer proberen, voor de knop in Instellingen. Geeft de zin die op het scherm komt.
  Future<({bool ok, String reden})> proef() async {
    if (!ingesteld) {
      return (ok: false, reden: 'Vul eerst het adres en de API-sleutel in.');
    }
    try {
      final uit = await search('flac');
      return (
        ok: true,
        reden: uit.isEmpty
            ? 'Verbonden, maar deze proefzoekopdracht gaf niets. Staan er al indexers in Jackett?'
            : 'Verbonden — ${uit.length} treffers op een proefzoekopdracht.',
      );
    } on TimeoutException {
      return (ok: false, reden: 'Geen antwoord binnen elf seconden. Draait Jackett op dat adres?');
    } catch (e) {
      return (ok: false, reden: '$e');
    }
  }
}
