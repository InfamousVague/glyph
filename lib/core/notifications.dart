/// What a notification can be, and the one place its words live (docs/TEAMS.md, "Kinds"). A port of
/// `src/app/core/notifications/kinds.ts`, with the rules of `core/notifications/feed.ts` that a list of rows asks
/// and nothing else of it: [listed], [isWanted], [unreadCount], [isPendingInvite].
///
/// Two shapes in one feed: the kinds the service makes about an organization (an invitation, who joined, who left, a
/// rename) carry their few words in the clear; the kinds this account makes for itself (Claude's writes, a meeting
/// written up, a note kept twice by a sync) are sealed under the account key, with the kind inside the seal. The
/// categories are what Settings › Notifications switches: an invitation is not switchable.
///
/// What differs:
/// - A row is [FeedNotification], not `Notification`, which is Flutter's own name for something else.
/// - A kind, a category and an invitation's state are the web's words as strings, as they are kept and fed, so a
///   row of a kind this build does not know is still a row; [kinds] is the list this build knows.
/// - The sealed payload's seven shapes (`Details`, a union) are one [NotificationDetails] with the fields of all of
///   them, each null where its kind does not carry it.
/// - The feed itself - the cursor, the marks waiting for the service, the pass, opening a seal - is the account's
///   stage and is not here.
library;

import 'package:flutter/foundation.dart';

import 'preferences.dart' show NotificationPrefs;

/// Made by the service, about an organization; the words it needs ride in `body`, in the clear (`SERVER_KINDS`).
const List<String> serverKinds = ['invite', 'invite-accepted', 'invite-declined', 'member-joined', 'member-left', 'member-removed', 'role-changed', 'org-renamed', 'org-deleted'];

/// Made by this account for itself, sealed; the MCP server posts the first five, the app the rest (`SELF_KINDS`).
/// `form-answer` is a ticket filed from an answer to a form (lib/forms/form_inbox.dart; Matt, 2026-10-30): an older
/// build does not know it, and draws nothing for it. `page-expired`, a verified page whose time ran out
/// (lib/verified/verified.dart; Matt, 2026-10-30: "add all 12"), is the app's own and has no web counterpart yet.
/// `ticket-digest` is the morning's word on a person's tickets, due, overdue and blocked (lib/book/ticket_digest.dart;
/// Matt, 2026-10-31), written by the one device that sends it.
const List<String> selfKinds = ['note-created', 'note-edited', 'note-appended', 'journal-entry', 'rule-added', 'summary-written', 'sync-conflict', 'form-answer', 'page-expired', 'ticket-digest', ticketRuleKind];

/// A ticket's rule told the person something (lib/book/rule_runs.dart `notify`; Matt, 2026-10-31).
const String ticketRuleKind = 'ticket-rule';

/// Written by the service on a member's word, to another member of the organization, sealed under the organization
/// key (lib/mentions/mention_notices.dart; server/src/notifications.rs): who sent it and the organization ride in the
/// clear, as a server kind's do, and the words in a seal, as a self kind's do. An older build does not know the kind
/// and does not draw the row. `ticket` is a ticket's watchers told what changed on it, the same way
/// (lib/book/ticket_events.dart; Matt, 2026-10-31).
const List<String> memberKinds = ['mention', 'ticket'];

/// Every kind this build knows (`KINDS`).
const List<String> kinds = [...serverKinds, ...selfKinds, ...memberKinds];

/// The colour each kind's mark wears (Matt: "color code different notification icons so they're easier to match at
/// first sight"), one of the app's hues (ink.css `[data-hue]`) by what the news is: someone arriving is moss, someone
/// going or a refusal is rose, an invitation waiting is violet, a role or a name changed is amber, a note written by
/// Claude or the phone is sea, and something that wants looking at is ember (`KIND_HUES`).
const Map<String, String> kindHues = {
  'invite': 'violet',
  'invite-accepted': 'moss',
  'invite-declined': 'rose',
  'member-joined': 'moss',
  'member-left': 'rose',
  'member-removed': 'rose',
  'role-changed': 'amber',
  'org-renamed': 'amber',
  'org-deleted': 'rose',
  'note-created': 'sea',
  'note-edited': 'sea',
  'note-appended': 'sea',
  'journal-entry': 'sea',
  'rule-added': 'violet',
  'summary-written': 'sea',
  'sync-conflict': 'ember',
  // A ticket written from an answer to a form: a note written, sea.
  'form-answer': 'sea',
  'page-expired': 'amber',
  'mention': 'violet',
  'ticket': 'violet',
  'ticket-digest': 'amber',
  ticketRuleKind: 'violet',
};

bool isKind(Object? value) => value is String && kinds.contains(value);

bool isSelfKind(Object? value) => value is String && selfKinds.contains(value);

