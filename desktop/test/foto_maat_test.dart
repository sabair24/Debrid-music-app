// "Foto kiezen" met de maat erbij, de scherpste eerst, en Wikipedia-foto's (Saber, 19-10-2026, na "de
// foto's zijn vaak niet scherp"). GEMETEN: 28 van zijn 29 gsm-foto's werden meer dan 2,5 keer
// opgerekt; Alabina's Discogs-foto is 339×510 en wordt 4,2 keer opgerekt.
import 'dart:io';

import 'package:debridmusic/discogs.dart' show DiscogsImage;
import 'package:debridmusic/fotomaat.dart';
import 'package:debridmusic/wikifotos.dart';
import 'package:flutter_test/flutter_test.dart';

DiscogsImage _f(String url, int b, int h) => DiscogsImage(url, url, b, h, false);

void main() {
  group('scherpte op een gsm', () {
    test('de gemeten gevallen', () {
      expect(oprekOpGsm(339, 510), closeTo(4.25, .01), reason: 'Alabina, Discogs');
      expect(oprekOpGsm(1280, 720), closeTo(2.72, .01), reason: 'TheAudioDB-fanart in een staande kop');
      expect(oprekOpGsm(1000, 1000), closeTo(1.96, .01), reason: 'Deezer xl');
      expect(oprekOpGsm(1920, 2560), closeTo(.77, .01), reason: 'een Wikipedia-foto op 1920');
      expect(oprekOpGsm(0, 0), isNull);
    });

    test('het merk: Discogs en TheAudioDB-fanart wel, Deezer xl en Wikipedia niet, onbekend nooit', () {
      expect(onscherpOpGsm(339, 510), isTrue);
      expect(onscherpOpGsm(1280, 720), isTrue);
      expect(onscherpOpGsm(1000, 1000), isFalse);
      expect(onscherpOpGsm(1100, 800), isFalse, reason: '2,45 keer: net onder de grens van 2,5');
      expect(onscherpOpGsm(1000, 760), isTrue, reason: '2,58 keer: net erboven');
      expect(onscherpOpGsm(1920, 2560), isFalse);
      expect(onscherpOpGsm(0, 0), isFalse, reason: 'geen maat = geen gok');
    });

    test('DE KERN: de scherpste eerst, onbekend achteraan, verder de oude volgorde', () {
      final uit = opScherpte([
        _f('discogs', 339, 510),
        _f('onbekend', 0, 0),
        _f('deezer', 1000, 1000),
        _f('wiki', 1920, 2560),
        _f('discogs2', 339, 510),
      ], breed: false);
      expect(uit.map((i) => i.uri), ['wiki', 'deezer', 'discogs', 'discogs2', 'onbekend']);
    });

    test('liggend sorteert op de brede kop van de pc', () {
      final uit = opScherpte([_f('klein', 1000, 562), _f('groot', 1920, 1080), _f('midden', 1280, 720)], breed: true);
      expect(uit.map((i) => i.uri), ['groot', 'midden', 'klein']);
    });

    test('de bron onder de tegel', () {
      expect(fotoBron('https://i.discogs.com/x.jpeg'), 'Discogs');
      expect(fotoBron('https://r2.theaudiodb.com/images/media/artist/fanart/x.jpg'), 'TheAudioDB');
      expect(fotoBron('https://cdn-images.dzcdn.net/images/artist/x/1000x1000.jpg'), 'Deezer');
      expect(fotoBron('https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/X.jpg/1920px-X.jpg'), 'Wikipedia');
      expect(fotoBron('https://example.com/foto.jpg'), 'eigen foto');
    });
  });

  group('Wikipedia: wat Commons teruggeeft', () {
    Map<String, dynamic> pagina(String titel, String mime, int b, int h, {int? tb, int? th}) => {
          'title': titel,
          'imageinfo': [
            {
              'mime': mime,
              'width': b,
              'height': h,
              'url': 'https://upload.wikimedia.org/wikipedia/commons/a/ab/${titel.substring(5)}',
              if (tb != null) 'thumburl': 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/x/1920px-x.jpg',
              if (tb != null) 'thumbwidth': tb,
              if (th != null) 'thumbheight': th,
              'extmetadata': {
                'Artist': {'value': '<a href="x">Arun</a>'},
                'LicenseShortName': {'value': 'CC BY-SA 4.0'},
              },
            }
          ],
        };

    test('DE KERN: de maat van wat de kop krijgt, een voorbeeld van 400, in de gevraagde volgorde', () {
      final info = {
        'query': {
          'pages': [
            pagina('File:B.jpg', 'image/jpeg', 4000, 5000, tb: 1920, th: 2400),
            pagina('File:A.jpg', 'image/jpeg', 3000, 2000, tb: 1920, th: 1280),
          ]
        }
      };
      final uit = portrettenUitInfo(info, ['File:A.jpg', 'File:B.jpg']);
      expect(uit.map((p) => p.bestand), ['File:A.jpg', 'File:B.jpg']);
      expect((uit.first.breedte, uit.first.hoogte), (1920, 1280), reason: 'de miniatuur, niet het origineel');
      expect(uit.first.voorbeeld, contains('/500px-'), reason: 'Wikimedia weigert 400 (gemeten 19-10-2026)');
      expect(uit.first.vermelding, 'Foto: Arun · CC BY-SA 4.0 · Wikimedia Commons');
    });

    test('een origineel smaller dan 1920 heeft geen miniatuur: dan het origineel', () {
      final uit = portrettenUitInfo({
        'query': {
          'pages': [pagina('File:Klein.jpg', 'image/jpeg', 900, 1200)]
        }
      }, ['File:Klein.jpg']);
      expect((uit.single.breedte, uit.single.hoogte), (900, 1200));
      expect(uit.single.url, endsWith('/Klein.jpg'));
    });

    test('geen svg, geen piepkleine, geen video', () {
      final uit = portrettenUitInfo({
        'query': {
          'pages': [
            pagina('File:Logo.svg', 'image/svg+xml', 2000, 2000),
            pagina('File:Duim.jpg', 'image/jpeg', 300, 400),
            pagina('File:Clip.webm', 'video/webm', 1920, 1080),
          ]
        }
      }, ['File:Logo.svg', 'File:Duim.jpg', 'File:Clip.webm']);
      expect(uit, isEmpty);
    });

    test('een Commons-categorie verzamelt meer dan foto\'s van de artiest', () {
      expect(geenPortret('File:Austria Vienna Michael Jackson concert ticket.png'), isTrue);
      expect(geenPortret('File:Collage of Walk of Fame.png'), isTrue);
      expect(geenPortret('File:Michael Jackson 1983 (3x4 cropped) (contrast).jpg'), isFalse);
      expect(geenPortret('File:32 Michael Jackson 1991 by Arun.jpg'), isFalse);
    });

    test('bewaard en teruggelezen', () {
      const p = WikiPortret(
          bestand: 'File:A.jpg', url: 'u', voorbeeld: 'v', breedte: 1920, hoogte: 1280, maker: 'M', licentie: 'L');
      final terug = WikiPortret.fromJson(p.toJson())!;
      expect((terug.bestand, terug.url, terug.voorbeeld, terug.breedte, terug.hoogte, terug.maker, terug.licentie),
          ('File:A.jpg', 'u', 'v', 1920, 1280, 'M', 'L'));
    });
  });

  test('aangesloten: de kiezer toont de maat, sorteert op scherpte en haalt Wikipedia en Deezer erbij', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final begin = main.indexOf('class _ArtistArtGalleryState');
    final kiezer = main.substring(begin, main.indexOf('\nclass ', begin + 10));
    expect(kiezer, contains('final liggend = [...eigen, ...opScherpte(vorm.liggend, breed: true)];'));
    expect(kiezer, contains('final staand = [...eigen, ...opScherpte(vorm.staand, breed: false)];'));
    expect(kiezer, contains('wiki = await WikiFotoService().portretten(widget.artist);'));
    expect(kiezer, contains('final dz = await CoverEnricher(settings).deezerFotoAdres(widget.artist);'));
    expect(kiezer, contains('final onscherp = !breed && onscherpOpGsm(img.width, img.height);'));
    expect(kiezer, contains("child: _fotoVlak(_voorbeeld[img.uri] ?? img.uri),"));
    expect(kiezer, contains('final echt = bytes == null ? null : imageSize(bytes);'));
  });
}
