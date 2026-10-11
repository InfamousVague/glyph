/// Links that opened the app. A port of `src/app/share/appLinks.ts`, with the sorting of them from
/// `src/app/shell/useAppLinks.ts` and what a shared link does once sorted from `App.tsx` (`forkFromLink`) and
/// `notes/JoinSheet.tsx` (`JoinInvites`).
///
/// Four kinds: a share link, `ghostmd://fork#<id>.<key>`, the reader page's "Open in the Ghost.md app"; an invite
/// link, `ghostmd://join/<code>` (lib/orgs/join_links.dart); a note link, `ghostmd://note/<id>`, the tap on the
/// notification that says a meeting was written up; and a place, `ghostmd://notifications` or `ghostmd://org/<id>`.
///
/// What differs:
/// - **The plumbing is not here.** On the page the native side keeps each link until asked (`links_take`), says when
///   another arrives (`glyph://link`), and the Android activity remembers the one it was opened with
///   (`GlyphHost.takeLink`). Here those three are a [LinkSource] that whoever owns the Android intent gives;
///   [followAppLinks] is the page's function over it, the same link from both roads opened once.
/// - The sorting, which the page does inside a hook, is [readAppLink], and [openAppLink] hands a sorted link to an
///   [AppLinkDoor]: the four things the app does with one.
/// - What a share link and an invite do are functions the door's owner calls: [forkFromLink] (an invite pasted
///   where a share was asked for is an invite; else the share is read and a copy saved) and [takeJoin] /
///   [joinToAsk] (the code held on this device, and asked about once someone is signed in).
library;

import 'dart:async';

import '../core/note.dart';
import '../core/stored.dart';
import '../orgs/join_links.dart';
import 'share.dart';

final RegExp _noteLink = RegExp(r'^ghostmd://note/([A-Za-z0-9_-]+)/?$');

/// The note a `ghostmd://note/<id>` link names, or null for any other link (`readNoteLink`). The id is a plain one.
String? readNoteLink(String link) => _noteLink.firstMatch(link.trim())?.group(1);

/// A place a link can name (`readPlaceLink`'s answer).
sealed class LinkedPlace {
  const LinkedPlace();
}

/// `ghostmd://notifications`: the notifications drawer.
class NotificationsPlace extends LinkedPlace {
  const NotificationsPlace();

  @override
  bool operator ==(Object other) => other is NotificationsPlace;

  @override
  int get hashCode => (NotificationsPlace).hashCode;
}

/// `ghostmd://org/<id>`: an organization's dashboard.
class OrganizationPlace extends LinkedPlace {
  const OrganizationPlace(this.orgId);
  final String orgId;

  @override
  bool operator ==(Object other) => other is OrganizationPlace && other.orgId == orgId;

  @override
  int get hashCode => orgId.hashCode;
}

final RegExp _notificationsLink = RegExp(r'^ghostmd://notifications/?$');
final RegExp _orgLink = RegExp(r'^ghostmd://org/([A-Za-z0-9_-]{1,64})/?$');

/// The notifications drawer, `ghostmd://notifications`, or an organization's dashboard, `ghostmd://org/<id>`, the id
/// as the service makes one. Null for any other link (`readPlaceLink`).
LinkedPlace? readPlaceLink(String link) {
  final trimmed = link.trim();
  if (_notificationsLink.hasMatch(trimmed)) return const NotificationsPlace();
  final org = _orgLink.firstMatch(trimmed)?.group(1);
  return org != null ? OrganizationPlace(org) : null;
}

/// A link that opened the app, sorted.
sealed class AppLink {
  const AppLink(this.link);

  /// The link as it arrived.
  final String link;
}

/// `ghostmd://join/<code>`: an invitation to an organization.
class JoinAppLink extends AppLink {
  const JoinAppLink(super.link, this.code);
  final String code;
}

/// `ghostmd://note/<id>`: a note to open.
class NoteAppLink extends AppLink {
  const NoteAppLink(super.link, this.noteId);
  final String noteId;
}

/// `ghostmd://notifications` or `ghostmd://org/<id>`.
class PlaceAppLink extends AppLink {
  const PlaceAppLink(super.link, this.place);
  final LinkedPlace place;
}

/// `ghostmd://fork#<id>.<key>`: something shared, to save a copy of.
class ShareAppLink extends AppLink {
  const ShareAppLink(super.link, this.id, this.key);
  final String id;
  final String key;
}

/// What a link is, in the order the page asks (shell/useAppLinks.ts): an invite only by the app's own scheme, then a
/// note, then a place, then anything that carries a share's id and key. Null for a link that is none of them.
AppLink? readAppLink(String link) {
  final join = link.trim().startsWith('ghostmd://join/') ? readJoinLink(link) : null;
  if (join != null) return JoinAppLink(link, join);
  final note = readNoteLink(link);
  if (note != null) return NoteAppLink(link, note);
  final place = readPlaceLink(link);
  if (place != null) return PlaceAppLink(link, place);
  final share = readShareLink(link);
  return share != null ? ShareAppLink(link, share.id, share.key) : null;
}

