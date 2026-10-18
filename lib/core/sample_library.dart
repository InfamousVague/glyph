/// A library to draw the home page over until the real one (the Rust core behind FFI, stage 3) arrives: the invented
/// notes the store screenshots are taken over, and the examples a fresh library starts with, behind the few
/// operations the home page performs.
///
/// Ports:
/// - `ghost-md-app-store-pack/tools/seed.mjs` `library()` and the workspaces of its `seed()`: [seedLibrary],
///   [seedWorkspaces]. Nobody in it is real: Sam, Ana and Ali are first names and nothing more.
/// - `src/app/core/seed.ts` `addStarterExamples` and `addSampleNote`, with the bodies of `core/starterNotes.ts`,
///   `core/boardNote.ts` and `core/sampleNote.ts`: [starterNotes].
///
/// What differs:
/// - The store is [NoteLibrary] (lib/core/library.dart, handed on from here for the files that found it here), with
///   [SampleLibrary] behind it in memory; the real one is lib/core/core_library.dart. A delete here hands back what it
///   took, and [NoteLibrary.restore] puts it back, for the screens from before the trash was a preference.
/// - seed.mjs pins its clock to ten on a Monday morning in London; [seedNow] is that wall clock on this device, so the
///   same notes fall in "Today" wherever the page is drawn.
/// - The sample note's picture is put in by whoever makes the note where pictures are kept ([sampleNoteWith], the
///   web's `samplePicture`); [sampleNoteBody] is the note without it, as the web makes it where one cannot be.
/// - The spoken notes' `segments` are left out, as seed.mjs's own iPhone library leaves them.
library;

import 'images.dart' show imageMarkdown;
import 'iphone_app.dart' show recordsVoice;
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'command_mutations.dart';
import 'library.dart';
import 'locale_dates.dart';
import 'native/core.dart';
import 'note.dart';
import 'workspaces.dart';

export 'library.dart' show NoteLibrary;

// ---- the store ---------------------------------------------------------------------------------------------------

/// [NoteLibrary] over a list held in memory: the store screenshots' library, and what a test draws a screen over.
/// It keeps the store's rules where a screen can meet them (a save over the revision it read, an id made once, a
/// pin that is not an edit, a command's write and its undo each held against the note as it was left), as the
/// browser half of `core/store.ts` does, and nothing of the library's files: a note here has no path, and a blank
/// one is a note like any other.
class SampleLibrary extends ValueNotifier<List<Note>> implements NoteLibrary {
  SampleLibrary(List<Note> notes, {int Function()? clock, Random? random})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _random = random ?? Random(),
        super(List.unmodifiable(notes));

  /// The store screenshots' library, at their moment ([seedNow]) unless [now] says another.
  factory SampleLibrary.seeded({int? now, int Function()? clock}) => SampleLibrary([...seedLibrary(now), ...tourExtraNotes(now)], clock: clock);

  /// A fresh library: the examples the app makes for a new person.
  factory SampleLibrary.starter({int? now, int Function()? clock}) => SampleLibrary(starterNotes(now ?? DateTime.now().millisecondsSinceEpoch), clock: clock);

  final int Function() _clock;
  final Random _random;

  /// The notes are here: there is never a first read to wait for.
  @override
  bool get loading => false;

  @override
  Future<void> load() => Future<void>.value();

  @override
  Note? noteOf(String id) {
    for (final note in value) {
      if (note.id == id) return note;
    }
    return null;
  }

  @override
  Future<Note?> get(String id) => Future<Note?>.value(noteOf(id));

  void _replace(String id, Note Function(Note note) change) {
    if (noteOf(id) == null) return;
    value = List.unmodifiable([for (final note in value) note.id == id ? change(note) : note]);
  }

  @override
  Future<void> pin(String id, {required bool pinned}) {
    _replace(id, (note) => note.copyWith(starred: pinned));
    return Future<void>.value();
  }

  @override
  Future<void> archive(String id, {required bool archived}) {
    final at = _clock();
    _replace(id, (note) => note.copyWith(archivedAt: () => archived ? at : null));
    return Future<void>.value();
  }

  @override
  Note? delete(String id) {
    final note = noteOf(id);
    if (note == null) return null;
    value = List.unmodifiable(value.where((each) => each.id != id));
    return note;
  }

  @override
  Future<void> destroy(String id) {
    delete(id);
    return Future<void>.value();
  }

  @override
  void restore(Note note) {
    if (noteOf(note.id) != null) return;
    value = List.unmodifiable([...value, note]);
  }

  Note _make(String id, String body, NoteSource source) {
    final at = _clock();
    final note = Note(id: id, body: body, createdAt: at, updatedAt: at, source: source);
    value = List.unmodifiable([note, ...value]);
    return note;
  }

  @override
  Note create(String body, {NoteSource source = NoteSource.editor}) {
    const letters = '0123456789abcdefghijklmnopqrstuvwxyz';
    String id;
    do {
      id = 'n-${List.generate(10, (_) => letters[_random.nextInt(letters.length)]).join()}';
    } while (noteOf(id) != null);
    return _make(id, body, source);
  }

