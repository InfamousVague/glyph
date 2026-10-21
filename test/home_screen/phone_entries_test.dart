import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/home_screen/phone_entries.dart';
import 'package:ghost_md/share/app_links.dart';

/// The ways into the app from the home screen, the icon's shortcuts and the tile (lib/home_screen/phone_entries.dart):
/// each a link of the app's own scheme, read, and handed to the door that does it.

class Door implements PhoneEntryDoor {
  final List<String> did = [];

  @override
  void newNote() => did.add('new');

  @override
  void voiceNote() => did.add('voice');

  @override
  void today() => did.add('today');

  @override
  void search() => did.add('search');

  @override
  void scan() => did.add('scan');

  @override
  void openNoteAt(String noteId, int line, String find) => did.add('note $noteId $line "$find"');

  @override
  void newNoteIn(String workspaceId) => did.add('new in $workspaceId');

  @override
  void checklist() => did.add('checklist');

  @override
  void talk() => did.add('talk');

  @override
  void chat() => did.add('chat');
}

void main() {
  test('the links the shortcuts, the widgets and the tile open the app with', () {
    expect(readPhoneEntry('ghostmd://new'), const NewNoteEntry());
    expect(readPhoneEntry('ghostmd://new/'), const NewNoteEntry());
    expect(readPhoneEntry('ghostmd://voice'), const VoiceNoteEntry());
    expect(readPhoneEntry('ghostmd://today'), const TodayEntry());
    expect(readPhoneEntry('ghostmd://search'), const SearchEntry());
    expect(readPhoneEntry('ghostmd://scan'), const ScanEntry());
    expect(readPhoneEntry('ghostmd://note/n_12?line=7&find=Call%20the%20plumber'), const NoteAtEntry('n_12', line: 7, find: 'Call the plumber'));
    expect(readPhoneEntry('ghostmd://note/n_12?line=x'), const NoteAtEntry('n_12'));
    expect(readPhoneEntry('ghostmd://new?into=w-k3f9x2'), const NewNoteInEntry('w-k3f9x2'));
    expect(readPhoneEntry('ghostmd://new?into='), const NewNoteEntry(), reason: 'no workspace said: a plain new note');
    expect(readPhoneEntry('ghostmd://new?into=a%20b'), const NewNoteEntry(), reason: 'no workspace has such an id');
    expect(readPhoneEntry('ghostmd://checklist'), const ChecklistEntry());
    expect(readPhoneEntry('ghostmd://talk'), const TalkEntry());
    expect(readPhoneEntry('ghostmd://chat'), const ChatEntry());
  });

  test('a new note in a folder, as A folder widget is handed it, reads back the same', () {
    expect(newNoteInLink('org-9f2c-41'), 'ghostmd://new?into=org-9f2c-41');
    expect(readPhoneEntry(newNoteInLink('org-9f2c-41')), const NewNoteInEntry('org-9f2c-41'));
  });

  test('leaves every other link to the app’s own reader, the bare note link among them', () {
    for (final link in ['ghostmd://note/n_12', 'ghostmd://notifications', 'ghostmd://join/abc', 'ghostmd://new/thing', 'https://ghostmarkdown.com/new']) {
      expect(readPhoneEntry(link), isNull, reason: link);
    }
    expect(readAppLink('ghostmd://note/n_12'), isA<NoteAppLink>());
  });

  test('a note at a line, as the phone is handed it, reads back the same', () {
    final link = noteAtLink('n_12', line: 4, find: 'Call the plumber & the electrician');
    expect(readPhoneEntry(link), const NoteAtEntry('n_12', line: 4, find: 'Call the plumber & the electrician'));
    final long = noteAtLink('n_12', line: 1, find: 'x' * 200);
    expect((readPhoneEntry(long)! as NoteAtEntry).find, hasLength(80));
  });

  test('each is handed to the door, and anything else is not', () {
    final door = Door();
    for (final link in [
      'ghostmd://new',
      'ghostmd://voice',
      'ghostmd://today',
      'ghostmd://search',
      'ghostmd://note/a?line=2&find=Call',
      'ghostmd://new?into=w-1',
      'ghostmd://checklist',
      'ghostmd://talk',
      'ghostmd://chat',
      'ghostmd://notifications',
    ]) {
      followPhoneEntry(link, door);
    }
    expect(door.did, ['new', 'voice', 'today', 'search', 'note a 2 "Call"', 'new in w-1', 'checklist', 'talk', 'chat']);
  });
}
