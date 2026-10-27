/// Header banners for notes, made by Lovart in the house's dotwork (Matt, 2026-10-26: "help me generate a pre-prompt
/// for generation of note summary header images generated with lovart, i want them to be banners at the top in a in
/// house style"; then, of the four offered, "I like the dotwork prompt, bake it into generating the header prompts and
/// add a setting to automatically generate header images for notes (turn it on by default when lovart is enabled)").
///
/// The style is the ghost's own (tauri/docs/GHOSTS.md): stipple dotwork on pure white, in full colour since Matt asked
/// for it (2026-10-26: "The dotwork pre prompts should be full color like the grocery store item from earlier"; they
/// were black ink only before, and lib/note/note_banner.dart draws each as it is), the mascot described
/// word for word as every ghost scene describes it, small on the right two-thirds doing what the note is about, the
/// left third left white. [bannerPrompt] is that pre-prompt with the note's title and its opening as the subject;
/// Lovart picks the one scene. The banner is the note's front matter `banner:` (lib/core/banner.dart), drawn across
/// the top of the page (lib/note/note_screen.dart, by [NoteBannerView]).
///
/// The rules for making one by itself ([LovartBanners.noteLeft]):
/// - **Only where asked.** The plugin on (Local only holds it off), both keys kept, and "Header images for notes" on
///   in its page ([bannersOn]: on until switched off, since adding the plugin is the asking).
/// - **When a note is left**, never while it is open: its words are still moving, and the picture is made from them.
///   So the notes that get one are the ones the person opens, and the library is not spent in one go.
/// - **Only real notes.** Not a ticket, a meeting Ghost was in or a written-up recording, a mail, a canvas, a
///   notebook, a journal or a template; not one with fewer than [bannerMinWords] words; not one with a banner.
/// - **Once per note.** Marked in the plugin's storage before Lovart is asked ([bannersDoneKey]), so a banner taken
///   off, or a failure, asks nothing more; "Header image" on the note's cog is there to make one again.
/// - **Into the note as it is then.** Read again once the picture is kept, written over the revision read; one that
///   moved on meanwhile is read again and written once more.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/banner.dart';
import '../../core/front_matter.dart' show frontMatterFence, frontMatterOffset;
import '../../core/images.dart' show PictureStore;
import '../../core/note.dart' show Note;
import '../../core/note_facts.dart' show NoteFacts;
import '../../core/note_text.dart' show hasTape, noteTitle;
import '../../core/summary_text.dart' show summarySection;
import '../../meet/meet_note.dart' show ghostLineStart;
import '../registry.dart' show pluginOn;
import '../types.dart';
import 'client.dart';
import 'keep.dart';
import 'manifest.dart';

/// How many of a note's opening characters tell Lovart what it is about, past its title.
const int bannerChars = 900;

/// The fewest words a note has before it is given a banner by itself: a grocery list of two things is not yet one.
const int bannerMinWords = 25;

/// How many notes are remembered as given one: the newest.
const int _doneKept = 2000;