  @override
  Future<Note> createNote(String body, {NoteSource source = NoteSource.editor, String? id}) {
    if (id == null) return Future<Note>.value(create(body, source: source));
    if (noteOf(id) != null) return Future<Note>.error(const CoreError(noteIdTaken));
    return Future<Note>.value(_make(id, body, source));
  }

  @override
  Future<Note> update(String id, String body, int expectedRevision) {
    final existing = noteOf(id);
    if (existing == null || existing.revision != expectedRevision) return Future<Note>.error(noteChangedError());
    final note = existing.copyWith(body: body, updatedAt: _clock(), revision: expectedRevision + 1);
    _replace(id, (_) => note);
    return Future<Note>.value(note);
  }

  /// The commands applied here, by their ids, each with the revision it left its note at and whether it was taken
  /// back: the page's `glyph-command-mutations` (`webCommands`), held in memory as the notes are.
  final Map<String, ({CommandMutationRequest request, int afterRevision, bool undone, int createdAt})> _commands = {};

  /// `applyCommandMutation`, the browser half: exactly the words previewed, if the previewed revision still exists.
  @override
  Future<CommandMutationResult> applyCommandMutation(CommandMutationRequest request) {
    final current = noteOf(request.noteId);
    final matches = request.beforeRevision == null
        ? current == null && request.beforeBody == null
        : current != null && current.revision == request.beforeRevision && current.body == request.beforeBody;
    if (!matches) return Future<CommandMutationResult>.value(CommandMutationResultConflict(current: current));
    final Note note;
    if (current == null) {
      note = _make(request.noteId, request.afterBody, request.source);
    } else {
      note = current.copyWith(body: request.afterBody, updatedAt: _clock(), revision: current.revision + 1);
      _replace(note.id, (_) => note);
    }
    _commands[request.mutationId] = (request: request, afterRevision: note.revision, undone: false, createdAt: _clock());
    return Future<CommandMutationResult>.value(CommandMutationResultApplied(mutationId: request.mutationId, note: note));
  }

  /// `undoCommandMutation`, the browser half: only while the command's exact result is still the note.
  @override
  Future<CommandUndoResult> undoCommandMutation(String mutationId) {
    final record = _commands[mutationId];
    if (record == null) return Future<CommandUndoResult>.value(const CommandUndoResultNotFound());
    if (record.undone) return Future<CommandUndoResult>.value(const CommandUndoResultAlreadyUndone());
    final request = record.request;
    final current = noteOf(request.noteId);
    if (current == null || current.revision != record.afterRevision || current.body != request.afterBody) {
      return Future<CommandUndoResult>.value(CommandUndoResultConflict(current: current));
    }
    Note? restored;
    final before = request.beforeBody;
    if (request.beforeRevision != null && before != null) {
      final back = restored = current.copyWith(body: before, updatedAt: _clock(), revision: record.afterRevision + 1);
      _replace(back.id, (_) => back);
    } else {
      value = List.unmodifiable(value.where((each) => each.id != current.id));
    }
    _commands[mutationId] = (request: request, afterRevision: record.afterRevision, undone: true, createdAt: record.createdAt);
    return Future<CommandUndoResult>.value(CommandUndoResultUndone(mutationId: mutationId, note: restored));
  }

  /// `latestCommandMutation`, the browser half: the newest command of the last ten minutes that was not taken back
  /// and whose note is still exactly what it left.
  @override
  Future<PendingCommandUndo?> latestCommandMutation() {
    final cutoff = _clock() - 10 * 60 * 1000;
    PendingCommandUndo? latest;
    for (final entry in _commands.entries) {
      final record = entry.value, request = record.request;
      if (record.undone || record.createdAt < cutoff || (latest != null && record.createdAt < latest.createdAt)) continue;
      final note = noteOf(request.noteId);
      if (note == null || note.body != request.afterBody || note.revision != record.afterRevision) continue;
      latest = PendingCommandUndo(mutationId: entry.key, noteId: request.noteId, kind: request.kind, createdAt: record.createdAt);
    }
    return Future<PendingCommandUndo?>.value(latest);
  }

  @override
  Future<Note> save(String id, String body) {
    final known = noteOf(id);
    return known == null ? Future<Note>.error(noteChangedError()) : update(id, body, known.revision);
  }

  @override
  Future<Note> apply(Note note) {
    value = List.unmodifiable([note, ...value.where((each) => each.id != note.id)]);
    return Future<Note>.value(note);
  }

  @override
  Future<void> refresh() async {
    // Nothing to read again: the notes are here.
  }
}

// ---- seed.mjs ----------------------------------------------------------------------------------------------------

/// Monday 28 September 2026, ten in the morning on this device: the shots' today (`NOW`).
final int seedNow = DateTime(2026, 9, 28, 10).millisecondsSinceEpoch;

