/// Sharing a note or a book by its link (docs/SHARING.md). A port of `src/app/share/share.ts`.
///
/// Anyone with the link reads it, and the server cannot; what is shared follows the owner's edits; a reader can save
/// a copy into their own Ghost.md or download it as Markdown. So a share is sealed on the device under a key made
/// for that share alone, and the key rides in the link after the `#`, which a browser never sends to a server: the
/// link is the only way in, and the service (server/src/shares.rs) keeps ciphertext it cannot open, as it does a
/// synced note. A book is shared whole - its index and every chapter that has a note. This device keeps which of its
/// notes it has shared, with each share's key, in the synced settings (`preferences.shares`), and writes a share
/// again a few seconds after any save that changed what it holds ([Shares.follow]).
///
/// Where a note was written is left out of a share unless the note's "Share where it was written" is ticked
/// ([ShareEntry.place]), and the places written in its words unless "Share the places in it" is
/// ([ShareEntry.places]): a share follows every save, so a tag added to a note shared last week would otherwise
/// publish the coordinates to everyone holding the link. The opt-in is the design; there is no rounding fallback.
///
/// What differs:
/// - The page's module state is [Shares], made with the account, the [Api], the crypto, the preferences, the notes
///   and the pictures; the pure halves ([sharedOf], [sealShare], [openShare], [withPictures], [forkShared],
///   [sharedAsFile], the links) are functions as there.
/// - **Picture bytes come through [SharePictures]**: reading one, drawing one smaller, keeping one. The page calls
///   `imageBytes`, `smallerImage(bytes, 1024, 0.72)` and `keepImage`; here whoever holds the device's pictures gives
///   the three (a `smaller` that answers the bytes as they are is a share that drops what does not fit).
/// - A share's key is taken up through [AccountCrypto.importSealKey], and sealed with `sealBytes`/`openBytes` in the
///   context `glyph/v1/share`, as the wire has it.
/// - The shares kept under the old `glyph-shares` key, from before they were synced, are the web's own history and
///   are not read: this app never kept one.
/// - [readerUrl] is the public reader page. It is only ever written into a link a person copies; nothing in this app
///   asks it for anything, so it is not one of the hosts a development build must be kept from (docs/STAGE7.md) -
///   but a share made against the fake service is a link the real page cannot open.
/// - What a download is, on the page a `Blob`, is [SharedFile]: a name, the bytes and their type.
/// - The share's digest is the page's FNV over `JSON.stringify`; `jsonEncode` writes a lone surrogate as it is where
///   the page escapes it, so a share whose pages hold one is sent once more after changing hands. Nothing else
///   differs.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../account/session.dart';
import '../core/book.dart';
import '../core/bytes.dart';
import '../core/front_matter.dart';
import '../core/note.dart';
import '../core/note_text.dart';
import '../core/preferences.dart';
import '../meet/meet_note.dart' show ghostLineStart;
import '../sync/notes.dart' show imageNames;
import 'carried.dart';
import 'share_audio.dart';
import 'zip.dart';

export 'share_audio.dart' show ShareRecording, ShareRecordings, SharedAudio, audioTooLong;

/// One page of a share.
@immutable
class SharedPage {
  const SharedPage({required this.title, required this.body});
  final String title;
  final String body;

  Map<String, Object?> toJson() => {'title': title, 'body': body};

  @override
  bool operator ==(Object other) => other is SharedPage && other.title == title && other.body == body;

  @override
  int get hashCode => Object.hash(title, body);

  @override
  String toString() => 'SharedPage($title)';
}

/// What a share holds, sealed (`Shared`). A note is one page; a book is its index first, then its chapters in order.
@immutable
class Shared {
  const Shared({required this.kind, required this.title, required this.pages, required this.at, this.pictures, this.meeting, this.note});

  /// `note` or `book`.
  final String kind;
  final String title;
  final List<SharedPage> pages;

  /// When it was written, in ms.
  final int at;

  /// The pictures its pages show, by name. Carried in the share itself: a reader has no account to fetch them from,
  /// and the server keeps the share whole or not at all.
  final Map<String, Uint8List>? pictures;

  /// A meeting's recording length, its colour, who spoke and its turns, and the recording it carries where it carries
  /// one (lib/share/share_audio.dart `sharedMeeting`): what the page draws its tape and transcript from. Null for
  /// everything but a meeting, and for a share made by an older build.
  final Map<String, Object?>? meeting;

  /// The id of the note it was made from (the book's, for a book), so the app of someone who has that note opens it
  /// rather than saving a copy ([forkFromLink]; Matt, 2026-10-29: a meeting's own link from Slack saved as "Engineering
  /// Standup (shared)" beside it). A random id, which says nothing of the note; null from a share made by an older
  /// build, and one the reader page and an older app pass over.
  final String? note;

