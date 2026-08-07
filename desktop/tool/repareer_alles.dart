// Vervang elk betrapt nummer, ronde na ronde, tot er niets meer betrapt is.
//
// Werkt via de app zelf: zoeken en downloaden gaan over dezelfde API die een gsm gebruikt, en de app
// doet zijn eigen rangschikking, zijn meting bij het landen en zijn jacht-bij-betrapt. Dit script
// kiest dus niet welke kopie beter is — het levert kandidaten aan en kijkt wat eruit komt.
//
// Twee zeven bovenop wat de app al doet:
//  - speelduur binnen 4 s van het bestand dat vervangen wordt, anders is het een remix of een live;
//  - het TRACKNUMMER in de naam van de peer moet kloppen als het erin staat.
import 'dart:convert';
import 'dart:io';

final http = HttpClient()..connectionTimeout = const Duration(seconds: 30);
late String tok, basis;

Future<Map<String, dynamic>?> _get(String url) async {
  try {
    final req = await http.getUrl(Uri.parse(url));
    req.headers.set('Authorization', 'Bearer $tok');
    final res = await req.close().timeout(const Duration(seconds: 240));
    if (res.statusCode != 200) {
      await res.drain<void>();
      return null;
    }
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<bool> _post(String url, Map<String, dynamic> body) async {
  try {
    final req = await http.postUrl(Uri.parse(url));
    req.headers.set('Authorization', 'Bearer $tok');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close().timeout(const Duration(seconds: 60));
    await res.drain<void>();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

String _oordelenPad() => [Platform.environment['APPDATA'], 'DebridMusic', 'echtheid_oordelen.json']
    .join(Platform.pathSeparator);

/// Alles wat nu nog afgekapt is EN nog bestaat.
List<Map<String, dynamic>> _betrapt() {
  final d = jsonDecode(File(_oordelenPad()).readAsStringSync()) as Map<String, dynamic>;
  final uit = <Map<String, dynamic>>[];
  d.forEach((p, o) {
    if ((o as Map)['band'] != 'afgekapt') return;
    if (p.contains('_dubbel') || p.contains('_inkomend')) return;
    if (!File(p).existsSync()) return;
    final delen = p.split(Platform.pathSeparator);
    if (delen.length < 3) return;
    final titel = delen.last.replaceAll('.flac', '').replaceFirst(RegExp(r'^\d+\s*[-.]\s*'), '');
    uit.add({
      'pad': p,
      'artiest': delen[delen.length - 3],
      'album': delen[delen.length - 2],
      'titel': titel,
      'afkapHz': o['afkapHz'] ?? 0,
    });
  });
  uit.sort((a, b) => (a['afkapHz'] as num).compareTo(b['afkapHz'] as num));
  return uit;
}

/// Duur en tags van het bestaande bestand: de duur om remixen te weren, de tags om te erven.
Future<Map<String, dynamic>?> _eigenschappen(String pad) async {
  try {
    final r = await Process.run('ffprobe', [
      '-v', 'error', '-show_entries', 'format=duration', '-show_entries', 'format_tags',
      '-of', 'json', pad,
    ]);
    if (r.exitCode != 0) return null;
    final j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    final f = j['format'] as Map<String, dynamic>?;
    if (f == null) return null;
    final tags = <String, String>{};
    (f['tags'] as Map<String, dynamic>? ?? {}).forEach((k, v) => tags[k.toLowerCase()] = '$v');
    return {'duur': (double.tryParse('${f['duration']}') ?? 0).round(), 'tags': tags};
  } catch (_) {
    return null;
  }
}

/// Het tracknummer dat in de naam van een peer zit, of null.
///
/// Vormen die peers echt gebruiken: "01-06. Titel", "1-02 - Titel", "05 - Titel", "05. Titel".
/// Bewust alleen aan het BEGIN van de naam: een kaal getal middenin zou van "Blink 182" een
/// tracknummer maken.
int? tracknummerUitNaam(String bestandsnaam) {
  final naam = bestandsnaam.split(RegExp(r'[\\/]')).last;
  final m = RegExp(r'^(?:\d{1,2}[-_])?(\d{1,2})\s*[-. _]').firstMatch(naam);
  if (m == null) return null;
  final n = int.tryParse(m.group(1)!);
  return (n != null && n >= 1 && n <= 99) ? n : null;
}

Future<void> main(List<String> args) async {
  tok = args[0];
  basis = args[1];
  final maxRondes = args.length > 2 ? int.parse(args[2]) : 6;

  var vorigAantal = -1, zonderVooruitgang = 0;
  for (var ronde = 1; ronde <= maxRondes; ronde++) {
    final lijst = _betrapt();
    stdout.writeln('');
    stdout.writeln('===== RONDE $ronde - ${lijst.length} nog betrapt =====');
    if (lijst.isEmpty) {
      stdout.writeln('KLAAR: niets meer betrapt.');
      break;
    }
    if (lijst.length == vorigAantal) {
      zonderVooruitgang++;
      if (zonderVooruitgang >= 2) {
        stdout.writeln('Twee rondes zonder vooruitgang - hier houdt het op.');
        break;
      }
    } else {
      zonderVooruitgang = 0;
    }
    vorigAantal = lijst.length;

    var gestart = 0;
    for (var i = 0; i < lijst.length; i++) {
      final w = lijst[i];
      final eig = await _eigenschappen(w['pad'] as String);
      if (eig == null) continue;
      final duur = eig['duur'] as int;
      final tags = eig['tags'] as Map<String, String>;
      final verwachtNr = int.tryParse(tags['track'] ?? tags['tracknumber'] ?? '') ?? 0;

      final q = '${w['artiest']} ${w['titel']}';
      final r = await _get('$basis/api/soulseek/search?q=${Uri.encodeQueryComponent(q)}');
      final files = (r?['files'] as List? ?? const []).cast<Map<String, dynamic>>();

      final goed = files.where((f) {
        final naam = (f['filename'] as String).toLowerCase();
        if (!naam.endsWith('.flac')) return false;
        final d = f['durationSec'] as int? ?? 0;
        if (d == 0 || (d - duur).abs() > 4) return false;
        for (final woord in ['remix', 'live', 'karaoke', 'instrumental', 'acapella']) {
          if (naam.contains(woord)) return false;
        }
        if (verwachtNr > 0) {
          final nr = tracknummerUitNaam(f['filename'] as String);
          if (nr != null && nr != verwachtNr) return false;
        }
        return true;
      }).toList();

      if (goed.isEmpty) {
        stdout.writeln('  ${q.padRight(52)} GEEN bruikbare kandidaat (van ${files.length})');
        continue;
      }
      final ok = await _post('$basis/api/soulseek/download', {
        'candidates': goed.take(30).toList(),
        'key': 'rep:$ronde:$i',
        'authority': {
          'title': tags['title'] ?? w['titel'],
          'artist': tags['artist'] ?? w['artiest'],
          'album': tags['album'] ?? w['album'],
          'trackNo': verwachtNr,
          if (tags['album_artist'] != null) 'albumArtist': tags['album_artist'],
          if (tags['tracktotal'] != null) 'trackTotal': int.tryParse(tags['tracktotal']!) ?? 0,
          if ((tags['date'] ?? '').length >= 4) 'year': int.tryParse(tags['date']!.substring(0, 4)),
        },
      });
      if (ok) gestart++;
      stdout.writeln('  ${q.padRight(52)} ${goed.length}/${files.length} kandidaten -> '
          '${ok ? "gestart" : "geweigerd"}');
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    stdout.writeln('  --- $gestart gestart, wachten ---');
    for (var w = 0; w < 180; w++) {
      await Future<void>.delayed(const Duration(seconds: 10));
      final j = await _get('$basis/api/jobs');
      final jobs = (j?['jobs'] as List? ?? const []).cast<Map<String, dynamic>>();
      final bezig = jobs
          .where((x) =>
              '${x['key']}'.startsWith('rep:$ronde:') &&
              x['status'] != 'done' &&
              x['status'] != 'failed')
          .length;
      if (bezig == 0) break;
    }
    // De jachten mogen nalopen voordat we opnieuw tellen.
    await Future<void>.delayed(const Duration(seconds: 60));
  }

  final rest = _betrapt();
  stdout.writeln('');
  stdout.writeln('===== EINDE: ${rest.length} nog betrapt =====');
  for (final w in rest) {
    stdout.writeln('  ${((w['afkapHz'] as num) / 1000).toStringAsFixed(1)} kHz  '
        '${w['artiest']} - ${w['titel']}');
  }
  http.close();
}
