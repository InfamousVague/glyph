//! The AIs that have read or written an organization's notes through a member's connector (src/orgs.rs,
//! docs/TEAMS.md). Matt: "when an AI has accessed an ORG add it as a member labeled as (AI)".
//!
//! An entry is a record and nothing else: the name the AI's app gave, the member whose connector it came through,
//! and when it was first and last seen. It is not an account and holds no row among the members: it has no key wrap,
//! is never counted as missing one, owes the key no turn, takes no seat and cannot be invited. The access it records
//! is the member's own - the connector reads with the member's wrap - so removing an entry removes the record, not
//! the access. One entry per member and name; it goes with the member's row, with the organization and with the
//! account.

use super::{OrgWrite, Store};
use rusqlite::{params, Connection, OptionalExtension, Row};

/// An AI seen in an organization, as every member reads it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrgAi {
    pub id: String,
    pub name: String,
    /// The handle of the member whose connector it came through.
    pub via: String,
    pub first_seen: i64,
    pub last_seen: i64,
}

const AI_SELECT: &str = "SELECT i.id, i.name, a.handle, i.first_seen, i.last_seen FROM org_ais i \
    JOIN accounts a ON a.id = i.account_id \
    JOIN org_members m ON m.org_id = i.org_id AND m.account_id = i.account_id AND m.state = 'member'";

impl Store {
    fn ai_row(r: &Row<'_>) -> rusqlite::Result<OrgAi> {
        Ok(OrgAi { id: r.get(0)?, name: r.get(1)?, via: r.get(2)?, first_seen: r.get(3)?, last_seen: r.get(4)? })
    }

    /// The organization's entries, the first seen first.
    pub(super) fn ais_in(conn: &Connection, org: &str) -> rusqlite::Result<Vec<OrgAi>> {
        let mut stmt = conn.prepare(&format!("{AI_SELECT} WHERE i.org_id = ?1 ORDER BY i.first_seen, i.rowid"))?;
        let ais = stmt.query_map(params![org], Self::ai_row)?.filter_map(Result::ok).collect();
        Ok(ais)
    }

    /// An AI seen through the caller's connector, who must have joined: its entry made, or its last seen moved on.
    /// A member holds `most` names at once in one organization; past that the one seen longest ago goes.
    pub fn ai_seen(&self, actor: i64, org: &str, id: &str, name: &str, now: i64, most: i64) -> Result<OrgAi, OrgWrite> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        Self::acting(&tx, org, actor)?;
        tx.execute(
            "INSERT INTO org_ais (id, org_id, account_id, name, first_seen, last_seen) VALUES (?1, ?2, ?3, ?4, ?5, ?5) \
             ON CONFLICT(org_id, account_id, name) DO UPDATE SET last_seen = excluded.last_seen",
            params![id, org, actor, name, now],
        )?;
        tx.execute(
            "DELETE FROM org_ais WHERE org_id = ?1 AND account_id = ?2 AND id NOT IN \
             (SELECT id FROM org_ais WHERE org_id = ?1 AND account_id = ?2 ORDER BY last_seen DESC, rowid DESC LIMIT ?3)",
            params![org, actor, most],
        )?;
        let ai = tx.query_row(&format!("{AI_SELECT} WHERE i.org_id = ?1 AND i.account_id = ?2 AND i.name = ?3"), params![org, actor, name], Self::ai_row)?;
        tx.commit()?;
        Ok(ai)
    }

    /// An entry removed: by the owner or an admin, or by the member it came through. The record goes; the member's
    /// access, which is what the connector reads with, is as it was.
    pub fn drop_ai(&self, actor: i64, org: &str, id: &str) -> Result<(), OrgWrite> {
        let conn = self.lock();
        let seat = Self::acting(&conn, org, actor)?;
        let owner: Option<i64> = conn.query_row("SELECT account_id FROM org_ais WHERE id = ?1 AND org_id = ?2", params![id, org], |r| r.get(0)).optional()?;
        let Some(owner) = owner else { return Err(OrgWrite::NoSuchAi) };
        if owner != actor && !seat.role.manages() {
            return Err(OrgWrite::AdminOnly);
        }
        conn.execute("DELETE FROM org_ais WHERE id = ?1 AND org_id = ?2", params![id, org])?;
        Ok(())
    }
}
