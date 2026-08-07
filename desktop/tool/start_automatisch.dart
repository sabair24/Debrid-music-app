// Start een AUTOMATISCHE download: geen `exact`, dus de app rangschikt en kiest zelf.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final tok = args[0], basis = args[1];
  final j = jsonDecode(File(args[2]).readAsStringSync()) as Map<String, dynamic>;
  final duur = int.parse(args[3]);
  final alle = (j['files'] as List).cast<Map<String, dynamic>>();
  final kand = alle.where((f) {
    final d = f['durationSec'] as int? ?? 0;
    return (f['filename'] as String).toLowerCase().endsWith('.flac') && d != 0 && (d - duur).abs() <= 4;
  }).toList();
  // Alle hi-res claims mee (die gaat de rangschikking kiezen) plus ruim 44,1 voor de jacht erna.
  final hi = kand.where((f) => (f['sampleRate'] as int? ?? 0) > 48000).toList();
  final cd = kand.where((f) => (f['sampleRate'] as int? ?? 0) <= 48000).take(40).toList();
  final mee = [...hi, ...cd];
  stdout.writeln('${mee.length} kandidaten mee (${hi.length} boven 48 kHz, ${cd.length} cd-tarief)');

  final body = {
    'candidates': mee,
    'key': 'proef2:tousllesmemes',
    'authority': {
      'title': 'Tous les mêmes',
      'artist': 'Stromae',
      'album': 'Racine Carrée (Standard US Version)',
      'trackNo': 5,
      'albumArtist': 'Stromae',
      'trackTotal': 14,
      'year': 2013,
    },
  };
  final http = HttpClient();
  final req = await http.postUrl(Uri.parse('$basis/api/soulseek/download'));
  req.headers.set('Authorization', 'Bearer $tok');
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(body));
  final res = await req.close();
  stdout.writeln('http ${res.statusCode} ${await res.transform(utf8.decoder).join()}');
  http.close();
}
