# Builds the sample and copies runtime binaries next to the executable.
$ErrorActionPreference = "Stop"
$sample = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = (Resolve-Path (Join-Path $sample "..\..")).Path
$out = Join-Path $sample "basic.exe"
odin build $sample -out:$out
if ($LASTEXITCODE -ne 0) { throw "odin build failed" }
& (Join-Path $root "stage.ps1") $sample
Write-Host "Built $out"
