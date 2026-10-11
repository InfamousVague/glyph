//! The crypto of stage 7 held to the web app's own (docs/STAGE7.md): `fixtures/crypto_web.json` is what
//! `tauri/src/app/core/sync/crypto.ts`, `core/orgs/wrap.ts`, `core/live/wire.ts` and `share/share.ts` sealed,
//! at the real 600,000 rounds (tool/crypto_vectors.mjs make). Every test here opens some of it through the
//! commands the app calls.
//!
//! And the reverse: the last test seals the same kinds of thing with those commands and writes them to
//! `target/vectors/crypto_from_rust.json`, which `node tool/crypto_vectors.mjs check` opens with the web code.

use serde_json::{json, Value};

const NOT_OPENED: &str = "That could not be opened: it was sealed with another key, or for something else, or it has been changed.";
const NEWER: &str = "This was sealed by a newer Ghost.md. Update the app to read it.";
const WRONG_SECRET: &str = "That password or recovery code does not open this account's key.";

fn fixture() -> Value {
    serde_json::from_str(include_str!("fixtures/crypto_web.json")).expect("fixtures/crypto_web.json")
}

fn ask(command: &str, args: Value) -> Value {
    ghost_core::dispatch::invoke(command, args).unwrap_or_else(|e| panic!("{command}: {e}"))
}

fn refused(command: &str, args: Value) -> String {
    ghost_core::dispatch::invoke(command, args).expect_err(command)
}

fn list<'a>(value: &'a Value, field: &str) -> &'a Vec<Value> {
    value[field].as_array().unwrap_or_else(|| panic!("no {field}"))
}

/// The web's account key, as a device that kept it would have it back at launch.
fn account(web: &Value) -> Value {
    ask("key_restore", json!({"kind": "account", "raw": web["accountKey"]}))["key"].clone()
}

/// The web's organization key, the only way a device ever has one: unwrapped with the account's pair.
fn org(web: &Value, account: &Value) -> Value {
    let pair = ask("pair_open", json!({"sealed": web["pair"]["sealed"], "accountKey": account}));
    ask("org_key_unwrap", json!({"pair": pair["key"], "wrapped": web["org"]["wrapped"], "context": web["org"]["context"]}))["key"].clone()
}

#[test]
fn a_handle_is_salted_and_a_code_normalised_as_the_web_does_it() {
    let web = fixture();
    for one in list(&web, "salts") {
        assert_eq!(ask("salt", json!({"handle": one["handle"], "kind": one["kind"]})), one["salt"], "{one}");
    }
    for one in list(&web, "codes") {
        assert_eq!(ask("normalise_code", json!({"code": one["typed"]})), one["normalised"], "{one}");
    }
}

#[test]
fn a_secret_derives_to_the_web_s_login_half_and_its_wrap_key_at_the_real_rounds() {
    let web = fixture();
    assert_eq!(web["rounds"], ghost_core::crypto::ROUNDS);
    let note = &list(&web, "sealed")[0];
    for one in list(&web, "derive") {
        // No `rounds`: the default is the real number.
        let derived = ask("derive", json!({"secret": one["secret"], "salt": one["salt"]}));
        assert_eq!(derived["login"], one["login"], "{}", one["salt"]);
        // The wrap key cannot be read out of either side; what it unwraps is the proof.
        let key = ask("account_key_unwrap", json!({"wrapped": one["wrapped"], "wrapKey": derived["wrapKey"]}));
        assert_eq!(ask("open", json!({"key": key["key"], "context": note["context"], "blob": note["blob"]})), note["value"]);
    }
    // Another password's wrap key does not open the first password's wrap.
    let wrong = ask("derive", json!({"secret": "correct horse battery stapl", "salt": web["derive"][0]["salt"], "rounds": 1000}));
    assert_eq!(refused("account_key_unwrap", json!({"wrapped": web["derive"][0]["wrapped"], "wrapKey": wrong["wrapKey"]})), WRONG_SECRET);
}

