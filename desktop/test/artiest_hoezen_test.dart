/// De discografie op een artiestpagina: de juiste Discogs-artiest, hoezen uit het Cover Art
/// Archive, een nette tegel waar er geen is, en blokken die niet eindeloos doorlopen.
///
/// **Waarom dit een toets verdient.** Aangewezen op 25-09-2026 bij Oasis: de LIVE-sectie was 200
/// tegels, waarvan 191 hetzelfde grijze vak met een schijfje — "dit oogt echt heel lelijk".
/// Gemeten in de cache op de pc:
///
/// * Discogs gaf **één** regel, want de zoektocht op naam koos "Oasis" (26794), een Belgisch
///   tranceproject, en niet "Oasis (2)" (140140). Zonder Discogs-hoezen ging de regel uit die
///   tegels zonder hoes verbergt, en op de pagina stond "Ook in: Tony Varone · Cl. Sacchi · Peter
///   Peyskens". MusicBrainz verwijst zelf naar `discogs.com/artist/140140`.
/// * De 191 kwamen alleen van MusicBrainz, dat per releasegroep nooit een hoes levert — maar het
///   Cover Art Archive had er in een steekproef van 39 er 32.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/discography.dart';
import 'package:debridmusic/discography_service.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/ui/plaattegel.dart';

/// MusicBrainz zonder netwerk: een vaste artiest en een vaste Discogs-verwijzing.
class _NepMb extends MusicBrainzService {
  _NepMb({this.artiest, this.discogs});
  final MbArtist? artiest;
  final int? discogs;
  int gezocht = 0;

  @override
  Future<MbArtist?> resolveArtist(String name) async {
    gezocht++;
    return artiest;
  }

  @override
  Future<int?> discogsArtistId(String mbid) async => mbid == artiest?.mbid || artiest == null
      ? discogs
      : null;
}

/// Discogs zonder netwerk: op naam komt altijd het tranceproject terug, zoals bij Oasis.
class _NepDiscogs extends DiscogsService {
  _NepDiscogs() : super(AppSettings());
  int opNaam = 0;

  @override
  Future<int?> artistId(String name) async {
    opNaam++;
    return 26794;
  }
}

DiscoRelease _rij(String titel, RecordKind soort, {String? hoes, String? groep}) => DiscoRelease(
      title: titel,
      kind: soort,
      firstDate: '1995',
      cover: hoes,
      sources: {DiscoSource.musicbrainz},
      refs: {if (groep != null) DiscoSource.musicbrainz: CatalogRef.musicbrainzGroup(groep)},
    );

