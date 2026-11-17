#!/bin/sh
# Regenerates the Odin bindings, then builds shared rmlui_capi and rmlui_capi_backend (SDL_GL3).
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
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

require_any() {
	found=0
	for file in "$@"; do
		if [ -e "$file" ]; then
			found=1
		fi
	done
	if [ "$found" -ne 1 ]; then
		echo "Build did not produce $(basename "$1")" >&2
		exit 1
	fi
}

case "$(uname -s)" in
	Linux) os_name="linux" ;;
	Darwin) os_name="darwin" ;;
	*) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
	x86_64|amd64)
		if [ "$os_name" = "linux" ]; then triplet="x64-linux-dynamic"; else triplet="x64-osx-dynamic"; fi
		;;
	aarch64|arm64)
		if [ "$os_name" = "linux" ]; then triplet="arm64-linux-dynamic"; else triplet="arm64-osx-dynamic"; fi
		;;
	*)
		echo "Unsupported architecture: $(uname -m)" >&2
		exit 1
		;;
esac
if [ "$os_name" = "linux" ]; then
	lib_ext="so"
else
	lib_ext="dylib"
fi

require_tool git
require_tool cmake
require_tool ninja
require_tool c++
require_tool odin

if [ ! -f "$deps/CMakeLists.txt" ]; then
	echo "Missing $deps. From the package root, run: git submodule update --init --recursive" >&2
	exit 1
fi

"$root/generate.sh"

mkdir -p "$root/.tools"
ensure_pinned_repo "$vcpkg_dir" "$vcpkg_url" "$vcpkg_commit"
"$vcpkg_dir/bootstrap-vcpkg.sh"

log="$build/configure.log"
mkdir -p "$build"
set +e
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

core_lib="$root/rmlui/lib/$os_name"
backend_lib="$root/rmlui_backend/lib/$os_name"
bin="$root/bin/$os_name"
mkdir -p "$core_lib" "$backend_lib" "$bin"

capi_name="librmlui_capi.$lib_ext"
backend_name="librmlui_capi_backend.$lib_ext"
cp -aL "$dist/$capi_name" "$core_lib/"
cp -aL "$dist/$backend_name" "$backend_lib/"
for name in "$capi_name" "$backend_name" "librmlui.$lib_ext" "librmlui_debugger.$lib_ext"; do
	cp -aL "$dist/$name" "$bin/"
done

vcpkg_lib="$build/vcpkg_installed/$triplet/lib"
if [ -d "$vcpkg_lib" ]; then
	if [ "$os_name" = "linux" ]; then
		cp -a "$vcpkg_lib"/*.so* "$bin/"
	else
		cp -a "$vcpkg_lib"/*.dylib "$bin/"
	fi
fi

for name in "$capi_name" "$backend_name" "librmlui.$lib_ext" "librmlui_debugger.$lib_ext"; do
	if [ ! -e "$bin/$name" ]; then
		echo "Build did not produce $name in $dist." >&2
		exit 1
	fi
done
if [ "$os_name" = "linux" ]; then
	require_any "$bin"/libfreetype.so*
	require_any "$bin"/libSDL3.so*
else
	require_any "$bin"/libfreetype*.dylib
	require_any "$bin"/libSDL3*.dylib
fi
echo "Bootstrap complete. Runtime binaries are in $bin"
