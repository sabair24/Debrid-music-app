/// Windows-1251, beide kanten op.
///
/// **Waarom dit een eigen bestand is.** De ene richting stond al in `rutracker.dart` — als
/// `cp1251Byte`, om het inlogformulier te versturen. De andere ontbrak, en dat is precies waarom
/// Russische titels als onzin binnenkwamen: het antwoord werd met `latin1.decode` gelezen, en
/// latin-1 en cp1251 zijn het alleen over ASCII eens. Elke Cyrillische byte werd dus een ander
/// teken.
///
/// Nu is er één tabel, op één plek, en twee dingen gebruiken hem: de tracker en de cue-lezer. Een
/// cuesheet van een Russische persing is namelijk net zo goed cp1251, en dat is precies het bestand
/// waar de nummernamen in staan.
///
/// Zuiver en zonder netwerk, dus na te meten zonder toestel.
library;

import 'dart:convert';
import 'dart:typed_data';

/// De tekens op 0x80–0xBF. Cyrillisch ligt daarboven aaneengesloten en heeft geen tabel nodig.
///
/// Dit stuk is leestekens en symbolen — aanhalingstekens, een gedachtestreepje, `№`, `©`. Die komen
/// in albumtitels vaker voor dan je zou denken, en zonder deze regels worden het vraagtekens.
const _hoog = <int>[
  0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, // 80–87
  0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F, // 88–8F
  0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, // 90–97
  0xFFFD, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F, // 98–9F (0x98 bestaat niet)
  0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, // A0–A7
  0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407, // A8–AF
  0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7, // B0–B7
  0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457, // B8–BF
];

/// Bytes in windows-1251 naar tekst.
///
/// **Via een `Uint16List` en niet via een `StringBuffer`, en dat scheelt een veelvoud.** Elke byte
/// wordt precies één teken — dat staat van tevoren vast — dus de lengte is bekend en er valt niets
/// te laten groeien. Een `StringBuffer` weet dat niet: die vraagt bij elke `writeCharCode` opnieuw
/// of er nog plaats is en kopieert zichzelf als dat niet zo is. Op een zoekpagina van RuTracker
/// gaat het om een half miljoen tekens, en dat op de tekendraad.
String cp1251Tekst(List<int> bytes) {
  final uit = Uint16List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    uit[i] = b < 0x80
        ? b
        : b < 0xC0
            ? _hoog[b - 0x80]
            // А..я liggen aaneengesloten op 0xC0..0xFF. Dat is het leeuwendeel en het kost geen tabel.
            : 0x410 + (b - 0xC0);
  }
  return String.fromCharCodes(uit);
}

/// Eén teken naar zijn byte in windows-1251, of null als die codetabel het niet kent.
int? cp1251Byte(int teken) {
  if (teken < 0x80) return teken; // ASCII is in beide tabellen hetzelfde
  if (teken >= 0x410 && teken <= 0x44F) return 0xC0 + (teken - 0x410); // А..я aaneengesloten
  if (teken == 0x401) return 0xA8; // Ё
  if (teken == 0x451) return 0xB8; // ё
  final i = _hoog.indexOf(teken);
  return i < 0 ? null : 0x80 + i;
}

/// Tekst uit bytes waarvan je de codering niet weet.
///
/// **De volgorde is niet willekeurig.** Eerst een BOM, want die is een verklaring en geen gok.
/// Daarna UTF-8 mét controle: geldige UTF-8 met Cyrillisch erin is bijna nooit per ongeluk geldig,
/// dus als dat lukt is het dat ook. Pas als dat faalt is het cp1251 — en dán is het dat vrijwel
/// zeker, want dat is wat Russische persingen en RuTracker gebruiken.
///
/// Nooit `latin1` als vangnet. Dat lukt namelijk ALTIJD — elke byte is een geldig latin-1-teken —
/// en dan krijg je stilletjes onzin in plaats van een fout. Precies de val waar dit uit voortkomt.
String tekstUitOnbekend(List<int> bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  try {
    return utf8.decode(bytes); // niet toegeeflijk: falen is hier het signaal
  } on FormatException {
    return cp1251Tekst(bytes);
  }
}
