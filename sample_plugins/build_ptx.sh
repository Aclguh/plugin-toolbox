#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

for plugin in "$DIR"/*/; do
  if [ -f "$plugin/plugin.json" ]; then
    name=$(basename "$plugin")
    echo "Packaging $name -> $name.ptx ..."
    (cd "$plugin" && zip -r "$DIR/$name.ptx" ./*)
    echo "Done: $DIR/$name.ptx"
  fi
done
