import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../account/ui_state.dart';
import '../aside/aside.dart';
import '../aside/aside_panel.dart';
import '../ai/available.dart' show AvailabilityController, modelFor, presentIds;
import '../ai/backend.dart' as engine show aiBackend, readDevice;
import '../ai/fills/queue.dart' show resumeParked, startFills;
import '../ai/note_ai.dart' show NoteAi;
import '../ai/note_review.dart' show ReviewHost;
import '../ai/start.dart' as ai_start;
import '../ai/summaries.dart' show SummaryKind;
import '../ai/summary_keep.dart' show keptText, summaryUnchanged;
import '../ai/summary_text.dart' show summarySection;
import '../ai/support/runnable.dart' show cannotRun;
import '../art/art.dart';
import '../book/book_spot.dart' show whereLeft;
import '../book/entry_starts.dart' show pageBody;
import '../book/journal.dart' as journal;
import '../book/template_picker.dart' show EntryPlaceDevice;
import '../core/location.dart' show Locations, Locator, PlaceLookup;
import '../core/films.dart' show Films;
import '../core/phone_pictures.dart' show corePictureAdopter;
import '../core/place_tags.dart';
import '../editor/items/field_menu.dart' show DayPicker;
import '../guide/guide_models.dart' show GuideModels, PhoneGuideModels;
import '../editor/media/map_card.dart' show MapTilesBuilder;
import '../book/journal_view.dart' show JournalPages;
import '../book/new_book_sheet.dart';
import '../book/tickets.dart';
import '../academy/academy_screen.dart';
import '../canvas/json_canvas.dart' show Canvas, canvasNoteBody;
import '../capture/meeting_live.dart' show MeetingLive;
import '../capture/place.dart' show Placing;
import '../capture/ui/capture_screen.dart';
import '../capture/ui/meeting_screen.dart';
import '../capture/voice_model.dart';
import '../commands/app_commands.dart';
import '../commands/command_bar.dart';
import '../comments/ask.dart';
import '../core/backup.dart' show Backups;
import '../core/book.dart';
import '../core/canvas_body.dart';
import '../core/core_library.dart';
import '../core/export_all.dart' show ExportAll;
import '../core/front_matter.dart' show frontMatterOffset;
import '../core/images.dart';
import '../core/iphone_app.dart';
import '../core/kept_trash.dart';
import '../core/library_files.dart' show LibraryFiles;
import '../core/library_folder.dart' show LibraryFolder;
import '../core/link_preview.dart' show KeptLinkPreviews, LinkOpener, LinkPreviewFetch;
import '../core/kept_workspaces.dart';
import '../core/native/core.dart';
import '../core/native/files.dart';
import '../core/native/ghost_core.dart' show GhostCore;
import '../core/note.dart';
import '../core/note_folders.dart';
import '../core/note_text.dart';
import '../core/preferences.dart';
import '../core/properties.dart';
import '../core/query/query.dart' show TicketDraft;
import '../core/reset.dart' show resetLocalData;
import '../core/sample_library.dart';
import '../core/stored.dart';
import '../core/template.dart' show openEnd;
import '../core/trash.dart';
import '../core/untouched.dart';
import '../core/updates.dart';
import '../core/versions_record.dart';
import '../core/versions_store.dart';
import '../core/workspaces.dart';
import '../diag/scene_bench.dart' show showSceneBench;
import '../diag/wisp_bench.dart' show showWispBench;
import '../editor/queries/queries.dart' show NoteChange;
import '../format/device_facts.dart' show DeviceFactsController;
import '../format/gist.dart' show Gists, gistVisible, gistsCameBack, pauseGists;
import '../guide/guide.dart';
import '../guide/guide_state.dart';
import '../guide/guidebook.dart';
import '../home/home_layout.dart';
import '../home/home_screen.dart';
import '../home/note_peek.dart' show PeekPictures;
import '../launch/launch_screen.dart';
import '../note/note_builder.dart';
import '../note/open_screen.dart';
import '../note/note_screen.dart' show withFrontMatterTitle;
import '../notes/all_notes_screen.dart';
import '../notes/new_sheet.dart';
import '../notes/note_actions.dart';
import '../notes/note_menu.dart';
import '../notes/note_templates.dart';
import '../notes/own_templates.dart' hide templateOf;
import '../notes/note_tree.dart';
import '../notes/notes_drawer.dart';
import '../notes/notices.dart' as notices;
import '../notes/notifications_drawer.dart';
import '../notes/workspace_sheet.dart';
import '../orgs/join_links.dart' show readJoinLink;
import '../orgs/ui/fed_notifications.dart';
import '../orgs/ui/join_sheet.dart';
import '../orgs/ui/new_organization_sheet.dart';
import '../orgs/ui/org_news.dart';
import '../home/home_organizations.dart' show OrgPresence;
import '../live/presence.dart' show Seen;
import '../orgs/types.dart' show OrgRow;
import '../orgs/ui/organization_log.dart';
import '../orgs/ui/organization_screen.dart';
import '../plugins/claude/claude.dart' show claudeHandle;
import '../plugins/registry.dart' show plugins;
import '../settings/organization_sheet.dart';
import '../settings/settings_screen.dart';
import '../scene/at_work.dart';
import '../settings/settings_sheet.dart';
import '../settings/tapes.dart' show oldTapes, tapeBytes;
import '../settings/tapes_here.dart';
import '../share/app_links.dart';
import '../shell/account_gate.dart';
import '../shell/app_shell.dart';
import '../shell/screen.dart';
import '../shell/top_bar.dart';
import '../shell/wide_screen.dart' show mousePointer, splitFits;
import '../tapes/player.dart' show TapePlayer;
import 'account_wiring.dart';
import 'capture_route.dart';
import 'desktop_wiring.dart';
import 'library_reads.dart';
import 'note_desk.dart';
import 'reset_wiring.dart';
import 'scene_play.dart';
import 'take_back.dart';
import 'iphone_wiring.dart';
import 'update_wiring.dart';
import 'voice_wiring.dart';

/// The app, put together: what the web app's `App.tsx` does once its screens exist. The launch screen over the
/// shell (lib/shell/app_shell.dart); in the shell the home page, the notes' sidebar as a card or docked, and the
/// notifications; over it Settings and a workspace's sheet; and the art in the seams each of them left for it.
///
/// What it stands on:
/// - **The library** is the Rust core's ([core], lib/core/core_library.dart): the notes are Markdown files in the app's
///   own folder, as the Tauri app keeps them; the workspaces and the trash are preferences; a fresh library is given
///   the starter notes once. Without a core (a test, a picture) it is the store screenshots' invented library in memory.
/// - **A note's own screen** is lib/note's, over the editor (lib/editor) with every piece of it, put together for
///   each open note by lib/root/note_desk.dart: its boards, queries and tickets, and the canvas, the notebook's index
///   and the journal's entries that take the page for a note that is not words. What those read of the library is
///   lib/root/library_reads.dart; what they ask of the app (a title opened in a notebook's tab, a page, a ticket or
///   a canvas made from an index, a journal's new entry, another note written from a query) is here, as it is in
///   App.tsx.
/// - **The +** opens the sheet of what it makes (lib/notes/new_sheet.dart): a note, opened ready to type on a blank
///   page that offers names and templates, a canvas, a notebook or a journal (lib/book/new_book_sheet.dart), or an
///   entry in the journal written in last.
/// - **The account** is made only where the build was told its service ([account], lib/root/account_wiring.dart):
///   then the shell, Settings and a note's sharing are under one [AccountScope], the organizations have their
///   pages, the notifications are the feed's, and the way in is the first thing on screen once. With none there
///   is no account object anywhere, and every screen is the signed-out one.
/// - **A link that opened the app** ([GhostRoot.links], lib/share/app_links.dart) is followed once the notes are
///   read, as `shell/useAppLinks.ts` does: a note opened where it was left, the notifications, an organization's
///   dashboard, an invitation asked about before anything is joined, and a shared link's copy saved and opened. And
///   an address tapped in a note is handed to the phone ([GhostRoot.openLink]).
/// - **Speak** ([GhostRoot.voiceMaking], lib/root/voice_wiring.dart) is the recorder over the core's Whisper and the
///   phone's microphone, and the phone's meeting service: the dock's microphone, the sidebar's, the palette's and a
///   note's own open the capture screen, the + sheet's Meeting and the card's "Meeting instead" start the service
///   with the meeting screen over it, and where each begins and ends is lib/root/capture_route.dart
///   (`shell/useCaptureRoute.ts`). Settings' Recording and AI pages have their real rows. No always-on microphone:
///   one is opened by a recorder's screen that is on screen. Without a core (a test, a picture) there is no voice
///   unless one is given ([GhostRoot.voice]).
class GhostRoot extends StatefulWidget {
  const GhostRoot({super.key, this.sheet, this.core, this.library, this.workspaces, this.stored, this.clock, this.launch = true, this.account, this.services, this.untouched, this.links, this.openLink, this.voice, this.voiceMaking, this.previewFetch, this.native, this.restart, this.guide, this.tapePlayer, this.updates, this.locator, this.placeLookup, this.mapTiles, this.picturePicker, this.films, this.dayPicker});