  Shared withPictures(Map<String, Uint8List>? pictures) => Shared(kind: kind, title: title, pages: pages, at: at, pictures: pictures, meeting: meeting, note: note);

  Shared withMeeting(Map<String, Object?>? meeting) => Shared(kind: kind, title: title, pages: pages, at: at, pictures: pictures, meeting: meeting, note: note);

  /// The share's words, as they are sealed: everything but the pictures.
  Map<String, Object?> toJson() => {'v': 1, 'kind': kind, 'title': title, 'pages': [for (final page in pages) page.toJson()], 'at': at, if (meeting != null) 'meeting': meeting, if (note != null) 'note': note};

  @override
  String toString() => 'Shared($kind, $title, ${pages.length} pages, ${pictures?.length ?? 0} pictures)';
}

/// The context a share is sealed in: a synced note's ciphertext cannot be passed off as a share, nor the reverse.
const String shareContext = 'glyph/v1/share';

/// Where a reader reads: the small page (read.html), on ghostmarkdown.com (`READER_URL`). `--dart-define
/// GLYPH_READER=…` names another, as the page's `VITE_GLYPH_READER` does.
final String readerUrl = () {
  const given = String.fromEnvironment('GLYPH_READER');
  final trimmed = given.replaceFirst(RegExp(r'/+$'), '');
  return trimmed.isEmpty ? 'https://ghostmarkdown.com/read.html' : trimmed;
}();

/// Something a share could not do, in words a person can read.
class ShareError implements Exception {
  const ShareError(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---- keys, ids and links --------------------------------------------------------------------------------------------

/// A share's id: 128 random bits, base64url (`newShareId`).
String newShareId(AccountCrypto crypto) => toBase64Url(crypto.randomBytes(16));

/// A share's key: 256 random bits, base64url, carried in the link and nowhere else but this device (`newShareKey`).
String newShareKey(AccountCrypto crypto) => toBase64Url(crypto.randomBytes(32));

Future<SealKey> _keyOf(AccountCrypto crypto, String key) => crypto.importSealKey(fromBase64Url(key));

/// `GSP1`: a share with pictures, sealed, begins with these.
const List<int> _pictured = [0x47, 0x53, 0x50, 0x31];

/// The longest share the server keeps (server/src/shares.rs `SHARE_LIMIT`), in the base64url characters it counts.
const int shareLimit = 6000000;

/// What a share may hold before it is sealed and encoded: three quarters of the limit, less room for the seal
/// (`SHARE_BYTES`).
const int shareBytes = 4400000;

/// A picture's name as a note writes it: nothing a share could use to reach outside the picture store.
final RegExp _pictureName = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,127}$');

/// A share sealed under its key (`sealShare`). With pictures: `GSP1`, the length of what follows as four bytes, the
/// share's words as JSON (with each picture's name and size where the pictures were), and then the pictures' bytes
/// one after another. Pictures sealed as base64 inside the JSON would be encoded twice over, since the sealed share
/// goes to the server as base64 again, and the server's limit is on that text. A share with no pictures is its JSON
/// alone, as it always was. A published site is sealed the same way in its own [context] (lib/share/sites.dart).
Future<String> sealShare(AccountCrypto crypto, Shared shared, String key, {String context = shareContext}) async {
  final pictures = shared.pictures ?? const <String, Uint8List>{};
  final sealKey = await _keyOf(crypto, key);
  if (pictures.isEmpty) return toBase64Url(await crypto.sealBytes(sealKey, utf8.encode(jsonEncode(shared.toJson())), context));
  final head = utf8.encode(jsonEncode({
    ...shared.toJson(),
    'pictures': [
      for (final entry in pictures.entries) [entry.key, entry.value.length],
    ],
  }));
  final out = BytesBuilder(copy: false)
    ..add(_pictured)
    ..add((ByteData(4)..setUint32(0, head.length)).buffer.asUint8List())
    ..add(head);
  for (final bytes in pictures.values) {
    out.add(bytes);
  }
  return toBase64Url(await crypto.sealBytes(sealKey, out.takeBytes(), context));
}

/// A share opened with its key (`openShare`). Throws for another key, a blob that was tampered with, or a share
/// from a newer build. A published site opens the same way in its own [context].
Future<Shared> openShare(AccountCrypto crypto, String blob, String key, {String context = shareContext}) async {
  final bytes = await crypto.openBytes(await _keyOf(crypto, key), fromBase64Url(blob), context);
  Object? words;
  Map<String, Uint8List>? pictures;
  var gsp = bytes.length >= 8;
  for (var i = 0; gsp && i < _pictured.length; i += 1) {
    gsp = bytes[i] == _pictured[i];
  }
  if (gsp) {
    final length = ByteData.sublistView(bytes).getUint32(4);
    words = jsonDecode(utf8.decode(Uint8List.sublistView(bytes, 8, 8 + length)));
    pictures = {};
    var at = 8 + length;
    final listed = words is Map ? words['pictures'] : null;
    for (final each in listed is List ? listed : const <Object?>[]) {
      final name = each is List && each.isNotEmpty ? each[0] : null;
      final size = each is List && each.length > 1 ? each[1] : null;
      if (name is String && _pictureName.hasMatch(name) && size is int && size > 0 && at + size <= bytes.length) {
        pictures[name] = Uint8List.fromList(Uint8List.sublistView(bytes, at, at + size));
      }
      at += size is num ? size.toInt() : 0;
    }
  } else {
    words = jsonDecode(utf8.decode(bytes));
  }
  final pages = words is Map ? words['pages'] : null;
  if (words is! Map || words['v'] != 1 || pages is! List) throw const ShareError('This link was shared by a newer Ghost.md. Update the app to read it.');
  return Shared(
    kind: words['kind'] == 'book' ? 'book' : 'note',
    title: words['title'] is String ? words['title'] as String : '',
    pages: List.unmodifiable([
      for (final page in pages)
        if (page is Map && page['title'] is String && page['body'] is String) SharedPage(title: page['title'] as String, body: page['body'] as String),
    ]),
    at: words['at'] is num ? (words['at'] as num).toInt() : 0,
    pictures: pictures,
    meeting: words['meeting'] is Map ? (words['meeting'] as Map).cast<String, Object?>() : null,
    note: words['note'] is String && (words['note'] as String).isNotEmpty ? words['note'] as String : null,
  );
}

/// This device's pictures, as a share asks for them.
abstract interface class SharePictures {
  /// The picture by that name, or null where this device has none (`imageBytes`).
  Future<Uint8List?> read(String name);

