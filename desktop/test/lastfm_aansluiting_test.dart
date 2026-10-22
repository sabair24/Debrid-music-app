// Waar Last.fm in de app zit (Saber, 22-10-2026: "doe wat zeker beter zou zijn voor de app", met zijn account
// Sabair24): de artiestpagina, het startscherm, het smaakprofiel van radio en aanbevelingen, de vermelding die Last.fm
// vraagt, en de gebruikersnaam in de instellingen (die meereist met je account).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _lees(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final main = _lees('lib/main.dart');

  test('de artiestpagina: "Bekend, nog niet van jou" tussen je eigen platen en de discografie', () {
    expect(main, contains('    _loadLastfmTop();\n'));
    expect(main, contains('final mis = bekendeNummersDieJeMist(top, van);'));
    final eigen = main.indexOf("_sectionTitle('In mijn bibliotheek'");
    final bekend = main.indexOf("_sectionTitle('Bekend, nog niet van jou', 'Last.fm')");
    final disco = main.indexOf("mine.isEmpty ? 'Discografie' : 'Volledige discografie'");
    expect(eigen < bekend && bekend < disco, isTrue);
    expect(main, contains('SpeelNuKnop(artiest: n.artiest, titel: n.titel),'), reason: 'halen en meteen laten klinken');
  });

  test('het startscherm: "Vroeger veel gespeeld, nog niet van jou" uit je geschiedenis, opgezocht met hoes', () {
    expect(main, contains("final vroegerF = _vroegerGespeeld(cfg, lib.tracks.toList());"));
    expect(main, contains('final mis = nogNietVanJou(g.nummers, bibliotheek).take(30).toList();'));
    expect(main, contains("elders: _itunesVoorModel, eldersNaam: 'iTunes', van: 'je Last.fm');"));
    expect(
      main,
      contains(
        "_section('Vroeger veel gespeeld, nog niet van jou', _recRow(_vroeger.take(20).toList(), rij: 'vroeger'),",
      ),
    );
    expect(main, contains('    vroeger = [];\n'), reason: 'Ververs berekent hem opnieuw');
  });

  test('het startscherm: "Nieuwe artiesten voor jou" — verwanten van wie je speelt, die je niet hebt, met foto', () {
    expect(main, contains('final nieuweArtiestenF = _zoekNieuweArtiesten('));
    expect(main, contains('for (final n in nieuweArtiestenVoorJou(verwant, jouwArtiesten: jouw)) {'));
    expect(
      main,
      contains("_section('Nieuwe artiesten voor jou', _artiestRij(_nieuweArtiesten), bij: 'lijkt op wie je draait'),"),
    );
    expect(main, contains('    nieuweArtiesten = [];\n'), reason: 'Ververs berekent hem opnieuw');
    expect(main, contains('onTap: () => openArtist(context, artiesten[i].name),'));
  });

  test('een radio uit een zin: ook de bekendste nummers onder het genre (Last.fm-tag), hoogstens een derde', () {
    expect(
      main,
      contains("final nummers = await _nummersVoor(o, lastfmSleutel: context.read<AppSettings>().lastfmKey);"),
    );
    expect(main, contains('final tag = await _lastfmBron.tagNummers(o.genre, sleutel: lastfmSleutel, limit: 60);'));
    expect(main, contains('final namen = genreNummersErbij(tag ?? const [], max: ruim ~/ 3);'));
    final tag = main.indexOf('final tag = await _lastfmBron.tagNummers(');
    expect(tag, lessThan(main.indexOf('  uit.shuffle();\n', tag)), reason: 'vóór het door elkaar schudden en zeven');
  });

  test(
    'Bekend / Ontdekken: wie in je bibliotheek of je Last.fm-geschiedenis staat, ken je — niet alleen wat het model raadt',
    () {
      expect(main, contains('return (n) => n.bekend || jouw.contains(artiestSleutel(n.artiest));'));
      expect('modelVolgorde(lijst, await _kentJe(lib, cfg),'.allMatches(main).length, 2, reason: 'start en afstemmen');
      expect(main, isNot(contains('modelVolgorde(lijst, (n) => n.bekend,')));
    },
  );

  test('de albumpagina: een sterretje bij de bekendste nummers, na het laden van de nummers', () {
    expect(main, contains('    _load().then((_) => _laadHits());\n'));
    expect(main, contains('final hits = hitsVanAlbum(luisteraars);'));
    expect(main, contains('if (_hits[i] case final n?)'));
    expect(main, contains("luisteraars op Last.fm',"));
  });

  test('het smaakprofiel: ook wie je volgens Last.fm het meest speelde — op het startscherm en bij de radio', () {
    expect(main, contains('final lfmArtiestenF = _lastfmTopArtiesten(cfg, al: gespeeldeNamen);'));
    expect(main, contains('gespeeld: [...gespeeldeNamen, ...extra].take(15).toList(),'));
    expect(
      main,
      contains("final lfm = await _lastfmTopArtiesten(cfg, al: gespeeld, geduld: const Duration(milliseconds: 800));"),
      reason: 'een radio wacht niet op een koude vraag',
    );
    expect(main, contains('gespeeld: [...gespeeld, ...lfm].take(15).toList(),'));
  });

  test('de vermelding die Last.fm vraagt, en de buffer in een eigen map', () {
    expect(main, contains('powered by AudioScrobbler (last.fm)'));
    expect(main, contains("LastfmZoeker(buffer: '\$appDir\${Platform.pathSeparator}lastfm');"));
  });

  test('de gebruikersnaam: een veld in de instellingen, bewaard, en hij reist mee met je account', () {
    expect(main, contains("_field('Last.fm-gebruikersnaam (je luistergeschiedenis)', _lastfmGebruiker),"));
    expect(main, contains('s.lastfmGebruiker = _lastfmGebruiker.text.trim();'));
    final settings = _lees('lib/settings.dart');
    expect(settings, contains("lastfmGebruiker = (m['lastfm_user'] ?? '') as String;"));
    expect(settings, contains("'lastfm_user': lastfmGebruiker,"));
    expect(_lees('lib/cloud/settings_sync.dart'), contains("  'lastfm_user',\n"));
  });
}
