import 'package:http/http.dart' as http;
import 'json_body.dart';

/// One torrent hit (from a search source), reused through the TorBox resolve flow.
class SearchResult {
  final String name;
  final int size;
  final int seeders;
  final int leechers;
  final String magnet;
  final String hash;
  final String source;
  bool cached;

  /// Waar het `.torrent`-BESTAND te halen is, als de bron dat heeft. Leeg bij de meeste.
  ///
  /// **Waarom dit erbij moest.** Een magneet draagt alleen de infohash; wie hem oppakt moet de
  /// zwerm zelf zien te vinden via DHT. Bij een tracker als RuTracker zit die zwerm achter hún
  /// announce, en dan vindt DHT niemand. Gemeten op 23-08-2026 met dezelfde plaat (Kai Tracid,
  /// Liquid Skies, 24/96):
  ///
  ///     als magneet   : 2,5 uur "checking", size -1, seeds 0  -> nooit iets
  ///     als .torrent  : binnen 12 s "downloading", 554 MB, seeds 1, 4% -> 61% in twee minuten
  ///
  /// Het verschil is de `announce` die in het bestand staat en in de magneet niet.
  final String torrentUrl;

  SearchResult({
    required this.name,
    this.size = 0,
    this.seeders = 0,
    this.leechers = 0,
    required this.magnet,
    required this.hash,
    this.source = '',
    this.cached = false,
    this.torrentUrl = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name, 'size': size, 'seeders': seeders, 'leechers': leechers,
        'magnet': magnet, 'hash': hash, 'source': source, 'cached': cached,
        'torrentUrl': torrentUrl,
      };

  /// The way back in, for a Mac or an iPad reading results the PC found. Beside [toJson] on
  /// purpose: a field added to one and forgotten in the other is a result that silently loses
  /// its magnet.
  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        name: (j['name'] ?? '') as String,
        size: (j['size'] as num?)?.toInt() ?? 0,
        seeders: (j['seeders'] as num?)?.toInt() ?? 0,
        leechers: (j['leechers'] as num?)?.toInt() ?? 0,
        magnet: (j['magnet'] ?? '') as String,
        hash: (j['hash'] ?? '') as String,
        source: (j['source'] ?? '') as String,
        cached: j['cached'] == true,
        torrentUrl: (j['torrentUrl'] ?? '') as String,
      );
}

class TbFile {
  final int id;
  final String name;
  final String? shortName;
  final int size;
  final String? mimeType;
  TbFile(this.id, this.name, this.shortName, this.size, this.mimeType);

  factory TbFile.fromJson(Map<String, dynamic> j) => TbFile(
        (j['id'] ?? 0) as int,
        (j['name'] ?? '') as String,
        j['short_name'] as String?,
        (j['size'] ?? 0) as int,
        j['mime_type'] as String?,
      );

  String get _ext {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  bool get isAudio =>
      (mimeType?.startsWith('audio/') ?? false) ||
      const {'flac', 'mp3', 'm4a', 'aac', 'ogg', 'opus', 'wav', 'alac', 'ape', 'wv'}.contains(_ext);
  bool get isFlac => (mimeType?.contains('flac') ?? false) || name.toLowerCase().endsWith('.flac');
  String get label => shortName ?? name;
}

class TbTorrent {
  final int id;
  final String name;
  final String? hash;
  final String status;
  final double progress;
  final List<TbFile> files;
  final bool downloadFinished;
  final bool cached;

  /// Hoe groot TorBox denkt dat de torrent is. **-1 betekent: hij weet het nog niet** — de metadata
  /// is nog niet binnen, dus er is nog niet eens een bestandslijst.
  final int size;

  /// Hoeveel seeders TorBox ziet. Nul plus geen metadata is het beeld van een torrent die nergens
  /// meer te vinden is.
  final int seeds;

  TbTorrent(this.id, this.name, this.hash, this.status, this.progress, this.files,
      this.downloadFinished, this.cached,
      {this.size = 0, this.seeds = 0});

  factory TbTorrent.fromJson(Map<String, dynamic> j) => TbTorrent(
        (j['id'] ?? 0) as int,
        (j['name'] ?? '') as String,
        j['hash'] as String?,
        (j['status'] ?? '') as String,
        ((j['progress'] ?? 0) as num).toDouble(),
        ((j['files'] as List?) ?? const []).map((f) => TbFile.fromJson(f as Map<String, dynamic>)).toList(),
        (j['download_finished'] ?? false) as bool,
        (j['cached'] ?? false) as bool,
        size: ((j['size'] ?? 0) as num).toInt(),
        seeds: ((j['seeds'] ?? 0) as num).toInt(),
      );

  bool get isReady => status == 'completed' || cached || downloadFinished;
  bool get isFailed => status == 'error' || status == 'stalled';