/// The invented library the store screenshots are taken over (`library(now)`).
/// A DEBUG BUILD'S ONLY: notes the iPhone simulator's tour adds to the invented library for one start, for the 2.2
/// store pictures (lib/shell/phone_tour.dart, a script beginning `invented+`): a week with a calendar of to-dos and
/// a launch timeline. None unless that tour asked, which a release never does (`kDebugMode`).
List<Note> Function(int? now) tourExtraNotes = _noExtraNotes;

List<Note> _noExtraNotes(int? now) => const [];

List<Note> seedLibrary([int? now]) {
  final moment = now ?? seedNow;
  final today = DateTime.fromMillisecondsSinceEpoch(moment);
  int at(int daysAgo, int hh, int mm) => DateTime(today.year, today.month, today.day - daysAgo, hh, mm).millisecondsSinceEpoch;
  Note n(String id, String body, {required int createdAt, required int updatedAt, bool starred = false}) =>
      Note(id: id, body: body, createdAt: createdAt, updatedAt: updatedAt, starred: starred);

  final call = [
    '# Planning call with Sam',
    '',
    '## Summary',
    'What the call settled about the March launch.',
    '',
    '- Launch moves to the second week of March.',
    '- Sam: the press list by Friday.',
    '- Decided: no paid ads until the beta closes.',
    '- [ ] Book the venue before the 10th.',
    '- [ ] Send Sam the deck this week.',
    '',
    'We started with the launch date. Sam wants the second week of March so the press list has time to go out, and nobody argued with that.',
    '',
    'The beta is the other thing. It closes at the end of February, and until it does we hold off on paid ads. Ana thinks the numbers from the beta are what the launch post should lead with.',
    '',
    'I said I would book the venue before the 10th and send Sam the deck this week. Sam takes the press list.',
    '',
    'Last thing, the pricing page. Nothing decided. We look at it again on Thursday.',
  ].join('\n');

  final standup = [
    '# Monday standup',
    '',
    '## Summary',
    'Who has what this week, and the one thing blocking the beta.',
    '',
    '- Ana: the launch post draft by Wednesday.',
    '- Ali: the sign-up form, then the emails.',
    '- Decided: the beta closes on the 28th.',
    '- [ ] Ask Ali about the form.',
    '',
    'We went round the room. Ana has the launch post and wants it drafted by Wednesday so there is time to argue about it.',
    '',
    'Ali is on the sign-up form, then the emails after that. The form is what is blocking the beta right now.',
    '',
    'We agreed the beta closes on the 28th whatever state it is in.',
  ].join('\n');

  final weekend = [
    '# Weekend trip',
    '',
    'Three days at the cabin, the second weekend of October. **Book by Friday**, the deposit is 200. #cabin',
    '',
    '## Before we go',
    '',
    '- [ ] Book the cabin',
    '- [ ] Ask Sam about the dog',
    '- [x] Pick the weekend',
    '- [ ] Oil change for the car',
    '- Bottles of water [3/8]',
    '',
    'The ==cabin key== is under ||the third stone||. Saturday the lake, Sunday the long walk if it is dry.',
    '',
    '## Who brings what',
    '',
    '| Who | Brings |',
    '| --- | --- |',
    '| Sam | The tent |',
    '| Ali | Food for Saturday |',
    '| Me | The car, and the coffee |',
    '',
    '> The note you make on the way is the one you keep.',
    '',
    '## Where do we stay',
    '',
    '- ( ) Tent',
    '- (x) Cabin',
    '',
    '= 200 + 3 * 45',
  ].join('\n');

  final house = ['# House TODOs', '', '## Electrical', '', '- [ ] Replace the hall bulb', '- [x] Label the fuse box', '', '## Kitchen', '', '- [ ] Fix the leaking tap', '- [ ] Descale the kettle'].join('\n');
  final groceries = ['# Groceries', '', '- Oat milk', '- Eggs', '- Bread', '- The good coffee', '- Bin bags'].join('\n');
  final launch = [
    '# Launch week',
    '',
    'Second week of March. What is left is below; Sam has the photos and the press list.',
    '',
    '```board',
    'This week: pricing-page, beta-list, deck',
    'Waiting on Sam: photos, press-list',
    'Done: launch-date',
    '```',
    '',
    '## The work',
    '',
    '- [ ] Write the pricing page ^pricing-page',
    '- [ ] Email the beta list ^beta-list',
    '- [ ] Send Sam the deck ^deck',
    '- [ ] Get the photos back from Sam ^photos',
    '- [ ] The press list ^press-list',
    '- [x] Pick the launch date ^launch-date',
  ].join('\n');
  final portugal = ['---', 'title: "Portugal"', 'book: true', '---', '# Portugal', '', 'Ten days in October, written up a day at a time.', '', '- [[Packing]]', '- [[Lisbon, the first three days]]', '- [[The coast]]', ''].join('\n');
  final packing = ['# Packing', '', '- [ ] Adapter', '- [ ] Boots', '- [x] Passport', '- [ ] The small bag for the train'].join('\n');
  final lisbon = [
    '# Lisbon, the first three days',
    '',
    'The flat is above the bakery, which is either a good thing or a bad thing at six in the morning.',
    '',
    'Day one, the castle and the long way down. Day two, the tram to Belém. Day three, nothing planned.',
    '',
    '> [!TIP]',
    '> The number 28 tram is full by nine. Walk up, ride down.',
  ].join('\n');
  final coast = ['# The coast', '', 'Train to Cascais, then the bikes along the front to Guincho if the wind lets us.', '', '- [ ] Book the bikes the night before'].join('\n');
  final reading = ['# Reading list', '', '1. Piranesi', '2. The Peregrine', '3. The lamp book Ana mentioned'].join('\n');
  final flat = ['# Flat', '', '- [ ] Send the deposit', '- Keys on Tuesday', "- The landlord is Ana's cousin, which explains the price"].join('\n');
  final cabinCanvas = '---\ntitle: "Cabin weekend, laid out"\n---\n$_cabinCanvasJson\n';

  // Tickets and queries: a Product notebook of tickets, a ticket with its fields, and two notes whose ```query fences
  // draw the open tickets. Due days sit a few days past the seed's moment.
  final product = [
    '---',
    'title: "Product"',
    'book: true',
    'key: PRD',
    'statuses: [To do, In progress, In review, Done]',
    '---',
    '# Product',
    '',
    'What we are shipping for the launch.',
    '',
    '- [[Fix the sign-in loop]]',
    '- [[Pricing page copy]]',
    '- [[Release notes]]',
    '- [[Offline search]]',
    '',
  ].join('\n');
  String tkt(String id, String title, Map<String, String> fields, String words) =>
      ['---', 'type: ticket', 'id: $id', for (final field in fields.entries) '${field.key}: ${field.value}', '---', '# $title', '', words].join('\n');
  final prd11 = tkt(
    'PRD-11',
    'Fix the sign-in loop',
    {'status': 'In progress', 'assignee': 'Sam', 'priority': 'highest', 'due': '2026-09-30', 'estimate': '3', 'blocked-by': '"[[PRD-9]]"', 'labels': '[bug, auth]'},
    'Signing in on the phone sends you back to the sign-in page once the cookie has expired.\n\n- [x] Find where the cookie is dropped\n- [ ] Refresh it before it expires @sam\n- [ ] Test it on a slow network',
  );
  final prd10 = tkt('PRD-10', 'Pricing page copy', {'status': 'In review', 'assignee': 'Matt', 'priority': 'high', 'due': '2026-10-01', 'estimate': '1'}, 'Three plans, said plainly.');
  final prd12 = tkt('PRD-12', 'Release notes', {'status': 'To do', 'assignee': 'Matt', 'priority': 'medium', 'due': '2026-10-03', 'estimate': '1'}, 'What changed, in a line each.');
  final prd13 = tkt('PRD-13', 'Offline search', {'status': 'To do', 'assignee': 'Ana', 'priority': 'low', 'due': '2026-10-06', 'estimate': '5'}, 'Search every note with no network.');
  final sprint = ['# This sprint', '', '```query', 'from: tickets [[Product]]', 'where: status != Done', 'sort: priority, due', 'show: board', '```', ''].join('\n');
  final openTickets = [
    '# Open tickets',
    '',
    '```query',
    'from: tickets [[Product]]',
    'where: status != Done',
    'sort: priority, due',
    'columns: id, title, status, estimate',
    'total: estimate',
    'show: table',
    '```',
    '',
  ].join('\n');

  return [
    // The iPhone app records nothing yet, so its pictures show no tape and no meeting: the call and the standup are
    // notes typed up.
    n('call-sam', call, createdAt: at(3, 14, 5), updatedAt: at(3, 14, 41)),
    n('standup', standup, createdAt: at(0, 9, 2), updatedAt: at(0, 9, 20)),
    n('weekend', weekend, starred: true, createdAt: at(2, 20, 15), updatedAt: at(0, 8, 10)),
    n('house', house, createdAt: at(6, 11, 0), updatedAt: at(1, 18, 30)),
    n('groceries', groceries, createdAt: at(4, 8, 0), updatedAt: at(0, 7, 55)),
    n('launch', launch, createdAt: at(5, 10, 0), updatedAt: at(1, 12, 0)),
    n('portugal', portugal, createdAt: at(8, 21, 0), updatedAt: at(2, 21, 0)),
    n('packing', packing, createdAt: at(8, 21, 5), updatedAt: at(2, 21, 5)),
    n('lisbon', lisbon, createdAt: at(8, 21, 10), updatedAt: at(2, 21, 10)),
    n('coast', coast, createdAt: at(8, 21, 15), updatedAt: at(2, 21, 15)),
    n('reading', reading, createdAt: at(9, 22, 0), updatedAt: at(0, 8, 50)),
    n('flat', flat, createdAt: at(2, 9, 0), updatedAt: at(0, 9, 12)),
    n('cabin-canvas', cabinCanvas, createdAt: at(7, 16, 0), updatedAt: at(3, 16, 0)),
    n('product', product, createdAt: at(6, 9, 0), updatedAt: at(1, 11, 0)),
    n('prd11', prd11, createdAt: at(2, 14, 0), updatedAt: at(0, 9, 40)),
    n('prd10', prd10, createdAt: at(3, 10, 0), updatedAt: at(1, 16, 0)),
    n('prd12', prd12, createdAt: at(2, 11, 0), updatedAt: at(1, 11, 0)),
    n('prd13', prd13, createdAt: at(4, 15, 0), updatedAt: at(2, 15, 0)),
    n('sprint', sprint, createdAt: at(1, 9, 0), updatedAt: at(0, 9, 5)),
    n('open-tickets', openTickets, createdAt: at(1, 9, 10), updatedAt: at(0, 9, 10)),
  ];
}

