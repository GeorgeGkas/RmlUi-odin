#!/bin/sh
# Regenerates the Odin packages from deps/RmlUi/Include.
# Builds a pinned odin-c-bindgen. Linux and macOS need libclang 16+ installed.
set -eu
root=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
tools="$root/.tools"
bindgen_commit="12f4e7adb7ff4be1546ff4c3c3a7a42b637a7315"
bindgen_url="https://github.com/karl-zylinski/odin-c-bindgen.git"
bindgen_src="$tools/odin-c-bindgen"
min_llvm_major=16

# Git is always pointed at $dir/.git explicitly. With `git -C`, a broken checkout would make git
# fall through to an enclosing repository, such as a project that vendors this package.
ensure_pinned_repo() {
	dir="$1"
	url="$2"
	commit="$3"
	if [ -d "$dir/.git" ]; then
		head=$(git --git-dir="$dir/.git" rev-parse -q --verify HEAD 2>/dev/null || true)
		if [ "$head" = "$commit" ]; then
			return
		fi
		if git --git-dir="$dir/.git" --work-tree="$dir" fetch --depth 1 "$url" "$commit" &&
			git --git-dir="$dir/.git" --work-tree="$dir" checkout --detach FETCH_HEAD; then
			return
		fi
		echo "Re-cloning $dir." >&2
	fi
	rm -rf "$dir"
	git init -q "$dir"
	git --git-dir="$dir/.git" remote add origin "$url"
	git --git-dir="$dir/.git" --work-tree="$dir" fetch --depth 1 "$url" "$commit"
	git --git-dir="$dir/.git" --work-tree="$dir" checkout --detach FETCH_HEAD
}

# Prints the LLVM major version encoded in a path such as /usr/lib/llvm-18/lib or .../opt/llvm@18/lib.
llvm_major_from_path() {
	printf '%s\n' "$1" | sed -n 's|.*llvm[-@]\([0-9][0-9]*\).*|\1|p'
}

# Prints the first directory that contains a usable libclang, newest versions first.
find_libclang_dir() {
	candidates=""
	case "$(uname -s)" in
		Linux)
			lib_name="libclang.so"
			if command -v llvm-config >/dev/null 2>&1; then
				candidates=$(llvm-config --libdir)
			fi
			candidates="$candidates $(printf '%s\n' /usr/lib/llvm-*/lib | sort -t- -k2 -n -r)"
			;;
		Darwin)
			lib_name="libclang.dylib"
			if command -v brew >/dev/null 2>&1; then
				brew_prefix=$(brew --prefix)
				candidates="$brew_prefix/opt/llvm/lib $(printf '%s\n' "$brew_prefix"/opt/llvm@*/lib | sort -t@ -k2 -n -r)"
			fi
			if command -v xcode-select >/dev/null 2>&1; then
				developer_dir=$(xcode-select -p 2>/dev/null || true)
				candidates="$candidates $developer_dir/usr/lib $developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/lib"
			fi
			;;
	esac
	for dir in $candidates; do
		if [ ! -e "$dir/$lib_name" ]; then
			continue
		fi
		major=$(llvm_major_from_path "$dir")
		if [ -n "$major" ] && [ "$major" -lt "$min_llvm_major" ]; then
			continue
		fi
		printf '%s\n' "$dir"
		return
	done
}

if ! command -v git >/dev/null 2>&1; then
	echo "Required tool 'git' was not found on PATH." >&2
	exit 1
fi
if ! command -v odin >/dev/null 2>&1; then
	echo "Required tool 'odin' was not found on PATH." >&2
	exit 1
fi
if [ ! -f "$root/deps/RmlUi/Include/RmlUi/CApi/Core.h" ]; then
	echo "Missing $root/deps/RmlUi. From the package root, run: git submodule update --init --recursive" >&2
	exit 1
fi

mkdir -p "$tools"
ensure_pinned_repo "$bindgen_src" "$bindgen_url" "$bindgen_commit"

# odin-c-bindgen links system:clang, which is often not on the default linker path.
libclang_dir=$(find_libclang_dir)
if [ -n "$libclang_dir" ]; then
	echo "Using libclang from $libclang_dir"
	link_flags="-extra-linker-flags:-L$libclang_dir -Wl,-rpath,$libclang_dir"
else
	link_flags=""
fi

if ! (cd "$bindgen_src" && odin build src -out:bindgen.bin ${link_flags:+"$link_flags"}); then
	echo "Failed to build odin-c-bindgen. Install libclang $min_llvm_major or newer and re-run." >&2
	echo "Linux: libclang-dev (Debian/Ubuntu) or clang-devel (Fedora)." >&2
	echo "macOS: brew install llvm" >&2
	exit 1
fi

# Without a sysroot, libclang on macOS cannot find the SDK's C headers.
if [ "$(uname -s)" = "Darwin" ] && [ -z "${SDKROOT:-}" ] && command -v xcrun >/dev/null 2>&1; then
	SDKROOT=$(xcrun --show-sdk-path)
	export SDKROOT
fi

# odin-c-bindgen exits 0 even when clang fails to parse a header, so its log is checked for errors.
run_bindgen() {
	config="$1"
	package="$2"
	log="$tools/$(basename "$package")-bindgen.log"
	rm -rf "$config/out"
	if ! (cd "$bindgen_src" && ./bindgen.bin "$config") >"$log" 2>&1; then
		cat "$log" >&2
		echo "odin-c-bindgen failed for $config." >&2
		exit 1
	fi
	if grep -q '\[ERROR\]' "$log"; then
		grep '\[ERROR\]' "$log" >&2
		echo "odin-c-bindgen reported errors for $config. Full log: $log" >&2
		exit 1
	fi
	set -- "$config/out/"*.odin
	if [ ! -e "$1" ]; then
		echo "odin-c-bindgen produced no files in $config/out." >&2
		exit 1
	fi
	mkdir -p "$package"
	find "$package" -maxdepth 1 -name '*.odin' ! -name 'helpers.odin' ! -name 'aliases.odin' -delete
	cp "$@" "$package/"
}

run_bindgen "$root/bindgen/rmlui" "$root/rmlui"
run_bindgen "$root/bindgen/rmlui_backend" "$root/rmlui_backend"
echo "Generated Odin packages."
