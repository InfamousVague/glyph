part of 'ghost_root.dart';

/// Voice and the AI as the root holds them: made once the root is up (the recorder over the core's Whisper and the
/// phone's microphone, the capture's route, the models, whether the AI can run, the gists' runner, the fills'
/// queue), and what the screens ask of them: a note's own Speak, the meeting's screen, a desk's AI, and Settings'
/// Recording and AI pages.
///
/// One of the files `_GhostRootState` is written in (lib/root/ghost_root.dart says which). The fields these fill
/// (`_voice`, `_capture`, `_availability`) and what each is listened to by (`_voiceChanged`,
/// `_modelsChanged`, `_aiChanged`) are the class's own: a listener added here is taken off there,
/// by the same function.
extension _RootVoice on _GhostRootState {
  /// Voice made, once the root is up (lib/root/voice_wiring.dart): the recorder, where a capture begins and ends
  /// (lib/root/capture_route.dart), what it is listened to by, then the AI over it, then the launch a side key or
  /// a meeting already recording asked for.
  Future<void> _speakUp() async {
    // The phone's half of voice, or, where it had not attached by the first frame, that half when it has
    // (lib/main.dart): the recorder and the AI are made then, where the run had neither.
    final making = widget.voiceMaking ?? (widget.voice == null ? await widget.voiceLater : null);
    if (widget.voiceWhen case final ready?) await ready;
    if (!mounted) return;
    final Voice? voice;
    try {
      voice = widget.voice ??
          (making != null && _real
              ? await Voice.make(
                  making,
                  library: _library,
                  kept: _stored,
                  published: (id) => _services?.shares?.linkFor(id) != null,
                  isTrashed: _trash.isTrashed,
                  syncNow: _services?.engine?.syncNow,
                  syncSettled: _services?.engine?.syncSettled,
                  // "A meeting was written up", in the bell.
                  record: feedRecord(() => _services),
                )
              : null);
    } catch (failure) {
      debugPrint('[ghost] voice could not be made: $failure');
      return _voiceKnown.complete();
    }
    if (voice == null) return _voiceKnown.complete();
    if (!mounted) return voice.dispose();
    final models = voice.models;
    final recorder = voice.recorder;
    final capture = CaptureRoute(
      voice: voice,
      world: CaptureRouteWorld(
        screen: () => _shell.currentState?.screen ?? const Screen.list(),
        setScreen: (next) => _shell.currentState?.show(next),
        refresh: _library.refresh,
        flushDeletes: () => _made?.flushDeletes() ?? Future<void>.value(),
        clearStage: () {
          FocusManager.instance.primaryFocus?.unfocus();
          _guide?.hide();
          // A recording takes the microphone: an ask being said to Claude is let go first.
          _talk?.cancel();
          if (mounted) {
            _told(() {
              _settings = false;
              _newSheet = false;
              _bookSheet = null;
            });
          }
        },
        say: (message) {
          if (mounted) _say(context, message);
        },
        getNote: _library.get,
        createNote: (body, {required source}) => _library.createNote(body, source: source),
        deleteNote: _library.destroy,
        fileNewNote: _workspaces.fileNewNote,
        untouched: _untouched,
        tooSoon: () => _guide?.onReadingPage() ?? false,
        // The phone's assistant talks to Claude where Claude can answer here (lib/root/root_claude.dart).
        askAi: _assistantTalk,
        sayTooSoon: () => _guide?.sayTooSoon(),
        // Once the note's screen is up and watches its tag, so the tag goes through its editor and not under it.
        tagNew: _places == null
            ? null
            : (id, {required reviewing, required quiet}) => WidgetsBinding.instance.addPostFrameCallback((_) {
                  unawaited(_places.tagNewNotesIfWanted([id], (reviewing: reviewing), quiet: quiet, introduce: _introduceLocation));
                }),
      ),
    );
    _told(() {
      _voice = voice;
      _capture = capture;
    });
    _voiceKnown.complete();
    // The phone's write-up changed a note: the note's own screen, if it is open, takes it.
    _unhearRecordings = voice.summaries?.onRecordingChanged((id) {
      for (final heard in _recordingHeard.toList()) {
        heard(id);
      }
    });
    // The meeting's state, for the row that says "Recording now", and the models, for Settings' AI page.
    _unwatchMeeting = voice.live?.subscribe(_voiceChanged);
    voice.live?.canNotify.addListener(_voiceChanged);
    voice.live?.canNotifyNow();
    models?.addListener(_modelsChanged);
    // The voice model's fetch, for the line above the notes: the line follows its fetch by itself, and the home
    // page is drawn again only when there is a line where there was none (`_voiceModelLine`).
    recorder.voiceModel.addListener(_tick.tell);
    _voiceLife = AppLifecycleListener(onStateChange: (state) {
      recorder.lifecycle(state);
      if (state == AppLifecycleState.resumed) {
        unawaited(models?.refresh());
        gistsCameBack();
      }
    });
    await _aiUp(voice);
    await voice.start(
      // A better-words pass landed: a tag that waited for it may land too.
      notesChanged: () {
        unawaited(_library.refresh().catchError((Object _) {}));
        _settleTags();
      },
      // A summary landed with the app on screen: said, with the way to the note.
      summarized: (done) {
        if (!mounted) return;
        // `Summarized “${title}”`, for ten seconds, and Open goes to the note where it was left.
        GlacierToast.of(context).toast(
          message: Text('Summarized “${done.title}”'),
          duration: const Duration(seconds: 10),
          action: GlacierToastAction(
            label: 'Open',
            onPress: () {
              final shell = _shell.currentState;
              if (shell != null) _openWhereLeft(shell, done.id);
            },
          ),
        );
      },
    );
    // Voice has started: what it can do here (a meeting, the computer's sound) is read again.
    _voiceChanged();
    // The launch, once the notes are read: the side key's capture in a build with the assistant, or the meeting
    // already being recorded.
    await _notesRead.future;
    if (mounted) capture.boot();
  }

