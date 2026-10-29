//! Vommet issue 801: list the sticker and emoji packs of a Telegram account
//! (QR login, read-only, signed out straight away). The Telegram side lives
//! in `vommet_telegram`; Dart only gets these few calls, so it can't send
//! any other Telegram method.

use crate::frb_generated::StreamSink;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum TelegramImportEventKind {
    /// `login_url` is set: show it as a QR code (or open it in Telegram).
    LoginUrl,
    /// Ask for the cloud password; `password_hint`, `password_wrong`.
    PasswordNeeded,
    SignedIn,
    /// `packs` is set.
    Packs,
    SignedOut,
    SignOutUnconfirmed,
    /// `failure` is set.
    Failed,
}

#[derive(Clone)]
pub struct TelegramImportEvent {
    pub kind: TelegramImportEventKind,
    pub login_url: Option<String>,
    /// Unix seconds.
    pub login_url_expires_at: i64,
    pub password_hint: Option<String>,
    pub password_wrong: bool,
    pub packs: Vec<TelegramPack>,
    pub failure: Option<String>,
}

#[derive(Clone)]
pub struct TelegramPack {
    pub short_name: String,
    pub title: String,
    pub count: i32,
    pub emoji: bool,
}

/// Runs one import off the UI thread; the stream ends when the Telegram
/// session is gone. Answer with the other `telegram_import_*` calls.
#[cfg(not(target_family = "wasm"))]
pub fn telegram_import_run(
    job: i32,
    api_id: i32,
    api_hash: String,
    app_version: String,
    system_version: String,
    lang_code: String,
    sink: StreamSink<TelegramImportEvent>,
) -> anyhow::Result<()> {
    use vommet_telegram::{run_blocking, Event, Params};

    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    jobs::insert(job, tx);
    run_blocking(
        Params {
            api_id,
            api_hash,
            app_version,
            system_version,
            lang_code,
        },
        rx,
        |event| {
            let mut out = TelegramImportEvent {
                kind: TelegramImportEventKind::Failed,
                login_url: None,
                login_url_expires_at: 0,
                password_hint: None,
                password_wrong: false,
                packs: Vec::new(),
                failure: None,
            };
            match event {
                Event::LoginUrl { url, expires_at } => {
                    out.kind = TelegramImportEventKind::LoginUrl;
                    out.login_url = Some(url);
                    out.login_url_expires_at = expires_at;
                }
                Event::PasswordNeeded { hint, wrong } => {
                    out.kind = TelegramImportEventKind::PasswordNeeded;
                    out.password_hint = hint;
                    out.password_wrong = wrong;
                }
                Event::SignedIn => out.kind = TelegramImportEventKind::SignedIn,
                Event::Packs(packs) => {
                    out.kind = TelegramImportEventKind::Packs;
                    out.packs = packs
                        .into_iter()
                        .map(|p| TelegramPack {
                            short_name: p.short_name,
                            title: p.title,
                            count: p.count,
                            emoji: p.emoji,
                        })
                        .collect();
                }
                Event::SignedOut => out.kind = TelegramImportEventKind::SignedOut,
                Event::SignOutUnconfirmed => out.kind = TelegramImportEventKind::SignOutUnconfirmed,
                Event::Failed(reason) => out.failure = Some(reason),
            }
            let _ = sink.add(out);
        },
    );
    jobs::remove(job);
    Ok(())
}

#[cfg(target_family = "wasm")]
pub fn telegram_import_run(
    job: i32,
    api_id: i32,
    api_hash: String,
    app_version: String,
    system_version: String,
    lang_code: String,
    sink: StreamSink<TelegramImportEvent>,
) -> anyhow::Result<()> {
    let _ = (job, api_id, api_hash, app_version, system_version, lang_code, sink);
    anyhow::bail!("Telegram import isn't available on the web")
}

/// The cloud password for a `PasswordNeeded` event.
#[flutter_rust_bridge::frb(sync)]
pub fn telegram_import_password(job: i32, password: String) {
    #[cfg(not(target_family = "wasm"))]
    jobs::send(
        job,
        vommet_telegram::Command::Password(zeroize::Zeroizing::new(password)),
    );
    #[cfg(target_family = "wasm")]
    let _ = (job, password);
}

#[flutter_rust_bridge::frb(sync)]
pub fn telegram_import_retry_sign_out(job: i32) {
    #[cfg(not(target_family = "wasm"))]
    jobs::send(job, vommet_telegram::Command::RetrySignOut);
    #[cfg(target_family = "wasm")]
    let _ = job;
}

/// Stops the import; signs out first if the account might be signed in.
/// Also call it when the user leaves the sign-out screen.
#[flutter_rust_bridge::frb(sync)]
pub fn telegram_import_cancel(job: i32) {
    #[cfg(not(target_family = "wasm"))]
    jobs::send(job, vommet_telegram::Command::Cancel);
    #[cfg(target_family = "wasm")]
    let _ = job;
}

#[cfg(not(target_family = "wasm"))]
mod jobs {
    use std::collections::HashMap;
    use std::sync::{Mutex, OnceLock};

    use tokio::sync::mpsc::UnboundedSender;
    use vommet_telegram::Command;

    fn jobs() -> &'static Mutex<HashMap<i32, UnboundedSender<Command>>> {
        static JOBS: OnceLock<Mutex<HashMap<i32, UnboundedSender<Command>>>> = OnceLock::new();
        JOBS.get_or_init(Default::default)
    }

    pub(super) fn insert(job: i32, tx: UnboundedSender<Command>) {
        jobs().lock().unwrap().insert(job, tx);
    }

    pub(super) fn remove(job: i32) {
        jobs().lock().unwrap().remove(&job);
    }

    pub(super) fn send(job: i32, command: Command) {
        if let Some(tx) = jobs().lock().unwrap().get(&job) {
            let _ = tx.send(command);
        }
    }
}
