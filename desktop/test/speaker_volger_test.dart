/// Speakers van verschillende merken samen (Saber, 01-11-2026: de Nest Minis "in group met andere zones"; gekozen:
/// "via de app met Sonos/KEF/Shield/toestellen, ongeveer gelijk, met de schuif"). Sonossen onderling doen het zelf; een
/// ander merk speelt via de pc mee: hetzelfde nummer, het volgende klaargezet, pauze en verder mee, en bijgezet op de
/// plek van de leider (speaker_volger.dart).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/cast_manager.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/google_cast.dart';
import 'package:debridmusic/lan/speaker_volger.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/upnp.dart';
import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';

String _id(String url) => RegExp(r'/stream/([^/.?]+)').firstMatch(url)?.group(1) ?? url;

/// Een Sonos die opschrijft wat hij krijgt.
class _NepUpnp extends UpnpControlPoint {
  final opdrachten = <String>[];
  final uri = <String, String?>{};

  @override
  Future<List<Renderer>> discover({Duration timeout = const Duration(seconds: 3)}) async => const [];

  @override
  Future<void> playUrl(Renderer renderer, String url,
      {required String title,
      required String artist,
      required String album,
      required String mime,
      String? artUrl,
      Duration? duration}) async {
    opdrachten.add('${renderer.id} open $title');
    uri[renderer.id] = url;
  }

  @override
  Future<void> setNextUrl(Renderer renderer, String url,
          {required String title,
          required String artist,
          required String album,
          required String mime,
          String? artUrl,
          Duration? duration}) async =>
      opdrachten.add('${renderer.id} volgende $title');

  @override
  Future<void> play(Renderer r) async => opdrachten.add('${r.id} play');
  @override
  Future<void> pause(Renderer r) async => opdrachten.add('${r.id} pause');
  @override
  Future<void> stop(Renderer r) async => opdrachten.add('${r.id} stop');
  @override
  Future<int?> getVolume(Renderer r) async => 40;
  @override
  Future<void> setVolume(Renderer r, int volume) async => opdrachten.add('${r.id} volume $volume');
  @override
  Future<void> seek(Renderer r, Duration to) async => opdrachten.add('${r.id} seek ${to.inSeconds}');
  @override
  Future<List<({String leider, List<String> leden})>?> sonosGroepen(Renderer eender) async => const [];
  @override
  Future<({Duration? position, Duration duration, String? trackUri})?> positionInfo(Renderer r) async =>
      (position: const Duration(seconds: 30), duration: const Duration(seconds: 200), trackUri: uri[r.id]);
  @override
  Future<TransportState?> transportState(Renderer r) async => const TransportState('PLAYING');
}

/// Een Nest Mini die opschrijft wat hij krijgt; [uri] is wat hij nu speelt.
class _NepCast extends CastBediening {
  final opdrachten = <String>[];
  String? uri;
  var plek = const Duration(seconds: 1);
  var duur = const Duration(seconds: 200);

  @override
  Future<void> playUrl(Renderer renderer, String url,
      {required String title,
      required String artist,
      required String album,
      required String mime,
      String? artUrl,
      Duration? duration}) async {
    opdrachten.add('open $title');
    uri = url;
  }

  @override
  Future<void> setNextUrl(Renderer renderer, String url,
          {required String title,
          required String artist,
          required String album,
          required String mime,
          String? artUrl,
          Duration? duration}) async =>
      opdrachten.add('volgende $title');

  @override
  Future<void> play(Renderer r) async => opdrachten.add('play');
  @override
  Future<void> pause(Renderer r) async => opdrachten.add('pause');
  @override
  Future<void> stop(Renderer r) async => opdrachten.add('stop');
  @override
  Future<void> seek(Renderer r, Duration to) async => opdrachten.add('seek ${to.inMilliseconds}');
  @override
  Future<int?> getVolume(Renderer r) async => 25;
  @override
  Future<void> setVolume(Renderer r, int volume) async => opdrachten.add('volume $volume');
  @override
  Future<({Duration? position, Duration duration, String? trackUri})?> positionInfo(Renderer r) async =>
      uri == null ? null : (position: plek, duration: duur, trackUri: uri);
}

