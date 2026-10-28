// Een groot antwoord van de clouddatabase wordt buiten de tekendraad omgezet (28-10-2026): de pc hield om de 20,8 s
// ~150 ms de tekendraad vast met ~100 MB geheugen erbij — het ritme van de cloudwachtrij. Hier ligt vast dat de weg
// langs de eigen isolate precies dezelfde documenten oplevert als de gewone.
import 'dart:convert';

import 'package:debridmusic/cloud/firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _antwoord(int n) => jsonEncode({
      'documents': [
        for (var i = 0; i < n; i++)
          {
            'name': 'projects/p/databases/(default)/documents/users/u/queue/item$i',
            'fields': {
              'title': {'stringValue': 'Nummer $i ${'x' * 200}'},
              'progress': {'doubleValue': 0.5},
            },
            'updateTime': '2026-10-28T20:00:00Z',
          }
      ],
    });

void main() {
  Future<List<FirestoreDoc>> lijst(String body) => Firestore(
        token: 't',
        client: MockClient((_) async => http.Response(body, 200, headers: {'content-type': 'application/json'})),
      ).list('users/u/queue');

  test('DE KERN: een groot antwoord (boven de grens) geeft dezelfde documenten', () async {
    final body = _antwoord(2000);
    expect(utf8.encode(body).length, greaterThan(kGrootCloudAntwoord), reason: 'anders toetst dit de gewone weg');
    final docs = await lijst(body);
    expect(docs, hasLength(2000));
    expect(docs.first.id, 'item0');
    expect(docs.last.id, 'item1999');
    expect(docs[7].data['title'], startsWith('Nummer 7 '));
    expect(docs[7].data['progress'], 0.5);
  });

  test('een klein antwoord gaat de gewone weg, met dezelfde uitkomst', () async {
    final docs = await lijst(_antwoord(3));
    expect([for (final d in docs) d.id], ['item0', 'item1', 'item2']);
    expect(docs[1].data['title'], startsWith('Nummer 1 '));
  });
}
