# Third-party library include directories

# Bergamot translator root directory
# Located at: third_party/bergamot-translator/
# Used for: 3rd_party/marian-dev/src/3rd_party/CLI/CLI.hpp, 3rd_party/yaml-cpp/yaml.h, etc.
# This is needed because parser.h includes paths relative to bergamot-translator root
set(BERGAMOT_TRANSLATOR_ROOT_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bergamot-translator")

# Bergamot translator headers
# Located at: third_party/bergamot-translator/src/
# Used for: translator/*.h includes
set(BERGAMOT_TRANSLATOR_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bergamot-translator/src")

# Marian-dev headers (dependency of bergamot-translator)
# Located at: third_party/bergamot-translator/3rd_party/marian-dev/src/
# Used for: data/types.h, data/vocab_base.h, common/*.h, etc.
set(MARIAN_DEV_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bergamot-translator/3rd_party/marian-dev/src")

# Marian-dev 3rd_party headers (for sentencepiece, absl, etc.)
# Located at: third_party/bergamot-translator/3rd_party/marian-dev/src/3rd_party/
# Used for: sentencepiece/third_party/absl/strings/string_view.h, etc.
set(MARIAN_DEV_3RD_PARTY_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bergamot-translator/3rd_party/marian-dev/src/3rd_party")

# SSplit-cpp headers (sentence splitter)
# Located at: third_party/bergamot-translator/3rd_party/ssplit-cpp/src/ssplit/
# Used for: ssplit.h (text_processor.h includes "ssplit.h")
set(SSPLIT_CPP_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bergamot-translator/3rd_party/ssplit-cpp/src/ssplit")

# CLD2 language detection headers
# Located at: third_party/cld2/public/
# Used for: compact_lang_det.h
set(CLD2_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/cld2/public")

# Create an interface library to propagate include directories
add_library(third_party_includes INTERFACE)

target_include_directories(third_party_includes INTERFACE
    ${BERGAMOT_TRANSLATOR_ROOT_INCLUDE_DIR}
    ${BERGAMOT_TRANSLATOR_INCLUDE_DIR}
    ${MARIAN_DEV_INCLUDE_DIR}
    ${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}
    ${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}/ruy  # For ruy/ruy.h (used by integer_common.h)
    ${MARIAN_DEV_3RD_PARTY_INCLUDE_DIR}/sentencepiece/src  # For SentencePiece headers (third_party/absl/strings/string_view.h)
    ${SSPLIT_CPP_INCLUDE_DIR}
    ${CLD2_INCLUDE_DIR}
)

# Set C++ standard to C++17 (required by bergamot-translator)
target_compile_features(third_party_includes INTERFACE cxx_std_17)

