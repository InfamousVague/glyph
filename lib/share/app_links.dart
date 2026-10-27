/// Links that opened the app. A port of `src/app/share/appLinks.ts`, with the sorting of them from
/// `src/app/shell/useAppLinks.ts` and what a shared link does once sorted from `App.tsx` (`forkFromLink`) and
/// `notes/JoinSheet.tsx` (`JoinInvites`).
///
/// Four kinds: a share link, `ghostmd://fork#<id>.<key>`, the reader page's "Open in the Ghost.md app"; an invite
/// link, `ghostmd://join/<code>` (lib/orgs/join_links.dart); a note link, `ghostmd://note/<id>`, the tap on the
/// notification that says a meeting was written up; and a place, `ghostmd://notifications`, `ghostmd://org/<id>` or
/// the Market, `ghostmd://market/<kind>/<id>` (ghostmarkdown.com/market.html's Open in Ghost.md).
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

/// What a link into the Market names: a plugin, a theme, a font, or an icon pack (`icons`, Matt, 2026-10-27).
enum MarketKind { plugin, theme, font, icons }

/// `ghostmd://market`, the Market (lib/market/market_screen.dart), at one thing on its shelves when the link names it
/// (Matt, 2026-10-26: "add a browsable marketplace listed under the plugins section on the website that deeplinks to
/// the app"). The website's market page (landing/market.html) opens each plugin, theme and font by
/// `ghostmd://market/<kind>/<id>`: `ghostmd://market/plugin/notion`, `ghostmd://market/theme/dusk`,
/// `ghostmd://market/font/lora`, and each icon pack by `ghostmd://market/icons/phosphor`. A kind alone, `ghostmd://market/theme`, is that shelf; an id alone,
/// `ghostmd://market/notion`, is whichever of the three has it, a plugin first. Not on the page, which had no Market.
///
/// [kind] and [id] are as the link has them, not yet looked up: whether the id is one this build carries is the
/// Market's to say ([marketLinkLanding], lib/market/market_items.dart), and one it does not carry lands on the
/// Market's front with a word saying so.
class MarketPlace extends LinkedPlace {
  const MarketPlace({this.kind, this.id});
  final MarketKind? kind;
  final String? id;

  @override
  bool operator ==(Object other) => other is MarketPlace && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'ghostmd://market${kind == null ? '' : '/${kind!.name}'}${id == null ? '' : '/$id'}';
}

final RegExp _notificationsLink = RegExp(r'^ghostmd://notifications/?$');
final RegExp _orgLink = RegExp(r'^ghostmd://org/([A-Za-z0-9_-]{1,64})/?$');

/// `ghostmd://market`, then a kind or an id or both: an id as the app's lists keep one, lowercase letters, digits and
/// dashes. A link from a page may carry a query or a fragment after it (`?from=site`); they say nothing here.
final RegExp _marketLink = RegExp(r'^ghostmd://market(?:/(plugin|theme|font|icon)s?)?(?:/([a-z0-9][a-z0-9_-]{0,63}))?/?(?:[?#].*)?$');

/// The notifications drawer, `ghostmd://notifications`, an organization's dashboard, `ghostmd://org/<id>`, the id
/// as the service makes one, or the Market, `ghostmd://market/<kind>/<id>` ([MarketPlace]). Null for any other link
/// (`readPlaceLink`).
LinkedPlace? readPlaceLink(String link) {
  final trimmed = link.trim();
  if (_notificationsLink.hasMatch(trimmed)) return const NotificationsPlace();
  final org = _orgLink.firstMatch(trimmed)?.group(1);
  if (org != null) return OrganizationPlace(org);
  final market = _marketLink.firstMatch(trimmed.toLowerCase());
  if (market == null) return null;
  final kind = market.group(1);
  // `icon` and `icons` are both the icon packs' shelf, whose kind is written `icons` (`ghostmd://market/icons`).
  return MarketPlace(kind: kind == null ? null : (kind == 'icon' ? MarketKind.icons : MarketKind.values.byName(kind)), id: market.group(2));
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

/// `ghostmd://notifications`, `ghostmd://org/<id>` or `ghostmd://market/<kind>/<id>`.
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

  /// The notifications drawer, an organization's dashboard, or the Market at a plugin, a theme or a font.
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
