/// A note keeping its place: the tag that waits to be written, tagging the notes a person makes, a new note's held
/// box, the watchers and the kept refusal. Ports what lib/core/location.dart left of `src/app/core/location.ts`,
/// on top of its [Locations]: `pendingTag`, `setPendingTag`, `settleTag`, `settleWaitingTags`, `landTag`,
/// `tagNewNotes`, `tagNewNotesIfWanted`, `tagEntryIfWanted`, `askFromPress`, `willLocate`, `holdFor`, `heldFor`,
/// `watchTag`, `wantPlace`, `autoTagRefusal`, `refusedFor`, `rememberRefusal`, `forgetRefusal`, `refusalStanding`
/// and `allowLocationWhere`.
///
/// The rules of the page's module stand, and the ones kept here are:
///
/// 2. THE NAME IS ASKED ONCE, FOR A TAG MADE HERE, and only once the tag is in the note ([PlaceTags.wantPlace]): a
///    tag still waiting, for a draft that may never get a word, sends nothing. Never for a note that arrived by
///    sync or a forked share: nothing here asks for a tag it did not make.
/// 3. A TAG WAITS FOR THE BETTER WORDS. A tag for a new recording is kept aside ([PlaceTags.setPendingTag]) while a
///    pass is queued or a review is live, and written once the pass has landed or the review has handed back: by
///    the note's screen when it is open, and otherwise here ([PlaceTags.settleWaitingTags]), when a pass finishes,
///    when a note is left, and at launch. It also waits for a note's first words: a typed new note is a draft with
///    no file until it has some, and a draft left without any takes its waiting tag with it. A journal's entry has
///    words from birth, its template's, so its tag waits for the first of its own.
/// 4. NEVER WHILE THE RECORDER IS LIVE. A fix is asked from a note's More sheet, Settings' Location card, a
///    journal's place switch, and the shell after a capture has ended and its screen has gone.
///
/// The first automatic ask on a device that has never answered the prompt is introduced in the app's own words
/// first (`introduce`, a toast with "Allow location" on it), so the system's dialog comes from a press rather than
/// over a blank note. A NEW NOTE'S MAP HOLDS ITS PLACE: where a fix is expected ([PlaceTags.willLocate]) the note's
/// box is held from its first frame ([PlaceTags.holdFor]) and kept until the note is left, found or not.
///
/// What differs:
/// - The module's state is a [PlaceTags] object, and what it asked of the rest of the page is given to it: the
///   better words' queue (`refinePending`), the note store (`getNote`, `updateNote`), the records of the notes
///   nobody wrote in, the preferences, this device's memory, the clock and the wait.
/// - A tag here is the note's own (lib/core/geotag.dart [GeoTag]); [Locations] is handed its twin
///   (lib/core/place_refs.dart).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import 'front_matter.dart';
import 'geotag.dart';
import 'location.dart' as where;
import 'location.dart' show LocateFailure, LocationAccess, Locations, whyLocateFailed;
import 'note.dart';
import 'place_refs.dart' as refs;
import 'preferences.dart';
import 'stored.dart';
import 'untouched.dart';

/// A pending tag older than this is forgotten on read (`PENDING_MS`).
const int pendingTagMs = 24 * 60 * 60000;

/// A note just left: its last save lands before a waiting tag is written into it (`LEFT_MS`).
const Duration leftWait = Duration(milliseconds: 2000);

/// A refusal is about the notes made from a little before it (the one whose ask it answered) onwards.
const int refusalReachMs = 5 * 60000;

const String _pendingKey = 'glyph-geotag-pending';
const String _refusedKey = 'glyph-geotag-refused';

/// What a note's screen is told of its tag (`TagEvent`): a name arriving, a tag now waiting to be written, or its
/// box held or let go.
sealed class TagEvent {
  const TagEvent();
}

class TagPlace extends TagEvent {
  const TagPlace(this.place, this.lat, this.lon);
  final String place;
  final double lat;
  final double lon;
}

class TagPending extends TagEvent {
  const TagPending();
}

class TagHeld extends TagEvent {
  const TagHeld();
}

/// Why a note's box is held: its fix on its way, or none coming.
enum Held { waiting, missed }