  /// The app's token sheet, which the shell stamps its layout over: the theme's own unless given.
  final TokenSheet? sheet;

  /// The Rust core (lib/core/native): given, the notes are the real library's files, and the workspaces and the
  /// trash are kept in the preferences as on the web. Absent, everything is in memory over the invented library.
  final CoreInvoke? core;

  /// The notes, where a test brings its own.
  final NoteLibrary? library;
  final WorkspaceStore? workspaces;

  /// Where this device keeps how its sidebar was left; the app's own (core/stored.dart) unless given.
  final Stored? stored;

  /// The time, for a picture that must say the same "2 hr ago" every day.
  final int Function()? clock;

  /// Whether the app opens behind its launch screen. A test's picture of a screen does not.
  final bool launch;

  /// Where this build's account service is, with the crypto to reach it (lib/root/account_wiring.dart). Absent,
  /// as in every build not given `GHOST_API`, there is no account at all. It needs the [core].
  final AccountMaking? account;

  /// The account's objects, where a test brings its own; then nothing is made from [account].
  final AccountServices? services;

  /// Where the links that opened the app come from: the phone's (lib/core/phone_links.dart) in the app. Absent, no
  /// link is followed.
  final LinkSource? links;

  /// Hands an address to the phone (lib/core/open_link.dart): a link's tap in a note, Settings' pages. Absent, a tap
  /// opens nothing.
  final LinkOpener? openLink;

  /// The whole core, for what is a job there and says the rest as events: Settings' Library folder, Backup and
  /// Export (lib/core/library_folder.dart, backup.dart, export_all.dart). Absent, as in a test, those pages say
  /// what a build without them says.
  final GhostCore? native;

  /// Builds the whole app anew, after a reset (`window.location.reload()`): whoever holds this root gives it. Absent,
  /// Developer's two resets cannot be pressed.
  final VoidCallback? restart;

  /// The welcome walkthrough's place in the app (lib/guide/guide_state.dart). The app over a core makes its own,
  /// which opens by itself on a first launch; a test brings one, or has none and is never walked through.
  final GuideController? guide;

  /// The app's one player of a note's recording (lib/tapes/phone_player.dart on a phone). Absent, a spoken note
  /// draws no tape.
  final TapePlayer? tapePlayer;

  /// Where the phone is (lib/core/phone_position.dart on a phone), what names a place (lib/core/geocode.dart) and
  /// what draws a map's tiles (lib/editor/media/map_tiles.dart). With no [locator], as in a test, no note keeps a
  /// place: nothing is asked of anywhere, and a note draws only the tag its words carry.
  final Locator? locator;
  final PlaceLookup? placeLookup;
  final MapTilesBuilder? mapTiles;

  /// The phone's picture chooser, given what keeps a chosen picture among the library's
  /// (lib/core/phone_pictures.dart `phonePicturePicker`). Absent, as in a test, no picture can be added.
  final PicturePicker Function(PictureAdopter adopt)? picturePicker;

  /// This phone's films: its picker, where each film stands and its player (lib/core/phone_films.dart). Absent, as
  /// in a test, a film in a note is its poster and none can be added.
  final Films? films;

  /// The calendar Pick a date opens (lib/core/phone_day.dart on a phone). Absent, a date is Today, Tomorrow or
  /// Next week.
  final DayPicker? dayPicker;

  /// Reads a linked page's title, site and summary (lib/core/link_preview.dart `linkPreviewFetch`). Absent, as in a
  /// test, a link's card says its site and its path and nothing is asked of anywhere.
  final LinkPreviewFetch? previewFetch;

  /// Voice, where a test brings its own; then nothing is made from [voiceMaking].
  final Voice? voice;

  /// The app's updates (lib/core/updates.dart), the process's own as the core is: made by whoever holds this root,
  /// and only in a build told where its releases are. Absent, as in every debug build and every test that brings
  /// none, no screen says anything of an update and nothing is asked of anywhere.
  final Updates? updates;

  /// The core and the phone's halves a [Voice] is made from (lib/root/voice_wiring.dart). Absent, as without a
  /// core, nothing records and Speak is offered nowhere. It needs the [core].
  final VoiceMaking? voiceMaking;

  /// The records of the notes nobody has written in yet (core/untouched.dart); the app's own unless a test brings
  /// its own.
  final UntouchedNotes? untouched;

  @override
  State<GhostRoot> createState() => _GhostRootState();
}

