//! Email to a note (src/mail.rs, docs/MAIL.md): each account's private address, and the mail sent to it, sealed.
//!
//! An address is kept as its local part, lower-cased, in the clear: the service has to find the account a mail is for,
//! as it finds one by its handle, and a person's devices read it back to show it. One address an account; making a new
//! one puts it in place of the old, which takes no mail from then on.
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

    /// Gives the account `address`, in place of any it had: the old one is dead from this moment.
    pub fn set_mail_address(&self, account: i64, address: &str, now: i64) -> rusqlite::Result<()> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        tx.execute("DELETE FROM mail_addresses WHERE account_id = ?1", params![account])?;
        tx.execute("INSERT INTO mail_addresses (address, account_id, created_at) VALUES (?1, ?2, ?3)", params![address, account, now])?;
        tx.commit()
    }

    /// Turns the account's address off. Mail already waiting stays until a device takes it.
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
}