const _amp = Renderer(
    id: 'uuid:amp',
    name: 'Sonos Amp',
    host: '192.168.0.20',
    avTransportUrl: 'http://192.168.0.20/av',
    manufacturer: 'Sonos, Inc.',
    udn: 'RINCON_AMP');
final _kantoor = castRenderer(id: 'k1', host: '192.168.0.253', poort: 8009, naam: 'Kantoor', model: 'Google Home Mini');
final _hal = castRenderer(id: 'h1', host: '192.168.0.184', poort: 8009, naam: 'Hal', model: 'Google Nest Mini');
const _kef = Renderer(
    id: 'kef-1', name: 'LS50', host: '192.168.0.100', avTransportUrl: 'kef://192.168.0.100', manufacturer: 'KEF');

Future<void> _tot(bool Function() klaar) async {
  for (var i = 0; i < 200 && !klaar(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('wie leidt, wie volgt', () {
    test('de minst precieze leidt: Sonos, dan KEF, dan de rest, dan de Nest (die spoelt tot op de ms)', () {
      expect(besteLeider([_kantoor, _amp]).id, _amp.id);
      expect(besteLeider([_kantoor, _kef]).id, _kef.id);
      expect(besteLeider([_kef, _amp]).id, _amp.id);
      expect(besteLeider([_hal, _kantoor]).id, _hal.id, reason: 'gelijk: wie je koos');
    });

    test('alleen een Sonos bij een Sonos speelt vanzelf mee; de rest via de pc', () {
      const move = Renderer(
          id: 'uuid:move', name: 'Move', host: 'x', avTransportUrl: 'http://x/av', manufacturer: 'Sonos', udn: 'RINCON_M');
      expect(speeltVanzelfMee(_amp, move), isTrue);
      expect(speeltVanzelfMee(_amp, _kantoor), isFalse);
      expect(speeltVanzelfMee(_kantoor, _hal), isFalse);
    });
  });

  group('het besluit', () {
    ({VolgStap stap, int doelMs}) besluit(
            {required ({bool speelt, int positieMs})? leider,
            required ({bool speelt, int positieMs})? volger,
            int vertraging = 0,
            int voorsprong = 200,
            int pogingen = 0,
            int sinds = 10000,
            int? rest}) =>
        volgBesluit(
            leider: leider,
            volger: volger,
            vertragingMs: vertraging,
            voorsprongMs: voorsprong,
            pogingen: pogingen,
            sindsSpoelenMs: sinds,
            leiderRestMs: rest);

    test('binnen de marge niets; erbuiten spoelen naar de leider plus de voorsprong', () {
      expect(besluit(leider: (speelt: true, positieMs: 10000), volger: (speelt: true, positieMs: 10000 + kVolgMarge)).stap,
          VolgStap.niets);
      final b = besluit(leider: (speelt: true, positieMs: 10000), volger: (speelt: true, positieMs: 9500));
      expect(b.stap, VolgStap.spoel);
      expect(b.doelMs, 10200);
    });

    test('de schuif telt mee: +80 ms = de volger hoort 80 ms later te zijn', () {
      expect(besluit(leider: (speelt: true, positieMs: 10000), volger: (speelt: true, positieMs: 10080), vertraging: 80).stap,
          VolgStap.niets);
      final b = besluit(leider: (speelt: true, positieMs: 10000), volger: (speelt: true, positieMs: 10000), vertraging: 300);
      expect(b.stap, VolgStap.spoel);
      expect(b.doelMs, 10500);
    });

    test('niet eindeloos: hoogstens vier keer per nummer, niet vlak na de vorige keer, niet aan het eind', () {
      final ver = (speelt: true, positieMs: 9000);
      const leider = (speelt: true, positieMs: 10000);
      expect(besluit(leider: leider, volger: ver, pogingen: kVolgPogingen).stap, VolgStap.niets);
      expect(besluit(leider: leider, volger: ver, sinds: kVolgRust - 1).stap, VolgStap.niets);
      expect(besluit(leider: leider, volger: ver, rest: kVolgEindRust - 1).stap, VolgStap.niets);
      expect(besluit(leider: leider, volger: ver, rest: kVolgEindRust + 1).stap, VolgStap.spoel);
    });

    test('pauze en verder met de leider mee', () {
      expect(besluit(leider: (speelt: false, positieMs: 10000), volger: (speelt: true, positieMs: 10000)).stap,
          VolgStap.pauze);
      expect(besluit(leider: (speelt: false, positieMs: 10000), volger: (speelt: false, positieMs: 10000)).stap,
          VolgStap.niets);
      expect(besluit(leider: (speelt: true, positieMs: 10000), volger: (speelt: false, positieMs: 10000)).stap,
          VolgStap.verder);
      expect(besluit(leider: null, volger: (speelt: true, positieMs: 1)).stap, VolgStap.niets);
    });

    test('de voorsprong leert: liep hij 450 ms achter (de Nest met een lege buffer), dan 450 ms meer', () {
      expect(leerVoorsprong(200, -450), 650);
      expect(leerVoorsprong(650, 100), 550);
      expect(leerVoorsprong(100, 500), 0);
      expect(leerVoorsprong(1900, -500), kVoorsprongMax);
    });
  });

  group('in de cast (Sonos leidt, Nest volgt)', () {
    late Directory map;
    late LanCatalog catalog;
    late _NepUpnp upnp;
    late _NepCast nest;
    late CastManager cast;
    late List<String> ids;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_speaker_volger_');
      final library = LibraryStore()..rootPath = map.path;
      library.tracks.addAll([
        for (final n in ['Een', 'Twee', 'Drie'])
          Track(
            path: '${map.path}/A/Album/$n.flac',
            title: n,
            artist: 'A',
            album: 'Album',
            trackNo: 1,
            duration: const Duration(seconds: 200),
            isFlac: true,
            sizeBytes: 1000,
            sampleRate: 44100,
            bitsPerSample: 16,
          ),
      ]);
      library.rebuildAlbums();
      catalog = LanCatalog(library);
      ids = [for (final t in catalog.snapshot().catalog.tracks) t.id];
      ids.sort((x, y) => catalog.track(x)!.title.compareTo(catalog.track(y)!.title)); // Drie, Een, Twee
      upnp = _NepUpnp();
      nest = _NepCast();
      cast = CastManager(
          catalog: catalog,
          token: 't',
          port: 47820,
          upnp: upnp,
          cast: nest,
          zoekCast: () async => const [],
          zoekKef: () async => const [],
          startGrace: Duration.zero)
        ..kenSpeakersVoorToets([_amp, _kantoor])
        // Zonder de ronde van elke halve seconde: wat hier gebeurt, doet de cast meteen.
        ..volgElke = const Duration(hours: 1);
    });

    tearDown(() {
      cast.dispose();
      catalog.dispose();
      map.deleteSync(recursive: true);
    });

    test('DE KERN: de Nest speelt hetzelfde nummer, het volgende staat klaar, en hij staat in de groep van de Sonos',
        () async {
      await cast.play(_amp.id, [ids[0], ids[1], ids[2]], 0, alsZone: true);
      await cast.groepeer(_amp.id, [_kantoor.id]);
      await _tot(() => nest.opdrachten.contains('volgende Een'));
      expect(nest.opdrachten, ['open Drie', 'volgende Een']);
      expect(_id(nest.uri!), ids[0]);
      expect(upnp.opdrachten.where((o) => o.contains(' bij ')), isEmpty, reason: 'geen Sonos-groep met een Nest');
      expect([for (final g in cast.speakerGroepen) '${g.leider}: ${g.leden.join(',')}'], ['${_amp.id}: ${_amp.id},${_kantoor.id}']);
      final stand = cast.laatsteStanden.firstWhere((s) => s.id == _kantoor.id);
      expect(stand.volume, 25, reason: 'zijn eigen volume, voor zijn regel in de groep');
    });

    test('pauze, verder en stop gaan mee; een volume niet (elk zijn eigen)', () async {
      await cast.play(_amp.id, [ids[0], ids[1]], 0, alsZone: true);
      await cast.groepeer(_amp.id, [_kantoor.id]);
      await _tot(() => nest.uri != null);
      await cast.control(_amp.id, 'pause');
      await _tot(() => nest.opdrachten.contains('pause'));
      await cast.control(_amp.id, 'play');
      await _tot(() => nest.opdrachten.contains('play'));
      await cast.control(_amp.id, 'volume', value: 60);
      await cast.control(_amp.id, 'stop');
      await _tot(() => nest.opdrachten.contains('stop'));
      expect(nest.opdrachten, containsAllInOrder(['pause', 'play', 'stop']));
      expect(nest.opdrachten.where((o) => o.startsWith('volume')), isEmpty);
      await cast.control(_kantoor.id, 'volume', value: 12);
      expect(nest.opdrachten.last, 'volume 12');
      expect(cast.laatsteStanden.firstWhere((s) => s.id == _kantoor.id).volume, 12);
    });

    test('een volgend nummer: de Nest krijgt het, tenzij hij er zelf al naadloos heen ging', () async {
      await cast.play(_amp.id, [ids[0], ids[1], ids[2], ids[0]], 0, alsZone: true);
      await cast.groepeer(_amp.id, [_kantoor.id]);
      await _tot(() => nest.opdrachten.contains('volgende Een'));
      await cast.control(_amp.id, 'next');
      await _tot(() => nest.opdrachten.contains('volgende Twee'));
      expect(_id(nest.uri!), ids[1]);
      expect(nest.opdrachten.where((o) => o == 'volgende Twee'), hasLength(1), reason: 'één keer klaarzetten, niet twee');
      // Nu was de Nest al zelf door (zijn rij), vóór de Sonos: niet opnieuw openen, alleen het volgende klaarzetten.
      nest.uri = 'http://pc/stream/${ids[2]}.flac';
      nest.opdrachten.clear();
      await cast.control(_amp.id, 'next');
      await _tot(() => nest.opdrachten.contains('volgende Drie'));
      expect(nest.opdrachten, ['volgende Drie']);
    });

    test('iets hierna bij de Sonos: ook op de Nest staat dan het juiste volgende klaar', () async {
      await cast.play(_amp.id, [ids[0], ids[1]], 0, alsZone: true);
      await cast.groepeer(_amp.id, [_kantoor.id]);
      await _tot(() => nest.opdrachten.contains('volgende Een'));
      await cast.voegToe(_amp.id, [ids[2]], hierna: true);
      await _tot(() => nest.opdrachten.contains('volgende Twee'));
      expect(nest.opdrachten.last, 'volgende Twee');
    });

    test('uit de groep: de Nest stopt en staat er niet meer bij', () async {
      await cast.play(_amp.id, [ids[0]], 0, alsZone: true);
      await cast.groepeer(_amp.id, [_kantoor.id]);
      await _tot(() => nest.uri != null);
      await cast.groepeer(_amp.id, []);
      expect(nest.opdrachten.last, 'stop');
      expect(cast.speakerGroepen, isEmpty);
      expect(cast.laatsteStanden.map((s) => s.id), [_amp.id]);
    });

    test('krijgt de Nest zelf iets te spelen, dan speelt hij niet meer mee', () async {
      await cast.play(_amp.id, [ids[0]], 0, alsZone: true);
      await cast.groepeer(_amp.id, [_kantoor.id]);
      await _tot(() => nest.uri != null);
      await cast.play(_kantoor.id, [ids[2]], 0, alsZone: true);
      expect(cast.speakerGroepen, isEmpty);
      expect(_id(nest.uri!), ids[2]);
    });

    test('zonder andere speakers (alleen toestellen, of los) leidt wie je koos — zonder hem op het netwerk te zoeken', () async {
      // Een speaker die de pc (nog) niet kent: in de bouwstraat is er geen netwerk met speakers.
      expect(await cast.leiderVoor('uuid:onbekend', []), 'uuid:onbekend');
      expect(await cast.leiderVoor('uuid:onbekend', ['uuid:onbekend']), 'uuid:onbekend');
      expect(await cast.besteLeiderVan(['uuid:onbekend']), 'uuid:onbekend');
    });

    test('kies je de Nest en zet je de Sonos erbij, dan neemt de Sonos de muziek over en volgt de Nest', () async {
      await cast.play(_kantoor.id, [ids[1], ids[2]], 1, alsZone: true);
      final leider = await cast.leiderVoor(_kantoor.id, [_amp.id]);
      expect(leider, _amp.id);
      expect(_id(upnp.uri[_amp.id]!), ids[2], reason: 'de Sonos speelt verder wat de Nest speelde');
      await cast.groepeer(leider, [_kantoor.id]);
      expect(cast.speakerGroepen.single.leider, _amp.id);
    });
  });

  group('in de zonelijst', () {
    late Directory map;
    late LanStateStore staat;
    late ZoneRegister reg;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_speaker_volger_reg_');
      staat = LanStateStore(File('${map.path}/state.json'));
      reg = ZoneRegister(state: staat, pcId: 'pc-THUIS', pcNaam: 'THUIS');
    });

    tearDown(() async {
      await reg.dispose();
      await staat.dispose();
      map.deleteSync(recursive: true);
    });

    test('een groep van merken is één kaart; de Nest is een lid via de pc, met zijn eigen schuif', () {
      reg.zetSpeakers(const [], bekend: [
        (id: 'uuid:amp', naam: 'Sonos Amp', sonos: true),
        (id: 'uuid:move', naam: 'Sonos Move', sonos: true),
        (id: 'cast-k1', naam: 'Kantoor', sonos: false),
      ], groepen: [
        (leider: 'uuid:amp', leden: ['uuid:amp', 'uuid:move', 'cast-k1'])
      ]);
      reg.zetSpeakerVertraging('cast-k1', 120);
      final z = {for (final x in reg.lijst()) x.id: x};
      expect(z.keys, isNot(contains('spk:cast-k1')));
      final amp = z['spk:uuid:amp']!;
      expect(amp.naam, 'Sonos Amp + Sonos Move + Kantoor');
      final leden = {for (final l in amp.leden) l.id: l};
      expect(leden['spk:cast-k1']!.viaPc, isTrue);
      expect(leden['spk:cast-k1']!.samenMs, 120);
      expect(leden['spk:uuid:move']!.viaPc, isFalse, reason: 'een Sonos bij een Sonos doet het zelf');
      expect(leden['spk:uuid:amp']!.viaPc, isFalse);
      expect(ZoneStaat.fromJson(amp.toJson()), amp, reason: 'heen en terug over de lijn');
    });
  });

  test('de klok van de leider loopt ook voor wie via de pc meespeelt', () {
    final s = File('lib/lan/cast_manager.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(s, contains('    final wil = _klokGewenst.contains(s.renderer.id) || _volgersVan(s.renderer.id).isNotEmpty;\n'));
  });

  test('de server: de minst precieze leidt, ook vanuit een toestel; de schuif per lid herijkt', () {
    final s = File('lib/lan/server.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(s, contains('        speaker = await cast.besteLeiderVan(groepSpeakers);\n'));
    expect(s, contains('            final leider = await cast.leiderVoor(speaker, leden);\n'));
    expect(s, contains('        leider = await cast.leiderVoor(gekozen, groepSpeakers);\n'));
    expect(s, contains('      if (lid.startsWith(\'spk:\')) cast.herijkVolger(wie);\n'));
    expect(s, contains('    cast.volgVertraging = (id) => zones.speakerVertraging[id] ?? 0;\n'));
  });
}