/// The workspaces seed.mjs files the notes under: the work notes under Work, the house notes under Home.
WorkspaceSheet seedWorkspaces() => const WorkspaceSheet(
      list: [Workspace(id: 'work', name: 'Work', hue: 'moss'), Workspace(id: 'home', name: 'Home', hue: 'sea')],
      notes: {
        'call-sam': 'work',
        'standup': 'work',
        'launch': 'work',
        'product': 'work',
        'prd11': 'work',
        'prd10': 'work',
        'prd12': 'work',
        'prd13': 'work',
        'sprint': 'work',
        'open-tickets': 'work',
        'house': 'home',
        'groceries': 'home',
        'flat': 'home',
      },
    );

/// The canvas of "Cabin weekend, laid out", as `JSON.stringify(canvas, null, 2)` writes it.
const String _cabinCanvasJson = r'''
{
  "nodes": [
    {
      "id": "before",
      "type": "group",
      "x": -40,
      "y": -60,
      "width": 640,
      "height": 400,
      "label": "Before we go",
      "color": "5"
    },
    {
      "id": "book",
      "type": "text",
      "x": 0,
      "y": 0,
      "width": 260,
      "height": 110,
      "color": "4",
      "text": "# Book the cabin\n\nBy Friday. The deposit is **200**."
    },
    {
      "id": "pack",
      "type": "text",
      "x": 320,
      "y": 0,
      "width": 260,
      "height": 110,
      "text": "- [ ] Snacks\n- [ ] A charger for the drive\n- [x] The good coffee"
    },
    {
      "id": "sam",
      "type": "text",
      "x": 0,
      "y": 160,
      "width": 260,
      "height": 90,
      "color": "2",
      "text": "Ask Sam about the dog"
    },
    {
      "id": "kit",
      "type": "text",
      "x": 320,
      "y": 160,
      "width": 260,
      "height": 150,
      "text": "| Who | Brings |\n| --- | --- |\n| Sam | The tent |\n| Ali | Food for Saturday |\n| Me | The car, and the coffee |"
    },
    {
      "id": "days",
      "type": "text",
      "x": 720,
      "y": -40,
      "width": 380,
      "height": 120,
      "color": "6",
      "text": "```mermaid\nflowchart LR\n  F[Friday: drive up] --> S[Saturday: the lake]\n  S --> U[Sunday: the long walk]\n  U --> H[Home by dark]\n```\n"
    },
    {
      "id": "there",
      "type": "text",
      "x": 720,
      "y": 140,
      "width": 380,
      "height": 190,
      "color": "6",
      "text": "# The weekend\n\nSaturday the lake, Sunday the long walk if it is dry. Nothing planned for the evenings."
    },
    {
      "id": "trip",
      "type": "file",
      "x": 0,
      "y": 300,
      "width": 260,
      "height": 210,
      "file": "Weekend trip.md"
    }
  ],
  "edges": [
    {
      "id": "e1",
      "fromNode": "book",
      "toNode": "pack",
      "fromSide": "right",
      "toSide": "left",
      "label": "then"
    },
    {
      "id": "e2",
      "fromNode": "book",
      "toNode": "sam",
      "fromSide": "bottom",
      "toSide": "top"
    },
    {
      "id": "e3",
      "fromNode": "pack",
      "toNode": "kit",
      "fromSide": "bottom",
      "toSide": "top",
      "color": "2",
      "label": "who brings what"
    },
    {
      "id": "e4",
      "fromNode": "before",
      "toNode": "days",
      "fromSide": "right",
      "toSide": "left",
      "label": "and then"
    },
    {
      "id": "e5",
      "fromNode": "sam",
      "toNode": "trip",
      "fromSide": "bottom",
      "toSide": "top",
      "toEnd": "none"
    },
    {
      "id": "e6",
      "fromNode": "days",
      "toNode": "there",
      "fromSide": "bottom",
      "toSide": "top",
      "color": "6"
    }
  ]
}''';

