/// The gist: one quiet line under each note's title on the home page, what the note is about, written on the phone
/// in the background. A port of `src/app/format/gist.ts`.
///
/// Matt's board: "live on-device AI summaries on the home list". The page hands this the notes it has cards for
/// ([Gists]); a runner works through the ones with no gist, or a gist written from an older body, one at a time,
/// newest first, only while the app is on screen, and only with a model on the phone - the smallest, since a line of
/// twelve words wants speed, not care. Each gist is kept with the hash of the body it came from (results.dart), so a
/// note that has not changed is never asked about twice, and a note that has shows its old line until the new one
/// lands. A note the runner could not gist is left alone for the rest of the session, and a note's own run always
/// goes first (ai/runs.dart): the model is one. Nothing leaves the phone.
///
/// The home page and the page of every note both draw gists (home/home_screen.dart, notes/all_notes_screen.dart),
/// each for the first cards it draws, with its own search and filter. The bodies the runner works from are the
/// pages' that have handed theirs over ([Gists.show]), the last to do so first: two pages up together (a page kept
/// under another) do not take turns replacing each other's, and when the one on top has gone the other's are the
/// runner's again. With no page up, under a note, it goes on with the cards it was last shown, as the web app's
/// does.
///
/// The recorder wins the cores (docs/DESIGN.md §127 section 2): while it or a review is up ([pauseGists], following
/// capture/refine.dart's hold) a gist in flight is cancelled and not counted against its note, and the runner looks
/// again once the hold has gone.
///
/// The gist is of the note's words, after its front matter: where a note was written (core/geotag.dart) must not
/// become "Written at Trafalgar Square" on the home page, and a tag or a place written in must not change the hash
/// the gist is kept against. A note with front matter regenerates its gist once, on this change.
///
/// What differs:
/// - `useGists(notes)` is a [Gists]: a page makes one, hands it the notes it has cards for ([Gists.show]) each time
///   they change, listens to it, reads [Gists.value] and disposes of it. It does what the hook's two effects and its
///   memo did.
/// - The page's own state is asked of two things a module has no way to know: whether the app is on screen
///   ([gistVisible], the document's `visibilityState`; [gistsCameBack] is its `visibilitychange`), and the hold
///   (`onRefineHold(pauseGists)` ran as the page's module loaded; here whoever makes the better-words queue says
///   `refining.onRefineHold(pauseGists)`).
/// - `isTauri()` is the engine's [AiBackend.available]; a warning goes to [gistWarn].
/// - **A turn asks whether there is a model before it says it has begun**, and with none it says nothing and does
///   not look again by itself. The page's turn took the first note owed a line, said it had begun, found no model,
///   said it had ended and looked again 800 ms on, for as long as the app was open: on a phone with no model that
///   was an ask of the engine and two tellings of every card every 800 ms (measured here: 39 asks in 30 s), and a
///   card's ring lit for the length of each ask. Here the runner waits to be told the models changed
///   ([gistModelsChanged], [wakeGistsOn]) or the app came back ([gistsCameBack]).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ai/available.dart' show presentIds, smallestOf;
import '../ai/backend.dart';
import '../ai/runs.dart' show anyRunning, isRunning;
import '../capture/meeting_live.dart' show ExternalStore;
import '../core/blanks.dart' show withoutBlanks;
import '../core/front_matter.dart' show frontMatterOffset;
import '../core/item_syntax.dart' show jsTrim, markerPattern;
import '../core/note.dart' show Note;
import 'body_hash.dart';
import 'links.dart';
import 'prompt.dart' show gistPrompt, temperature;
import 'results.dart';

/// Whether the app is on screen (`document.visibilityState === 'visible'`). True unless whoever watches the app's
/// life says otherwise.
bool Function() gistVisible = _always;
bool _always() => true;

/// Where a gist that did not come is written down (`console.warn`).
void Function(String message, Object failure) gistWarn = _debugWarn;
void _debugWarn(String message, Object failure) => debugPrint('$message $failure');

/// The note's words: everything after its front matter (core/front_matter.dart).
String _wordsOf(String body) => body.substring(frontMatterOffset(body));

