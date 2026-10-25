# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Set CMake policies to suppress warnings from third-party libraries
# Policy CMP0153: Suppress exec_program deprecation warning (used by FindSSE.cmake in marian-dev)
if(POLICY CMP0153)
    cmake_policy(SET CMP0153 OLD)
endif()

# Suppress deprecation warnings about cmake_minimum_required version
# These warnings come from third-party libraries
set(CMAKE_WARN_DEPRECATED OFF CACHE BOOL "Suppress CMake deprecation warnings" FORCE)

# Android platform thread configuration (must be set before project() and add_subdirectory)
# Android NDK has pthread support built-in, but CMake's FindThreads needs hints
if(ANDROID)
    message(STATUS "Configuring for Android platform - setting up thread support")
    # Include custom FindThreads for Android BEFORE project() call
    # This ensures our custom module is used instead of the default FindThreads
    list(INSERT CMAKE_MODULE_PATH 0 "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
    include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/FindThreadsAndroid.cmake)
endif()

project(bergamot_translator_library VERSION 0.0.1 LANGUAGES CXX)

# Include third-party library configurations
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../third_party third_party)

set(_BERGAMOT_TRANSLATOR_LIBTYPE SHARED)
# iOS does not support arbitrary dylibs; build a static library when cross-compiling for iOS.
# (CocoaPods will still package this plugin as a framework, and link these objects in.)
if(IOS)
  set(_BERGAMOT_TRANSLATOR_LIBTYPE STATIC)
endif()

add_library(bergamot_translator ${_BERGAMOT_TRANSLATOR_LIBTYPE}
  "bergamot_translator.cpp"
)

set_target_properties(bergamot_translator PROPERTIES
  PUBLIC_HEADER bergamot_translator.h
  OUTPUT_NAME "bergamot_translator"
)

# Set C++ standard to C++17 (required by bergamot-translator)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

target_compile_definitions(bergamot_translator PUBLIC DART_SHARED_LIB)

# Link third-party include directories and libraries
# Note: bergamot-translator must come before other libraries to ensure proper symbol resolution
# yaml-cpp must be linked before marian-data to ensure YAML::Clone symbols are available
# ssplit must be linked for SentenceSplitter symbols (used by text_processor)
# marian must be linked for ExpressionGraph and other marian core symbols (used by translation_model)
target_link_libraries(bergamot_translator PRIVATE 
    bergamot-translator
    third_party_includes
    cld2
    yaml-cpp
    marian-data
    marian  # Required for marian::ExpressionGraph and other marian core symbols
    ssplit  # Required for ug::ssplit::SentenceSplitter (used by text_processor)
)

# Add compile options to suppress warnings
target_compile_options(bergamot_translator PRIVATE
    -Wno-unused-value  # Suppress "expression result unused" warnings
    -Wno-deprecated-declarations  # Suppress deprecated iterator warnings from yaml-cpp and sprintf warnings from protobuf-lite
    -Wno-unknown-pragmas  # Suppress pragma diagnostic pop warnings from marian-dev/src/functional/operators.h
)

# macOS platform configuration
if(APPLE AND NOT IOS)
    if(CMAKE_OSX_ARCHITECTURES MATCHES "arm64")
        target_compile_definitions(bergamot_translator PRIVATE
            ARM=1
            FMA=1
            SSE=1
            USE_SIMD_UTILS=1
            __ARM_NEON=1
            __ARM_NEON__=1
        )
    elseif(CMAKE_OSX_ARCHITECTURES MATCHES "x86_64")
        target_compile_options(bergamot_translator PRIVATE
            -msse4.1
        )
    endif()
endif()

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(bergamot_translator PRIVATE "-Wl,-z,max-page-size=16384")
endif()
