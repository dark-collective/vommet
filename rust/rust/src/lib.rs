pub mod api;
mod frb_generated;

// Links the voice filter in, which exports its C functions from this library.
pub use vommet_voice;

#[cfg(any(target_os = "windows", target_os = "linux"))]
mod widget_runner;

#[no_mangle]
pub extern "C" fn commet_widget_runner() {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        widget_runner::run();
    }
}