/// Whether a review is live for the notes being tagged (`{ reviewing }`).
typedef Waiting = ({bool reviewing});

/// Says what a first location ask is for, and hands its press the ask (`introduce`).
typedef Introduce = void Function(void Function() allow);

refs.GeoTag _ref(GeoTag tag) => refs.GeoTag(lat: tag.lat, lon: tag.lon, place: tag.place, rough: tag.rough);
GeoTag _note(refs.GeoTag tag) => GeoTag(lat: tag.lat, lon: tag.lon, place: tag.place, rough: tag.rough);

/// A fix as the note's tag (`tagOf`).
GeoTag tagOfFix(where.Fix fix) => _note(where.tagOf(fix));

/// The tags that wait, the notes being tagged, and what the device refused.
class PlaceTags {
  PlaceTags({
    required this.locations,
    required Future<Note?> Function(String id) getNote,
    required Future<Object?> Function(String id, String body, int expectedRevision) updateNote,
    bool Function(String id)? refinePending,
    UntouchedNotes? untouched,
    PreferencesStore? prefs,
    Stored? kept,
    int Function()? now,
    Timer Function(Duration wait, void Function() then)? later,
  })  : _getNote = getNote,
        _updateNote = updateNote,
        _refinePending = refinePending ?? ((_) => false),
        _untouched = untouched,
        _prefs = prefs,
        _kept = kept,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _later = later ?? Timer.new;

  /// The fix, the gates and a place's name.
  final Locations locations;
  final Future<Note?> Function(String id) _getNote;
  final Future<Object?> Function(String id, String body, int expectedRevision) _updateNote;
  final bool Function(String id) _refinePending;
  final UntouchedNotes? _untouched;
  final PreferencesStore? _prefs;
  final Stored? _kept;
  final int Function() _now;
  final Timer Function(Duration wait, void Function() then) _later;

  Stored get _device => _kept ?? stored;
  Preferences get _preferences => (_prefs ?? preferences).value;
  UntouchedNotes get _records => _untouched ?? untouchedNotes;

  // ---- the watchers -------------------------------------------------------------------------------------------------

  final Map<String, Set<void Function(TagEvent event)>> _watchers = <String, Set<void Function(TagEvent event)>>{};

  /// The note's screen, following its tag: a name arriving, or a tag now waiting to be written. Answers the way to
  /// stop (`watchTag`).
  void Function() watchTag(String noteId, void Function(TagEvent event) listener) {
    final set = _watchers.putIfAbsent(noteId, () => <void Function(TagEvent event)>{})..add(listener);
    return () {
      set.remove(listener);
      if (set.isNotEmpty) return;
      _watchers.remove(noteId);
      // The note left: its box is let go once its fix has settled, and a tag still waiting for it is written in
      // once its last save has landed, where it may be.
      if (_held[noteId] != Held.waiting) _held.remove(noteId);
      if (pendingTag(noteId) != null) _later(leftWait, () => unawaited(_settleClosed(noteId)));
    };
  }

  bool _watched(String noteId) => _watchers[noteId]?.isNotEmpty ?? false;

  void _tell(String noteId, TagEvent event) {
    for (final listener in <void Function(TagEvent event)>[...?_watchers[noteId]]) {
      listener(event);
    }
  }

  // ---- the box held for a fix on its way ----------------------------------------------------------------------------

  /// The new notes whose map's box is held: while their fix is on its way, and once it is known none is coming.
  final Map<String, Held> _held = <String, Held>{};

  /// Holds each note's map box from now, its fix on its way (`holdFor`).
  void holdFor(Iterable<String> ids) {
    for (final id in ids) {
      _held[id] = Held.waiting;
      _tell(id, const TagHeld());
    }
  }

  /// Whether the note's box is held, and why; null for a note holding none (`heldFor`).
  Held? heldFor(String noteId) => _held[noteId];

  /// A held note's fix settled. Found, the tag holds the box from here, so the hold goes. Missed, the box stays,
  /// saying so, until the note is left; a note already left lets it go now (`settleHold`).
  void _settleHold(Iterable<String> ids, bool found) {
    for (final id in ids) {
      if (!_held.containsKey(id)) continue;
      if (found || !_watched(id)) {
        _held.remove(id);
      } else {
        _held[id] = Held.missed;
      }
      _tell(id, const TagHeld());
    }
  }

