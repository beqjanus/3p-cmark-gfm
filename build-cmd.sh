#!/usr/bin/env bash
set -euo pipefail

top=$(cd "$(dirname "$0")" && pwd)
cd "$top"
# shellcheck disable=SC1091
source "$top/upstream.lock"

platform=${AUTOBUILD_PLATFORM:-}
if [[ -z "$platform" ]]; then
  case "$(uname -s)" in
    Darwin) platform=darwin64 ;;
    Linux) platform=linux64 ;;
    MINGW*|MSYS*|CYGWIN*) platform=windows64 ;;
    *) echo "Unsupported host platform: $(uname -s)" >&2; exit 1 ;;
  esac
fi

case "$platform" in
  windows*) target=windows64 ;;
  linux*) target=linux64 ;;
  darwin*) target=darwin64 ;;
  *) echo "Unsupported Autobuild platform: $platform" >&2; exit 1 ;;
esac

source_dir="$top/cmark-gfm"
build_dir="$top/build/$target"
stage_dir="$top/stage"

if [[ ! -d "$source_dir/.git" ]]; then
  git clone --depth 1 --branch "$UPSTREAM_TAG" "$UPSTREAM_URL" "$source_dir"
fi

# Fetch the named tag from the canonical remote before checking out the pinned
# object.  This protects local source trees from silently building master.
git -C "$source_dir" fetch --depth 1 "$UPSTREAM_URL" \
  "refs/tags/$UPSTREAM_TAG:refs/tags/$UPSTREAM_TAG"
git -C "$source_dir" checkout --detach "$UPSTREAM_COMMIT"
actual_commit=$(git -C "$source_dir" rev-parse HEAD)
tag_commit=$(git -C "$source_dir" rev-parse "$UPSTREAM_TAG^{}")
[[ "$actual_commit" == "$UPSTREAM_COMMIT" && "$tag_commit" == "$UPSTREAM_COMMIT" ]] || {
  echo "Upstream tag/commit verification failed" >&2
  exit 1
}

rm -rf "$build_dir"
# Autobuild invokes this script while its process is in stage/.  Empty it in
# place instead of removing the directory, otherwise Autobuild cannot write
# its package metadata after this script returns.
mkdir -p "$stage_dir"
find "$stage_dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
mkdir -p "$build_dir" "$stage_dir/include" "$stage_dir/lib" "$stage_dir/LICENSES"

cmake_args=(
  -S "$source_dir" -B "$build_dir"
  -DCMARK_STATIC=ON -DCMARK_SHARED=OFF -DCMARK_TESTS=OFF
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
)
build_args=(--build "$build_dir" --target libcmark-gfm_static libcmark-gfm-extensions_static --parallel)
smoke_args=(-S "$top/tests" -B "$build_dir/smoke" "-DSTAGE_DIR=$stage_dir")

if command -v ninja >/dev/null 2>&1; then
  unix_generator=Ninja
else
  unix_generator="Unix Makefiles"
fi

case "$target" in
  windows64)
    cmake_args+=(-G "Visual Studio 17 2022" -A x64)
    build_args+=(--config Release)
    smoke_args+=(-G "Visual Studio 17 2022" -A x64)
    core_name=cmark-gfm_static.lib
    extensions_name=cmark-gfm-extensions_static.lib
    ;;
  linux64)
    cmake_args+=(-G "$unix_generator" -DCMAKE_BUILD_TYPE=Release)
    smoke_args+=(-G "$unix_generator" -DCMAKE_BUILD_TYPE=Release)
    core_name=libcmark-gfm.a
    extensions_name=libcmark-gfm-extensions.a
    ;;
  darwin64)
    cmake_args+=(-G "$unix_generator" -DCMAKE_BUILD_TYPE=Release "-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64")
    smoke_args+=(-G "$unix_generator" -DCMAKE_BUILD_TYPE=Release "-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64")
    core_name=libcmark-gfm.a
    extensions_name=libcmark-gfm-extensions.a
    ;;
esac

cmake "${cmake_args[@]}"
cmake "${build_args[@]}"

find_library() {
  local name=$1
  local found
  found=$(find "$build_dir" -type f -name "$name" -print -quit)
  [[ -n "$found" ]] || { echo "Built archive not found: $name" >&2; exit 1; }
  printf '%s\n' "$found"
}

cp "$(find_library "$core_name")" "$stage_dir/lib/$core_name"
cp "$(find_library "$extensions_name")" "$stage_dir/lib/$extensions_name"
cp "$source_dir/src/cmark-gfm.h" "$source_dir/src/cmark-gfm-extension_api.h" "$stage_dir/include/"
cp "$build_dir/src/cmark-gfm_export.h" "$build_dir/src/cmark-gfm_version.h" "$stage_dir/include/"
cp "$source_dir/extensions/cmark-gfm-core-extensions.h" "$stage_dir/include/"
cp "$source_dir/COPYING" "$stage_dir/LICENSES/cmark-gfm-COPYING.txt"
printf '%s.%s\n' "$UPSTREAM_TAG" "${AUTOBUILD_BUILD_ID:-0}" > "$stage_dir/VERSION.txt"

if [[ "$target" == windows64 ]]; then
  powershell -NoProfile -ExecutionPolicy Bypass -File "$top/tests/verify-package.ps1" -StageDir "$stage_dir"
else
  "$top/tests/verify-package.sh" "$stage_dir" "$target"
fi

rm -rf "$build_dir/smoke"
cmake "${smoke_args[@]}"
cmake --build "$build_dir/smoke" --config Release --parallel
if [[ "$target" != windows64 ]]; then
  "$build_dir/smoke/cmark-gfm-package-smoke"
else
  "$build_dir/smoke/Release/cmark-gfm-package-smoke.exe"
fi
