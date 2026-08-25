/// Eén menu voor een nummer of een plaat, in twee vormen.
///
/// **Waarom dit los van main.dart staat.** Dezelfde reden als `navigatie.dart`: de schil heeft
/// veertien providers en een libmpv die in een toetsrun niet bestaat, dus alles wat dáár staat is
/// onmeetbaar. Hier staan alleen gegevens en twee tekeningen — geen store, geen provider — en dat
/// maakt dit bestand te pompen in een toets. `tv.dart` importeert zelf niets uit `main.dart`, dus
/// er ontstaat ook geen kringetje.
///
/// **Waarom het menu opnieuw is gemaakt.** Het was Flutters kale `showMenu`, zonder één instelling
/// behalve een kleur, en dat voelde stroef. Dat is geen gevoel maar een rekensom, nagelezen in de
/// vastgezette broncode van Flutter 3.41.9:
///
///   * de overgang duurt standaard 300 ms, heen én terug;
///   * `_PopupMenu` animeert `Align(widthFactor:, heightFactor:)` binnen een `AnimatedBuilder`
///     (popup_menu.dart:796) — een volledige HERINDELING van het menu op elk beeld. Het groeit open
///     in plaats van te verschijnen, en dat is precies wat je ziet;
///   * elke regel komt apart in beeld op `1/(n+1.5)` van de tijd (popup_menu.dart:727). Bij veertien
///     posten begint de laatste pas rond 280 ms. Dat druppelen ís de stroefheid.
///
/// Op een telefoon en een tv is het antwoord niet "sneller uitrollen" maar een ander ding: een blad
/// dat van onderaf omhoog schuift, dicht bij je duim, zoals de wachtrij dat al doet. Onder een muis
/// blijft een zwevend menu juist, maar dan kort en bij de cursor.
library;

import 'package:flutter/material.dart';

import '../tv.dart';
import 'kleuren.dart';

/// Eén regel in het menu.
@immutable
class MenuRegel {
  const MenuRegel(this.icoon, this.tekst, this.doen, {this.uit = false});

  final IconData icoon;
  final String tekst;

  /// Zichtbaar maar niet te kiezen, in lichter grijs.
  ///
  /// **Waarom tonen en niet weglaten.** Bij een ontbrekend nummer werkt de helft van dit menu niet:
  /// je kunt niets afspelen wat er niet is. Die regels weglaten zou een kórter menu geven dat elke
  /// keer een andere vorm heeft, en dan moet je zoeken waar "Zoeken met Soulseek" nu weer staat.
  /// Grijs laat de vorm staan en zegt meteen wat er wél kan.
  final bool uit;

  /// Al gebonden aan zijn nummer of album op het moment dat het menu wordt samengesteld.
  ///
  /// Daardoor heeft geen van beide tekeningen een provider nodig — en dát is wat het blad op de
  /// HOOFDnavigator mogelijk maakt, waar de providers wél bij zijn maar de sectie niet.
  final VoidCallback doen;
}

/// Een menu als GEGEVENS: blokken regels, met de strepen ertussen en niet erin.
///
/// **Waarom blokken en geen platte lijst met scheidingsposten.** "Ga naar album" bestaat alleen als
/// het nummer een album heeft. Met scheidingen als losse post blijft er dan een streep over die
/// nergens tussen staat, en dat is de bugsoort die je pas op een schermafbeelding ziet. Als blok mag
/// het gewoon leeg zijn; [gevuld] laat het vallen en de strepen kloppen vanzelf.
@immutable
class ItemMenu {
  const ItemMenu({required this.titel, this.ondertitel, required this.blokken});

  /// Waar dit menu over gaat. Op een telefoon staat de rij die je lang indrukte onder je duim tegen
  /// de tijd dat het blad omhoog is; zonder kop weet je niet meer wat je vasthoudt.
  final String titel;
  final String? ondertitel;

  final List<List<MenuRegel>> blokken;

  List<List<MenuRegel>> get gevuld => [
        for (final b in blokken)
          if (b.isNotEmpty) b,
      ];

  List<MenuRegel> get regels => [for (final b in gevuld) ...b];
}

/// Welke vorm dit toestel krijgt.
enum MenuVorm {
  /// Van onderaf omhoog: telefoon en televisie.
  blad,

  /// Zwevend bij de aanwijzer: muis en toetsenbord.
  zwevend,
}