  // ---- the place's name ---------------------------------------------------------------------------------------------

  /// Notes with an ask in flight.
  final Set<String> _asking = <String>{};

  /// A name that came for these coordinates while nothing was open to take it, or null (`placeFor`).
  String? placeFor(GeoTag tag) => locations.placeFor(_ref(tag));

  /// A name that arrived for a note that is closed: written straight in, unless a pass is queued to rewrite it.
  Future<void> _writePlaceClosed(String noteId, GeoTag tag, String place) async {
    if (_refinePending(noteId)) return;
    final Note? fresh;
    try {
      fresh = await _getNote(noteId);
    } catch (_) {
      return;
    }
    if (fresh == null) return;
    final now = geoTagOf(fresh.body);
    if (now == null || now.place != null || now.lat != tag.lat || now.lon != tag.lon) return;
    try {
      await _updateNote(noteId, withGeoTag(fresh.body, now.named(place)), fresh.revision);
    } catch (_) {
      // Another writer got there first: the name is known for the next open.
    }
  }

  /// A name for the note's tag, where it can be taken: the note's screen, the tag still waiting, or the closed note.
  Future<void> _deliver(String noteId, GeoTag tag, String place) async {
    final pending = pendingTag(noteId);
    if (pending != null && pending.lat == tag.lat && pending.lon == tag.lon) setPendingTag(noteId, pending.named(place));
    if (_watched(noteId)) {
      _tell(noteId, TagPlace(place, tag.lat, tag.lon));
    } else if (pending == null) {
      await _writePlaceClosed(noteId, tag, place);
    }
  }

  /// Asks for the tag's name, once, for a tag this device made and has written into its note: a no-op for a tag
  /// that has one, one that failed this run, or where asking is not allowed. The note's screen is told when it
  /// arrives; a closed note is written; a name nobody could take waits in memory (`wantPlace`).
  void wantPlace(String noteId, GeoTag tag) {
    if (tag.place != null) return;
    final had = placeFor(tag);
    if (had != null) {
      unawaited(_deliver(noteId, tag, had));
      return;
    }
    if (_asking.contains(noteId)) return;
    _asking.add(noteId);
    unawaited(
      locations.placeName(_ref(tag)).then<void>((place) => place == null ? null : _deliver(noteId, tag, place)).whenComplete(() {
        _asking.remove(noteId);
      }),
    );
  }

  // ---- the tag waiting for the better words -------------------------------------------------------------------------

  Map<String, Map<String, Object?>> _readPending() {
    final all = _device.read<Map<String, Object?>>(_pendingKey, const <String, Object?>{}, (raw) => raw is Map ? raw.cast<String, Object?>() : null);
    final now = _now();
    final kept = <String, Map<String, Object?>>{};
    for (final MapEntry(key: id, value: raw) in all.entries) {
      if (raw is! Map) continue;
      final entry = raw.cast<String, Object?>();
      final at = entry['at'];
      if (entry['lat'] is! num || entry['lon'] is! num || at is! num) continue;
      // A day, or for as long as the note's pass is still queued: the tag is what the pass is waited for.
      if (now - at > pendingTagMs && !_refinePending(id)) continue;
      kept[id] = entry;
    }
    return kept;
  }

  /// The tag waiting to be written into the note, or null (`pendingTag`).
  GeoTag? pendingTag(String noteId) {
    final entry = _readPending()[noteId];
    if (entry == null) return null;
    final place = entry['place'];
    return GeoTag(lat: (entry['lat']! as num).toDouble(), lon: (entry['lon']! as num).toDouble(), rough: entry['rough'] == true, place: place is String && place.isNotEmpty ? place : null);
  }