#[test]
fn every_code_of_the_web_s_recovery_sheet_unwraps_the_account_key() {
    let web = fixture();
    let sheet = &web["sheet"];
    let salt = ask("salt", json!({"handle": sheet["handle"], "kind": "recovery"}));
    let note = &list(&web, "sealed")[0];
    for (code, entry) in list(sheet, "codes").iter().zip(list(sheet, "entries")) {
        let typed = code.as_str().unwrap().to_lowercase().replace('-', " ");
        let derived = ask("derive", json!({"secret": ask("normalise_code", json!({"code": typed})), "salt": salt}));
        assert_eq!(derived["login"], entry["login"], "{code}");
        let key = ask("account_key_unwrap", json!({"wrapped": entry["wrapped"], "wrapKey": derived["wrapKey"]}));
        assert_eq!(ask("open", json!({"key": key["key"], "context": note["context"], "blob": note["blob"]})), note["value"]);
    }
}

#[test]
fn every_blob_the_web_sealed_opens_in_its_own_context_and_in_no_other() {
    let web = fixture();
    let account = account(&web);
    let org = org(&web, &account);
    let sealed = list(&web, "sealed");
    assert!(sealed.len() >= 15);
    for one in sealed {
        let (key, other) = if one["key"] == "org" { (&org, &account) } else { (&account, &org) };
        let form = one["as"].as_str().unwrap();
        let opened = ask("open", json!({"key": key, "context": one["context"], "blob": one["blob"], "as": form}));
        assert_eq!(opened, one[form], "{}", one["context"]);
        // The wrong key, the wrong context, a changed byte.
        assert_eq!(refused("open", json!({"key": other, "context": one["context"], "blob": one["blob"], "as": form})), NOT_OPENED);
        assert_eq!(refused("open", json!({"key": key, "context": format!("{}x", one["context"].as_str().unwrap()), "blob": one["blob"], "as": form})), NOT_OPENED);
        let mut bytes = ghost_core::crypto::from_base64url(one["blob"].as_str().unwrap()).unwrap();
        let last = bytes.len() - 1;
        bytes[last] ^= 1;
        assert_eq!(refused("open", json!({"key": key, "context": one["context"], "blob": ghost_core::crypto::to_base64url(&bytes), "as": form})), NOT_OPENED);
    }
    assert_eq!(refused("open", json!({"key": account, "context": web["newer"]["context"], "blob": web["newer"]["blob"]})), NEWER);
}

#[test]
fn the_web_s_pair_arrives_sealed_and_unwraps_the_organization_key() {
    let web = fixture();
    let account = account(&web);
    for sealed in ["sealed", "sealedBare"] {
        let pair = ask("pair_open", json!({"sealed": web["pair"][sealed], "accountKey": account}));
        assert_eq!(pair["public"], web["pair"]["public"], "{sealed}");
        assert_eq!(ask("key_public", json!({"key": pair["key"]})), web["pair"]["public"]);
        for wrapped in ["wrapped", "wrappedAgain"] {
            // As bytes, the way the web's `unwrapWith` answers, and taken up as its `importKey` takes them.
            let raw = ask("unwrap_with", json!({"pair": pair["key"], "wrapped": web["org"][wrapped], "context": web["org"]["context"]}));
            let imported = ask("seal_key_import", json!({"raw": raw}));
            let update = list(&web, "sealed").iter().find(|one| one["context"] == "org:org-1:note:n1:update").unwrap();
            assert_eq!(ask("open", json!({"key": imported["key"], "context": update["context"], "blob": update["blob"], "as": "data"})), update["data"]);
            let key = ask("org_key_unwrap", json!({"pair": pair["key"], "wrapped": web["org"][wrapped], "context": web["org"]["context"]}));
            // The same key both times: it opens what the web sealed under the organization's.
            let team = list(&web, "sealed").iter().find(|one| one["context"] == "org:org-1:note:n1").unwrap();
            assert_eq!(ask("open", json!({"key": key["key"], "context": team["context"], "blob": team["blob"]})), team["value"]);
        }
        // Another generation, another organization: the wrap opens in neither.
        for context in ["org-key:org-1:4", "org-key:org-2:3"] {
            let said = refused("org_key_unwrap", json!({"pair": pair["key"], "wrapped": web["org"]["wrapped"], "context": context}));
            assert_eq!(said, "That wrap is not for this account, or not for this organization.");
        }
    }
    // The JWK as the web exported it, taken as its `importEncryptionKey` takes it.
    assert_eq!(ask("pair_import_jwk", json!({"jwk": web["pair"]["jwk"]}))["public"], web["pair"]["public"]);
    // Another account's pair.
    let other = ask("pair_new", json!({}));
    assert!(ghost_core::dispatch::invoke("org_key_unwrap", json!({"pair": other["key"], "wrapped": web["org"]["wrapped"], "context": web["org"]["context"]})).is_err());
}

