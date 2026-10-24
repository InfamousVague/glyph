//! Email to a note (src/mail.rs, docs/MAIL.md): each account's private address, and the mail sent to it, sealed.
//!
//! An address is kept as its local part, lower-cased, in the clear: the service has to find the account a mail is for,
//! as it finds one by its handle, and a person's devices read it back to show it. One address an account; making a new
//! one, or choosing a name of one's own, puts it in place of the old, which takes no mail from then on.
//!
//! An address given up is not free again. The trigger on `mail_addresses` (store.rs) keeps each one that goes, by any
//! door, in `mail_addresses_retired` against the account it was: that account may take it back, and nobody else may
//! ever have it, so whoever still has it in a contact or on a Calendar invite is refused rather than heard by a
//! stranger. A deleted account's addresses stay there as their local parts, linked to an id no account will have again.
//!
//! A mail is kept ONLY sealed: `wrapped` is a fresh key wrapped to the account's encryption public key, `blob` the mail
//! as a note's words and files sealed under that key (src/mail/seal.rs). The service made both from the clear mail a
//! moment before and cannot open either. A mail waits here until one of the account's devices has opened it and filed
//! its note, and deletes it.

use super::Store;
use rusqlite::{params, OptionalExtension};

/// Why a mail was not kept.
#[derive(Debug, PartialEq, Eq)]
pub enum MailWrite {
    /// The account has as many mails waiting as it may: none of its devices has synced for a while.
    Full,
    Failed,
}

impl From<rusqlite::Error> for MailWrite {
    fn from(_: rusqlite::Error) -> Self {
        MailWrite::Failed
    }
}

/// Why an address could not be the account's.
#[derive(Debug, PartialEq, Eq)]
pub enum MailClaim {
    /// Another account's, live or given up.
    Taken,
    Failed,
}

impl From<rusqlite::Error> for MailClaim {
    fn from(_: rusqlite::Error) -> Self {
        MailClaim::Failed
    }
}

/// Where an address stands for one account.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MailStanding {
    Free,
    /// The account's live address now.
    Yours,
    /// Another account's: live, given up, or a deleted account's.
    Taken,
}

/// A sealed mail as a device reads it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SealedMail {
    pub wrapped: String,
    pub blob: String,
    pub at: i64,
}

impl Store {
    // --- the address ------------------------------------------------------------------

    /// The account's address, its local part, if it has one on.
    pub fn mail_address_of(&self, account: i64) -> Option<String> {
        self.one("SELECT address FROM mail_addresses WHERE account_id = ?1", params![account], |r| r.get(0))
    }

