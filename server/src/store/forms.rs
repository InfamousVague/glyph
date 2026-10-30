//! Forms from a share link (src/forms.rs, docs/FORMS.md): which shares are forms, whose they are and whether they take
//! answers, and the answers waiting, sealed, for a device to file as tickets.
//!
//! A FORM is a share (store/shares.rs) its owner said takes answers: its id is the share's, so taking the share down
//! takes the form and every answer waiting with it (the cascade). It keeps in the clear only what the service must
//! act on without a key: its owner, the organization whose members file it (none for the owner's own), whether it is
//! open, paused or closed, whether it takes a file (the larger size), the id of the note that defines it (a random id
//! the service already holds for every synced note, so a teammate's device finds the form it files), and three counts - answers taken, waiting, and
//! filed. Its fields, its notebook and its words are in the share, which the service cannot open.
//!
//! An ANSWER is kept ONLY sealed: the browser sealed it before it was sent (src/forms.rs says how), so what is kept is
//! the wraps of its key, each to one recipient's public key, and its blob. It waits until a device has filed it and
//! said so (`ack_form_item`), or until it is thirty days old, when the sweep takes it. A device CLAIMS one before it
//! files it: a claim is held for a couple of minutes by the device that made it, so two devices of an account, or two
//! members of a team, never file one answer twice; a claim lapsed is anyone's again.

use super::Store;
use rusqlite::{params, OptionalExtension};

/// The tables, made beside store.rs's own at every open (`schema`).
pub(super) const SCHEMA: &str = r#"
-- Forms from a share link (server/src/forms.rs, docs/FORMS.md; store/forms.rs). A form is a share that takes answers:
-- its id is the share's, and it goes with the share, with its owner's account and with its organization. In the clear:
-- whose it is, which organization files it, the note that defines it (its id, as sync already names it), open/paused/
-- closed, whether it takes a file, and its counts.
CREATE TABLE IF NOT EXISTS forms (
    id         TEXT PRIMARY KEY REFERENCES shares(id) ON DELETE CASCADE,
    account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    org_id     TEXT REFERENCES orgs(id) ON DELETE CASCADE,
    note_id    TEXT,
    state      TEXT NOT NULL,
    files      INTEGER NOT NULL DEFAULT 0,
    received   INTEGER NOT NULL DEFAULT 0,
    filed      INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS forms_by_account ON forms(account_id);
CREATE INDEX IF NOT EXISTS forms_by_org ON forms(org_id);
-- An answer to a form, ONLY sealed by the browser that sent it: its key's wraps (JSON, each to a recipient's public
-- key) and its blob. `seq` orders the inbox and is its cursor; the id is the browser's own, so a send retried lands
-- once. A claim is the device that holds it and until when. Goes with its form; swept at thirty days.
CREATE TABLE IF NOT EXISTS form_inbox (
    seq           INTEGER PRIMARY KEY AUTOINCREMENT,
    id            TEXT NOT NULL UNIQUE,
    form_id       TEXT NOT NULL REFERENCES forms(id) ON DELETE CASCADE,
    wraps         TEXT NOT NULL,
    blob          TEXT NOT NULL,
    received_at   INTEGER NOT NULL,
    claimed_by    TEXT,
    claimed_until INTEGER
);
CREATE INDEX IF NOT EXISTS form_inbox_by_form ON form_inbox(form_id, seq);
CREATE INDEX IF NOT EXISTS form_inbox_by_age ON form_inbox(received_at);
"#;

/// Whether a form takes answers.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FormState {
    Open,
    /// Not just now: the link says so, and says it may open again.
    Paused,
    /// For good: the link says it is closed.
    Closed,
}

impl FormState {
    pub fn parse(state: &str) -> Option<FormState> {
        match state {
            "open" => Some(FormState::Open),
            "paused" => Some(FormState::Paused),
            "closed" => Some(FormState::Closed),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            FormState::Open => "open",
            FormState::Paused => "paused",
            FormState::Closed => "closed",
        }
    }
}

/// A form as the routes read one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FormRow {
    pub id: String,
    pub account: i64,
    pub org: Option<String>,
    /// The note that defines it, by its id, for the device that files an answer; none from a device that named none.
    pub note: Option<String>,
    pub state: FormState,
    pub files: bool,
    pub received: i64,
    pub filed: i64,
    /// Answers waiting now, younger than the retention.
    pub waiting: i64,
    pub created_at: i64,
    pub updated_at: i64,
}

