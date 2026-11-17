#!/bin/sh
set -eu
sample=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH= cd -- "$sample/../.." && pwd)
case "$(uname -s)" in
	Linux) rpath='-Wl,-rpath,$ORIGIN' ;;
	Darwin) rpath='-Wl,-rpath,@loader_path' ;;
	*) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
odin build "$sample" -out:"$sample/basic" -extra-linker-flags:"$rpath"
"$root/stage.sh" "$sample"
echo "Built $sample/basic"
