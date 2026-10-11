/// A voice memo left in a note: a stretch of the note's own tape, written where it was spoken. Ports
/// `src/app/core/clips.ts`. It lives here, beside the editor's clips, because this piece owns no `lib/core/clips`;
/// it reaches for nothing of the editor's and can move there as it is.
///
/// Matt: "allow for voice memos to be left as a bullet point or inline audio segment". A clip is markdown, like a
/// picture is, so a note is still a plain file and nothing is lost by opening it anywhere:
/// `![voice 0:12](tape:12000-19500)` is the tape from 12.0 s to 19.5 s. On its own line after a "- " it is a
/// bullet; in the middle of a sentence it is an inline segment; and the editor draws a small player over it
/// (clips.dart).
///
/// The times are milliseconds into the note's recording. A clip also says WHICH tape it means:
/// `tape:12000-19500@k3f9x2`. A note's recording can be removed and another recorded, and the new file starts its
/// own timeline, so times alone would point at whatever sound happens to be there now. A clip plays only while the
/// note's tape still carries its id; a mark with no id is from before this and plays while the note has any
/// recording at all.
///
/// What differs: the tape ids the page kept in localStorage through module functions (`tapeId`, `setTapeId`) are
/// a [TapeIds] over a `Stored`, read plainly (the page read them through core/noteSheet.ts's `sheetOf`, which is
/// the other workspaces' sheets and is the library's to give).
library;

import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/stored.dart';

@immutable
class Clip {
  const Clip({required this.startMs, required this.endMs, this.tape});

  final int startMs;
  final int endMs;

  /// The tape this is a piece of, or null on a mark written before clips said.
  final String? tape;

  @override
  bool operator ==(Object other) => other is Clip && other.startMs == startMs && other.endMs == endMs && other.tape == tape;

  @override
  int get hashCode => Object.hash(startMs, endMs, tape);

  @override
  String toString() => 'Clip($startMs-$endMs${tape == null ? '' : '@$tape'})';
}

/// A clip, and where its mark sits in the text it was found in.
class PlacedClip extends Clip {
  const PlacedClip({required super.startMs, required super.endMs, super.tape, required this.from, required this.to});

  final int from;
  final int to;
}

/// `tape:12000-19500`, with the tape's id after an @ when it has one, inside a picture-shaped mark.
final RegExp _clip = RegExp(r'!\[([^\]]*)\]\(tape:(\d+)-(\d+)(?:@([A-Za-z0-9_-]{1,32}))?\)');
final RegExp _tapeName = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

/// "0:12", the length a person reads on the player.
String clipLength(Clip clip) {
  final seconds = max(0, ((clip.endMs - clip.startMs) / 1000).round());
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// The markdown for a clip from times as they were measured: its length as the words, so a note read anywhere
/// still says what it is. Times are rounded, and a clip never ends before it starts.
String clipMarkdown({required num startMs, required num endMs, String? tape}) {
  final from = max(0, startMs.round());
  final to = max(from, endMs.round());
  final named = tape != null && _tapeName.hasMatch(tape) ? '@$tape' : '';
  return '![voice ${clipLength(Clip(startMs: from, endMs: to))}](tape:$from-$to$named)';
}

/// The clip a mark is, or null: not a clip, or times that make no sense.
Clip? parseClip(String markdown) {
  final found = _clip.firstMatch(markdown);
  if (found == null) return null;
  final startMs = int.tryParse(found.group(2)!), endMs = int.tryParse(found.group(3)!);
  if (startMs == null || endMs == null || endMs <= startMs) return null;
  return Clip(startMs: startMs, endMs: endMs, tape: found.group(4));
}

/// Every clip in `text`, with where its mark sits, in order.
List<PlacedClip> clipsIn(String text) {
  final found = <PlacedClip>[];
  for (final match in _clip.allMatches(text)) {
    final clip = parseClip(match.group(0)!);
    if (clip != null) found.add(PlacedClip(startMs: clip.startMs, endMs: clip.endMs, tape: clip.tape, from: match.start, to: match.end));
  }
  return found;
}

/// Whether a note holds any voice memo.
bool hasClips(String text) => clipsIn(text).isNotEmpty;

/// Whether this clip is a piece of the tape the note has now: a clip that names one plays only for that tape, and
/// one from before ids plays for whatever recording the note has.
bool playsOn(Clip clip, String? tape) => clip.tape == null || clip.tape!.isEmpty || clip.tape == tape;

const String _tapesKey = 'glyph-tape-ids';

/// The tape each note holds now, kept beside the notes on this device because the audio is on this device too.
class TapeIds {
  const TapeIds(this._stored);

  final Stored _stored;

  Map<String, String> _tapes() => _stored.read<Map<String, String>>(_tapesKey, <String, String>{}, (value) {
    if (value is! Map) return null;
    return <String, String>{
      for (final entry in value.entries)
        if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
    };
  });

  /// The id of the tape `noteId` holds now, or null: the note has none, or its recording is from before ids.
  String? tapeId(String noteId) => _tapes()[noteId];

  /// Names the tape `noteId` holds now. A fresh recording takes a new id; a take appended to one keeps it.
  void setTapeId(String noteId, String? id) {
    final all = _tapes();
    if (id != null && id.isNotEmpty) {
      all[noteId] = id;
    } else {
      all.remove(noteId);
    }
    // Without storage a clip plays while the note has a recording, as one from before ids does.
    _stored.write(_tapesKey, all);
  }
}

final Random _random = Random();

/// An id for a tape starting now: short, and only ever compared with itself.
String freshTapeId() {
  const digits = '0123456789abcdefghijklmnopqrstuvwxyz';
  return <String>[for (var i = 0; i < 8; i++) digits[_random.nextInt(36)]].join();
}
