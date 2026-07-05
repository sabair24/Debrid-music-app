import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/recommend.dart';
void main() {
  test('discover from library seeds', () async {
    final r = await RecommendService().discover(['Adele', 'Michael Jackson', 'Daft Punk']);
    final artists = r.map((t) => t.artist).toSet();
    // ignore: avoid_print
    print('discover: ${r.length} tracks across ${artists.length} artists; sample=${r.take(4).map((t) => "${t.artist} — ${t.title}").toList()}');
    expect(r.length > 10, true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
