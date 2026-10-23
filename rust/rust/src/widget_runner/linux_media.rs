//! Vommet: WebRTC and microphone/camera access for widgets on Linux.
//!
//! WebKitGTK ships with WebRTC and media capture switched off, and denies
//! every permission request nobody answers. Call widgets need both, so they
//! are switched on here, and a widget asking for the microphone or camera
//! gets a yes/no dialog first (as Chromium asks). Other requests
//! (notifications, location, ...) are denied.
//!
//! WebKit also only lets a page start playing audible media after a click in
//! it. Watch Together starts the video when someone else presses play, so
//! pages may autoplay here, as they could in a Chromium app window.

use gtk::prelude::*;
use log::info;
use webkit2gtk::{
    AutoplayPolicy, PermissionRequestExt, PolicyDecisionExt, PolicyDecisionType, SettingsExt,
    UserMediaPermissionRequest, WebViewExt, WebsitePolicies,
};
use wry::WebViewExtUnix;

pub fn enable(webview: &wry::WebView, window: &gtk::ApplicationWindow) {
    let view = webview.webview();

    if let Some(settings) = WebViewExt::settings(&view) {
        settings.set_enable_webrtc(true);
        settings.set_enable_media_stream(true);
    }

    // Website policies can only be given with a navigation decision. The
    // runner sets no navigation handler, so nothing else answers these.
    view.connect_decide_policy(|_, decision, kind| {
        if kind != PolicyDecisionType::NavigationAction {
            return false;
        }
        let policies = WebsitePolicies::builder()
            .autoplay(AutoplayPolicy::Allow)
            .build();
        decision.use_with_policies(&policies);
        true
    });

    let window = window.clone();
    view.connect_permission_request(move |_, request| {
        if request.downcast_ref::<UserMediaPermissionRequest>().is_none() {
            info!("Denying a non-media permission request");
            request.deny();
            return true;
        }

        let dialog = gtk::MessageDialog::new(
            Some(&window),
            gtk::DialogFlags::MODAL | gtk::DialogFlags::DESTROY_WITH_PARENT,
            gtk::MessageType::Question,
            gtk::ButtonsType::None,
            "This widget wants to use your microphone or camera.",
        );
        dialog.add_button("Block", gtk::ResponseType::Reject);
        dialog.add_button("Allow", gtk::ResponseType::Accept);
        dialog.set_default_response(gtk::ResponseType::Reject);

        let request = request.clone();
        dialog.connect_response(move |dialog, response| {
            if response == gtk::ResponseType::Accept {
                info!("Media permission allowed");
                request.allow();
            } else {
                info!("Media permission blocked");
                request.deny();
            }
            dialog.close();
        });
        dialog.show_all();
        true
    });
}