// ---- the examples a fresh library starts with (core/seed.ts) ------------------------------------------------------

const List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
String _two(int n) => n.toString().padLeft(2, '0');
String _isoDay(DateTime at) => '${at.year}-${_two(at.month)}-${_two(at.day)}';

/// The example notebook: a ticket key, so its pages are tickets numbered EX-1 to EX-3, and its index
/// (`exampleNotebookBody`).
String exampleNotebookBody() => '---\ntitle: "Example project"\nbook: true\nkey: EX\n---\n# Example project\n\n'
    "A notebook with a ticket key: every page made from New ticket is a ticket, numbered EX-1, EX-2 and on. Tap a ticket's status to move it along.\n\n"
    '- [[Plan the first release]]\n- [[Fix the sign-in loop]]\n- [[Write the welcome page]]\n';

/// The three example tickets, EX-1 to EX-3, as they are written, in the notebook's order (`exampleTicketBodies`).
/// [today] is the day their due days are counted from.
List<String> exampleTicketBodies(DateTime today) {
  String due(int days) => _isoDay(DateTime(today.year, today.month, today.day + days));
  return [
    '---\ntype: ticket\nid: EX-1\nstatus: Done\nassignee: Alex\npriority: high\n---\n# Plan the first release\n\n'
        'What goes in the first release, and what waits for the second.\n\n- [x] List what the release needs\n- [x] Cut what can wait\n',
    '---\ntype: ticket\nid: EX-2\nstatus: In progress\nassignee: Sam\npriority: highest\ndue: ${due(2)}\n---\n# Fix the sign-in loop\n\n'
        'Signing in on the phone sends you back to the sign-in page once the cookie has expired.\n\n'
        'A ticket is a note: its properties are the panel above, kept in the note’s front matter. Tap a value to change it.\n\n'
        '- [ ] Write the failing test\n- [ ] Refresh the token once, not twice\n',
    '---\ntype: ticket\nid: EX-3\nstatus: To do\npriority: medium\ndue: ${due(7)}\nblocked-by: "[[EX-2]]"\n---\n# Write the welcome page\n\n'
        'The first page a new person sees. It waits on EX-2, and says so with a lock until that is done.\n\n- [ ] Draft the words\n- [ ] Pick a picture\n',
  ];
}