/// Een blad op een telefoon en op een tv, een zwevend menu onder een muis.
///
/// `compact` en niet "is dit Android": een pc-venster dat smal getrokken is heeft precies hetzelfde
/// probleem als een telefoon. En op een tv is er geen aanwijzer om iets aan te verankeren, dus is elk
/// zwevend menu daar een gok.
MenuVorm menuVorm({required bool compact, required bool tv}) =>
    compact || tv ? MenuVorm.blad : MenuVorm.zwevend;

/// Hoe lang het zwevende menu erover doet — en dus ook hoe lang de handeling wacht.
const kItemMenuDuur = Duration(milliseconds: 120);

/// Hoe lang Flutters blad erover doet om te sluiten, plus een marge.
///
/// Alleen nodig als de route van het blad niet te pakken is; zie [_viaBlad].
const _bladSluitDuur = Duration(milliseconds: 220);

/// Toon [menu], en voer pas uit wat gekozen is als het menu ECHT weg is.
///
/// [bij] is waar de muis stond bij een rechtsklik. Null betekent: hang aan het aangewezen ding zelf —
/// dat is juist bij een knop, want daar is de knop het anker en een muispositie willekeurig.
Future<void> toonItemMenu(BuildContext context, ItemMenu menu, {Offset? bij}) async {
  final keuze = menuVorm(compact: isCompact(context), tv: isTv) == MenuVorm.blad
      ? await _viaBlad(context, menu)
      : await _viaZwever(context, menu, bij);
  // Een uitgeschakelde regel is niet te kiezen, maar hem hier ook weigeren kost niets en houdt de
  // belofte op één plek staan.
  if (keuze != null && !keuze.uit) keuze.doen();
}

Future<MenuRegel?> _viaBlad(BuildContext context, ItemMenu menu) async {
  ModalRoute<Object?>? route;
  final keuze = await showModalBottomSheet<MenuRegel>(
    context: context,
    // DE HOOFDNAVIGATOR, en dat draagt het geheel.
    //
    // Sinds de secties een eigen navigator binnen de schil hebben, eindigt die navigator bóven de
    // spelerbalk en de onderbalk. Zonder deze regel zou het blad daar vandaan omhoogschuiven en zou
    // zijn waas de balken niet halen — een blad dat halverwege het scherm begint.
    //
    // Mag, omdat de providers bóven de MaterialApp staan. Wat er niet doorheen komt zijn de
    // handelingen, en die zitten al gebonden in de gegevens: zie [MenuRegel.doen].
    useRootNavigator: true,
    // [kBovenop] en niet [kPaneel]: dit blad ligt óver de app, en op de kleur van een gewone rij
    // leest het als een rij die per ongeluk heel groot geworden is.
    backgroundColor: kBovenop,
    // Anders knipt Flutter het blad af op 9/16 van het scherm. Op een Shield van 540 punten met
    // tekstschaal 1,35 zie je dan vijf van de veertien regels.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (bladContext) {
      route ??= ModalRoute.of(bladContext);
      return ItemMenuBlad(menu: menu);
    },
  );

  // PAS HANDELEN ALS HET BLAD WEG IS.
  //
  // `Navigator.pop` is niet genoeg: de toekomst die daaruit komt is al klaar zodra het poppen
  // BEGINT. Zo werkte het oude menu, en daardoor schoof een albumpagina open bovenop een menu dat
  // nog stond dicht te vouwen. `completed` wacht de animatie af én de verwijdering uit de overlay.
  final klaar = route?.completed;
  if (klaar != null) {
    await klaar;
  } else {
    await Future<void>.delayed(_bladSluitDuur);
  }
  return keuze;
}

Future<MenuRegel?> _viaZwever(BuildContext context, ItemMenu menu, Offset? bij) async {
  final laag = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (laag == null) return null;

  Offset punt;
  if (bij != null) {
    punt = laag.globalToLocal(bij);
  } else {
    // Geen muispositie: hang aan het ding zelf, rechts in het midden.
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    punt = box.localToGlobal(box.size.centerRight(Offset.zero), ancestor: laag);
  }

  final keuze = await showMenu<MenuRegel>(
    context: context,
    position: RelativeRect.fromLTRB(
        punt.dx, punt.dy, laag.size.width - punt.dx, laag.size.height - punt.dy),
    // Honderdtwintig milliseconden in plaats van driehonderd, met een curve die meteen doortrekt:
    // de breedte en de hoogte staan dan binnen een handvol beelden op vol en de rest is inkleuren.
    //
    // LET OP: `reverseDuration` doet hier NIETS. `_PopupMenuRoute` overschrijft alleen
    // `transitionDuration`, en het terugvouwen valt daarop terug (routes.dart:148). Wie het menu
    // anders wil laten sluiten moet `reverseCurve` gebruiken.
    popUpAnimationStyle: const AnimationStyle(duration: kItemMenuDuur, curve: Curves.easeOutCubic),
    // Standaard is dit 112 tot 280. Onder de 232 breekt "Toevoegen aan de wachtrij" over twee
    // regels; boven de 300 wordt een menu van korte regels een vlak.
    constraints: const BoxConstraints(minWidth: 232, maxWidth: 300),
    items: itemMenuPosten(menu),
  );

  // Zelfde regel als bij het blad: pas handelen als het weg is. Er valt hier geen route vast te
  // pakken, maar de duur kiezen we zelf, dus die afwachten is precies genoeg.
  await Future<void>.delayed(kItemMenuDuur);
  return keuze;
}

