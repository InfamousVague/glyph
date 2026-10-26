/// The Lovart plugin: images made by Lovart's design agent, from a note (Matt, 2026-10-26: "I'd like to build a
/// Lovart.ai plugin into the app. They have a API for OpenClaw and I think we can build a wrapper around that in order
/// to create images automatically based on notes and with some custom inline syntax. For example during design
/// meetings the Lovart.ai plugin can generate inspo images and such"). docs/LOVART.md says what Lovart's API is and
/// how it was found.
///
/// Where it shows, once added in Settings › Plugins (off until then: it spends the person's Lovart credits):
/// - **`{image: a prompt}`** anywhere in a note (cues.dart). The editor marks a cue with Lovart's mark while the plugin
///   is on (lib/editor/ai/lovart_cues.dart), and tapping the mark makes that one; **Make images** on the note's cog
///   makes every cue, in order. Each becomes `![the prompt](image/lovart-….png)`.
/// - **Inspiration images** on the note's cog: a moodboard of four from the note, under `## Inspiration`
///   (inspiration.dart).
/// - **Inspiration for design meetings**, a switch on its page: a meeting that reads as a design meeting gets the same,
///   once, as soon as it is written up (meetings.dart).
/// - Its page in Settings: the two keys, checked before they are kept, and the switch (lovart_pane.dart).
///
/// A picture Lovart made carries Lovart's mark at its corner wherever it is drawn (lib/editor/media/lovart_badge.dart),
/// by its name, plugin on or not.
library;


import 'package:flutter/foundation.dart';

import '../registry.dart' show pluginOn;
import '../types.dart';
import 'client.dart';
import 'cues.dart';
import 'inspiration.dart';
import 'keep.dart';
import 'lovart_mark.dart';
import 'lovart_pane.dart';
import 'manifest.dart';

export 'client.dart';
export 'cues.dart';
export 'inspiration.dart';
export 'keep.dart';
export 'lovart_mark.dart';
export 'lovart_pane.dart';
export 'manifest.dart' show accessKeySecret, secretKeySecret, meetingsKey, projectKey;
export 'meetings.dart';

/// The cues being made now, by note and cue (`noteId\ncue`): the chip by each draws a spinner while it is here.
final ValueNotifier<Set<String>> lovartMaking = ValueNotifier<Set<String>>(const {});

String _making(String noteId, String cueText) => '$noteId\n$cueText';

/// Whether the cue [cueText] of [noteId] is being made.
bool lovartIsMaking(String noteId, String cueText) => lovartMaking.value.contains(_making(noteId, cueText));

void _mark(String key, bool on) {
  final next = {...lovartMaking.value};
  if (on ? next.add(key) : next.remove(key)) lovartMaking.value = Set.unmodifiable(next);
}

/// What the person is told when Lovart cannot be asked here.
String? lovartUnready() {
  if (!hasLovartKeys()) return 'Add your Lovart keys in Settings › Plugins › Lovart first.';
  if (lovartPictureStore == null) return cannotKeepLovart;
  return null;
}

/// What a failure is said as.
String lovartSaid(LovartFailure failure) => failure is LovartNeedsConfirmation ? failure.said : failure.message;

/// Writes the pictures [names] where the cue [cue] is in the open note now (cues.dart [cueEdits]), each line through
/// its editor. Answers whether the cue was still there.
bool placeCue(NoteEditing editing, ImageCue cue, List<String> names) {
  final edits = cueEdits(editing.body(), cue, names);
  for (final edit in edits) {
    editing.replaceLine((text, line) => line == edit.line, (_) => edit.text);
  }
  return edits.isNotEmpty;
}

/// Makes the cue [cue] of the open note into its picture: asked, kept, then written where the cue still is. Answers
/// whether it was; says why not on the note.
Future<bool> makeCue(NoteEditing editing, ImageCue cue) async {
  final unready = lovartUnready();
  if (unready != null) {
    editing.say(unready);
    return false;
  }
  final lovart = lovartClient();
  if (lovart == null) return false;
  final key = _making(editing.noteId, cue.text);
  if (lovartMaking.value.contains(key)) return false;
  _mark(key, true);
  try {
    final names = await keepLovartImages(await lovart.generate(cuePrompt(cue.prompt)));
    if (names.isEmpty) return false;
    final written = placeCue(editing, cue, names);
    if (!written) editing.say('The image was made, but its {image: …} was gone from the note.');
    return written;
  } on LovartFailure catch (failure) {
    editing.say(lovartSaid(failure));
    return false;
  } finally {
    _mark(key, false);
  }
}