  /// A reading copy of a picture, smaller (`smallerImage(bytes, 1024, 0.72)`).
  Future<Uint8List> smaller(Uint8List bytes);

  /// Keeps a picture under its own name: a saved copy's (`keepImage`).
  Future<void> keep(String name, Uint8List bytes);
}

/// [shared] with the pictures its pages show, read from this device, as many as the share can hold (`withPictures`):
/// as they are kept if they fit, else each drawn smaller, else as many as fit in the order the pages show them. A
/// picture this device does not have is left out, and the reader sees it missing, as the owner's other devices
/// would; those are answered as `lacked`, so the share is sent again when one arrives ([Shares.refreshShares]).
Future<({Shared shared, List<String> lacked})> withPictures(Shared shared, SharePictures deps, {int budget = shareBytes}) async {
  final names = <String>{
    for (final page in shared.pages) ...imageNames(page.body),
  };
  if (names.isEmpty) return (shared: shared, lacked: const <String>[]);
  var found = <(String, Uint8List)>[];
  final lacked = <String>[];
  for (final name in names) {
    Uint8List? bytes;
    try {
      bytes = await deps.read(name);
    } catch (_) {
      bytes = null;
    }
    if (bytes != null && bytes.isNotEmpty) {
      found.add((name, bytes));
    } else {
      lacked.add(name);
    }
  }
  final room = budget - utf8.encode(jsonEncode(shared.toJson())).length;
  int size(List<(String, Uint8List)> list) => list.fold(0, (sum, each) => sum + each.$2.length);
  if (size(found) > room) {
    // Too much to carry as kept: a reading copy of each, smaller.
    final smaller = <(String, Uint8List)>[];
    for (final (name, bytes) in found) {
      Uint8List drawn;
      try {
        drawn = await deps.smaller(bytes);
      } catch (_) {
        drawn = bytes;
      }
      smaller.add((name, drawn));
    }
    found = smaller;
  }
  final pictures = <String, Uint8List>{};
  var used = 0;
  for (final (name, bytes) in found) {
    if (used + bytes.length > room) continue;
    pictures[name] = bytes;
    used += bytes.length;
  }
  return (shared: pictures.isNotEmpty ? shared.withPictures(pictures) : shared, lacked: lacked);
}

/// Sealed for the server, or a refusal a person can read when even the words are more than a share holds.
Future<String> _sealForServer(AccountCrypto crypto, Shared shared, String key) async {
  final blob = await sealShare(crypto, shared, key);
  if (blob.length > shareLimit) throw const ShareError('That is more than a share can hold, even with its pictures drawn smaller. Share a page, or fewer of them.');
  return blob;
}

/// The link a reader opens: the reader page, and after the `#` the share's id and key (`shareLink`).
String shareLink(String id, String key) => '$readerUrl#$id.$key';

final RegExp _linked = RegExp(r'([A-Za-z0-9_-]{22,64})\.([A-Za-z0-9_-]{43})(?![A-Za-z0-9_-])');

/// A share's id and key out of a link, or out of what follows its `#`; null when it holds none (`readShareLink`).
({String id, String key})? readShareLink(String text) {
  final at = text.indexOf('#');
  final hash = at >= 0 ? text.substring(at + 1) : text;
  final found = _linked.firstMatch(hash.trim());
  return found != null ? (id: found.group(1)!, key: found.group(2)!) : null;
}

// ---- what a note or a book shares -----------------------------------------------------------------------------------

String _titleOf(String body) {
  final title = noteTitle(body);
  return title.isEmpty ? 'Untitled' : title;
}

/// What [note] shares: itself, or a book's index and every chapter that has a note, found among [notes]
/// (`sharedOf`). Where each page was written stays out unless [place] says to carry it, and the places written in
/// the words unless [places] does (see the header). [at] is when, the clock's unless given.
Shared sharedOf(Note note, List<Note> notes, {bool place = false, bool places = false, int? at}) {
  String carried(String body) {
    final tagged = place ? body : withoutGeoTag(body);
    return places ? tagged : withoutPlaces(tagged);
  }

  final when = at ?? DateTime.now().millisecondsSinceEpoch;
  final title = _titleOf(note.body);
  if (!isBookBody(note.body)) return Shared(kind: 'note', title: title, pages: [SharedPage(title: title, body: carried(note.body))], at: when, note: note.id);
  final pages = [SharedPage(title: title, body: carried(note.body))];
  for (final chapter in chaptersOf(note.body)) {
    Note? found;
    for (final n in notes) {
      if (n.id != note.id && sameTitle(noteTitle(n.body), chapter.title)) {
        found = n;
        break;
      }
    }
    if (found != null && !pages.any((p) => sameTitle(p.title, chapter.title))) pages.add(SharedPage(title: chapter.title, body: carried(found.body)));
  }
  return Shared(kind: 'book', title: title, pages: pages, at: when, note: note.id);
}

/// Whether the pages [note] would share say where any of them was written, for the sheet to offer the choice
/// (`sharesPlace`).
bool sharesPlace(Note note, List<Note> notes) => sharedOf(note, notes, place: true, places: true).pages.any((page) => page.body != withoutGeoTag(page.body));

/// Whether the pages [note] would share hold a place in their words, in any chapter, for the sheet to offer its own
/// choice (`sharesPlaces`).
bool sharesPlaces(Note note, List<Note> notes) => sharedOf(note, notes, place: true, places: true).pages.any((page) => hasPlaces(page.body));

/// A short digest of what a share holds, pages only: when it was written does not make it different (`digest`).
String shareDigest(Shared shared) {
  // "p2": pictures travel with a share, and a share remembers which it lacked. A share sent before either reads as
  // changed, so it is sent again, with them and with that list. A meeting's turns and the recording it names are
  // what it holds too; anything else digests as it did, so it is not sent again for them. A meeting's note's id too
  // ([Shared.note]): its share went to the team's Slack channel, and is sent again once carrying it, so a member's app
  // opens the team's meeting from it rather than saving a copy (Matt, 2026-10-29). Any other share takes it on at its
  // next change.
  final text = jsonEncode(['p2', shared.kind, shared.title, [for (final page in shared.pages) page.toJson()], if (shared.meeting != null) shared.meeting, if (shared.meeting != null && shared.note != null) shared.note]);
  var h = 2166136261;
  for (var i = 0; i < text.length; i += 1) {
    h = ((h ^ text.codeUnitAt(i)) * 16777619) & 0xffffffff;
  }
  return '${text.length}:${h.toRadixString(36)}';
}

// ---- the account's shares -------------------------------------------------------------------------------------------

/// After a save, the shares follow: a few seconds' quiet, then every share that changed is written again
/// (`FOLLOW_MS`).
const Duration followWait = Duration(milliseconds: 3000);

/// The account's shares on this device: which notes are shared, each share's link, and the writing of them.
/// Tells its listeners whenever a note starts or stops being shared, here or (by the synced settings) on another
/// device (`onShares`).
class Shares extends ChangeNotifier {
  /// [listNotes] reads this device's notes (`listNotes`); [prefs] is where the shares are kept.
  /// [recordings] reads this device's meeting recordings, for a share that carries one (lib/share/share_audio.dart);
  /// without it no share carries a recording, though one sent from another device is still named.
  Shares({required this.account, required this.api, required this.crypto, required this.prefs, required this.pictures, required this.listNotes, this.recordings}) {
    prefs.addListener(notifyListeners);
  }

