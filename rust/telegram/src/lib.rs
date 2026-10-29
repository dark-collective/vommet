//! Vommet issue 801: sign in to a Telegram account by QR code just long
//! enough to list its sticker and custom emoji packs, then sign out.
//!
//! - Only the methods in [`allowlist`] can be sent.
//! - The session lives in memory ([`MemorySession`]) and is dropped when
//!   [`run_blocking`] returns. Nothing is written to disk.
//! - Signing out happens before the pack list is handed over, and is tried
//!   whenever the account might be signed in, also after a cancel or error.

mod allowlist;
mod password;

use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::Engine;
use grammers_mtsender::{ConnectionParams, InvocationError, SenderPool};
use grammers_session::storages::MemorySession;
use grammers_session::updates::UpdatesLike;
use grammers_session::Session;
use grammers_tl_types as tl;
use tokio::sync::mpsc;
use zeroize::Zeroizing;

use allowlist::Caller;

/// What Telegram shows in the new-login alert and under Settings › Devices.
pub const DEVICE_MODEL: &str = "Vommet sticker import";

/// Give up on a login nobody finishes.
const LOGIN_TIMEOUT: Duration = Duration::from_secs(10 * 60);
const SIGN_OUT_TIMEOUT: Duration = Duration::from_secs(15);

pub struct Params {
    /// From my.telegram.org. Not a user secret, but kept out of the repo.
    pub api_id: i32,
    pub api_hash: String,
    pub app_version: String,
    pub system_version: String,
    pub lang_code: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pack {
    /// The set's name in t.me/addstickers/<name> (or addemoji).
    pub short_name: String,
    pub title: String,
    pub count: i32,
    /// A custom emoji set.
    pub emoji: bool,
}

pub enum Event {
    /// Show this as a QR code, or hand it to the Telegram app, until
    /// `expires_at` (Unix seconds). A newer one replaces it.
    LoginUrl { url: String, expires_at: i64 },
    /// The account has a cloud password; answer with [`Command::Password`].
    PasswordNeeded { hint: Option<String>, wrong: bool },
    /// Signed in; reading the packs and signing out now.
    SignedIn,
    /// The installed packs. Always followed by [`Event::SignedOut`] or
    /// [`Event::SignOutUnconfirmed`].
    Packs(Vec<Pack>),
    SignedOut,
    /// Telegram didn't confirm the sign-out. [`Command::RetrySignOut`] tries
    /// again; closing the command channel ends the session for good.
    SignOutUnconfirmed,
    /// The import stopped: `timeout`, `network`, or Telegram's error name.
    /// When the account might have been signed in, a [`Event::SignedOut`] or
    /// [`Event::SignOutUnconfirmed`] follows.
    Failed(String),
}

pub enum Command {
    Password(Zeroizing<String>),
    RetrySignOut,
    Cancel,
}

/// Runs one import on the calling thread. `emit` gets every [`Event`];
/// returns once the session is gone. Closing `commands` counts as cancel.
pub fn run_blocking(
    params: Params,
    commands: mpsc::UnboundedReceiver<Command>,
    mut emit: impl FnMut(Event),
) {
    let runtime = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(e) => {
            log::warn!("Telegram import: no runtime: {e}");
            emit(Event::Failed("runtime".into()));
            return;
        }
    };
    runtime.block_on(run(params, commands, emit));
}

async fn run(
    params: Params,
    mut commands: mpsc::UnboundedReceiver<Command>,
    mut emit: impl FnMut(Event),
) {
    let session = Arc::new(MemorySession::default());
    let home_dc = session.home_dc_id().unwrap_or(2);
    let SenderPool {
        runner,
        handle,
        mut updates,
    } = SenderPool::with_configuration(
        Arc::clone(&session),
        params.api_id,
        ConnectionParams {
            device_model: DEVICE_MODEL.into(),
            system_version: params.system_version.clone(),
            app_version: params.app_version.clone(),
            system_lang_code: params.lang_code.clone(),
            lang_code: params.lang_code.clone(),
            ..Default::default()
        },
    );
    let runner = tokio::spawn(runner.run());
    let mut caller = Caller::new(&handle, home_dc);
    drop(handle);

    // Set as soon as the account might be signed in (the QR code was
    // scanned), so every way out below signs out first.
    let mut maybe_signed_in = false;
    let login = tokio::time::timeout(
        LOGIN_TIMEOUT,
        sign_in(
            &mut caller,
            &session,
            &params,
            &mut updates,
            &mut commands,
            &mut emit,
            &mut maybe_signed_in,
        ),
    )
    .await;

    let outcome = match login {
        Ok(Ok(())) => {
            emit(Event::SignedIn);
            list_packs(&caller).await.map_err(|e| Some(failure_name(&e)))
        }
        Ok(Err(End::Cancelled)) => Err(None),
        Ok(Err(End::Failed(reason))) => Err(Some(reason)),
        Err(_) => Err(Some("timeout".into())),
    };
    match outcome {
        Ok(packs) => {
            // Sign out first; the packs are only handed over afterwards.
            let signed_out = sign_out(&caller).await;
            emit(Event::Packs(packs));
            finish_sign_out(&caller, signed_out, &mut commands, &mut emit).await;
        }
        Err(reason) => {
            if let Some(reason) = reason {
                emit(Event::Failed(reason));
            }
            if maybe_signed_in {
                let signed_out = sign_out(&caller).await;
                finish_sign_out(&caller, signed_out, &mut commands, &mut emit).await;
            }
        }
    }

    caller.quit();
    let _ = runner.await;
    drop(caller);
    drop(session);
}

