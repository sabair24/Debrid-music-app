/// Which service keys travel to your other devices, and which stay put.
///
/// Most of them are worth carrying: a phone reinstalled from the App Store has an empty container,
/// and retyping a TorBox token on four devices is nobody's idea of a hub. The Soulseek login is the
/// exception, and this file exists so it stays the exception.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/cloud/config.dart';
import 'package:debridmusic/cloud/firestore.dart';
import 'package:debridmusic/cloud/settings_sync.dart';
import 'package:debridmusic/settings.dart';

const _config = CloudConfig(projectId: 'test-project', apiKey: 'test-key');

void main() {
  /// The document the app tried to write, as Firestore would have received it.
  late Map<String, dynamic> written;

  Firestore db() => Firestore(
        token: 'id-token',
        config: _config,
        client: MockClient((req) async {
          if (req.method == 'PATCH') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            final fields = (body['fields'] as Map).cast<String, dynamic>();
            // Firestore wraps every value in a type tag; the name is all this test needs.
            written = fields;
          }
          return http.Response('{}', 200);
        }),
      );

  setUp(() => written = {});

  AppSettings filled() => AppSettings()
    ..discogsToken = 'discogs-abc'
    ..torboxToken = 'torbox-abc'
    ..soulseekUser = 'leedagair'
    ..soulseekPass = 'geheim'
    ..soulseekPort = 10422
    ..rutrackerUser = 'leedagair'
    ..rutrackerPass = 'ookgeheim';

  test('the Soulseek login does not travel to your other devices', () async {
    // Soulseek allows one session per account: two devices signed in kick each other in turn until
    // the server refuses them both. Only the machine holding the music talks to Soulseek, and that
    // is the machine you typed the password on.
    await SettingsSync(db: db(), uid: 'user-1').push(filled());

    expect(written, isNotEmpty, reason: 'zonder een write bewijst deze test niets');
    expect(written.keys, isNot(contains('soulseek_user')));
    expect(written.keys, isNot(contains('soulseek_pass')));
    // The port describes one router forwarding, not an account.
    expect(written.keys, isNot(contains('soulseek_port')));
  });

  test('the keys that SHOULD travel still do', () async {
    await SettingsSync(db: db(), uid: 'user-1').push(filled());

    // Reinstalling on a phone wipes the container, and retyping these on four devices is the thing
    // the sync exists to prevent.
    expect(written.keys, containsAll(<String>['discogs_token', 'torbox_token']));
    expect(written.keys, containsAll(<String>['rutracker_user', 'rutracker_pass']));
  });

  test('a settings file that failed to load is never pushed', () async {
    // Otherwise one unreadable file on one device would blank the keys for all of them.
    final broken = filled()..loadFailed = true;
    await SettingsSync(db: db(), uid: 'user-1').push(broken);
    expect(written, isEmpty);
  });
}
