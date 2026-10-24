part of 'ghost_root.dart';

/// What the root does to the library, as `App.tsx` does it: a note opened where it was left, made (a note, a
/// canvas, a page of a notebook, a ticket, a journal's entry said or written, your templates, the guide and the
/// examples, a shared link's copy), written from outside its own screen (a query's tick, a board's new ticket) and
/// renamed from its tab.
///
/// One of the files `_GhostRootState` is written in (lib/root/ghost_root.dart says which): its methods here are an
/// extension on it, in the same library, so each reads the root's own fields as it did when it stood in the class.
/// What is handed out to be called back and compared (a listener, a press a widget keeps) stays in the class,
/// where a method torn off twice is the same function.
extension _RootCommands on _GhostRootState {
  /// A note opened from the home page (`onOpen`): the tape being recorded opens the meeting screen, not the note,
  /// which has nothing in it yet but its title.
  void _openFromHome(AppShellState shell, String id) {
    final live = _voice?.live?.meetingStateNow();
    if (live != null && live.recording && live.noteId == id && (_capture?.showMeeting(false) ?? false)) return;
    _openWhereLeft(shell, id);
  }

  /// A cassette on the home page's shelf (Matt, 2026-10-24: "make tapping a cassette open the note at its tape"): the
  /// note at its top, where the tape is, and the tape playing, so the transcript has the page. The meeting being
  /// recorded now opens its recorder, as from the list.
  void _openTape(AppShellState shell, String id) {
    final live = _voice?.live?.meetingStateNow();
    if (live != null && live.recording && live.noteId == id) return _openFromHome(shell, id);
    shell.openNote(id, at: atTape);
  }

  /// A note opened from outside it (`openNoteWhereLeft`: the home page, All notes, the sidebar, a note's menu, a
  /// notification, an organization's page): a notebook goes back to the chapter it was left in
  /// (lib/book/book_spot.dart). A tab, Back and Forward show the note itself.
  void _openWhereLeft(AppShellState shell, String id) {
    final note = _library.noteOf(id);
    shell.openNote(note == null ? id : whereLeft(note, _shown, shell.shown, on: _stored).id);
  }

  /// The Ghost.md guide as a notebook (`onGuideBook`, `openSample`): read against the library as it is now, less
  /// the trash, so a second press opens the first; then opened in a tab of its own.
  Future<void> _openGuideBook() async {
    _closeSettings();
    try {
      // Signed in, a sync first, so a book added on another device is here before that is asked; a slow network
      // holds the press five seconds at most (`GUIDE_SYNC_WAIT_MS`).
      await _services?.engine?.syncWithin().then<void>((_) {}, onError: (Object _) {});
      await _library.refresh();
      final note = await addGuideBook(_library, outOfTrash(_library.value, _trash.value));
      await _library.refresh();
      if (mounted) _afterFrame((shell) => shell.openNote(note.id));
    } catch (_) {
      await _library.refresh().catchError((Object _) {});
      if (mounted) _say(context, '$guideTitle did not load. Try again.');
    }
  }

