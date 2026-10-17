/// Which places the phone is to watch, decided from the notes: pure, so every case is a test
/// (test/reminders/place_plan_test.dart). The app is the source of truth: after any change to the notes (a sync's
/// included) the whole set is worked out again and handed over (place_scheduler.dart), and the phone keeps only that.
///
/// - Each open to-do with a `📍` (place_syntax.dart) is a geofence of [placeRadius] metres around its place. A ticked
///   or cancelled one is not, nor one with a done day on it; a list item with no box is not either, since a place on
///   a plain line is a place, not a task.
/// - Nothing in the Trash, the archive, a template, or a note this phone cannot read as words (a canvas). Fenced
///   code and front matter are passed over.
/// - At most [mostPlaces] at once (Google Play services holds a hundred geofences for an app): where there are more,
///   the nearest to where the phone last was, and where it has never said, the first as the notes have them.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/front_matter.dart' show frontMatterEnd;
import '../core/item_syntax.dart' show lineWords, listLead;
import '../core/note.dart';
import '../core/note_facts.dart';
import '../core/place_refs.dart' show jsNumber;
import '../core/task_fields.dart' show fieldsOf, withoutFields;
import 'place_syntax.dart';
import 'reminder_plan.dart' show stableId;

/// How many places the phone is handed at once: Play services' own limit for an app.
const int mostPlaces = 100;

/// How near the place a phone must come for its to-do to remind, in metres.
const double placeRadius = 150;

/// One open to-do with a place, as the phone is handed it.
@immutable
class PlaceReminder {
  const PlaceReminder({required this.id, required this.mark, required this.noteId, required this.line, required this.words, required this.note, this.radius = placeRadius});

  /// The same for the same item at the same place, from one pass to the next and one run to the next: what the
  /// phone knows a geofence by.
  final String id;
  final PlaceMark mark;
  final double radius;
  final String noteId;

  /// The item's line, counting from 1.
  final int line;

  /// What the item says, its lead and its fields taken off: "Buy diapers". Done finds the item by these.
  final String words;

  /// The note's title.
  final String note;

  /// What the place is called.
  String get place => mark.name;

  /// The notification's title: "Buy diapers — you're at Target".
  String get title => '${words.isEmpty ? 'A to-do' : words} — you’re at $place';

  /// The line under it: the note.
  String get text => note.isEmpty ? 'Untitled' : note;

  Map<String, Object?> toJson() => {
    'id': id,
    'lat': mark.lat,
    'lon': mark.lon,
    'radius': radius,
    'title': title,
    'text': text,
    'place': place,
    'noteId': noteId,
    'line': line,
    'words': words,
  };

  @override
  bool operator ==(Object other) =>
      other is PlaceReminder && other.id == id && other.mark == mark && other.radius == radius && other.noteId == noteId && other.line == line && other.words == words && other.note == note;

  @override
  int get hashCode => Object.hash(id, mark, radius, noteId, line, words, note);

  @override
  String toString() => 'PlaceReminder("$words" at ${mark.link} in $noteId:$line)';
}

/// Fenced code's opening and closing line.
final RegExp _fence = RegExp(r'^\s*(```|~~~)');

/// The open to-dos with a place in [note], in the order they are written. Pure; [PlacedItems.of] keeps each note's.
List<PlaceReminder> placeRemindersIn(Note note, [NoteFacts? read]) {
  final body = note.body;
  if (!mayPlace(body)) return const [];
  final facts = read ?? NoteFacts.read(body);
  if (facts.isCanvas || facts.isTemplatePage || facts.isTemplatesBook) return const [];
  final out = <PlaceReminder>[];
  final lines = body.split('\n');
  var fenced = false;
  for (var index = frontMatterEnd(lines); index < lines.length; index += 1) {
    final text = lines[index];
    if (_fence.hasMatch(text)) {
      fenced = !fenced;
      continue;
    }
    if (fenced || !mayPlace(text)) continue;
    final lead = listLead(text);
    // A to-do still to do: its box, empty.
    if (lead == null || lead.done != false) continue;
    final mark = placeOn(text);
    if (mark == null) continue;
    final fields = fieldsOf(text);
    if (fields.done != null || fields.cancelled != null) continue;
    final words = withoutFields(lineWords(text));
    out.add(
      PlaceReminder(
        id: stableId('place\u0000${note.id}\u0000$words\u0000${jsNumber(mark.lat)},${jsNumber(mark.lon)}'),
        mark: mark,
        noteId: note.id,
        line: index + 1,
        words: words,
        note: facts.title,
      ),
    );
  }
  return out;
}

/// Each note's places, kept by the note object, which the library keeps the same while the note is.
class PlacedItems {
  PlacedItems._();

  static final Expando<List<PlaceReminder>> _kept = Expando<List<PlaceReminder>>('placedItems');

  /// [note]'s open to-dos with a place, read the first time it is asked for this object.
  static List<PlaceReminder> of(Note note) => _kept[note] ??= List<PlaceReminder>.unmodifiable(placeRemindersIn(note, NoteFacts.of(note)));
}

/// Where the phone was, in degrees.
typedef LatLon = ({double lat, double lon});

/// The distance between two places over the Earth's surface, in metres (haversine, on a sphere of the mean radius).
double metresBetween(double lat1, double lon1, double lat2, double lon2) {
  const earth = 6371008.8;
  double rad(double degrees) => degrees * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * earth * math.asin(math.min(1, math.sqrt(a)));
}

/// The most [most] of [all]: every one where there are no more than that; else the nearest to [near], the nearer
/// of two as far first by id, and where [near] is not known, the first [most] as they came.
List<PlaceReminder> nearestPlaces(List<PlaceReminder> all, {LatLon? near, int most = mostPlaces}) {
  if (all.length <= most) return all;
  if (near == null) return all.sublist(0, most);
  final far = {for (final place in all) place.id: metresBetween(near.lat, near.lon, place.mark.lat, place.mark.lon)};
  final sorted = [...all]..sort((a, b) {
    final by = far[a.id]!.compareTo(far[b.id]!);
    return by != 0 ? by : a.id.compareTo(b.id);
  });
  return sorted.sublist(0, most);
}

/// Every open to-do with a place in [notes], less what [skip] says to leave out (the Trash) and the archive: once
/// each by id, in the order the notes have them.
List<PlaceReminder> placesIn(List<Note> notes, {bool Function(Note note)? skip}) {
  final ids = <String>{};
  final out = <PlaceReminder>[];
  for (final note in notes) {
    if ((note.archivedAt ?? 0) != 0 || (skip?.call(note) ?? false)) continue;
    for (final place in PlacedItems.of(note)) {
      // The same item twice on a line written twice is one geofence.
      if (ids.add(place.id)) out.add(place);
    }
  }
  return out;
}

/// The set as the phone is handed it, and as two passes are compared.
String placesJson(List<PlaceReminder> places) => jsonEncode([for (final place in places) place.toJson()]);
