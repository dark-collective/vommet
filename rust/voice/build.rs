// Builds the vendored RNNoise 0.2 (BSD-3-Clause, third_party/rnnoise) into the
// library. The weights are compiled in (src/rnnoise_data.c), so nothing is
// downloaded at build or run time.
fn main() {
    let dir = "third_party/rnnoise";
    let mut build = cc::Build::new();
    build
        .include(format!("{dir}/include"))
        .include(format!("{dir}/src"))
        // Keep the C symbols out of our exported API.
        .define("RNNOISE_EXPORT", Some(""))
        // The network is too slow unoptimised, even in debug builds.
        .opt_level(2)
        .warnings(false);
    if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc") {
        build.define("_USE_MATH_DEFINES", None);
        // RNNoise's x86 header needs AVX/SSSE3 declarations that clang-cl
        // only provides with those CPU features enabled, so use the portable
        // path on Windows (cl.exe never defines __SSE2__ anyway).
        build.flag("/U__SSE2__").flag("/U__SSE__");
    }
    for file in [
        "denoise.c",
        "rnn.c",
        "pitch.c",
        "kiss_fft.c",
        "celt_lpc.c",
        "nnet.c",
        "nnet_default.c",
        "parse_lpcnet_weights.c",
        "rnnoise_data.c",
        "rnnoise_tables.c",
    ] {
        build.file(format!("{dir}/src/{file}"));
    }
    build.compile("rnnoise");
    println!("cargo:rerun-if-changed={dir}");
}
