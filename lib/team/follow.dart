/// Following a team's page (docs/TEAMSPACES.md, "Follow a doc and Updates"; Matt, 2026-10-31: "`watchers:` (the
/// tickets' key) works on any page; watching sends that page's changes to your Updates … Auto-follow when you create,
/// edit or are mentioned on a team page"). Who follows a page is the page's own front matter, the key a ticket's
/// watchers are kept under (lib/book/ticket_watchers.dart), so it travels with the file and syncs to the team as any
/// edit does, and a clone of the Library folder says the same:
///
///     ---
///     watchers: ["@matt", "@sam"]
///     ---
///
/// **Following by hand** is Follow and Following on the page's More sheet ([withFollowing]); **being made a
/// follower** ([autoFollowEdit], [autoFollowMention]) is once per page and per reason, and written into the page with
/// the change that caused it, never on every keystroke: the first edit this account makes to a team page on this
/// device (making one counts, its first words being its first edit), and each new mention of this account in one.
/// Which of those have been done is this device's bookkeeping ([FollowLedger], per account, in the device's own
/// memory): someone who unfollows is not followed again by their next edit, only by a new mention, as a ticket's
/// watcher who unwatches is followed again only by something new (ticket_watchers.dart `autoWatchers`).
///
/// A ticket keeps its own rules (its creator, its assignee, whoever comments or is mentioned): an edit to a ticket
/// makes nobody a follower here, so a teammate fixing a typo on a ticket is not told of its every change after.
///
/// Pure but for the ledger's memory, so every rule is a test (test/team/follow_test.dart).
library;

import '../book/ticket_watchers.dart' show handleOf, watchersOf, watches, withWatcher;
import '../core/properties.dart' show isTicket;
import '../core/stored.dart';
import '../mentions/mention_syntax.dart' show handleKey;

/// Whether [handle] follows the page: is among its `watchers:`.
bool follows(String body, String? handle) => watches(body, handle);

/// Who follows the page, as written, each once, without the at sign.
List<String> followersOf(String body) => watchersOf(body);

/// The page with [handle] following it ([on]) or not; the body as it was where nothing changes.
String withFollowing(String body, String handle, bool on) => withWatcher(body, handle, on);

/// Where the device keeps which pages each account has been made a follower of, and why (`edit:<note id>`,
/// `mention:<notification id>`).
const String followLedgerKey = 'glyph-auto-followed';

/// How many reasons the ledger keeps per account before it forgets the oldest.
const int followLedgerKept = 4000;

/// Which auto-follows have been done on this device, per account: a page's first edit, a mention's row. Kept in the
/// device's own memory ([Stored]): it is the device's bookkeeping, not the library's, and a fresh device that edits
/// a page it was never made a follower of makes its account one then, once.
class FollowLedger {
  FollowLedger(this.stored);

  final Stored stored;
  Map<String, List<String>>? _read;

  Map<String, List<String>> get _all => _read ??= stored.read<Map<String, List<String>>>(followLedgerKey, <String, List<String>>{}, (raw) {
        if (raw is! Map) return null;
        return {
          for (final MapEntry(:key, :value) in raw.entries)
            if (key is String && value is List) key: [for (final item in value) if (item is String) item],
        };
      });

  /// Whether [reason] was done for [handle].
  bool done(String handle, String reason) => _all[handleKey(handle)]?.contains(reason) ?? false;

  /// [reason] done for [handle]; true where it was not done before.
  bool mark(String handle, String reason) {
    final key = handleKey(handle);
    final list = _all.putIfAbsent(key, () => <String>[]);
    if (list.contains(reason)) return false;
    list.add(reason);
    if (list.length > followLedgerKept) list.removeRange(0, list.length - followLedgerKept);
    stored.write(followLedgerKey, _all);
    return true;
  }
}

/// The reason a page's first edit is kept under.
String editReason(String noteId) => 'edit:$noteId';

/// The reason a mention's row is kept under.
String mentionReason(String notificationId) => 'mention:$notificationId';

/// What [me]'s edit of a team page from [before] to [after] makes of its followers: [after] with [me] following,
/// where this is the first edit of the page this device has made for [me] and [me] does not follow it already; null
/// where nothing is written (not a team page, a ticket, no account, an edit already counted, or [me] following). The
/// edit is counted in [ledger] either way, so a follow taken back by hand stays taken back.
String? autoFollowEdit({required String noteId, required String before, required String after, required String? me, required bool teamPage, required FollowLedger ledger}) {
  final who = handleOf(me);
  if (who == null || !teamPage || before == after) return null;
  if (isTicket(after) || isTicket(before)) return null;
  if (!ledger.mark(who, editReason(noteId))) return null;
  if (follows(after, who)) return null;
  return withFollowing(after, who, true);
}

/// Whether a mention of [me] (the notification [notificationId]) in a team page makes [me] a follower of it: true the
/// first time the row is seen, counted in [ledger]; the page's words are then written by whoever asked, through the
/// open editor where there is one.
bool autoFollowMention({required String notificationId, required String? me, required FollowLedger ledger}) {
  final who = handleOf(me);
  if (who == null) return false;
  return ledger.mark(who, mentionReason(notificationId));
}

/// What a note's desk is handed for a team's pages (lib/root/note_desk.dart): who is signed in, whether a note is a
/// team's page, the device's ledger of auto-follows, and the way to a member's page from a mention's chip.
class TeamPageSeams {
  const TeamPageSeams({required this.me, required this.teamPage, required this.ledger, this.openMember});

  /// The account's handle, or null signed out.
  final String? Function() me;

  /// Whether a note is a team's page now: filed in an organization's workspace or a folder under it.
  final bool Function(String noteId) teamPage;
  final FollowLedger ledger;

  /// A member's page, by their organization and handle.
  final void Function(String orgId, String handle)? openMember;
}