  /// Niemand heeft deze torrent, en TorBox weet niet eens hoe groot hij is.
  ///
  /// **Waarom dit apart staat.** Gemeten op 23-08-2026 met een RuTracker-vondst (Kai Tracid,
  /// Liquid Skies, 1998): tweeënhalf uur na het toevoegen stond hij nog op `checking`, `size: -1`,
  /// `seeds: 0`, `peers: 2`. Zo'n torrent komt niet meer los — het is geen trage download, er is
  /// niets om van te downloaden. Toch bleef de app "Voorbereiden" melden, en bij elke herstart begon
  /// dat wachten opnieuw. Beter meteen zeggen wat er aan de hand is.
  bool get geenBron => size <= 0 && seeds <= 0 && !isReady;
  List<TbFile> get audio => files.where((f) => f.isAudio).toList();
}

/// Thin TorBox API client. The key is read per-call so settings changes take effect live.
class TorBox {
  final String Function() apiKey;
  TorBox(this.apiKey);
  static const _base = 'https://api.torbox.app/v1/api';

  bool get hasKey => apiKey().trim().isNotEmpty;
  Map<String, String> get _auth => hasKey ? {'Authorization': 'Bearer ${apiKey()}'} : {};

  /// Confirm the API key is valid (used by the connection-status check).
  Future<bool> verify() async {
    if (!hasKey) return false;
    try {
      final r = await http
          .get(Uri.parse('$_base/user/me?settings=false'), headers: _auth)
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return false;
      final j = jsonBody(r);
      return j is Map && (j['success'] == true || j['data'] != null);
    } catch (_) {
      return false;
    }
  }

  Future<Set<String>> checkCached(List<String> hashes) async {
    if (hashes.isEmpty || !hasKey) return {};
    try {
      final q = Uri.encodeComponent(hashes.join(','));
      final r = await http
          .get(Uri.parse('$_base/torrents/checkcached?hash=$q&format=list&list_files=false'), headers: _auth)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return {};
      final data = (jsonBody(r)['data'] as List?) ?? const [];
      return data.map((e) => (e['hash'] as String?)?.toLowerCase()).whereType<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  /// Returns (success, torrentId?, hash?, detail).
  Future<(bool, int?, String?, String)> addMagnet(String magnet) async {
    try {
      final r = await http
          .post(Uri.parse('$_base/torrents/createtorrent'), headers: _auth, body: {'magnet': magnet})
          .timeout(const Duration(seconds: 15));
      final j = jsonBody(r) as Map<String, dynamic>;
      final data = j['data'] as Map<String, dynamic>?;
      final detail = (j['detail'] ?? j['error'] ?? '').toString();
      final id = (data?['torrent_id'] as int?);
      return ((j['success'] ?? false) as bool, (id != null && id > 0) ? id : null, data?['hash'] as String?, detail);
    } catch (e) {
      return (false, null, null, e.toString());
    }
  }

  /// Een `.torrent`-BESTAND aanmelden in plaats van een magneet.
  ///
  /// Dat maakt het verschil bij een tracker die zijn zwerm niet in DHT heeft staan: het bestand
  /// draagt de `announce`, de magneet niet. Zie [SearchResult.torrentUrl] voor de meting.
  ///
  /// **Let op de dubbelentrap.** TorBox kijkt naar de infohash: staat er al een (vastgelopen)
  /// poging met dezelfde hash, dan antwoordt hij "Found Cached Torrent" en krijg je die oude terug,
  /// bestand of niet. Vandaar dat de app het bestand meteen als eerste aanbiedt en niet pas nadat
  /// een magneet is blijven hangen.
  Future<(bool, int?, String?, String)> addTorrentFile(List<int> bytes, String naam) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$_base/torrents/createtorrent'))
        ..headers.addAll(_auth)
        ..files.add(http.MultipartFile.fromBytes('file', bytes,
            filename: naam.isEmpty ? 'bron.torrent' : naam));
      final streamed = await req.send().timeout(const Duration(seconds: 45));
      final r = await http.Response.fromStream(streamed);
      final j = jsonBody(r) as Map<String, dynamic>;
      final data = j['data'] as Map<String, dynamic>?;
      final detail = (j['detail'] ?? j['error'] ?? '').toString();
      final id = (data?['torrent_id'] as int?);
      return (
        (j['success'] ?? false) as bool,
        (id != null && id > 0) ? id : null,
        data?['hash'] as String?,
        detail
      );
    } catch (e) {
      return (false, null, null, e.toString());
    }
  }

  Future<List<TbTorrent>> listTorrents() async {
    try {
      final r = await http
          .get(Uri.parse('$_base/torrents/mylist?bypass_cache=true'), headers: _auth)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return [];
      final data = (jsonBody(r)['data'] as List?) ?? const [];
      return data.map((e) => TbTorrent.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> requestDownload(int torrentId, int fileId) async {
    if (!hasKey) return null;
    try {
      final tok = Uri.encodeComponent(apiKey());
      final r = await http.get(
        Uri.parse('$_base/torrents/requestdl?token=$tok&torrent_id=$torrentId&file_id=$fileId&zip_link=false'),
        headers: _auth,
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final url = jsonBody(r)['data'] as String?;
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }
}
