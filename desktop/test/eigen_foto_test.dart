/// Een eigen foto van internet voor een artiest (Saber, 18-10-2026).
library;

import 'dart:io';

import 'package:debridmusic/eigen_foto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('welk adres er overblijft', () {
    test('een gewoon adres blijft zoals het is', () {
      expect(echtAfbeeldingsadres('  https://upload.wikimedia.org/a-ha.jpg  '), 'https://upload.wikimedia.org/a-ha.jpg');
      expect(echtAfbeeldingsadres('http://voorbeeld.be/foto.png?w=1200'), 'http://voorbeeld.be/foto.png?w=1200');
    });

    test('een link uit Google Afbeeldingen of Bing wordt het adres van de foto zelf', () {
      expect(
          echtAfbeeldingsadres('https://www.google.com/imgres?imgurl=https%3A%2F%2Fvoorbeeld.be%2Faha.jpg&imgrefurl=https%3A%2F%2Fvoorbeeld.be%2F'),
          'https://voorbeeld.be/aha.jpg');
      expect(echtAfbeeldingsadres('https://www.google.be/imgres?imgurl=https://x.org/b.jpg'), 'https://x.org/b.jpg');
      expect(
          echtAfbeeldingsadres('https://www.bing.com/images/search?view=detailV2&mediaurl=https%3A%2F%2Fx.org%2Fc.webp&q=a-ha'),
          'https://x.org/c.webp');
    });

    test('een miniatuur, een pad op de pc of iets anders wordt niets, met uitleg', () {
      expect(echtAfbeeldingsadres('data:image/jpeg;base64,/9j/4AAQSkZJRg=='), isNull);
      expect(waaromGeenAdres('data:image/jpeg;base64,/9j/'), contains('miniatuur'));
      expect(echtAfbeeldingsadres(r'C:\Users\saber\Pictures\aha.jpg'), isNull);
      expect(echtAfbeeldingsadres('file:///C:/aha.jpg'), isNull, reason: 'de gsm kan een pad op de pc niet openen');
      expect(echtAfbeeldingsadres('a-ha band foto'), isNull);
      expect(echtAfbeeldingsadres(''), isNull);
      expect(waaromGeenAdres(''), contains('Plak eerst'));
      expect(waaromGeenAdres('a-ha'), contains('http'));
    });
  });

  test('de galerij heeft het plakveld, controleert de foto en kiest hem', () {
    final hoofd = File('lib/main.dart').readAsStringSync();
    final begin = hoofd.indexOf('class _ArtistArtGalleryState extends State<ArtistArtGallery>');
    final lijf = hoofd.substring(begin, hoofd.indexOf('Widget _sectieKop(', begin));
    expect(lijf, contains('_vanInternet(),'));
    expect(lijf, contains('echtAfbeeldingsadres(invoer)'));
    expect(lijf, contains('CoverEnricher(settings).downloadImage(adres)'),
        reason: 'met dezelfde ophaler als de pagina, anders werkt hij hier wel en daar niet');
    expect(lijf, contains('decodeImageFromList(bytes)'), reason: 'alleen iets wat echt een foto is');
    expect(lijf, contains('lib.setArtistArt(widget.artist, nieuw.isWide ? kSoortLiggend : kSoortStaand, adres)'));
    expect(lijf, contains('final liggend = [...eigen, ...vorm.liggend];'));
    expect(lijf, contains('final staand = [...eigen, ...vorm.staand];'));
  });
}
