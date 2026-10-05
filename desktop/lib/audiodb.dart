/// TheAudioDB als bron die je zelf kiest: in "Metadata corrigeren" en in "Uitgave kiezen".
///
/// **Gevraagd op 04-10-2026.** Saber, bij *Brave* van Jennifer Lopez: *"waar is the audiodb
/// eigenlijk ?? ik wil daar ook alles kunnen selecteren voor de metadata. dit is ook een heel grote
/// database met hoge resolutie."* De app gebruikte TheAudioDB al jaren, maar alleen op de
/// achtergrond (artiestbeelden, biografieën, achterkant en cd-scan op de albumpagina — zie
/// `enrichment.dart`). Kiezen kon je er niets uit.
///
/// **Gemeten die dag, met de gratis sleutel:**
///   * de hoes (`strAlbumThumb`) is 700×700; de HQ-hoes (`strAlbumThumbHQ`) 2160×2160 — die is er
///     niet altijd: *Play* en *Thriller* wel, *Brave* en *The Truth About Love* niet;
///   * de achterkant (`strAlbumBack`) ~700 breed, de cd (`strAlbumCDart`) 1000×1000, doorzichtig;
///   * `/small` achter een beeldadres geeft 240 (480 bij een HQ-hoes) — genoeg voor een rij;
///   * `track.php?m=` gaf met de gratis sleutel **één** nummer van de veertien. Een tracklijst van
///     hier kan dus alleen met een eigen (premium) sleutel, en zonder zegt dit dat ook.
///
/// TheAudioDB kent geen persingen: één album is één regel, geen cd uit Duitsland naast een vinyl uit
/// Japan. Daarom zet een keuze van hier ook geen persing vast — zie [AudioDbAlbum.keuze].
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'editions.dart';
import 'enrichment.dart' show CoverEnricher;
import 'settings.dart';

/// De gratis, openbare sleutel van TheAudioDB. Geen geheim: hij staat in hun eigen documentatie.
const kAudioDbGratis = '123';

/// Een fout van TheAudioDB die je kunt lezen — en die nooit het adres bevat.
///
/// Bij v1 zit de sleutel IN het adres (`/api/v1/json/<sleutel>/…`); zo heeft TheAudioDB het
/// ontworpen, er is geen kopregel voor. Een `ClientException` van het http-pakket zet het adres in
/// zijn tekst, en die tekst belandt in een melding of een logboek. Daarom wordt elke fout hier
/// omgezet naar dit, zonder adres.
class AudioDbFout implements Exception {
  const AudioDbFout(this.uitleg);
  final String uitleg;
  @override
  String toString() => uitleg;
}

/// Een bron die wel antwoordt maar dit niet geeft zonder eigen sleutel. Geen storing: opnieuw
/// proberen helpt niet, een sleutel invullen wel.
class AudioDbSleutelNodig implements Exception {
  const AudioDbSleutelNodig(this.uitleg);
  final String uitleg;
  @override
  String toString() => uitleg;
}

/// Eén album zoals TheAudioDB het kent.
class AudioDbAlbum {
  const AudioDbAlbum({
    required this.id,
    required this.artiest,
    required this.titel,
    this.jaar,
    this.label = '',
    this.formaat = '',
    this.genre = '',
    this.hoes,
    this.hoesHQ,
    this.achter,
    this.cd,
    this.rug,
    this.doos3d,
    this.plat3d,
    this.voor3d,
    this.duim3d,
  });

  final String id, artiest, titel, label, formaat, genre;
  final int? jaar;
  final String? hoes, hoesHQ, achter, cd, rug, doos3d, plat3d, voor3d, duim3d;

  /// De scherpste hoes die er is.
  String? get besteHoes => hoesHQ ?? hoes;

  /// Een klein voorbeeld voor een rij: TheAudioDB maakt het zelf als je `/small` achter het adres zet.
  static String klein(String url) => '$url/small';

  static String? _tekst(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty || s.toLowerCase() == 'null' ? null : s;
  }

  static AudioDbAlbum? vanJson(Map j) {
    final id = _tekst(j['idAlbum']);
    final titel = _tekst(j['strAlbum']);
    if (id == null || titel == null) return null;
    return AudioDbAlbum(
      id: id,
      artiest: _tekst(j['strArtist']) ?? '',
      titel: titel,
      jaar: int.tryParse(_tekst(j['intYearReleased']) ?? ''),
      label: _tekst(j['strLabel']) ?? '',
      formaat: _tekst(j['strReleaseFormat']) ?? '',
      genre: _tekst(j['strGenre']) ?? '',
      hoes: _tekst(j['strAlbumThumb']),
      hoesHQ: _tekst(j['strAlbumThumbHQ']),
      achter: _tekst(j['strAlbumBack']) ?? _tekst(j['strAlbumThumbBack']),
      cd: _tekst(j['strAlbumCDart']),
      rug: _tekst(j['strAlbumSpine']),
      doos3d: _tekst(j['strAlbum3DCase']),
      plat3d: _tekst(j['strAlbum3DFlat']),
      voor3d: _tekst(j['strAlbum3DFace']),
      duim3d: _tekst(j['strAlbum3DThumb']),
    );
  }