  /// The bundled smoke photograph kept as a picture of this device's, answering its name; null where a picture
  /// cannot be kept, and the sample is then made without one rather than not at all (core/seed.ts `samplePicture`).
  /// Kept as it is: the page shrinks it first, and it is small already.
  Future<String?> _samplePicture() async {
    final pictures = _pictures;
    if (pictures == null) return null;
    try {
      final data = await rootBundle.load(sampleSmokeAsset);
      final name = '${randomId('img')}.jpg';
      await pictures.keep(name, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      return name;
    } catch (_) {
      return null;
    }
  }

  /// One of Settings › About › Examples' notes made now and opened (App.tsx `openSample` over core/seed.ts's
  /// `addSampleNote`, `addBoardNote`, `addCanvasNote` and `addHowCanvas`): Settings goes, the note is written, and
  /// the app is on it. One that could not be written says so.
  VoidCallback _openExample(FutureOr<String> Function() body) => () => unawaited(() async {
        _closeSettings();
        try {
          final note = await _library.createNote(await body());
          await _library.refresh();
          if (mounted) _afterFrame((shell) => shell.openNote(note.id));
        } catch (_) {
          await _library.refresh().catchError((Object _) {});
          if (mounted) _say(context, 'That note could not be added. Try again.');
        }
      }());

  /// A copy of something shared with this person, from its link: saved into the library, then opened in a tab of
  /// its own. An invite link pasted where a share was asked for is held and asked about (`forkFromLink`). Throws
  /// what went wrong, for the + sheet to say; a build with no account has nothing to read a share with.
  Future<void> _forkFromLink(String link) async {
    final invite = readJoinLink(link);
    if (invite != null) return _joinFromLink(invite);
    final shares = _services?.shares;
    if (shares == null) throw StateError('This build has no service to read a shared link from.');
    final forked = await forkFromLink(link, shares: shares, notes: () async => _library.value, save: _library.createNote);
    if (forked is! ForkedCopy) return;
    await _library.refresh();
    if (!mounted) return;
    _afterFrame((shell) => shell.openNote(forked.note.id));
  }

  /// `ghostmd://note/<id>` (`openNoteFromLink`), the tap on "written up": a result still waiting is put into the
  /// note first, so the tap opens a note with its summary; then the notes are read again, and the note opened where
  /// it was left.
  ///
  /// The page's `landNativeResult` is its module's, there as soon as the page is. Here the summaries are voice's,
  /// made a moment after the notes are read, and a tap that started the app is in hand before them: the link waits
  /// for voice to be known ([_voiceKnown]), so the result is not skipped for want of something to land it with.
  /// Three seconds and no longer, which is what the app's start gives a phone to attach its half of voice
  /// (lib/root/voice_wiring.dart `inTime`): a phone slower than that opens the note as it is, and the write-up is
  /// put into it, open, when the queue is there (lib/ai/summaries.dart).
  Future<void> _openNoteFromLink(String id) async {
    await _voiceKnown.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    if (!mounted) return;
    await _voice?.summaries?.landNativeResult(id).then<void>((_) {}, onError: (Object _) {});
    await _library.refresh();
    final shell = _shell.currentState;
    final note = _library.noteOf(id);
    if (!mounted || shell == null || note == null || _trash.isTrashed(id)) return;
    shell.openNote(whereLeft(note, _shown, shell.shown, on: _stored).id);
  }

  static final Canvas _emptyCanvas = Canvas(nodes: const [], edges: const []);

  /// The note on screen, as the library has it.
  Note? get _onScreen {
    final id = _shell.currentState?.shown;
    return id == null ? null : _library.noteOf(id);
  }

  /// Once the shell has been handed the library as it is now: it opens only what it has.
  void _afterFrame(void Function(AppShellState shell) then) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shell = _shell.currentState;
      if (mounted && shell != null) then(shell);
    });
    if (mounted) _told(() {});
  }

  /// A note just made (`showMade`): filed in the workspace being looked at, and in [into] where it was made from an
  /// organization's +, and shown, in a tab of its own or, [within], in the tab of the note on screen. [fresh] is a
  /// new note of the person's own, whose blank page offers names and templates until they write in it.
  Note _showMade(String body, {Caret? caret, String? into, bool within = false, bool fresh = false}) {
    final note = _library.create(body);
    if (fresh) _untouched.markFresh(note.id);
    _workspaces.fileNewNote(note.id);
    if (into != null) _workspaces.fileNote(note.id, into);
    _afterFrame((shell) => within ? shell.openNoteWithin(note.id, caret: caret) : shell.openNote(note.id, caret: caret));
    return note;
  }

  /// `[[A title]]` tapped (`openTitle`): the note by that title, or a new note that starts with it as its heading.
  /// A link to a notebook, from outside it, goes back to where the notebook was left.
  void _openTitle(String title, [String? anchor]) {
    final shell = _shell.currentState;
    if (shell == null) return;
    final found = anchor == null ? _reads.titled(title) : null;
    final there = found == null ? null : whereLeft(found, _shown, shell.shown, on: _stored);
    if (there != null && found != null && there.id != found.id) return shell.openNote(there.id);
    _openTitleFrom(title, at: anchor);
  }

  /// [make] is what a note made for a title nobody has written yet starts as: a heading, or an empty canvas
  /// (`openTitleFrom`).
  void _openTitleFrom(String title, {String? at, String Function(String named)? make, bool within = false}) {
    final shell = _shell.currentState;
    if (shell == null) return;
    final found = _reads.titled(title);
    if (found != null) return within ? shell.openNoteWithin(found.id) : shell.openNote(found.id, at: at);
    final named = title.trim();
    if (named.isEmpty) return;
    _showMade(make?.call(named) ?? '# $named\n\n', within: within);
  }

  /// A title opened from inside a notebook: in the current tab's place. Inside a Templates notebook a line is a
  /// template's page, the marked note of its name, and never a note of the person's that shares it
  /// (`openTitleWithin`).
  void _openTitleWithin(String title) {
    final on = _onScreen;
    if (on != null && isTemplatesBody(on.body)) return _openTemplatePage(title);
    _openTitleFrom(title, within: true);
  }

  /// A template's page by its name, the oldest of it, made where there is none: marked, named by its `title:`, its
  /// heading left open for a note's name (`openTemplatePage`).
  void _openTemplatePage(String title) {
    Note? found;
    for (final note in _shown) {
      if ((note.archivedAt ?? 0) != 0 || !isTemplatePageBody(note.body) || !sameTitle(noteTitle(note.body), title)) continue;
      if (found == null || note.createdAt < found.createdAt) found = note;
    }
    if (found != null) return _shell.currentState?.openNoteWithin(found.id);
    _showMade(newTemplatePageBody(title), within: true);
  }

  /// A notebook's new page from a template, opened from its index in the notebook's tab (`openPageWithin`).
  void _openPageWithin(String title, String template) {
    final on = _onScreen;
    if (on != null && isTemplatesBody(on.body)) return _openTemplatePage(title);
    final notebook = on == null ? '' : noteTitle(on.body);
    _openTitleFrom(title, within: true, make: (named) => pageBody(named, template, notebook));
  }

  /// Every other note's title key, archived and in the Trash too (`takenTitles`).
  Set<String> get _takenTitles {
    final shown = _shell.currentState?.shown;
    return {
      for (final note in _library.value)
        if (note.id != shown) titleKey(noteTitle(note.body)),
    }..remove('');
  }

  /// A ticket made in a notebook, from its index's New ticket (`openTicketWithin`): the notebook's next key, read
  /// across every note the store has, the Trash's too, so no number is given twice; its workflow's first open
  /// status; and its template filled for it, or its title alone.
  void _openTicketWithin(String title, String notebook, NoteTemplate? template) {
    final id = nextTicketId(notebook, [for (final note in _library.value) note.body]);
    final words = template == null ? null : fillNoteTemplate(template, DateTime.now(), _takenTitles, nextId: id, title: title).body;
    _openTitleFrom(title, within: true, make: (named) => newTicketBody(named, id: id, statuses: statusesOf(notebook), words: words));
  }

  /// A canvas by that title opened from a notebook's index, made first if there is none (`openCanvasWithin`).
  void _openCanvasWithin(String title) => _openTitleFrom(title, within: true, make: (named) => canvasNoteBody(named, _emptyCanvas));

  /// A change to another note's words, from a query or a notebook's index (`tickFromQuery`, `moveFromQuery`): the
  /// note as the store has it now, changed, and the notes read again. A line or a note gone is left alone.
  Future<void> _writeNote(String id, NoteChange change) async {
    try {
      final note = await _library.get(id);
      final next = note == null ? null : change(note.body);
      if (note == null || next == null || next == note.body) return;
      await _library.update(id, next, note.revision);
      await _library.refresh();
    } catch (_) {
      // Another writer got there first: the query is drawn again from what the store has.
      await _library.refresh().catchError((Object _) {});
    }
  }

  /// A ticket typed at the + of a lane of a query's board (`addFromQuery`). Its notebook is the one `from: [[…]]`
  /// names, else the one the board's own note is in: the notebook's next key and its workflow, then the lane's value
  /// and what the query insists on, so it lands in the lane it was typed in. Its page goes in the notebook's index
  /// and it is filed where the notebook is. It is not opened. Answers true where the board's own note is the
  /// notebook, whose index the board's editor writes.
  Future<bool> _addFromQuery(TicketDraft draft, String title, String? from) async {
    final live = [
      for (final note in _shown)
        if ((note.archivedAt ?? 0) == 0) note,
    ];
    if (live.any((note) => sameTitle(noteTitle(note.body), title))) {
      _say(context, 'There is already a note called “$title”.');
      return false;
    }
    final link = draft.link;
    final linked = link == null ? null : live.where((note) => sameTitle(noteTitle(note.body), link)).firstOrNull;
    final board = from == null ? null : live.where((note) => note.id == from).firstOrNull;
    final notebook = linked != null && isBookBody(linked.body) ? linked : (board == null ? null : notebookFinder(live)(board));
    final id = notebook != null && notebookKey(notebook.body) != null ? nextTicketId(notebook.body, [for (final note in _library.value) note.body]) : null;
    var body = newTicketBody(title, id: id, statuses: statusesOf(notebook?.body));
    for (final (field, value) in draft.fields) {
      body = withProperty(body, field, value);
    }
    if (draft.labels.isNotEmpty) body = withProperty(body, 'labels', draft.labels);
    // `from: [[A note]]` that is no notebook lists the notes linking to it: so this one does.
    if (linked != null && linked.id != notebook?.id) body = '${body.replaceFirst(RegExp(r'\n*$'), '')}\n\n[[${noteTitle(linked.body)}]]\n';
    final made = await _library.createNote(body);
    final space = (notebook == null ? null : _workspaces.workspaceOf(notebook.id)) ?? (from == null ? null : _workspaces.workspaceOf(from));
    if (space != null) {
      _workspaces.fileNote(made.id, space.id);
    } else {
      _workspaces.fileNewNote(made.id);
    }
    final here = notebook != null && notebook.id == from;
    if (notebook != null && !here) {
      final fresh = await _library.get(notebook.id);
      if (fresh != null) await _library.update(fresh.id, withChapter(fresh.body, title), fresh.revision).then<void>((_) {}, onError: (Object _) {});
    }
    await _library.refresh();
    return here;
  }

  /// A journal's New entry (`newEntry`): a note named by the minute, started from the template chosen or the
  /// journal's own, its line put last in the journal's index, opened with the caret at its end: in the journal's
  /// tab from inside the journal, a tab of its own from anywhere else.
  Future<void> _newEntry(String journalId, [String? template, bool spoken = false]) async {
    if (spoken) return _spokenEntry(journalId);
    final within = _shell.currentState?.shown == journalId;
    final note = await _pages.newEntry(journalId, template: template);
    if (note == null) return;
    if (!mounted) {
      _pages.making.remove(note.id);
      return;
    }
    _workspaces.fileNewNote(note.id);
    // Being made until it is on screen: the take-back leaves it alone meanwhile.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pages.making.remove(note.id));
    _afterFrame((shell) => within ? shell.openNoteWithin(note.id, caret: const Caret.end()) : shell.openNote(note.id, caret: const Caret.end()));
    // Where it was written, when the journal keeps that: the tag waits for the entry's first own words.
    final book = _library.noteOf(journalId);
    if (book != null && journal.entryPlaceOf(book.body)) {
      unawaited(_places?.tagEntryIfWanted([note.id], (reviewing: false), introduce: _introduceEntries(noteTitle(book.body))));
    }
  }

  /// A journal's entry said aloud (`makeEntry` with `speak`): made with its template's last line taken off, and the
  /// capture aimed at it. Nothing said: the journal, from where the entry is taken back.
  Future<void> _spokenEntry(String journalId) async {
    final capture = _capture;
    if (capture == null) return;
    // A meeting holds the microphone: the way to it, and nothing made that its capture would leave behind.
    if (_voice?.live?.meetingStateNow()?.recording ?? false) {
      capture.showMeeting(false);
      return;
    }
    final made = await _pages.newSpokenEntry(journalId);
    if (made == null) return;
    final id = made.note.id;
    final book = _library.noteOf(journalId);
    try {
      if (!mounted) return;
      _workspaces.fileNewNote(id);
      await capture.start(
        false,
        noteId: id,
        entry: EntryAim(
          id: id,
          placing: made.placing,
          // Asked once the recorder has gone, never at the tap. Quiet over a locked phone.
          tag: _places == null || book == null || !journal.entryPlaceOf(book.body)
              ? null
              : ({required reviewing, required locked}) => WidgetsBinding.instance.addPostFrameCallback((_) {
                    unawaited(_places.tagEntryIfWanted([id], (reviewing: reviewing), quiet: locked, introduce: _introduceEntries(noteTitle(book.body))));
                  }),
          nothing: () async {
            final back = await _library.get(journalId).catchError((Object _) => null);
            return back == null ? const Screen.list() : ScreenNote(back);
          },
        ),
      );
    } finally {
      _pages.making.remove(id);
    }
  }

  /// The + sheet's row for a new entry (`entryRow`): in the journal on screen, or the journal of the entry on
  /// screen, before the one written in last.
  NewSheetEntry? _entryRow() {
    final journals = _reads.journals;
    if (journals.isEmpty) return null;
    final on = _onScreen;
    final place = on == null ? null : _reads.placeInBook(on);
    final chosen = journals.where((note) => note.id == on?.id).firstOrNull ??
        (place != null && place.journal ? journals.where((note) => note.id == place.book.id).firstOrNull : null) ??
        journals.first;
    final usual = journal.templateOf(chosen.body);
    final name = noteTitle(chosen.body);
    return NewSheetEntry(
      journal: name.isEmpty ? 'Untitled journal' : name,
      hint: journal.templateSentence(usual),
      usual: usual,
      // The usual row sends no template: the entry is made from the journal as the store has it now.
      onPress: (template) => unawaited(_newEntry(chosen.id, template)),
    );
  }

  /// What can be a page of a new notebook (`pageTitles`): every note's title but the notebooks' own, and none of a
  /// journal's entries, which belong to their journal.
  List<String> _pageTitles({bool books = true}) => [
        for (final note in _shown)
          if ((books || !isBookBody(note.body)) && !_reads.entryIds.contains(note.id) && noteTitle(note.body).trim().isNotEmpty) noteTitle(note.body),
      ];

  /// Your templates, the blank page's last card (`openTemplates`): the Templates notebook, opened in the blank
  /// note's tab. The first time there is none, and it is made with the built-ins as its pages, the pages first and
  /// the notebook last, so a press cut short makes only what is missing the next time. Not filed: they are the
  /// app's pages until the person changes them. A second press while it is being made is the same press.
  Future<void> _openTemplates() async {
    if (_seeding) return;
    _seeding = true;
    try {
      final plan = seedPlan(outOfTrash(_library.value, _trash.value));
      final open = plan.open;
      if (open != null) return _shell.currentState?.openNoteWithin(open.id);
      for (final template in plan.pages.reversed) {
        await _library.createNote(templatePageBody(template));
      }
      final book = await _library.createNote(plan.index!);
      await _library.refresh();
      _afterFrame((shell) => shell.openNoteWithin(book.id));
    } catch (_) {
      await _library.refresh().catchError((Object _) {});
      if (mounted) _say(context, 'Your templates could not be made. Try again.');
    } finally {
      _seeding = false;
    }
  }

  /// A canvas or a notebook renamed from its tab: its `title:` written, as the More sheet's name does. The note
  /// being read is its screen's, whose live words are what its next save writes, so it is asked and writes the name
  /// itself; any other tab has no screen holding it, and is a plain write (App.tsx `renameNote`).
  void _rename(String id, String title) {
    if (_shell.currentState?.shown == id) {
      final screen = openNoteScreen(_shell.currentContext, id);
      if (screen != null) return screen.renameHere(title);
    }
    final note = _library.noteOf(id);
    if (note == null) return;
    final named = withFrontMatterTitle(note.body, title);
    if (named != note.body) unawaited(_library.save(id, named).then<void>((_) {}, onError: (Object _) {}));
  }

  /// A new note (`newNote`): opened ready to type, the caret in line 1 and the editor focused, and fresh, so its
  /// blank page offers names and templates until the person writes in it.
  /// And it starts with where the person is, when Settings says so: the tag waits for the note's first words, so a
  /// note opened and left still leaves nothing behind. Only a note the person makes here: a canvas, a notebook, the
  /// guide, a shared link's copy and a note made for a title are the app's, and are not tagged. Where a fix is
  /// expected its map's box is held first (`willLocate`), so the card arriving never moves line 1.
  /// [template] (the home screen's Checklist: "A checklist") makes it as that template's card on its blank page does
  /// (NoteScreen `startFrom`): filled, its name settled against every other note's, the caret in its first open line,
  /// and its record kept, so a note left without a word of the person's own is taken back.
  void _new([String? into, NoteTemplate? template]) {
    Note make() {
      if (template == null) return _showMade('', caret: const Caret.at(0), fresh: true, into: into);
      final now = DateTime.now();
      final filled = fillNoteTemplate(template, now, _takenTitles);
      final note = _showMade(filled.body, caret: Caret.at(filled.caret), fresh: true, into: into);
      _untouched.remember(note.id, UntouchedRecord(title: filled.title, words: filled.words, at: now.millisecondsSinceEpoch));
      return note;
    }

    final places = _places;
    if (places == null) {
      make();
      return;
    }
    unawaited(() async {
      // Asked first, and not waited on for long: the phone answers in a turn, and the box is there from the first
      // frame.
      final expected = await places.willLocate().timeout(const Duration(milliseconds: 300), onTimeout: () => false).then<bool>((will) => will, onError: (Object _) => false);
      if (!mounted) return;
      final note = make();
      if (expected) places.holdFor([note.id]);
      await places.tagNewNotesIfWanted([note.id], (reviewing: false), introduce: _introduceLocation);
    }());
  }

  /// A canvas from the + (`newCanvas`).
  void _newCanvas([String? into]) => _showMade(canvasNoteBody('Untitled canvas', _emptyCanvas), into: into);
}
