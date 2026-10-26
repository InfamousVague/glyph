import 'package:flutter/foundation.dart';

import '../core/note.dart';
import '../share/app_links.dart' show MarketPlace;
import 'visited.dart';

/// Something handed to a screen once, with the number that tells one handing from the next (the web's
/// `SpokenAsk & { key: number }` and its kin): a spoken instruction, a review after Stop, what a recording just
/// wrote. What it carries belongs to modules not ported yet (capture/, ai/), so it is held as an [Object].
@immutable
class Keyed {
  const Keyed(this.value, this.key);
  final Object value;
  final int key;

  @override
  bool operator ==(Object other) => other is Keyed && other.key == key && other.value == value;

  @override
  int get hashCode => Object.hash(value, key);
}

/// Where the caret goes in a note just made, opened to be written in (`caret?: number | 'end'`): an offset, or the
/// end of its words.
@immutable
class Caret {
  const Caret.at(int this.offset);
  const Caret.end() : offset = null;

  /// Null is the end.
  final int? offset;

  bool get atEnd => offset == null;

  @override
  bool operator ==(Object other) => other is Caret && other.offset == offset;

  @override
  int get hashCode => offset.hashCode;
}

/// Which screen is up: the one piece of state the app would have bought a router to hold (`Screen`, the web app's
/// shell/screen.ts).
///
/// Seven screens, each a member of one sealed class: the home page, the All notes grid, a note, a capture, a meeting
/// being recorded by the phone's service, the Academy and an organization's dashboard. Everything else a person sees
/// - Settings, the notifications drawer, the guide, the + sheet, the sidebar's card, the aside, the palette - is a
/// sheet or a card over whichever of these is up, and is held beside it in the shell rather than in here.
///
/// Four of the seven are places: the home page, the grid, a note and an organization's dashboard are where a person
/// goes, so they are where the tab row is drawn and where a wide window splits into panes; the first three are on
/// the trail the arrows walk. A capture, a meeting and the Academy are things a person is doing, each the whole
/// screen with its own way out.
///
/// Differs from the web: the union's members are classes ([ScreenList], [ScreenNotes], [ScreenNote],
/// [ScreenCapture], [ScreenMeeting], [ScreenAcademy], [ScreenOrganization]), and the questions asked of every
/// render are getters on it: `isRecording(screen)` is [isRecording], `placeOf(screen)` is [place], `isPlace(screen)`
/// is [isPlace] and `noteOnScreen(screen)` is [noteOnScreen]. What a note's screen carries of the capture and AI modules
/// (`ask`, `review`, `landing`, `cursor`, a capture's `placing`) is held without its type until those are ported.
@immutable
sealed class Screen {
  const Screen();

  /// The home page, which the app opens on and every way out comes back to.
  const factory Screen.list() = ScreenList;

  /// Every note as a grid of cards; with [tapes], only the notes with a recording.
  const factory Screen.notes({bool tapes}) = ScreenNotes;

  /// A note.
  const factory Screen.note(Note note, {String? at, Keyed? ask, Keyed? review, Keyed? landing, Caret? caret, Object? cursor}) = ScreenNote;

  /// Glyph Academy.
  const factory Screen.academy() = ScreenAcademy;

  /// An organization's dashboard, or with [page] its audit log.
  const factory Screen.organization(String orgId, {OrganizationPage? page}) = ScreenOrganization;

  /// The Tags page, one tag's notes, or a smart notebook's (lib/notes/collection_screen.dart).
  const factory Screen.collection(CollectionKind kind, {String key, bool fromTags}) = ScreenCollection;

  /// The Market: the plugins, themes and fonts to add (lib/market/market_screen.dart), opened at [plugin]'s page
  /// when one is named, or where a `ghostmd://market` [link] lands.
  const factory Screen.market({String? plugin, MarketPlace? link}) = ScreenMarket;

  /// The union's tag: `list`, `notes`, `note`, `capture`, `meeting`, `academy`, `organization`, `collection`,
  /// `market`.
  String get name;

  /// Whether the screen is the whole window with a microphone behind it: a capture or a meeting, over which nothing
  /// else is drawn.
  bool get isRecording => this is ScreenCapture || this is ScreenMeeting;

  /// Where on the trail the screen is: the home page, the grid, or a note. A capture, the Academy and an
  /// organization's dashboard are none: the arrows never walk into them, whose way out is their own arrow home.
  Place? get place => switch (this) {
        ScreenNote(:final note) => notePlace(note.id),
        ScreenList() => homePlace,
        ScreenNotes() => allNotesPlace,
        _ => null,
      };

