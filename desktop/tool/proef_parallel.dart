// Zoek voor elk betrapt nummer en zet ze ALLEMAAL tegelijk in de wachtrij.
// Doel: meten wat er samen doorheen komt, niet wat één download haalt.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final tok = args[0], basis = args[1];
  final werk = (jsonDecode(File(args[2]).readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 30);

  Future<Map<String, dynamic>?> haal(String url) async {
    final req = await http.getUrl(Uri.parse(url));
    req.headers.set('Authorization', 'Bearer $tok');
    final res = await req.close().timeout(const Duration(seconds: 200));
    if (res.statusCode != 200) return null;
    return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
  }

  // Eerst ALLE zoekopdrachten, dan pas starten -- anders begint de eerste al te downloaden terwijl
  // de laatste nog zoekt, en meet je een oplopende in plaats van een gelijktijdige belasting.
  final klaar = <Map<String, dynamic>>[];
  for (final w in werk) {
    final q = '${w['artiest']} ${w['titel']}';
    final r = await haal('$basis/api/soulseek/search?q=${Uri.encodeQueryComponent(q)}');
    final files = (r?['files'] as List? ?? const []).cast<Map<String, dynamic>>();
    final flac = files.where((f) => (f['filename'] as String).toLowerCase().endsWith('.flac')).toList();
    stdout.writeln('${q.padRight(58)} ${flac.length} FLAC');
    if (flac.isEmpty) continue;
    klaar.add({'w': w, 'kand': flac.take(30).toList()});
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  stdout.writeln('\n--- ${klaar.length} nummers tegelijk in de wachtrij ---');
  for (var i = 0; i < klaar.length; i++) {
    final w = klaar[i]['w'] as Map<String, dynamic>;
    final body = {
      'candidates': klaar[i]['kand'],
      'key': 'par:$i',
      'authority': {
        'title': w['titel'],
        'artist': w['artiest'],
        'album': '',
        'trackNo': 0,
      },
    };
    final req = await http.postUrl(Uri.parse('$basis/api/soulseek/download'));
    req.headers.set('Authorization', 'Bearer $tok');
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    stdout.writeln('  par:$i -> ${res.statusCode} ${await res.transform(utf8.decoder).join()}');
  }
  http.close();
}
