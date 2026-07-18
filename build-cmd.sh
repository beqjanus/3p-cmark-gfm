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

# Override only for a disposable source checkout, for example in a CI or
# recovery build. The default remains the Autobuild source directory.
source_dir=${CMARK_GFM_SOURCE_DIR:-"$top/cmark-gfm"}
build_dir="$top/build/$target"
stage_dir="$top/stage"
archive_dir="$build_dir/archives"

# action-autobuild disables MSYS argument conversion.  Native CMake then
# interprets a Git Bash path such as /d/a/workspace as D:\\d\\a\\workspace,
# while shell tools correctly see it as D:\\a\\workspace.  Use native paths
# only for CMake on Windows; keep POSIX paths for Bash file operations.
cmake_source_dir="$source_dir"
cmake_build_dir="$build_dir"
cmake_archive_dir="$archive_dir"
cmake_smoke_dir="$build_dir/smoke"
cmake_stage_dir="$stage_dir"
cmake_tests_dir="$top/tests"
if [[ "$target" == windows64 ]]; then
  command -v cygpath >/dev/null 2>&1 || {
    echo "Windows builds require cygpath to pass native paths to CMake" >&2
    exit 1
  }
  cmake_source_dir=$(cygpath -w "$source_dir")
  cmake_build_dir=$(cygpath -w "$build_dir")
  cmake_archive_dir=$(cygpath -w "$archive_dir")
  cmake_smoke_dir=$(cygpath -w "$build_dir/smoke")
  cmake_stage_dir=$(cygpath -w "$stage_dir")
  cmake_tests_dir=$(cygpath -w "$top/tests")
fi

if [[ ! -d "$source_dir/.git" ]]; then
  git clone "$UPSTREAM_URL" "$source_dir"
elif ! git -C "$source_dir" diff --quiet || ! git -C "$source_dir" diff --cached --quiet; then
  echo "Refusing to replace local changes in $source_dir; use a clean checkout or CMARK_GFM_SOURCE_DIR." >&2
  exit 1
fi

# Refresh the recorded source branch, then check out the immutable lock-file
# commit. This permits a master snapshot without silently advancing to master.
git -C "$source_dir" fetch "$UPSTREAM_URL" "$UPSTREAM_REF"
git -C "$source_dir" checkout --detach "$UPSTREAM_COMMIT"
actual_commit=$(git -C "$source_dir" rev-parse HEAD)
[[ "$actual_commit" == "$UPSTREAM_COMMIT" ]] || {
  echo "Upstream commit verification failed" >&2
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
  -S "$cmake_source_dir" -B "$cmake_build_dir"
  -DCMARK_STATIC=ON -DCMARK_SHARED=OFF -DCMARK_TESTS=OFF
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
)
build_args=(--build "$cmake_build_dir" --target libcmark-gfm_static libcmark-gfm-extensions_static --parallel)
smoke_args=(-S "$cmake_tests_dir" -B "$cmake_smoke_dir" "-DSTAGE_DIR=$cmake_stage_dir")

if command -v ninja >/dev/null 2>&1; then
  unix_generator=Ninja
else
  unix_generator="Unix Makefiles"
fi

case "$target" in
  windows64)
    cmake_args+=(-G "Visual Studio 17 2022" -A x64)
    # Prefer a configuration-independent location for Visual Studio archives.
    # Older CMake/VS combinations can still use their target-specific output
    # directory, so archive discovery below remains authoritative.
    cmake_args+=("-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELEASE=$cmake_archive_dir")
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
  if [[ -z "$found" ]]; then
    echo "Built archive not found: $name" >&2
    echo "Static libraries produced under $build_dir:" >&2
    find "$build_dir" -type f -name '*.lib' -print >&2
    return 1
  fi
  printf '%s\n' "$found"
}

core_archive=$(find_library "$core_name")
extensions_archive=$(find_library "$extensions_name")

for archive in "$core_archive" "$extensions_archive"; do
  [[ -f "$archive" ]] || {
    echo "Built archive not found: $archive" >&2
    exit 1
  }
done

cp "$core_archive" "$stage_dir/lib/$core_name"
cp "$extensions_archive" "$stage_dir/lib/$extensions_name"
cp "$source_dir/src/cmark-gfm.h" "$source_dir/src/cmark-gfm-extension_api.h" "$stage_dir/include/"
cp "$build_dir/src/cmark-gfm_export.h" "$build_dir/src/cmark-gfm_version.h" "$stage_dir/include/"
cp "$source_dir/extensions/cmark-gfm-core-extensions.h" "$stage_dir/include/"
cp "$source_dir/COPYING" "$stage_dir/LICENSES/cmark-gfm-COPYING.txt"
printf '%s.%s\n' "$UPSTREAM_VERSION" "${AUTOBUILD_BUILD_ID:-0}" > "$stage_dir/VERSION.txt"

if [[ "$target" == windows64 ]]; then
  powershell -NoProfile -ExecutionPolicy Bypass -File "$top/tests/verify-package.ps1" -StageDir "$stage_dir"
else
  "$top/tests/verify-package.sh" "$stage_dir" "$target"
fi

rm -rf "$build_dir/smoke"
cmake "${smoke_args[@]}"
cmake --build "$cmake_smoke_dir" --config Release --parallel
if [[ "$target" != windows64 ]]; then
  "$build_dir/smoke/cmark-gfm-package-smoke"
else
  "$build_dir/smoke/Release/cmark-gfm-package-smoke.exe"
fi