enum End {
    Cancelled,
    Failed(String),
}

impl From<InvocationError> for End {
    fn from(e: InvocationError) -> Self {
        End::Failed(failure_name(&e))
    }
}

async fn sign_in(
    caller: &mut Caller,
    session: &MemorySession,
    params: &Params,
    updates: &mut mpsc::Receiver<UpdatesLike>,
    commands: &mut mpsc::UnboundedReceiver<Command>,
    emit: &mut impl FnMut(Event),
    maybe_signed_in: &mut bool,
) -> Result<(), End> {
    use tl::enums::auth::LoginToken;

    loop {
        let exported = caller
            .invoke(&tl::functions::auth::ExportLoginToken {
                api_id: params.api_id,
                api_hash: params.api_hash.clone(),
                except_ids: Vec::new(),
            })
            .await;
        let token = match exported {
            Ok(token) => token,
            Err(e) if e.is("SESSION_PASSWORD_NEEDED") => {
                *maybe_signed_in = true;
                return check_password(caller, commands, emit).await;
            }
            Err(e) => return Err(e.into()),
        };
        match token {
            LoginToken::Token(token) => {
                emit(Event::LoginUrl {
                    url: login_url(&token.token),
                    expires_at: token.expires as i64,
                });
                if wait_for_scan(token.expires, updates, commands).await? {
                    *maybe_signed_in = true;
                }
                // Scanned or expired: exporting again reports the result,
                // or gives a fresh code.
            }
            LoginToken::MigrateTo(migrate) => {
                *maybe_signed_in = true;
                caller.dc = migrate.dc_id;
                let _ = session.set_home_dc_id(migrate.dc_id).await;
                let imported = caller
                    .invoke(&tl::functions::auth::ImportLoginToken {
                        token: migrate.token,
                    })
                    .await;
                match imported {
                    Ok(LoginToken::Success(_)) => return Ok(()),
                    Ok(_) => {}
                    Err(e) if e.is("SESSION_PASSWORD_NEEDED") => {
                        return check_password(caller, commands, emit).await
                    }
                    Err(e) => return Err(e.into()),
                }
            }
            LoginToken::Success(_) => {
                *maybe_signed_in = true;
                return Ok(());
            }
        }
    }
}

/// Waits until the code is scanned (true) or expires (false).
async fn wait_for_scan(
    expires: i32,
    updates: &mut mpsc::Receiver<UpdatesLike>,
    commands: &mut mpsc::UnboundedReceiver<Command>,
) -> Result<bool, End> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let left = (expires as i64 - now).clamp(1, 60) as u64;
    let expiry = tokio::time::sleep(Duration::from_secs(left));
    tokio::pin!(expiry);
    loop {
        tokio::select! {
            update = updates.recv() => match update {
                Some(update) if is_login_token_update(&update) => return Ok(true),
                Some(_) => {}
                None => return Err(End::Failed("network".into())),
            },
            _ = &mut expiry => return Ok(false),
            command = commands.recv() => match command {
                Some(Command::Cancel) | None => return Err(End::Cancelled),
                Some(_) => {}
            },
        }
    }
}

fn is_login_token_update(update: &UpdatesLike) -> bool {
    use tl::enums::{Update, Updates};
    let UpdatesLike::Updates(updates) = update else {
        return false;
    };
    match updates {
        Updates::UpdateShort(short) => matches!(short.update, Update::LoginToken),
        Updates::Updates(all) => all.updates.iter().any(|u| matches!(u, Update::LoginToken)),
        Updates::Combined(all) => all.updates.iter().any(|u| matches!(u, Update::LoginToken)),
        _ => false,
    }
}

async fn check_password(
    caller: &Caller,
    commands: &mut mpsc::UnboundedReceiver<Command>,
    emit: &mut impl FnMut(Event),
) -> Result<(), End> {
    let mut wrong = false;
    loop {
        let tl::enums::account::Password::Password(info) =
            caller.invoke(&tl::functions::account::GetPassword {}).await?;
        emit(Event::PasswordNeeded {
            hint: info.hint.clone(),
            wrong,
        });
        let password = loop {
            match commands.recv().await {
                Some(Command::Password(password)) => break password,
                Some(Command::RetrySignOut) => {}
                Some(Command::Cancel) | None => return Err(End::Cancelled),
            }
        };
        let proof = password::srp_proof(&info, password.as_bytes());
        drop(password);
        let Some(proof) = proof else {
            return Err(End::Failed("password_parameters".into()));
        };
        match caller
            .invoke(&tl::functions::auth::CheckPassword { password: proof })
            .await
        {
            Ok(tl::enums::auth::Authorization::Authorization(_)) => return Ok(()),
            Ok(tl::enums::auth::Authorization::SignUpRequired(_)) => {
                return Err(End::Failed("sign_up_required".into()))
            }
            Err(e) if e.is("PASSWORD_HASH_INVALID") => wrong = true,
            Err(e) => return Err(e.into()),
        }
    }
}

