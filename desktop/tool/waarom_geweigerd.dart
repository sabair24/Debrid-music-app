/// Waarom weigert het tagpakket dit bestand, en wat ziet onze eigen lezer erin?
library;

import 'dart:io';

import 'package:debridmusic/flac_tags.dart' show tagParserWouldClaim;
import 'package:debridmusic/mp3_tags.dart';
import 'package:debridmusic/organize.dart';

void main(List<String> args) {
  for (final p in args) {
    final f = File(p);
    if (!f.existsSync()) {
      stdout.writeln('bestaat niet: $p');
      continue;
    }
    stdout.writeln(p.split(Platform.pathSeparator).last);
    final kop = readId3Header(f);
    stdout.writeln('   ID3-kop        : ${kop == null ? "geen" : "v2.${kop.major}  ${kop.size} bytes"
        '  schrijfbaar=${kop.writable}  lastig=${kop.awkward}'}');
    stdout.writeln('   pakket claimt  : ${tagParserWouldClaim(f)}');
    stdout.writeln('   eigen ID3-lezer: ${readMp3RawFields(f)}');
    final t = readTags(f);
    stdout.writeln('   readTags       : ${t == null ? "null" : 'artiest="${t.artist}" titel="${t.title}" album="${t.album}" nr=${t.trackNo}'}');
  }
}
