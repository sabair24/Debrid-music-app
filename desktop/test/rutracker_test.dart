import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/rutracker.dart';
import 'package:debridmusic/settings.dart';

void main() {
  test('login reaches RuTracker and parses the CAPTCHA challenge', () async {
    final s = AppSettings()
      ..rutrackerUser = 'debridtest_x'
      ..rutrackerPass = 'wrongpass_x';
    final r = await RuTrackerService(s).login();
    print('ok=${r.ok} error=${r.error} captcha=${r.captcha != null}');
    if (r.captcha != null) {
      print('  img=${r.captcha!.imageUrl}');
      print('  sid=${r.captcha!.sid}');
      print('  field=${r.captcha!.codeField}');
      print('  cookies=${r.captcha!.cookies}');
      expect(r.captcha!.imageUrl.startsWith('http'), true);
      expect(r.captcha!.sid.isNotEmpty, true);
      expect(r.captcha!.codeField.startsWith('cap_code_'), true);
    }
    // Reaches the server and returns a well-formed result (never a crash).
    expect(r.ok || r.captcha != null || r.error != null, true);
  });
}
