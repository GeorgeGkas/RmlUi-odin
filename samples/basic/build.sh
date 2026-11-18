#!/bin/sh
# Builds the sample and copies runtime binaries next to the executable.
set -eu
sample=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH='' cd -- "$sample/../.." && pwd)
odin build "$sample" -out:"$sample/basic"
sh "$root/stage.sh" "$sample"
echo "Built $sample/basic"
