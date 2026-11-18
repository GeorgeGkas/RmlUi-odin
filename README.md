# rmlui-odin

Odin bindings for [RmlUi](https://github.com/mikke89/RmlUi), built on the C API in [this fork](https://github.com/GeorgeGkas/RmlUi).

## Requirements

- git
- the Odin compiler on `PATH`
- Windows: Visual Studio 2022 or 2026 with the Desktop development with C++ workload, including its C++ CMake tools. Bootstrap uses the CMake and Ninja that ship with Visual Studio.
- Linux: CMake, Ninja, a C and C++ compiler, pkg-config, curl, zip, unzip, tar, and libclang 16 or newer. SDL 3 is built with X11 and Wayland support, which needs their development packages. On Debian/Ubuntu:

  ```text
  sudo apt install cmake ninja-build build-essential pkg-config curl zip unzip tar libclang-dev \
      libx11-dev libxft-dev libxext-dev libwayland-dev libxkbcommon-dev libegl1-mesa-dev
  ```

  On Fedora, `clang-devel` provides libclang.
- macOS: CMake, Ninja, pkg-config, the Xcode command line tools, and libclang 16 or newer. `brew install cmake ninja pkg-config llvm` covers all of them. Without Homebrew LLVM, generate falls back to the libclang in the active Xcode toolchain.

FreeType, SDL 3, and SDL3_image are fetched by bootstrap. An OpenGL 3 driver is required to run the sample.

## Use it from an Odin project

```text
git submodule add <url of this repository> third_party/rmlui
git submodule update --init --recursive
```

Windows:

```text
powershell -ExecutionPolicy Bypass -File third_party/rmlui/bootstrap.ps1
```

The `-ExecutionPolicy Bypass` flag is only needed when the machine's policy blocks local scripts, which is the default on Windows client editions.

Linux and macOS:

```text
sh third_party/rmlui/bootstrap.sh
```

Import the packages:

```odin
import rmlui "third_party/rmlui/rmlui"
import rmlui_backend "third_party/rmlui/rmlui_backend"
```

Copy runtime binaries next to your executable:

```text
powershell -ExecutionPolicy Bypass -File third_party/rmlui/stage.ps1 <output-directory>
sh third_party/rmlui/stage.sh <output-directory>
```

On Linux and macOS, Odin already links executables with an rpath of `$ORIGIN` or `@loader_path`, so staged libraries are found beside the executable. Do not build with `-no-rpath`.

## What bootstrap builds

Bootstrap checks out vcpkg at `3af1d1e60af2b2abf55760538cd607829029b07a`, installs FreeType, SDL 3, and SDL3_image from `vcpkg.json`, and builds `deps/RmlUi` as shared libraries with `RMLUI_CAPI=ON`, `RMLUI_CAPI_BACKEND=ON`, `RMLUI_BACKEND=SDL_GL3`, and `RMLUI_SDL_VERSION_MAJOR=3`. That is the SDL 3 windowing layer with the OpenGL 3 renderer on Windows, Linux, and macOS. All platforms use the release-only triplets in `triplets/`, and FreeType and SDL 3 are shared libraries.

It also checks out odin-c-bindgen at `12f4e7adb7ff4be1546ff4c3c3a7a42b637a7315` and regenerates `rmlui` and `rmlui_backend` from `deps/RmlUi/Include`. `rmlui/helpers.odin` and `rmlui_backend/aliases.odin` are left in place. Windows downloads LLVM 20.1.8 for libclang and verifies its SHA-256. Linux and macOS use a libclang already installed on the machine. Generation fails if libclang reports an error in any header.

On Windows, import libraries land in `rmlui/lib/windows` and `rmlui_backend/lib/windows`, and runtime binaries land in `bin/windows`. On Linux and macOS, the Odin packages link directly against `bin/linux` or `bin/darwin`. Every library there has an rpath of `$ORIGIN` or `@loader_path`, so the directory works without the `build` directory and can be moved as a unit.

`stage` copies `bin/<os>` next to an executable. Each bootstrap run replaces `bin/<os>`.

## Sample

From this repository's root, after bootstrap:

```text
powershell -ExecutionPolicy Bypass -File samples/basic/build.ps1
samples/basic/basic.exe
```

On Linux and macOS, `sh samples/basic/build.sh` produces `samples/basic/basic`. The font path `deps/RmlUi/Samples/assets/LatoLatin-Regular.ttf` is resolved from the package root.

## Maintainer

`generate.ps1` and `generate.sh` regenerate the Odin packages without building the C libraries. Bootstrap calls them.

`abi_test/run.ps1` and `abi_test/run.sh` check that Odin's `string` matches the C API's `RmlStringView` (`{const char*, size_t}`) when passed and returned by value. The bindings depend on that.

`deps/RmlUi` is a submodule of `https://github.com/GeorgeGkas/RmlUi.git`, pinned to `8ffe0e6364e37bbb4639672a17de8871c2c480a9`.

CI in `.github/workflows/ci.yml` runs bootstrap, the ABI test, and the sample build on Windows x64, Linux x64 and arm64, and macOS arm64 and x64. It runs on pushes to `main` or `master` and on manual dispatch.
