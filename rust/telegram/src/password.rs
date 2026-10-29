//! Two-step verification: the SRP proof for `auth.checkPassword`, worked
//! out on this device so the password itself is never sent.

use grammers_crypto::two_factor_auth::{calculate_2fa, check_p_and_g};
use grammers_tl_types as tl;
use zeroize::Zeroize;

/// The proof for [`tl::functions::auth::CheckPassword`], or None when
/// Telegram's parameters fail the checks its SRP documentation asks for.
pub(crate) fn srp_proof(
    info: &tl::types::account::Password,
    password: &[u8],
) -> Option<tl::enums::InputCheckPasswordSrp> {
    let tl::enums::PasswordKdfAlgo::Sha256Sha256Pbkdf2Hmacsha512iter100000Sha256ModPow(algo) =
        info.current_algo.as_ref()?
    else {
        return None;
    };
    let g_b = info.srp_b.clone()?;
    let srp_id = info.srp_id?;
    if !check_p_and_g(&algo.p, &algo.g) || !between_one_and_p_minus_one(&g_b, &algo.p) {
        return None;
    }

    // grammers' own client takes `a` straight from the server's
    // secure_random; mix in our own randomness so the secret is ours.
    let mut a = vec![0u8; 256];
    getrandom::fill(&mut a).ok()?;
    for (byte, server) in a.iter_mut().zip(&info.secure_random) {
        *byte ^= server;
    }
    let (m1, g_a) = calculate_2fa(&algo.salt1, &algo.salt2, &algo.p, &algo.g, g_b, a.clone(), password);
    a.zeroize();

    Some(tl::enums::InputCheckPasswordSrp::Srp(tl::types::InputCheckPasswordSrp {
        srp_id,
        a: g_a.to_vec(),
        m1: m1.to_vec(),
    }))
}

/// 1 < value < p - 1, both big-endian. p is an odd prime (checked first),
/// so p - 1 only differs from p in its last byte.
fn between_one_and_p_minus_one(value: &[u8], p: &[u8]) -> bool {
    let value = trim(value);
    let p = trim(p);
    let Some((&last, rest)) = p.split_last() else {
        return false;
    };
    let mut p_minus_one = rest.to_vec();
    p_minus_one.push(last.wrapping_sub(1));
    greater(value, &[1]) && greater(trim(&p_minus_one), value)
}

fn trim(bytes: &[u8]) -> &[u8] {
    let start = bytes.iter().position(|&b| b != 0).unwrap_or(bytes.len());
    &bytes[start..]
}

/// a > b for trimmed big-endian numbers.
fn greater(a: &[u8], b: &[u8]) -> bool {
    match a.len().cmp(&b.len()) {
        std::cmp::Ordering::Equal => a > b,
        other => other == std::cmp::Ordering::Greater,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn g_b_range() {
        let p = [0x00, 0x01, 0x07]; // 263
        assert!(!between_one_and_p_minus_one(&[0], &p));
        assert!(!between_one_and_p_minus_one(&[1], &p));
        assert!(between_one_and_p_minus_one(&[2], &p));
        assert!(between_one_and_p_minus_one(&[0, 0, 0xff], &p));
        assert!(between_one_and_p_minus_one(&[1, 5], &p)); // 261
        assert!(!between_one_and_p_minus_one(&[1, 6], &p)); // 262 = p - 1
        assert!(!between_one_and_p_minus_one(&[1, 7], &p));
        assert!(!between_one_and_p_minus_one(&[2, 0], &p));
    }

    #[test]
    fn no_proof_without_srp_parameters() {
        let info = tl::types::account::Password {
            has_recovery: false,
            has_secure_values: false,
            has_password: false,
            current_algo: None,
            srp_b: None,
            srp_id: None,
            hint: None,
            email_unconfirmed_pattern: None,
            new_algo: tl::enums::PasswordKdfAlgo::Unknown,
            new_secure_algo: tl::enums::SecurePasswordKdfAlgo::Unknown,
            secure_random: vec![0; 256],
            pending_reset_date: None,
            login_email_pattern: None,
        };
        assert!(srp_proof(&info, b"password").is_none());
    }
}
