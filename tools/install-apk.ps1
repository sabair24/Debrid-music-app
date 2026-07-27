# Zet de nieuwste getekende DebridMusic-APK op een aangesloten telefoon.
#
# Waarom dit bestaat: Play Protect scant een APK die Google nog nooit heeft gezien en blokkeert de
# installatie in de installer-UI ("Geblokkeerd om je telefoon te beschermen"). Die stap zit ALLEEN
# in die UI. Over de kabel installeert Android het pakket rechtstreeks, en de gewone
# pakketverificatie -- die wel meeloopt -- keurt de app goed. Gemeten: met
# verifier_verify_adb_installs op 1, dus strenger dan standaard, ging de installatie gewoon door.
#
# Gebruik:   powershell -ExecutionPolicy Bypass -File tools\install-apk.ps1
#            powershell -ExecutionPolicy Bypass -File tools\install-apk.ps1 -Apk C:\pad\naar.apk

param(
  [string]$Apk = '',
  [string]$Repo = 'sabair24/Debrid-music-app-releases'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Find-Tool([string]$naam, [string[]]$paden) {
  $c = Get-Command $naam -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  foreach ($p in $paden) { if (Test-Path $p) { return $p } }
  return $null
}

$adb = Find-Tool 'adb' @(
  "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
  "$env:USERPROFILE\AppData\Local\Android\Sdk\platform-tools\adb.exe",
  'C:\Android\platform-tools\adb.exe'
)
if (-not $adb) {
  Write-Host 'adb niet gevonden. Installeer de Android platform-tools of zet adb in je PATH.' -ForegroundColor Red
  exit 1
}

# Telefoon aangesloten?
$devices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' }
if (-not $devices) {
  Write-Host 'Geen telefoon gevonden.' -ForegroundColor Red
  Write-Host 'Zet USB-foutopsporing aan (Instellingen > Ontwikkelaarsopties) en sluit de kabel aan.'
  Write-Host 'Staat er "unauthorized"? Kijk dan op het scherm van de telefoon: daar staat een vraag.'
  exit 1
}
$model = (& $adb shell getprop ro.product.model).Trim()
Write-Host "Telefoon: $model"

# De APK ophalen, tenzij er al een is meegegeven.
if (-not $Apk) {
  Write-Host "Nieuwste release zoeken in $Repo ..."
  $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases?per_page=10" -Headers @{'User-Agent' = 'debridmusic-installer' }
  $hit = $rel | Where-Object { $_.assets | Where-Object { $_.name -like '*.apk' } } | Select-Object -First 1
  if (-not $hit) { Write-Host 'Geen release met een APK gevonden.' -ForegroundColor Red; exit 1 }
  $asset = $hit.assets | Where-Object { $_.name -like '*.apk' } | Select-Object -First 1
  $Apk = Join-Path $env:TEMP $asset.name
  Write-Host ("Downloaden: {0} ({1} MB)" -f $asset.name, [math]::Round($asset.size / 1MB, 1))
  Invoke-WebRequest $asset.browser_download_url -OutFile $Apk -UseBasicParsing
}

# Nooit een debug-getekende APK installeren. Zo een kun je daarna niet bijwerken naar de echte:
# Android weigert een update met een andere sleutel, en dan moet je eerst verwijderen.
$bt = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" -Directory -ErrorAction SilentlyContinue |
Sort-Object Name -Descending | Select-Object -First 1
if ($bt) {
  $apksigner = Join-Path $bt.FullName 'apksigner.bat'
  if (Test-Path $apksigner) {
    $dn = & $apksigner verify --print-certs $Apk 2>&1 | Select-String 'certificate DN'
    Write-Host ("Ondertekend door: " + ($dn -replace '.*certificate DN: ', ''))
    if ($dn -match 'Android Debug') {
      Write-Host 'Dit is de Android-debugsleutel, niet jouw sleutel. Niet installeren.' -ForegroundColor Red
      exit 1
    }
  }
}
else {
  Write-Host 'Geen build-tools gevonden, handtekening niet gecontroleerd.' -ForegroundColor Yellow
}

Write-Host 'Installeren ...'
$out = & $adb install -r $Apk 2>&1
$out | ForEach-Object { Write-Host "  $_" }
if ($out -match 'Success') {
  Write-Host 'Klaar. De app staat op je telefoon.' -ForegroundColor Green
  exit 0
}
if ($out -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
  Write-Host 'Er staat een versie op met een andere sleutel (waarschijnlijk een oude debug-build).' -ForegroundColor Yellow
  Write-Host 'Verwijder die eerst op de telefoon, en draai dit script opnieuw.'
}
exit 1
