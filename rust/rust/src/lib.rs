pub mod api;
mod frb_generated;
#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
mod transcription;

// Links the voice filter in, which exports its C functions from this library.
pub use vommet_voice;

// Vommet: message box spellcheck, exported as plain C functions.
mod spellcheck;

#[cfg(any(target_os = "windows", target_os = "linux"))]
mod widget_runner;

#[no_mangle]
pub extern "C" fn commet_widget_runner() {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        widget_runner::run();
    }
}

#[no_mangle]
pub extern "C" fn commet_overlay() {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        overlay::run_overlay(false);
    }
}
