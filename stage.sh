#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
if [ "$#" -lt 1 ] || [ -z "$1" ]; then
	echo "Usage: stage.sh <directory>" >&2
	exit 1
fi
case "$(uname -s)" in
	Linux) os_name="linux" ;;
	Darwin) os_name="darwin" ;;
	*) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
bin="$root/bin/$os_name"
if [ ! -d "$bin" ]; then
	echo "Missing $bin. Run bootstrap.sh first." >&2
	exit 1
fi
mkdir -p "$1"
cp -a "$bin"/. "$1"/
echo "Staged runtime binaries to $1"