/// What the app does with each kind of link (the hook's `fork`, `openNote`, `openPlace`, `join`).
abstract interface class AppLinkDoor {
  /// A share link: read it and save a copy ([forkFromLink]), then open what was saved.
  Future<void> fork(String link);

  /// A note link: open that note where it was left.
  Future<void> openNote(String id);

  /// The notifications drawer, or an organization's dashboard.
  void openPlace(LinkedPlace place);

  /// An invitation: hold the code and ask "Join it?" ([takeJoin]).
  void join(String code);
}

/// Hands [link] to [door] by its kind; nothing for a link that is none of them. A door that fails is its own
/// trouble: [onError] hears of it, as the page's `console.warn` does.
void openAppLink(String link, AppLinkDoor door, {void Function(Object failure)? onError}) {
  void warn(Object failure) => onError?.call(failure);
  switch (readAppLink(link)) {
    case JoinAppLink(:final code):
      door.join(code);
    case NoteAppLink(:final noteId):
      unawaited(door.openNote(noteId).then<void>((_) {}, onError: warn));
    case PlaceAppLink(:final place):
      door.openPlace(place);
    case ShareAppLink():
      unawaited(door.fork(link).then<void>((_) {}, onError: warn));
    case null:
      break;
  }
}

/// Where links that opened the app come from: the native side's three.
abstract interface class LinkSource {
  /// Every link kept since the last ask, and kept no longer (`links_take`). May throw on a side that has none.
  Future<List<String>> take();

  /// The link the activity was opened with, once, or null (`GlyphHost.takeLink`): the deep-link channel is set once
  /// per activity, and an activity recreated inside a live process may have none.
  String? takeActivityLink();

  /// Told each time another link arrives while the app runs (`glyph://link`); null on a side that cannot say.
  Stream<void>? get arrived;
}

/// Takes the links that opened the app once the app has its notes, and again whenever one arrives while it runs, and
/// hands every one to [open], which sorts them (`followAppLinks`). The same link from both roads is opened once.
/// Answers the way to stop; a take that answers after the stop opens nothing.
void Function() followAppLinks(void Function(String link) open, LinkSource source) {
  var gone = false;
  Future<void> take() async {
    List<String> links;
    try {
      links = await source.take();
    } catch (_) {
      links = const [];
    }
    if (gone) return;
    final activity = source.takeActivityLink();
    final seen = <String>{};
    for (final link in [...links, if (activity != null && activity.isNotEmpty) activity]) {
      if (seen.add(link)) open(link);
    }
  }

  unawaited(take());
  final heard = source.arrived?.listen((_) => unawaited(take()));
  return () {
    gone = true;
    unawaited(heard?.cancel());
  };
}

// --- what each does --------------------------------------------------------------------------------------------------

/// What following a link pasted or opened as a share came to (`forkFromLink`).
sealed class Forked {
  const Forked();
}

/// It was an invite link after all: [code] is to be asked about ([takeJoin]).
class ForkedInvite extends Forked {
  const ForkedInvite(this.code);
  final String code;
}

/// A copy was saved: [note] is the one to open, the note or the book.
class ForkedCopy extends Forked {
  const ForkedCopy(this.note);
  final Note note;
}

/// A link given where a share was asked for - the app's own scheme, or pasted into "From a shared link" - followed
/// (`forkFromLink`, App.tsx): an invite is an invite; anything else is read as a share ([Shares.readShared]) and a
/// copy saved into this library ([forkShared]), its pictures kept through the [Shares]' own. [notes] lists the
/// library and [save] makes a note with those words. The caller refreshes its list and opens what is answered.
Future<Forked> forkFromLink(String link, {required Shares shares, required Future<List<Note>> Function() notes, required Future<Note> Function(String body) save}) async {
  final invite = readJoinLink(link);
  if (invite != null) return ForkedInvite(invite);
  final shared = await shares.readShared(link);
  return ForkedCopy(await forkShared(shared, notes: notes, save: save, keep: shares.pictures.keep));
}

/// An invite link arrived (`JoinInvites`, the first effect): the code is held on this device, so one followed
/// signed out is still there once an account is, and answered for the sheet to ask "Join it?" about.
String takeJoin(String code, {int? now, Stored? kept}) {
  holdJoin(code, now: now, kept: kept);
  return code;
}

/// The code to ask about now that someone is signed in, if one is held and not stale (`JoinInvites`, the second
/// effect); null signed out, where nothing can be joined yet. Let it go with `dropHeldJoin` once it is joined or
/// the person says no.
String? joinToAsk({required bool signedIn, int? now, Stored? kept}) => signedIn ? heldJoin(now: now, kept: kept) : null;