#[test]
fn the_device_key_signs_as_the_web_s_does() {
    let web = fixture();
    let device = ask("key_restore", json!({"kind": "device", "raw": web["device"]["seed"]}));
    assert_eq!(device["public"], web["device"]["public"]);
    // Ed25519 is deterministic: the same key and nonce are the same signature, byte for byte.
    for one in list(&web["device"], "signed") {
        assert_eq!(ask("device_key_sign", json!({"key": device["key"], "nonce": one["nonce"]})), one["signature"], "{}", one["nonce"]);
    }
}

#[test]
fn the_web_s_shares_open_with_their_pictures() {
    let web = fixture();
    let share = &web["share"];
    let plain = ask("share_open", json!({"key": share["key"], "blob": share["plain"]}));
    assert_eq!((&plain["shared"], &plain["pictures"]), (&share["words"], &json!([])));
    let pictured = ask("share_open", json!({"key": share["key"], "blob": share["pictured"]}));
    assert_eq!((&pictured["shared"], &pictured["pictures"]), (&share["words"], &share["pictures"]));
    assert_eq!(list(&pictured, "pictures").len(), 2);
    assert_eq!(refused("share_open", json!({"key": ask("share_key_new", json!({})), "blob": share["pictured"]})), NOT_OPENED);
}

#[test]
fn fingerprints_ids_and_base64url_are_the_web_s() {
    let web = fixture();
    for one in list(&web, "sha") {
        assert_eq!(ask("sha256_16", json!({"data": one["data"]})), one["sha"]);
    }
    for one in list(&web, "base64url") {
        let bytes = ghost_core::crypto::from_base64url(one["standard"].as_str().unwrap()).unwrap();
        assert_eq!(ghost_core::crypto::to_base64url(&bytes), one["url"]);
        assert_eq!(ghost_core::crypto::from_base64url(one["url"].as_str().unwrap()).unwrap(), bytes);
    }
    let (ours, theirs) = (ask("short_id", json!({})), web["shortId"].as_str().unwrap());
    assert_eq!(ours.as_str().unwrap().len(), theirs.len());
}

