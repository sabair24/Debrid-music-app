# Builds the DebridMusic Windows desktop app (self-contained, bundled JRE).
# Requires JDK 17+ (uses its jpackage). Output: server\dist\DebridMusic\DebridMusic.exe
#
#   powershell -ExecutionPolicy Bypass -File server\package-windows.ps1
#
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path      # ...\server
$root = Split-Path -Parent $here                              # repo root

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
  --add-modules java.base,java.desktop,java.sql,java.naming,java.xml,java.management,java.logging,jdk.unsupported,java.net.http

Write-Host "`nBuilt: $dist\DebridMusic\DebridMusic.exe"