/// The example journal and its first entry, written at [at], as New entry writes them (`exampleJournal`). Its
/// heading is the template's `{{date}}`: the day in the phone's own order once it has said which
/// (core/locale_dates.dart: "Monday 28 September" on a British phone), and as an American page fills it until then.
({String journal, String entry, String entryTitle}) exampleJournal(DateTime at) {
  final title = '${_isoDay(at)} ${_two(at.hour)}.${_two(at.minute)}';
  final time = '${_two(at.hour)}:${_two(at.minute)}';
  return (
    journal: '---\ntitle: "Journal"\nbook: true\njournal: true\ntemplate: "# {{date}}\\n\\n**{{time}}** "\n---\n# Journal\n\n- [[$title]]\n',
    entry: '---\ntitle: "$title"\ndate: ${_isoDay(at)}T$time\n---\n# ${toldDate(at, DateForm.MMMMEEEEd) ?? '${_weekdays[at.weekday - 1]}, ${_months[at.month - 1]} ${at.day}'}\n\n'
        "**$time** The first entry. A journal keeps one for each time you write, named by the minute, and its page lists them by day. New entry starts the next from the journal's template.\n",
    entryTitle: title,
  );
}

/// The notes a fresh library starts with (`addStarterExamples`, then `addSampleNote`): the three tickets and their
/// notebook, the board, the journal's entry and then the journal, and the sample note, made last so it leads Recent.
/// Each is made a millisecond after the one before, as they were made one after another.
///
/// Without [examples], the sample note alone: what a fresh library gets until Advanced is chosen (GHST-103; Matt,
/// 2026-10-18: a simple install starts with the sample note only, "the tickets, board, notebook and journal come with
/// Advanced"). The examples are then [starterExamples], added when the choice is made.
List<Note> starterNotes(int now, {bool examples = true}) {
  final at = DateTime.fromMillisecondsSinceEpoch(now);
  final journal = exampleJournal(at);
  final bodies = [...exampleTicketBodies(at), exampleNotebookBody(), boardNoteBody, journal.entry, journal.journal, sampleNoteBody];
  const ids = ['starter-ex-1', 'starter-ex-2', 'starter-ex-3', 'starter-notebook', 'starter-board', 'starter-entry', 'starter-journal', 'starter-sample'];
  return [
    for (var i = 0; i < bodies.length; i += 1)
      if (examples || ids[i] == starterSampleId) Note(id: ids[i], body: bodies[i], createdAt: now + i, updatedAt: now + i),
  ];
}

/// The sample note's id among [starterNotes].
const String starterSampleId = 'starter-sample';

/// The starter notes that are not the sample: the three tickets and their notebook, the board, the journal and its
/// entry, for a library that began with the sample alone.
List<Note> starterExamples(int now) => [for (final note in starterNotes(now)) if (note.id != starterSampleId) note];