/// The house's banner, the ghost's dotwork, with [subject] where the scene goes.
String bannerStyle(String subject) => [
  'A wide 16:9 landscape illustration, 1920 by 1080 pixels, never square, for the header banner of a note in Ghost.md, a notes app. Keep everything drawn inside the middle band of the picture, away from its top and bottom edges, with plain white above and below, so the banner can be cropped wider without cutting anything off.',
  'A stipple dotwork illustration in full colour on pure white: form, folds and shadow built entirely from dots of rich, natural colour, dense in the shadows and sparse in the light, with a fine clean outline. The colours are true to the things drawn, warm and clear. Precise, patient and quietly elegant, like a hand-coloured fine-art print or a careful naturalist\'s plate.',
  'In it is the mascot of Ghost.md: a ghost made from a single sheet of fine writing paper. The sheet falls from a softly rounded top with one small corner folded down like a dog-eared page, a little taller than it is wide and as wide at the bottom as at the top, and ends in a hem cut in three soft waves that never touches the ground and never narrows to a tail. The sheet is plain, with no lines or writing on it. There is nothing inside the sheet: no body, no legs, no feet. Two small, simple eyes, each a solid black oval of dots, set wide and a little low, with no eyelids, iris, pupils, highlights or lashes. No mouth, and two short arms that are only a lift in the cloth. A single thin curl of smoke rises from the top of its head. The sheet bends, billows and folds with every movement; it never stands on the ground, and its small shadow of dots is below it. Calm and quietly warm, with the poise of a grown-up; not cute, not spooky.',
  'The ghost is small in the frame, in the right two-thirds, doing what this note is about: $subject The left third is empty white.',
  'Full colour, every tone made of dots: no flat fills, no smooth gradients. The ghost\'s sheet stays white paper and its eyes black. No text, no letters, no words, no watermark, no border.',
  'Make one image.',
].join('\n\n');

String _opening(String body) {
  var words = body.substring(frontMatterOffset(body)).replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (words.length > bannerChars) words = '${words.substring(0, bannerChars).trimRight()}…';
  return words;
}

/// The prompt for [body]'s banner: the house style, with the note as the subject for Lovart to pick one scene from.
String bannerPrompt(String body) {
  final title = noteTitle(body);
  final opening = _opening(body);
  final subject = [
    'pick one simple, concrete scene from the note below and show the ghost in it, with a few objects from it drawn with care.',
    if (title.isNotEmpty) 'The note is titled “$title”.',
    if (opening.isNotEmpty) 'It reads: $opening',
  ].join(' ');
  return bannerStyle(subject);
}

/// The notes being given a banner now, by id: their banner's place draws Lovart at work while one is here.
final ValueNotifier<Set<String>> lovartBannerMaking = ValueNotifier<Set<String>>(const {});

void _making(String id, bool on) {
  final next = {...lovartBannerMaking.value};
  if (on ? next.add(id) : next.remove(id)) lovartBannerMaking.value = Set.unmodifiable(next);
}

/// Whether notes are given banners by themselves on this device: on until switched off.
bool bannersOn([PluginHost? via]) => (via ?? host).storage.get<Object?>(bannersKey, true) != false;

/// Switches it.
void setBanners(bool on, [PluginHost? via]) => (via ?? host).storage.set(bannersKey, on);

List<String> _done(PluginHost on) {
  final Object? kept = on.storage.get<Object?>(bannersDoneKey, const <Object?>[]);
  return kept is List ? [for (final id in kept) if (id is String) id] : <String>[];
}

/// The notes this device has given a banner to, or asked Lovart for one: never asked again by themselves.
List<String> bannersGiven([PluginHost? via]) => _done(via ?? host);

/// [ids] taken off that list: a run cut short before their pictures came asks for them again (banner_run.dart).
void forgetBannersGiven(Iterable<String> ids, [PluginHost? via]) {
  final on = via ?? host;
  final gone = ids.toSet();
  final done = _done(on);
  if (!done.any(gone.contains)) return;
  on.storage.set(bannersDoneKey, [for (final id in done) if (!gone.contains(id)) id]);
}

void _markDone(PluginHost on, String id) {
  final done = _done(on);
  if (done.contains(id)) return;
  final next = [...done, id];
  on.storage.set(bannersDoneKey, next.length > _doneKept ? next.sublist(next.length - _doneKept) : next);
}

