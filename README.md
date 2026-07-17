# 3p-cmark-gfm

Firestorm Autobuild package repository for [cmark-gfm](https://github.com/github/cmark-gfm), pinned to upstream tag `0.29.0.gfm.13` (`587a12bb54d95ac37241377e6ddc93ea0e45439b`). The pin is recorded in [`upstream.lock`](upstream.lock) and verified by the build script; it never builds upstream `master`.

## Contents and platforms

The package supports Windows x64, Ubuntu 24.04 x64, and universal macOS (x86_64 + arm64). It contains only static libraries, public/generated headers, `LICENSES/cmark-gfm-COPYING.txt`, and `VERSION.txt` (`0.29.0.gfm.13.$AUTOBUILD_BUILD_ID`). No shared libraries or `cmark-gfm` executable are staged.

| Platform | Core | Extensions |
| --- | --- | --- |
| Windows x64 | `lib/cmark-gfm_static.lib` | `lib/cmark-gfm-extensions_static.lib` |
| Linux x64 | `lib/libcmark-gfm.a` | `lib/libcmark-gfm-extensions.a` |
| macOS universal | `lib/libcmark-gfm.a` | `lib/libcmark-gfm-extensions.a` |

These are upstream's native static archive names. This deliberately matches the current Firestorm [`CMarkGFM.cmake`](../phoenix-firestorm/indra/cmake/CMarkGFM.cmake) lookup names rather than normalising Windows names. Consumers link extensions before core and compile with `CMARK_GFM_STATIC_DEFINE` and `CMARK_GFM_EXTENSIONS_STATIC_DEFINE` (the viewer already propagates both).

Packaged headers are `cmark-gfm.h`, `cmark-gfm-extension_api.h`, generated `cmark-gfm_export.h`, generated `cmark-gfm_version.h`, and `cmark-gfm-core-extensions.h`.

## Local build and validation

On the matching host platform, run:

```bash
AUTOBUILD_BUILD_ID=0 ./build-cmd.sh
```

This downloads/verifies the pin when necessary, configures `Release` with `CMARK_STATIC=ON`, `CMARK_SHARED=OFF`, `CMARK_TESTS=OFF`, and PIC enabled, stages the package, validates its contents, and builds/runs `tests/smoke.c`. The smoke test registers the core extensions, attaches the table extension to a parser, parses Markdown, and links both static archives in viewer order. On macOS it also requires both archives to contain x86_64 and arm64 slices.

To build and archive through Autobuild:

```bash
AUTOBUILD_PLATFORM=linux64 AUTOBUILD_BUILD_ID=0 autobuild -A64 build --config-file=autobuild.xml
AUTOBUILD_PLATFORM=linux64 autobuild -A64 package --config-file=autobuild.xml
```

To install an archive locally from a Firestorm viewer checkout:

```bash
AUTOBUILD_PLATFORM=linux64 autobuild -A64 install --config-file=/path/to/phoenix-firestorm/autobuild.xml \
  --install-dir=installed --installed-manifest=installed-manifest \
  --local="$(find "$PWD" -maxdepth 1 -name 'cmark_gfm-*.tar.bz2' -print -quit)" cmark-gfm
```

The validation workflow runs the staged checks, smoke test, Autobuild build/package, and a local Autobuild installation through a minimal consumer manifest on Windows x64, Ubuntu 24.04 x64, and macOS universal.

Substitute `windows64` or `darwin64` for `linux64` on those hosts.

## Releases and updates

Push an intentional tag matching `cmark-gfm-*` (for example `cmark-gfm-0.29.0.gfm.13-1`) or use **Run workflow** for the release workflow. It builds all platforms, assembles releases through `AlchemyViewer/action-autobuild` and `AlchemyViewer/action-autobuild-release`, publishes the GitHub release artifacts, then copies the exact generated Autobuild `.zst`/`.tzst` archives to `fs_r2_deploy:buildsupport`. Configure the repository secret `RCLONE_CONFIG`; no credentials or rclone configuration are committed. Pull requests and ordinary branch pushes never reach the upload job.

To update upstream, resolve and verify the desired release tag's commit, update all three values in `upstream.lock`, run the local build/smoke test, and let the validation workflow pass on every platform. Update this README and create a new intentional release tag only after review. No upstream patches are carried.

The reference repositories use a source/stage script and Autobuild release assembly. This package differs only by compiling upstream directly instead of repackaging another prebuilt dependency.
