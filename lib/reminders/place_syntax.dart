/// A place reminder as a line writes it: `📍` and a place's link, after the item's words and before the run of
/// Obsidian Tasks' fields, where a reminder's `⏰` goes (docs/INTEGRATIONS.md §3, "Place reminders").
///
///     - [ ] Buy diapers 📍 [Target](geo:35.7002,-81.3084)
///
/// The link is the one a place line is written with (lib/core/place_refs.dart `placeMarkdown`): the place's name as
/// its words, or the coordinates where no name came, and a `geo:` address (RFC 5870) at four decimals, or two for a
/// rough fix. So another app shows a pin and a link that opens its maps. The grammar is lib/core/task_fields.dart's
/// (the `place` key, one of Tasks' others): a board's card and a title sent elsewhere leave it out as they leave out a
/// date, and an item's words, by which Done finds it again (tick_item.dart), are the same with a place or without.
///
/// What arriving there does is the phone's: a geofence for each open to-do with a place (place_plan.dart, and
/// android/…/ghost_md/reminders/Places.kt).
library;

import 'package:flutter/foundation.dart';

import '../core/place_refs.dart' show GeoTag, cleanPlaceName, placeMarkdown, placeOfLine, tagLabel;
import '../core/task_fields.dart' show FieldKind, fieldsIn, withWrittenField;

/// The sign a line writes a place reminder with.
const String placeSign = '📍';

/// A place to be reminded at: where it is, and what it is called.
@immutable
class PlaceMark {
  const PlaceMark(this.tag);

  /// A place by its name and coordinates, at four decimals unless [rough].
  factory PlaceMark.at(double lat, double lon, {String? name, bool rough = false}) {
    final clean = cleanPlaceName(name ?? '');
    return PlaceMark(GeoTag(lat: lat, lon: lon, place: clean.isEmpty ? null : clean, rough: rough));
  }

  /// The place as a tag: its `place` is the name, or null where the link's words are only the coordinates.
  final GeoTag tag;

  double get lat => tag.lat;
  double get lon => tag.lon;

  /// What the chip and the notification call it: the name, or the coordinates as a person reads them.
  String get name => tagLabel(tag);

  /// `[Target](geo:35.7002,-81.3084)`.
  String get link => placeMarkdown(tag, tag.place);

  /// `📍 [Target](geo:35.7002,-81.3084)`, as a line writes it.
  String get written => '$placeSign $link';

  /// The same place, at the coordinates as written: what two marks are compared by.
  @override
  bool operator ==(Object other) => other is PlaceMark && other.link == link;

  @override
  int get hashCode => link.hashCode;

  @override
  String toString() => 'PlaceMark($link)';
}

/// A place's link read (`[Target](geo:35.7002,-81.3084)`), or null for one that is not a place on Earth.
PlaceMark? readPlaceMark(String? link) {
  final place = placeOfLine(link ?? '');
  return place == null ? null : PlaceMark(place.tag);
}

/// Whether [line] could hold a place reminder, asked before it is read: the sign is there.
bool mayPlace(String line) => line.contains(placeSign);

/// The place [line] reminds at, the first where it has two, or null.
PlaceMark? placeOn(String line) {
  if (!mayPlace(line)) return null;
  for (final span in fieldsIn(line)) {
    if (span.kind == FieldKind.tasks && span.key == 'place') {
      final mark = readPlaceMark(span.value);
      if (mark != null) return mark;
    }
  }
  return null;
}

/// [line] with its place set to [mark], or taken off with null: one `📍`, before Tasks' fields.
String withPlace(String line, PlaceMark? mark) => withWrittenField(line, 'place', mark?.written);
