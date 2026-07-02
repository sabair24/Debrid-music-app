# Builds the DebridMusic Windows desktop app (self-contained, bundled JRE).
# Requires JDK 17+ (uses its jpackage). Outputs:
#   server\dist\DebridMusic\DebridMusic.exe          (portable app-image folder)
#   server\installer\DebridMusic-<v>.exe             (installer, if WiX 3.x is found)
#
#   powershell -ExecutionPolicy Bypass -File server\package-windows.ps1
#
# For the installer, WiX 3.14 must be on PATH or extracted to C:\Users\<you>\wix314
# (download wix314-binaries.zip from github.com/wixtoolset/wix3/releases).
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path      # ...\server
$root = Split-Path -Parent $here                              # repo root
$MODULES = 'java.base,java.desktop,java.sql,java.naming,java.xml,java.management,java.logging,jdk.unsupported,java.net.http,jdk.crypto.ec,jdk.crypto.cryptoki'

# 1. Fat JAR (web UI + casting bundled in).
Push-Location $root
& .\gradlew.bat -p server shadowJar --console=plain
Pop-Location

# 2. jpackage -> self-contained Windows app-image.
$jpackage = Join-Path $env:JAVA_HOME 'bin\jpackage.exe'
if (-not (Test-Path $jpackage)) { throw "jpackage not found at $jpackage (set JAVA_HOME to a JDK 17+)" }

$dist = Join-Path $here 'dist'
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }

$iconArg = @()
$icon = Join-Path $here 'build-res\icon.ico'
if (Test-Path $icon) { $iconArg = @('--icon', $icon) }

& $jpackage `
  --type app-image `
  --name DebridMusic `
  --input (Join-Path $here 'build\libs') `
  --main-jar musicserver.jar `
  --main-class com.debridmusic.server.DesktopMain `
  --dest $dist `
  --app-version 0.1.0 `
  --vendor 'DebridMusic' `
  --java-options '-Xmx768m' `
  @iconArg `
  --add-modules $MODULES

Write-Host "`nBuilt app-image: $dist\DebridMusic\DebridMusic.exe"

# 3. Installer (.exe) — only if WiX 3.x is available.
$wixLocal = Join-Path $env:USERPROFILE 'wix314'
if ((Get-Command candle.exe -ErrorAction SilentlyContinue) -eq $null -and (Test-Path (Join-Path $wixLocal 'candle.exe'))) {
    $env:PATH = "$wixLocal;$env:PATH"
}
if (Get-Command candle.exe -ErrorAction SilentlyContinue) {
    $inst = Join-Path $here 'installer'
    if (Test-Path $inst) { Remove-Item $inst -Recurse -Force }
    & $jpackage `
      --type exe `
      --name DebridMusic `
      --input (Join-Path $here 'build\libs') `
      --main-jar musicserver.jar `
      --main-class com.debridmusic.server.DesktopMain `
      --dest $inst `
      --app-version 1.0.0 `
      --vendor 'DebridMusic' `
      --description 'DebridMusic - your personal music hub' `
      --java-options '-Xmx768m' `
      @iconArg `
      --add-modules $MODULES `
      --win-shortcut --win-menu --win-menu-group 'DebridMusic' --win-dir-chooser --win-per-user-install
    Write-Host "Built installer: $inst\DebridMusic-1.0.0.exe"
} else {
    Write-Host "WiX not found -> skipped installer (extract wix314-binaries.zip to $wixLocal to enable)."
}
