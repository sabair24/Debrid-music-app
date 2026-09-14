library;

import 'dart:typed_data';

import 'package:debridmusic/kapot_bestand.dart';
import 'package:flutter_test/flutter_test.dart';

/// **GEMETEN OP 14-09-2026 over alle 907 FLAC-bestanden van Saber.**
///
/// De aanleiding staat in `kapot_bestand.dart` zelf, in een commentaarregel die het gat toegaf:
/// *"een AFGEKAPTE flac begint nog altijd met fLaC, en die valt hieronder dus ook netjes stil."*
/// Precies dat gebeurde: vier nummers openden niet, en de app kon er niets zinnigs over zeggen.
///
/// De verhouding tussen wat een bestand weegt en wat zijn eigen STREAMINFO belooft:
///
///     laagste ECHTE nummer    21,2 %   Seal - Stand by Me
///     1 op de 100             42,6 %
///     mediaan                 70,2 %
///     hoogste                109,9 %
///
///     0,13 %  Stromae - Sommeil          } alle vier: ffmpeg zegt "invalid residual"
///     0,86 %  Britney Spears - Radar     } en "decode_frame() failed"
///     2,19 %  Stromae - Moules frites    }
///     2,37 %  Tiesto - Heroes            }
///
/// De regel sloeg aan op exact die vier en op geen enkel ander bestand.
///
/// **En hij vond een fout die er al zat.** Acht bestanden beginnen met `ID3` en kregen daardoor
/// "dit heet .flac maar het is een MP3-achtig blok" te horen, terwijl ffprobe er `codec_name=flac`
/// van maakt en er `fLaC` staat op de byte achter de tag. Een ID3-tag zegt niets over wat eronder
/// ligt. Die regel is weg; zie [id3TagLengte].
void main() {
  /// Een geldige FLAC-kop die [monsters] monsters belooft, op 44,1 kHz stereo 16-bits.
  ///
  /// Met de hand gezet en niet met een schuifhulpje, omdat juist de bitgrenzen de val zijn: de
  /// frequentie is twintig bits, de kanalen drie, de diepte vijf en het aantal monsters
  /// zesendertig, en die lopen alle vier dwars door een byte heen.
  Uint8List kop({required int monsters, int frequentie = 44100, int kanalen = 2, int diepte = 16}) {
    final b = Uint8List(64);
    b.setRange(0, 4, 'fLaC'.codeUnits);
    b[4] = 0x00; // metablok 0 = STREAMINFO, niet het laatste
    b[5] = 0x00;
    b[6] = 0x00;
    b[7] = 34;
    b[18] = (frequentie >> 12) & 0xFF;
    b[19] = (frequentie >> 4) & 0xFF;
    b[20] = ((frequentie & 0x0F) << 4) | (((kanalen - 1) & 0x07) << 1) | (((diepte - 1) >> 4) & 0x01);
    b[21] = (((diepte - 1) & 0x0F) << 4) | ((monsters >> 32) & 0x0F);
    b[22] = (monsters >> 24) & 0xFF;
    b[23] = (monsters >> 16) & 0xFF;
    b[24] = (monsters >> 8) & 0xFF;
    b[25] = monsters & 0xFF;
    return b;
  }

  // Sommeil duurt 3:38. Dat is wat zijn kop belooft; er staat 76 KB in.
  const monstersVanSommeil = 218 * 44100;
  final onverpaktSommeil = monstersVanSommeil * 2 * 2; // stereo, 16 bits = 2 bytes

  group('een FLAC die veel te licht is voor zijn eigen kop', () {
    test('DE KERN: Sommeil wordt herkend als afgekapt', () {
      final zin = waaromNietTeOpenen(
        naam: '11 - Sommeil.flac',
        bytes: 76 * 1024,
        kop: kop(monsters: monstersVanSommeil),
      );
      expect(zin, isNotNull,
          reason: 'de gebruiker kreeg "Failed to recognize file format" en wist niets');
      expect(zin, contains('afgekapt'));
      expect(zin, contains('minder dan 1%'),
          reason: '0,13 % afronden geeft 0 %, en "er staat maar 0% in" leest als een rekenfout');
    });

    test('DE VAL: het zuinigste ECHTE nummer blijft ongemoeid', () {
      // Seal - Stand by Me, 21,2 %: 192 kHz met 44,1-materiaal erin. Dit is het bestand dat de
      // marge bepaalt, en het speelt gewoon — ffmpeg decodeert het zonder één klacht.
      final monsters = 246 * 192000;
      final onverpakt = monsters * 2 * 2;
      expect(
        waaromNietTeOpenen(
          naam: '11 - Stand by Me.flac',
          bytes: (onverpakt * 0.212).round(),
          kop: kop(monsters: monsters, frequentie: 192000),
        ),
        isNull,
        reason: 'een opgewaardeerd bestand perst ver weg en is daarom niet stuk',
      );
    });

    test('DE GRENS: precies op tien procent zwijgt hij nog', () {
      expect(
        waaromNietTeOpenen(
          naam: 'x.flac',
          bytes: (onverpaktSommeil * kMinimaleFlacVerhouding).round(),
          kop: kop(monsters: monstersVanSommeil),
        ),
        isNull,
      );
      expect(
        waaromNietTeOpenen(
          naam: 'x.flac',
          bytes: (onverpaktSommeil * kMinimaleFlacVerhouding).round() - 1024,
          kop: kop(monsters: monstersVanSommeil),
        ),
        contains('afgekapt'),
      );
    });

    test('DE GRENS: de drempel houdt aan BEIDE kanten een ruime marge', () {
      // Niet "ergens tussen 2,37 en 21,2" — dan zou 3 % ook slagen, en dat staat op anderhalve
      // vingerbreedte van een bewezen kapot bestand. Wat de meting draagt is een drempel met
      // ruimte naar twee kanten: zeker een factor drie boven het ergste kapotte, en zeker een
      // factor twee onder het zuinigste echte. Dat is precies de reden dat het 10 % werd.
      expect(kMinimaleFlacVerhouding, greaterThanOrEqualTo(0.0237 * 3),
          reason: 'te dicht op Tiesto - Heroes (2,37 %); één zuiniger kapot bestand en hij zwijgt');
      expect(kMinimaleFlacVerhouding, lessThanOrEqualTo(0.212 / 2),
          reason: 'te dicht op Seal - Stand by Me (21,2 %); één zuiniger ECHT bestand en hij liegt');
    });
  });

  group('wat de kop zelf zegt', () {
    test('DE KERN: het onverpakte formaat komt uit de bitvelden', () {
      expect(flacOnverpakteBytes(kop(monsters: monstersVanSommeil)), onverpaktSommeil);
    });

    test('DE VAL: nul monsters betekent "onbekend" en dus geen bewering', () {
      // Een FLAC die live is gestreamd weet zijn lengte niet en zet daar nullen. Dat is geen
      // afgekapt bestand, en elke verhouding zou dan door nul rekenen.
      expect(flacOnverpakteBytes(kop(monsters: 0)), isNull);
      expect(waaromNietTeOpenen(naam: 'x.flac', bytes: 1024 * 1024, kop: kop(monsters: 0)), isNull);
    });

    test('DE VAL: 24 bits telt als drie bytes, niet als twee', () {
      final monsters = 100000;
      expect(flacOnverpakteBytes(kop(monsters: monsters, diepte: 24)), monsters * 2 * 3);
      expect(flacOnverpakteBytes(kop(monsters: monsters, diepte: 8, kanalen: 1)), monsters * 1 * 1);
    });

    test('DE VAL: 20 bits wordt naar BOVEN afgerond, naar drie bytes', () {
      // Alleen bij een diepte die geen veelvoud van acht is, is er verschil te zien tussen naar
      // boven afronden en gewoon delen. FLAC staat 4 tot 32 bits toe, en 20 bits komt echt voor
      // (DVD-Audio). Deelt hij hier af naar twee bytes, dan schat hij het bestand anderhalf keer
      // te licht in en gaat hij echte nummers beschuldigen.
      final monsters = 100000;
      expect(flacOnverpakteBytes(kop(monsters: monsters, diepte: 20)), monsters * 2 * 3);
      expect(flacOnverpakteBytes(kop(monsters: monsters, diepte: 12, kanalen: 1)), monsters * 2);
    });

    test('DE GRENS: het aantal monsters is zesendertig bits, niet tweeëndertig', () {
      // De hoge vier bits staan in de lage helft van byte 21, samen met het staartje van de
      // bitdiepte. Worden ze vergeten, dan telt een kop met bits daarboven ruim vier miljard
      // monsters te weinig — en een BESCHADIGDE kop heeft daar zomaar bits staan. Dan wordt het
      // beloofde formaat te klein en zwijgt de detector precies bij het bestand waar het om gaat.
      final groot = 0x100000000 + 1000;
      expect(flacOnverpakteBytes(kop(monsters: groot)), groot * 2 * 2);
    });

    test('DE GRENS: een halve kop levert niets op', () {
      expect(flacOnverpakteBytes(kop(monsters: 1000).sublist(0, 25)), isNull);
      expect(flacOnverpakteBytes('fLaC'.codeUnits), isNull);
      expect(flacOnverpakteBytes(const []), isNull);
    });

    test('DE GRENS: een kop zonder frequentie of kanalen is geen kop', () {
      // Nul als monsterfrequentie is volgens de FLAC-beschrijving ongeldig. Staat er toch nul,
      // dan is de kop zelf beschadigd en is er niets uit af te leiden — ook niet het aantal
      // monsters dat er vlak naast staat. Beschuldigen op grond van een kapotte kop is raden.
      expect(flacOnverpakteBytes(kop(monsters: 100000, frequentie: 0)), isNull);
      // Een diepte onder de vier bits bestaat niet in FLAC. Wie hem toch gelooft, rekent met een
      // byte per monster en schat het bestand tot vier keer te licht in.
      expect(flacOnverpakteBytes(kop(monsters: 100000, diepte: 1)), isNull);
      // 2 KB ligt ruim boven [kMinimumBytes] en ruim onder de tien procent van 400 KB, dus als de
      // wacht wegvalt slaat de regel hier wél aan en valt deze toets om.
      expect(
          waaromNietTeOpenen(naam: 'x.flac', bytes: 2048, kop: kop(monsters: 100000, frequentie: 0)),
          isNull);
    });

    test('DE GRENS: het eerste metablok moet STREAMINFO zijn', () {
      final b = kop(monsters: monstersVanSommeil);
      b[4] = 0x04; // VORBIS_COMMENT
      expect(flacOnverpakteBytes(b), isNull);
    });
  });

  group('een ID3-tag vooraan', () {
    /// Een ID3v2-tag van [lengte] nuttige bytes, gevolgd door [erna].
    Uint8List metTag(int lengte, List<int> erna, {int vlaggen = 0}) {
      final b = Uint8List(10 + lengte + erna.length);
      b.setRange(0, 3, 'ID3'.codeUnits);
      b[3] = 3;
      b[4] = 0;
      b[5] = vlaggen;
      b[6] = (lengte >> 21) & 0x7F;
      b[7] = (lengte >> 14) & 0x7F;
      b[8] = (lengte >> 7) & 0x7F;
      b[9] = lengte & 0x7F;
      b.setRange(10 + lengte, b.length, erna);
      return b;
    }

    test('DE KERN: een FLAC met een ID3-tag ervoor is geen mp3', () {
      // Dit is de fout zoals hij op schijf stond: acht bestanden, waaronder Spice Girls - Mama en
      // Dr. Alban - One Love, kregen "dit heet .flac maar het is een MP3-achtig blok".
      expect(
        waaromNietTeOpenen(
          naam: '06 - Mama.flac',
          bytes: 30 * 1024 * 1024,
          kop: metTag(46329, 'fLaC'.codeUnits),
        ),
        isNull,
        reason: 'ffprobe zegt codec_name=flac; de app beschuldigde een goed bestand',
      );
    });

    test('DE VAL: reikt de kop niet over de tag heen, dan zwijgt hij', () {
      // De echte tags waren 2 KB tot 896 KB groot, en er wordt maar 64 bytes gelezen. Niets weten
      // is hier het juiste antwoord; de oude regel gokte en gokte fout.
      final kort = Uint8List(64);
      kort.setRange(0, 3, 'ID3'.codeUnits);
      kort[3] = 3;
      kort[9] = 0x7F; // 127 bytes tag, ruim voorbij de 64 die we hebben
      expect(id3TagLengte(kort), 10 + 127);
      expect(waaromNietTeOpenen(naam: 'x.flac', bytes: 30 * 1024 * 1024, kop: kort), isNull);
    });

    test('DE VAL: onder de tag wordt nog altijd gekeken', () {
      // Zwijgen mag geen blinde vlek worden: staat er een webpagina onder de tag, dan hoort dat
      // gezegd te worden.
      expect(
        waaromNietTeOpenen(
          naam: 'x.flac',
          bytes: 30 * 1024,
          kop: metTag(4, '<!DOCTYPE html>'.codeUnits),
        ),
        contains('webpagina'),
      );
    });

    test('DE GRENS: de voettekst telt mee, de unsynchronisatie-bit niet', () {
      // Twee van de acht bestanden hadden vlaggen 0x80 staan. Zou die als voettekst worden geteld,
      // dan wees de lengte tien bytes te ver en stond er geen `fLaC` meer.
      expect(id3TagLengte(metTag(100, const [], vlaggen: 0x80)), 110);
      expect(id3TagLengte(metTag(100, const [], vlaggen: 0x10)), 120);
    });

    test('DE GRENS: een lengtebyte met een hoge bit is geen geldige tag', () {
      final b = Uint8List(32);
      b.setRange(0, 3, 'ID3'.codeUnits);
      b[3] = 3;
      b[8] = 0x80; // syncsafe verbiedt dit
      expect(id3TagLengte(b), isNull);
      expect(id3TagLengte(Uint8List(32)), isNull, reason: 'nullen zijn geen ID3');
      // De beschrijving verbiedt 0xFF in de twee versiebytes, juist zodat 'ID3' in willekeurige
      // bytes niet per ongeluk als tag leest.
      final v = Uint8List(32);
      v.setRange(0, 3, 'ID3'.codeUnits);
      v[3] = 0xFF;
      expect(id3TagLengte(v), isNull, reason: 'geen bestaande ID3-versie');
      v[3] = 3;
      v[4] = 0xFF; // de herzieningsbyte telt net zo goed mee
      expect(id3TagLengte(v), isNull, reason: 'geen bestaande ID3-herziening');
      expect(id3TagLengte('ID3'.codeUnits), isNull, reason: 'te kort om een lengte te dragen');
    });
  });
}