final RegExp _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Whether [note] is one a banner is made for by itself (the rules above), banner and keys aside. [replacing], one
/// that may have one already: a run's Redo black-and-white headers in colour (banner_run.dart).
bool wantsBanner(Note note, {bool replacing = false}) {
  if (note.archivedAt != null) return false;
  final body = note.body;
  if (!replacing && bannerOf(body) != null) return false;
  final facts = NoteFacts.read(body);
  if (facts.isTicket || facts.isBook || facts.isCanvas || facts.isTemplatePage || facts.isTemplatesBook) return false;
  // A mail as it arrived, and a meeting: Ghost's own, or a recording written up.
  if (facts.value('from') != null) return false;
  if (body.contains(ghostLineStart)) return false;
  if (hasTape(note) && summarySection(body) != null) return false;
  return _word.allMatches(body.substring(frontMatterOffset(body))).length >= bannerMinWords;
}

/// What the person is told where a banner cannot be asked for here, or null.
String? bannerUnready() {
  if (!hasLovartKeys()) return 'Add your Lovart keys in Settings › Lovart first.';
  if (lovartPictureStore == null) return cannotKeepLovart;
  return null;
}

/// Gives notes their banners as they are left.
class LovartBanners {
  LovartBanners({required this.getNote, required this.update, this.write, this.pictures, this.client, this.warn, this.done, PluginHost? via}) : _host = via;

  final Future<Note?> Function(String id) getNote;
  final Future<Note> Function(String id, String body, int expectedRevision) update;

  /// The note changed where it is now, where given (Matt, 2026-10-26: "Make the header generation async and a
  /// background task that runs while the app is generating the images"): the root's, which hands the change to the
  /// note's editor while the note is open, as Claude's writes go (lib/root/root_commands.dart `_changeNote`), and
  /// writes it where it is kept otherwise. A banner made while the note is open then lands as an edit of its front
  /// matter alone, and what the person is typing stays theirs: a write behind the editor would be refused at its
  /// next save and stop its saving. Without it, [getNote] and [update], from the revision read.
  final Future<void> Function(String id, String Function(String body) change)? write;

  /// Where the pictures are kept: the root's ([lovartPictureStore]) unless given.
  final PictureStore? pictures;

  /// The client to ask; the one with the kept keys unless given.
  final LovartClient? Function()? client;
  final void Function(String message)? warn;

  /// Told the note a banner was written into.
  final void Function(String id)? done;
  final PluginHost? _host;

  PluginHost get _on => _host ?? host;

  /// The note [id] was left: given its banner, where it is one to have. Answers whether it was.
  Future<bool> noteLeft(String id) async {
    if (!bannersOn(_on)) return false;
    return make(id);
  }