/// A kind whose words are sealed: one this account makes for itself, or a member's mention.
bool isSealedKind(Object? value) => value is String && (selfKinds.contains(value) || memberKinds.contains(value));

/// The four switches, in the order the pane draws them (`CATEGORIES`). `invites` is a category with no switch.
const List<String> categories = ['team', 'claude', 'summaries', 'conflicts'];

const Map<String, String> _categoryOf = {
  'invite': 'invites',
  'invite-accepted': 'team',
  'invite-declined': 'team',
  'member-joined': 'team',
  'member-left': 'team',
  'member-removed': 'team',
  'role-changed': 'team',
  'org-renamed': 'team',
  'org-deleted': 'team',
  'note-created': 'claude',
  'note-edited': 'claude',
  'note-appended': 'claude',
  'journal-entry': 'claude',
  'rule-added': 'claude',
  'summary-written': 'summaries',
  'sync-conflict': 'conflicts',
  // Someone outside asked for something: shown as an invitation is, with no switch to turn it off.
  'form-answer': 'invites',
  // A person's own business, with no switch, as an invitation has none: someone asked something of them, or a page
  // they vouch for wants looking at. The bell's Mentions filter shows the first.
  'mention': 'mentions',
  'page-expired': 'mentions',
  // A ticket the person watches, and their morning's tickets: their own business, as a mention is.
  'ticket': 'mentions',
  'ticket-digest': 'mentions',
  // A rule the person wrote told them: their own business, as a mention is, under Mentions.
  ticketRuleKind: 'mentions',
};

/// The category of a kind this build knows: one of [categories], or `invites`.
String categoryOf(String kind) => _categoryOf[kind]!;

// --- what a sealed kind carries --------------------------------------------------------------------------------------

/// The sealed payload of a self notification, once opened (`Details`): the kind inside the seal, the note it is
/// about, and what that kind says of it.
@immutable
class NotificationDetails {
  const NotificationDetails({required this.kind, required this.noteId, required this.title, this.by, this.added, this.removed, this.first, this.at, this.lines, this.journal, this.what});

  /// One of [selfKinds], or a member's `mention`: the one trusted, where the row's own `kind` is for the service's
  /// pruning.
  final String kind;
  final String noteId;
  final String title;

  /// Who wrote it ('Claude' when the MCP had no other name); null for the two kinds the app makes.
  final String? by;

  /// `note-edited`: how many lines came and went.
  final int? added;
  final int? removed;

  /// The first line changed, added or written, at most 120 characters.
  final String? first;

  /// `note-edited`: where the first change is, as the note screen takes it: the line's anchor.
  final String? at;

  /// `note-appended`: how many lines were added.
  final int? lines;

  /// `journal-entry`: the journal's name.
  final String? journal;

  /// `ticket`: what was done to it, `closed`, `commented` or `changed` (lib/book/ticket_events.dart `batchWhat`).
  final String? what;

  /// An opened payload, if it has the shape of a self kind: a kind this build knows, about a note with a title
  /// (`isDetails`); null otherwise.
  static NotificationDetails? fromJson(Object? value) {
    if (value is! Map) return null;
    final kind = value['kind'], noteId = value['noteId'], title = value['title'];
    if (!isSealedKind(kind) || noteId is! String || title is! String) return null;
    String? text(String key) => value[key] is String ? value[key] as String : null;
    int? count(String key) => value[key] is num ? (value[key] as num).toInt() : null;
    return NotificationDetails(
      kind: kind as String,
      noteId: noteId,
      title: title,
      by: text('by'),
      added: count('added'),
      removed: count('removed'),
      first: text('first'),
      at: text('at'),
      lines: count('lines'),
      journal: text('journal'),
      what: text('what'),
    );
  }
}

// --- the row as it is kept -------------------------------------------------------------------------------------------

/// The organization a server kind is about.
typedef NotificationOrg = ({String id, String name});

/// One notification as the service feeds it and this device keeps it (`Notification`; docs/TEAMS.md, "Shapes").
@immutable
class FeedNotification {
  const FeedNotification({required this.id, this.rev = 0, required this.kind, required this.at, this.readAt, this.hidden = false, this.from, this.org, this.body, this.blob, this.state});

  final String id;

  /// The account's revision at which the row was last written; 0 for a self row this device has not sent yet.
  final int rev;

  /// One of [kinds], or a kind a newer build made, which is kept and not drawn.
  final String kind;

  /// When it happened, in ms.
  final int at;
  final int? readAt;
  final bool hidden;

  /// The handle of who caused it; null when that account is gone ("someone"), and for a self kind, which has none.
  final String? from;

  /// Its live name while the reader is a member, else the name in [body].
  final NotificationOrg? org;

  /// A server kind's few words, in the clear.
  final Map<String, Object?>? body;

  /// A self kind's payload, sealed: a [NotificationDetails].
  final String? blob;

