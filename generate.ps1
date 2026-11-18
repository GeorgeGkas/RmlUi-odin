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
$llvmSha256 = "f229769f11d6a6edc8ada599c0cda964b7dee6ab1a08c6cf9dd7f513e85b107f"

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

# Runs a program with stdout and stderr captured to $log. Windows PowerShell turns redirected native
# stderr into terminating errors under $ErrorActionPreference = "Stop", so this bypasses the pipeline.
function Invoke-Logged([string]$exe, [string]$arguments, [string]$workingDirectory, [string]$log) {
	$info = New-Object System.Diagnostics.ProcessStartInfo
	$info.FileName = $exe
	$info.Arguments = $arguments
	$info.WorkingDirectory = $workingDirectory
	$info.UseShellExecute = $false
	$info.RedirectStandardOutput = $true
	$info.RedirectStandardError = $true
	$process = [System.Diagnostics.Process]::Start($info)
	$stderr = $process.StandardError.ReadToEndAsync()
	$stdout = $process.StandardOutput.ReadToEnd()
	$process.WaitForExit()
	Set-Content -Path $log -Value ($stdout + $stderr.Result)
	return $process.ExitCode
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
		$partial = "$llvmArchive.partial"
		Write-Host "Downloading LLVM 20.1.8 (libclang)..."
		curl.exe -L --fail -o $partial $llvmUrl
		if ($LASTEXITCODE -ne 0) {
			Remove-Item -Force $partial -ErrorAction SilentlyContinue
			throw "Download failed: $llvmUrl"
		}
		$hash = (Get-FileHash -Algorithm SHA256 $partial).Hash.ToLowerInvariant()
		if ($hash -ne $llvmSha256) {
			Remove-Item -Force $partial
			throw "Checksum mismatch for $llvmUrl. Expected $llvmSha256, got $hash."
		}
		Move-Item -Force $partial $llvmArchive
	}
	Write-Host "Extracting libclang..."
	$extract = Join-Path $tools "llvm-extract"
	if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
	New-Item -ItemType Directory -Force -Path $extract | Out-Null
	tar.exe -xf $llvmArchive -C $extract "*/bin/libclang.dll" "*/lib/libclang.lib"
	if ($LASTEXITCODE -ne 0) { throw "Failed to extract libclang from $llvmArchive" }
	$dll = Get-ChildItem -Path $extract -Recurse -Filter libclang.dll | Select-Object -First 1
	$lib = Get-ChildItem -Path $extract -Recurse -Filter libclang.lib | Select-Object -First 1
	if (-not $dll -or -not $lib) { throw "libclang.dll or libclang.lib was not found in the LLVM archive." }
	Copy-Item $dll.FullName (Join-Path $tools "libclang.dll") -Force
	Copy-Item $lib.FullName (Join-Path $tools "libclang.lib") -Force
	Remove-Item -Recurse -Force $extract
	Remove-Item -Force $llvmArchive
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

# odin-c-bindgen exits 0 even when clang fails to parse a header, so its log is checked for errors.
function Invoke-Bindgen([string]$configDir, [string]$packageDir) {
	$out = Join-Path $configDir "out"
	$log = Join-Path $tools "$(Split-Path -Leaf $packageDir)-bindgen.log"
	if (Test-Path $out) { Remove-Item -Recurse -Force $out }
	$exitCode = Invoke-Logged (Join-Path $bindgenSrc "bindgen.exe") "`"$configDir`"" $bindgenSrc $log
	if ($exitCode -ne 0) {
		Get-Content $log | Write-Host
		throw "bindgen failed for $configDir"
	}
	$errors = Select-String -Path $log -Pattern "[ERROR]" -SimpleMatch
	if ($errors) {
		$errors | ForEach-Object { Write-Host $_.Line }
		throw "bindgen reported errors for $configDir. Full log: $log"
	}
	$generated = Get-ChildItem -Path $out -Filter *.odin -ErrorAction SilentlyContinue
	if (-not $generated) { throw "bindgen produced no files in $out." }
	New-Item -ItemType Directory -Force -Path $packageDir | Out-Null
	Get-ChildItem -Path $packageDir -Filter *.odin | Where-Object { $_.Name -ne "helpers.odin" -and $_.Name -ne "aliases.odin" } | Remove-Item -Force
	$generated | Copy-Item -Destination $packageDir -Force
}

Invoke-Bindgen (Join-Path $root "bindgen\rmlui") (Join-Path $root "rmlui")
Invoke-Bindgen (Join-Path $root "bindgen\rmlui_backend") (Join-Path $root "rmlui_backend")
Write-Host "Generated Odin packages."