/// Every cue of the open note, in order, saying how far it is. A key refused, credits spent or a costly step waiting
/// stops the rest; Lovart declining one goes on to the next.
Future<void> makeAllCues(NoteEditing editing) async {
  final unready = lovartUnready();
  if (unready != null) return editing.say(unready);
  final cues = imageCues(editing.body());
  var made = 0;
  for (final (index, cue) in cues.indexed) {
    editing.say(cues.length == 1 ? 'Lovart is making the image…' : 'Lovart is making image ${index + 1} of ${cues.length}…');
    final lovart = lovartClient();
    if (lovart == null) return;
    final key = _making(editing.noteId, cue.text);
    _mark(key, true);
    try {
      final names = await keepLovartImages(await lovart.generate(cuePrompt(cue.prompt)));
      if (names.isNotEmpty && placeCue(editing, cue, names)) made += 1;
    } on LovartRefused catch (failure) {
      editing.say(failure.message);
    } on LovartFailure catch (failure) {
      editing.say(lovartSaid(failure));
      return;
    } finally {
      _mark(key, false);
    }
  }
  if (made > 0) editing.say(made == 1 ? 'Made 1 image with Lovart.' : 'Made $made images with Lovart.');
}

/// A moodboard of four for the open note, under its `## Inspiration`.
Future<void> makeInspiration(NoteEditing editing) async {
  final unready = lovartUnready();
  if (unready != null) return editing.say(unready);
  final lovart = lovartClient();
  if (lovart == null) return;
  editing.say('Lovart is making inspiration images…');
  try {
    final names = await keepLovartImages(await lovart.generate(inspirationPrompt(editing.body())));
    if (names.isEmpty) return;
    final at = inspirationInsert(editing.body(), names);
    editing.replaceLine((text, line) => line == at.line, (text) => '$text${at.add}');
    editing.say(names.length == 1 ? 'Added 1 inspiration image.' : 'Added ${names.length} inspiration images.');
  } on LovartFailure catch (failure) {
    editing.say(lovartSaid(failure));
  }
}

String _summary() => hasLovartKeys() ? 'Keys kept' : 'Not set up';

/// Whether the cues of notes are marked in the editor: the plugin on.
bool lovartCuesOn() => pluginOn(manifest);

final GlyphPlugin lovartPlugin = GlyphPlugin(
  manifest: manifest,
  icon: 'palette',
  settings: PluginSettings(
    pane: (context) => const LovartPane(),
    hue: 'purple',
    settings: lovartFindable,
    summary: _summary,
  ),
  noteActions: [
    NoteAction(
      id: 'lovart-cues',
      label: 'Make images',
      icon: lovartIcon,
      visible: (noteId, body) => imageCues(body).isNotEmpty,
      hint: (noteId, body) {
        final unready = lovartUnready();
        if (unready != null) return unready;
        final count = imageCues(body).length;
        return '$count {image: …} ${count == 1 ? 'becomes a picture' : 'become pictures'}, made by Lovart with your credits.';
      },
      enabled: (noteId, body) => lovartUnready() == null && imageCues(body).isNotEmpty,
      run: (editing, [choice]) => makeAllCues(editing),
    ),
    NoteAction(
      id: 'lovart-inspiration',
      label: 'Inspiration images',
      icon: lovartIcon,
      visible: (noteId, body) => body.trim().isNotEmpty,
      hint: (noteId, body) => lovartUnready() ?? 'A moodboard of $inspirationCount from this note, under Inspiration, made by Lovart with your credits.',
      enabled: (noteId, body) => lovartUnready() == null,
      run: (editing, [choice]) => makeInspiration(editing),
    ),
  ],
);