  final AccountSource account;
  final Api api;
  final AccountCrypto crypto;
  final PreferencesStore prefs;
  final SharePictures pictures;
  final Future<List<Note>> Function() listNotes;
  final ShareRecordings? recordings;

  /// The recordings being sent, by note id, with how much of each has gone (0 to 1).
  final ValueNotifier<Map<String, double>> audioSending = ValueNotifier(const {});

  /// Why a note's recording did not go with its share, by note id, until it goes.
  final Map<String, String> _audioProblems = {};

  /// Why [noteId]'s recording did not go with its share, or null.
  String? audioProblem(String noteId) => _audioProblems[noteId];

  /// Whether [note] is a meeting: one recorded as a meeting here or on another of the account's devices, or one Ghost
  /// was in. Its share carries its turns, and its recording where it has one ([sharingRecording]).
  bool isMeeting(Note note) => prefs.value.meetings.containsKey(note.id) || note.body.contains(ghostLineStart);

  Map<String, ShareEntry> _readKept() => {...prefs.value.shares};

  void _writeKept(Map<String, ShareEntry> kept) {
    // The preferences tell this one's listeners, as they do for a share made on another device.
    prefs.update((now) => now.copyWith(shares: Map.unmodifiable(kept)));
  }

  String _token() {
    final session = account.session;
    if (session == null) throw const ShareError('Sign in under Settings > Account to share: a share is kept with your account.');
    return session.token;
  }