/// De posten voor het zwevende menu: regels met strepen ertussen.
///
/// Openbaar omdat de vorm ervan te meten hoort te zijn: nooit een streep vooraan, nooit een streep
/// achteraan, en nooit twee achter elkaar.
List<PopupMenuEntry<MenuRegel>> itemMenuPosten(ItemMenu menu) {
  final blokken = menu.gevuld;
  return [
    for (var b = 0; b < blokken.length; b++) ...[
      if (b > 0) const PopupMenuDivider(),
      for (final r in blokken[b])
        PopupMenuItem<MenuRegel>(
          value: r,
          enabled: !r.uit,
          height: 40,
          child: Row(children: [
            Icon(r.icoon, size: 17, color: r.uit ? kUitgezet : kGedempt),
            const SizedBox(width: 10),
            Expanded(
                child: Text(r.tekst,
                    style: TextStyle(fontSize: 13.5, color: r.uit ? kUitgezet : null))),
          ]),
        ),
    ],
  ];
}

/// Het menu als blad: een kop, en daaronder de regels op vingerformaat.
///
/// Los van [toonItemMenu] zodat een toets hem kan pompen zonder navigator en zonder providers.
class ItemMenuBlad extends StatelessWidget {
  const ItemMenuBlad({super.key, required this.menu});

  final ItemMenu menu;

  @override
  Widget build(BuildContext context) {
    final blokken = menu.gevuld;
    // Welke regel de markering krijgt op een tv: de eerste die je ook echt kunt kiezen. Zou dat de
    // allereerste regel zijn, dan begon de markering bij een ontbrekend nummer op iets dat uit
    // staat, en dan lijkt de afstandsbediening niets te doen.
    MenuRegel? eerste;
    for (final r in blokken.expand((b) => b)) {
      if (!r.uit) {
        eerste = r;
        break;
      }
    }
    return SafeArea(
      // Een televisie meldt geen inzetten, dus `SafeArea` alleen doet daar niets. Dit is de marge
      // die de onderste regel van de rand van de beeldbuis af houdt.
      minimum: tvOverscan,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * (isTv ? .86 : .78)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(menu.titel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (menu.ondertitel case final s? when s.trim().isNotEmpty)
                    Text(s,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kGedempt, fontSize: 12.5)),
                ],
              ),
            ),
            const Divider(color: kLijn, height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  for (var b = 0; b < blokken.length; b++) ...[
                    if (b > 0)
                      const Divider(color: kLijn, height: 9, indent: 20, endIndent: 20),
                    for (final r in blokken[b])
                      InkWell(
                        // Op een afstandsbediening legt een blad de markering nergens neer, dus zou
                        // de eerste druk op OMLAAG opgaan aan het binnenkomen. Op een telefoon is
                        // dit onzichtbaar: bij aanraking tekent Flutter geen markering.
                        autofocus: isTv && identical(r, eerste),
                        // Null en niet een lege functie: dan tekent Flutter ook geen rimpeling, en
                        // slaat de afstandsbediening hem over in plaats van erop te blijven staan.
                        onTap: r.uit ? null : () => Navigator.pop(context, r),
                        child: Padding(
                          // GEEN vaste hoogte. Op een tv schaalt de tekst 1,35 keer, en dan knipt
                          // een vast getal de regel af; ruimte eromheen groeit gewoon mee.
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          child: Row(children: [
                            Icon(r.icoon, size: 20, color: r.uit ? kUitgezet : kGedempt),
                            const SizedBox(width: 16),
                            Expanded(
                                child: Text(r.tekst,
                                    style: TextStyle(
                                        fontSize: 15, color: r.uit ? kUitgezet : null))),
                          ]),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
