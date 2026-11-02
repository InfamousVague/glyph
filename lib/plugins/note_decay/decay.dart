/// Note decay alerts as the app holds them: one [NoteDecay] for the life of the app, which every place that shows a
/// mark asks (docs/NOTE_DECAY.md; Matt, 2026-11-02: "docs and pages that reference things that have since changed …
/// get a quiet 'may be out of date' mark with the reason"). The open note's marks (marks.dart), the lists of pages
/// that may be out of date (decay_list.dart) and the plugin's page read it, and it tells them when what it knows
/// changes.
///
/// What it keeps is a cache: the signals are made again from the files whenever they are asked after the library
/// changed; GitHub's and Figma's answers and the AI's are kept for the page they were asked for, until it changes.
/// What it remembers is the renames it hears (a title before and after a save), since the library keeps none.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/docs_book.dart' show isDocsBody;
import '../../core/note.dart';
import '../../core/note_text.dart' show noteTitle;
import 'ai.dart';
import 'dismissals.dart';
import 'lookups.dart';
import 'signals.dart';

/// A page with what may have made it out of date: a row of a list.
@immutable
class DecayPage {
  const DecayPage(this.note, this.title, this.signals);
  final Note note;
  final String title;
  final List<DecaySignal> signals;
}

/// What a remote or AI pass found for a page, and the body it was found in: a page edited since asks again.
class _Found {
  _Found(this.body, this.signals);
  final String body;
  final List<DecaySignal> signals;
}

/// The app's note decay (see the header). Everything it reads is handed in, so a test's is its own.
class NoteDecay extends ChangeNotifier {
  NoteDecay({
    required List<Note> Function() notes,
    this.changes,
    DecayLookups Function()? lookups,
    DecayModel Function()? model,
    bool Function()? on,
    bool Function()? aiOn,
    int Function()? months,
    Map<String, String> Function()? renames,
    void Function(Map<String, String> renames)? keepRenames,
    DateTime Function()? clock,
  })  : _notes = notes,
        _lookups = lookups ?? (() => const NoDecayLookups()),
        _model = model ?? (() => const NoDecayModel()),
        _on = on ?? (() => true),
        _aiOn = aiOn ?? (() => false),
        _months = months ?? (() => 3),
        _renames = renames ?? (() => const {}),
        _keepRenames = keepRenames,
        _clock = clock ?? DateTime.now {
    _titles = {for (final note in _notes()) note.id: noteTitle(note.body)};
    changes?.addListener(_libraryChanged);
  }

  final List<Note> Function() _notes;

  /// Says when the library changed.
  final Listenable? changes;
  final DecayLookups Function() _lookups;
  final DecayModel Function() _model;
  final bool Function() _on;
  final bool Function() _aiOn;
  final int Function() _months;
  final Map<String, String> Function() _renames;
  final void Function(Map<String, String> renames)? _keepRenames;
  final DateTime Function() _clock;

  Map<String, String> _titles = {};
  List<Note>? _readFrom;
  Map<String, String>? _renamesFrom;
  DecayLibrary? _library;
  final Map<String, _Found> _remote = {};
  final Map<String, _Found> _ai = {};
  final Set<String> _asking = {};

  /// Whether the plugin is on: off, nothing is marked anywhere.
  bool get on => _on();

  /// Whether the AI pass may run.
  bool get aiOn => _aiOn() && _model().ready;

  /// Who the AI pass and Update with AI ask.
  DecayModel get model => _model();

  /// Whether a pass for [noteId] is being made now.
  bool asking(String noteId) => _asking.contains(noteId);

  /// Called when the plugin's settings or the AI's change: everything is read again.
  void settingsChanged() {
    _library = null;
    notifyListeners();
  }

  void _libraryChanged() {
    final notes = _notes();
    final renamed = <String, String>{};
    final next = <String, String>{};
    for (final note in notes) {
      final title = noteTitle(note.body);
      next[note.id] = title;
      final was = _titles[note.id];
      if (was != null && was.trim().isNotEmpty && title.trim().isNotEmpty && was.trim().toLowerCase() != title.trim().toLowerCase()) renamed[was.trim()] = title.trim();
    }
    _titles = next;
    if (renamed.isNotEmpty && _keepRenames != null) {
      // A title taken back to what it was is no rename; the rest follow on to the newest.
      final kept = {..._renames(), ...renamed}..removeWhere((from, to) => from.toLowerCase() == to.toLowerCase());
      _keepRenames(kept);
    }
    _library = null;
    notifyListeners();
  }

  /// The library as the checks read it, made again once the notes or the renames changed.
  DecayLibrary get library {
    final notes = _notes();
    final renames = _renames();
    if (_library != null && identical(notes, _readFrom) && identical(renames, _renamesFrom)) return _library!;
    _readFrom = notes;
    _renamesFrom = renames;
    final docPages = <String>{};
    for (final note in notes) {
      if (!note.inTrash && isDocsBody(note.body)) docPages.addAll(linkedTitles(note.body).map((t) => t.toLowerCase()));
    }
    return _library = DecayLibrary([for (final note in notes) _decayNote(note, docPages)], renamed: renames);
  }

