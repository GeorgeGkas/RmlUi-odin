# Regenerates the Odin bindings, then builds shared rmlui_capi and rmlui_capi_backend (SDL_GL3).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$vcpkgCommit = "3af1d1e60af2b2abf55760538cd607829029b07a"
$vcpkgUrl = "https://github.com/microsoft/vcpkg.git"
$vcpkgDir = Join-Path $root ".tools\vcpkg"
$deps = Join-Path $root "deps\RmlUi"
$build = Join-Path $root "build"
$dist = Join-Path $build "dist"
$triplet = "x64-windows-release"

function Require-Tool([string]$name) {
	if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
		throw "Required tool '$name' was not found on PATH."
	}
}

# Git is always pointed at $dir\.git explicitly. With `git -C`, a broken checkout would make git
# fall through to an enclosing repository, such as a project that vendors this package.
function Ensure-PinnedRepo([string]$dir, [string]$url, [string]$commit) {
	$gitDir = Join-Path $dir ".git"
	if (Test-Path $gitDir) {
		$head = git --git-dir=$gitDir rev-parse -q --verify HEAD
		if ($LASTEXITCODE -eq 0 -and "$head".Trim() -eq $commit) { return }
		git --git-dir=$gitDir --work-tree=$dir fetch --depth 1 $url $commit
		if ($LASTEXITCODE -eq 0) {
			git --git-dir=$gitDir --work-tree=$dir checkout --detach FETCH_HEAD
			if ($LASTEXITCODE -eq 0) { return }
		}
		Write-Host "Re-cloning $dir."
	}
	if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
	git init -q $dir
	if ($LASTEXITCODE -ne 0) { throw "git init $dir failed." }
	git --git-dir=$gitDir remote add origin $url
	if ($LASTEXITCODE -ne 0) { throw "git remote add $url failed." }
	git --git-dir=$gitDir --work-tree=$dir fetch --depth 1 $url $commit
	if ($LASTEXITCODE -ne 0) { throw "git fetch $url $commit failed." }
	git --git-dir=$gitDir --work-tree=$dir checkout --detach FETCH_HEAD
	if ($LASTEXITCODE -ne 0) { throw "git checkout $commit failed." }
}

function Restore-Environment([hashtable]$saved) {
	foreach ($name in @(Get-ChildItem env: | ForEach-Object Name)) {
		if (-not $saved.ContainsKey($name)) {
			Remove-Item -LiteralPath "env:$name"
		}
	}
	foreach ($name in $saved.Keys) {
		[Environment]::SetEnvironmentVariable($name, $saved[$name])
	}
}

# Enter-VsDevShell changes the environment of the calling session, so it is restored on exit.
$savedEnvironment = @{}
Get-ChildItem env: | ForEach-Object { $savedEnvironment[$_.Name] = $_.Value }