  /// "Album · 2007 · Epic" — wat dit album IS, op één regel.
  String get regel => [
        if (formaat.isNotEmpty) formaat,
        if (jaar != null && jaar! > 0) '$jaar',
        if (label.isNotEmpty) label,
      ].join(' · ');

  static ChoiceImage _beeld(String url) => ChoiceImage(url, klein(url));

  /// Als rij in "Uitgave kiezen". Volledig ([ReleaseChoice.detailed]): alles wat TheAudioDB weet,
  /// staat al in het ene antwoord, er valt niets na te zoeken.
  ///
  /// Geen [ReleaseChoice.releaseId] en geen [ReleaseChoice.mbid]. TheAudioDB geeft wel een
  /// MusicBrainz-nummer mee, maar dat is van de releasegroep — het ALBUM — en niet van een persing;
  /// het als persing vastzetten zou de albumpagina laten beweren dat je een cd hebt die niemand
  /// heeft aangewezen.
  ReleaseChoice keuze() => ReleaseChoice(
        source: EditionSource.audiodb,
        audioDbId: id,
        format: formaat,
        label: label.isEmpty ? null : label,
        year: jaar,
        front: besteHoes == null ? null : _beeld(besteHoes!),
        back: achter == null ? null : _beeld(achter!),
        disc: cd == null ? null : _beeld(cd!),
      );

  /// Alle scans, voor "Alle scans van deze uitgave". Ook de gewone hoes naast de HQ: soms is de HQ
  /// een andere scan, en kiezen hoort bij jou.
  List<ChoiceImage> get alleScans => [
        for (final u in [hoesHQ, hoes, achter, cd, rug, doos3d, plat3d, voor3d, duim3d])
          if (u != null) _beeld(u),
      ];
}

/// Praat met TheAudioDB. Met [AppSettings.audiodbKey] als die er is, anders met de gratis sleutel.
class AudioDbService {
  AudioDbService(this.settings, {this.client});

  final AppSettings settings;
  final http.Client? client;

  static const _basis = 'https://www.theaudiodb.com/api';
  static const _ua = 'DebridMusic/0.1 ( https://github.com/sabair24/Debrid-music-app )';

  String get _sleutel => settings.audiodbKey.trim();

  /// Staat er een eigen sleutel? Dan komt de volle tracklijst mee, en mag er meer per minuut.
  bool get premium => _sleutel.isNotEmpty;

  /// Wie hier vraagt, staat te wachten — dus niet achter de rij van de achtergrond.
  ///
  /// `enrichment.dart` haalt op de achtergrond honderden albums op, drie seconden uit elkaar. Een
  /// zoekopdracht uit een venster daarachter zetten betekent minuten wachten. Wel MELDT dit zich bij
  /// die rij ([vraagGedaan]), zodat de achtergrond erna weer drie seconden afstand houdt.
  static void Function() vraagGedaan = CoverEnricher.meldAudioDbVraag;

