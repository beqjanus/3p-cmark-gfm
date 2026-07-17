cmake_minimum_required(VERSION 3.5)
project(cmark_gfm_package_smoke C)

if(NOT DEFINED STAGE_DIR)
  message(FATAL_ERROR "Pass -DSTAGE_DIR=/absolute/path/to/stage")
endif()

add_executable(cmark-gfm-package-smoke smoke.c)
target_include_directories(cmark-gfm-package-smoke PRIVATE "${STAGE_DIR}/include")
target_compile_definitions(cmark-gfm-package-smoke PRIVATE
  CMARK_GFM_STATIC_DEFINE
  CMARK_GFM_EXTENSIONS_STATIC_DEFINE)

if(MSVC)
  set(CMARK_GFM_CORE "${STAGE_DIR}/lib/cmark-gfm_static.lib")
  set(CMARK_GFM_EXTENSIONS "${STAGE_DIR}/lib/cmark-gfm-extensions_static.lib")
else()
  set(CMARK_GFM_CORE "${STAGE_DIR}/lib/libcmark-gfm.a")
  set(CMARK_GFM_EXTENSIONS "${STAGE_DIR}/lib/libcmark-gfm-extensions.a")
endif()

# Keep the viewer's required static-link order: extensions first, then core.
target_link_libraries(cmark-gfm-package-smoke PRIVATE
  "${CMARK_GFM_EXTENSIONS}"
  "${CMARK_GFM_CORE}")
