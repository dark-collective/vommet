# Vommet: fetch the pinned C++ sources at configure time.
#
# Upstream ships bergamot-translator and CLD2 as git submodules, which pub path
# packages don't carry. This clones the exact commits upstream pins (git checks
# every object against the commit hash), initialises their submodules at the
# commits those trees record, and applies upstream's patch once. The checkout
# lives next to this file (git-ignored) so repeat builds reuse it.
#
# Set BERGAMOT_SOURCES_OFFLINE=ON to fail instead of touching the network.

set(BERGAMOT_TRANSLATOR_REPO "https://github.com/DavidVentura/bergamot-translator.git")
set(BERGAMOT_TRANSLATOR_COMMIT "96c0fcca3c1ddd89fb1f75e8ff952417ae9e5c45")
set(CLD2_REPO "https://github.com/CLD2Owners/cld2.git")
set(CLD2_COMMIT "b56fa78a2fe44ac2851bae5bf4f4693a0644da7b")

set(_BT_THIRD_PARTY "${CMAKE_CURRENT_LIST_DIR}/..")
get_filename_component(_BT_THIRD_PARTY "${_BT_THIRD_PARTY}" ABSOLUTE)
set(_BT_PATCH "${_BT_THIRD_PARTY}/patches/00-bergamot-translator.patch")

find_package(Git REQUIRED)

function(_bt_run)
  execute_process(COMMAND ${ARGV} RESULT_VARIABLE rc OUTPUT_VARIABLE out ERROR_VARIABLE err)
  if(NOT rc EQUAL 0)
    message(FATAL_ERROR "bergamot sources: `${ARGV}` failed (${rc}):\n${out}\n${err}")
  endif()
endfunction()

# Clone <repo> at <commit> into <dir> (with submodules if <recursive>), unless
# the stamp says that exact commit is already there.
function(_bt_fetch name repo commit dir recursive)
  set(stamp "${dir}/.vommet-source")
  if(EXISTS "${stamp}")
    file(READ "${stamp}" have)
    string(STRIP "${have}" have)
    if(have STREQUAL commit)
      return()
    endif()
  endif()
  if(BERGAMOT_SOURCES_OFFLINE)
    message(FATAL_ERROR "bergamot sources: ${name} ${commit} missing at ${dir} and BERGAMOT_SOURCES_OFFLINE is set")
  endif()
  message(STATUS "bergamot sources: fetching ${name} ${commit}")
  file(REMOVE_RECURSE "${dir}")
  file(MAKE_DIRECTORY "${dir}")
  _bt_run(${GIT_EXECUTABLE} -C "${dir}" init -q)
  _bt_run(${GIT_EXECUTABLE} -C "${dir}" fetch -q --depth 1 "${repo}" "${commit}")
  _bt_run(${GIT_EXECUTABLE} -C "${dir}" -c advice.detachedHead=false checkout -q FETCH_HEAD)
  execute_process(COMMAND ${GIT_EXECUTABLE} -C "${dir}" rev-parse HEAD OUTPUT_VARIABLE got OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT got STREQUAL commit)
    message(FATAL_ERROR "bergamot sources: ${name} is at ${got}, expected ${commit}")
  endif()
  if(recursive)
    _bt_run(${GIT_EXECUTABLE} -C "${dir}" submodule update -q --init --recursive --depth 1 --jobs 4)
  endif()
  if(name STREQUAL "bergamot-translator")
    # Upstream's patch is written against the plugin root (third_party/bergamot-translator/...).
    find_program(_BT_PATCH_TOOL patch REQUIRED)
    _bt_run(${_BT_PATCH_TOOL} -p3 -s -d "${dir}" -i "${_BT_PATCH}")
  endif()
  file(WRITE "${stamp}" "${commit}\n")
endfunction()

file(LOCK "${_BT_THIRD_PARTY}/.vommet-source.lock" GUARD PROCESS TIMEOUT 1800)
_bt_fetch(bergamot-translator "${BERGAMOT_TRANSLATOR_REPO}" "${BERGAMOT_TRANSLATOR_COMMIT}" "${_BT_THIRD_PARTY}/bergamot-translator" ON)
_bt_fetch(cld2 "${CLD2_REPO}" "${CLD2_COMMIT}" "${_BT_THIRD_PARTY}/cld2" OFF)
file(LOCK "${_BT_THIRD_PARTY}/.vommet-source.lock" RELEASE)