  Future<Map<String, dynamic>> _v1(String pad) async {
    vraagGedaan();
    final sleutel = premium ? _sleutel : kAudioDbGratis;
    final u = Uri.parse('$_basis/v1/json/$sleutel/$pad');
    http.Response r;
    try {
      r = await (client == null ? http.get(u, headers: {'User-Agent': _ua}) : client!.get(u, headers: {'User-Agent': _ua}))
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const AudioDbFout('TheAudioDB antwoordde niet op tijd.');
    } catch (_) {
      // Bewust zonder de oorspronkelijke tekst: die bevat het adres, en daarmee je sleutel.
      throw const AudioDbFout('Geen verbinding met TheAudioDB.');
    }
    if (r.statusCode == 429) throw const AudioDbFout('TheAudioDB: te veel vragen — wacht een minuut.');
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw const AudioDbFout('TheAudioDB weigerde de sleutel — kijk hem na in Instellingen.');
    }
    if (r.statusCode != 200) throw AudioDbFout('TheAudioDB gaf ${r.statusCode}.');
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? j : const {};
    } catch (_) {
      throw const AudioDbFout('TheAudioDB gaf een onleesbaar antwoord.');
    }
  }

  static List<Map> _lijst(Map<String, dynamic> j, String naam) =>
      [for (final x in (j[naam] as List?) ?? const []) if (x is Map) x];

  /// De albums van [artiest] die [album] heten.
  ///
  /// Allebei nodig: zonder artiest geeft TheAudioDB niets terug (`searchalbum.php?a=Brave` was leeg),
  /// en met alleen de artiest geeft de gratis sleutel er één.
  Future<List<AudioDbAlbum>> zoek(String artiest, String album) async {
    final wie = artiest.trim(), wat = album.trim();
    if (wie.isEmpty || wat.isEmpty) return const [];
    final j = await _v1('searchalbum.php?s=${Uri.encodeQueryComponent(wie)}&a=${Uri.encodeQueryComponent(wat)}');
    return [
      for (final m in _lijst(j, 'album'))
        if (AudioDbAlbum.vanJson(m) case final a?) a,
    ];
  }

  /// Eén album op zijn nummer.
  Future<AudioDbAlbum?> album(String id) async {
    final j = await _v1('album.php?m=${Uri.encodeQueryComponent(id)}');
    final l = _lijst(j, 'album');
    return l.isEmpty ? null : AudioDbAlbum.vanJson(l.first);
  }

  /// De nummers van album [id], in volgorde, per schijf.
  ///
  /// Alleen met een eigen sleutel: de gratis gaf er één van de veertien (gemeten op *Brave*), en een
  /// tracklijst van één nummer is erger dan geen — hij laat de rest van je plaat onder "Niet op deze
  /// uitgave" vallen.
  Future<List<ChoiceTrack>> nummers(String id) async {
    if (!premium) {
      throw const AudioDbSleutelNodig(
          'TheAudioDB geeft de volle tracklijst alleen met je eigen sleutel — vul hem in bij Instellingen.');
    }
    final j = await _v1('track.php?m=${Uri.encodeQueryComponent(id)}');
    final rijen = <({int cd, int nr, ChoiceTrack t})>[];
    for (final m in _lijst(j, 'track')) {
      final titel = AudioDbAlbum._tekst(m['strTrack']);
      if (titel == null) continue;
      final cd = int.tryParse(AudioDbAlbum._tekst(m['intCD']) ?? '') ?? 1;
      final nr = int.tryParse(AudioDbAlbum._tekst(m['intTrackNumber']) ?? '') ?? (rijen.length + 1);
      // In milliseconden. 210026 is "Stay Together", 3:30.
      final ms = int.tryParse(AudioDbAlbum._tekst(m['intDuration']) ?? '');
      rijen.add((
        cd: cd < 1 ? 1 : cd,
        nr: nr,
        t: ChoiceTrack('', titel, ms == null || ms <= 0 ? null : (ms / 1000).round(),
            disc: cd < 1 ? 1 : cd, artist: AudioDbAlbum._tekst(m['strArtist']) ?? ''),
      ));
    }
    rijen.sort((a, b) => a.cd != b.cd ? a.cd.compareTo(b.cd) : a.nr.compareTo(b.nr));
    final meer = rijen.any((r) => r.cd > 1);
    return [
      for (final r in rijen)
        ChoiceTrack(meer ? '${r.cd}-${r.nr}' : '${r.nr}', r.t.title, r.t.seconds,
            disc: r.cd, artist: r.t.artist),
    ];
  }

  /// Een beeld van TheAudioDB. Zonder sleutel en zonder token: de beeldserver vraagt er niet om, en
  /// een andere dienst zijn sleutel hier meesturen is een lek — zie [scanBronVan].
  Future<Uint8List?> beeld(String url) async {
    try {
      final u = Uri.parse(url);
      final r = await (client == null ? http.get(u, headers: {'User-Agent': _ua}) : client!.get(u, headers: {'User-Agent': _ua}))
          .timeout(const Duration(seconds: 20));
      return r.statusCode == 200 && r.bodyBytes.length > 500 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  /// Werkt de eigen sleutel? Via v2, waar hij in een KOPREGEL gaat en dus nergens in een adres.
  /// 200 is ja; TheAudioDB zegt "Invalid Premium API key" met een 400 als het nee is.
  Future<bool> sleutelWerkt() async {
    if (!premium) return false;
    final u = Uri.parse('$_basis/v2/json/lookup/artist/111239');
    final kop = {'User-Agent': _ua, 'X-API-KEY': _sleutel};
    try {
      final r = await (client == null ? http.get(u, headers: kop) : client!.get(u, headers: kop))
          .timeout(const Duration(seconds: 15));
      return r.statusCode == 200;
    } catch (_) {
      throw const AudioDbFout('Geen verbinding met TheAudioDB.');
    }
  }
}
