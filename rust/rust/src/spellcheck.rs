//! Spellchecking for the message box (Vommet). Hunspell dictionaries are parsed by
//! `spellbook` (pure Rust, no system library). Called from Dart over plain FFI
//! (commet/lib/utils/spellcheck/spellcheck_ffi.dart), not flutter_rust_bridge, so
//! frb_generated stays untouched.

use std::ffi::{c_char, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::slice;

use spellbook::Dictionary;

/// Decodes a dictionary file using the `SET` encoding named in its .aff file.
fn decode(bytes: &[u8], encoding: &'static encoding_rs::Encoding) -> String {
    let (text, _, _) = encoding.decode(bytes);
    text.into_owned()
}

/// The `SET <encoding>` line of an .aff file, UTF-8 when missing or unknown.
fn aff_encoding(aff: &[u8]) -> &'static encoding_rs::Encoding {
    for line in aff.split(|b| *b == b'\n') {
        let line = String::from_utf8_lossy(line);
        let mut parts = line.split_whitespace();
        if parts.next() == Some("SET") {
            if let Some(label) = parts.next() {
                if let Some(encoding) = encoding_rs::Encoding::for_label(label.as_bytes()) {
                    return encoding;
                }
            }
            break;
        }
    }
    encoding_rs::UTF_8
}

unsafe fn bytes<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if ptr.is_null() || len == 0 {
        &[]
    } else {
        slice::from_raw_parts(ptr, len)
    }
}

unsafe fn word<'a>(ptr: *const u8, len: usize) -> Option<&'a str> {
    std::str::from_utf8(bytes(ptr, len)).ok()
}

/// Parses a dictionary. Returns null if it can't be parsed.
///
/// # Safety
/// `aff`/`dic` must point to `aff_len`/`dic_len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn vommet_spell_open(
    aff: *const u8,
    aff_len: usize,
    dic: *const u8,
    dic_len: usize,
) -> *mut Dictionary {
    let result = catch_unwind(|| {
        let aff = bytes(aff, aff_len);
        let dic = bytes(dic, dic_len);
        let encoding = aff_encoding(aff);
        let aff = decode(aff, encoding);
        let dic = decode(dic, encoding);
        Dictionary::new(aff.trim_start_matches('\u{feff}'), dic.trim_start_matches('\u{feff}'))
            .ok()
    });
    match result {
        Ok(Some(dictionary)) => Box::into_raw(Box::new(dictionary)),
        _ => std::ptr::null_mut(),
    }
}

/// 1 = correct, 0 = misspelled, -1 = error.
///
/// # Safety
/// `dict` must come from `vommet_spell_open`; `ptr` must point to `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn vommet_spell_check(
    dict: *const Dictionary,
    ptr: *const u8,
    len: usize,
) -> i32 {
    if dict.is_null() {
        return -1;
    }
    let Some(word) = word(ptr, len) else {
        return -1;
    };
    let dict = &*dict;
    match catch_unwind(AssertUnwindSafe(|| dict.check(word))) {
        Ok(true) => 1,
        Ok(false) => 0,
        Err(_) => -1,
    }
}

/// Up to `max` suggestions joined by '\n', or null. Free with `vommet_spell_free_string`.
///
/// # Safety
/// `dict` must come from `vommet_spell_open`; `ptr` must point to `len` bytes.
#[no_mangle]
pub unsafe extern "C" fn vommet_spell_suggest(
    dict: *const Dictionary,
    ptr: *const u8,
    len: usize,
    max: usize,
) -> *mut c_char {
    if dict.is_null() {
        return std::ptr::null_mut();
    }
    let Some(word) = word(ptr, len) else {
        return std::ptr::null_mut();
    };
    let dict = &*dict;
    let result = catch_unwind(AssertUnwindSafe(|| {
        let mut out = Vec::new();
        dict.suggest(word, &mut out);
        out.truncate(max);
        out.join("\n")
    }));
    match result.ok().and_then(|s| CString::new(s).ok()) {
        Some(s) => s.into_raw(),
        None => std::ptr::null_mut(),
    }
}

/// # Safety
/// `s` must come from `vommet_spell_suggest` (or be null).
#[no_mangle]
pub unsafe extern "C" fn vommet_spell_free_string(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// # Safety
/// `dict` must come from `vommet_spell_open` (or be null) and not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn vommet_spell_close(dict: *mut Dictionary) {
    if !dict.is_null() {
        drop(Box::from_raw(dict));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const AFF: &str = "SET ISO8859-1\nSFX S Y 1\nSFX S 0 s .\n";

    fn open(aff: &[u8], dic: &[u8]) -> *mut Dictionary {
        unsafe { vommet_spell_open(aff.as_ptr(), aff.len(), dic.as_ptr(), dic.len()) }
    }

    fn check(d: *const Dictionary, w: &str) -> i32 {
        unsafe { vommet_spell_check(d, w.as_ptr(), w.len()) }
    }

    #[test]
    fn checks_and_suggests_latin1_dictionary() {
        // "café/S" encoded as ISO8859-1 (é = 0xE9).
        let dic = b"2\ncaf\xe9/S\nbook/S\n";
        let d = open(AFF.as_bytes(), dic);
        assert!(!d.is_null());
        assert_eq!(check(d, "café"), 1);
        assert_eq!(check(d, "cafés"), 1);
        assert_eq!(check(d, "books"), 1);
        assert_eq!(check(d, "bcuh"), 0);
        let s = unsafe { vommet_spell_suggest(d, "bok".as_ptr(), 3, 5) };
        assert!(!s.is_null());
        let text = unsafe { std::ffi::CStr::from_ptr(s) }.to_str().unwrap().to_owned();
        unsafe { vommet_spell_free_string(s) };
        assert!(text.split('\n').any(|w| w == "book"), "{text}");
        unsafe { vommet_spell_close(d) };
    }

    #[test]
    fn invalid_input_is_an_error_not_a_crash() {
        let d = open(b"SET UTF-8\n", b"1\nhello\n");
        assert!(!d.is_null());
        let bad = [0xffu8, 0xfe];
        assert_eq!(unsafe { vommet_spell_check(d, bad.as_ptr(), 2) }, -1);
        assert_eq!(check(std::ptr::null(), "hello"), -1);
        unsafe { vommet_spell_close(d) };
    }
}