  /// Keeps `tag` aside for the note, or (null) forgets it: the note went to the trash, its words were undone, or
  /// the tag landed (`setPendingTag`).
  void setPendingTag(String noteId, GeoTag? tag) {
    final all = _readPending();
    if (tag != null) {
      all[noteId] = <String, Object?>{'lat': tag.lat, 'lon': tag.lon, 'rough': tag.rough, if (tag.place != null && tag.place!.isNotEmpty) 'place': tag.place, 'at': _now()};
    } else if (!all.containsKey(noteId)) {
      return;
    } else {
      all.remove(noteId);
    }
    _device.write(_pendingKey, all.isEmpty ? null : all);
  }

  /// Whether the words after the front matter say anything.
  static bool _hasWords(String body) => body.substring(frontMatterOffset(body)).trim().isNotEmpty;

  /// Whether the words are the person's own: any at all, and not a journal's entry still as this device made it
  /// from its template (`hasOwnWords`).
  bool _hasOwnWords(String noteId, String body, [Note? note]) =>
      _hasWords(body) && !_records.isUntouched(noteId, body, recordingMs: note?.recordingMs, starred: note?.starred ?? false, archivedAt: note?.archivedAt);

  /// The body with the note's pending tag written in, when it may land: not while a better-words pass is queued or
  /// running for the note, not while a review is live for it, and not into a note with no words yet. Null when it
  /// may not, or there is nothing waiting (`settleTag`).
  String? settleTag(String noteId, String body, {required bool reviewing}) {
    final tag = pendingTag(noteId);
    if (tag == null) return null;
    if (reviewing || _refinePending(noteId) || !_hasOwnWords(noteId, body)) return null;
    return withGeoTag(body, tag);
  }

  // ---- the kept refusal ---------------------------------------------------------------------------------------------

  ({LocateFailure why, int at})? _readRefusal() => _device.read<({LocateFailure why, int at})?>(_refusedKey, null, (raw) {
        if (raw is! Map) return null;
        final why = raw['why'], at = raw['at'];
        if (why is! String || at is! num) return null;
        for (final failure in LocateFailure.values) {
          if (_word(failure) == why) return (why: failure, at: at.toInt());
        }
        return null;
      });

  /// A failure as the page kept it (`'local-only'` for the one word that differs).
  static String _word(LocateFailure why) => why == LocateFailure.localOnly ? 'local-only' : why.name;

  /// The refusal the last automatic ask met, if any (`autoTagRefusal`).
  LocateFailure? autoTagRefusal() => _readRefusal()?.why;

  /// Why a note made at `createdAt` was not tagged on its own, if a refusal explains it: the note's More sheet says
  /// so. A note older than the refusal was never going to be tagged, so it is told nothing (`refusedFor`).
  LocateFailure? refusedFor(int createdAt) {
    final kept = _readRefusal();
    return kept != null && createdAt >= kept.at - refusalReachMs ? kept.why : null;
  }

  /// Counts up each time a refusal is kept or forgotten, for what says one on screen (Settings' Location card,
  /// where the page kept `refusedHere` in the card's own state).
  ValueListenable<int> get refusals => _refusals;
  final ValueNotifier<int> _refusals = ValueNotifier<int>(0);

  /// An automatic ask was refused, or the phone blocks location: no automatic ask is made again until it is allowed
  /// (`rememberRefusal`).
  void rememberRefusal(LocateFailure why) {
    if (why != LocateFailure.refused && why != LocateFailure.blocked) return;
    _device.write(_refusedKey, <String, Object?>{'why': _word(why), 'at': _now()});
    _refusals.value += 1;
  }

  /// Where location is allowed again after a refusal, as a sentence's start (`allowLocationWhere`).
  String allowLocationWhere() => locations.onPhone ? 'Allow location for Ghost.md in the phone’s settings' : 'Allow location for this site in the browser’s settings';

  /// A fix came, or the person allowed location: the automatic ask may be made again (`forgetRefusal`).
  void forgetRefusal() {
    if (_readRefusal() == null) return;
    _device.write(_refusedKey, null);
    _refusals.value += 1;
  }

  /// Whether the device says location is allowed for the app now; false where it cannot say (`allowedNow`).
  Future<bool> _allowedNow() async {
    final state = await locations.access();
    return state == LocationAccess.granted || state == LocationAccess.approximate;
  }