async fn list_packs(caller: &Caller) -> Result<Vec<Pack>, InvocationError> {
    let stickers = caller
        .invoke(&tl::functions::messages::GetAllStickers { hash: 0 })
        .await?;
    let emoji = caller
        .invoke(&tl::functions::messages::GetEmojiStickers { hash: 0 })
        .await?;
    Ok(packs_from(stickers, emoji))
}

fn packs_from(
    stickers: tl::enums::messages::AllStickers,
    emoji: tl::enums::messages::AllStickers,
) -> Vec<Pack> {
    let mut packs: Vec<Pack> = Vec::new();
    for (all, emoji_list) in [(stickers, false), (emoji, true)] {
        let tl::enums::messages::AllStickers::Stickers(all) = all else {
            continue;
        };
        for set in all.sets {
            let tl::enums::StickerSet::Set(set) = set;
            if set.archived || set.short_name.is_empty() {
                continue;
            }
            let duplicate = packs
                .iter()
                .any(|p| p.short_name.eq_ignore_ascii_case(&set.short_name));
            if duplicate {
                continue;
            }
            packs.push(Pack {
                short_name: set.short_name,
                title: set.title,
                count: set.count,
                emoji: emoji_list || set.emojis,
            });
        }
    }
    packs
}

/// True when Telegram confirmed the sign-out, or says there is no
/// authorization left to sign out of.
async fn sign_out(caller: &Caller) -> bool {
    let logout = caller.invoke(&tl::functions::auth::LogOut {});
    match tokio::time::timeout(SIGN_OUT_TIMEOUT, logout).await {
        Ok(Ok(_)) => true,
        Ok(Err(e)) => {
            e.is("AUTH_KEY_UNREGISTERED") || e.is("SESSION_REVOKED") || e.is("USER_DEACTIVATED*")
        }
        Err(_) => false,
    }
}

/// Reports the sign-out; while it's unconfirmed, the user can retry until
/// they leave the screen (which closes `commands`).
async fn finish_sign_out(
    caller: &Caller,
    mut signed_out: bool,
    commands: &mut mpsc::UnboundedReceiver<Command>,
    emit: &mut impl FnMut(Event),
) {
    loop {
        if signed_out {
            emit(Event::SignedOut);
            return;
        }
        emit(Event::SignOutUnconfirmed);
        loop {
            match commands.recv().await {
                Some(Command::RetrySignOut) => break,
                Some(Command::Password(_)) => {}
                Some(Command::Cancel) | None => return,
            }
        }
        signed_out = sign_out(caller).await;
    }
}

/// The `tg://login` link Telegram's apps accept, as a QR code or opened
/// directly.
fn login_url(token: &[u8]) -> String {
    format!(
        "tg://login?token={}",
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(token)
    )
}

fn failure_name(e: &InvocationError) -> String {
    match e {
        InvocationError::Rpc(rpc) => rpc.name.clone(),
        _ => "network".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn login_url_is_base64url() {
        assert_eq!(login_url(&[0xfb, 0xff, 0x01]), "tg://login?token=-_8B");
    }

    fn set(short_name: &str, archived: bool, emojis: bool) -> tl::enums::StickerSet {
        tl::enums::StickerSet::Set(tl::types::StickerSet {
            archived,
            official: false,
            masks: false,
            emojis,
            text_color: false,
            channel_emoji_status: false,
            creator: false,
            installed_date: None,
            id: 0,
            access_hash: 0,
            title: short_name.to_uppercase(),
            short_name: short_name.into(),
            thumbs: None,
            thumb_dc_id: None,
            thumb_version: None,
            thumb_document_id: None,
            count: 3,
            hash: 0,
        })
    }

    fn all(sets: Vec<tl::enums::StickerSet>) -> tl::enums::messages::AllStickers {
        tl::enums::messages::AllStickers::Stickers(tl::types::messages::AllStickers { hash: 0, sets })
    }

    #[test]
    fn packs_skip_archived_and_duplicates() {
        let packs = packs_from(
            all(vec![set("cats", false, false), set("old", true, false), set("Frogs", false, false)]),
            all(vec![set("hearts", false, true), set("frogs", false, true)]),
        );
        let names: Vec<_> = packs.iter().map(|p| (p.short_name.as_str(), p.emoji)).collect();
        assert_eq!(names, [("cats", false), ("Frogs", false), ("hearts", true)]);
    }

    #[test]
    fn not_modified_lists_are_empty() {
        let packs = packs_from(
            tl::enums::messages::AllStickers::NotModified,
            tl::enums::messages::AllStickers::NotModified,
        );
        assert!(packs.is_empty());
    }
}