try {
	Require-Tool "git"
	Require-Tool "odin"

	if (-not (Test-Path (Join-Path $deps "CMakeLists.txt"))) {
		throw "Missing $deps. From the package root, run: git submodule update --init --recursive"
	}

	$vsMissing = "Visual Studio 2022 or 2026 with the Desktop development with C++ workload was not found. Install that workload."
	$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
	if (-not (Test-Path $vswhere)) { throw $vsMissing }
	$vsInstall = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -version "[17.0,19.0)" -property installationPath
	if (-not $vsInstall) { throw $vsMissing }
	Import-Module (Join-Path $vsInstall "Common7\Tools\Microsoft.VisualStudio.DevShell.dll")
	Enter-VsDevShell -VsInstallPath $vsInstall -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64" | Out-Null
	Require-Tool "cl"
	Require-Tool "cmake"
	Require-Tool "ninja"

	& (Join-Path $root "generate.ps1")

	New-Item -ItemType Directory -Force -Path (Join-Path $root ".tools") | Out-Null
	Ensure-PinnedRepo $vcpkgDir $vcpkgUrl $vcpkgCommit

	& (Join-Path $vcpkgDir "bootstrap-vcpkg.bat") -disableMetrics
	if ($LASTEXITCODE -ne 0) { throw "bootstrap-vcpkg.bat failed." }

	# Earlier versions of this script configured build\ with the Visual Studio generator.
	$cache = Join-Path $build "CMakeCache.txt"
	if (Test-Path $cache) {
		$generator = Select-String -Path $cache -Pattern "^CMAKE_GENERATOR:INTERNAL=(.*)$" | Select-Object -First 1
		if ($generator -and $generator.Matches[0].Groups[1].Value -ne "Ninja") {
			Remove-Item -Force $cache
			$cmakeFiles = Join-Path $build "CMakeFiles"
			if (Test-Path $cmakeFiles) { Remove-Item -Recurse -Force $cmakeFiles }
		}
	}

	$cmakeArgs = @(
		"-G", "Ninja",
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
		"-DCMAKE_TOOLCHAIN_FILE=$(Join-Path $vcpkgDir "scripts\buildsystems\vcpkg.cmake")",
		"-DVCPKG_MANIFEST_DIR=$root",
		"-DVCPKG_TARGET_TRIPLET=$triplet",
		"-DVCPKG_OVERLAY_TRIPLETS=$(Join-Path $root "triplets")",
		"-DCMAKE_RUNTIME_OUTPUT_DIRECTORY=$dist",
		"-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=$dist",
		"-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY=$dist"
	)
	& cmake @cmakeArgs
	if ($LASTEXITCODE -ne 0) {
		throw "CMake configure failed. Command: cmake $($cmakeArgs -join ' ')"
	}

	& cmake --build $build --target rmlui_capi --target rmlui_capi_backend
	if ($LASTEXITCODE -ne 0) {
		throw "CMake build failed. Command: cmake --build $build --target rmlui_capi --target rmlui_capi_backend"
	}

	$coreLib = Join-Path $root "rmlui\lib\windows"
	$backendLib = Join-Path $root "rmlui_backend\lib\windows"
	$bin = Join-Path $root "bin\windows"
	foreach ($dir in @($coreLib, $backendLib, $bin)) {
		if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
		New-Item -ItemType Directory -Force -Path $dir | Out-Null
	}

	foreach ($pair in @(@("rmlui_capi.lib", $coreLib), @("rmlui_capi_backend.lib", $backendLib))) {
		$path = Join-Path $dist $pair[0]
		if (-not (Test-Path $path)) { throw "Build did not produce $($pair[0]) in $dist." }
		Copy-Item $path $pair[1] -Force
	}

	foreach ($name in @("rmlui_capi", "rmlui_capi_backend", "rmlui", "rmlui_debugger")) {
		$dll = Join-Path $dist "$name.dll"
		if (-not (Test-Path $dll)) { throw "Build did not produce $name.dll in $dist." }
		Copy-Item $dll $bin -Force
		$pdb = Join-Path $dist "$name.pdb"
		if (Test-Path $pdb) { Copy-Item $pdb $bin -Force }
	}

	$vcpkgBin = Join-Path $build "vcpkg_installed\$triplet\bin"
	if (-not (Get-ChildItem $vcpkgBin -Filter "*.dll" -ErrorAction SilentlyContinue)) {
		throw "No DLLs found in $vcpkgBin."
	}
	Copy-Item (Join-Path $vcpkgBin "*.dll") $bin -Force
	Get-ChildItem $vcpkgBin -Filter "*.pdb" -ErrorAction SilentlyContinue | Copy-Item -Destination $bin -Force

	foreach ($pattern in @("freetype*.dll", "SDL3.dll", "SDL3_image.dll")) {
		if (-not (Get-ChildItem $bin -Filter $pattern -ErrorAction SilentlyContinue)) {
			throw "Build did not produce $pattern in $bin."
		}
	}
	Write-Host "Bootstrap complete. Runtime binaries are in $bin"
} finally {
	Restore-Environment $savedEnvironment
}