  /// Every note shared by a link, by note id, with its link: the settings' list of shares (`sharedLinks`).
  List<({String noteId, String link, String id})> sharedLinks() => [
        for (final entry in _readKept().entries) (noteId: entry.key, id: entry.value.id, link: shareLink(entry.value.id, entry.value.key)),
      ];

  /// Every share the account holds on the server, those no device lists any more included, with when each was
  /// written, in seconds (`sharesOnServer`).
  Future<List<({String id, int updated})>> sharesOnServer() async {
    final answer = await api.callMap('GET', 'shares', token: _token());
    final shares = answer['shares'];
    return [
      if (shares is List)
        for (final each in shares)
          if (each is Map && each['id'] is String) (id: each['id'] as String, updated: each['updated'] is num ? (each['updated'] as num).toInt() : 0),
    ];
  }

  /// Takes down a share by its id alone: one the settings lost track of, so it has no note to stop it from
  /// (`takeDownShare`).
  Future<void> takeDownShare(String id) async {
    await api.call('DELETE', 'shares/$id', token: _token());
  }

  /// The note this account shared under the share [shareId], here or on another of its devices (the settings keep
  /// every share by its note), or null for a share that is not the account's own.
  String? noteOfShare(String shareId) {
    for (final entry in _readKept().entries) {
      if (entry.value.id == shareId) return entry.key;
    }
    return null;
  }

  /// The link for a shared note, or null (`linkFor`).
  String? linkFor(String noteId) {
    final kept = _readKept()[noteId];
    return kept != null ? shareLink(kept.id, kept.key) : null;
  }

  /// Records that [noteId]'s share went as [sent], lacking [lacked], on the entry as it is NOW: a recording sent
  /// meanwhile, or a switch turned, is kept, where writing back the entries read before the share went would lose it.
  void _markSent(String noteId, String sent, List<String> lacked) {
    final all = _readKept();
    final kept = all[noteId];
    if (kept == null) return;
    all[noteId] = kept.copyWith(sent: sent, lacked: () => lacked.isEmpty ? null : List.unmodifiable(lacked));
    _writeKept(all);
  }

  /// What [note]'s share holds: its pages, and a meeting's turns and the recording it names.
  Shared _sharedOf(Note note, List<Note> notes, ShareEntry kept) {
    final shared = sharedOf(note, notes, place: kept.place, places: kept.places);
    if (shared.kind != 'note' || !isMeeting(note)) return shared;
    final audio = kept.recording ? SharedAudio.fromJson(kept.audio) : null;
    return shared.withMeeting(sharedMeeting(note, at: prefs.value.meetings[note.id]?.toInt() ?? note.createdAt, audio: audio));
  }

  /// Shares [note] (and, for a book, its chapters among [notes]), or writes its share again; answers the link
  /// (`shareNote`). A meeting's share made here carries its recording unless [recording] is false (the sheet's
  /// "Include the recording"): the words go first, and the link with them, and the recording follows on its own,
  /// [audioSending] saying how far it is.
  Future<String> shareNote(Note note, List<Note> notes, {bool? recording}) async {
    final auth = _token();
    final made = _readKept()[note.id] ?? ShareEntry(id: newShareId(crypto), key: newShareKey(crypto));
    final kept = recording == null || recording == made.recording ? made : made.copyWith(recording: recording);
    final shared = _sharedOf(note, notes, kept);
    final carried = await withPictures(shared, pictures);
    await api.call('PUT', 'shares/${kept.id}', token: auth, body: {'blob': await _sealForServer(crypto, carried.shared, kept.key)});
    final all = _readKept();
    all[note.id] = (all[note.id] ?? kept).copyWith(recording: kept.recording, sent: shareDigest(shared), lacked: () => carried.lacked.isEmpty ? null : List.unmodifiable(carried.lacked));
    _writeKept(all);
    _sendAudioSoon(note);
    return shareLink(kept.id, kept.key);
  }