  /// The AI, once voice has made its engine the app's: whether it can run here, the phone as the strip's card
  /// names it, the gists' runner and the fills' queue.
  Future<void> _aiUp(Voice voice) async {
    if (!engine.aiBackend.available || voice.models == null) return;
    // Who signs a note beside the AI.
    ai_start.noteOwner = () => _services?.session?.handle;
    final availability = AvailabilityController(models: voice.models)..addListener(_voiceChanged);
    final device = await engine.readDevice();
    if (!mounted) return availability.dispose();
    final ram = device?.totalRamBytes;
    _told(() {
      _availability = availability;
      _deviceFacts = DeviceFactsController(cores: device?.cores, memoryGb: ram == null ? null : ram / 1e9);
    });
    _aiReady.value = true;
    // The gists step aside for the recorder and a review, and are written only with the app on screen.
    _stopGistHold = voice.recorder.refining?.onRefineHold(pauseGists);
    gistVisible = () => WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    // With no model on the phone the runner asks nothing: it looks again when one is there (a download ended).
    final models = voice.models!;
    _stopGistModels = wakeGistsOn(models, () => presentIds(models.models));
    // The fills' queue: a press run to its end and landed, in the open note or a closed one.
    _stopFills = startFills(
      (said) {
        if (!mounted) return;
        final action = said.action;
        GlacierToast.of(context).toast(
          message: Text(said.message),
          duration: said.duration == null ? null : Duration(milliseconds: said.duration!),
          action: action == null ? null : GlacierToastAction(label: action.label, onPress: action.onPress),
        );
      },
      (id) => _shell.currentState?.openNote(id),
      getNote: _library.get,
      // A write another writer won says so in the queue's own words.
      updateNote: (id, body, expectedRevision) async {
        final now = await _library.get(id);
        if (now == null) throw StateError('The note was deleted.');
        if (now.revision != expectedRevision) throw StateError('The note changed: its revision is another.');
        return _library.update(id, body, expectedRevision);
      },
      syncNow: _services?.engine?.syncNow,
      // `navigator.onLine` and the window's `online`: the parked lookups go on when a connection is back.
      onLine: widget.connection == null ? null : () => widget.connection!.onLine,
      onOnline: widget.connection?.onOnline,
      visible: () => WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
  }

  /// What a desk's AI stands on (lib/root/note_desk.dart `NoteAiWorld`); null until there is an engine.
  NoteAiWorld? _aiWorld() {
    final availability = _availability;
    final voice = _voice;
    if (availability == null || voice == null) return null;
    final refining = voice.recorder.refining;
    final summaries = voice.summaries;
    return NoteAiWorld(
      availability: availability,
      deviceFacts: _deviceFacts,
      reviewHost: refining == null
          ? null
          : ReviewHost(
              getNote: _library.get,
              listNotes: () async => _library.value,
              updateNote: (id, body, expectedRevision) async {
                await _library.update(id, body, expectedRevision);
              },
              enqueueRefine: refining.enqueueRefine,
              holdRefining: refining.holdRefining,
              keepBetterPhrases: refining.keepBetterPhrases,
              listenAgain: refining.listenAgain,
            ),
      openForSummaries: summaries?.openForSummaries,
      // Settings on AI with the Model card lit, where a model is fetched (App.tsx `setToModel`, which the sheet
      // reads as `{ id: 'ai', setting: 'Model' }`).
      onGetModel: () => _told(() {
        _settings = true;
        _settingsPage = SettingsTarget('ai', setting: 'Model', nonce: DateTime.now().microsecondsSinceEpoch);
      }),
      // The tape's real kind: a meeting's write-up for a meeting, a recording's otherwise.
      summarize: summaries == null
          ? null
          : (id, replace) => summaries.enqueueSummary(id, preferences.value.meetings.containsKey(id) ? SummaryKind.meeting : SummaryKind.recording, replace: replace),
      summaryEdited: (id, body) {
        final section = summarySection(body, keptText(id));
        return section != null && !summaryUnchanged(id, section.text);
      },
      opened: (id, ai) {
        if (ai == null && _noteAiId != id) return;
        _noteAi?.removeListener(_aiChanged);
        _noteAi?.reviewStage.removeListener(_aiChanged);
        _noteAiId = ai == null ? null : id;
        _noteAi = ai;
        ai?.addListener(_aiChanged);
        ai?.reviewStage.addListener(_aiChanged);
        _aiChanged();
      },
    );
  }

  /// A note's own Speak (`speakInto`). A journal's is a new entry said aloud. An entry nobody has written in is
  /// spoken into where its template was left open: the line it was left open with is taken off and put back before
  /// the words, so it still starts with its time; said nothing, the entry is put back as it was made. Any other
  /// note is spoken into as any note is.
  Future<void> _speakInto(String id) async {
    final capture = _capture;
    if (capture == null) return;
    final note = _library.noteOf(id) ?? await _library.get(id).catchError((Object _) => null);
    if (note != null && isJournalBody(note.body)) return _newEntry(id, null, true);
    final fresh = _untouched.recordOf(id)?.journalId != null ? await _library.get(id).catchError((Object _) => null) : null;
    // A meeting holds the microphone: the capture opens the meeting instead, and the entry is left as it was made.
    if (fresh == null ||
        !_untouched.isUntouched(id, fresh.body, recordingMs: fresh.recordingMs, starred: fresh.starred, archivedAt: fresh.archivedAt) ||
        (_voice?.live?.meetingStateNow()?.recording ?? false)) {
      return capture.start(false, noteId: id);
    }
    final head = fresh.body.substring(0, frontMatterOffset(fresh.body));
    final filled = fresh.body.substring(head.length);
    final (:base, :placing) = openEnd(filled);
    if (base != filled) {
      await _library.update(id, '$head$base', fresh.revision).then<void>((_) {}, onError: (Object _) {});
      _untouched.setWords(id, base);
    }
    await capture.start(
      false,
      noteId: id,
      entry: EntryAim(
        id: id,
        placing: placing,
        nothing: () async {
          final now = await _library.get(id).catchError((Object _) => null);
          if (now == null) return const Screen.list();
          if (base == filled) return ScreenNote(now);
          final back = await _library.update(id, '$head$filled', now.revision).catchError((Object _) => now);
          _untouched.setWords(id, filled);
          return ScreenNote(back);
        },
      ),
    );
  }

  /// What the meeting's screen asks of the phone and the app (lib/capture/ui/meeting_screen.dart).
  MeetingScreenHost _meetingHost(Voice voice, MeetingLive live) {
    final service = voice.service;
    void quietly(Future<void>? asked) => unawaited(asked?.then<void>((_) {}, onError: (Object _) {}));
    return MeetingScreenHost(
      isLocked: () => voice.locked,
      endCapture: (leave) => quietly(service?.endCapture(leave: leave)),
      stopMeeting: () => quietly(service?.stopMeeting()),
      discardMeeting: () => quietly(service?.discardMeeting()),
      // The phone's own answer (`ghost_md/meeting` `requestNotifications`: allowed, asked or blocked), which the
      // screen waits for: a phone that blocks notifications outright showed no prompt, and is not marked as asked.
      requestNotifications: () => askToNotify(service, live),
      deleteNote: _library.destroy,
      dropSummary: (id) => voice.summaries?.dropSummary(id),
      forgetMeeting: (id) => preferences.update((now) => now.copyWith(meetings: {...now.meetings}..remove(id))),
    );
  }

  /// What Settings' Recording and AI pages ask of voice (settings/RecordingPane.tsx, AiPane.tsx): the models on
  /// this phone with Get and Remove, the Meetings card where the phone has the service, and the room the tapes
  /// on this device take, said from their lengths (settings/tapes.ts: 16 kHz, 16-bit, mono is 32 bytes a
  /// millisecond).
  SettingsFeatures _features(AccountServices? services) {
    final voice = _voice;
    final wayIn = services == null ? noServiceWayIn : null;
    // Developer's two benches, over everything (diag/WispBench.tsx, diag/SceneBench.tsx).
    void smoke() => unawaited(showWispBench(context));
    void scene(String readings) => unawaited(showSceneBench(context, readings, scene: scenePlay));
    // Starting over (lib/core/reset.dart over lib/root/reset_wiring.dart): only where the app can be built anew.
    final restart = widget.restart;
    final reset = restart == null
        ? null
        : ({required bool models}) => resetLocalData(
              resetGroundFor(
                invoke: _real ? widget.core : null,
                services: _services,
                recordingNow: () => _voice?.live?.state?.recording ?? false,
                kept: () => _stored,
                restart: restart,
                teamDocsIn: widget.account?.dataDir,
              ),
              models: models,
            );
    // Test results: the report this build carries, and the fingerprint of the code the build was made from.
    final tests = _builtReport.value;
    if (voice == null) {
      return SettingsFeatures(onWayIn: wayIn, onSmokeBench: smoke, onPlayScene: scene, onReset: reset, libraryFolder: _libraryFolder, backup: _backups, export: _export, importer: _importer, ghostex: _ghostex, places: _places, testReport: tests, testBuildSource: buildSource);
    }
    final models = voice.models;
    final present = models == null ? const <String>{} : presentIds(models.models).toSet();
    final download = models?.download;
    final (:bytes, :old) = _tapeFacts;
    final remove = voice.removeAudio;
    final service = voice.service;
    final live = voice.live;
    return SettingsFeatures(
      onWayIn: wayIn,
      onSmokeBench: smoke,
      onPlayScene: scene,
      onReset: reset,
      libraryFolder: _libraryFolder,
      backup: _backups,
      export: _export,
      importer: _importer,
      ghostex: _ghostex,
      places: _places,
      testReport: tests,
      testBuildSource: buildSource,
      models: models == null
          ? null
          : SettingsModelsState(
              present: present,
              running: modelFor(present, preferences.value.formatModel),
              downloading: download?.id,
              received: download?.received ?? 0,
              total: download?.total ?? 0,
              problem: models.problem,
              cannotRun: {
                for (final id in present)
                  if (cannotRun(id)) id,
              },
            ),
      onGetModel: models == null ? null : (id) => unawaited(models.fetch(id)),
      onRemoveModel: models == null ? null : (id) => unawaited(models.remove(id)),
      meetings: service != null && voice.canMeet,
      canNotifyMeetings: live?.canNotify.value ?? false,
      // False where the phone blocks it, which Settings then says: no dialog changes that.
      onAllowMeetingNotices: service == null || live == null ? null : () async => await askToNotify(service, live) != NotificationsAnswer.blocked,
      meetingSound: voice.sound?.supported ?? false,
      meetingSoundWhy: voice.sound?.reason,
      tapes: bytes,
      // "Your tapes are being counted.", until the notes have been read for the first time.
      countingTapes: !_read,
      oldTapes: old.length,
      onCountTapes: () => unawaited(_tapes.ask(_library.value).then<void>((_) {
        if (mounted) _told(() => _tapesAt += 1);
      })),
      onRemoveOldAudio: remove == null
          ? null
          : () async {
              final removed = await remove(old);
              _tapesAt += 1;
              _changed();
              return removed.length;
            },
    );
  }
}
