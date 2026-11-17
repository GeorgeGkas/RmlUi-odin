# Regenerates the Odin bindings, then builds shared rmlui_capi and rmlui_capi_backend (SDL_GL3).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$vcpkgCommit = "3af1d1e60af2b2abf55760538cd607829029b07a"
$vcpkgUrl = "https://github.com/microsoft/vcpkg.git"
$vcpkgDir = Join-Path $root ".tools\vcpkg"
$deps = Join-Path $root "deps\RmlUi"
$build = Join-Path $root "build"
$dist = Join-Path $build "dist"

function Require-Tool([string]$name) {
	if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
		throw "Required tool '$name' was not found on PATH."
	}
}

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

function Resolve-DistFile([string]$name) {
	$direct = Join-Path $dist $name
	if (Test-Path $direct) { return $direct }
	$release = Join-Path $dist "Release\$name"
	if (Test-Path $release) { return $release }
	return $null
}

Require-Tool "git"
Require-Tool "odin"

if (-not (Test-Path (Join-Path $deps "CMakeLists.txt"))) {
	throw "Missing $deps. From the package root, run: git submodule update --init --recursive"
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
	throw "Visual Studio 2022 with the Desktop development with C++ workload was not found. Install that workload."
}
$vsInstall = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -version "[17.0,18.0)" -property installationPath
if (-not $vsInstall) {
	throw "Visual Studio 2022 with the Desktop development with C++ workload was not found. Install that workload."
}
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
	$vsCMake = Join-Path $vsInstall "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
	if (Test-Path (Join-Path $vsCMake "cmake.exe")) {
		$env:PATH = "$vsCMake;$env:PATH"
	}
}
Require-Tool "cmake"

& (Join-Path $root "generate.ps1")

New-Item -ItemType Directory -Force -Path (Join-Path $root ".tools") | Out-Null
Ensure-PinnedRepo $vcpkgDir $vcpkgUrl $vcpkgCommit

$bootstrapBat = Join-Path $vcpkgDir "bootstrap-vcpkg.bat"
cmd /c "`"$bootstrapBat`""
if ($LASTEXITCODE -ne 0) { throw "bootstrap-vcpkg.bat failed: $bootstrapBat" }

$toolchain = Join-Path $vcpkgDir "scripts\buildsystems\vcpkg.cmake"
$cmakeArgs = @(
	"-G", "Visual Studio 17 2022",
	"-A", "x64",
	"-S", $deps,
	"-B", $build,
	"-DBUILD_SHARED_LIBS=ON",
	"-DBUILD_TESTING=OFF",
	"-DRMLUI_SAMPLES=OFF",
	"-DRMLUI_CAPI=ON",
	"-DRMLUI_CAPI_BACKEND=ON",
	"-DRMLUI_BACKEND=SDL_GL3",
	"-DRMLUI_SDL_VERSION_MAJOR=3",
	"-DRMLUI_FONT_ENGINE=freetype",
	"-DCMAKE_BUILD_TYPE=Release",
	"-DCMAKE_TOOLCHAIN_FILE=$toolchain",
	"-DVCPKG_MANIFEST_DIR=$root",
	"-DVCPKG_TARGET_TRIPLET=x64-windows",
	"-DCMAKE_RUNTIME_OUTPUT_DIRECTORY=$dist",
	"-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=$dist",
	"-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY=$dist",
	"-DCMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE=$dist",
	"-DCMAKE_LIBRARY_OUTPUT_DIRECTORY_RELEASE=$dist",
	"-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELEASE=$dist"
)
& cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) {
	throw "CMake configure failed. Command: cmake $($cmakeArgs -join ' ')"
}

& cmake --build $build --config Release --target rmlui_capi --target rmlui_capi_backend
if ($LASTEXITCODE -ne 0) {
	throw "CMake build failed. Command: cmake --build $build --config Release --target rmlui_capi --target rmlui_capi_backend"
}

$coreLib = Join-Path $root "rmlui\lib\windows"
$backendLib = Join-Path $root "rmlui_backend\lib\windows"
$bin = Join-Path $root "bin\windows"
New-Item -ItemType Directory -Force -Path $coreLib, $backendLib, $bin | Out-Null

$coreImport = Resolve-DistFile "rmlui_capi.lib"
$backendImport = Resolve-DistFile "rmlui_capi_backend.lib"
if (-not $coreImport -or -not $backendImport) {
	throw "Build did not produce rmlui_capi.lib and rmlui_capi_backend.lib in $dist."
}
Copy-Item $coreImport $coreLib -Force
Copy-Item $backendImport $backendLib -Force

foreach ($name in @(
	"rmlui_capi.dll", "rmlui_capi_backend.dll", "rmlui.dll", "rmlui_debugger.dll",
	"rmlui_capi.pdb", "rmlui_capi_backend.pdb", "rmlui.pdb", "rmlui_debugger.pdb")) {
	$path = Resolve-DistFile $name
	if ($path) { Copy-Item $path $bin -Force }
}

$vcpkgBin = Join-Path $build "vcpkg_installed\x64-windows\bin"
if (Test-Path $vcpkgBin) {
	Copy-Item (Join-Path $vcpkgBin "*.dll") $bin -Force
	Get-ChildItem $vcpkgBin -Filter "*.pdb" -ErrorAction SilentlyContinue | Copy-Item -Destination $bin -Force
}

foreach ($name in @("rmlui_capi.dll", "rmlui_capi_backend.dll", "rmlui.dll", "rmlui_debugger.dll")) {
	if (-not (Test-Path (Join-Path $bin $name))) {
		throw "Build did not produce $name in $dist."
	}
}
if (-not (Get-ChildItem $bin -Filter "freetype*.dll" -ErrorAction SilentlyContinue)) {
	throw "Build did not produce a FreeType DLL in $bin."
}
if (-not (Get-ChildItem $bin -Filter "SDL3.dll" -ErrorAction SilentlyContinue)) {
	throw "Build did not produce SDL3.dll in $bin."
}
Write-Host "Bootstrap complete. Runtime binaries are in $bin"
