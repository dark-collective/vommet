//! The only Telegram methods this crate can send. [`Caller`] is the one
//! holder of the connection, and it only takes requests that implement
//! [`Allowed`], which is sealed: adding a method means adding it to the
//! `allow!` list below, where review will see it. Anything else fails to
//! compile. (`initConnection` and `help.getConfig` are sent by grammers when
//! it opens a connection.)

use grammers_mtsender::{InvocationError, SenderPoolFatHandle, SenderPoolHandle};
use grammers_tl_types::{self as tl, RemoteCall};

mod sealed {
    pub trait Sealed {}
}

pub(crate) trait Allowed: RemoteCall + sealed::Sealed {}

macro_rules! allow {
    ($($method:ty),* $(,)?) => {
        $(
            impl sealed::Sealed for $method {}
            impl Allowed for $method {}
        )*
    };
}

allow!(
    // QR login
    tl::functions::auth::ExportLoginToken,
    tl::functions::auth::ImportLoginToken,
    // Two-step verification
    tl::functions::account::GetPassword,
    tl::functions::auth::CheckPassword,
    // The pack lists
    tl::functions::messages::GetAllStickers,
    tl::functions::messages::GetEmojiStickers,
    // Signing out
    tl::functions::auth::LogOut,
);

/// Sends allowed requests to the account's data center.
pub(crate) struct Caller {
    handle: SenderPoolHandle,
    pub(crate) dc: i32,
}

impl Caller {
    pub(crate) fn new(pool: &SenderPoolFatHandle, dc: i32) -> Self {
        Self {
            handle: pool.thin.clone(),
            dc,
        }
    }

    pub(crate) async fn invoke<R: Allowed>(&self, request: &R) -> Result<R::Return, InvocationError> {
        self.handle.invoke_in_dc(self.dc, request).await
    }

    pub(crate) fn quit(&self) {
        self.handle.quit();
    }
}

#[cfg(test)]
mod tests {
    /// Nothing outside this file may reach the connection directly.
    #[test]
    fn only_the_allowlist_sends_requests() {
        let src = concat!(env!("CARGO_MANIFEST_DIR"), "/src");
        for entry in std::fs::read_dir(src).unwrap() {
            let path = entry.unwrap().path();
            if path.file_name().unwrap() == "allowlist.rs" {
                continue;
            }
            let text = std::fs::read_to_string(&path).unwrap();
            for needle in ["invoke_in_dc", "raw_invoke", "SenderPoolHandle", ".thin"] {
                assert!(
                    !text.contains(needle),
                    "{} uses `{needle}`; send requests through allowlist::Caller",
                    path.display()
                );
            }
        }
    }
}
