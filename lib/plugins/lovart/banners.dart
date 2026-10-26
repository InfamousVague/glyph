/// Header banners for notes, made by Lovart in the house's dotwork (Matt, 2026-10-26: "help me generate a pre-prompt
/// for generation of note summary header images generated with lovart, i want them to be banners at the top in a in
/// house style"; then, of the four offered, "I like the dotwork prompt, bake it into generating the header prompts and
/// add a setting to automatically generate header images for notes (turn it on by default when lovart is enabled)").
///
/// The style is the ghost's own (tauri/docs/GHOSTS.md): stipple dotwork, black ink on pure white, the mascot described
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
  'A wide banner illustration, 4:1 landscape, for the header of a note in Ghost.md, a notes app.',
  'A stipple dotwork illustration, black ink on pure white: form, folds and shadow built entirely from black dots, dense in the shadows and sparse in the light, with a fine clean outline. Precise, patient and quietly elegant, like a fine-art print or a careful naturalist\'s plate.',
  'In it is the mascot of Ghost.md: a ghost made from a single sheet of fine writing paper. The sheet falls from a softly rounded top with one small corner folded down like a dog-eared page, a little taller than it is wide and as wide at the bottom as at the top, and ends in a hem cut in three soft waves that never touches the ground and never narrows to a tail. The sheet is plain, with no lines or writing on it. There is nothing inside the sheet: no body, no legs, no feet. Two small, simple eyes, each a solid black oval of dots, set wide and a little low, with no eyelids, iris, pupils, highlights or lashes. No mouth, and two short arms that are only a lift in the cloth. A single thin curl of smoke rises from the top of its head. The sheet bends, billows and folds with every movement; it never stands on the ground, and its small shadow of dots is below it. Calm and quietly warm, with the poise of a grown-up; not cute, not spooky.',
  'The ghost is small in the frame, in the right two-thirds, doing what this note is about: $subject The left third is empty white.',
  'Pure black and white only: no grey tones, no colour, no gradients; every tone is made of dots. No text, no letters, no words, no watermark, no border.',
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

void _markDone(PluginHost on, String id) {
  final done = _done(on);
  if (done.contains(id)) return;
  final next = [...done, id];
  on.storage.set(bannersDoneKey, next.length > _doneKept ? next.sublist(next.length - _doneKept) : next);
}

final RegExp _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Whether [note] is one a banner is made for by itself (the rules above), banner and keys aside.
bool wantsBanner(Note note) {
  if (note.archivedAt != null) return false;
  final body = note.body;
  if (bannerOf(body) != null) return false;
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
  LovartBanners({required this.getNote, required this.update, this.pictures, this.client, this.warn, this.done, PluginHost? via}) : _host = via;

  final Future<Note?> Function(String id) getNote;
  final Future<Note> Function(String id, String body, int expectedRevision) update;

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
  Future<bool> make(String id, {bool rethrowStopping = false}) async {
    if (!pluginOn(manifest) || !hasLovartKeys(_on)) return false;
    if ((pictures ?? lovartPictureStore) == null) return false;
    if (_done(_on).contains(id) || lovartBannerMaking.value.contains(id)) return false;
    final note = await getNote(id);
    if (note == null || !wantsBanner(note)) return false;
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
          // Not this note's fault: a run started again later tries it again.
          _on.storage.set(bannersDoneKey, [for (final done in _done(_on)) if (done != id) done]);
          rethrow;
        }
        warn?.call('[lovart] no banner for the note: ${failure is LovartNeedsConfirmation ? failure.said : failure.message}');
        return false;
      }
      final names = await keepLovartImages(images.take(1).toList(), into: pictures);
      if (names.isEmpty) return false;
      for (var attempt = 0; attempt < 2; attempt += 1) {
        final now = await getNote(id);
        // Gone, or given one by hand meanwhile: that one stands.
        if (now == null || bannerOf(now.body) != null) return false;
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

/// Where a run over the recent notes stands (Matt, 2026-10-26: "add the banner to 100 of the most recent notes that
/// are not tickets or meetings"): how many it set out to make, how many are done, how many came back with a banner,
/// and why it stopped where it stopped early.
@immutable
class BannerRun {
  const BannerRun({required this.total, this.done = 0, this.made = 0, this.running = true, this.stopped});
  final int total;
  final int done;
  final int made;
  final bool running;
  final String? stopped;

  BannerRun next({int? done, int? made, bool? running, String? stopped}) =>
      BannerRun(total: total, done: done ?? this.done, made: made ?? this.made, running: running ?? this.running, stopped: stopped ?? this.stopped);
}

/// The run over the recent notes, if one has been: the page draws it, and it outlives the page.
final ValueNotifier<BannerRun?> lovartBannerRun = ValueNotifier<BannerRun?>(null);

/// How many recent notes a run gives banners to, and how many Lovart is asked for at once.
const int bannerRunMost = 100;
const int bannerRunAtOnce = 3;

/// What the root hands the page for a run: the library's notes now, and the maker. Null where there is no library.
({List<Note> Function() notes, LovartBanners banners})? lovartBannerSource;

bool _stopRun = false;

/// Stops the run after the pictures being made now.
void stopBannerRun() => _stopRun = true;

/// The [most] most recently changed notes that are ones to have a banner and were never given one, newest first.
List<Note> bannerCandidates(List<Note> notes, {int most = bannerRunMost, PluginHost? via}) {
  final done = _done(via ?? host).toSet();
  final sorted = [...notes]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return [for (final note in sorted) if (!done.contains(note.id) && wantsBanner(note)) note].take(most).toList();
}

/// Gives banners to the most recent notes ([bannerCandidates]), [bannerRunAtOnce] at a time, telling
/// [lovartBannerRun] as each is done. Credits spent, keys refused or a costly step waiting stops the rest; Lovart
/// declining one goes on.
Future<void> runBanners() async {
  final source = lovartBannerSource;
  if (source == null || lovartBannerRun.value?.running == true) return;
  final unready = bannerUnready();
  if (unready != null) {
    lovartBannerRun.value = BannerRun(total: 0, running: false, stopped: unready);
    return;
  }
  final queue = bannerCandidates(source.notes());
  _stopRun = false;
  var run = lovartBannerRun.value = BannerRun(total: queue.length);
  String? stopped;
  var next = 0;
  Future<void> worker() async {
    while (!_stopRun && stopped == null && next < queue.length) {
      final note = queue[next++];
      try {
        final made = await source.banners.make(note.id, rethrowStopping: true);
        run = lovartBannerRun.value = run.next(done: run.done + 1, made: run.made + (made ? 1 : 0));
      } on LovartFailure catch (failure) {
        stopped = failure is LovartNeedsConfirmation ? failure.said : failure.message;
        run = lovartBannerRun.value = run.next(done: run.done + 1);
      }
    }
  }

  await Future.wait([for (var i = 0; i < bannerRunAtOnce; i += 1) worker()]);
  lovartBannerRun.value = run.next(running: false, stopped: stopped ?? (_stopRun ? 'Stopped.' : null));
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