  /// Whether [noteId]'s share carries where it was written (`sharingPlace`).
  bool sharingPlace(String noteId) => _readKept()[noteId]?.place ?? false;

  /// Sets whether [noteId]'s share carries where it was written, and sends the share again as it now reads
  /// (`shareWithPlace`).
  Future<void> shareWithPlace(String noteId, {required bool on}) async {
    final all = _readKept();
    final kept = all[noteId];
    if (kept == null) return;
    all[noteId] = kept.copyWith(place: on);
    _writeKept(all);
    await refreshShares();
  }

  /// Whether [noteId]'s share carries the places written in its words (`sharingPlaces`).
  bool sharingPlaces(String noteId) => _readKept()[noteId]?.places ?? false;

  /// Sets whether [noteId]'s share carries the places written in its words, and sends the share again as it now
  /// reads (`shareWithPlaces`).
  Future<void> shareWithPlaces(String noteId, {required bool on}) async {
    final all = _readKept();
    final kept = all[noteId];
    if (kept == null) return;
    all[noteId] = kept.copyWith(places: on);
    _writeKept(all);
    await refreshShares();
  }

  // ---- a meeting's recording ---------------------------------------------------------------------------------------

  /// Whether [noteId]'s share carries its meeting's recording: on unless turned off.
  bool sharingRecording(String noteId) => _readKept()[noteId]?.recording ?? true;

  /// Whether [noteId]'s share has a recording on the service, sent from this device or another.
  bool recordingSent(String noteId) {
    final kept = _readKept()[noteId];
    return kept != null && kept.recording && SharedAudio.fromJson(kept.audio) != null;
  }

  /// Where [note]'s recording is for its share: here to send ([ShareRecording]), or null where this device has none.
  Future<ShareRecording?> recordingHere(Note note) async {
    final from = recordings;
    if (from == null || (note.recordingMs ?? 0) <= 0) return null;
    try {
      return await from.recordingOf(note.id);
    } catch (_) {
      return null;
    }
  }

  /// Sets whether [noteId]'s share carries its recording. Off, the recording is taken down from the service and the
  /// share written again without it; on, it is sent from here where this device has it.
  Future<void> shareWithRecording(String noteId, {required bool on}) async {
    final all = _readKept();
    final kept = all[noteId];
    if (kept == null) return;
    all[noteId] = kept.copyWith(recording: on, audio: on ? null : () => null);
    _writeKept(all);
    _audioProblems.remove(noteId);
    if (!on) await api.call('DELETE', 'shares/${kept.id}/audio', token: _token());
    await refreshShares();
  }

  final Map<String, Future<void>> _audioRuns = {};

  /// Sends [note]'s recording with its share, once, where it wants one this device has and has not sent as it is now
  /// (lib/share/share_audio.dart says when that is). Nothing is waited for: [audioSending] says how far it is, and
  /// the share is written again naming it once it is all there.
  void _sendAudioSoon(Note note) {
    if (_audioRuns.containsKey(note.id)) return;
    final run = _sendAudio(note).catchError((Object failure) {
      _audioProblems[note.id] = 'The recording didn’t go: $failure It is tried again after the next save.';
      notifyListeners();
    }).whenComplete(() {
      _audioRuns.remove(note.id);
      audioSending.value = {...audioSending.value}..remove(note.id);
    });
    _audioRuns[note.id] = run;
  }

  /// The run [_sendAudioSoon] starts, for the tests to wait on.
  @visibleForTesting
  Future<void> audioSent(String noteId) => _audioRuns[noteId] ?? Future<void>.value();

