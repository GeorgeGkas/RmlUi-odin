#!/bin/sh
# Checks that Odin's string matches {const char*, size_t} by value, as the RmlStringView override assumes.
set -eu
dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
case "$(uname -s)" in
	Linux) cc -shared -fPIC -Wl,-soname,libabi.so -o "$dir/libabi.so" "$dir/abi.c" ;;
	Darwin) cc -dynamiclib -install_name @rpath/libabi.dylib -o "$dir/libabi.dylib" "$dir/abi.c" ;;
	*) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
odin build "$dir" -out:"$dir/abi.bin"
"$dir/abi.bin"
