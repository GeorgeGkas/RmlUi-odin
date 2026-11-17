# Regenerates the Odin packages from deps\RmlUi\Include.
# Downloads LLVM 20.1.8 libclang and builds a pinned odin-c-bindgen on first run.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools = Join-Path $root ".tools"
$bindgenCommit = "12f4e7adb7ff4be1546ff4c3c3a7a42b637a7315"
$bindgenUrl = "https://github.com/karl-zylinski/odin-c-bindgen.git"
$bindgenSrc = Join-Path $tools "odin-c-bindgen"
$llvmArchive = Join-Path $tools "clang+llvm-20.1.8-x86_64-pc-windows-msvc.tar.xz"
$llvmUrl = "https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/clang+llvm-20.1.8-x86_64-pc-windows-msvc.tar.xz"

function Ensure-PinnedRepo([string]$dir, [string]$url, [string]$commit) {
	if (Test-Path (Join-Path $dir ".git")) {
		$head = (git -C $dir rev-parse HEAD).Trim()
		if ($head -eq $commit) { return }
		git -C $dir fetch --depth 1 origin $commit
		if ($LASTEXITCODE -ne 0) { throw "git fetch $url $commit failed." }
		git -C $dir checkout --detach $commit
		if ($LASTEXITCODE -ne 0) { throw "git checkout $commit failed." }
		return
	}
	if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
	New-Item -ItemType Directory -Force -Path $dir | Out-Null
	git -C $dir init
	if ($LASTEXITCODE -ne 0) { throw "git init $dir failed." }
	git -C $dir remote add origin $url
	if ($LASTEXITCODE -ne 0) { throw "git remote add $url failed." }
	git -C $dir fetch --depth 1 origin $commit
	if ($LASTEXITCODE -ne 0) { throw "git fetch $url $commit failed." }
	git -C $dir checkout --detach FETCH_HEAD
	if ($LASTEXITCODE -ne 0) { throw "git checkout $commit failed." }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
	throw "Required tool 'git' was not found on PATH."
}
if (-not (Get-Command odin -ErrorAction SilentlyContinue)) {
	throw "Required tool 'odin' was not found on PATH."
}
if (-not (Test-Path (Join-Path $root "deps\RmlUi\Include\RmlUi\CApi\Core.h"))) {
	throw "Missing deps\RmlUi. From the package root, run: git submodule update --init --recursive"
}

New-Item -ItemType Directory -Force -Path $tools | Out-Null

if (-not (Test-Path (Join-Path $tools "libclang.dll")) -or -not (Test-Path (Join-Path $tools "libclang.lib"))) {
	if (-not (Test-Path $llvmArchive)) {
		Write-Host "Downloading LLVM 20.1.8 (libclang)..."
		curl.exe -L --fail -o $llvmArchive $llvmUrl
		if ($LASTEXITCODE -ne 0) { throw "Download failed: $llvmUrl" }
	}
	Write-Host "Extracting libclang..."
	$extract = Join-Path $tools "llvm-extract"
	if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
	New-Item -ItemType Directory -Force -Path $extract | Out-Null
	tar.exe -xf $llvmArchive -C $extract
	if ($LASTEXITCODE -ne 0) { throw "Failed to extract $llvmArchive" }
	$dll = Get-ChildItem -Path $extract -Recurse -Filter libclang.dll | Select-Object -First 1
	$lib = Get-ChildItem -Path $extract -Recurse -Filter libclang.lib | Select-Object -First 1
	if (-not $dll -or -not $lib) { throw "libclang.dll or libclang.lib was not found in the LLVM archive." }
	Copy-Item $dll.FullName (Join-Path $tools "libclang.dll") -Force
	Copy-Item $lib.FullName (Join-Path $tools "libclang.lib") -Force
	Remove-Item -Recurse -Force $extract
}

Ensure-PinnedRepo $bindgenSrc $bindgenUrl $bindgenCommit

$libclangDir = Join-Path $bindgenSrc "libclang"
New-Item -ItemType Directory -Force -Path $libclangDir | Out-Null
Copy-Item (Join-Path $tools "libclang.lib") (Join-Path $libclangDir "libclang.lib") -Force
Copy-Item (Join-Path $tools "libclang.dll") (Join-Path $bindgenSrc "libclang.dll") -Force

Push-Location $bindgenSrc
try {
	odin build src -out:bindgen.exe
	if ($LASTEXITCODE -ne 0) { throw "Failed to build odin-c-bindgen." }
} finally {
	Pop-Location
}

function Invoke-Bindgen([string]$configDir, [string]$packageDir) {
	$out = Join-Path $configDir "out"
	if (Test-Path $out) { Remove-Item -Recurse -Force $out }
	Push-Location $bindgenSrc
	try {
		$env:PATH = "$tools;$bindgenSrc;" + $env:PATH
		& .\bindgen.exe $configDir
		if ($LASTEXITCODE -ne 0) { throw "bindgen failed for $configDir" }
	} finally {
		Pop-Location
	}
	New-Item -ItemType Directory -Force -Path $packageDir | Out-Null
	Get-ChildItem -Path $packageDir -Filter *.odin | Where-Object { $_.Name -ne "helpers.odin" -and $_.Name -ne "aliases.odin" } | Remove-Item -Force
	Copy-Item (Join-Path $out "*.odin") $packageDir -Force
}

Invoke-Bindgen (Join-Path $root "bindgen\rmlui") (Join-Path $root "rmlui")
Invoke-Bindgen (Join-Path $root "bindgen\rmlui_backend") (Join-Path $root "rmlui_backend")
Write-Host "Generated Odin packages."
