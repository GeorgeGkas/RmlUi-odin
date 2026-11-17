# rmlui-odin

Odin bindings for [RmlUi](https://github.com/mikke89/RmlUi), built on the C API in [this fork](https://github.com/GeorgeGkas/RmlUi).

## Requirements

- git
- CMake on `PATH`, or the CMake that ships with Visual Studio 2022
- the Odin compiler on `PATH`
- Windows: Visual Studio 2022 with the Desktop development with C++ workload
- Linux: Ninja, a C++ compiler, pkg-config, and the X11 and OpenGL development packages. libclang 16 or newer (`libclang-dev` on Debian/Ubuntu, `clang-devel` on Fedora)
- macOS: Ninja, a C++ compiler, and libclang 16 or newer (`brew install llvm`)

FreeType, SDL 3, and SDL3_image are fetched by bootstrap. An OpenGL 3 driver is required to run the sample.

## Use it from an Odin project

```text
git submodule add <url of this repository> third_party/rmlui
git submodule update --init --recursive
```

Windows:

```text
third_party/rmlui/bootstrap.ps1
```

Linux and macOS:

```text
third_party/rmlui/bootstrap.sh
```

Import the packages:

```odin
import rmlui "third_party/rmlui/rmlui"
import rmlui_backend "third_party/rmlui/rmlui_backend"
```

Copy runtime binaries next to your executable:

```text
third_party/rmlui/stage.ps1 <output-directory>
third_party/rmlui/stage.sh <output-directory>
```

On Linux, add this to the Odin link line so the loader searches beside the executable:

```text
-extra-linker-flags:"-Wl,-rpath,$ORIGIN"
```

On macOS, use:

```text
-extra-linker-flags:"-Wl,-rpath,@loader_path"
```

## What bootstrap builds

Bootstrap checks out vcpkg at `3af1d1e60af2b2abf55760538cd607829029b07a`, installs FreeType, SDL 3, and SDL3_image from `vcpkg.json`, and builds `deps/RmlUi` as shared libraries with `RMLUI_CAPI=ON`, `RMLUI_CAPI_BACKEND=ON`, `RMLUI_BACKEND=SDL_GL3`, and `RMLUI_SDL_VERSION_MAJOR=3`. That is the SDL 3 windowing layer with the OpenGL 3 renderer on Windows, Linux, and macOS. Linux and macOS use the dynamic triplets in `triplets/` so FreeType and SDL 3 are shared libraries, matching the Windows vcpkg triplet.

It also checks out odin-c-bindgen at `12f4e7adb7ff4be1546ff4c3c3a7a42b637a7315` and regenerates `rmlui` and `rmlui_backend` from `deps/RmlUi/Include`. `rmlui/helpers.odin` and `rmlui_backend/aliases.odin` are left in place. Windows downloads LLVM 20.1.8 for libclang. Linux and macOS use a libclang already installed on the machine.

Link inputs land in `rmlui/lib/<os>` and `rmlui_backend/lib/<os>`. Runtime binaries, including FreeType and SDL 3, land in `bin/<os>`. `<os>` is `windows`, `linux`, or `darwin`.

`stage` copies that whole directory next to an executable.

## Sample

From this repository's root, after bootstrap:

```text
samples/basic/build.ps1
samples/basic/basic.exe
```

On Linux and macOS, `samples/basic/build.sh` produces `samples/basic/basic`. The font path `deps/RmlUi/Samples/assets/LatoLatin-Regular.ttf` is resolved from the package root.

## Maintainer

`generate.ps1` and `generate.sh` regenerate the Odin packages without building the C libraries. Bootstrap calls them.

`deps/RmlUi` is a submodule of `https://github.com/GeorgeGkas/RmlUi.git`, pinned to `8ffe0e6364e37bbb4639672a17de8871c2c480a9`.