/// One answer waiting, sealed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FormItem {
    pub id: String,
    pub form: String,
    /// Its form's note, as the form says it (read with the inbox, not kept on the answer).
    pub note: Option<String>,
    /// The wraps of its key, as the JSON the browser sent: `[{ "to": <public key>, "wrap": <wrap> }, ...]`.
    pub wraps: String,
    pub blob: String,
    pub at: i64,
    /// Whether a device holds a claim on it that has not lapsed.
    pub claimed: bool,
}

/// Why a form, or an answer to one, was not kept.
#[derive(Debug, PartialEq, Eq)]
pub enum FormWrite {
    /// No share of the account's by that id.
    NoShare,
    /// The form is another account's.
    Taken,
    /// The organization named is not one the account has joined.
    NotMember,
    /// The account has as many forms, or the form as many answers waiting, as it may.
    Full,
    Failed,
}

impl From<rusqlite::Error> for FormWrite {
    fn from(_: rusqlite::Error) -> Self {
        FormWrite::Failed
    }
}

/// What a claim came to.
#[derive(Debug, PartialEq, Eq)]
pub enum Claim {
    /// Held by this device until then (seconds).
    Held(i64),
    /// Another device holds it.
    Elsewhere,
    /// No such answer, or not one this account may file.
    Gone,
}

/// The forms an account may file: its own, and those of every organization it has joined. `?1` is the account.
const MAY_FILE: &str = "(f.account_id = ?1 OR (f.org_id IS NOT NULL AND EXISTS (SELECT 1 FROM org_members m WHERE m.org_id = f.org_id AND m.account_id = ?1 AND m.state = 'member')))";

const FORM_COLUMNS: &str = "f.id, f.account_id, f.org_id, f.state, f.files, f.received, f.filed, f.created_at, f.updated_at, f.note_id";

fn form_row(r: &rusqlite::Row<'_>, waiting: i64) -> rusqlite::Result<FormRow> {
    let state: String = r.get(3)?;
    Ok(FormRow {
        id: r.get(0)?,
        account: r.get(1)?,
        org: r.get(2)?,
        state: FormState::parse(&state).unwrap_or(FormState::Closed),
        files: r.get::<_, i64>(4)? != 0,
        received: r.get(5)?,
        filed: r.get(6)?,
        waiting,
        created_at: r.get(7)?,
        updated_at: r.get(8)?,
        note: r.get(9)?,
    })
}

impl Store {
    // --- the forms ---------------------------------------------------------------------

