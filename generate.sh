#!/bin/sh
# Regenerates the Odin packages from deps/RmlUi/Include.
# Builds a pinned odin-c-bindgen. Linux and macOS need libclang 16+ installed.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
tools="$root/.tools"
bindgen_commit="12f4e7adb7ff4be1546ff4c3c3a7a42b637a7315"
bindgen_url="https://github.com/karl-zylinski/odin-c-bindgen.git"
bindgen_src="$tools/odin-c-bindgen"

ensure_pinned_repo() {
	dir="$1"
	url="$2"
	commit="$3"
	if [ -d "$dir/.git" ]; then
		head=$(git -C "$dir" rev-parse HEAD)
		if [ "$head" = "$commit" ]; then
			return
		fi
		git -C "$dir" fetch --depth 1 origin "$commit"
		git -C "$dir" checkout --detach "$commit"
		return
	fi
	rm -rf "$dir"
	mkdir -p "$dir"
	git -C "$dir" init
	git -C "$dir" remote add origin "$url"
	git -C "$dir" fetch --depth 1 origin "$commit"
	git -C "$dir" checkout --detach FETCH_HEAD
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

# odin-c-bindgen links system:clang. Prefer a Homebrew LLVM on macOS.
if [ "$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
	llvm_prefix=$(brew --prefix llvm 2>/dev/null || true)
	if [ -n "$llvm_prefix" ] && [ -d "$llvm_prefix/lib" ]; then
		export LIBRARY_PATH="$llvm_prefix/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
		export DYLD_LIBRARY_PATH="$llvm_prefix/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
	fi
fi

mkdir -p "$tools"
ensure_pinned_repo "$bindgen_src" "$bindgen_url" "$bindgen_commit"

if ! (cd "$bindgen_src" && odin build src -out:bindgen.bin); then
	echo "Failed to build odin-c-bindgen. Install libclang 16 or newer and re-run." >&2
	echo "Linux: libclang-dev (Debian/Ubuntu) or clang-devel (Fedora)." >&2
	echo "macOS: brew install llvm" >&2
	exit 1
fi

run_bindgen() {
	config="$1"
	package="$2"
	rm -rf "$config/out"
	(cd "$bindgen_src" && ./bindgen.bin "$config")
	mkdir -p "$package"
	find "$package" -maxdepth 1 -name '*.odin' ! -name 'helpers.odin' ! -name 'aliases.odin' -delete
	cp "$config/out/"*.odin "$package/"
}

run_bindgen "$root/bindgen/rmlui" "$root/rmlui"
run_bindgen "$root/bindgen/rmlui_backend" "$root/rmlui_backend"
echo "Generated Odin packages."
