# Copies bin\windows into the directory given as the first argument.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($args.Count -lt 1 -or [string]::IsNullOrWhiteSpace($args[0])) {
	throw "Usage: stage.ps1 <directory>"
}
$dest = $args[0]
$bin = Join-Path $root "bin\windows"
if (-not (Test-Path $bin)) {
	throw "Missing $bin. Run bootstrap.ps1 first."
}
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $bin "*") $dest -Force
Write-Host "Staged runtime binaries to $dest"
