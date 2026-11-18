#!/bin/sh
# Regenerates the Odin bindings, then builds shared rmlui_capi and rmlui_capi_backend (SDL_GL3).
set -eu
root=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
vcpkg_commit="3af1d1e60af2b2abf55760538cd607829029b07a"
vcpkg_url="https://github.com/microsoft/vcpkg.git"
vcpkg_dir="$root/.tools/vcpkg"
deps="$root/deps/RmlUi"
build="$root/build"
dist="$build/dist"

require_tool() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Required tool '$1' was not found on PATH." >&2
		exit 1
	fi
}

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

require_any() {
	for file in "$@"; do
		if [ -e "$file" ]; then
			return
		fi
	done
	echo "Build did not produce $(basename "$1")" >&2
	exit 1
}

case "$(uname -s)" in
	Linux) os_name="linux" ;;
	Darwin) os_name="darwin" ;;
	*) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
	x86_64|amd64) arch="x64"; osx_arch="x86_64" ;;
	aarch64|arm64) arch="arm64"; osx_arch="arm64" ;;
	*)
		echo "Unsupported architecture: $(uname -m)" >&2
		exit 1
		;;
esac
if [ "$os_name" = "linux" ]; then
	triplet="$arch-linux-dynamic"
	lib_ext="so"
	# $ORIGIN must reach CMake unexpanded.
	# shellcheck disable=SC2016
	origin='$ORIGIN'
	platform_args="-DCMAKE_INSTALL_RPATH=$origin"
	if [ "$arch" = "arm64" ]; then
		# vcpkg cannot download its own CMake and Ninja on arm64 Linux.
		export VCPKG_FORCE_SYSTEM_BINARIES="${VCPKG_FORCE_SYSTEM_BINARIES:-1}"
	fi
else
	triplet="$arch-osx-dynamic"
	lib_ext="dylib"
	platform_args="-DCMAKE_INSTALL_RPATH=@loader_path -DCMAKE_OSX_ARCHITECTURES=$osx_arch"
fi

require_tool git
require_tool cmake
require_tool ninja
require_tool cc
require_tool c++
require_tool pkg-config
require_tool odin

if [ ! -f "$deps/CMakeLists.txt" ]; then
	echo "Missing $deps. From the package root, run: git submodule update --init --recursive" >&2
	exit 1
fi

sh "$root/generate.sh"

mkdir -p "$root/.tools"
ensure_pinned_repo "$vcpkg_dir" "$vcpkg_url" "$vcpkg_commit"
"$vcpkg_dir/bootstrap-vcpkg.sh" -disableMetrics

log="$build/configure.log"
mkdir -p "$build"
set +e
# shellcheck disable=SC2086
cmake -G Ninja -S "$deps" -B "$build" \
	-DBUILD_SHARED_LIBS=ON \
	-DBUILD_TESTING=OFF \
	-DRMLUI_SAMPLES=OFF \
	-DRMLUI_CAPI=ON \
	-DRMLUI_CAPI_BACKEND=ON \
	-DRMLUI_BACKEND=SDL_GL3 \
	-DRMLUI_SDL_VERSION_MAJOR=3 \
	-DRMLUI_FONT_ENGINE=freetype \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
	$platform_args \
	-DCMAKE_TOOLCHAIN_FILE="$vcpkg_dir/scripts/buildsystems/vcpkg.cmake" \
	-DVCPKG_MANIFEST_DIR="$root" \
	-DVCPKG_TARGET_TRIPLET="$triplet" \
	-DVCPKG_OVERLAY_TRIPLETS="$root/triplets" \
	-DCMAKE_RUNTIME_OUTPUT_DIRECTORY="$dist" \
	-DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$dist" \
	-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY="$dist" \
	>"$log" 2>&1
configure_status=$?
set -e
if [ "$configure_status" -ne 0 ]; then
	cat "$log" >&2
	echo "CMake configure failed." >&2
	exit 1
fi

cmake --build "$build" --target rmlui_capi --target rmlui_capi_backend

# The Odin packages link against bin/<os> so the linker can resolve each library's dependencies beside it.
bin="$root/bin/$os_name"
rm -rf "$bin" "$root/rmlui/lib/$os_name" "$root/rmlui_backend/lib/$os_name"
mkdir -p "$bin"

rmlui_libs="librmlui_capi.$lib_ext librmlui_capi_backend.$lib_ext librmlui.$lib_ext librmlui_debugger.$lib_ext"
for name in $rmlui_libs; do
	if [ ! -e "$dist/$name" ]; then
		echo "Build did not produce $name in $dist." >&2
		exit 1
	fi
	cp -L "$dist/$name" "$bin/"
done

vcpkg_lib="$build/vcpkg_installed/$triplet/lib"
if [ "$os_name" = "linux" ]; then
	set -- "$vcpkg_lib"/*.so*
else
	set -- "$vcpkg_lib"/*.dylib
fi
if [ ! -e "$1" ]; then
	echo "No shared libraries found in $vcpkg_lib." >&2
	exit 1
fi
cp -a "$@" "$bin/"

if [ "$os_name" = "linux" ]; then
	require_any "$bin"/libfreetype.so*
	require_any "$bin"/libSDL3.so*
	require_any "$bin"/libSDL3_image.so*
else
	require_any "$bin"/libfreetype*.dylib
	require_any "$bin"/libSDL3.*dylib
	require_any "$bin"/libSDL3_image*.dylib
fi
echo "Bootstrap complete. Link inputs and runtime binaries are in $bin"
