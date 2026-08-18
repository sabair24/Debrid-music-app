# De APK ondertekenen

Zonder dit kun je een nieuwe build niet over de vorige installeren. Android vergelijkt de
handtekening van wat je installeert met die van wat er staat, en weigert als ze niet gelijk zijn —
dus moest de app er eerst af, met je offline kopieën en je login erbij.

De build tekende met de **debug**-sleutel. Die wordt per machine bij eerste gebruik aangemaakt, en
een CI-runner is elke run een nieuwe machine. Elke APK had dus een andere handtekening.

De code is klaar. Wat er nog moet gebeuren is een sleutel maken en hem aan GitHub geven — dat kan
alleen jij doen, want die sleutel hoort van niemand anders te zijn.

## 1. Maak de sleutel

Op de pc, in PowerShell. `keytool` zit bij de JDK die je al hebt staan voor de serverbuild.

```powershell
keytool -genkeypair -v `
  -keystore debridmusic.jks `
  -storetype JKS `
  -keyalg RSA -keysize 4096 -validity 10000 `
  -alias debridmusic
```

Hij vraagt om een wachtwoord en om je naam en plaats. De naamvelden mag je leeg laten of invullen
zoals je wil — ze staan in het certificaat en verder nergens. Onthoud het wachtwoord.

> **Bewaar `debridmusic.jks`.** Raak je hem kwijt, dan kun je nooit meer een update maken voor de
> app die dan geïnstalleerd staat — iedereen moet dan weer één keer verwijderen en opnieuw
> installeren. Zet hem in je wachtwoordkluis of ergens waar je back-ups van maakt. **Niet in deze
> repo**; `.gitignore` houdt hem tegen, maar de regel is: hij hoort er niet in.

## 2. Zet hem om naar tekst

GitHub-secrets zijn tekst, dus het bestand moet als base64:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("debridmusic.jks")) | Set-Clipboard
```

Staat nu op je klembord.

## 3. Geef hem aan GitHub

In deze repo → **Settings → Secrets and variables → Actions → New repository secret**. Vier stuks:

| Naam | Waarde |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | wat er op je klembord staat |
| `ANDROID_KEYSTORE_PASSWORD` | het wachtwoord uit stap 1 |
| `ANDROID_KEY_ALIAS` | `debridmusic` |
| `ANDROID_KEY_PASSWORD` | hetzelfde wachtwoord (keytool gebruikt er standaard één) |

Vanaf de eerstvolgende build is de APK ondertekend.

## 4. Eén keer nog verwijderen

De app die nu op je telefoon staat is met een debug-sleutel ondertekend. De eerste ondertekende
build kan die dus nog steeds niet bijwerken — daar moet één laatste keer verwijderen-en-opnieuw-
installeren tussen.

**Daarna werkt bijwerken gewoon**, zolang die `.jks` blijft bestaan.

## Wat dit niet oplost

De waarschuwing bij het installeren zelf. Die komt doordat je buiten de Play Store om installeert,
en die blijft — Play Protect kent deze app niet en gaat hem ook niet leren kennen zolang hij niet
in de Play Store staat. Ondertekenen lost het *bijwerken* op, niet het *waarschuwen*.

## Zonder de secrets

Dan valt de build terug op de debug-sleutel en zegt dat in het buildlogboek:

```
No release keystore — signing with the debug key. This APK cannot update a signed install.
```

Er breekt dus niets zolang de secrets er nog niet zijn; je zit alleen nog met het oude probleem.
