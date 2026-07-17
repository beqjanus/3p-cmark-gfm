#!/usr/bin/env bash
set -euo pipefail

stage_dir=${1:?usage: tests/verify-package.sh STAGE_DIR PLATFORM}
platform=${2:?usage: tests/verify-package.sh STAGE_DIR PLATFORM}

require_file() {
  [[ -f "$1" ]] || { echo "Missing required file: $1" >&2; exit 1; }
}

for header in cmark-gfm.h cmark-gfm-extension_api.h cmark-gfm_export.h \
              cmark-gfm_version.h cmark-gfm-core-extensions.h; do
  require_file "$stage_dir/include/$header"
done
require_file "$stage_dir/LICENSES/cmark-gfm-COPYING.txt"
require_file "$stage_dir/VERSION.txt"

case "$platform" in
  darwin*)
    core="$stage_dir/lib/libcmark-gfm.a"
    extensions="$stage_dir/lib/libcmark-gfm-extensions.a"
    ;;
  linux*)
    core="$stage_dir/lib/libcmark-gfm.a"
    extensions="$stage_dir/lib/libcmark-gfm-extensions.a"
    ;;
  *)
    echo "Unsupported POSIX platform: $platform" >&2
    exit 1
    ;;
esac
require_file "$core"
require_file "$extensions"

if find "$stage_dir" -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \
    -o -name '*.dll' -o -name 'cmark-gfm' -o -name 'cmark-gfm.exe' \) -print -quit | grep -q .; then
  echo "Package contains a forbidden shared library or cmark executable" >&2
  exit 1
fi

if [[ "$platform" == darwin* ]]; then
  for archive in "$core" "$extensions"; do
    info=$(lipo -info "$archive")
    printf '%s\n' "$info"
    [[ "$info" == *x86_64* && "$info" == *arm64* ]] || {
      echo "Archive is not universal: $archive" >&2
      exit 1
    }
  done
else
  for archive in "$core" "$extensions"; do
    member=$(ar t "$archive" | head -n 1)
    [[ -n "$member" ]]
    ar p "$archive" "$member" | file - | grep -Eq 'x86-64|x86_64' || {
      echo "Archive is not x86_64: $archive" >&2
      exit 1
    }
  done
fi
