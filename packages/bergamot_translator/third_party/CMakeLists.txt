# Third-party library configuration and building
# This file includes modular CMake files from cmake/ directory

# Step 0 (Vommet): fetch the pinned bergamot-translator + CLD2 sources (pub path
# packages carry no submodules)
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/sources.cmake)

# Step 1: Load CMake configuration and policies
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/third_party_config.cmake)

# Step 2: Define include directories and create third_party_includes interface library
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/third_party_includes.cmake)

# Step 3: Build yaml-cpp library (required for bergamot-translator parser)
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/yaml_cpp.cmake)

# Step 4: Build CLD2 language detection library
# Set CLD2_DIR before including cld2.cmake for correct path resolution
set(CLD2_DIR "${CMAKE_CURRENT_SOURCE_DIR}/cld2")
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/cld2.cmake)

# Step 5: Build bergamot-translator library
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/bergamot_translator.cmake)

# Step 6: Build SentencePiece library and configure intgemm
# This must be done before marian-data because SentencePiece and intgemm targets are needed
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/sentencepiece.cmake)

# Step 7: Build marian-data library (depends on SentencePiece and intgemm)
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/marian_data.cmake)