/// The example board (`core/boardNote.ts` `boardNoteBody()`): a note that is a working board.
const String boardNoteBody = r'''
# Launch week

A board is two ordinary things: this fence, which lays out the columns, and the list under it, each item ending with
a name after a `^`. The cards are those items. Tick one here and the to-do below is ticked; tap its words and you
land on the line; press and hold a card to drag it into another column.

```board
This week: pricing-page, beta-list
Waiting on Sam: photos
Done: launch-date
```

## The work

- [ ] Write the pricing page ^pricing-page
- [ ] Email the beta list ^beta-list
- [ ] Get the photos back from Sam ^photos
- [x] Pick the launch date ^launch-date
- [ ] Book the venue, which is not on the board at all

## Anything in a list can be a card

A name after a `^` is not only for to-dos. A bullet takes one, and so does a numbered step, which is how something
with nothing to tick gets onto a board: a question to ask, a thing to keep an eye on.

- Ask Sam which photos are cleared ^ask-sam
- The old pricing page, until the new one is up ^old-page

The name is also how the words point at the work: the pricing page is waiting on [[#^ask-sam]], and tapping that
goes to the line. One name, pointed at from the board and from the middle of a sentence.

## How to change it

- Press and hold a card, then drag it: into another column, or up and down its own.
- Move a card with the chevrons on it instead; the fence above is rewritten either way.
- Add one with the **+** on a column: it writes a new to-do into the note and puts the card in that column.
- Take a card off the board by taking its name out of the fence. The item stays in the note.
- Tap the fence itself to edit the columns as text: rename one, add one, reorder them.

A second board in the same note is another fence, and an item can sit on both.

```board
Someday: venue
```

- [ ] Find a venue for the party ^venue
''';

/// The bundled photograph the sample note and the example canvas show (`assets/sample-smoke.jpg`): smoke, by Jocelyn
/// Morales, from Unsplash under the Unsplash License. Kept among the library's pictures as the note is made, the way
/// a pasted picture is, so the note holds a real `![…](image/…)` line and not a special case.
const String sampleSmokeAsset = 'assets/sample/sample-smoke.jpg';

/// The sample note's body, with the picture's section when there is a picture to show (`sampleNoteBody(image)`):
/// [image] is its name among the library's pictures. Without one the note says nothing of a picture.
///
/// [voice] false is the note for a build that records nothing, null asks the platform ([recordsVoice]): an iPhone
/// is given [sampleNoteTyped], the same note without the words to say.
String sampleNoteWith(String? image, {bool? voice}) {
  final sampleNoteBody = (voice ?? recordsVoice) ? _spokenSampleNote : sampleNoteTyped();
  if (image == null || image.isEmpty) return sampleNoteBody;
  const after = '## Without typing';
  final picture = '## Pictures\n\nPaste one, or press and hold and choose Add image. It sits under its own line, and the line stays:\n\n${imageMarkdown(image, 'A wisp of smoke, by Jocelyn Morales')}\n\n';
  return sampleNoteBody.replaceFirst(after, '$picture$after');
}

const String _spokenSampleNote = sampleNoteBody;

final RegExp _sayIt = RegExp(r'^Say "[^\n]*?\.(?: |$)| Say "[^\n]*?\.(?= |$)', multiLine: true);

/// The sample note for a build that records nothing (the iPhone app; Matt, 2026-10-13): every mark is still taught
/// by what to type, and each sentence that says what to say aloud is left out, with the three other places the
/// note speaks of saying. Made from [sampleNoteBody], so a mark added there is here too.
String sampleNoteTyped() => sampleNoteBody
    .replaceFirst('Type a mark, or say its word while recording, and Ghost.md draws it.', 'Type a mark and Ghost.md draws it.')
    .replaceAll(_sayIt, '')
    .replaceFirst('> Say it now, and fix it after.', '> Write it now, and fix it after.')
    .replaceFirst('A[Say it] --> B[A note]', 'A[Write it] --> B[A note]');