  Future<void> _sendAudio(Note note) async {
    final first = _readKept()[note.id];
    if (first == null || !first.recording || !isMeeting(note) || account.session == null) return;
    final recording = await recordingHere(note);
    if (recording == null) return;
    final digest = recordingDigest(recording.bytes, note.recordingMs);
    if (SharedAudio.fromJson(first.audio)?.sent == digest) return;
    if (!audioFits(recording.bytes)) {
      _audioProblems[note.id] = audioTooLong;
      notifyListeners();
      return;
    }
    _audioProblems.remove(note.id);
    audioSending.value = {...audioSending.value, note.id: 0};
    bool wanted() {
      final now = _readKept()[note.id];
      return now != null && now.id == first.id && now.recording;
    }

    final sent = await sendShareAudio(
      api: api,
      token: _token(),
      crypto: crypto,
      shareId: first.id,
      key: first.key,
      recording: recording,
      ms: note.recordingMs ?? 0,
      wanted: wanted,
      progress: (done) => audioSending.value = {...audioSending.value, note.id: done},
    );
    if (sent == null || !wanted()) return;
    final all = _readKept();
    all[note.id] = all[note.id]!.copyWith(audio: () => sent.toJson());
    _writeKept(all);
    // The words again, naming the recording: its descriptor is in what the share holds, so the digest moved.
    await refreshShares();
  }

  /// Whether a picture a share lacked when it was sent is on this device now. Only those names are looked for.
  Future<bool> _lackedArrived(ShareEntry kept) async {
    for (final name in kept.lacked ?? const <String>[]) {
      try {
        final bytes = await pictures.read(name);
        if (bytes != null && bytes.isNotEmpty) return true;
      } catch (_) {
        // Not readable: not here.
      }
    }
    return false;
  }

  /// Stops sharing [noteId]: the share is taken down and its link reads nothing from then on (`stopSharing`). The
  /// service takes a meeting's recording down with it, and a recording still being sent stops at its next part.
  Future<void> stopSharing(String noteId) async {
    final all = _readKept();
    final kept = all[noteId];
    if (kept == null) return;
    await api.call('DELETE', 'shares/${kept.id}', token: _token());
    all.remove(noteId);
    _writeKept(all);
  }

  /// Writes again every share whose note, or whose book's chapters, changed since it was last sent
  /// (`refreshShares`). Answers how many went.
  Future<int> refreshShares() async {
    final all = _readKept();
    if (all.isEmpty || account.session == null) return 0;
    final notes = await listNotes();
    var sent = 0;
    for (final id in all.keys.toList()) {
      Note? note;
      for (final n in notes) {
        if (n.id == id) {
          note = n;
          break;
        }
      }
      final kept = all[id];
      if (note == null || kept == null) continue;
      // A meeting's recording, where this device has one the share has not had as it is now: on its own, after.
      if (kept.recording && isMeeting(note)) _sendAudioSoon(note);
      final shared = _sharedOf(note, notes, kept);
      // The pages as they were, and every picture they show either sent or still not here: nothing to send.
      if (shareDigest(shared) == kept.sent && !await _lackedArrived(kept)) continue;
      try {
        final carried = await withPictures(shared, pictures);
        await api.call('PUT', 'shares/${kept.id}', token: _token(), body: {'blob': await _sealForServer(crypto, carried.shared, kept.key)});
        _markSent(id, shareDigest(shared), carried.lacked);
        sent += 1;
      } on Exception {
        // Offline, or signed out: the next save tries again.
      }
    }
    return sent;
  }

  Timer? _timer;
  final List<VoidCallback> _unfollow = [];

  void _soon() {
    if (_readKept().isEmpty) return;
    _timer?.cancel();
    _timer = Timer(followWait, () => unawaited(refreshShares().then<void>((_) {}, onError: (Object _) {})));
  }

  /// After a save, the shares follow (`followShares`): [saved] is told when a note is saved here
  /// (`CoreLibrary.touched`, the page's `NOTE_SAVED`) and [changed] when notes changed by sync (the library itself,
  /// the page's `NOTES_CHANGED`) - a chapter edited on the Mac reaches a book's share from the phone too. And once
  /// at launch, once the app has settled: a share whose notes changed on another device goes out as it is now.
  /// Asked twice, it follows once.
  void follow({required Listenable saved, Listenable? changed}) {
    if (_unfollow.isNotEmpty) return;
    for (final source in [saved, ?changed]) {
      source.addListener(_soon);
      _unfollow.add(() => source.removeListener(_soon));
    }
    if (_readKept().isNotEmpty) _timer = Timer(followWait * 4, () => unawaited(refreshShares().then<void>((_) {}, onError: (Object _) {})));
  }

  // ---- reading -------------------------------------------------------------------------------------------------------

  /// What a link shares, read and opened: anyone with the link can, with no account (`readShared`).
  Future<Shared> readShared(String link) async {
    final found = readShareLink(link);
    if (found == null) throw const ShareError('That is not a Ghost.md share link.');
    final answer = await api.callMap('GET', 'shares/${found.id}');
    final blob = answer['blob'];
    if (blob is! String) throw const ShareError('That link reads nothing: the share was taken down.');
    return openShare(crypto, blob, found.key);
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final stop in _unfollow) {
      stop();
    }
    _unfollow.clear();
    prefs.removeListener(notifyListeners);
    audioSending.dispose();
    super.dispose();
  }
}

