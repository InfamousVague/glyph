/// The ways into the app from the phone's home screen, its launcher and its notification shade, each a link of the
/// app's own scheme that the activity keeps until the app asks (AppLinks.kt; lib/share/app_links.dart):
///
/// | link                                | from                                                | does                        |
/// | ----------------------------------- | --------------------------------------------------- | --------------------------- |
/// | `ghostmd://new`                     | the icon's New note, a widget's pen or +, the tile  | a new note, keyboard up     |
/// | `ghostmd://voice`                   | the icon's Voice note, the Voice note widget's ring | a new note, recording       |
/// | `ghostmd://today`                   | the icon's Today's note                             | today's entry               |
/// | `ghostmd://search`                  | the icon's Search                                   | the palette, to type in     |
/// | `ghostmd://scan`                    | the icon's Scan document                            | a new note of a scan        |
/// | `ghostmd://note/<id>?line=12&find=` | a reminder, a widget's row, a recent note           | the note, at that line      |
///
/// A voice note's microphone opens only on the tap that asks for it, as the dock's does: nothing listens before.
/// `ghostmd://note/<id>` with nothing after it is the app's older note link (app_links.dart), which this leaves alone.
library;

/// One of them, read.
sealed class PhoneEntry {
  const PhoneEntry();
}

class NewNoteEntry extends PhoneEntry {
  const NewNoteEntry();
  @override
  bool operator ==(Object other) => other is NewNoteEntry;
  @override
  int get hashCode => 1;
}

class VoiceNoteEntry extends PhoneEntry {
  const VoiceNoteEntry();
  @override
  bool operator ==(Object other) => other is VoiceNoteEntry;
  @override
  int get hashCode => 2;
}

class TodayEntry extends PhoneEntry {
  const TodayEntry();
  @override
  bool operator ==(Object other) => other is TodayEntry;
  @override
  int get hashCode => 3;
}

class SearchEntry extends PhoneEntry {
  const SearchEntry();
  @override
  bool operator ==(Object other) => other is SearchEntry;
  @override
  int get hashCode => 4;
}

/// Google's document scanner, its pages kept as a new note's PDF (lib/files/plus_files.dart `scanToNewNote`).
class ScanEntry extends PhoneEntry {
  const ScanEntry();
  @override
  bool operator ==(Object other) => other is ScanEntry;
  @override
  int get hashCode => 6;
}

/// A note at a line: [line] counting from 1 (0 for none, the note where it was left), [find] the item's words, for
/// a line that has moved since.
class NoteAtEntry extends PhoneEntry {
  const NoteAtEntry(this.noteId, {this.line = 0, this.find = ''});
  final String noteId;
  final int line;
  final String find;

  @override
  bool operator ==(Object other) => other is NoteAtEntry && other.noteId == noteId && other.line == line && other.find == find;
  @override
  int get hashCode => Object.hash(noteId, line, find);
  @override
  String toString() => 'NoteAtEntry($noteId, $line, "$find")';
}

final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// What [link] asks, or null for any other link (the app's others are app_links.dart's).
PhoneEntry? readPhoneEntry(String link) {
  final Uri uri;
  try {
    uri = Uri.parse(link.trim());
  } on FormatException {
    return null;
  }
  if (uri.scheme != 'ghostmd') return null;
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  switch (uri.host) {
    case 'new' when segments.isEmpty:
      return const NewNoteEntry();
    case 'voice' when segments.isEmpty:
      return const VoiceNoteEntry();
    case 'today' when segments.isEmpty:
      return const TodayEntry();
    case 'search' when segments.isEmpty:
      return const SearchEntry();
    case 'scan' when segments.isEmpty:
      return const ScanEntry();
    // Only with a query: the bare note link stays the app's own.
    case 'note' when segments.length == 1 && _id.hasMatch(segments.first) && uri.hasQuery:
      final line = int.tryParse(uri.queryParameters['line'] ?? '') ?? 0;
      return NoteAtEntry(segments.first, line: line < 0 ? 0 : line, find: uri.queryParameters['find'] ?? '');
  }
  return null;
}

/// The link for a note at a line, as the phone's widgets, reminders and shortcuts are handed it.
String noteAtLink(String noteId, {int line = 0, String find = ''}) {
  final words = find.length > 80 ? find.substring(0, 80) : find;
  return Uri(scheme: 'ghostmd', host: 'note', path: '/$noteId', queryParameters: {'line': '$line', if (words.isNotEmpty) 'find': words}).toString();
}

/// What the app does with each.
abstract interface class PhoneEntryDoor {
  void newNote();
  void voiceNote();
  void today();
  void search();

  /// A document scanned into a new note; nothing where this device cannot scan.
  void scan();
  void openNoteAt(String noteId, int line, String find);
}

/// Hands [link] to [door] when it is one of these, and says whether it was.
bool followPhoneEntry(String link, PhoneEntryDoor door) {
  switch (readPhoneEntry(link)) {
    case NewNoteEntry():
      door.newNote();
    case VoiceNoteEntry():
      door.voiceNote();
    case TodayEntry():
      door.today();
    case SearchEntry():
      door.search();
    case ScanEntry():
      door.scan();
    case NoteAtEntry(:final noteId, :final line, :final find):
      door.openNoteAt(noteId, line, find);
    case null:
      return false;
  }
  return true;
}
