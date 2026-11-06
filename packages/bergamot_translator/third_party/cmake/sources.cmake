# Vommet: fetch the pinned C++ sources at configure time.
#
# Upstream ships bergamot-translator and CLD2 as git submodules, which pub path
# packages don't carry. This clones the exact commits upstream pins (git checks
# every object against the commit hash), initialises their submodules at the
# commits those trees record, and applies the patches in ../patches once, in
# name order (00 = upstream's, 01+ = Vommet's). The checkout lives next to this
# file (git-ignored) so repeat builds reuse it; changing a patch re-fetches.
# Windows: line endings stay as committed (the patches expect LF), long paths
# are allowed, and `patch` comes from Git for Windows.
#
# Set BERGAMOT_SOURCES_OFFLINE=ON to fail instead of touching the network.

set(BERGAMOT_TRANSLATOR_REPO "https://github.com/DavidVentura/bergamot-translator.git")
set(BERGAMOT_TRANSLATOR_COMMIT "96c0fcca3c1ddd89fb1f75e8ff952417ae9e5c45")
set(CLD2_REPO "https://github.com/CLD2Owners/cld2.git")
set(CLD2_COMMIT "b56fa78a2fe44ac2851bae5bf4f4693a0644da7b")

set(_BT_THIRD_PARTY "${CMAKE_CURRENT_LIST_DIR}/..")
get_filename_component(_BT_THIRD_PARTY "${_BT_THIRD_PARTY}" ABSOLUTE)
file(GLOB _BT_PATCHES "${_BT_THIRD_PARTY}/patches/*.patch")
list(SORT _BT_PATCHES)
set(_BT_PATCHES_HASH "")
foreach(p IN LISTS _BT_PATCHES)
  file(SHA256 "${p}" h)
  string(APPEND _BT_PATCHES_HASH "${h}")
endforeach()
string(SHA256 _BT_PATCHES_HASH "${_BT_PATCHES_HASH}")

find_package(Git REQUIRED)
set(_BT_GIT ${GIT_EXECUTABLE} -c core.autocrlf=false -c core.longpaths=true)

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
  set(want "${commit}")
  if(name STREQUAL "bergamot-translator")
    set(want "${commit} ${_BT_PATCHES_HASH}")
  endif()
  if(EXISTS "${stamp}")
    file(READ "${stamp}" have)
    string(STRIP "${have}" have)
    if(have STREQUAL want)
      return()
    endif()
  endif()
  if(BERGAMOT_SOURCES_OFFLINE)
    message(FATAL_ERROR "bergamot sources: ${name} ${commit} missing at ${dir} and BERGAMOT_SOURCES_OFFLINE is set")
  endif()
  message(STATUS "bergamot sources: fetching ${name} ${commit}")
  file(REMOVE_RECURSE "${dir}")
  file(MAKE_DIRECTORY "${dir}")
  _bt_run(${_BT_GIT} -C "${dir}" init -q)
  _bt_run(${_BT_GIT} -C "${dir}" config core.autocrlf false)
  _bt_run(${_BT_GIT} -C "${dir}" config core.longpaths true)
  _bt_run(${_BT_GIT} -C "${dir}" fetch -q --depth 1 "${repo}" "${commit}")
  _bt_run(${_BT_GIT} -C "${dir}" -c advice.detachedHead=false checkout -q FETCH_HEAD)
  execute_process(COMMAND ${GIT_EXECUTABLE} -C "${dir}" rev-parse HEAD OUTPUT_VARIABLE got OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT got STREQUAL commit)
    message(FATAL_ERROR "bergamot sources: ${name} is at ${got}, expected ${commit}")
  endif()
  if(recursive)
    _bt_run(${_BT_GIT} -C "${dir}" submodule update -q --init --recursive --depth 1 --jobs 4)
  endif()
  if(name STREQUAL "bergamot-translator")
    # The patches are written against the plugin root (third_party/bergamot-translator/...).
    get_filename_component(_git_dir "${GIT_EXECUTABLE}" DIRECTORY)
    find_program(_BT_PATCH_TOOL patch REQUIRED HINTS "${_git_dir}/../usr/bin" "${_git_dir}/../../usr/bin")
    foreach(p IN LISTS _BT_PATCHES)
      _bt_run(${_BT_PATCH_TOOL} -p3 -s --binary -d "${dir}" -i "${p}")
    endforeach()
  endif()
  file(WRITE "${stamp}" "${want}\n")
endfunction()

file(LOCK "${_BT_THIRD_PARTY}/.vommet-source.lock" GUARD PROCESS TIMEOUT 1800)
_bt_fetch(bergamot-translator "${BERGAMOT_TRANSLATOR_REPO}" "${BERGAMOT_TRANSLATOR_COMMIT}" "${_BT_THIRD_PARTY}/bergamot-translator" ON)
_bt_fetch(cld2 "${CLD2_REPO}" "${CLD2_COMMIT}" "${_BT_THIRD_PARTY}/cld2" OFF)
file(LOCK "${_BT_THIRD_PARTY}/.vommet-source.lock" RELEASE)