    /// Gives the account `address`, in place of any it had: the old one is dead from this moment, and kept as the
    /// account's (`mail_addresses_retired`, by the trigger) so it is never anyone else's. Refused as [`MailClaim::Taken`]
    /// when the address is another account's, live or given up; the account's own given-up address it may take back,
    /// and its live one is a change of nothing.
    ///
    /// The look and the write are one transaction on the one connection, and the address is the live table's key, so
    /// two accounts asking for `matt` at once cannot both have it: the second finds the first's row, or, were the look
    /// ever to miss it, the key refuses the insert and the transaction is undone with the old address still on.
    pub fn set_mail_address(&self, account: i64, address: &str, now: i64) -> Result<(), MailClaim> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        match Self::standing(&tx, account, address)? {
            MailStanding::Yours => return Ok(()),
            MailStanding::Taken => return Err(MailClaim::Taken),
            MailStanding::Free => {}
        }
        tx.execute("DELETE FROM mail_addresses WHERE account_id = ?1", params![account])?;
        // The account's own, given up once and live again.
        tx.execute("DELETE FROM mail_addresses_retired WHERE address = ?1 AND account_id = ?2", params![address, account])?;
        match tx.execute("INSERT INTO mail_addresses (address, account_id, created_at) VALUES (?1, ?2, ?3)", params![address, account, now]) {
            Ok(_) => {}
            Err(rusqlite::Error::SqliteFailure(e, _)) if e.code == rusqlite::ErrorCode::ConstraintViolation => return Err(MailClaim::Taken),
            Err(e) => return Err(e.into()),
        }
        tx.commit()?;
        Ok(())
    }

    /// Whether `address` could be the account's: free, its own already, or another's (live, or given up).
    pub fn mail_address_standing(&self, account: i64, address: &str) -> Option<MailStanding> {
        Self::standing(&self.lock(), account, address).ok()
    }

    fn standing(conn: &rusqlite::Connection, account: i64, address: &str) -> rusqlite::Result<MailStanding> {
        let live: Option<i64> = conn.query_row("SELECT account_id FROM mail_addresses WHERE address = ?1", params![address], |r| r.get(0)).optional()?;
        if let Some(holder) = live {
            return Ok(if holder == account { MailStanding::Yours } else { MailStanding::Taken });
        }
        let retired: Option<i64> = conn.query_row("SELECT account_id FROM mail_addresses_retired WHERE address = ?1", params![address], |r| r.get(0)).optional()?;
        Ok(match retired {
            Some(holder) if holder != account => MailStanding::Taken,
            _ => MailStanding::Free,
        })
    }

    /// Turns the account's address off; it is kept as the account's, as a replaced one is. Mail already waiting
    /// stays until a device takes it.
    pub fn clear_mail_address(&self, account: i64) -> bool {
        self.lock().execute("DELETE FROM mail_addresses WHERE account_id = ?1", params![account]).map(|n| n > 0).unwrap_or(false)
    }

    /// The account an address belongs to, if it is live.
    pub fn mail_account(&self, address: &str) -> Option<i64> {
        self.one("SELECT account_id FROM mail_addresses WHERE address = ?1", params![address], |r| r.get(0))
    }

    // --- the mail waiting --------------------------------------------------------------

    /// Keeps a sealed mail for the account, unless it already has `most` waiting.
    pub fn put_mail(&self, account: i64, id: &str, mail: &SealedMail, most: i64) -> Result<(), MailWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let waiting: i64 = tx.query_row("SELECT COUNT(*) FROM mail_in WHERE account_id = ?1", params![account], |r| r.get(0))?;
        if waiting >= most {
            return Err(MailWrite::Full);
        }
        let size = (mail.wrapped.len() + mail.blob.len()) as i64;
        tx.execute(
            "INSERT INTO mail_in (id, account_id, wrapped, blob, size, received_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![id, account, mail.wrapped, mail.blob, size, mail.at],
        )?;
        tx.commit()?;
        Ok(())
    }

    /// What waits for the account, oldest first: each mail's id, its size in characters, and when it came.
    pub fn mail_waiting(&self, account: i64) -> Vec<(String, i64, i64)> {
        self.all("SELECT id, size, received_at FROM mail_in WHERE account_id = ?1 ORDER BY received_at, id", params![account], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))
    }

    /// One of the account's sealed mails; another account's is none.
    pub fn mail(&self, account: i64, id: &str) -> Option<SealedMail> {
        self.lock()
            .query_row("SELECT wrapped, blob, received_at FROM mail_in WHERE id = ?1 AND account_id = ?2", params![id, account], |r| {
                Ok(SealedMail { wrapped: r.get(0)?, blob: r.get(1)?, at: r.get(2)? })
            })
            .optional()
            .ok()
            .flatten()
    }

    /// A mail taken: its note is filed. Answers whether one went.
    pub fn delete_mail(&self, account: i64, id: &str) -> bool {
        self.lock().execute("DELETE FROM mail_in WHERE id = ?1 AND account_id = ?2", params![id, account]).map(|n| n > 0).unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::super::fixture;
    use super::*;

    fn sealed(at: i64) -> SealedMail {
        SealedMail { wrapped: "w".into(), blob: "b".into(), at }
    }

    #[test]
    fn a_new_address_takes_the_place_of_the_old_and_off_is_none() {
        let (s, a, _dir) = fixture();
        assert_eq!(s.mail_address_of(a.id), None);
        s.set_mail_address(a.id, "first", 1).unwrap();
        assert_eq!(s.mail_account("first"), Some(a.id));
        s.set_mail_address(a.id, "second", 2).unwrap();
        assert_eq!(s.mail_account("first"), None, "the old address is dead at once");
        assert_eq!((s.mail_address_of(a.id).as_deref(), s.mail_account("second")), (Some("second"), Some(a.id)));
        assert!(s.clear_mail_address(a.id));
        assert_eq!((s.mail_address_of(a.id), s.mail_account("second")), (None, None));
    }

    #[test]
    fn mail_waits_oldest_first_up_to_its_limit_and_only_its_account_reads_or_takes_it() {
        let (s, a, _dir) = fixture();
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        s.put_mail(a.id, "later", &sealed(20), 2).unwrap();
        s.put_mail(a.id, "sooner", &sealed(10), 2).unwrap();
        assert_eq!(s.put_mail(a.id, "third", &sealed(30), 2), Err(MailWrite::Full));
        assert_eq!(s.mail_waiting(a.id).iter().map(|(id, _, _)| id.as_str()).collect::<Vec<_>>(), vec!["sooner", "later"]);
        assert_eq!(s.mail(b.id, "sooner"), None, "another account reads none of it");
        assert!(!s.delete_mail(b.id, "sooner"));
        assert_eq!(s.mail(a.id, "sooner"), Some(sealed(10)));
        assert!(s.delete_mail(a.id, "sooner"));
        assert_eq!(s.mail(a.id, "sooner"), None);
    }

    #[test]
    fn an_address_and_its_mail_go_with_the_account() {
        let (s, a, _dir) = fixture();
        s.set_mail_address(a.id, "gone", 1).unwrap();
        s.put_mail(a.id, "m", &sealed(1), 10).unwrap();
        s.lock().execute("DELETE FROM accounts WHERE id = ?1", params![a.id]).unwrap();
        assert_eq!((s.mail_account("gone"), s.mail(a.id, "m")), (None, None));
    }

    #[test]
    fn an_address_given_up_any_way_is_never_another_account_s_and_its_own_may_take_it_back() {
        let (s, a, _dir) = fixture();
        let b = s.create_account("other", "", "", None, &[], 1).unwrap();
        s.set_mail_address(a.id, "matt", 1).unwrap();
        assert_eq!(s.set_mail_address(b.id, "matt", 2), Err(MailClaim::Taken), "live");
        assert_eq!((s.mail_address_standing(a.id, "matt"), s.mail_address_standing(b.id, "matt")), (Some(MailStanding::Yours), Some(MailStanding::Taken)));
        assert_eq!(s.set_mail_address(a.id, "matt", 3), Ok(()), "its own already: nothing changes");
        // Replaced: given up, still not b's.
        s.set_mail_address(a.id, "matthew", 4).unwrap();
        assert_eq!(s.mail_account("matt"), None);
        assert_eq!(s.set_mail_address(b.id, "matt", 5), Err(MailClaim::Taken), "given up");
        assert_eq!(s.mail_address_of(b.id), None, "a refusal leaves b as it was");
        // Turned off: the same.
        assert!(s.clear_mail_address(a.id));
        assert_eq!(s.mail_address_standing(b.id, "matthew"), Some(MailStanding::Taken));
        // a may have either back.
        assert_eq!(s.mail_address_standing(a.id, "matt"), Some(MailStanding::Free));
        s.set_mail_address(a.id, "matt", 6).unwrap();
        assert_eq!(s.mail_account("matt"), Some(a.id));
        let retired: i64 = s.lock().query_row("SELECT COUNT(*) FROM mail_addresses_retired WHERE address = 'matt'", [], |r| r.get(0)).unwrap();
        assert_eq!(retired, 0, "live again, not given up");
    }

    #[test]
    fn a_deleted_account_s_address_is_nobody_s_for_good() {
        let (s, a, _dir) = fixture();
        s.set_mail_address(a.id, "sam", 1).unwrap();
        s.set_mail_address(a.id, "sam.lee", 2).unwrap();
        // The cascade takes the live row; the trigger keeps it.
        assert_eq!(s.delete_account(a.id, 3).ok(), Some(true));
        let b = s.create_account("other", "", "", None, &[], 4).unwrap();
        assert_ne!(a.id, b.id);
        for name in ["sam", "sam.lee"] {
            assert_eq!(s.mail_address_standing(b.id, name), Some(MailStanding::Taken), "{name}");
            assert_eq!(s.set_mail_address(b.id, name, 5), Err(MailClaim::Taken), "{name}");
        }
    }
}