    /// Makes the account's share `id` a form, or sets it again: its organization (which the account must have joined),
    /// its note, whether it takes a file, and its state where one is given (a new form is open unless it says). Refused
    /// for a share that is not the account's, a form that is another's, and a new one past `most`.
    #[allow(clippy::too_many_arguments)]
    pub fn put_form(&self, account: i64, id: &str, org: Option<&str>, note: Option<&str>, state: Option<FormState>, files: bool, now: i64, most: i64) -> Result<FormRow, FormWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let share: Option<i64> = tx.query_row("SELECT account_id FROM shares WHERE id = ?1", params![id], |r| r.get(0)).optional()?;
        if share != Some(account) {
            return Err(FormWrite::NoShare);
        }
        if let Some(org) = org {
            let joined: Option<i64> = tx.query_row("SELECT 1 FROM org_members WHERE org_id = ?1 AND account_id = ?2 AND state = 'member'", params![org, account], |r| r.get(0)).optional()?;
            if joined.is_none() {
                return Err(FormWrite::NotMember);
            }
        }
        let owner: Option<i64> = tx.query_row("SELECT account_id FROM forms WHERE id = ?1", params![id], |r| r.get(0)).optional()?;
        match owner {
            Some(owner) if owner != account => return Err(FormWrite::Taken),
            Some(_) => {
                tx.execute(
                    "UPDATE forms SET org_id = ?1, note_id = COALESCE(?2, note_id), state = COALESCE(?3, state), files = ?4, updated_at = ?5 WHERE id = ?6",
                    params![org, note, state.map(FormState::as_str), files as i64, now, id],
                )?;
            }
            None => {
                let made: i64 = tx.query_row("SELECT COUNT(*) FROM forms WHERE account_id = ?1", params![account], |r| r.get(0))?;
                if made >= most {
                    return Err(FormWrite::Full);
                }
                tx.execute(
                    "INSERT INTO forms (id, account_id, org_id, note_id, state, files, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)",
                    params![id, account, org, note, state.unwrap_or(FormState::Open).as_str(), files as i64, now],
                )?;
            }
        }
        let row = tx.query_row(&format!("SELECT {FORM_COLUMNS}, (SELECT COUNT(*) FROM form_inbox i WHERE i.form_id = f.id) FROM forms f WHERE f.id = ?1"), params![id], |r| {
            let waiting = r.get(10)?;
            form_row(r, waiting)
        })?;
        tx.commit()?;
        Ok(row)
    }

    /// A form, whoever's it is, with its answers waiting younger than `expired` (seconds).
    pub fn form(&self, id: &str, expired: i64) -> Option<FormRow> {
        self.one(
            &format!("SELECT {FORM_COLUMNS}, (SELECT COUNT(*) FROM form_inbox i WHERE i.form_id = f.id AND i.received_at > ?2) FROM forms f WHERE f.id = ?1"),
            params![id, expired],
            |r| {
                let waiting = r.get(10)?;
                form_row(r, waiting)
            },
        )
    }

    /// The forms an account may file - its own, and its organizations' - oldest first.
    pub fn forms_for(&self, account: i64, expired: i64) -> Vec<FormRow> {
        self.all(
            &format!("SELECT {FORM_COLUMNS}, (SELECT COUNT(*) FROM form_inbox i WHERE i.form_id = f.id AND i.received_at > ?2) FROM forms f WHERE {MAY_FILE} ORDER BY f.created_at, f.id"),
            params![account, expired],
            |r| {
                let waiting = r.get(10)?;
                form_row(r, waiting)
            },
        )
    }

    /// Whether the account may file, and so manage, the form `id`.
    pub fn may_file(&self, account: i64, id: &str) -> bool {
        self.one(&format!("SELECT 1 FROM forms f WHERE f.id = ?2 AND {MAY_FILE}"), params![account, id], |r| r.get::<_, i64>(0)).is_some()
    }

    /// A form's state set by one who may file it. Answers the form as it now is.
    pub fn set_form_state(&self, account: i64, id: &str, state: FormState, now: i64) -> Option<FormRow> {
        let changed = self.lock().execute(&format!("UPDATE forms SET state = ?3, updated_at = ?4 WHERE id = ?2 AND id IN (SELECT f.id FROM forms f WHERE {MAY_FILE})"), params![account, id, state.as_str(), now]).ok()?;
        if changed == 0 {
            return None;
        }
        self.form(id, 0)
    }

    /// A form gone, with every answer waiting, by its owner. Its share stays: the device takes that down itself.
    pub fn delete_form(&self, account: i64, id: &str) -> bool {
        self.lock().execute("DELETE FROM forms WHERE id = ?1 AND account_id = ?2", params![id, account]).map(|n| n > 0).unwrap_or(false)
    }

    /// The public keys an answer to the form is sealed to: its owner's, or every member's of its organization who has
    /// one (a member with none yet is sealed to once a device of theirs made one).
    pub fn form_recipients(&self, form: &FormRow) -> Vec<String> {
        match &form.org {
            Some(org) => self.all(
                "SELECT k.pub FROM org_members m JOIN account_keys k ON k.account_id = m.account_id WHERE m.org_id = ?1 AND m.state = 'member' ORDER BY m.since, m.account_id",
                params![org],
                |r| r.get(0),
            ),
            None => self.account_key(form.account).map(|k| vec![k.pub_key]).unwrap_or_default(),
        }
    }

    // --- the answers -------------------------------------------------------------------

    /// Keeps a sealed answer, unless its form has `most` waiting younger than `expired`; those older go first, in the
    /// same transaction. An answer whose id is already kept for this form is the same send again: it answers false
    /// and keeps nothing more. An id another form's answer has is refused as taken.
    pub fn put_form_item(&self, item: &FormItem, most: i64, expired: i64) -> Result<bool, FormWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        tx.execute("DELETE FROM form_inbox WHERE form_id = ?1 AND received_at <= ?2", params![item.form, expired])?;
        let kept: Option<String> = tx.query_row("SELECT form_id FROM form_inbox WHERE id = ?1", params![item.id], |r| r.get(0)).optional()?;
        match kept {
            Some(form) if form == item.form => return Ok(false),
            Some(_) => return Err(FormWrite::Taken),
            None => {}
        }
        let waiting: i64 = tx.query_row("SELECT COUNT(*) FROM form_inbox WHERE form_id = ?1", params![item.form], |r| r.get(0))?;
        if waiting >= most {
            return Err(FormWrite::Full);
        }
        tx.execute(
            "INSERT INTO form_inbox (id, form_id, wraps, blob, received_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![item.id, item.form, item.wraps, item.blob, item.at],
        )?;
        tx.execute("UPDATE forms SET received = received + 1 WHERE id = ?1", params![item.form])?;
        tx.commit()?;
        Ok(true)
    }

    /// What waits for the account to file, across every form it may, oldest first, at most `limit`, younger than
    /// `expired`: after the answer `after` names, or from the first when it names none or one already filed. `now`
    /// says which claims still hold.
    pub fn form_inbox(&self, account: i64, after: Option<&str>, limit: i64, expired: i64, now: i64) -> Vec<FormItem> {
        self.all(
            &format!(
                "SELECT i.id, i.form_id, i.wraps, i.blob, i.received_at, COALESCE(i.claimed_until, 0) > ?5, f.note_id FROM form_inbox i JOIN forms f ON f.id = i.form_id \
                 WHERE {MAY_FILE} AND i.received_at > ?2 AND i.seq > COALESCE((SELECT seq FROM form_inbox WHERE id = ?3), 0) ORDER BY i.seq LIMIT ?4"
            ),
            params![account, expired, after, limit, now],
            |r| Ok(FormItem { id: r.get(0)?, form: r.get(1)?, note: r.get(6)?, wraps: r.get(2)?, blob: r.get(3)?, at: r.get(4)?, claimed: r.get(5)? }),
        )
    }

    /// The answer `id` claimed by `device` for `lease` seconds, if the account may file it and no other device holds
    /// it: one unclaimed, one whose claim lapsed, or one this device holds already (held again from now).
    pub fn claim_form_item(&self, account: i64, id: &str, device: &str, now: i64, lease: i64) -> Claim {
        let mut conn = self.lock();
        let Ok(tx) = conn.transaction() else { return Claim::Gone };
        let found = tx
            .query_row(
                &format!("SELECT i.claimed_by, COALESCE(i.claimed_until, 0) FROM form_inbox i JOIN forms f ON f.id = i.form_id WHERE i.id = ?2 AND {MAY_FILE}"),
                params![account, id],
                |r| Ok((r.get::<_, Option<String>>(0)?, r.get::<_, i64>(1)?)),
            )
            .optional();
        let Ok(Some((by, until))) = found else { return Claim::Gone };
        if until > now && by.as_deref() != Some(device) {
            return Claim::Elsewhere;
        }
        let held = now + lease;
        if tx.execute("UPDATE form_inbox SET claimed_by = ?1, claimed_until = ?2 WHERE id = ?3", params![device, held, id]).is_err() || tx.commit().is_err() {
            return Claim::Gone;
        }
        Claim::Held(held)
    }

    /// An answer filed: gone from the inbox, and counted on its form. Answers whether one went.
    pub fn ack_form_item(&self, account: i64, id: &str) -> bool {
        let mut conn = self.lock();
        let Ok(tx) = conn.transaction() else { return false };
        let form: Option<String> = tx
            .query_row(&format!("SELECT i.form_id FROM form_inbox i JOIN forms f ON f.id = i.form_id WHERE i.id = ?2 AND {MAY_FILE}"), params![account, id], |r| r.get(0))
            .optional()
            .ok()
            .flatten();
        let Some(form) = form else { return false };
        let gone = tx.execute("DELETE FROM form_inbox WHERE id = ?1", params![id]).unwrap_or(0) > 0;
        if gone {
            let _ = tx.execute("UPDATE forms SET filed = filed + 1 WHERE id = ?1", params![form]);
        }
        tx.commit().is_ok() && gone
    }

    /// Every answer waiting for the form `id` deleted, by one who may file it. Answers how many.
    pub fn clear_form_items(&self, account: i64, id: &str) -> usize {
        if !self.may_file(account, id) {
            return 0;
        }
        self.lock().execute("DELETE FROM form_inbox WHERE form_id = ?1", params![id]).unwrap_or(0)
    }

    /// Every answer, of every form, at `expired` (seconds) or older, gone. Answers how many.
    pub fn sweep_form_inbox(&self, expired: i64) -> usize {
        self.lock().execute("DELETE FROM form_inbox WHERE received_at <= ?1", params![expired]).unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;
    use super::*;

    fn item(id: &str, form: &str, at: i64) -> FormItem {
        FormItem { id: id.into(), form: form.into(), note: None, wraps: "[]".into(), blob: "b".into(), at, claimed: false }
    }

    #[test]
    fn a_form_is_a_share_of_the_account_s_own_and_goes_with_it() {
        let (s, a, _dir) = fixture();
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        assert_eq!(s.put_form(a.id, "share-1", None, None, Some(FormState::Open), false, 10, 5), Err(FormWrite::NoShare), "no share yet");
        s.put_share(a.id, "share-1", "blob", 10, 10).unwrap();
        assert_eq!(s.put_form(b.id, "share-1", None, None, Some(FormState::Open), false, 10, 5), Err(FormWrite::NoShare), "another's share");
        let made = s.put_form(a.id, "share-1", None, None, Some(FormState::Open), true, 10, 5).unwrap();
        assert_eq!((made.state, made.files, made.received, made.waiting), (FormState::Open, true, 0, 0));
        let paused = s.put_form(a.id, "share-1", None, None, Some(FormState::Paused), false, 20, 5).unwrap();
        assert_eq!((paused.state, paused.files, paused.updated_at, paused.created_at), (FormState::Paused, false, 20, 10));
        let noted = s.put_form(a.id, "share-1", None, Some("note-1"), None, false, 25, 5).unwrap();
        assert_eq!((noted.state, noted.note.as_deref()), (FormState::Paused, Some("note-1")), "said again with no state, its state stands");
        s.put_form_item(&item("x1", "share-1", 30), 10, 0).unwrap();
        assert!(s.delete_share(a.id, "share-1"));
        assert_eq!(s.form("share-1", 0), None, "the share taken down takes its form");
        assert!(s.form_inbox(a.id, None, 10, 0, 0).is_empty(), "and its answers");
    }

    #[test]
    fn an_answer_is_kept_once_counted_and_capped_per_form() {
        let (s, a, _dir) = fixture();
        s.put_share(a.id, "f", "blob", 1, 10).unwrap();
        s.put_form(a.id, "f", None, None, Some(FormState::Open), false, 1, 5).unwrap();
        assert_eq!(s.put_form_item(&item("x1", "f", 10), 2, 0), Ok(true));
        assert_eq!(s.put_form_item(&item("x1", "f", 11), 2, 0), Ok(false), "the same send again keeps nothing more");
        assert_eq!(s.put_form_item(&item("x2", "f", 12), 2, 0), Ok(true));
        assert_eq!(s.put_form_item(&item("x3", "f", 13), 2, 0), Err(FormWrite::Full));
        let form = s.form("f", 0).unwrap();
        assert_eq!((form.received, form.waiting), (2, 2));
        assert_eq!(s.put_form_item(&item("x4", "f", 200), 2, 12), Ok(true), "the old ones went to make room");
        assert_eq!(s.form_inbox(a.id, None, 10, 0, 0).iter().map(|i| i.id.as_str()).collect::<Vec<_>>(), vec!["x4"]);
        assert_eq!(s.sweep_form_inbox(199), 0);
        assert_eq!(s.sweep_form_inbox(200), 1);
        assert!(s.form_inbox(a.id, None, 10, 0, 0).is_empty());
    }

    #[test]
    fn a_claim_holds_one_device_at_a_time_until_it_lapses_and_an_ack_files_it_once() {
        let (s, a, _dir) = fixture();
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        s.put_share(a.id, "f", "blob", 1, 10).unwrap();
        s.put_form(a.id, "f", None, None, Some(FormState::Open), false, 1, 5).unwrap();
        s.put_form_item(&item("x1", "f", 10), 10, 0).unwrap();
        assert_eq!(s.claim_form_item(b.id, "x1", "phone", 100, 120), Claim::Gone, "not another account's to file");
        assert_eq!(s.claim_form_item(a.id, "x1", "phone", 100, 120), Claim::Held(220));
        assert_eq!(s.claim_form_item(a.id, "x1", "mac", 150, 120), Claim::Elsewhere);
        assert!(s.form_inbox(a.id, None, 10, 0, 150)[0].claimed);
        assert_eq!(s.claim_form_item(a.id, "x1", "phone", 160, 120), Claim::Held(280), "held again by its own device");
        assert_eq!(s.claim_form_item(a.id, "x1", "mac", 281, 120), Claim::Held(401), "a lapsed claim is anyone's");
        assert!(!s.ack_form_item(b.id, "x1"));
        assert!(s.ack_form_item(a.id, "x1"));
        assert!(!s.ack_form_item(a.id, "x1"), "filed once");
        assert_eq!(s.claim_form_item(a.id, "x1", "phone", 300, 120), Claim::Gone);
        let form = s.form("f", 0).unwrap();
        assert_eq!((form.received, form.waiting, form.filed), (1, 0, 1));
    }
}