  /// Gives the note [id] its banner, where it is one to have, the switch aside. Answers whether it was. A failure is
  /// said to the log, or thrown where [rethrowStopping] and it is one that stops a run (anything but Lovart declining).
  ///
  /// Asked by a run the person started, two more ways (Matt, 2026-10-26: "remove the header banner images on the
  /// docs as we will regenerate them"): [again], a note given one before whose banner was taken off, made once more
  /// although it is marked given; and [replacing], the black-and-white banner of that name made again in colour and
  /// put in its place. Either way only while the note still has what it had: a banner given by hand meanwhile, or a
  /// different one, stands. Leaving a note never asks either: there a banner taken off stays off.
  Future<bool> make(String id, {bool rethrowStopping = false, bool again = false, String? replacing}) async {
    if (!pluginOn(manifest) || !hasLovartKeys(_on)) return false;
    if ((pictures ?? lovartPictureStore) == null) return false;
    final asked = again || replacing != null;
    if ((!asked && _done(_on).contains(id)) || lovartBannerMaking.value.contains(id)) return false;
    final note = await getNote(id);
    if (note == null || !wantsBanner(note, replacing: replacing != null) || bannerOf(note.body) != replacing) return false;
    // Marked before Lovart is asked: once per note, whatever happens next.
    _markDone(_on, id);
    final lovart = client != null ? client!() : (_host == null ? lovartClient() : LovartClient.kept(via: _host));
    if (lovart == null) return false;
    _making(id, true);
    try {
      final List<Uint8List> images;
      try {
        images = await lovart.generate(bannerPrompt(note.body));
      } on LovartFailure catch (failure) {
        if (rethrowStopping && failure is! LovartRefused) {
          // Not this note's fault: a run started again later tries it again. One asked again was given one before,
          // and stays so for leaving it.
          if (!asked) _on.storage.set(bannersDoneKey, [for (final done in _done(_on)) if (done != id) done]);
          rethrow;
        }
        // Lovart at its limit of jobs at once: not this note's doing, so leaving it again asks again.
        if (failure.busy && !asked) _on.storage.set(bannersDoneKey, [for (final done in _done(_on)) if (done != id) done]);
        warn?.call('[lovart] no banner for the note: ${failure is LovartNeedsConfirmation ? failure.said : failure.message}');
        return false;
      }
      final names = await keepLovartImages(images.take(1).toList(), into: pictures);
      if (names.isEmpty) return false;
      final into = write;
      if (into != null) {
        for (var attempt = 0; attempt < 2; attempt += 1) {
          var wrote = false;
          try {
            await into(id, (body) {
              // Given one by hand meanwhile (or, one being replaced, another one): that one stands.
              if (bannerOf(body) != replacing) return body;
              wrote = true;
              return withBanner(body, names.first);
            });
            if (wrote) done?.call(id);
            return wrote;
          } catch (failure) {
            if (attempt == 1) warn?.call('[lovart] the banner was not written into the note: $failure');
          }
        }
        return false;
      }
      for (var attempt = 0; attempt < 2; attempt += 1) {
        final now = await getNote(id);
        // Gone, or given one by hand meanwhile (or, one being replaced, another one): that one stands.
        if (now == null || bannerOf(now.body) != replacing) return false;
        try {
          await update(id, withBanner(now.body, names.first), now.revision);
          done?.call(id);
          return true;
        } catch (failure) {
          if (attempt == 1) warn?.call('[lovart] the banner was not written into the note: $failure');
        }
      }
      return false;
    } finally {
      _making(id, false);
    }
  }
}

/// The one line of the open note [body] to change for its banner to be [name], and what it becomes: the banner's own
/// line where there is one, the front matter's closing fence where there is front matter, else the first line with
/// front matter put before it.
({int line, String Function(String text) next}) bannerEdit(String body, String name) {
  final lines = body.split('\n');
  final value = '$bannerKey: ${bannerValue(name)}';
  if (frontMatterOffset(body) > 0) {
    final end = lines.indexWhere(frontMatterFence.hasMatch, 1);
    final key = RegExp('^\\s*$bannerKey\\s*:', caseSensitive: false);
    for (var i = 1; i < end; i += 1) {
      if (key.hasMatch(lines[i])) return (line: i + 1, next: (_) => value);
    }
    // Last of its keys, as [withBanner] adds it: before the closing fence.
    return (line: end + 1, next: (text) => '$value\n$text');
  }
  return (line: 1, next: (text) => '---\n$value\n---\n$text');
}

/// A banner for the open note, made now: the cog's "Header image", which makes one again where there is one.
Future<void> makeBanner(NoteEditing editing) async {
  final unready = bannerUnready();
  if (unready != null) return editing.say(unready);
  final lovart = lovartClient();
  if (lovart == null) return;
  final id = editing.noteId;
  if (lovartBannerMaking.value.contains(id)) return;
  _markDone(host, id);
  _making(id, true);
  editing.say('Lovart is making a header image…');
  try {
    final names = await keepLovartImages((await lovart.generate(bannerPrompt(editing.body()))).take(1).toList());
    if (names.isEmpty) return;
    final edit = bannerEdit(editing.body(), names.first);
    editing.replaceLine((text, line) => line == edit.line, edit.next);
  } on LovartFailure catch (failure) {
    editing.say(failure is LovartNeedsConfirmation ? failure.said : failure.message);
  } finally {
    _making(id, false);
  }
}