  /// An invitation's answer, if any: `pending` until one is given, then `accepted` or `declined`.
  final String? state;

  /// A row as kept, if it has the shape this build reads (`asItem`, core/notifications/feed.ts); null otherwise.
  static FeedNotification? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], kind = raw['kind'], at = raw['at'];
    if (id is! String || kind is! String || at is! num) return null;
    final org = raw['org'];
    final state = raw['state'];
    return FeedNotification(
      id: id,
      rev: raw['rev'] is num ? (raw['rev'] as num).toInt() : 0,
      kind: kind,
      at: at.toInt(),
      readAt: raw['readAt'] is num ? (raw['readAt'] as num).toInt() : null,
      hidden: raw['hidden'] == true,
      from: raw['from'] is String ? raw['from'] as String : null,
      org: org is Map && org['id'] is String ? (id: org['id'] as String, name: org['name'] is String ? org['name'] as String : '') : null,
      body: raw['body'] is Map ? (raw['body'] as Map).cast<String, Object?>() : null,
      blob: raw['blob'] is String ? raw['blob'] as String : null,
      state: state == 'pending' || state == 'accepted' || state == 'declined' ? state as String : null,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'rev': rev,
        'kind': kind,
        'at': at,
        'readAt': readAt,
        'hidden': hidden,
        if (from != null) 'from': from,
        if (org != null) 'org': {'id': org!.id, 'name': org!.name},
        if (body != null) 'body': body,
        if (blob != null) 'blob': blob,
        if (state != null) 'state': state,
      };

  FeedNotification copyWith({int? Function()? readAt, bool? hidden, String? state}) => FeedNotification(
        id: id,
        rev: rev,
        kind: kind,
        at: at,
        readAt: readAt == null ? this.readAt : readAt(),
        hidden: hidden ?? this.hidden,
        from: from,
        org: org,
        body: body,
        blob: blob,
        state: state ?? this.state,
      );
}

// --- the words -------------------------------------------------------------------------------------------------------

/// "sam", or "Someone" for an account that is gone.
String _who(String? from) => from != null && from.isNotEmpty ? from : 'Someone';

/// The organization's name: live while the reader is a member, else as the row remembers it.
String _orgName(FeedNotification n) {
  final named = n.body?['name'];
  return n.org?.name ?? (named is String ? named : 'an organization');
}

String _text(Object? value, String fallback) => value is String && value.isNotEmpty ? value : fallback;

String _roleWords(Object? role) {
  if (role == 'owner') return 'the owner';
  if (role == 'admin') return 'an admin';
  return 'a member';
}

String _lines(int count) => count == 1 ? '1 line' : '$count lines';

/// The sentence a row reads as (`sentenceOf`). [opened] is a self row's payload once this device has opened it, or
/// null while it is sealed, or could not be opened: then the row is drawn by its kind alone ("Claude edited a
/// note"), and never stalls on the seal.
String sentenceOf(FeedNotification n, [NotificationDetails? opened]) {
  final kind = opened?.kind ?? n.kind;
  bool open(String want) => opened != null && opened.kind == want;
  switch (kind) {
    case 'invite':
      return '${_who(n.from)} invited you to ${_orgName(n)}';
    case 'invite-accepted':
      return '${_who(n.from)} accepted your invitation to ${_orgName(n)}';
    case 'invite-declined':
      return '${_who(n.from)} declined your invitation to ${_orgName(n)}';
    case 'member-joined':
      return '${_who(n.from)} joined ${_orgName(n)}';
    case 'member-left':
      return '${_who(n.from)} left ${_orgName(n)}';
    case 'member-removed':
      // The removed person is told the name (they are no longer a member, so the live name is not theirs to read);
      // the others are told who went.
      final handle = n.body?['handle'];
      return handle is String ? '${_who(n.from)} removed $handle from ${_orgName(n)}' : '${_who(n.from)} removed you from ${_orgName(n)}';
    case 'role-changed':
      return '${_who(n.from)} made you ${_roleWords(n.body?['role'])} of ${_orgName(n)}';
    case 'org-renamed':
      return '${_who(n.from)} renamed ${_text(n.body?['was'], 'an organization')} to ${_orgName(n)}';
    case 'org-deleted':
      return '${_who(n.from)} deleted ${_orgName(n)}';
    case 'note-created':
      return open('note-created') ? '${opened!.by} created ${opened.title}' : 'Claude created a note';
    case 'note-edited':
      return open('note-edited') ? '${opened!.by} edited ${opened.title} · ${_lines((opened.added ?? 0) + (opened.removed ?? 0))} changed' : 'Claude edited a note';
    case 'note-appended':
      return open('note-appended') ? '${opened!.by} added ${_lines(opened.lines ?? 0)} to ${opened.title}' : 'Claude added to a note';
    case 'journal-entry':
      return open('journal-entry') ? '${opened!.by} wrote an entry in ${opened.title}' : 'Claude wrote a journal entry';
    case 'rule-added':
      return open('rule-added') ? '${opened!.by} added a rule to ${opened.title}' : 'Claude added a rule';
    case 'summary-written':
      return open('summary-written') ? 'A meeting was written up: ${opened!.title}' : 'A meeting was written up';
    case 'sync-conflict':
      return open('sync-conflict') ? '${opened!.title} was kept twice: both devices had changed it' : 'A note was kept twice';
    case 'form-answer':
      return open('form-answer') ? 'A new answer to ${opened!.by ?? 'a form'}: ${opened.title}' : 'A form was answered';
    case 'mention':
      return open('mention') ? '${_text(opened!.by, _who(n.from))} mentioned you in ${opened.title}' : '${_who(n.from)} mentioned you in a note';
    case 'page-expired':
      return open('page-expired') ? '${opened!.title} needs review: its verification ran out' : 'A verified page needs review';
    case 'ticket':
      if (!open('ticket')) return '${_who(n.from)} changed a ticket you watch';
      final by = _text(opened!.by, _who(n.from));
      return switch (opened.what) {
        'closed' => '$by closed ${opened.title}',
        'commented' => '$by commented on ${opened.title}',
        _ => '$by changed ${opened.title}',
      };
    case 'ticket-digest':
      return open('ticket-digest') ? 'Your tickets today: ${opened!.title}' : 'Your tickets for today';
    case ticketRuleKind:
      return open(ticketRuleKind) ? 'A rule on ${opened!.title}' : 'A rule on a ticket';
  }
  // A kind this build does not know is not drawn (`listed`); asked for anyway, it has no words.
  return '';
}