/// The sample note (`core/sampleNote.ts` `sampleNoteBody(null)`): a short tutorial for formatting everything, one mark
/// at a time, here without its picture ([sampleNoteWith] puts it in).
const String sampleNoteBody = r'''
# How to format a note

A note is plain Markdown: words with a few marks around them. Type a mark, or say its word while recording, and Ghost.md draws it. The marks stay on the page, a little dimmed. Try each one here, then delete this note.

## Headings

Type `#` and a space for the note's name, `##` for a section, and more hashes, up to six, for smaller ones. Say "heading", or "subheading".

### Three hashes

#### Four

##### Five

###### Six

## Words

Two stars for **bold**, underscores for _italic_, three stars for ***both***, two tildes to ~~strike~~, and backticks for `code`. Say "bold", then "end bold"; italic works the same way. A backslash makes a mark mean itself: \*not italic\*.

Two pipes each side keep a secret, drawn as smoke until the caret is in it: ||the key is under the third stone||. Say "spoiler", then "end spoiler".

One caret each side raises part of a word, and one tilde lowers it: the 2^nd^ of June, H~2~O. Say "superscript", then "end superscript"; "subscript" works the same way.

## Ghost.md's own marks

Two of the same sign each side: ==highlight==, %%an aside%%, ??unsure?? (with a reason in brackets after it: ??the deposit??(ask Sam)), @@redact@@, ^^shout^^, and ++added++. A redaction is a bar of ink over its words, lifted while the caret is in them; the words are still in the note, and in the file a share gives, and where there is no caret to lift it, on a shared note's page or a card, the bar stays. A colour's name in brackets after a highlight changes its colour: ==the cabin key==(green). Say "highlight", then "end highlight"; the others work the same way.

## Effects

Words that move, each written as its emoji twice either side, so the note still says what it means in any other app. Heat bends the line above it, like air over a hot road:

- 🔥🔥Heat🔥🔥 goes bold, and the line above it wavers.
- ❄️❄️Frost❄️❄️ grows a rime over the edges of the letters.
- 🌊🌊Wave🌊🌊 bobs along the line.
- ✨✨Shimmer✨✨ catches a glint every few seconds.
- 👻👻Haunt👻👻 fades almost away, and back.

Say "heated", then "end heated"; "frosted", "wavy", "shimmering" and "haunted" work the same way. An effect lifts while the caret is in its words, so they edit as plain text, and it holds still when the phone is set to reduce motion.

## Lists

A dash for a point, indented for a smaller one. Say "bullet point".

- Milk
  - Oat, if they have it

A number and a dot for steps. Say "number one", "number two".

1. Wake up
2. Write it down

A dash and a box for a to-do; tap the box to tick it. Say "remember to", or "done task" for one that is done already. The heading above counts them.

- [ ] Book the cabin ^book-cabin
- [x] Call Sam ^call-sam

A caret and a name at the end of an item name it, so something else can point at it: [[#^book-cabin]]. Say "anchor", the name, then "end anchor".

Round brackets make a choice, and a tap picks one. Say "option", or "picked option" for the one you chose.

Where do we stay?
- ( ) Tent
- (x) Cabin

A count and a goal in square brackets is a counter: tap it to add one, hold it to take one away. Say "counter three of eight".

- Water [3/8]

An equals sign and a space at the start of a line work out the sum after them, and show its answer without writing it into the note. Say "calculate".

= $450 + 120 * 2

A hash against a word tags the line: #cabin. Say "hashtag", then the word.

## Quotes

A line that starts with `>`. Say "quote".

> The note you make on the way is the one you keep.

A quote that opens with `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]` is a callout. Say "info box", or "warning callout".

> [!TIP]
> Say it now, and fix it after.

A bar straight after the `>` keeps the line in smoke until the caret is in it. Say "hidden line".

>| The answer is forty-two.

## Links

Words in brackets and the address after: [Ghost.md](https://attack.fm/glyph). An address on its own line gets a card with the page's title:

https://attack.fm/glyph

Two square brackets each side link to another note by its name: [[Weekend trip]]. A name with no note yet is drawn dashed, and a tap makes that note. Say "note link", the name, then "end link".

A caret and a name in square brackets mark a footnote, and a line starting with the same mark says what it is: the deposit is four hundred[^sam]. Tap the mark to read it. Say "footnote", what it says, then "end footnote".

[^sam]: Sam said so.

Two section signs, `§§`, at the end of a line are the note's bookmark, and the note opens there. The bookmark button at the top of the note moves it to the line you are on. Say "bookmark this" at the end of a line.

## Tables

Pipes between cells and a row of dashes under the first. Or press and hold, choose Style, then Table. Tap a drawn table to change it.

| What | Where |
| :--- | ---: |
| Tent | Garage |
| Stove | Loft |

## A few more

A word, and its meaning on the next line after a colon, is a definition. Say "define deposit as what you pay up front".

Deposit
: what you pay up front

Dollar signs each side set maths apart, exactly as typed: $x^2 + y$. Say "maths", the formula, then "end maths".

A name between colons is its emoji: shipped :tada:. Say "emoji", then its name.

## Code

Three backticks above and below, with the language after the first three:

```js
const note = 'said, then written';
```

## Boards and diagrams

A block marked board lays items out as columns, by their names. These are the to-dos from Lists; tick one there and its card moves here.

```board
To do: book-cabin
Done: call-sam
```

A block marked mermaid is drawn as the diagram it describes. Tap it to change the words.

```mermaid
flowchart LR
  A[Say it] --> B[A note]
```

A canvas can sit in a note in a frame you can look around in: its name in `![[ ]]`, on a line of its own.

## A line across

Three dashes on a line of their own:

---

## Without typing

Press and hold on any words and choose Style to put one of these marks on them. Every mark is in the cheat sheet as well: tap the three dots at the top of any note, then Formatting cheat sheet.
''';