// ---- forking --------------------------------------------------------------------------------------------------------

final RegExp _headingLine = RegExp(r'^#\s');
final RegExp _headingLead = RegExp(r'^#\s+');

/// A page's body under a new title: its front matter's title if it has one, else its first heading (`retitled`).
String _retitled(String body, String from, String to) {
  if (frontMatterValue(body, 'title') != null) return withFrontMatterTitle(body, to);
  final lines = body.split('\n');
  final at = lines.indexWhere(_headingLine.hasMatch);
  if (at >= 0 && sameTitle(lines[at].replaceFirst(_headingLead, ''), from)) {
    lines[at] = '# $to';
  } else {
    lines.insertAll(0, ['# $to', '']);
  }
  return lines.join('\n');
}

/// Saves a copy of what was shared into this library, as the reader's own notes: a note, or a book with its chapters
/// (`forkShared`). A page whose title a note here already has is saved as "Title (shared)", and a book's index points
/// at the copies, so a fork never mixes with what the reader already wrote. Answers the note to open: the note, or
/// the book.
///
/// [notes] lists this library's notes, [save] makes one with those words (`createNote(newNoteId(), body,
/// 'editor')`), and [keep] keeps a picture under its own name ([SharePictures.keep]); without one the pictures are
/// not kept.
Future<Note> forkShared(
  Shared shared, {
  required Future<List<Note>> Function() notes,
  required Future<Note> Function(String body) save,
  Future<void> Function(String name, Uint8List bytes)? keep,
}) async {
  // The pictures first, under their own names, so the pages draw them as they open; sync sends them on from here.
  if (keep != null) {
    for (final entry in (shared.pictures ?? const <String, Uint8List>{}).entries) {
      try {
        await keep(entry.key, entry.value);
      } catch (failure) {
        debugPrint('[glyph] a shared picture was not kept: $failure');
      }
    }
  }
  final have = [for (final n in await notes()) noteTitle(n.body)];
  bool taken(String t) => have.any((h) => sameTitle(h, t));
  final names = <String, String>{};
  for (final page in shared.pages) {
    var name = page.title;
    for (var n = 1; taken(name) || names.values.any((v) => sameTitle(v, name)); n += 1) {
      name = n == 1 ? '${page.title} (shared)' : '${page.title} (shared $n)';
    }
    names[page.title] = name;
  }
  Note? first;
  for (final (i, page) in shared.pages.indexed) {
    var body = page.body;
    final name = names[page.title]!;
    if (name != page.title) body = _retitled(body, page.title, name);
    // The book's index points at the copies it was saved with.
    if (shared.kind == 'book' && i == 0) {
      for (final MapEntry(key: from, value: to) in names.entries) {
        if (from != to && from != page.title) body = body.split('[[$from]]').join('[[$to]]');
      }
    }
    final saved = await save(body);
    first ??= saved;
  }
  if (first == null) throw const ShareError('That share holds nothing to save.');
  return first;
}

final RegExp _unholdable = RegExp(r'[\\/:*?"<>|\n]');
final RegExp _spaces = RegExp(r'\s+');

/// A file name from a title: what a file system takes, never empty.
String _fileName(String title) {
  final clean = title.replaceAll(_unholdable, ' ').replaceAll(_spaces, ' ').trim();
  final cut = clean.length > 120 ? clean.substring(0, 120) : clean;
  return cut.isEmpty ? 'Untitled' : cut;
}

/// A download: its name, its bytes, and what they are.
class SharedFile {
  const SharedFile({required this.name, required this.bytes, required this.type});
  final String name;
  final Uint8List bytes;

  /// `text/markdown` or `application/zip`.
  final String type;
}

/// What was shared, as files for any Markdown app: one `.md` for a note, a `.zip` of every page for a book
/// (`sharedAsFile`).
SharedFile sharedAsFile(Shared shared, {DateTime? dated}) {
  // The pictures beside the pages in an `image/` folder, which is where the pages' `image/<name>` links point.
  final pictures = [
    for (final entry in (shared.pictures ?? const <String, Uint8List>{}).entries) ZipFile(name: 'image/${entry.key}', bytes: entry.value),
  ];
  if ((shared.kind == 'note' || shared.pages.length == 1) && pictures.isEmpty) {
    final page = shared.pages.first;
    return SharedFile(name: '${_fileName(page.title)}.md', bytes: utf8.encode(page.body), type: 'text/markdown');
  }
  final files = [
    for (final page in shared.pages) ZipFile(name: '${_fileName(page.title)}.md', bytes: utf8.encode(page.body)),
    ...pictures,
  ];
  return SharedFile(name: '${_fileName(shared.title)}.zip', bytes: zipFiles(files, dated), type: 'application/zip');
}