  /// Whether a kept refusal still stands. Allowing location in the phone's settings is a choice too: where the
  /// device says it is allowed now, the refusal is forgotten and the ask made (`stillRefused`).
  Future<LocateFailure?> _stillRefused() async {
    final why = autoTagRefusal();
    if (why == null) return null;
    if (!await _allowedNow()) return why;
    forgetRefusal();
    return null;
  }

  /// Whether a refusal the device keeps still stands (`refusalStanding`).
  Future<bool> refusalStanding() async => await _stillRefused() != null;

  // ---- a waiting tag written where no screen holds it ---------------------------------------------------------------

  /// A waiting tag written into its note where no screen holds it: once no pass is queued for it and it has words,
  /// and unless it says where it was written already. A note that is gone takes its waiting tag with it. The name
  /// is asked then, since the tag has landed. Answers whether the tag landed (`settleClosed`).
  Future<bool> _settleClosed(String id) async {
    final tag = pendingTag(id);
    if (tag == null || _watched(id)) return false;
    if (_refinePending(id)) {
      // Still waiting for the pass: its day starts again, so the tag is there when the pass lands, however late.
      setPendingTag(id, tag);
      return false;
    }
    final Note? fresh;
    try {
      fresh = await _getNote(id);
    } catch (_) {
      // The store did not answer: the tag waits for the next look.
      return false;
    }
    if (fresh == null || geoTagOf(fresh.body) != null) {
      setPendingTag(id, null);
      return false;
    }
    if (!_hasOwnWords(id, fresh.body, fresh)) return false;
    try {
      await _updateNote(id, withGeoTag(fresh.body, tag), fresh.revision);
    } catch (_) {
      // Another writer got there first: the tag waits for the next look.
      return false;
    }
    setPendingTag(id, null);
    wantPlace(id, tag);
    return true;
  }

  Future<int>? _sweeping;
  bool _sweepAgain = false;

  /// Every waiting tag whose note is closed, written in where it may now land: called when a better-words pass has
  /// finished and at launch, so a recording's tag reaches the note without the note being opened again. Answers how
  /// many landed, so the list is read again only when one did (`settleWaitingTags`).
  Future<int> settleWaitingTags() {
    final already = _sweeping;
    if (already != null) {
      _sweepAgain = true;
      return already;
    }
    Future<int> sweep() async {
      var landed = 0;
      do {
        _sweepAgain = false;
        for (final id in _readPending().keys.toList()) {
          if (await _settleClosed(id)) landed += 1;
        }
      } while (_sweepAgain);
      return landed;
    }

    return _sweeping = sweep().whenComplete(() {
      _sweeping = null;
    });
  }

  /// A tag this device made for a note whose screen has gone (left while the fix was coming): kept, and written
  /// where it may land (`landTag`).
  void landTag(String noteId, GeoTag tag) {
    setPendingTag(noteId, tag);
    if (_watched(noteId)) {
      _tell(noteId, const TagPending());
    } else {
      unawaited(_settleClosed(noteId));
    }
  }

  // ---- tagging the notes a person makes -----------------------------------------------------------------------------

  /// Tags every note in `ids` with the fix once it comes: a note whose screen is open is handed the tag through its
  /// editor (or holds it); a closed note with words, no pass queued and no review live is written now; anything
  /// else waits as a pending tag. Answers why the fix did not come, or null (`tagNewNotes`).
  Future<LocateFailure?> tagNewNotes(List<String> ids, Future<where.Fix> fix, Waiting waiting) async {
    if (ids.isEmpty) {
      // Nobody waits for it: its failure is nobody's either.
      unawaited(fix.then<void>((_) {}, onError: (Object _) {}));
      return null;
    }
    final where.Fix position;
    try {
      position = await fix;
    } catch (failure) {
      final why = whyLocateFailed(failure);
      rememberRefusal(why);
      _settleHold(ids, false);
      return why;
    }
    forgetRefusal();
    final tag = tagOfFix(position);
    for (final id in ids) {
      setPendingTag(id, tag);
      if (_watched(id)) {
        _tell(id, const TagPending());
      } else if (!waiting.reviewing) {
        await _settleClosed(id);
      }
    }
    _settleHold(ids, true);
    return null;
  }

