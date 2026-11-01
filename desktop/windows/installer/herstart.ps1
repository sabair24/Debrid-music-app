# Na een stille update (bijwerken vanuit de app): DebridMusic starten en nagaan dat hij echt opkomt.
#
# Waarom (31-10-2026, 3.9.689): de installer startte de app, en dat proces bleef hangen voor zijn eerste regel -- een
# thread, 5 MB, geen venster, niets in start.log -- tot het de volgende ochtend met de hand gestopt werd. 3.9.685 tot en
# met 3.9.688 kwamen dezelfde dag gewoon op. Waarom dat ene keer niet, viel achteraf niet meer te zien (geen melding van
# Defender, niets in de logboeken van Windows). Dit script vangt het op: het eerste wat de app doet is een regel
# "runner: proces <pid> gestart door ..." in start.log (windows/runner/main.cpp). Komt die niet binnen dertig seconden,
# dan weg ermee en opnieuw, hoogstens drie keer.
#
# Wat het deed, staat in %APPDATA%\DebridMusic\bijwerken.log.
param(
  [Parameter(Mandatory = $true)][string]$App,
  [string]$StartLog = (Join-Path $env:APPDATA 'DebridMusic\start.log'),
  [string]$Log = (Join-Path $env:APPDATA 'DebridMusic\bijwerken.log'),
  [int]$Geduld = 30,
  # Voor een proef: een andere procesnaam en argumenten, zodat de echte app nooit geraakt wordt.
  [string]$Naam = 'debridmusic',
  [string]$Argumenten = ''
)

function Regel([string]$tekst) {
  try { Add-Content -Path $Log -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $tekst) -Encoding UTF8 } catch {}
}

# Is dit proces voorbij zijn eerste regel? Dan laadt de app, en de rest staat in start.log.
function Leeft([int]$id) {
  try { return [bool](Select-String -Path $StartLog -Pattern ("runner: proces $id ") -SimpleMatch -Quiet) } catch { return $false }
}

# Kopieen die na [seconden] nog altijd niet voorbij hun eerste regel zijn: die hangen.
function Hangend([int]$seconden) {
  @(Get-Process -Name $Naam -ErrorAction SilentlyContinue | Where-Object {
      -not (Leeft $_.Id) -and $_.StartTime -lt (Get-Date).AddSeconds(-$seconden)
    })
}

for ($poging = 1; $poging -le 3; $poging++) {
  $p = if ($Argumenten) { Start-Process -FilePath $App -ArgumentList $Argumenten -PassThru } else { Start-Process -FilePath $App -PassThru }
  Regel "poging ${poging}: proces $($p.Id) gestart"
  $tot = (Get-Date).AddSeconds($Geduld)
  while ((Get-Date) -lt $tot) {
    Start-Sleep -Milliseconds 500
    if (Leeft $p.Id) {
      Regel "proces $($p.Id) is op"
      # Een eerdere kopie die bleef hangen, hoeft niet te blijven staan.
      foreach ($h in (Hangend 20)) { Regel "proces $($h.Id) hing nog -- gestopt"; Stop-Process -Id $h.Id -Force -ErrorAction SilentlyContinue }
      exit 0
    }
    if ($p.HasExited) {
      # Een tweede kopie meldt zich bij de eerste en sluit zichzelf (_instancePort in main.dart): dan moet die eerste leven.
      $andere = @(Get-Process -Name $Naam -ErrorAction SilentlyContinue | Where-Object { Leeft $_.Id })
      if ($andere.Count -gt 0) { Regel "er draait er al een: $($andere.Id -join ', ')"; exit 0 }
      Regel "proces $($p.Id) sloot zonder op te komen"
      break
    }
  }
  foreach ($h in (Hangend 0)) { Regel "proces $($h.Id) kwam niet op -- gestopt"; Stop-Process -Id $h.Id -Force -ErrorAction SilentlyContinue }
}
Regel 'na drie pogingen niet op'
exit 1