  /// Whether the screen is one of the places, which carry the app's tab row and take a pane beside the sidebar on a
  /// wide window: the three on the trail, and an organization's dashboard, drawn where All notes is.
  bool get isPlace => place != null || this is ScreenOrganization || this is ScreenCollection || this is ScreenMarket;

  /// The id of the note on screen, or null when the screen is not a note.
  String? get noteOnScreen => switch (this) { ScreenNote(:final note) => note.id, _ => null };
}

/// The home page (`{ name: 'list' }`).
class ScreenList extends Screen {
  const ScreenList();

  @override
  String get name => 'list';

  @override
  bool operator ==(Object other) => other is ScreenList;

  @override
  int get hashCode => name.hashCode;
}

/// The All notes grid (`{ name: 'notes'; tapes? }`).
class ScreenNotes extends Screen {
  const ScreenNotes({this.tapes = false});

  /// Opened from the Tapes heading's "See all": only the notes with a recording.
  final bool tapes;

  @override
  String get name => 'notes';

  @override
  bool operator ==(Object other) => other is ScreenNotes && other.tapes == tapes;

  @override
  int get hashCode => Object.hash(name, tapes);
}

/// A note (`{ name: 'note'; note; at?; ask?; review?; landing?; caret?; cursor? }`).
class ScreenNote extends Screen {
  const ScreenNote(this.note, {this.at, this.ask, this.review, this.landing, this.caret, this.cursor});

  final Note note;

  /// The item to land on, `^anchor`, when the note was opened by a link that pointed inside it.
  final String? at;

  /// A spoken instruction about this note, run on it as it opens.
  final Keyed? ask;

  /// After Stop: the slower models check the take in the note itself.
  final Keyed? review;

  /// What a recording just wrote into this note, for its Undo.
  final Keyed? landing;

  /// A note just made, opened to be written in: the caret here, the editor focused. A note opened to be read takes
  /// no focus.
  final Caret? caret;

  /// A member's caret, or their spot on a canvas, to open at.
  final Object? cursor;

  /// This screen with another spoken instruction: the palette's runs on the note being read.
  ScreenNote asked(Keyed ask) => ScreenNote(note, at: at, ask: ask, review: review, landing: landing, caret: caret, cursor: cursor);

  @override
  String get name => 'note';

  @override
  bool operator ==(Object other) =>
      other is ScreenNote && identical(other.note, note) && other.at == at && other.ask == ask && other.review == review && other.landing == landing && other.caret == caret && other.cursor == cursor;

  @override
  int get hashCode => Object.hash(name, note.id, at, ask, review, landing, caret, cursor);
}

/// A capture (`{ name: 'capture'; key; fromAssistant; stop; noteId?; placing?; meeting? }`).
class ScreenCapture extends Screen {
  const ScreenCapture({required this.key, required this.fromAssistant, this.stop = 0, this.noteId, this.placing, this.meeting = false});

  /// A capture, fresh (`captureScreen`): from the side key ([fromAssistant]) or a Speak button, into [noteId] when it
  /// was one note's, at [placing] when its opener says where in it; a meeting on the Mac with [meeting]. [now] is
  /// the clock, for a test.
  factory ScreenCapture.fresh(bool fromAssistant, {String? noteId, bool meeting = false, Object? placing, int? now}) => ScreenCapture(
        key: now ?? DateTime.now().millisecondsSinceEpoch,
        fromAssistant: fromAssistant,
        noteId: noteId,
        // Where in the note, only with a note to be in.
        placing: noteId == null ? null : placing,
        meeting: meeting,
      );

  /// Each capture is a fresh mount, keyed, so a second press mid-capture cannot inherit the first one's microphone.
  final int key;
  final bool fromAssistant;

  /// How many times the side key has asked this capture to stop: a count, so each press is a change.
  final int stop;

  /// Talking into this note, from its Speak: the words go here, and the capture comes back here.
  final String? noteId;

  /// Where in that note, when its opener says: a journal's entry said aloud.
  final Object? placing;

  /// A meeting in the page recorder (the Mac): recorded, not read, and written up after.
  final bool meeting;

  /// This capture asked to stop once more.
  ScreenCapture stopped() => ScreenCapture(key: key, fromAssistant: fromAssistant, stop: stop + 1, noteId: noteId, placing: placing, meeting: meeting);

