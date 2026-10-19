#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=2.10.0
checksum=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
cache="build/dependencies/Sparkle-$version"
archive="$cache.tar.xz"
if [[ ! -f "$archive" ]]; then
  mkdir -p build/dependencies
  curl --fail --location --retry 3 "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$archive"
fi
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c -
mkdir -p "$cache"
tar -xf "$archive" -C "$cache"
mkdir -p vendor
ditto "$cache/Sparkle.framework" vendor/Sparkle.framework
printf 'Sparkle %s is ready.\n' "$version"
