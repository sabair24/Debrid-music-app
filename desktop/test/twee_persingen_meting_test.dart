/// Meting, geen test: hoeveel mappen in de echte bibliotheek bevatten nummers die de gekozen
/// persing niet benoemt?
///
/// Dat getal is het antwoord op de vraag of "deze map bevat twee uitgaves" gebouwd moet worden. Als
/// het één album is, is het een handmatige reparatie; als het vijftien zijn, is het een functie.
///
/// Draait op de feitencache en de bestanden zelf -- geen netwerk, dus het antwoord is reproduceerbaar
/// en kost niemand een API-budget.
///
///     flutter test test/twee_persingen_meting_test.dart --plain-name meting
library;

import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/organize.dart';
import 'package:flutter_test/flutter_test.dart';

const _appdir = r'C:\Users\saber\AppData\Roaming\DebridMusic';
const _audio = {'.flac', '.mp3', '.m4a', '.ogg', '.opus', '.wav'};

void main() {
  test('meting', () {
    // Draait op de echte bibliotheek van deze machine. Elders -- en op de bouwserver -- is er niets
    // te meten, en dan hoort dit over te slaan in plaats van de suite rood te maken.
    if (!File('$_appdir\\album_facts.json').existsSync() ||
        !File('$_appdir\\album_uids.json').existsSync()) {
      markTestSkipped('geen bibliotheek op deze machine');
      return;
    }
    final feiten = jsonDecode(File('$_appdir\\album_facts.json').readAsStringSync()) as Map;
    final facts = (feiten['facts'] as Map).cast<String, dynamic>();
    final paths = ((jsonDecode(File('$_appdir\\album_uids.json').readAsStringSync()) as Map)['paths']
            as Map)
        .cast<String, dynamic>();

    // uid -> de bestanden die eronder vallen.
    final perAlbum = <String, List<String>>{};
    paths.forEach((pad, uid) => perAlbum.putIfAbsent(uid as String, () => []).add(pad));

    var bekeken = 0, metRest = 0, geenPersing = 0, losseBestanden = 0;
    final gevallen = <String>[];

    for (final entry in facts.entries) {
      final f = entry.value as Map;
      final rows = f['tracks'];
      if (rows is! List || rows.isEmpty) continue;
      final bestanden = perAlbum[entry.key];
      if (bestanden == null || bestanden.isEmpty) continue;

      final official = [
        for (final r in rows)
          ChoiceTrack('${(r as Map)['p'] ?? ''}', '${r['t'] ?? ''}', (r['s'] as num?)?.toInt()),
      ];

      final tracks = <Track>[];
      for (final p in bestanden) {
        final punt = p.lastIndexOf('.');
        if (punt < 0 || !_audio.contains(p.substring(punt).toLowerCase())) continue;
        final bestand = File(p);
        if (!bestand.existsSync()) continue;
        final t = readTags(bestand);
        Duration? lengte;
        try {
          lengte = readMetadata(bestand, getImage: false).duration;
        } catch (_) {/* onleesbaar; dan telt hij mee zonder lengte */}
        tracks.add(Track(
          path: p,
          title: t?.title ?? '',
          artist: t?.artist ?? '',
          album: t?.album ?? '',
          trackNo: t?.trackNo ?? 0,
          duration: lengte,
        ));
      }
      if (tracks.isEmpty) continue;

      bekeken++;
      final c = matchAlbumTracks(official, tracks, tracks.first.artist);
      final rest = c.slots.where((s) => s.index == -1).toList();
      if (rest.isEmpty) continue;
      metRest++;
      losseBestanden += rest.length;
      if (!c.namesEverything) geenPersing++;
      final map = bestanden.first.substring(0, bestanden.first.lastIndexOf('\\'));
      final regels = <String>[];
      for (final s in rest) {
        final t = s.track!;
        // Welke ONBEZETTE rij lijkt hier het meest op? Dat is de rij die het had moeten zijn, en het
        // verschil tussen die twee is de reden waarom hij afvalt.
        final vrij = [
          for (var i = 0; i < official.length; i++)
            if (c.slots[i].track == null) official[i],
        ];
        ChoiceTrack? beste;
        var meeste = 0.0;
        for (final o in vrij) {
          final ow = normKey(o.title).split(' ').toSet(), tw = normKey(t.title).split(' ').toSet();
          if (ow.isEmpty || tw.isEmpty) continue;
          final deel = ow.intersection(tw).length /
              (ow.length > tw.length ? ow.length : tw.length);
          if (deel > meeste) {
            meeste = deel;
            beste = o;
          }
        }
        if (beste == null || meeste < 0.4) {
          regels.add('        "${t.title}" — geen rij die erop lijkt (echt niet op deze uitgave)');
          continue;
        }
        final mA = versionMarkers(beste.title), mB = versionMarkers(t.title);
        final gat = (beste.seconds != null && t.duration != null)
            ? (beste.seconds! - t.duration!.inSeconds).abs()
            : -1;
        final waarom = <String>[];
        if (mA.length != mB.length) {
          waarom.add('merk erbij/eraf ($mA vs $mB)');
        } else if (mA.join() != mB.join()) {
          waarom.add('merk anders gespeld ($mA vs $mB)');
        }
        if (gat > 12) waarom.add('looptijd ${gat}s uit elkaar');
        if (meeste < 0.8) waarom.add('woordoverlap ${(meeste * 100).round()}%');
        regels.add('        "${t.title}"\n          tegen "${beste.title}" — ${waarom.isEmpty ? "onbekend" : waarom.join(", ")}');
      }
      gevallen.add('${rest.length} over van ${tracks.length} — ${map.replaceAll(r'D:\Flac music 2024\', '')}\n${regels.join('\n')}');
    }

    // ignore: avoid_print
    print('\n== $bekeken albums met een tracklijst gemeten ==');
    // ignore: avoid_print
    print('$metRest albums hebben in totaal $losseBestanden bestanden die de gekozen persing niet benoemt');
    // ignore: avoid_print
    print('$geenPersing daarvan gaven ook toe dat geen persing alles benoemt\n');
    for (final g in gevallen) {
      // ignore: avoid_print
      print('  $g');
    }
  });
}
