# bergamot_translator (vendored)

On-device machine translation for Vommet (Vommet issue 680): Bergamot / Marian,
the engine behind Firefox Translations, as a Flutter FFI plugin.

Vendored from https://github.com/jesses2025smith/bergamot_translator at commit
32b33b1 (MPL-2.0, see LICENSE; these files stay under the MPL). Vommet changes:

- Platforms: Linux (x86_64, aarch64), Windows (x64, MSVC) and Android
  (arm64-v8a). macOS and iOS aren't built. Windows needs Vommet's MSVC changes:
  `third_party/patches/01-vommet-msvc-pcre2.patch` (ssplit's internal PCRE2 as
  a static `/MT` library), the static runtime everywhere, NOMINMAX and
  `if(NOT MSVC)` around the GCC-only flags.
- `third_party/cmake/sources.cmake`: the C++ sources (bergamot-translator
  `DavidVentura/bergamot-translator` 96c0fcca, CLD2 b56fa78a) are fetched at the
  pinned commits at configure time and upstream's patch is applied, because pub
  path packages carry no git submodules. `BERGAMOT_SOURCES_OFFLINE=ON` forbids
  the network.
- `third_party/cmake/third_party_config.cmake`: desktop Linux builds library-only
  with a fixed CPU floor (x86-64-v2 = SSE4.2; marian's default `native` would
  target the build machine), internal PCRE2, and the ARM/ruy path on aarch64.
- `android/build.gradle`: minSdk 24 (the app's) with the native code built for API 28
  (glob/iconv; Android 9+, older phones just lack translation), no buildscript block (the app's
  AGP applies).
- `tool/smoke.c`: a C smoke test of the API (CI only, not shipped).
- No example app, no ffigen/flutter_lints dev dependencies.

Native code is compiled only by the release builds (GitHub `vommet-linux`,
`vommet-android`, `vommet-native`); the unit-test gate never builds it.
