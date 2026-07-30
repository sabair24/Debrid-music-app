/// Een getagd bestand ergens anders neerzetten via de eigen plaatsingslogica van de app.
///
/// Voor het opruimen van één geval: de eerste vondst van de wenslijst landde als
/// `Singles\Onbekende artiest\…` omdat de peer een bestand zonder één tag stuurde en er niets was om
/// op terug te vallen. De code is gerepareerd; dit zet dat ene bestand recht met precies dezelfde
/// weg die de app nu zelf zou nemen.
///
///     dart run tool/tag_en_verhuis.dart "<bestand>" "<wortel>" "<artiest>" "<titel>" "<album>" <nr> <totaal>
library;

import 'dart:io';

import 'package:debridmusic/organize.dart';

void main(List<String> args) async {
  if (args.length < 7) {
    stderr.writeln('te weinig argumenten');
    exit(1);
  }
  final f = File(args[0]);
  if (!f.existsSync()) {
    stderr.writeln('bestaat niet: ${args[0]}');
    exit(1);
  }
  final tags = TrackTags(
    artist: args[2],
    title: args[3],
    album: args[4],
    trackNo: int.tryParse(args[5]) ?? 0,
    trackTotal: int.tryParse(args[6]) ?? 0,
  );
  stdout.writeln('gezag: ${tags.artist} — ${tags.title} (${tags.album}) nr ${tags.trackNo}/${tags.trackTotal}'
      '  gezaghebbend=${tags.isAuthoritative}');
  final uit = await placeFileDetailed(f, args[1], tags: tags);
  stdout.writeln('uitkomst: ${uit.how.name}');
  stdout.writeln('pad     : ${uit.path}');
}