/// The model's answer as a card's line: the first line, bare, at most this long.
const int _longest = 90;

/// The marks a model may open its line with: a heading's, a list item's (core/item_syntax.dart), a quote's.
final RegExp _blockMarks = RegExp('^(?:#{1,6}\\s*|$markerPattern\\s+|>\\s*)+');
final RegExp _fence = RegExp(r'^```');
final RegExp _quotes = RegExp('^["“\'‘]+|["”\'’]+\$');
final RegExp _emphasis = RegExp(r'\*\*|__|`');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _closing = RegExp(r'[.!?:;,]+$');
final RegExp _trailingSpace = RegExp(r'\s+$');

/// See [_longest] (`tidyGist`).
String tidyGist(String text) {
  var line = '';
  for (final raw in text.split('\n')) {
    final l = jsTrim(raw);
    if (l.isNotEmpty && !_fence.hasMatch(l)) {
      line = l;
      break;
    }
  }
  var out = jsTrim(line.replaceFirst(_blockMarks, '').replaceAll(_quotes, '').replaceAll(_emphasis, '').replaceAll(_spaces, ' ').replaceFirst(_closing, ''));
  if (out.length > _longest) {
    final cut = out.substring(0, _longest);
    out = '${cut.substring(0, math.max(cut.lastIndexOf(' '), _longest - 20)).replaceFirst(_trailingSpace, '')}…';
  }
  return out;
}

// ---- the runner ----------------------------------------------------------------------------------------------------

/// The bodies the home page has cards for, by note id: what the runner works from. In the order they were handed
/// over, newest first.
final Map<String, String> _bodies = <String, String>{};
final Map<String, ({String body, int hash})> _hashes = <String, ({String body, int hash})>{};

/// How many times the runner has spoken - started a note, kept a gist, finished a turn - so the page reads the gists
/// again after each. A count rather than the runner's state, because what the page must notice is that something
/// happened: a turn that starts and lands between two of its frames leaves [_active] as it found it.
final ExternalStore<int> _spoken = ExternalStore<int>(0);
void _speak() => _spoken.update((n) => n + 1);
final Set<String> _failed = <String>{};

/// The note whose line is being written, as its card hears it (home/note_card.dart): told only when it changes, so
/// the cards of the notes that are not being worked on are left as they are drawn.
final ValueNotifier<String?> gistWorking = ValueNotifier<String?>(null);
String? get _active => gistWorking.value;
set _active(String? id) => gistWorking.value = id;

/// The generation in flight, so a pause can cancel it.
Run? _activeRun;
Timer? _timer;

/// The recorder or a review is up: nothing starts, and what was running is cancelled.
bool _paused = false;

/// A turn is asking the phone which models it has: no other turn begins meanwhile.
bool _asking = false;

/// The last turn found no model on the phone to write a line with: nothing is asked again until the models change
/// or the app comes back.
bool _noModel = false;

/// No gist runs while [on]; a run in flight is cancelled, uncounted, and the runner looks again once let go
/// (`pauseGists`).
void pauseGists(bool on) {
  if (_paused == on) return;
  _paused = on;
  if (on) {
    _activeRun?.cancel();
  } else {
    _kick();
  }
}

/// The notes open on the screen: none of them is gisted while it is, and a gist in flight for one is cancelled,
/// uncounted (Matt, 2026-10-26, on the model loading under a note being written and made pictures in: "Hold the gist
/// while the note is open"). The runner looks again once they are let go, for the words they were left with.
Set<String> _held = const <String>{};

/// The notes open now, from the shell as its screen changes (lib/root/root_parts.dart); none, back on a list.
void holdGistsFor(Iterable<String> ids) {
  final next = Set<String>.unmodifiable(ids);
  if (setEquals(next, _held)) return;
  final released = _held.any((id) => !next.contains(id));
  _held = next;
  if (_active != null && _held.contains(_active)) _activeRun?.cancel();
  if (released) _kick();
}

/// Whether [id]'s gist waits for its note to be closed.
bool gistHeld(String id) => _held.contains(id);

