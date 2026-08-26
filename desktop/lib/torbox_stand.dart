/// Wat TorBox aan het doen is, in één zin die waar is.
///
/// **Waarom dit bestaat.** In het nummerkeuzevenster stond een vaste regel:
///
/// > Niet-gecachte torrents met weinig seeders kunnen even duren.
///
/// Die stond er altijd, ongeacht wat er gebeurde. Gemeld op een torrent met **veertig** seeders —
/// dan zegt het scherm dus iets dat aantoonbaar onwaar is, en ga je de vertraging zoeken waar hij
/// niet zit.
///
/// Het pijnlijke is dat de waarheid er allang was. `_pollReady` in `online.dart` krijgt bij elke
/// peiling de stand van TorBox binnen — status, voortgang, aantal seeders, grootte — en gaf die ook
/// door. Het venster gooide alles behalve het percentage weg en zette er een gok voor in de plaats.
///
/// **Wat er echt speelt bij een torrent die niet gecacht is.** Dan moet TorBox het bestand éérst
/// zelf helemaal binnenhalen, en pas daarna begint jouw download. Dat wachten staat los van jouw
/// verbinding, en ook los van het seedersgetal in de zoeklijst: dat komt uit de index van de
/// tracker en zegt niets over wat TorBox op dit moment kan bereiken.
///
/// Zuiver, dus toetsbaar zonder toestel en zonder TorBox.
library;

/// De statuswoorden die TorBox teruggeeft, in gewone taal.
///
/// Alleen de woorden die er echt uitkomen; wat er niet in staat wordt letterlijk getoond in plaats
/// van vertaald naar iets dat misschien niet klopt.
const _statusWoorden = <String, String>{
  'downloading': 'TorBox haalt hem binnen',
  'metadl': 'TorBox zoekt de bestandslijst op',
  'checking': 'TorBox controleert wat hij heeft',
  'checkingresumedata': 'TorBox controleert wat hij heeft',
  'queued': 'TorBox heeft hem in de wachtrij gezet',
  'paused': 'TorBox heeft hem gepauzeerd',
  'uploading': 'TorBox heeft hem binnen',
  'completed': 'TorBox heeft hem binnen',
  'cached': 'TorBox had hem al klaarstaan',
  'stalleddl': 'TorBox vindt niemand om van te halen',
  'stalled': 'TorBox vindt niemand om van te halen',
  'toevoegen': 'Bezig met toevoegen bij TorBox',
};

/// Eén zin over wat er nu gebeurt.
///
/// [deel] loopt van 0 tot 1. [grootte] is -1 of 0 zolang TorBox de metadata nog niet heeft; dat is
/// een echt onderscheid en geen randgeval, want zonder metadata is er niet eens een bestandslijst.
String torboxStand({
  required bool gecacht,
  required double deel,
  required String status,
  required int seeds,
  required int grootte,
}) {
  final woord = _statusWoorden[status.trim().toLowerCase()];
  final kop = woord ?? (status.trim().isEmpty ? 'Bezig bij TorBox' : 'TorBox: ${status.trim()}');

  if (gecacht) return 'TorBox had deze al klaarstaan.';

  // Geen grootte én geen seeders: er is niets om van te halen. Dat is geen trage download maar een
  // dode zwerm, en dat hoort meteen gezegd te worden in plaats van na een half uur wachten.
  if (grootte <= 0 && seeds <= 0 && deel <= 0) {
    return '$kop — nog geen enkele seeder, en de grootte is nog onbekend. '
        'Het getal in de zoeklijst komt uit de index van de tracker en zegt niet of TorBox erbij kan.';
  }

  final erbij = <String>[];
  if (deel > 0) erbij.add('${(deel * 100).round()}%');
  if (seeds > 0) erbij.add('$seeds ${seeds == 1 ? 'seeder' : 'seeders'}');
  final staart = erbij.isEmpty ? '' : ' — ${erbij.join(' · ')}';
  return '$kop$staart.';
}

/// De regel eronder: waaróm je hierop staat te wachten.
///
/// Alleen bij een torrent die niet gecacht is, want alleen dan is er iets uit te leggen. Nooit meer
/// een uitspraak over het aantal seeders die niet gemeten is.
String torboxWaarom({required bool gecacht}) => gecacht
    ? ''
    : 'Deze staat niet in de cache van TorBox. Hij haalt het bestand eerst helemaal zelf binnen; '
        'pas daarna begint jouw download.';

/// De publieke announce-adressen die aan een magneet zonder trackers gehangen worden.
///
/// **Waarom dit helpt.** Een magneet draagt alleen de infohash. Wie hem oppakt moet de zwerm via
/// DHT zien te vinden, en dat lukt lang niet altijd — zeker niet als die zwerm bij de announce van
/// een tracker hangt. Dat verschil is in deze app al gemeten en staat bij `SearchResult.torrentUrl`:
/// dezelfde plaat als magneet gaf na tweeënhalf uur nog "checking" met nul seeds, als `.torrent`
/// binnen twaalf seconden 4% en na twee minuten 61%.
///
/// Voor een publieke torrent is dit precies het ontbrekende stuk: geen geheim adres, maar de open
/// trackers die vrijwel elke client standaard meestuurt.
const kOpenTrackers = <String>[
  'udp://tracker.opentrackr.org:1337/announce',
  'udp://open.demonii.com:1337/announce',
  'udp://tracker.openbittorrent.com:6969/announce',
  'udp://exodus.desync.com:6969/announce',
  'udp://tracker.torrent.eu.org:451/announce',
];

/// Hang open announce-adressen aan een magneet die er geen heeft.
///
/// Heeft hij er al, dan blijft hij zoals hij is: de trackers van de bron zelf weten beter waar die
/// zwerm zit dan een algemene lijst, en er iets bij plakken kan die volgorde alleen maar verstoren.
/// Is het geen magneet, dan gebeurt er niets.
String magneetMetAnnounce(String magnet) {
  final m = magnet.trim();
  if (!m.startsWith('magnet:?')) return magnet;
  if (m.contains('&tr=') || m.contains('?tr=')) return magnet;
  final staart = kOpenTrackers.map((t) => '&tr=${Uri.encodeComponent(t)}').join();
  return '$m$staart';
}