/// The line under the sentence, when a self kind carries one: the first line Claude changed, added or wrote
/// (`detailOf`).
String? detailOf(NotificationDetails? opened) {
  if (opened == null) return null;
  if (opened.kind == 'note-edited' || opened.kind == 'note-appended' || opened.kind == 'journal-entry' || opened.kind == 'rule-added' || opened.kind == 'mention' || opened.kind == 'ticket' || opened.kind == 'ticket-digest' || opened.kind == ticketRuleKind) {
    final first = opened.first;
    return first == null || first.isEmpty ? null : first;
  }
  return null;
}

// --- the rules a list of rows asks (core/notifications/feed.ts) ------------------------------------------------------

/// The rows as the page lists them: of a kind this build knows, not hidden, newest first (`listed`).
List<FeedNotification> listed(Iterable<FeedNotification> items) {
  final rows = [
    for (final (at, n) in items.indexed)
      if (!n.hidden && isKind(n.kind)) (at, n),
  ];
  rows.sort((a, b) {
    final when = b.$2.at.compareTo(a.$2.at);
    if (when != 0) return when;
    final rev = b.$2.rev.compareTo(a.$2.rev);
    // Equal rows keep the order they came in, as the page's sort does.
    return rev != 0 ? rev : a.$1.compareTo(b.$1);
  });
  return [for (final (_, n) in rows) n];
}

/// Whether a row is one the person asked to see (Settings › Notifications): its category's switch is on, and its
/// organization is not muted. An invitation always is. Read from the plaintext kind, so no seal is opened
/// (`isWanted`).
bool isWanted(FeedNotification n, NotificationPrefs prefs) {
  if (!isKind(n.kind)) return false;
  final category = categoryOf(n.kind);
  if (category == 'invites') return true;
  if (!prefs.isOn(category)) return false;
  final org = n.org;
  return !(org != null && prefs.mutedOrgs.contains(org.id));
}

/// How many of the rows are unread and wanted: the bell's dot and the drawer's count, from plaintext fields only
/// (`unreadCount`).
int unreadCount(NotificationPrefs prefs, Iterable<FeedNotification> items) => items.where((n) => n.readAt == null && isWanted(n, prefs)).length;

/// An invitation not yet answered: never cleared, since its row is the one place to answer it (`isPendingInvite`,
/// notes/NotificationsDrawer.tsx).
bool isPendingInvite(FeedNotification n) => n.kind == 'invite' && n.state == 'pending';

/// A member's mention of this account: what the bell's Mentions filter shows.
bool isMention(FeedNotification n) => n.kind == 'mention';

/// A change to a ticket this account watches: what the row's Unwatch is offered on (lib/book/ticket_events.dart).
bool isTicketEvent(FeedNotification n) => n.kind == 'ticket';

/// The kinds about an organization, whose row opens it; an invitation is answered on its own row instead
/// (`ORG_KINDS`, notes/NotificationsDrawer.tsx).
const Set<String> orgKinds = {'invite-accepted', 'invite-declined', 'member-joined', 'member-left', 'member-removed', 'role-changed', 'org-renamed'};