class _GhostRootState extends State<GhostRoot> {
  late final bool _real = widget.core != null && widget.library == null;
  late final NoteLibrary _library = widget.library ?? (_real ? CoreLibrary(widget.core!) : SampleLibrary.seeded(now: DateTime.now().millisecondsSinceEpoch));
  late final Trash _trash = _real ? KeptTrash() : MemoryTrash();
  late final WorkspaceStore _workspaces = widget.workspaces ??
      (_real
          ? WorkspaceStore(storage: KeptWorkspaceStorage(), trash: _trash, onFiled: NoteFolders(_library).fileNotesInFolder)
          : WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces()), trash: _trash));
  late final VersionsStore _versionsStore = VersionsStore(widget.core, kept: _stored);
  late final VersionsRecord _versions = VersionsRecord(store: _versionsStore, preferences: preferences, workspaces: _workspaces);

  /// The kept pictures, where there is a core to keep them.
  late final CorePictureStore? _pictures = widget.core == null ? null : CorePictureStore(CoreFiles(widget.core!), adopter: corePictureAdopter(CoreFiles(widget.core!)));

  /// A picture chosen on the phone and kept, where there is a chooser and a core to keep it in.
  late final PicturePicker? _pickPicture = widget.core == null ? null : widget.picturePicker?.call(corePictureAdopter(CoreFiles(widget.core!)));

  /// The account made for this build, where it was told its service and has a library of its own to sync.
  late final WiredAccount? _wired = widget.services == null && widget.account != null && _real
      ? WiredAccount.make(
          making: widget.account!,
          core: widget.core!,
          workspaces: _workspaces,
          versions: _versionsStore,
          touched: _library is CoreLibrary ? (_library).touched : null,
          refresh: _library.refresh,
          shownNotes: () => _shown,
          kept: _stored,
          onPicture: (name) => _pictures?.arrived(name),
          // A note of the account's own that met another device's while this one had changes unsent: this
          // device's words, kept beside the room's (lib/live/open.dart).
          keepCopy: (words) async {
            await _library.createNote(words);
          },
        )
      : null;
  late final AccountServices? _services = widget.services ?? _wired?.services;

  /// Whether the way into an account is up (shell/account_gate.dart): made once what this device kept is read.
  AccountGateState? _gate;
  AppLifecycleListener? _life;

  /// A member's caret a note is about to be opened at (an organization's Jump to cursor), by note; its desk takes it.
  final Map<String, Map<String, Object?>> _jumps = {};

  /// Who is in an organization's notes now, as the live rooms have them (lib/live/presence.dart): none in a build
  /// with no account, and while signed out.
  List<OrgPresence> _seenIn(String orgId) => [
        for (final seen in _wired?.live.presence.presenceIn(orgId) ?? const <Seen>[])
          OrgPresence(client: '${seen.client}', handle: seen.handle, hue: seen.hue, editingNote: seen.at?.note, editingTitle: seen.at?.title),
      ];

  /// Someone came, went, or opened another note: the home page's cards and the organization's rows say so. A
  /// team's note says it has been left as its desk is let go, which is while the tree is being built or taken
  /// down: drawn after that frame, where asking at once threw inside the desk's `dispose` and left its listeners
  /// behind (seen on the emulator, on leaving a team's note).
  void _presenceChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) return setState(() {});
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// A note opened where a member is editing it: at their caret, where the room has one.
  void _jumpTo(AppShellState shell, String orgId, String noteId) {
    for (final seen in _wired?.live.presence.presenceIn(orgId) ?? const <Seen>[]) {
      final cursor = seen.at?.note == noteId ? seen.at?.cursor : null;
      if (cursor != null) _jumps[noteId] = cursor;
    }
    shell.openNote(noteId);
  }

  /// An organization's settings, and the sheet a new one is named in.
  ({String id, OrganizationFrom from})? _organization;
  bool _newOrganization = false;

  void _say(BuildContext context, String message) => GlacierToast.of(context).toast(message: Text(message));

  /// What the note on screen reads of the library, read once per change to the notes (lib/root/library_reads.dart).
  late final LibraryReads _reads = LibraryReads(shown: () => _shown, all: () => _library.value);
  late final Listenable _libraryChanges = Listenable.merge([_library, _trash]);

  /// The journal on screen, writing its own index (`journalWriter`), and New entry's half of the library.
  journal.JournalWriter? _journalWriter;
  late final UntouchedNotes _untouched = widget.untouched ?? untouchedNotes;
  late final JournalPages _pages = JournalPages(
    _library,
    untouched: _untouched,
    write: (journalId, change) {
      final writer = _journalWriter;
      if (writer == null || writer.id != journalId || _shell.currentState?.shown != journalId) return false;
      writer.write(change);
      return true;
    },
  );

  /// An entry, or a new note given a name or a template, that nobody wrote in, taken back once it is left
  /// (lib/root/take_back.dart). It stays while it is the note on screen, while a capture is aimed at it, and while
  /// its tab is open behind another note, a capture or a meeting (`stays`).
  late final TakeBack _takeBack = TakeBack(
    library: _library,
    trash: _trash,
    untouched: _untouched,
    stays: (id) {
      final shell = _shell.currentState;
      if (shell == null) return false;
      final now = shell.screen;
      if (now is ScreenNote && now.note.id == id) return true;
      if (now is ScreenCapture && now.noteId == id) return true;
      return shell.tabs.open.contains(id) && (now is ScreenNote || now is ScreenCapture || now is ScreenMeeting);
    },
    writeJournal: _pages.writeJournal,
    dropTab: (id) => _shell.currentState?.dropTab(id),
    forgetTag: (id) => _places?.setPendingTag(id, null),
  )..making = _pages.making;

  /// The places notes keep (lib/core/place_tags.dart), where the build can say where the phone is: the fix, the
  /// name asked of OpenStreetMap once, the tag that waits for a note's first words or a recording's better ones.
  late final PlaceTags? _places = widget.locator == null
      ? null
      : PlaceTags(
          locations: Locations(
            locator: widget.locator,
            lookup: widget.placeLookup,
            localOnly: () => preferences.value.localOnly,
            mapTiles: () => preferences.value.mapTiles,
            placeNames: () => preferences.value.placeNames,
          ),
          getNote: _library.get,
          updateNote: _library.update,
          refinePending: (id) => _voice?.recorder.refining?.refinePending(id) ?? false,
          untouched: _untouched,
          kept: _stored,
        );

  /// The first time a new note would be tagged on a phone that has never answered the location prompt, the app
  /// says what it is for, in its own words, and the prompt comes from the press (`introduceLocation`).
  void _introduceLocation(void Function() allow) => _introduce('New notes can keep where they were written.', allow);

  /// The first ask for where a journal's entries were written, from its own press (`introduceEntries`).
  Introduce _introduceEntries(String journal) => (allow) => _introduce('$journal keeps where each entry was written.', allow);

  void _introduce(String message, void Function() allow) {
    if (!mounted) return;
    GlacierToast.of(context).toast(message: Text(message), duration: const Duration(seconds: 10), action: GlacierToastAction(label: 'Allow location', onPress: allow));
  }

  /// Every tag still waiting for a note that is closed, written where it may now land; the notes are read again
  /// when one did (shell/useHousekeeping.ts).
  void _settleTags() {
    final places = _places;
    if (places == null) return;
    unawaited(places.settleWaitingTags().then<void>((landed) async {
      if (landed > 0) await _library.refresh();
    }, onError: (Object _) {}));
  }

  /// Voice, once it is made (lib/root/voice_wiring.dart), and where a capture begins and ends
  /// (lib/root/capture_route.dart). Null until then, and for good in a build with none: Speak is offered nowhere.
  Voice? _voice;
  CaptureRoute? _capture;
  VoidCallback? _unwatchMeeting;
  AppLifecycleListener? _voiceLife;
  final Completer<void> _notesRead = Completer<void>();

  Future<void> _speakUp() async {
    final making = widget.voiceMaking;
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
                )
              : null);
    } catch (failure) {
      debugPrint('[ghost] voice could not be made: $failure');
      return;
    }
    if (voice == null) return;
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
          if (mounted) {
            setState(() {
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
        sayTooSoon: () => _guide?.sayTooSoon(),
        // Once the note's screen is up and watches its tag, so the tag goes through its editor and not under it.
        tagNew: _places == null
            ? null
            : (id, {required reviewing, required quiet}) => WidgetsBinding.instance.addPostFrameCallback((_) {
                  unawaited(_places.tagNewNotesIfWanted([id], (reviewing: reviewing), quiet: quiet, introduce: _introduceLocation));
                }),
      ),
    );
    setState(() {
      _voice = voice;
      _capture = capture;
    });
    // The meeting's state, for the row that says "Recording now", and the models, for Settings' AI page.
    _unwatchMeeting = voice.live?.subscribe(_voiceChanged);
    voice.live?.canNotify.addListener(_voiceChanged);
    voice.live?.canNotifyNow();
    models?.addListener(_voiceChanged);
    // The voice model's fetch, for the line above the notes.
    recorder.voiceModel.addListener(_voiceChanged);
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
        GlacierToast.of(context).toast(
          message: const Text('Summarized'),
          action: GlacierToastAction(label: 'Open', onPress: () => _shell.currentState?.openNote(done.id)),
        );
      },
    );
    if (mounted) setState(() {});
    // The launch, once the notes are read: the side key's capture in a build with the assistant, or the meeting
    // already being recorded.
    await _notesRead.future;
    if (mounted) capture.boot();
  }

  /// The meeting's state, whether the phone may notify, the models or the screen changed: drawn again, after the
  /// frame where one is being built.
  void _voiceChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// What is waiting on the person, above the notes (notes/Notices.tsx), in the page's order: a new version of the
  /// app (lib/root/update_wiring.dart, from [GhostRoot.updates]), an invitation to an organization where the build
  /// has an account, and the voice model while it is not ready.
  List<Widget> _notices() {
    final updates = widget.updates;
    final services = _services;
    final model = _voice?.recorder.voiceModel;
    final state = switch (model?.state) {
      VoiceModelStateDownloading(:final received, :final total) => notices.VoiceModelDownloading(received: received, total: total),
      VoiceModelStateFailed(:final message) => notices.VoiceModelFailed(message),
      _ => const notices.VoiceModelQuiet(),
    };
    return [
      if (updates != null && updates.apk is! ApkPhaseNone) notices.UpdateNotice(updates: updateCardOf(updates)),
      if (services != null) InviteWaiting(services: services, onOpen: (id) => _shell.currentState?.openOrganization(id)),
      if (model != null && state is! notices.VoiceModelQuiet) notices.VoiceModelStatus(state: state, onRetry: model.retry),
    ];
  }

  /// An update waiting: the sidebar's to carry on a wide window, where there is no home list to show it (App.tsx
  /// `notices`, notes/NoteTree.tsx): docked, and floating where the window is in two panes. Nothing while there is
  /// nothing newer, and the tree gives it no room then.
  List<Widget> _sidebarNotices() {
    final updates = widget.updates;
    return [if (updates != null && updates.apk is! ApkPhaseNone) notices.UpdateNotice(updates: updateCardOf(updates))];
  }

  /// The AI, once voice has made its engine the app's (docs/STAGE8_AI.md, "At launch"): whether it can run here,
  /// the phone as the strip's card names it, and the fills' queue. Null in a build with no engine.
  AvailabilityController? _availability;
  DeviceFactsController? _deviceFacts;
  VoidCallback? _stopFills;

  /// Local only as it stood at the last look: switched off, the fills parked while nothing could leave the phone
  /// are pressed again, where the queue was started.
  late bool _wasLocalOnly = preferences.value.localOnly;

  void _localOnlyMoved() {
    final now = preferences.value.localOnly;
    if (now == _wasLocalOnly) return;
    _wasLocalOnly = now;
    if (!now && _stopFills != null) resumeParked();
  }

  /// The phone's models as the walkthrough's model page reads them (lib/guide/guide_models.dart): where there is an
  /// engine to run one. Null before voice is made and in a build with none, and the page then says nothing of
  /// downloads.
  PhoneGuideModels? _guideModels;
  GuideModels? get _modelsForGuide {
    final models = _voice?.models;
    if (models == null || !engine.aiBackend.available) return null;
    return _guideModels ??= PhoneGuideModels(models, offered: defaultTargetPlatform != TargetPlatform.iOS);
  }

  /// A line for each note that wants one, written by the smallest model while nothing else has the cores
  /// (lib/format/gist.dart): the home page's cards read them.
  Gists? _gists;
  VoidCallback? _stopGistHold;

  /// The AI of the note on screen, told by its desk: the scene over the window is drawn from it.
  String? _noteAiId;
  NoteAi? _noteAi;

  Future<void> _aiUp(Voice voice) async {
    if (!engine.aiBackend.available || voice.models == null) return;
    // Who signs a note beside the AI.
    ai_start.noteOwner = () => _services?.session?.handle;
    final availability = AvailabilityController(models: voice.models)..addListener(_voiceChanged);
    final device = await engine.readDevice();
    if (!mounted) return availability.dispose();
    final ram = device?.totalRamBytes;
    setState(() {
      _availability = availability;
      _deviceFacts = DeviceFactsController(cores: device?.cores, memoryGb: ram == null ? null : ram / 1e9);
    });
    // The gists step aside for the recorder and a review, and are written only with the app on screen.
    _stopGistHold = voice.recorder.refining?.onRefineHold(pauseGists);
    gistVisible = () => WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _gists = Gists()
      ..addListener(_voiceChanged)
      ..show(_shown);
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
      onGetModel: () => setState(() {
        _settings = true;
        _settingsPage = SettingsTarget('ai', nonce: DateTime.now().microsecondsSinceEpoch);
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
        _noteAi?.removeListener(_voiceChanged);
        _noteAi?.reviewStage.removeListener(_voiceChanged);
        _noteAiId = ai == null ? null : id;
        _noteAi = ai;
        ai?.addListener(_voiceChanged);
        ai?.reviewStage.addListener(_voiceChanged);
        _voiceChanged();
      },
    );
  }

  /// A Speak button (`speak`): a capture into a new note, or the note its first command names.
  void _speak() => unawaited(_capture?.start(false));

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
      // The phone answers a moment later than the screen asks: allowed where it already may, else asked, and the
      // phone's own answer is told to the screen as the prompt's is (`MeetingLive.notified`).
      requestNotifications: () {
        if (live.canNotifyNow()) return NotificationsAnswer.allowed;
        if (service == null) return NotificationsAnswer.blocked;
        unawaited(service.requestNotifications().then<void>((answer) {
          if (answer != 'asked') live.notified();
        }, onError: (Object _) => live.notified()));
        return NotificationsAnswer.asked;
      },
      deleteNote: _library.destroy,
      dropSummary: (id) => voice.summaries?.dropSummary(id),
      forgetMeeting: (id) => preferences.update((now) => now.copyWith(meetings: {...now.meetings}..remove(id))),
    );
  }

  /// A note opened from the home page (`onOpen`): the tape being recorded opens the meeting screen, not the note,
  /// which has nothing in it yet but its title.
  void _openFromHome(AppShellState shell, String id) {
    final live = _voice?.live?.meetingStateNow();
    if (live != null && live.recording && live.noteId == id && (_capture?.showMeeting(false) ?? false)) return;
    _openWhereLeft(shell, id);
  }

  /// A note opened from outside it (`openNoteWhereLeft`: the home page, All notes, the sidebar, a note's menu, a
  /// notification, an organization's page): a notebook goes back to the chapter it was left in
  /// (lib/book/book_spot.dart). A tab, Back and Forward show the note itself.
  void _openWhereLeft(AppShellState shell, String id) {
    final note = _library.noteOf(id);
    shell.openNote(note == null ? id : whereLeft(note, _shown, shell.shown, on: _stored).id);
  }

  /// Settings' three pages over the core and the phone's pickers: where the library is and the calls that move it,
  /// the drives a backup goes to, and everything as one zip. Made once, where the build has the whole core.
  late final GhostCore? _native = _real ? widget.native : null;
  late final LibraryFolder? _libraryFolder = _native == null
      ? null
      : LibraryFolder(invoke: _native.invoke, onNotesChanged: () => unawaited(_library.refresh().catchError((Object _) {})));
  late final Backups? _backups = _native == null ? null : Backups.overCore(invoke: _native.invoke, startJob: _native.startJob, events: _native.events);
  late final ExportAll? _export = _native == null ? null : ExportAll.overCore(invoke: _native.invoke, startJob: _native.startJob, events: _native.events);

  /// The notes' folder in the phone's Files app, for the sidebar's Browse files (lib/core/library_files.dart): the
  /// phone is asked the first time a sidebar is built, and the tool is there once it has said it can.
  late final LibraryFiles _files = LibraryFiles();
  VoidCallback? get _browseFiles => _files.offered(() {
        if (mounted) setState(() {});
      });

  /// Which tapes' audio is on this device (lib/settings/tapes_here.dart): each tape's file is asked through the
  /// player as Settings' Tapes card is put up, as the page's card asked the `rec` scheme (`headStatus`).
  late final TapesHere _tapes = TapesHere(widget.tapePlayer?.onDevice);

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
    if (voice == null) return SettingsFeatures(onWayIn: wayIn, onSmokeBench: smoke, onPlayScene: scene, onReset: reset, libraryFolder: _libraryFolder, backup: _backups, export: _export, places: _places);
    final models = voice.models;
    final present = models == null ? const <String>{} : presentIds(models.models).toSet();
    final download = models?.download;
    // Only the tapes whose audio is here: not one the row removed, nor one whose file says it is elsewhere.
    final taped = _tapes.here(_library.value);
    final old = [for (final note in oldTapes(taped, DateTime.now().millisecondsSinceEpoch)) note.id];
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
      places: _places,
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
      onAllowMeetingNotices: service == null || live == null
          ? null
          : () {
              unawaited(service.requestNotifications().then<void>((_) {
                live.notified();
                live.canNotifyNow();
              }, onError: (Object _) {}));
              return true;
            },
      meetingSound: voice.sound?.supported ?? false,
      meetingSoundWhy: voice.sound?.reason,
      tapes: tapeBytes(taped),
      oldTapes: old.length,
      onCountTapes: () => unawaited(_tapes.ask(_library.value).then<void>((_) {
        if (mounted) setState(() {});
      })),
      onRemoveOldAudio: remove == null
          ? null
          : () async {
              final removed = await remove(old);
              _changed();
              return removed.length;
            },
    );
  }

  /// The walkthrough (shell/useGuide.ts): open by itself on the first launch that is not the side key's capture,
  /// and from Settings and the palette after. Made as the root is, the device's memory having been read by then.
  late final GuideController? _guide = widget.guide ??
      (_real ? GuideController(launchedByKey: (widget.voiceMaking?.assistant ?? false) && widget.voiceMaking?.launch == 'capture') : null);

  /// The Ghost.md guide as a notebook (`onGuideBook`, `openSample`): read against the library as it is now, less
  /// the trash, so a second press opens the first; then opened in a tab of its own.
  Future<void> _openGuideBook() async {
    setState(() => _settings = false);
    try {
      await _library.refresh();
      final note = await addGuideBook(_library, outOfTrash(_library.value, _trash.value));
      await _library.refresh();
      if (mounted) _afterFrame((shell) => shell.openNote(note.id));
    } catch (_) {
      await _library.refresh().catchError((Object _) {});
      if (mounted) _say(context, '$guideTitle did not load. Try again.');
    }
  }

  /// The titles of linked pages, kept on this device (`core/linkPreview.ts`): asked only with Link previews on and
  /// "Nothing leaves the phone" off.
  late final KeptLinkPreviews _previews = KeptLinkPreviews(
    _stored,
    fetch: widget.previewFetch,
    canAsk: () => preferences.value.linkPreviews && !preferences.value.localOnly,
  );

  /// Following the links that opened the app, from the notes' first read until the app is gone.
  void Function()? _stopLinks;

  /// An invite link that arrived, each arrival asked about again (`joinRequest`).
  JoinRequest? _joinRequest;
  void _joinFromLink(String code) {
    if (mounted) setState(() => _joinRequest = JoinRequest(code, DateTime.now().microsecondsSinceEpoch));
  }

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
  Future<void> _openNoteFromLink(String id) async {
    await _voice?.summaries?.landNativeResult(id).then<void>((_) {}, onError: (Object _) {});
    await _library.refresh();
    final shell = _shell.currentState;
    final note = _library.noteOf(id);
    if (!mounted || shell == null || note == null || _trash.isTrashed(id)) return;
    shell.openNote(whereLeft(note, _shown, shell.shown, on: _stored).id);
  }

  late final AppLinkDoor _door = _RootDoor(this);

  /// The + sheet, the workspace it makes into where it was an organization's +, and the New notebook sheet with its
  /// own.
  bool _newSheet = false;
  String? _newInto;
  NewBookKind? _bookSheet;
  String? _bookInto;

  static final Canvas _emptyCanvas = Canvas(nodes: const [], edges: const []);

  /// What the aside holds for the screen that is up (App.tsx `asideBody`): asked once for a library and a note.
  AsideContent? _asideOf(AppShellState shell) {
    final id = shell.shown;
    final notes = shell.notes;
    if (!identical(notes, _asideNotes) || id != _asideFor) {
      _asideNotes = notes;
      _asideFor = id;
      Note? open;
      if (id != null) {
        for (final note in notes) {
          if (note.id == id) open = note;
        }
      }
      _aside = asideContent(notes, open);
    }
    return _aside;
  }

  List<Note>? _asideNotes;
  String? _asideFor;
  AsideContent? _aside;

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
    if (mounted) setState(() {});
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
  bool _seeding = false;
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

  late final NoteDeskWorld _desk = NoteDeskWorld(
    titles: () => [
      for (final note in _shown)
        if (noteTitle(note.body).isNotEmpty) noteTitle(note.body),
    ],
    known: (title) => _reads.titled(title) != null,
    open: _openTitle,
    live: _wired?.noteLive,
    takeJump: (id) => _jumps.remove(id),
    bodyOf: (title) => _reads.titled(title)?.body,
    pictures: _pictures,
    films: widget.films,
    services: _services,
    changes: _libraryChanges,
    queryNotes: () => _reads.queryNotes,
    // A note a query listed, opened: the note itself, or a to-do's note at its line.
    openAt: (id, line) => _shell.currentState?.openNote(id, at: line == null ? null : 'line:${line + 1}'),
    write: (id, change) => unawaited(_writeNote(id, change)),
    addTicket: _addFromQuery,
    // `[[GHO-12]]` finds the ticket by its key too.
    tickets: (id) => _reads.ticketOptions(id, open: _openTitle),
    openWithin: _openTitleWithin,
    openCanvas: _openCanvasWithin,
    openPage: _openPageWithin,
    openTicket: _openTicketWithin,
    ticketTemplates: () => _reads.ticketTemplates,
    pageTitles: _pageTitles,
    noteOf: (title) => _reads.titled(title),
    newEntry: (id, template) => unawaited(_newEntry(id, template)),
    openLink: widget.openLink,
    previewer: _previews,
    ai: _aiWorld,
    tapePlayer: widget.tapePlayer,
    noteById: _library.noteOf,
    getNote: _library.get,
    setNoteRecording: (id, ms, segments) async => _voice?.recorder.store.setNoteRecording(id, ms, segments),
    tapes: _voice?.recorder.tapes,
    // Not where nothing records (an iPhone): a tape synced from another device then offers no Add.
    onSpeak: recordsVoice ? (id) => unawaited(_speakInto(id)) : null,
    pickPicture: _pickPicture,
    dayPicker: widget.dayPicker,
    mapTiles: widget.mapTiles,
    tags: _places,
    forgetTag: (id) => _places?.setPendingTag(id, null),
    holdNote: (id, on) => _voice?.recorder.refining?.holdNote(id, on),
    dropRefine: (id, fromMs) => _voice?.recorder.refining?.dropRefine(id, fromMs),
    // A landing's Undo takes back what the recording wrote to other notes (`undoCommandMutation`).
    undoCommandMutation: _library.undoCommandMutation,
  );

  /// A note's screen with its editor: one desk to an open note (lib/root/note_desk.dart).
  Widget _note(BuildContext context, AppShellState shell, ScreenNote screen) => NoteDesk(
        key: ValueKey('desk:${screen.note.id}'),
        noteId: screen.note.id,
        title: noteTitle(screen.note.body),
        world: _desk,
        readOnly: _trash.isTrashed(screen.note.id),
        // What the recorder handed the note it opened (lib/root/capture_route.dart `finished`).
        landing: screen.landing,
        ask: screen.ask,
        review: screen.review,
        say: (message) => _say(context, message),
        builder: (context, editor, seams) => noteScreenBuilder(
          library: _library,
          workspaces: _workspaces,
          actions: () => _actions,
          versions: _versions,
          trash: _trash,
          device: _stored,
          untouched: _untouched,
          editor: editor,
          seams: seams,
          say: _say,
          bookOf: _reads.placeInBook,
          templates: () => _reads.ownTemplates,
          onTemplates: () => unawaited(_openTemplates()),
          // Taken back by the next journal's own: one screen is gone only after the next has come.
          onJournal: (writer) => _journalWriter = writer ?? _journalWriter,
          onSpeak: _capture == null ? null : (id) => unawaited(_speakInto(id)),
          tags: _places,
        )(context, shell, screen),
      );
  NoteActions? _made;

  /// Pin, archive, delete and their Undo (notes/note_actions.dart); made once there is a toast to say them with.
  /// A tag waiting for a note goes with it to the trash, and with it for good (`forgetKept`).
  NoteActions get _actions => _made ??= NoteActions(
        library: _library,
        workspaces: _workspaces,
        trash: _trash,
        say: NoteActions.toaster(context),
        onForget: (id) => _places?.setPendingTag(id, null),
        onTrashed: (note) => _places?.setPendingTag(note.id, null),
      )..addListener(_changed);

  void _changed() {
    _reads.changed();
    _gists?.show(_shown);
    // The notes changed: a meeting's note may have been written by the service, and a write-up's result may wait.
    _voice?.notesChanged();
    if (mounted) setState(() {});
  }

  List<Note> get _shown => [
        for (final note in outOfTrash(_library.value, _trash.value))
          if (!(_made?.hidden.contains(note.id) ?? false)) note,
      ];
  List<Note> get _trashed => inTrash(_library.value, _trash.value);

  /// The notes made in this run that have no file yet (`CoreLibrary.isDraft`): the core leaves them out of its list.
  Set<String> get _drafts {
    final library = _library;
    if (library is! CoreLibrary) return const {};
    return {
      for (final note in library.value)
        if (library.isDraft(note.id)) note.id,
    };
  }
  late final Stored _stored = widget.stored ?? stored;
  late final Listenable _all = Listenable.merge([_library, _workspaces, _trash, preferences, _services?.changes]);

  final GlobalKey<AppShellState> _shell = GlobalKey<AppShellState>();
  final GlobalKey<CommandBarState> _commands = GlobalKey<CommandBarState>();

  /// Settings asked for at a page, by when it was asked (settings/settings_sheet.dart `toPage`).
  SettingsTarget? _settingsPage;

  void _search() => _commands.currentState?.show();

  /// A note's menu, from a long press or a right-click on it in any list (notes/note_menu.dart).
  final NoteMenuController _menu = NoteMenuController();

  late bool _launching = widget.launch;
  bool get _read => !_library.loading;
  bool _settings = false;

  /// Stops answering the desktop's keys and menu (lib/root/desktop_wiring.dart).
  VoidCallback? _stopDesktop;

  /// The workspace sheet: shut, a new one, or one to change.
  ({Workspace? editing})? _workspace;

  /// The smoke at the edges is the art's own switch (lib/art/wisp_settings.dart), which follows the preference.
  void _smoke() => WispSettings.instance.wanted = preferences.value.wispEdge;

  @override
  void dispose() {
    _stopDesktop?.call();
    preferences.removeListener(_smoke);
    preferences.removeListener(plugins.preferencesChanged);
    preferences.removeListener(_localOnlyMoved);
    _guide?.removeListener(_changed);
    // The updates are the process's, as the core is: let go of, never disposed.
    widget.updates?.removeListener(_voiceChanged);
    if (widget.guide == null) _guide?.dispose();
    _stopLinks?.call();
    _previews.dispose();
    _unwatchMeeting?.call();
    _stopFills?.call();
    _guideModels?.dispose();
    _stopGistHold?.call();
    _gists?.removeListener(_voiceChanged);
    _gists?.dispose();
    _availability?.removeListener(_voiceChanged);
    _availability?.dispose();
    _deviceFacts?.dispose();
    _voice?.live?.canNotify.removeListener(_voiceChanged);
    _voice?.models?.removeListener(_voiceChanged);
    _voice?.recorder.voiceModel.removeListener(_voiceChanged);
    _voiceLife?.dispose();
    _capture?.dispose();
    // A voice a test brought is the test's to let go.
    if (widget.voice == null) _voice?.dispose();
    _libraryChanges.removeListener(_reads.changed);
    _life?.dispose();
    _gate?.dispose();
    _wired?.live.presence.removeListener(_presenceChanged);
    _wired?.dispose();
    _pictures?.dispose();
    _made?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _smoke();
    preferences.addListener(_smoke);
    // Local only turning on or off changes which plugins are on without a switch moving.
    preferences.addListener(plugins.preferencesChanged);
    // And lets the fills that were parked under it go on (ai/fills/queue.ts `resumeParked`).
    preferences.addListener(_localOnlyMoved);
    // Who Claude's page in Settings reads as signed in (plugins/claude): this build's account, where it has one.
    claudeHandle = () => _services?.session?.handle;
    _guide?.addListener(_changed);
    _libraryChanges.addListener(_reads.changed);
    // The updates: drawn again as they change, not while a meeting records, and looked for from now (`useUpdates`).
    widget.updates
      ?..addListener(_voiceChanged)
      ..recording = (() => _voice?.live?.state?.recording ?? false)
      ..start();
    _open();
    unawaited(_account());
    unawaited(_speakUp());
    // A desktop's keys and the Mac's menu bar (lib/root/desktop_wiring.dart): Command-N, Command-R, the palette, Settings.
    _stopDesktop = wireDesktopCommands(
      onPlace: () => _shell.currentState?.screen.isPlace ?? false,
      covered: () => _settings || _newSheet || (_commands.currentState?.isOpen ?? false),
      newNote: _new,
      refresh: () async {
        await _library.refresh();
        await _services?.engine?.syncNow();
      },
      status: () {
        final now = _services?.engine?.status.value;
        return (phase: now?.phase ?? 'idle', message: now?.message);
      },
      say: (message) {
        if (mounted) _say(context, message);
      },
      palette: () => _commands.currentState?.show(),
      settings: () {
        if (mounted) setState(() => _settings = true);
      },
    );
  }

  /// What this device kept of an account, then the sync for as long as the app is open, and the way in where it is
  /// due. Nothing at all in a build with no account.
  Future<void> _account() async {
    final services = _services;
    if (services == null) return;
    final wired = _wired;
    if (wired != null) {
      await wired.start();
      // The relay's socket goes while the app is behind another, and is back with it.
      _life = AppLifecycleListener(onResume: wired.resumed, onPause: wired.paused);
      wired.live.presence.addListener(_presenceChanged);
    }
    if (!mounted) return;
    setState(() => _gate = AccountGateState(services: services, kept: _stored)..addListener(_changed));
  }

  void _toAccount() => setState(() {
        _settings = true;
        _settingsPage = SettingsTarget('account', nonce: DateTime.now().microsecondsSinceEpoch);
      });

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

  Widget _organizationPage(BuildContext context, AppShellState shell, ScreenOrganization screen) {
    final id = screen.orgId;
    final wisp = preferences.value.wispEdge;
    if (screen.page == OrganizationPage.log) {
      return OrganizationLog(services: _services, orgId: id, notes: shell.notes, onBack: () => shell.openOrganization(id), onOpenNote: (note) => _openWhereLeft(shell, note), record: _versions, wisp: wisp);
    }
    return OrganizationScreen(
      services: _services,
      orgId: id,
      notes: shell.notes,
      onBack: shell.backToList,
      onOpenNote: (note) => _openWhereLeft(shell, note),
      onNew: () => _plus(orgWorkspaceId(id)),
      onAllNotes: () {
        _workspaces.chooseWorkspace(orgWorkspaceId(id));
        shell.backToList();
      },
      onSettings: () => setState(() => _organization = (id: id, from: OrganizationFrom.dashboard)),
      onOpenOrganization: shell.openOrganization,
      seen: _seenIn(id),
      onJumpTo: (noteId) => _jumpTo(shell, id, noteId),
      onLog: () => shell.openOrganizationLog(id),
      onAccount: _toAccount,
      wisp: wisp,
    );
  }

  /// Reads the library, and gives a fresh one the starter notes once (core/seed.ts: `glyph-sample-note`).
  Future<void> _open() async {
    await _library.load();
    if (!_notesRead.isCompleted) _notesRead.complete();
    // At launch, which opens on the home page: what the phone let go of before it was left.
    if (mounted) unawaited(_takeBack.look());
    // And the tags that waited for a pass or a note's first words while the app was away.
    if (mounted) _settleTags();
    // The links that opened the app wait for the notes to be read, so a copy lands in a library that is there and
    // a note opened is one the list has.
    final links = widget.links;
    if (mounted && links != null) {
      _stopLinks = followAppLinks((link) {
        // The kind and never the link: a share's link carries its key.
        debugPrint('[glyph] a link opened the app: ${readAppLink(link)?.runtimeType ?? 'none of the app\'s'}');
        openAppLink(link, _door, onError: (failure) => debugPrint('[glyph] could not follow the link that opened the app: $failure'));
      }, links);
    }
    if (!_real || !mounted) return;
    final seeded = _stored.flag('glyph-sample-note', unreadable: true);
    if (seeded.isMarked) return;
    seeded.mark();
    if (_library.value.isNotEmpty) return;
    for (final note in starterNotes(DateTime.now().millisecondsSinceEpoch)) {
      await _library.createNote(note.body);
    }
  }

  /// The screen or the open tabs changed: a look at what was left (`takeBack`'s effect). After the frame, when the
  /// shell says where the person is now.
  bool _looking = false;
  void _left() {
    if (_looking) return;
    _looking = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _looking = false;
      if (mounted) unawaited(_takeBack.look());
    });
  }

  void _delete(String id) {
    final note = _library.noteOf(id);
    if (note != null) _actions.remove(note);
  }

  /// The + (`setNewSheet(true)`): the sheet of what it makes, one for every +, so the choice reads the same
  /// wherever it is offered. From an organization's +, what is made is filed in its workspace ([into]).
  void _plus([String? into]) => setState(() {
        _newInto = into;
        _newSheet = true;
      });

  /// A new note (`newNote`): opened ready to type, the caret in line 1 and the editor focused, and fresh, so its
  /// blank page offers names and templates until the person writes in it.
  /// And it starts with where the person is, when Settings says so: the tag waits for the note's first words, so a
  /// note opened and left still leaves nothing behind. Only a note the person makes here: a canvas, a notebook, the
  /// guide, a shared link's copy and a note made for a title are the app's, and are not tagged. Where a fix is
  /// expected its map's box is held first (`willLocate`), so the card arriving never moves line 1.
  void _new([String? into]) {
    final places = _places;
    if (places == null) {
      _showMade('', caret: const Caret.at(0), fresh: true, into: into);
      return;
    }
    unawaited(() async {
      // Asked first, and not waited on for long: the phone answers in a turn, and the box is there from the first
      // frame.
      final expected = await places.willLocate().timeout(const Duration(milliseconds: 300), onTimeout: () => false).then<bool>((will) => will, onError: (Object _) => false);
      if (!mounted) return;
      final note = _showMade('', caret: const Caret.at(0), fresh: true, into: into);
      if (expected) places.holdFor([note.id]);
      await places.tagNewNotesIfWanted([note.id], (reviewing: false), introduce: _introduceLocation);
    }());
  }

  /// A canvas from the + (`newCanvas`).
  void _newCanvas([String? into]) => _showMade(canvasNoteBody('Untitled canvas', _emptyCanvas), into: into);

  /// A notebook from the +, or a journal from the same sheet with Journal chosen (`newBook`, `newJournal`).
  void _newBook(NewBookKind kind, [String? into]) => setState(() {
        _bookInto = into;
        _bookSheet = kind;
      });

  List<String> _notesIn(String workspaceId) => [
        for (final note in _library.value)
          if (_workspaces.value.of[note.id] == workspaceId) note.id,
      ];

  Widget _tree(AppShellState shell, {VoidCallback? onClose}) {
    return NoteTree(
      notes: shell.notes,
      activeId: shell.shown,
      workspaces: _workspaces,
      stored: _stored,
      onOpen: (id) {
        onClose?.call();
        _openWhereLeft(shell, id);
      },
      onNew: () {
        onClose?.call();
        _plus();
      },
      onClose: onClose,
      onCommands: _search,
      onBrowseFiles: _browseFiles,
      notices: _sidebarNotices(),
      onSpeak: _capture == null
          ? null
          : () {
              onClose?.call();
              _speak();
            },
      onSettings: () {
        onClose?.call();
        setState(() => _settings = true);
      },
      trashed: _trashed,
      onRestore: _actions.restore,
      onDestroy: _actions.destroy,
      onEmptyTrash: () => _actions.emptyTrash(_trashed),
      notesInWorkspace: _notesIn,
      onTrashNotes: (ids) => ids.forEach(_trash.trashNote),
      emptyArt: const Ghost(scene: GhostScene.noNotes),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A note drawn small anywhere under here (a card on the home page, a row of the sidebar) draws its pictures and
    // a film's still from the app's own (lib/home/note_peek.dart).
    return PeekPictures(store: _pictures, child: _built(context));
  }

  Widget _built(BuildContext context) {
    return ListenableBuilder(
      listenable: _all,
      builder: (context, _) {
        final prefs = preferences.value;
        final services = _services;
        final signedIn = services?.signedIn ?? false;
        final gate = _gate;
        final voice = _voice;
        final capture = _capture;
        final guide = _guide;
        final recordingScreen = _shell.currentState?.screen.isRecording ?? false;
        // As last known: asking the service afresh tells its listeners, and this is a build.
        final meetingNow = voice?.live?.state;
        final recordingNow = (meetingNow?.recording ?? false) ? meetingNow?.noteId : null;
        // The organization the home page is filtered to, for its news.
        final chosen = _workspaces.value.current?.id;
        String? chosenOrg;
        for (final org in services?.joined ?? const []) {
          if (orgWorkspaceId(org.id) == chosen) chosenOrg = org.id;
        }
        return AccountScope(
          services: services,
          child: Stack(
          fit: StackFit.expand,
          children: [
            AppShell(
              key: _shell,
              sheet: widget.sheet ?? context.tokens.sheet,
              notes: _shown,
              // A note with no words yet is its own screen's alone, as on the page, whose list never holds it.
              drafts: _drafts,
              topBar: TopBarStyle.parse(prefs.topBar),
              sidebarStyle: prefs.sidebarStyle == 'docked' ? SidebarStyle.docked : SidebarStyle.popover,
              workspaces: _workspaces.value,
              organizations: signedIn ? services!.joined : const [],
              organizationBuilder: services == null ? null : _organizationPage,
              onRenameNote: _rename,
              openNotes: prefs.openNotes,
              tabGroups: prefs.tabGroups,
              // The screen and the tabs are what an entry is left by.
              onOpenNotesChanged: (open) {
                preferences.update((now) => now.copyWith(openNotes: open));
                _left();
              },
              // And the walkthrough steps aside for a recorder, so the root is drawn again with the screen.
              onScreenChanged: (_) {
                _left();
                _voiceChanged();
              },
              untouchedEntryOf: (id) => _untouched.recordOf(id)?.journalId,
              onTabGroupsChanged: (groups) => preferences.update((now) => now.copyWith(tabGroups: groups)),
              onSettings: () => setState(() => _settings = true),
              // The people icon with no organization joined, and the picker's last row: Settings › Organizations.
              onOrganizations: () => setState(() {
                _settings = true;
                _settingsPage = SettingsTarget('organizations', nonce: DateTime.now().microsecondsSinceEpoch);
              }),
              onNew: _plus,
              onDeleteNote: _delete,
              onRefresh: () => _library.refresh(),
              noteBuilder: _note,
              // The recorder, the whole window: a fresh mount for each capture, keyed by the shell.
              captureBuilder: voice == null || capture == null
                  ? null
                  : (context, shell, screen) => CaptureScreen(
                        recorder: voice.recorder,
                        fromAssistant: screen.fromAssistant,
                        stopRequests: screen.stop,
                        noteId: screen.noteId,
                        placing: screen.placing is Placing ? screen.placing as Placing : null,
                        meeting: screen.meeting,
                        onMeeting: voice.canMeet ? () => unawaited(capture.meeting(false)) : null,
                        onFinish: (note, locked, {review, ask, landing}) => unawaited(capture.finished(note, locked, review: review, ask: ask, landing: landing)),
                      ),
              // Ghost.md Academy, the whole window: out by its arrow, and its contents' way to the cheat sheet.
              academyBuilder: (context, shell) => AcademyScreen(
                onDone: shell.backToList,
                onCheatSheet: () {
                  shell.backToList();
                  setState(() {
                    _settings = true;
                    _settingsPage = SettingsTarget('cheatsheet', nonce: DateTime.now().microsecondsSinceEpoch);
                  });
                },
              ),
              meetingBuilder: voice == null || capture == null || voice.live == null
                  ? null
                  : (context, shell, screen) => MeetingScreen(
                        noteId: screen.noteId,
                        fromAssistant: screen.fromAssistant,
                        onLeave: capture.leftMeeting,
                        live: voice.live!,
                        host: _meetingHost(voice, voice.live!),
                      ),
              homeBuilder: (context, shell) => HomeScreen(
                notes: shell.notes,
                loading: !_read,
                workspaces: _workspaces,
                layout: homeLayoutOf(prefs.homeLayout),
                onOpen: (id) => _openFromHome(shell, id),
                onNew: _plus,
                // The dock's microphone, and the note of the meeting being recorded now.
                onCapture: capture == null ? null : _speak,
                recording: recordingNow,
                // `isAndroid ? 'Write it, or hold the side key and say it.'`: the page says the side key on any Android
                // phone, whether or not this build answers it, and the empty page's words are held to the page's.
                sideKey: defaultTargetPlatform == TargetPlatform.android,
                notices: _notices(),
                gists: _gists?.value ?? const {},
                clock: widget.clock,
                onAllNotes: shell.showAllNotes,
                onSearch: _search,
                // `tabs.drop(note.id)` before an archive or a delete (App.tsx `onSwipe`): the swiped note's tab goes too.
                onSwipe: (note, action) {
                  if (action.name != 'pin') _shell.currentState?.dropTab(note.id);
                  _actions.swipe(note, action);
                },
                onRefresh: _library.refresh,
                onNoteMenu: (id) => _menu.open(id, MediaQuery.sizeOf(context).center(Offset.zero)),
                onManageWorkspace: (workspace) => setState(() => _workspace = (editing: workspace)),
                organizations: homeOrganizations(services, here: {for (final row in services?.joined ?? const <OrgRow>[]) row.id: _seenIn(row.id)}),
                orgNews: homeOrgNews(services, chosenOrg),
                onOrganization: services == null ? null : shell.openOrganization,
                onOrganizationSettings: services == null ? null : (id) => setState(() => _organization = (id: id, from: OrganizationFrom.settings)),
                onNewOrganization: signedIn ? () => setState(() => _newOrganization = true) : null,
                headerEdge: (context, edge, scroller) => WispEdge(under: edge.under, foot: true, child: scroller),
                dockHalo: (context, it) => DockSmoke(behind: it.behind, dock: it.dock, alignment: it.alignment, padding: it.padding),
                ghost: (context, it) => Ghost(
                  scene: switch (it.scene) {
                    HomeGhostScene.noNotes => GhostScene.noNotes,
                    HomeGhostScene.emptyWorkspace => GhostScene.emptyWorkspace,
                    HomeGhostScene.searchNothing => GhostScene.searchNothing,
                  },
                  size: it.lead ? GhostSize.lead : GhostSize.small,
                  heightShare: it.heightShare,
                ),
              ),
              allNotesBuilder: (context, shell, screen) => AllNotesScreen(
                // The empty page's hint, as home's: the side key on any Android phone (AllNotesScreen.tsx `isAndroid`).
                sideKey: defaultTargetPlatform == TargetPlatform.android,
                notes: shell.notes,
                loading: !_read,
                workspaces: _workspaces,
                stored: _stored,
                tapes: screen.tapes,
                gists: _gists?.value ?? const {},
                clock: widget.clock,
                onOpen: (id) => _openWhereLeft(shell, id),
                onBack: shell.backToList,
                onRefresh: _library.refresh,
                onNoteMenu: (note, at) => _menu.open(note.id, at),
                notesInWorkspace: _notesIn,
                onTrashNotes: (ids) => ids.forEach(_trash.trashNote),
                wisp: prefs.wispEdge,
              ),
              sidebarBuilder: (context, shell, close) => NotesDrawer(
                open: true,
                notes: shell.notes,
                activeId: shell.shown,
                workspaces: _workspaces,
                stored: _stored,
                onOpen: (id) {
                  close();
                  _openWhereLeft(shell, id);
                },
                onNew: () {
                  close();
                  _plus();
                },
                onClose: close,
                onCommands: _search,
                onBrowseFiles: _browseFiles,
                // `notices={split ? notices : undefined}`: a phone has its home page for them.
                notices: splitFits(MediaQuery.sizeOf(context), mouse: mousePointer) ? _sidebarNotices() : const [],
                onSpeak: capture == null
                    ? null
                    : () {
                        close();
                        _speak();
                      },
                onSettings: () {
                  close();
                  setState(() => _settings = true);
                },
                trashed: _trashed,
                onRestore: _actions.restore,
                onDestroy: _actions.destroy,
                onEmptyTrash: () => _actions.emptyTrash(_trashed),
                notesInWorkspace: _notesIn,
                onTrashNotes: (ids) => ids.forEach(_trash.trashNote),
                emptyArt: const Ghost(scene: GhostScene.noNotes),
              ),
              dockedSidebarBuilder: (context, shell) => _tree(shell),
              // The docked sidebar and the aside, shown or hidden as this device left them (core/useWideScreen.ts
              // `readSidebarShown`, aside/aside.ts `readAsideShown`).
              sidebarShown: readSidebarShown(_stored),
              onSidebarShownChanged: (shown) => writeSidebarShown(shown, _stored),
              asideShown: readAsideShown(_stored),
              onAsideShownChanged: (shown) => writeAsideShown(shown, _stored),
              // The open note's book or run of chapters, beside it (aside/aside_panel.dart). The version history's
              // tab is a desktop's (`asideHistory`), and waits for one.
              asideBuilder: (context, shell) {
                final content = _asideOf(shell);
                return content == null ? null : AsidePanel(content: content, stored: _stored, onOpen: shell.openNoteWithin, onOpenTitle: _openTitleWithin);
              },
              asideCardBuilder: (context, shell, close) =>
                  AsideCard(content: _asideOf(shell), stored: _stored, onOpen: shell.openNoteWithin, onOpenTitle: _openTitleWithin, onClose: close),
              notificationsBuilder: (context, shell, close) {
                void openNote(String id, String? at) {
                  close();
                  // A note Claude edited opens at its first changed line; any other where it was left.
                  if (at == null) return _openWhereLeft(shell, id);
                  shell.openNote(id, at: at);
                }

                void account() {
                  close();
                  _toAccount();
                }

                if (services != null) {
                  return FedNotificationsDrawer(
                    services: services,
                    onClose: close,
                    onOpenNote: openNote,
                    onOpenOrganization: (id) {
                      close();
                      shell.openOrganization(id);
                    },
                    onAccount: account,
                  );
                }
                return NotificationsDrawer(notifications: const [], prefs: prefs.notifications, signedIn: false, onClose: close, onOpenNote: openNote, onOpenOrganization: (_) => close(), onAccount: account);
              },
            ),
            // The phone at work, over the app, while a review is on the note being read (lib/scene/at_work.dart).
            if (_noteAi case final noteAi? when _noteAiId != null)
              AtWork(
                noteId: _noteAiId!,
                opening: noteAi.reviewKey,
                heard: noteAi.handoff?.heard ?? '',
                body: _library.noteOf(_noteAiId!)?.body ?? '',
                hasJob: noteAi.handoff?.job != null,
                stage: noteAi.reviewStage.value,
                refining: voice?.recorder.refining?.refining,
                summaryDue: voice?.summaries?.pendingFor(_noteAiId!),
              ),
            SettingsSheet(
              open: _settings,
              toPage: _settingsPage,
              onClose: () => setState(() => _settings = false),
              workspaces: _workspaces,
              notesInWorkspace: _notesIn,
              onTrashNotes: (ids) => ids.forEach(_trash.trashNote),
              // About's Updates rows, in a build that looks for any (lib/root/update_wiring.dart).
              // An iPhone has no update client: About says whose its updates are (iphone_wiring.dart).
              updates: widget.updates == null ? appStoreUpdates() : settingsUpdatesOf(widget.updates!),
              // A build with no service says so where a way in is pressed; one with an account takes it from the scope.
              features: _features(services),
              onOrganization: services == null ? null : (id) => setState(() => _organization = (id: id, from: OrganizationFrom.settings)),
              onOpenLink: widget.openLink == null ? null : (url) => unawaited(widget.openLink!(url)),
              onAcademy: () {
                setState(() => _settings = false);
                _shell.currentState?.show(const Screen.academy());
              },
              onGuide: guide == null
                  ? null
                  : () {
                      setState(() => _settings = false);
                      guide.show(0);
                    },
              onGuideBook: () => unawaited(_openGuideBook()),
            ),
            CommandBar.over(
              key: _commands,
              world: () => paletteWorldFor(shell: _shell.currentState!, workspaces: _workspaces.value, prefs: preferences.value),
              doing: () => paletteDoingFor(
                shell: _shell.currentState!,
                library: _library,
                workspaces: _workspaces,
                newNote: _new,
                newNotebook: () => _newBook(NewBookKind.notebook),
                newJournal: () => _newBook(NewBookKind.journal),
                newEntry: (id) => unawaited(_newEntry(id)),
                academy: () => _shell.currentState?.show(const Screen.academy()),
                guide: guide == null ? null : () => guide.show(0),
                speak: _capture == null ? null : _speak,
                speakInto: _capture == null ? null : (id) => unawaited(_speakInto(id)),
                openNoteWhereLeft: (id) {
                  final note = _library.noteOf(id);
                  final shell = _shell.currentState;
                  if (note != null && shell != null) shell.openNote(whereLeft(note, _shown, shell.shown, on: _stored).id);
                },
                archive: (id) {
                  final note = _library.noteOf(id);
                  if (note == null) return;
                  _shell.currentState?.dropTab(id);
                  _actions.archive(note, archived: true);
                },
                removeNote: _delete,
                settings: () => setState(() => _settings = true),
                settingsPage: (id) => setState(() {
                  _settings = true;
                  _settingsPage = SettingsTarget(id, nonce: DateTime.now().microsecondsSinceEpoch);
                }),
              ),
            ),
            NoteMenuHost(
              controller: _menu,
              notes: _shown,
              onOpen: (note) {
                final shell = _shell.currentState;
                if (shell != null) _openWhereLeft(shell, note.id);
              },
              // The note itself, with a comment started on its first line once its editor is there
              // (core/comments/ask.ts).
              onComment: (note) {
                commentAsks.ask(note.id);
                _shell.currentState?.openNote(note.id);
              },
              onPin: _actions.pin,
              onArchive: (note, archived) => _actions.archive(note, archived: archived),
              onDelete: (note) => _delete(note.id),
            ),
            // What the + makes (notes/NewSheet.tsx). The rows read where to make it as they are pressed, since the
            // sheet closes first.
            Builder(builder: (context) {
              final into = _newInto;
              return NewSheet(
                open: _newSheet,
                onClose: () => setState(() {
                  _newSheet = false;
                  _newInto = null;
                }),
                onNote: () => _new(into),
                onCanvas: () => _newCanvas(into),
                onBook: () => _newBook(NewBookKind.notebook, into),
                // A journal's entry is the account's own, and is not offered from an organization's +.
                entry: into != null || !_newSheet ? null : _entryRow(),
                // A shared link's copy is read from the account's service: not offered in a build with none.
                onFromLink: into != null || services?.shares == null ? null : _forkFromLink,
                // A meeting is the account's own too, and is offered only where one can be recorded.
                onMeeting: into == null && capture != null && (voice?.canMeet ?? false) ? () => unawaited(capture.meeting(false)) : null,
                sound: into == null && capture != null && (voice?.canMeet ?? false) && (voice?.sound?.supported ?? false)
                    ? NewSheetSound(
                        // The page's words for it on this platform (`meetingSoundWords`): other apps' sound on
                        // Android, the computer's own on a Mac.
                        label: voice?.recorder.systemSound?.meetingSoundWords().label ?? 'Include sound from other apps',
                        hint: voice?.recorder.systemSound?.meetingSoundWords().hint ??
                            'Android lets Ghost.md hear media and games, never calls. It asks to share your screen each time; only the sound is kept.',
                        on: prefs.meetingSound,
                        onToggle: () => preferences.update((now) => now.copyWith(meetingSound: !now.meetingSound)),
                      )
                    : null,
              );
            }),
            NewBookSheet(
              open: _bookSheet != null,
              kind: _bookSheet ?? NewBookKind.notebook,
              onClose: () => setState(() => _bookSheet = null),
              titles: _bookSheet == null ? const [] : _pageTitles(books: false),
              isCanvas: (title) => isCanvasBody(_reads.titled(title)?.body ?? ''),
              onCreate: (title, pages) => _showMade(bookNoteBody(title, pages), into: _bookInto),
              onCreateJournal: (title, template, place) => _showMade(journal.journalNoteBody(title, template, place)),
              // A journal's "With where you are": the prompt from the press that turned it on, and why it cannot.
              device: _places == null
                  ? const EntryPlaceDevice()
                  : EntryPlaceDevice(cannot: () => _places.locations.cannotLocate, refused: _places.autoTagRefusal, allowWhere: _places.allowLocationWhere(), ask: _places.askFromPress),
            ),
            if (_workspace case final sheet?)
              WorkspaceManageSheet(
                store: _workspaces,
                editing: sheet.editing,
                onClose: () => setState(() => _workspace = null),
                notesIn: _notesIn,
                onTrashNotes: (ids) => ids.forEach(_trash.trashNote),
              ),
            if (services != null) ...[
              if (_organization case final sheet? when services.orgs != null)
                OrganizationSheet(
                  key: ValueKey('organization-sheet:${sheet.id}'),
                  services: services,
                  orgId: sheet.id,
                  from: sheet.from,
                  landOnMembers: sheet.from != OrganizationFrom.dashboard,
                  onClose: () => setState(() => _organization = null),
                  onNotes: () {
                    setState(() => _organization = null);
                    _workspaces.chooseWorkspace(orgWorkspaceId(sheet.id));
                    _shell.currentState?.backToList();
                  },
                ),
              NewOrganizationSheet(
                services: services,
                open: _newOrganization,
                onClose: () => setState(() => _newOrganization = false),
                onMade: (id) {
                  setState(() => _newOrganization = false);
                  _shell.currentState?.openOrganization(id);
                },
              ),
              // The way in, the first thing on screen once, on an open that is signed out.
              if (gate != null && gate.open) AccountGate(services: services, onDone: gate.close),
            ],
            // An invite link that opened the app, and a code held on this device from before, asked about once
            // someone is signed in: nothing is joined until the person says so. Held back while the way into an
            // account is up at launch.
            JoinInvites(
              services: services,
              request: _joinRequest,
              hold: services != null && (gate?.open ?? true),
              onOpen: (id) => _shell.currentState?.openOrganization(id),
              onAccount: _toAccount,
            ),
            // The walkthrough, over everything but the way into an account, and never over a recorder: it is taken
            // away while a capture is on screen and comes back, at its page, when the capture ends.
            if (guide != null && guide.open && !(gate?.open ?? false) && !recordingScreen)
              Guide(
                index: guide.page,
                tooSoon: guide.tooSoon,
                onIndex: guide.turn,
                recordsVoice: capture != null,
                models: _modelsForGuide,
                onClose: () {
                  guide.close();
                  // The list underneath loaded while the guide was up; ask again now it shows.
                  unawaited(_library.refresh().catchError((Object _) {}));
                },
                onAcademy: () {
                  guide.close();
                  _shell.currentState?.show(const Screen.academy());
                },
              ),
            if (_launching) LaunchScreen(loading: !_read, notes: _shown.length, updates: launchUpdatesOf(widget.updates), sync: launchSyncOf(_services?.engine?.status.value.phase), recording: () => voice?.live?.state?.recording ?? false, onDone: () => setState(() => _launching = false)),
          ],
          ),
        );
      },
    );
  }
}

/// What the app does with each kind of link that opened it (`useAppLinks`' `fork`, `openNote`, `openPlace`, `join`).
class _RootDoor implements AppLinkDoor {
  const _RootDoor(this.root);
  final _GhostRootState root;

  @override
  Future<void> fork(String link) => root._forkFromLink(link);

  @override
  Future<void> openNote(String id) => root._openNoteFromLink(id);

  /// The notifications drawer, or an organization's dashboard, which only a build with an account has.
  @override
  void openPlace(LinkedPlace place) {
    final shell = root._shell.currentState;
    if (shell == null) return;
    switch (place) {
      case NotificationsPlace():
        shell.showNotifications();
      case OrganizationPlace(:final orgId):
        if (root._services != null) shell.openOrganization(orgId);
    }
  }

  @override
  void join(String code) => root._joinFromLink(code);
}
