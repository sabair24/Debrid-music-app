// Verifies the Deezer recommendation engine (artist radio + mix) used by Radio.
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/recommend.dart';

void main() {
  test('artist radio returns tracks', () async {
    final r = await RecommendService().artistRadio('Michael Jackson');
    // ignore: avoid_print
    print('artistRadio: ${r.length} tracks; sample=${r.take(4).map((t) => "${t.artist} — ${t.title}").toList()}');
    expect(r.isNotEmpty, true);
    expect(r.first.title.isNotEmpty && r.first.artist.isNotEmpty, true);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('mixRadio blends related artists', () async {
    final r = await RecommendService().mixRadio('Adele');
    final artists = r.map((t) => t.artist).toSet();
    // ignore: avoid_print
    print('mixRadio: ${r.length} tracks across ${artists.length} artists');
    expect(r.length > 15, true);
    expect(artists.length > 1, true); // more than just the seed artist
  }, timeout: const Timeout(Duration(minutes: 2)));
}