void main() {
  group('de juiste Discogs-artiest', () {
    const oasis = MbArtist('39ab1aed-75e0-4140-bd47-540276886b60', 'Oasis');

    test('DE KERN: de verwijzing van MusicBrainz wint van de zoektocht op naam', () async {
      final mb = _NepMb(artiest: oasis, discogs: 140140);
      final dg = _NepDiscogs();
      final id = await DiscographyService(CatalogService(), mb, dg).discogsIdVoor('Oasis');
      expect(id, 140140, reason: 'op naam kwam het Belgische tranceproject terug (26794)');
      expect(dg.opNaam, 0, reason: 'met een verwijzing hoeft er niet op naam gezocht te worden');
    });

    test('DE GRENS: een bekend MusicBrainz-nummer slaat het zoeken over', () async {
      final mb = _NepMb(artiest: oasis, discogs: 140140);
      final id = await DiscographyService(CatalogService(), mb, _NepDiscogs())
          .discogsIdVoor('Oasis', bekendeMbid: oasis.mbid);
      expect(id, 140140);
      expect(mb.gezocht, 0);
    });

    test('DE GRENS: zonder verwijzing blijft het oude gedrag', () async {
      final dg = _NepDiscogs();
      final id = await DiscographyService(CatalogService(), _NepMb(artiest: oasis), dg)
          .discogsIdVoor('Oasis');
      expect(id, 26794);
      expect(dg.opNaam, 1);
    });

    test('DE VAL: een MusicBrainz-artiest met een andere naam telt niet', () async {
      // Dezelfde naamtucht als de discografie van MusicBrainz: "Backstreet" is niet "Backstreet
      // Girls", en diens Discogs-nummer hoort dus ook niet op deze pagina.
      final dg = _NepDiscogs();
      final id = await DiscographyService(CatalogService(),
              _NepMb(artiest: const MbArtist('x', 'Backstreet Girls'), discogs: 999), dg)
          .discogsIdVoor('Backstreet');
      expect(id, 26794, reason: 'het Discogs-nummer van een naamgenoot');
      expect(dg.opNaam, 1);
    });

    test('DE KERN: de verwijzing uit url-rels, zoals MusicBrainz hem voor Oasis geeft', () {
      expect(
          discogsIdUitRelaties([
            {'type': 'wikidata', 'url': {'resource': 'https://www.wikidata.org/wiki/Q42970'}},
            {'type': 'discogs', 'url': {'resource': 'https://www.discogs.com/artist/140140'}},
          ]),
          140140);
      expect(
          discogsIdUitRelaties([
            {'type': 'discogs', 'url': {'resource': 'https://www.discogs.com/artist/140140-Oasis-2'}},
          ]),
          140140,
          reason: 'soms staat de naam achter het nummer');
      expect(
          discogsIdUitRelaties([
            {'type': 'discogs', 'url': {'resource': 'https://www.discogs.com/label/1234'}},
          ]),
          isNull,
          reason: 'een label is geen artiest');
      expect(discogsIdUitRelaties(['onzin', 3, null]), isNull);
    });
  });

  group('hoezen uit het Cover Art Archive', () {
    test('DE KERN: de voorkant als kleine tegel, zoals het archief hem teruggeeft', () {
      // Een echt antwoord voor een live-opname van Oasis, 25-09-2026, ingekort.
      final antwoord = {
        'images': [
          {
            'front': true,
            'back': false,
            'types': ['Front'],
            'image': 'https://coverartarchive.org/release/877a0302-3edb-4928-8195-bf955544c15f/45367310185.jpg',
            'thumbnails': {
              '250': 'https://coverartarchive.org/release/877a0302-3edb-4928-8195-bf955544c15f/45367310185-250.jpg',
              '500': 'https://coverartarchive.org/release/877a0302-3edb-4928-8195-bf955544c15f/45367310185-500.jpg',
            },
          }
        ],
        'release': 'https://musicbrainz.org/release/877a0302-3edb-4928-8195-bf955544c15f',
      };
      expect(voorkantUitCaa(antwoord), endsWith('-250.jpg'));
    });

    test('DE VAL: een achterkant is geen hoes', () {
      expect(
          voorkantUitCaa({
            'images': [
              {'front': false, 'types': ['Back'], 'image': 'https://x/b.jpg', 'thumbnails': {'250': 'https://x/b-250.jpg'}},
            ]
          }),
          isNull,
          reason: 'een achterkant als tegel leest als een verkeerde hoes');
      expect(voorkantUitCaa(const {}), isNull);
    });

    test('DE KERN: alleen regels zonder hoes mét een releasegroep, op volgorde van de blokken', () {
      final lijst = groepenZonderHoes([
        _rij('Knebworth 1996', RecordKind.live, groep: 'g-live'),
        _rij('Heb al een hoes', RecordKind.live, hoes: 'https://x/h.jpg', groep: 'g-heeft'),
        _rij('Alleen Deezer', RecordKind.live),
        _rij('Een demo', RecordKind.demo, groep: 'g-demo'),
        _rij('Definitely Maybe', RecordKind.album, groep: 'g-album'),
      ]);
      expect([for (final g in lijst) g.mbid], ['g-album', 'g-live'],
          reason: 'de albums eerst; een regel mét hoes, zonder groep of in een verborgen blok niet');
      expect(lijst.last.sleutel, discoKey('Knebworth 1996'));
    });

    test('DE KERN: wat het archief vond komt via de gewone aanvulling op de regel', () {
      final rijen = [_rij('Roskilde \'95', RecordKind.live, groep: 'g1')];
      final uit = vulHoezenAan(rijen, {discoKey('Roskilde \'95'): 'https://caa/1-250.jpg'});
      expect(uit.single.cover, 'https://caa/1-250.jpg');
    });
  });

  group('een blok van tweehonderd', () {
    SliverConstraints breedte(double w) => SliverConstraints(
          axisDirection: AxisDirection.down,
          growthDirection: GrowthDirection.forward,
          userScrollDirection: ScrollDirection.idle,
          scrollOffset: 0,
          precedingScrollExtent: 0,
          overlap: 0,
          remainingPaintExtent: 1000,
          crossAxisExtent: w,
          crossAxisDirection: AxisDirection.right,
          viewportMainAxisExtent: 1000,
          remainingCacheExtent: 1000,
          cacheOrigin: 0,
        );

    test('DE VAL: dezelfde som als het raster zelf', () {
      // Een eigen som die ook maar één kolom afwijkt, toont "twee rijen" als anderhalve.
      const raster = SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: .74);
      for (final w in [120.0, 300.0, 388.0, 389.0, 700.0, 1232.0, 1344.0, 1888.0]) {
        final echt = (raster.getLayout(breedte(w)) as SliverGridRegularTileLayout).crossAxisCount;
        expect(kolommenVoor(w), echt, reason: 'bij $w punten breed');
      }
    });

    test('DE KERN: ingeklapt twee rijen, open alles', () {
      expect(zichtbaarInBlok(aantal: 200, kolommen: 8, open: false), 16);
      expect(zichtbaarInBlok(aantal: 200, kolommen: 8, open: true), 200);
    });

    test('DE GRENS: wat al in twee rijen past, toont alles', () {
      expect(zichtbaarInBlok(aantal: 9, kolommen: 8, open: false), 9,
          reason: 'een knop "toon alle 9" onder negen tegels is een knop voor niets');
      expect(zichtbaarInBlok(aantal: 16, kolommen: 8, open: false), 16);
    });
  });

  group('een plaat zonder hoes', () {
    testWidgets('DE KERN: de titel groot in beeld, geen grijs vak met een schijfje', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Center(child: PlaatTegel(titel: '1994-02-06: Gleneagles Hotel', jaar: '1994', maat: 180)),
      ));
      expect(find.text('1994-02-06: Gleneagles Hotel'), findsOneWidget);
      expect(find.text('1994'), findsOneWidget);
      expect(find.byIcon(Icons.album_rounded), findsNothing);
    });

    test('DE VAL: elke plaat houdt zijn eigen kleur, ook morgen', () {
      expect(tegelKleur('Roskilde \'95'), tegelKleur('Roskilde \'95'));
      expect(tegelKleur('Roskilde \'95'), tegelKleur('  roskilde \'95 '),
          reason: 'hoofdletters of een spatie zijn geen andere plaat');
      expect(tegelKleur('Roskilde \'95'), isNot(tegelKleur('Live by the Sea')));
    });
  });

  group('de aansluiting', () {
    // Wat alleen in de artiestpagina gebeurt, is zonder toestel niet te draaien — dus uit de bron,
    // zonder de commentaarregels.
    String bron(String pad) => File(pad)
        .readAsLinesSync()
        .where((r) => !r.trimLeft().startsWith('//'))
        .join('\n');
    void staatErin(String tekst, String stuk, String waarom) =>
        expect(tekst.contains(stuk), isTrue, reason: '$waarom\n  ontbreekt: $stuk');

    test('DE VAL: de pagina gebruikt de juiste Discogs-artiest, twee keer', () {
      final dienst = bron('lib/discography_service.dart');
      staatErin(dienst, 'final id = await discogsIdVoor(naam, bekendeMbid: bekendeMbid);',
          'de discografie zocht Discogs op naam');
      final main = bron('lib/main.dart');
      staatErin(main, 'svc.vanDiscogs(naam, bekendeMbid: ref.isMb ? ref.id : null)',
          'zonder het MusicBrainz-nummer moet de dienst het zelf opzoeken');
      staatErin(main, "DiscogsService(context.read<AppSettings>()).artist(naam, id: id)",
          'de regel "Ook in" noemde de leden van het tranceproject');
    });

    test('DE VAL: de hoezen van het archief komen op de pagina, en tellen pas mee als ze er zijn', () {
      final main = bron('lib/main.dart');
      staatErin(main, 'unawaited(_haalGroepHoezen(naam, alles));', 'de ronde wordt nooit gestart');
      staatErin(main, '{..._hoezen, ..._groepHoezen}', 'gevonden hoezen komen niet op de regels');
      staatErin(main, '(_dgStatus != BronStatus.geenToken && _hoezen.isNotEmpty) || _groepKlaar',
          'de hoesregel');
      staatErin(main, '_groepKlaar = nieuw > 0;',
          'zonder vondst hoort een artiest zijn platen niet te verliezen');
    });

    test('DE VAL: een tegel zonder hoes wordt een PlaatTegel, en de albums klappen niet in', () {
      final main = bron('lib/main.dart');
      staatErin(main, 'zonder: PlaatTegel(titel: al.title, jaar: al.year, maat: c.maxWidth)',
          'dan blijft het grijze vak met een schijfje');
      staatErin(main, 'final altijdOpen = blok.soort == RecordKind.album;',
          'een studioplaat hoort niet achter een knop');
      staatErin(main, 'kolommen: kolommenVoor(c.crossAxisExtent),', 'de breedte van het blok zelf');
    });
  });
}
