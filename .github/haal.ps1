# Een bestand ophalen dat niet de eerste keer hoeft te lukken.
#
# De release van 3.2.1 sneuvelde op "Download VC++ Redistributable": aka.ms antwoordde die ene keer
# niet, en daarmee was een build waar niets mis mee was verloren. Een enkele hik van een externe
# server hoort geen release te kosten -- vier pogingen met oplopende pauze dekken precies dat, en
# blijven kort genoeg dat een server die ECHT weg is de build gewoon laat falen in plaats van hem
# tien minuten te laten hangen.
function Haal {
    param(
        [Parameter(Mandatory = $true)][string] $Url,
        [Parameter(Mandatory = $true)][string] $Uit,
        [int] $Pogingen = 4
    )
    for ($i = 1; $i -le $Pogingen; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Uit -UseBasicParsing -TimeoutSec 120
            $mb = [math]::Round((Get-Item $Uit).Length / 1MB, 1)
            Write-Host "opgehaald: $Url ($mb MB, poging $i)"
            return
        } catch {
            Write-Host "poging $i van $Pogingen mislukt voor ${Url}: $($_.Exception.Message)"
            if ($i -eq $Pogingen) { throw }
            Start-Sleep -Seconds (5 * $i)
        }
    }
}