  /// Whether a fix here would raise the system's prompt: the person has not answered it yet (`wouldPrompt`).
  Future<bool> _wouldPrompt() async {
    final state = await locations.access();
    return state == null || state == LocationAccess.ask;
  }

  /// The system's prompt, raised from a press, where it can be asked and has never been answered: a journal's "With
  /// where you are" turned on, so its first entry is not the first ask. Answers why no fix came, or null, and null
  /// too where nothing was asked (`askFromPress`).
  Future<LocateFailure?> askFromPress() async {
    if (locations.cannotLocate != null || !await _wouldPrompt()) return null;
    try {
      await locations.locate();
      forgetRefusal();
      return null;
    } catch (failure) {
      final why = whyLocateFailed(failure);
      rememberRefusal(why);
      return why;
    }
  }

  /// The first automatic ask of this run was introduced: a person who let it pass is not asked again until the next.
  bool _introduced = false;

  /// The first ask for a journal's entries this run was introduced: its own, not the new notes'.
  bool _entryIntroduced = false;

  /// Tags new notes the person made here, when Settings says so: never under Local only, and not again after a
  /// refusal until the person allows location. `quiet` never raises a prompt (a locked phone). Where the prompt has
  /// never been answered, `introduce` says what the ask is for in the app's words and hands over the ask for a
  /// press to make, once a run. Any way this ends without a fix on its way lets a box held for these notes say none
  /// is coming (`tagNewNotesIfWanted`).
  Future<LocateFailure?> tagNewNotesIfWanted(List<String> ids, Waiting waiting, {bool quiet = false, Introduce? introduce}) async {
    final prefs = _preferences;
    if (ids.isEmpty) return null;
    if (!prefs.tagNewNotes || prefs.localOnly) return _missed(ids, null);
    final refused = await _stillRefused();
    if (refused != null) return _missed(ids, refused);
    if (!quiet && introduce != null && locations.cannotLocate == null && await _wouldPrompt()) {
      // Nothing comes unless the person allows it: a box held for these notes says so until the press holds it again.
      _missed(ids, null);
      if (_introduced) return null;
      _introduced = true;
      introduce(() => _allowFor(ids, waiting));
      return null;
    }
    return tagNewNotes(ids, locations.locate(quiet: quiet), waiting);
  }

  /// The introduction's Allow: the boxes held under the press, then the ask.
  void _allowFor(List<String> ids, Waiting waiting) {
    holdFor(ids);
    unawaited(tagNewNotes(ids, locations.locate(), waiting));
  }

  /// No fix is on its way for these notes: a box held for one says so. Answers `why`.
  LocateFailure? _missed(List<String> ids, LocateFailure? why) {
    _settleHold(ids, false);
    return why;
  }

  /// Tags a journal's new entries with where they were written, the journal's switch being the choice, and a note
  /// whose own choice is to keep its place: one made from A map at the top. [tagNewNotesIfWanted] without its check
  /// of Tag new notes, and with an introduction of its own (`tagEntryIfWanted`).
  Future<LocateFailure?> tagEntryIfWanted(List<String> ids, Waiting waiting, {bool quiet = false, Introduce? introduce}) async {
    if (ids.isEmpty) return null;
    if (_preferences.localOnly) return _missed(ids, null);
    final refused = await _stillRefused();
    if (refused != null) return _missed(ids, refused);
    if (!quiet && introduce != null && locations.cannotLocate == null && await _wouldPrompt()) {
      _missed(ids, null);
      if (_entryIntroduced) return null;
      _entryIntroduced = true;
      introduce(() => _allowFor(ids, waiting));
      return null;
    }
    return tagNewNotes(ids, locations.locate(quiet: quiet), waiting);
  }

  /// Whether a new note made now would get a fix without a prompt, so its map's box is held from its first frame:
  /// Tag new notes on, not Local only, a device that can locate, no refusal that still stands, and location allowed
  /// (`willLocate`).
  Future<bool> willLocate() async {
    final prefs = _preferences;
    if (!prefs.tagNewNotes || prefs.localOnly || locations.cannotLocate != null) return false;
    if (await _stillRefused() != null) return false;
    return _allowedNow();
  }
}