/// What `node tool/crypto_vectors.mjs check` opens with the web code.
#[test]
fn what_rust_seals_is_written_down_for_the_web_code_to_open() {
    let web = fixture();
    let b64 = ghost_core::crypto::to_base64url;
    // The web's account key as a device has it to wrap again: unwrapped with its password, extractable.
    let first = &web["derive"][0];
    let password = ask("derive", json!({"secret": first["secret"], "salt": first["salt"]}));
    let account = ask("account_key_unwrap", json!({"wrapped": first["wrapped"], "wrapKey": password["wrapKey"], "extractable": true}))["key"].clone();

    // Secrets, at the real rounds: the login half, and the web's account key wrapped under this side's wrap key.
    let mut derive = Vec::new();
    for (secret, salt) in [("correct horse battery staple", "glyph/v1/matt"), ("pässwörd ✓ 😀 with spaces", "glyph/v1/élodie σ"), ("ABCDEFGHJKLM", "glyph/v1/recovery/matt"), ("", "glyph/v1/nobody")] {
        let derived = ask("derive", json!({"secret": secret, "salt": salt}));
        let wrapped = ask("account_key_wrap", json!({"key": account, "wrapKey": derived["wrapKey"]}));
        derive.push(json!({"secret": secret, "salt": salt, "rounds": ghost_core::crypto::ROUNDS, "login": derived["login"], "wrapped": wrapped}));
    }
    let salts: Vec<Value> = [("Matt", "password"), ("  MattsSoftware\n", "password"), ("ÉLODIE Σ", "password"), ("ΌΣΟΣ İ", "password"), (" Matt ", "recovery")]
        .iter()
        .map(|(handle, kind)| json!({"handle": handle, "kind": kind, "salt": ask("salt", json!({"handle": handle, "kind": kind}))}))
        .collect();
    let codes: Vec<Value> = ["abcd-efgh ijkl", " 2345_6789\tzzzz ", "ébcd-1234"].iter().map(|typed| json!({"typed": typed, "normalised": ask("normalise_code", json!({"code": typed}))})).collect();
    let mut sheet = ask("recovery_sheet", json!({"handle": "Matt", "key": account}));
    sheet["handle"] = json!("Matt");

    // A pair made here, as the account's other devices will read it; and an organization key made here, wrapped
    // for the web's pair and for this one.
    let pair = ask("pair_new", json!({}));
    let pair_sealed = ask("pair_seal", json!({"key": pair["key"], "accountKey": account}));
    let org = ask("org_key_new", json!({}))["key"].clone();
    let context = "org-key:org-1:3";
    let for_web = ask("org_key_wrap", json!({"key": org, "public": web["pair"]["public"], "context": context}));
    let for_rust = ask("org_key_wrap", json!({"key": org, "public": pair["public"], "context": context}));
    // And the other road: the JWK exported for the caller to seal, and a key wrapped from its bytes.
    let exported = ask("pair_export_jwk", json!({"key": pair["key"]}));
    let sealed_by_caller = ask("seal", json!({"key": account, "context": "encryption-key", "value": exported}));
    let raw: Vec<u8> = (0..32u8).map(|i| i.wrapping_mul(11).wrapping_add(3)).collect();
    let raw_for_web = ask("wrap_for", json!({"public": web["pair"]["public"], "raw": b64(&raw), "context": context}));

    // A blob in every context.
    let note = json!({"v": 1, "note": {"id": "n1", "body": "# Weekend trip\n\nBook the cabin. día ✓ 😀\n", "createdAt": 1759000000000u64, "updatedAt": 1759000001234u64, "source": "editor", "starred": true, "archivedAt": null, "path": "Inbox/Weekend trip.md", "scale": 1.25}});
    let png: Vec<u8> = b"\x89PNG\r\n\x1a\n".iter().copied().chain((0..4000u32).map(|i| (i * 31 + (i >> 5)) as u8)).collect();
    let update: Vec<u8> = (0..41u8).map(|i| i.wrapping_mul(7)).collect();
    let mut sealed = Vec::new();
    let mut value = |key: &Value, who: &str, context: &str, value: Value| {
        let blob = ask("seal", json!({"key": key, "context": context, "value": value}));
        sealed.push(json!({"key": who, "context": context, "as": "value", "value": value, "blob": blob}));
    };
    value(&account, "account", "note:n1", note.clone());
    value(&account, "account", "prefs", json!({"v": 1, "theme": "dark", "workspaces": {"list": ["Work", "Home"], "notes": {"n1": "Work"}}, "trash": {"n9": 1759000000000u64}}));
    value(&account, "account", "notification:AAAAAAAAAAAAAAAAAAAAAA", json!({"kind": "mention", "note": "n1", "by": "sam"}));
    value(&account, "account", "prefs", json!("just a string"));
    value(&org, "org", "org:org-1:note:n1", json!({"v": 1, "note": note["note"], "by": "matt"}));
    let mut data = |key: &Value, who: &str, context: &str, bytes: &[u8]| {
        let blob = ask("seal", json!({"key": key, "context": context, "data": b64(bytes)}));
        sealed.push(json!({"key": who, "context": context, "as": "data", "data": b64(bytes), "blob": blob}));
    };
    data(&account, "account", "file:i-png-a1b2-c3", &png);
    data(&account, "account", "file:r-n1", b"RIFF and then the sound");
    data(&account, "account", "file:v-n1", br#"{"v":1,"versions":[]}"#);
    data(&account, "account", "recording:a", &png.repeat(15));
    data(&account, "account", "prefs", b"");
    data(&org, "org", "org:org-1:note:n1:update", &update);
    data(&org, "org", "file:i-jpg-team", &[0xff, 0xd8, 0xff, 0xe0, 1, 2]);
    // Text, sealed as the app writes its own JSON.
    let text = r#"{"v":1,"note":{"id":"n2","body":"día ✓ 😀","updatedAt":1759000001234.0}}"#;
    let blob = ask("seal", json!({"key": account, "context": "note:n2", "text": text}));
    sealed.push(json!({"key": "account", "context": "note:n2", "as": "value", "value": serde_json::from_str::<Value>(text).unwrap(), "blob": blob}));

    // Live typing: a kind byte and a payload, sealed for the relay, as wire.ts lays an envelope out.
    let mut live = Vec::new();
    for (key, org_id, room, kind, payload) in [(&account, None, "n1", 3u8, &update[..]), (&org, Some("org-1"), "n1", 3, &update[..]), (&org, Some("org-1"), "presence", 4, &png[..30]), (&account, None, "n1", 1, &[][..])] {
        let envelope: Vec<u8> = std::iter::once(kind).chain(payload.iter().copied()).collect();
        let context = match org_id {
            Some(org_id) => format!("live:org:{org_id}:{room}"),
            None => format!("live:{room}"),
        };
        let blob = ask("seal", json!({"key": key, "context": context, "data": b64(&envelope)}));
        live.push(json!({"org": org_id, "room": room, "kind": kind, "payload": b64(payload), "blob": blob}));
    }

    // A file sealed where it lies.
    let dir = std::env::temp_dir().join(format!("ghost-crypto-vectors-{}", ask("new_id", Value::Null).as_str().unwrap()));
    std::fs::create_dir_all(&dir).unwrap();
    let wav: Vec<u8> = b"RIFF".iter().copied().chain((0..200_000u32).map(|i| (i * 13) as u8)).collect();
    std::fs::write(dir.join("n1.wav"), &wav).unwrap();
    ask("seal_file", json!({"key": account, "context": "file:r-n1", "path": dir.join("n1.wav"), "out": dir.join("n1.sealed")}));
    let file = json!({"context": "file:r-n1", "data": b64(&wav), "sealed": b64(&std::fs::read(dir.join("n1.sealed")).unwrap())});
    std::fs::remove_dir_all(&dir).unwrap();

    // The device key.
    let device = ask("device_key_new", json!({}));
    let signed: Vec<Value> = ["nonce-1", "", "dQw4w9WgXcQ-día-😀"].iter().map(|nonce| json!({"nonce": nonce, "signature": ask("device_key_sign", json!({"key": device["key"], "nonce": nonce}))})).collect();

    // Shares.
    let key = ask("share_key_new", json!({}));
    let words = json!({"v": 1, "kind": "book", "title": "Trip", "pages": [{"title": "Trip", "body": "# Trip\n\n![](image/a1.png)\n"}, {"title": "Day one", "body": "We left. ![view](image/b-2.jpg)\n"}], "at": 1759000003000u64});
    let pictures = json!([["a1.png", b64(&png)], ["b-2.jpg", b64(&[0xff, 0xd8, 0xff, 0xe0, 9, 9, 9])]]);
    let share = json!({
        "key": key,
        "words": words,
        "pictures": pictures,
        "plain": ask("share_seal", json!({"key": key, "shared": words})),
        "pictured": ask("share_seal", json!({"key": key, "shared": words, "pictures": pictures})),
    });

    let sha: Vec<Value> = [&b""[..], b"abc", &png, &wav].iter().map(|bytes| json!({"data": b64(bytes), "sha": ask("sha256_16", json!({"data": b64(bytes)}))})).collect();
    let short_ids: Vec<Value> = (0..4).map(|_| ask("short_id", json!({}))).collect();

    let out = json!({
        "fixture": web["made"],
        "derive": derive,
        "salts": salts,
        "codes": codes,
        "sheet": sheet,
        "pair": {"sealed": pair_sealed, "sealedByCaller": sealed_by_caller, "public": pair["public"]},
        "org": {"context": context, "wrappedForWeb": for_web, "wrappedForRust": for_rust, "raw": b64(&raw), "rawWrappedForWeb": raw_for_web},
        "sealed": sealed,
        "live": live,
        "file": file,
        "device": {"public": device["public"], "signed": signed},
        "share": share,
        "sha": sha,
        "shortIds": short_ids,
    });
    let target = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("target/vectors");
    std::fs::create_dir_all(&target).unwrap();
    std::fs::write(target.join("crypto_from_rust.json"), serde_json::to_string(&out).unwrap()).unwrap();
}