int _hashOf(String id, String body) {
  final known = _hashes[id];
  if (known != null && known.body == body) return known.hash;
  final hash = bodyHash(_wordsOf(body));
  _hashes[id] = (body: body, hash: hash);
  return hash;
}

/// The words' first line, the part a gist would change with.
String _headOf(String body) {
  for (final l in _wordsOf(body).split('\n')) {
    final trimmed = jsTrim(l);
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

/// Whether the kept gist still stands for [body]: the same body, or one that changed in a small way - a fixed typo,
/// a word - rather than a meaningful one (Matt's card: "re-summarize after meaningful changes") (`gistStands`).
/// Meaningful is the first line changing, or the length moving by a twentieth and at least twenty characters. A
/// stale-but-close gist is shown and not asked for again.
bool gistStands(({int forBody, int? len, String? head})? kept, String id, String body) {
  if (kept == null) return false;
  if (kept.forBody == _hashOf(id, body)) return true;
  final len = kept.len, head = kept.head;
  if (len == null || head == null) return false;
  if (head != _headOf(body)) return false;
  return (_wordsOf(body).length - len).abs() < math.max(20, len * 0.05);
}

/// The kept gist for a note, when it still stands for the body the note has now (`gistFor`).
String? gistFor(String id, String body) {
  final kept = readGist(id);
  if (kept == null || kept.text.isEmpty) return null;
  return gistStands((forBody: kept.forBody, len: kept.len, head: kept.head), id, body) ? kept.text : null;
}

/// The note whose gist is being written right now, for its card to wear a working icon; null while none is
/// (`activeGist`).
String? activeGist() => _active;

(String, String)? _owed() {
  for (final entry in _bodies.entries) {
    final id = entry.key, body = entry.value;
    if (jsTrim(_wordsOf(body)).isEmpty || _failed.contains(id) || _held.contains(id) || gistFor(id, body) != null || isRunning(id)) continue;
    return (id, body);
  }
  return null;
}

/// One turn of the runner: the next note owed a gist, if the app is on screen (`runGists`). Public for its test.
Future<void> runGists() => _pump();

Future<void> _pump() async {
  if (_asking || _active != null || _paused || !aiBackend.available || !gistVisible()) return;
  // A note's own run comes first: the model is one, and a line for the home page can wait a few seconds.
  if (anyRunning()) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 3000), () => unawaited(_pump()));
    return;
  }
  final next = _owed();
  if (next == null) return;
  final (id, body) = next;
  // Whether there is a model to write it with, before anything is said to have begun: with none the cards are told
  // nothing, and the runner waits for the models to change rather than asking again in 800 ms.
  final String? model;
  _asking = true;
  try {
    model = smallestOf(presentIds(await listModels()));
  } catch (failure) {
    gistWarn('[glyph] the gist did not come:', failure);
    _noModel = true;
    return;
  } finally {
    _asking = false;
  }
  if (model == null) {
    _noModel = true;
    return;
  }
  _noModel = false;
  // The recorder may have come up while the catalogue was read, or the note been opened: nothing starts under either.
  if (_paused || _active != null || _held.contains(id)) return;
  _active = id;
  // The card being worked on shows it (home/note_card.dart).
  _speak();
  try {
    // The words after the front matter; links go in as tokens, as for every run, and the line never has them.
    final words = _wordsOf(body);
    // Blanks out and fills as their words (docs/DESIGN.md §145): the smallest model is never handed a question to
    // answer.
    final text = protectLinks(withoutBlanks(words)).text;
    final run = generate(RunOptions(model: model, system: gistPrompt, prompt: text, maxTokens: 40, temperature: temperature, onProgress: (_) {}));
    _activeRun = run;
    final output = await run.done;
    final line = tidyGist(output.text);
    if (line.isNotEmpty) {
      keepGist(id, Gist(text: line, forBody: _hashOf(id, body), model: model, len: words.length, head: _headOf(body)));
    } else {
      _failed.add(id);
    }
    _speak();
  } catch (failure) {
    // Cancelled for the recorder, or for the note being opened: asked about again once it has gone, or been closed.
    if (_paused || _held.contains(id)) return;
    gistWarn('[glyph] the gist did not come:', failure);
    _failed.add(id);
  } finally {
    _active = null;
    _activeRun = null;
    _speak();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), () => unawaited(_pump()));
  }
}