  @override
  String get name => 'capture';

  @override
  bool operator ==(Object other) =>
      other is ScreenCapture && other.key == key && other.fromAssistant == fromAssistant && other.stop == stop && other.noteId == noteId && other.placing == placing && other.meeting == meeting;

  @override
  int get hashCode => Object.hash(name, key, fromAssistant, stop, noteId, placing, meeting);
}

/// A meeting being recorded by the phone's own service (`{ name: 'meeting'; noteId; fromAssistant; key }`).
class ScreenMeeting extends Screen {
  const ScreenMeeting({required this.noteId, required this.fromAssistant, required this.key});

  /// The meeting screen for the note the service is recording into (`meetingScreen`).
  factory ScreenMeeting.fresh(String noteId, bool fromAssistant, {int? now}) =>
      ScreenMeeting(noteId: noteId, fromAssistant: fromAssistant, key: now ?? DateTime.now().millisecondsSinceEpoch);

  final String noteId;
  final bool fromAssistant;

  /// Each opening is a fresh mount, keyed, as a capture's is.
  final int key;

  @override
  String get name => 'meeting';

  @override
  bool operator ==(Object other) => other is ScreenMeeting && other.noteId == noteId && other.fromAssistant == fromAssistant && other.key == key;

  @override
  int get hashCode => Object.hash(name, noteId, fromAssistant, key);
}

/// Glyph Academy (`{ name: 'academy' }`).
class ScreenAcademy extends Screen {
  const ScreenAcademy();

  @override
  String get name => 'academy';

  @override
  bool operator ==(Object other) => other is ScreenAcademy;

  @override
  int get hashCode => name.hashCode;
}

/// A page under an organization's dashboard (`page?: 'log'`).
enum OrganizationPage { log }

/// An organization's dashboard (`{ name: 'organization'; orgId; page? }`); with [page] it is the organization's audit
/// log instead, a page under the dashboard whose arrow goes back to it.
class ScreenOrganization extends Screen {
  const ScreenOrganization(this.orgId, {this.page});

  final String orgId;
  final OrganizationPage? page;

  @override
  String get name => 'organization';

  @override
  bool operator ==(Object other) => other is ScreenOrganization && other.orgId == orgId && other.page == page;

  @override
  int get hashCode => Object.hash(name, orgId, page);
}

/// Which collection of notes a [ScreenCollection] is: every tag, the notes of one, or a smart notebook's.
enum CollectionKind { tags, tag, smart }

/// A page of notes gathered by what they say rather than where they are filed (the port's own, 2026-10-16): the Tags
/// page, a tag's notes ([key] is the tag), or a smart notebook's ([key] is its id). A place, drawn where All notes
/// is, with the tab row over it and the sidebar beside it on a wide window; not on the trail the arrows walk, as an
/// organization's dashboard is not. Its way out goes home, and a tag's opened from the Tags page ([fromTags]) goes
/// back there.
class ScreenCollection extends Screen {
  const ScreenCollection(this.kind, {this.key = '', this.fromTags = false});

  final CollectionKind kind;
  final String key;
  final bool fromTags;

  @override
  String get name => 'collection';

  @override
  bool operator ==(Object other) => other is ScreenCollection && other.kind == kind && other.key == key && other.fromTags == fromTags;

  @override
  int get hashCode => Object.hash(name, kind, key, fromTags);
}

/// The Market (the port's own, Matt, 2026-10-26: "Make the plugins a dedicated "Market" section in the app, include
/// some more themes, fonts an of course all our plugins"): every plugin, theme and font to add, out of Settings and
/// a place of its own. A place as the Tags page is, drawn where All notes is with the tab row over it and the sidebar
/// beside it on a wide window; not on the trail the arrows walk, and its way out goes home. With [plugin] it opens on
/// that plugin's page: an old link to Settings › Plugins › its name lands here. With [link] it opens where a
/// `ghostmd://market/<kind>/<id>` lands, the website's market page's Open in Ghost.md (lib/market/market_items.dart
/// `marketLinkLanding`).
class ScreenMarket extends Screen {
  const ScreenMarket({this.plugin, this.link});

  final String? plugin;
  final MarketPlace? link;

  @override
  String get name => 'market';

  @override
  bool operator ==(Object other) => other is ScreenMarket && other.plugin == plugin && other.link == link;

  @override
  int get hashCode => Object.hash(name, plugin, link);
}
