# Checks that Odin's string matches {const char*, size_t} by value, as the RmlStringView override assumes.
$ErrorActionPreference = "Stop"
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
	$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
	if (-not (Test-Path $vswhere)) { throw "cl.exe is not on PATH and Visual Studio was not found." }
	$vsInstall = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -version "[17.0,19.0)" -property installationPath
	if (-not $vsInstall) { throw "cl.exe is not on PATH and Visual Studio was not found." }
	Import-Module (Join-Path $vsInstall "Common7\Tools\Microsoft.VisualStudio.DevShell.dll")
	Enter-VsDevShell -VsInstallPath $vsInstall -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64" | Out-Null
}

Push-Location $dir
try {
	cl.exe /nologo /LD abi.c /Feabi.dll
	if ($LASTEXITCODE -ne 0) { throw "cl.exe failed to build abi.dll" }
	odin build . -out:abi.exe
	if ($LASTEXITCODE -ne 0) { throw "odin build failed" }
	.\abi.exe
	if ($LASTEXITCODE -ne 0) { throw "ABI test failed" }
} finally {
	Pop-Location
}
