# Werkafspraken voor deze app

## Uitgeven: niet vragen, doen

**Is de bouw groen, dan volgt samenvoegen en releasen. Zonder tussenvraag.**

Dat is met zoveel woorden gevraagd ("na build altijd mergen en releasen"), en het is ook de
snelste weg naar het enige oordeel dat telt: de app op het toestel. Wachten op "merge en
release" kost een ronde en levert niets op wat de bouw niet al zei.

De volgorde:

1. Werk op een `claude/**`-tak. Dat is de enige tak waar de sessie naartoe mag pushen, en de
   bouwstraat draait erop.
2. Bouw groen? Dan de PR uit concept halen en samenvoegen (squash) naar
   `feat/windows-desktop-app` — de standaardtak.
3. Releasen is een lege commit op de tak `claude/release`. `release.yml` pakt die op, zoekt zelf
   het volgende versienummer, zet de tag `win-vX.Y.Z` en start de drie bouwen (Android, Windows,
   Apple). Een tag is de enige weg naar buiten; `main` publiceert niets meer.
4. Melden welk **buildnummer** eruit komt, want dat is wat er in de update-melding op de telefoon
   staat.

Uitzondering, en alleen deze: een wijziging die niets aan de app verandert (documentatie, een
bouwstraatbestand dat geen code raakt) wordt wél samengevoegd maar wacht op de eerstvolgende
echte release. Drie platformen bouwen voor een tekstbestand is verspilling — dat hoort gezegd te
worden, niet stilletjes anders gedaan.

**Bouw rood?** Eerst lezen wat er staat. Een 429 van Maven Central of een weggevallen runner is
geen fout in de code en mag opnieuw; al het andere wordt uitgezocht voordat er iets samengevoegd
wordt. Een toets uitzetten om groen te worden is nooit de oplossing.

## Sleutels

De ondertekensleutel wordt **nooit** hier aangemaakt — die zou dan door de chat lopen. Hij komt
uit de repository-secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, en het wachtwoord
onder `ANDROID_STORE_PASSWORD` óf `ANDROID_KEYSTORE_PASSWORD`). In logs alleen of een geheim er
is, nooit wat erin staat. Een release met de debug-sleutel is fataal en breekt de bouw expres af:
een APK met een andere sleutel is geen update maar een tweede app.

## Toetsen

Hier draait geen Flutter, dus de bouwstraat is de compiler. `build-release.yml` draait op elke
`claude/**`-tak een handvol toetsen die zonder toestel en zonder netwerk iets kunnen zeggen; een
nieuw toetsbestand dat niet in die lijst staat, draait nooit. De Apple-bouw draait de rest, maar
alleen op een tag — een kapotte toets komt daar dus pas tijdens het uitgeven aan het licht.