void _kick() {
  _timer?.cancel();
  _timer = null;
  // With no engine in this build, or no model on the phone at the last look, there is nothing to wait for.
  if (!aiBackend.available || _noModel) return;
  _timer = Timer(const Duration(milliseconds: 1500), () => unawaited(_pump()));
}

/// The app came back to the screen: the runner looks again (the page's `visibilitychange`, when it says `visible`),
/// for a model too.
void gistsCameBack() {
  if (!gistVisible()) return;
  _noModel = false;
  _kick();
}

/// The models on the phone changed (one fetched, one removed): a runner that found none looks again.
void gistModelsChanged() {
  _noModel = false;
  _kick();
}

/// Wakes the runner as the models on the phone change: [models] is whatever says so (the app's catalogue, told for
/// a fetch's every chunk too), [present] the ids on the phone now. Only another set of ids is a change. Answers the
/// way to stop.
VoidCallback wakeGistsOn(Listenable models, Iterable<String> Function() present) {
  var had = present().join('\n');
  void heard() {
    final now = present().join('\n');
    if (now == had) return;
    had = now;
    gistModelsChanged();
  }

  models.addListener(heard);
  return () => models.removeListener(heard);
}

/// For the tests: the runner as a fresh launch has it. What is kept (results.dart) is the storage's to clear.
@visibleForTesting
void forgetGistRunner() {
  _timer?.cancel();
  _timer = null;
  _bodies.clear();
  _pages.clear();
  _hashes.clear();
  _failed.clear();
  _active = null;
  _activeRun = null;
  _paused = false;
  _asking = false;
  _noModel = false;
}

/// The pages that have handed their cards over, the last to do so last.
final List<Gists> _pages = <Gists>[];

/// The runner's bodies, from the pages': the last page's first, and each page's newest first.
void _gather() {
  _bodies.clear();
  for (final page in _pages.reversed) {
    for (final note in page._sorted) {
      _bodies.putIfAbsent(note.id, () => note.body);
    }
  }
}

/// The gists for the notes a page shows, by id, and the work to have them: the runner starts when a note has none
/// and the app is on screen (`useGists`).
class Gists extends ChangeNotifier implements ValueListenable<Map<String, String>> {
  Gists() {
    _stop = _spoken.subscribe(_heard);
  }

  late final VoidCallback _stop;
  List<Note> _notes = const <Note>[];
  List<Note> _sorted = const <Note>[];
  Map<String, String>? _read;

  // Read again after the runner speaks as well as when the notes change: the gists live in results.dart, not here.
  void _heard() {
    _read = null;
    notifyListeners();
  }

  /// The notes the page has cards for, as they are now.
  void show(List<Note> notes) {
    _notes = notes;
    _read = null;
    // Newest first: the note just made is the one a person is looking at.
    final sorted = <Note>[...notes];
    for (var i = 1; i < sorted.length; i += 1) {
      final note = sorted[i];
      var j = i - 1;
      while (j >= 0 && sorted[j].updatedAt < note.updatedAt) {
        sorted[j + 1] = sorted[j];
        j -= 1;
      }
      sorted[j + 1] = note;
    }
    _sorted = sorted;
    _pages
      ..remove(this)
      ..add(this);
    _gather();
    _kick();
  }

  /// Each note's gist, for the ones that have one that stands.
  @override
  Map<String, String> get value => _read ??= Map<String, String>.unmodifiable(<String, String>{
        for (final note in _notes)
          if (gistFor(note.id, note.body) case final String gist) note.id: gist,
      });

  @override
  void dispose() {
    // Its cards are no longer the runner's where another page has handed its own over: those stand. With no page
    // left (a note is open) the runner goes on with the cards it was last shown, as the web app's does, whose
    // bodies are a module's and outlive the page.
    if (_pages.remove(this) && _pages.isNotEmpty) _gather();
    _stop();
    super.dispose();
  }
}
