/// Which Firebase project this app talks to.
///
/// These are not secrets. A Firebase web API key identifies a project; it grants nothing on its
/// own, and Google publishes it in every web app that uses Firebase. What protects your library is
/// the Firestore rule saying a document under `users/{uid}` is readable only by that uid. Keeping
/// the key out of the repository would buy nothing and would mean every build machine needed one
/// more secret.
///
/// Empty values mean "no cloud configured": the app then falls back to the pairing code it has
/// always used, so a checkout without a Firebase project still builds and runs.
library;

class CloudConfig {
  const CloudConfig({required this.projectId, required this.apiKey});

  /// e.g. `debridmusic-1a2b3`
  final String projectId;

  /// Firebase console → Project settings → General → Web API Key.
  final String apiKey;

  bool get isConfigured => projectId.isNotEmpty && apiKey.isNotEmpty;

  /// Fill these in for your project. A `--dart-define` of the same name overrides them, which is
  /// how a build can point at a test project without editing the file.
  static const CloudConfig current = CloudConfig(
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'debridmusic-app'),
    apiKey: String.fromEnvironment('FIREBASE_API_KEY',
        defaultValue: 'AIzaSyB48pQ7Bp9AeRSViAMA5TC2ZBDV0JFnDRE'),
  );

  Uri authUrl(String method) => Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:$method?key=$apiKey');

  Uri refreshUrl() => Uri.parse('https://securetoken.googleapis.com/v1/token?key=$apiKey');

  /// A document or collection path under this project's default database.
  Uri documentsUrl(String path, [Map<String, String>? query]) => Uri.https(
        'firestore.googleapis.com',
        '/v1/projects/$projectId/databases/(default)/documents/$path',
        query,
      );
}