  DecayNote _decayNote(Note note, Set<String> docPages, [String? body]) {
    final title = noteTitle(note.body);
    return DecayNote(
      id: note.id,
      title: title,
      body: body ?? note.body,
      edited: DateTime.fromMillisecondsSinceEpoch(note.updatedAt),
      trashed: note.inTrash,
      archived: note.archivedAt != null,
      docPage: docPages.contains(title.toLowerCase()),
    );
  }

  /// The note [noteId] as the checks read it, its body [body] where given (the open editor's).
  DecayNote? decayNoteOf(String noteId, {String? body}) {
    final note = library.notes.where((n) => n.id == noteId).firstOrNull;
    if (note == null) return null;
    return body == null ? note : DecayNote(id: note.id, title: note.title, body: body, edited: note.edited, trashed: note.trashed, archived: note.archived, docPage: note.docPage);
  }

  /// What may have made [noteId] out of date now, its body [body] where given: the signals, then GitHub's, Figma's and
  /// the AI's where a pass found any for the page as it reads, less those the page keeps as still right.
  List<DecaySignal> signalsFor(String noteId, {String? body}) {
    if (!on) return const [];
    final note = decayNoteOf(noteId, body: body);
    if (note == null || note.trashed) return const [];
    final found = [
      ...signalsOf(note, library, now: _clock(), staleMonths: _months()),
      ...?_remote[noteId]?.signals,
      if (_aiOn()) ...?_ai[noteId]?.signals,
    ];
    // A remote or AI line still in the page; the rest went with the words they were about.
    final lines = note.body.split('\n');
    final kept = [
      for (final signal in found)
        if (signal.line == null || !_asked.contains(signal.kind) || _stillThere(lines, signal)) signal,
    ];
    return withoutStillRight(note.body, kept);
  }

  /// The kinds found by a pass rather than made again from the page as it reads.
  static const Set<DecayKind> _asked = {DecayKind.github, DecayKind.figma, DecayKind.ai};

  bool _stillThere(List<String> lines, DecaySignal signal) => lines.any((line) => line.trim() == signal.quote);

  /// Asks GitHub and Figma about [noteId]'s links, then the AI where its switch is on and the page was flagged or is a
  /// docs page older than [aiAfterDays]. What they say is kept for the page as it reads now.
  Future<void> look(String noteId, {int aiAfterDays = 30}) async {
    if (!on || !_asking.add(noteId)) return;
    notifyListeners();
    try {
      final note = decayNoteOf(noteId);
      if (note == null || note.trashed) return;
      final now = _clock();
      final remote = await remoteSignalsOf(note, _lookups(), now: now);
      _remote[noteId] = _Found(note.body, remote);
      if (_aiOn() && _model().ready) {
        final signals = withoutStillRight(note.body, [...signalsOf(note, library, now: now, staleMonths: _months()), ...remote]);
        final old = note.docPage && now.difference(note.edited).inDays >= aiAfterDays;
        if (signals.isNotEmpty || old) {
          final ai = await aiSignalsOf(note, sourcesFor(note, signals), _model()).catchError((Object _) => const <DecaySignal>[]);
          // The AI's line where a signal already marks it says nothing more.
          final marked = {for (final s in signals) s.line};
          _ai[noteId] = _Found(note.body, [for (final s in ai) if (!marked.contains(s.line)) s]);
        }
      }
    } finally {
      _asking.remove(noteId);
      notifyListeners();
    }
  }

  /// What [signals]' sources say now, for the AI to read beside the page: each source note's title and first lines.
  List<DecaySource> sourcesFor(DecayNote note, List<DecaySignal> signals) {
    final out = <DecaySource>[];
    final seen = <String>{};
    for (final signal in signals) {
      final source = signal.source == null ? null : library.notes.where((n) => n.id == signal.source).firstOrNull;
      final says = source == null ? signal.reason : '${signal.reason}. It reads now: ${_opening(source.body)}';
      if (seen.add('${signal.key}|$says')) out.add(DecaySource(what: signal.key, says: says));
    }
    return out;
  }

  static String _opening(String body) {
    final words = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return words.length <= 600 ? words : '${words.substring(0, 600)}…';
  }

  /// Update with AI for [signals] on [noteId], its body [body] (the editor's): the edits proposed, none applied.
  Future<List<DecayEdit>> propose(String noteId, String body, List<DecaySignal> signals) async {
    final note = decayNoteOf(noteId, body: body);
    final model = _model();
    if (note == null || !model.ready) return const [];
    return proposeEdits(note, signals, sourcesFor(note, signals), model);
  }

  /// Every page that may be out of date, [where] it is one the list wants, most signals first.
  List<DecayPage> pages({bool Function(Note note)? where}) {
    if (!on) return const [];
    final out = <DecayPage>[];
    for (final note in _notes()) {
      if (note.inTrash || note.archivedAt != null || (where != null && !where(note))) continue;
      final signals = signalsFor(note.id);
      if (signals.isNotEmpty) out.add(DecayPage(note, noteTitle(note.body), signals));
    }
    out.sort((a, b) => b.signals.length != a.signals.length ? b.signals.length - a.signals.length : a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return out;
  }

  /// Forgets what GitHub, Figma and the AI said: Check now.
  void forget() {
    _remote.clear();
    _ai.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    changes?.removeListener(_libraryChanged);
    super.dispose();
  }
}

/// The app's one, put in place by the root (note_decay.dart [startNoteDecay]); null until then, and in a test that
/// makes none.
NoteDecay? noteDecay;
