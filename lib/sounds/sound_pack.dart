/// Sound packs (Matt, 2026-10-27: "build ... the sounds settings"; docs/ideas/CUSTOMIZATION_AND_SOUNDS.md, Sounds):
/// what makes a sound in the app, and which file each pack plays for it.
///
/// A pack is the same eleven events in one voice, each a file under `assets/sounds/<pack>/<event>.<ext>`: `.ogg` for
/// Android, `.caf` for the Mac and the iPhone (assets/sounds/README.md says what goes in each). Ghostly is the
/// default and the only pack with files so far, and they are placeholders made by tool/placeholder_sounds.py until
/// Matt's from ElevenLabs drop in by the same names. Off is the pack with no files: nothing plays.
///
/// Kept apart from the player and the preferences, as words and paths alone, so the Market can list packs later
/// without either.
library;

/// Where a sound is heard: inside the app (through the in-app player, at the interface volume) or as a
/// notification's sound (the phone's or the Mac's, on its notification's own channel).
enum SoundPlace { interface, notification }

/// One thing that makes a sound, by the file name every pack uses for it.
enum SoundEvent {
  todoTicked('todo-ticked', 'To-do ticked', 'A soft tap as a box is ticked.', SoundPlace.interface, on: true),
  allTicked('all-ticked', 'All to-dos ticked', 'A small flourish when the last open to-do is done.', SoundPlace.interface),
  recordStart('record-start', 'Recording starts', 'Heard before you begin speaking.', SoundPlace.interface, on: true),
  recordStop('record-stop', 'Recording stops', 'The start’s answer, falling.', SoundPlace.interface, on: true),
  writeupReady('writeup-ready', 'Write-up ready', 'A summary or a meeting’s write-up has landed.', SoundPlace.notification),
  reminderDue('reminder-due', 'Reminder due', 'A reminder’s notification, more insistent than the rest.', SoundPlace.notification),
  meetingJoining('meeting-joining', 'Meeting starting', 'Ghost is joining a meeting.', SoundPlace.notification),
  teamComment('team-comment', 'Team comment', 'A comment or a mention from your team.', SoundPlace.notification),
  lovartReady('lovart-ready', 'Lovart picture ready', 'Lovart has drawn what you asked for.', SoundPlace.notification),
  failed('failed', 'Something failed', 'Low and soft, never alarming.', SoundPlace.interface),
  // A long job you started is done (docs/ACTIVITY.md, Sound; Matt, 2026-10-29): on, as the recorder's are, and heard
  // only for a job that ran over half a minute (lib/activity/activity_chime.dart).
  jobDone('job-done', 'Long job finished', 'A soft chime when something you started, that took a while, is done.', SoundPlace.interface, on: true),
  saved('saved', 'Saved', 'A breath when a note is saved. Very quiet.', SoundPlace.interface);

  const SoundEvent(this.id, this.label, this.hint, this.place, {this.on = false});

  /// The file's name in every pack, and the key it is kept under in the preferences.
  final String id;
  final String label;
  final String hint;
  final SoundPlace place;

  /// Whether it plays until it is switched: the recorder's start and stop and the to-do tick alone, as the doc
  /// says ("the recorder's start and stop are the only ones on by default", and the tick is "the one people keep
  /// on"); and since 2026-10-29 the long job's chime (docs/ACTIVITY.md, Sound), which is rare by its rule.
  final bool on;

  static SoundEvent? byId(String id) {
    for (final event in values) {
      if (event.id == id) return event;
    }
    return null;
  }
}

/// A set of sounds in one voice.
class SoundPack {
  const SoundPack({required this.id, required this.name, required this.description, this.events = const {}});

  final String id;
  final String name;
  final String description;

  /// The events this pack has a file for. An event it lacks is silent in it.
  final Set<SoundEvent> events;

  bool get silent => events.isEmpty;

  /// The asset key of [event]'s file for this platform's player ([apple] for the Mac and the iPhone), or null where
  /// the pack has none.
  String? asset(SoundEvent event, {required bool apple}) => events.contains(event) ? soundAsset(id, event, apple: apple) : null;
}

/// The path of a pack's file for an event: `assets/sounds/<pack>/<event>.ogg`, or `.caf` on Apple's platforms.
String soundAsset(String pack, SoundEvent event, {required bool apple}) => 'assets/sounds/$pack/${event.id}.${apple ? 'caf' : 'ogg'}';

/// The packs, in the chooser's order: Ghostly first and the default, then Off.
const List<SoundPack> soundPacks = [
  SoundPack(
    id: 'ghostly',
    name: 'Ghostly',
    description: 'Soft, breathy and airy: the app’s own character.',
    events: {...SoundEvent.values},
  ),
  SoundPack(id: 'off', name: 'Off', description: 'No sounds at all.'),
];

/// The pack ids, for the preferences to check a stored one against.
List<String> get soundPackIds => [for (final pack in soundPacks) pack.id];

/// The pack by its id; Ghostly for one this build does not have.
SoundPack soundPackOf(String id) => soundPacks.firstWhere((pack) => pack.id == id, orElse: () => soundPacks.first);
