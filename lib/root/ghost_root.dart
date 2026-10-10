import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, ValueListenable, defaultTargetPlatform, listEquals, mapEquals, setEquals;
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
import '../book/chapter_number.dart' show chapterOf;
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
import '../canvas/how_canvas.dart' show howCanvasBody;
import '../canvas/json_canvas.dart' show Canvas, canvasNoteBody;
import '../canvas/sample_canvas.dart' show sampleCanvasBody;
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
import '../core/note_facts.dart' show NoteFacts;
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
import '../format/gist.dart' show Gists, gistFor, gistVisible, gistsCameBack, pauseGists;
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
import '../notes/all_notes.dart' show readSort;
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
import '../perf/frame_log.dart';
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
import 'gisted.dart';
import 'library_reads.dart';
import 'note_desk.dart';
import 'opening.dart';
import 'reset_wiring.dart';
import 'scene_play.dart';
import 'selected.dart';
import 'take_back.dart';
import 'iphone_wiring.dart';
import 'update_wiring.dart';
import 'voice_wiring.dart';

part 'root_commands.dart';
part 'root_voice.dart';

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
  const GhostRoot({super.key, this.sheet, this.core, this.library, this.workspaces, this.stored, this.clock, this.launch = true, this.launchSeat, this.account, this.services, this.untouched, this.links, this.openLink, this.voice, this.voiceMaking, this.previewFetch, this.native, this.restart, this.guide, this.tapePlayer, this.updates, this.locator, this.placeLookup, this.mapTiles, this.picturePicker, this.films, this.dayPicker});

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

  /// Where the root says what the launch screen reads of it, when that screen is drawn over the root by whoever
  /// holds it and was up before there was a root (lib/root/opening.dart). Given, the root draws none of its own.
  final LaunchSeat? launchSeat;

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

/// The root's state is one class in more than one file, by what each part of it is for. Here: what the app is made
/// of (the library, the trash, the workspaces, the account, voice and what each is listened to by), which sheet is
/// open, and what is put on screen. What it does to the library, the making, opening, writing and renaming of
/// notes, is lib/root/root_commands.dart; voice and the AI, made after the first frame, and what the recorder's
/// and Settings' screens ask of them, lib/root/root_voice.dart.
class _GhostRootState extends State<GhostRoot> {
  late final bool _real = widget.core != null && widget.library == null;
  late final NoteLibrary _library = widget.library ?? (_real ? CoreLibrary(widget.core!) : SampleLibrary.seeded(now: DateTime.now().millisecondsSinceEpoch));
  late final Trash _trash = _real ? KeptTrash() : MemoryTrash();
  /// Where the real workspaces are kept, when the root makes them: it listens to the preferences, and is let go
  /// with the root.
  late final KeptWorkspaceStorage? _keptSpaces = widget.workspaces == null && _real ? KeptWorkspaceStorage() : null;
  late final WorkspaceStore _workspaces = widget.workspaces ??
      (_keptSpaces != null
          ? WorkspaceStore(storage: _keptSpaces, trash: _trash, onFiled: NoteFolders(_library).fileNotesInFolder)
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
          // A shared link follows the notes, by whichever hand they changed (lib/share/share.dart `follow`).
          notesChanged: _library,
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

  /// Someone came, went, or opened another note: the home page's cards and the organization's rows say so, and
  /// nothing else is drawn again for it. A team's note says it has been left as its desk is let go, which is while
  /// the tree is being built or taken down: a part told then is drawn after that frame (lib/root/selected.dart),
  /// where asking at once threw inside the desk's `dispose` and left its listeners behind (seen on the emulator, on
  /// leaving a team's note).
  void _presenceChanged() {
    _presenceAt += 1;
    _tick.tell();
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

  /// The meeting's state, whether the phone may notify or whether the AI can run here changed: the parts that read
  /// voice are told (the home page's recording, Settings' rows, the + sheet's meeting), after the frame where one
  /// is being built (lib/root/selected.dart).
  void _voiceChanged() {
    _voiceAt += 1;
    _tick.tell();
  }

  /// The models on this phone, or one's fetch: Settings' AI page and the walkthrough's model page.
  void _modelsChanged() {
    _modelsAt += 1;
    _tick.tell();
  }

  /// The app's updates: the notice above the notes and in the sidebar, About's rows, the launch screen's line.
  void _updatesChanged() {
    _updatesAt += 1;
    _tick.tell();
  }

  /// The AI of the note on screen, or its review's stage: the scene over the window.
  void _aiChanged() {
    _aiAt += 1;
    _tick.tell();
  }

  /// The gists' runner spoke: read again by whoever shows them, and drawn again only if a line is another
  /// (`_gistsShown`). It speaks twice a turn whether or not it wrote anything.
  void _gistsChanged() {
    _gistsRead = false;
    _tick.tell();
  }

  /// The voice model's fetch as its line says it.
  static notices.VoiceModel _voiceModelState(VoiceModel? model) => switch (model?.state) {
        VoiceModelStateDownloading(:final received, :final total) => notices.VoiceModelDownloading(received: received, total: total),
        VoiceModelStateFailed(:final message) => notices.VoiceModelFailed(message),
        _ => const notices.VoiceModelQuiet(),
      };

  /// Whether the voice model has a line above the notes, and which: nothing, its fetch, or why it failed. The
  /// fetch's progress is the line's own to follow.
  Object? get _voiceModelLine => switch (_voice?.recorder.voiceModel.state) {
        VoiceModelStateDownloading() => true,
        VoiceModelStateFailed(:final message) => message,
        _ => null,
      };

  /// What is waiting on the person, above the notes (notes/Notices.tsx), in the page's order: a new version of the
  /// app (lib/root/update_wiring.dart, from [GhostRoot.updates]), an invitation to an organization where the build
  /// has an account, and the voice model while it is not ready.
  List<Widget> _notices() {
    final updates = widget.updates;
    final services = _services;
    final model = _voice?.recorder.voiceModel;
    return [
      if (updates != null && updates.apk is! ApkPhaseNone) notices.UpdateNotice(updates: updateCardOf(updates)),
      if (services != null) InviteWaiting(services: services, onOpen: (id) => _shell.currentState?.openOrganization(id)),
      if (model != null && _voiceModelLine != null)
        ListenableBuilder(listenable: model, builder: (context, _) => notices.VoiceModelStatus(state: _voiceModelState(model), onRetry: model.retry)),
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

  /// Local only, listened to alone (`PreferencesStore.select`): it is read as the root begins to listen, so its first
  /// change is a change. Kept in a field read for the first time by the listener itself, it was read after it had
  /// moved, and the first switching off went unseen.
  late final ValueListenable<bool> _localOnly = preferences.select((prefs) => prefs.localOnly);

  /// Switched off, the fills parked while nothing could leave the phone are pressed again, where the queue was
  /// started.
  void _localOnlyMoved() {
    if (!_localOnly.value && _stopFills != null) resumeParked();
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

  /// A Speak button (`speak`): a capture into a new note, or the note its first command names.
  void _speak() => unawaited(_capture?.start(false));

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
        if (mounted) setState(() => _canBrowse = true);
      });

  /// Whether the phone has said it can show the folder: what a sidebar is drawn again for.
  bool _canBrowse = false;

  /// Which tapes' audio is on this device (lib/settings/tapes_here.dart): each tape's file is asked through the
  /// player as Settings' Tapes card is put up, as the page's card asked the `rec` scheme (`headStatus`).
  late final TapesHere _tapes = TapesHere(widget.tapePlayer?.onDevice);

  /// The room the tapes on this device take, and the old ones among them: only the tapes whose audio is here, not
  /// one the row removed nor one whose file says it is elsewhere. Read once per change to the notes or to what is
  /// known of the tapes, and the same answer while the room and the old ones are the same: Settings is handed it
  /// open or shut, and is not built again for a save that touched no tape.
  ({int bytes, List<String> old}) get _tapeFacts {
    final all = _library.value;
    if (identical(all, _tapedOf) && _tapesAt == _tapedAt) return _taped;
    _tapedOf = all;
    _tapedAt = _tapesAt;
    final taped = _tapes.here(all);
    final old = [for (final note in oldTapes(taped, DateTime.now().millisecondsSinceEpoch)) note.id];
    final bytes = tapeBytes(taped);
    return bytes == _taped.bytes && listEquals(old, _taped.old) ? _taped : _taped = (bytes: bytes, old: old);
  }

  List<Note>? _tapedOf;
  int _tapedAt = -1;
  ({int bytes, List<String> old}) _taped = (bytes: 0, old: const []);

  /// The walkthrough (shell/useGuide.ts): open by itself on the first launch that is not the side key's capture,
  /// and from Settings and the palette after. Made as the root is, the device's memory having been read by then.
  late final GuideController? _guide = widget.guide ??
      (_real ? GuideController(launchedByKey: (widget.voiceMaking?.assistant ?? false) && widget.voiceMaking?.launch == 'capture') : null);

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

  late final AppLinkDoor _door = _RootDoor(this);

  /// The + sheet, the workspace it makes into where it was an organization's +, and the New notebook sheet with its
  /// own.
  bool _newSheet = false;
  String? _newInto;
  NewBookKind? _bookSheet;
  String? _bookInto;

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

  /// Whether your templates are being made now (`_openTemplates`): a second press meanwhile is the same press.
  bool _seeding = false;

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

  /// A note's screen with its editor: one desk to an open note (lib/root/note_desk.dart). Built again when the
  /// screen is another (the note, what it was opened with), and when what it reads of the app is: the other notes
  /// (the titles that are taken, its place in its notebook, your templates; so a notebook thrown away takes its bar
  /// off the page being read at once, not when its Undo runs out), the trash, the workspaces, the preferences and
  /// the account. Not for a keystroke, the home page's news or a runner's turn; and **not for the note's own
  /// save**, of which the screen it is handed here shows nothing: it is built from the note as it was opened
  /// (`screen.note`, as the page's is), every other note's title, and its notebook's index, and what its editor
  /// holds, its saving and its pin are its own to follow (`_notesBut`).
  Widget _note(BuildContext context, AppShellState shell, ScreenNote screen) => Selected(
        listenable: _tick,
        name: 'note',
        select: () => (screen, _notesBut(screen.note.id), _trash.value, _made?.hidden, _workspaces.value, _prefsAt, _capture != null, _accountAt),
        builder: (context, _) => _desked(context, shell, screen),
      );

  Widget _desked(BuildContext context, AppShellState shell, ScreenNote screen) => NoteDesk(
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

  /// The note actions (a delete waiting on its Undo), the walkthrough or the way into an account changed.
  void _changed() {
    _reads.changed();
    // The notes changed: a meeting's note may have been written by the service, and a write-up's result may wait.
    _voice?.notesChanged();
    _tick.tell();
  }

  // ---- what changed, and who is told (lib/root/selected.dart) ---------------------------------------------------

  /// Told by everything the root is told by. Each part of the app the root puts on screen listens to it and asks,
  /// each time, whether what it reads is another value: the part that reads it is built again, and no other.
  final RootTick _tick = RootTick();

  /// The root draws nothing that changes: what it puts on screen is made once ([_whole]) and each part of it is
  /// built again by itself. So a change to what the root holds (a sheet opened, voice made) is not a build of the
  /// root, which would build nothing: the parts are told, and the ones that read it draw it.
  @override
  void setState(VoidCallback fn) {
    fn();
    _tick.tell();
    // A frame follows, as one followed every setState: what waits for the next frame (`_afterFrame`) is not left
    // waiting where no part had anything to draw.
    if (mounted) WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// What has no one value to compare is counted, and a part that reads it selects its count: the account (who is
  /// signed in, the organizations, the feed, the shares), where the sync stands, who is in an organization's notes,
  /// voice (a meeting's state, whether the phone may notify, whether the AI can run), the models and their
  /// fetches, the app's updates, the AI of the note on screen, and what is known of the tapes on this device.
  int _accountAt = 0, _syncAt = 0, _presenceAt = 0, _voiceAt = 0, _modelsAt = 0, _updatesAt = 0, _aiAt = 0, _tapesAt = 0;

  /// Any preference at all, for the two parts that hand the whole of them on (a note's desk, the palette): the
  /// others select the fields they read. Counted, not compared: two sets of preferences are told apart by writing
  /// both out.
  int _prefsAt = 0;

  void _prefsChanged() {
    _prefsAt += 1;
    _tick.tell();
  }

  void _accountChanged() {
    _accountAt += 1;
    _tick.tell();
  }

  /// Where the sync stands changes twice for every save it sends: it is the launch screen's line and the account's
  /// own sheets', and no screen of notes reads it.
  void _syncChanged() {
    _syncAt += 1;
    _tick.tell();
  }

  /// What the account is listened to by, less where its sync stands (`AccountServices.changes` is all of them).
  static List<Listenable?> _accountSays(AccountServices services) => [services.account, services.orgs, services.orgKeys, services.feed, services.shares, services.liveTyping];

  /// The notes every screen shows: none in the Trash, none a pending delete is holding back. The same list for as
  /// long as the library's, the trash and what is held back are the same, and while the notes in it are.
  List<Note> get _shown {
    final all = _library.value;
    final held = _trash.value;
    final hidden = _made?.hidden ?? const <String>{};
    if (identical(all, _shownOf) && identical(held, _shownLess) && identical(hidden, _shownHid)) return _shownNow;
    _shownOf = all;
    _shownLess = held;
    _shownHid = hidden;
    final next = [
      for (final note in outOfTrash(all, held))
        if (!hidden.contains(note.id)) note,
    ];
    var same = next.length == _shownNow.length;
    for (var i = 0; same && i < next.length; i += 1) {
      same = identical(next[i], _shownNow[i]);
    }
    return same ? _shownNow : _shownNow = List.unmodifiable(next);
  }

  List<Note>? _shownOf;
  TrashHeld? _shownLess;
  Set<String>? _shownHid;
  List<Note> _shownNow = const [];

  /// Whether [now] is [was] but for the note [id], which is in both: every other note the same object as it was
  /// and in the order it was. An open note saved is this: it is another object, at the head of the list now.
  static bool _sameButFor(List<Note> was, List<Note> now, String id) {
    if (was.length != now.length) return false;
    var i = 0, j = 0, found = 0;
    while (i < was.length || j < now.length) {
      if (i < was.length && was[i].id == id) {
        i += 1;
        found |= 1;
      } else if (j < now.length && now[j].id == id) {
        j += 1;
        found |= 2;
      } else if (i < was.length && j < now.length && identical(was[i], now[j])) {
        i += 1;
        j += 1;
      } else {
        return false;
      }
    }
    return found == 3;
  }

  /// A number that is another whenever any note but [id] changed, came or went, and the same through a change to
  /// [id] alone: what the screen of the note [id] reads of the library.
  int _notesBut(String id) {
    final all = _library.value;
    final was = _butOf;
    if (id != _butFor || was == null) {
      _butFor = id;
      _butAt += 1;
    } else if (!identical(all, was) && !_sameButFor(was, all, id)) {
      _butAt += 1;
    }
    _butOf = all;
    return _butAt;
  }

  String? _butFor;
  List<Note>? _butOf;
  int _butAt = 0;

  /// The notes the shell was last built with, and what it drew of the one on screen: its title, and whether it is
  /// a canvas or a notebook (a tab's name, and whether its menu offers Rename). Read from the note as that build
  /// had it, the first time a change is measured against it.
  List<Note> _shellNotes = const [];
  ({List<Note> of, String id, String title, bool named})? _shellDrew;

  ({List<Note> of, String id, String title, bool named})? _drewOf(List<Note> built, String id) {
    final had = _shellDrew;
    if (had != null && identical(had.of, built) && had.id == id) return had;
    for (final note in built) {
      if (note.id != id) continue;
      // Read and not kept: the reading kept for this note is of its words as they are now.
      final facts = NoteFacts.read(note.body);
      return _shellDrew = (of: built, id: id, title: facts.title, named: facts.isBook || facts.isCanvas);
    }
    return _shellDrew = null;
  }

  /// The notes as the shell is to draw them: the ones a screen shows, but the list it was last built with while
  /// that differs only by the note on screen, saved, and the shell draws nothing of the difference. Its tab says
  /// the title its editor has (lib/core/live_titles.dart), so a save that leaves the title and the kind of note as
  /// they were changes no tab; and with no index beside the note (it is no notebook, no page of one, no numbered
  /// chapter) the aside has nothing to read of it. The shell is handed the notes as they now are all the same,
  /// without a build ([AppShellState.takeNotes]): what its screens list, and a note it is asked to open, are never
  /// behind. The page's own list is not read again for an editor's save at all.
  List<Note> get _shellDraws {
    final shown = _shown;
    final built = _shellNotes;
    if (identical(shown, built)) return built;
    final shell = _shell.currentState;
    final on = shell?.shown;
    if (shell == null || on == null || _asideFor != on || _aside != null || !_sameButFor(built, shown, on)) return shown;
    final drew = _drewOf(built, on);
    final now = _library.noteOf(on);
    if (drew == null || now == null || drew.named || chapterOf(drew.title) != null) return shown;
    final facts = NoteFacts.of(now);
    if (facts.title != drew.title || facts.isBook || facts.isCanvas) return shown;
    shell.takeNotes(shown);
    return built;
  }

  /// The notes in the Trash, read once per change to the notes or to the trash.
  List<Note> get _trashed {
    final all = _library.value;
    final held = _trash.value;
    if (identical(all, _trashedOf) && identical(held, _trashedIn)) return _trashedNow;
    _trashedOf = all;
    _trashedIn = held;
    return _trashedNow = inTrash(all, held);
  }

  List<Note>? _trashedOf;
  TrashHeld? _trashedIn;
  List<Note> _trashedNow = const [];

  /// The notes made in this run that have no file yet (`CoreLibrary.isDraft`): the core leaves them out of its
  /// list. Read once per change to the notes, and the same set while the same notes are drafts.
  Set<String> get _drafts {
    final library = _library;
    if (library is! CoreLibrary) return const {};
    final all = library.value;
    if (identical(all, _draftsOf)) return _draftsNow;
    _draftsOf = all;
    final next = {
      for (final note in all)
        if (library.isDraft(note.id)) note.id,
    };
    return setEquals(next, _draftsNow) ? _draftsNow : _draftsNow = next;
  }

  List<Note>? _draftsOf;
  Set<String> _draftsNow = const {};

  /// Each note's gist for the page on screen, which is the only page the runner works for (`useGists(carded)`,
  /// lib/root/gisted.dart). [by] says which page it is and what it was laid out from: where that is another, the
  /// runner is shown the page's first cards ([carded]) in place of the ones it had. Under a note neither page asks,
  /// and the runner goes on with the cards it was last shown, as the page's does. The map is read again after the
  /// runner has spoken, and is the same map while no line in it is another.
  ///
  /// **With no model on the phone the runner is shown nothing.** It has no way to write a line then, and shown
  /// notes that are owed one it does not stop: every 800 ms it takes the first, says it has begun, finds there is no
  /// model, says it has ended and waits to begin again, for as long as the app is open (lib/format/gist.dart
  /// `_pump`; measured as two tellings of the whole app every turn, in every stretch of the walk, on a Mac and an
  /// emulator that have no model). The lines already kept for the cards are still read and drawn, by the same
  /// reading the runner's own map is made with (`gistFor`); and the cards are shown to it the moment a model is
  /// there (`_modelsChanged`).
  Map<String, String> _gistsOn(Object by, List<Note> Function() carded) {
    final gists = _gists;
    if (gists == null) return const {};
    final writes = presentIds(_voice?.models?.models ?? const []).isNotEmpty;
    final asked = (by, writes);
    if (asked != _gistedBy) {
      _gistedBy = asked;
      _gisted = carded();
      gists.show(writes ? _gisted : const []);
      _gistsRead = false;
    }
    if (!_gistsRead) {
      _gistsRead = true;
      final read = <String, String>{
        for (final note in _gisted)
          if (gistFor(note.id, note.body) case final String gist) note.id: gist,
      };
      if (!mapEquals(read, _gistsNow)) _gistsNow = Map.unmodifiable(read);
    }
    return _gistsNow;
  }

  /// The cards the page on screen begins with: whose lines are read.
  List<Note> _gisted = const [];

  /// The home page's: its first sixteen cards, as it lays out the notes it is handed today.
  Map<String, String> _homeGists(AppShellState shell) {
    final notes = shell.notes;
    final layout = homeLayoutOf(preferences.value.homeLayout);
    final now = widget.clock?.call() ?? DateTime.now().millisecondsSinceEpoch;
    return _gistsOn(('home', notes, _workspaces.value, layout, DateTime.fromMillisecondsSinceEpoch(now).day), () => homeCarded(notes, _workspaces, layout, now));
  }

  /// All notes': its first twenty-four, in the order it was left in.
  Map<String, String> _allNotesGists(AppShellState shell, bool tapes) {
    final notes = shell.notes;
    final sort = readSort(_stored);
    return _gistsOn(('notes', notes, _workspaces.value, sort, tapes), () => allNotesCarded(notes, _workspaces, sort: sort, tapes: tapes));
  }

  Object? _gistedBy;
  Map<String, String> _gistsNow = const {};
  bool _gistsRead = true;

  /// The note of the meeting being recorded now. As last known: asking the service afresh tells its listeners.
  String? get _recordingNow {
    final meeting = _voice?.live?.state;
    return (meeting?.recording ?? false) ? meeting?.noteId : null;
  }

  late final Stored _stored = widget.stored ?? stored;

  final GlobalKey<AppShellState> _shell = GlobalKey<AppShellState>();
  final GlobalKey<CommandBarState> _commands = GlobalKey<CommandBarState>();

  /// Settings asked for at a page, by when it was asked (settings/settings_sheet.dart `toPage`).
  SettingsTarget? _settingsPage;

  void _search() => _commands.currentState?.show();

  /// A note's menu, from a long press or a right-click on it in any list (notes/note_menu.dart).
  final NoteMenuController _menu = NoteMenuController();

  late bool _launching = widget.launch && widget.launchSeat == null;

  /// What the launch screen reads of the root, where it is drawn over it from outside (`GhostRoot.launchSeat`).
  LaunchFacts _launchFacts() => (loading: !_read, notes: _shown.length, sync: launchSyncOf(_services?.engine?.status.value.phase), recording: _meetingRecording);

  bool _meetingRecording() => _voice?.live?.state?.recording ?? false;
  bool get _read => !_library.loading;
  bool _settings = false;

  /// Stops answering the desktop's keys and menu (lib/root/desktop_wiring.dart).
  VoidCallback? _stopDesktop;

  /// The workspace sheet: shut, a new one, or one to change.
  ({Workspace? editing})? _workspace;

  /// The smoke at the edges is the art's own switch (lib/art/wisp_settings.dart), which follows the preference.
  late final ValueListenable<bool> _wispEdge = preferences.select((prefs) => prefs.wispEdge);
  void _smoke() => WispSettings.instance.wanted = _wispEdge.value;

  @override
  void dispose() {
    _stopDesktop?.call();
    _wispEdge.removeListener(_smoke);
    _localOnly.removeListener(plugins.preferencesChanged);
    _localOnly.removeListener(_localOnlyMoved);
    _guide?.removeListener(_changed);
    // The updates are the process's, as the core is: let go of, never disposed.
    widget.updates?.removeListener(_updatesChanged);
    if (widget.guide == null) _guide?.dispose();
    _stopLinks?.call();
    _previews.dispose();
    _unwatchMeeting?.call();
    _stopFills?.call();
    _guideModels?.dispose();
    _stopGistHold?.call();
    _gists?.removeListener(_gistsChanged);
    _gists?.dispose();
    _availability?.removeListener(_voiceChanged);
    _availability?.dispose();
    _deviceFacts?.dispose();
    _voice?.live?.canNotify.removeListener(_voiceChanged);
    _voice?.models?.removeListener(_modelsChanged);
    _voice?.recorder.voiceModel.removeListener(_tick.tell);
    _noteAi?.removeListener(_aiChanged);
    _noteAi?.reviewStage.removeListener(_aiChanged);
    _voiceLife?.dispose();
    _capture?.dispose();
    // A voice a test brought is the test's to let go.
    if (widget.voice == null) _voice?.dispose();
    _libraryChanges.removeListener(_reads.changed);
    _library.removeListener(_tick.tell);
    _workspaces.removeListener(_tick.tell);
    _trash.removeListener(_tick.tell);
    preferences.removeListener(_prefsChanged);
    final services = _services;
    if (services != null) {
      for (final says in _accountSays(services)) {
        says?.removeListener(_accountChanged);
      }
      services.engine?.status.removeListener(_syncChanged);
    }
    _life?.dispose();
    _gate?.dispose();
    _wired?.live.presence.removeListener(_presenceChanged);
    _wired?.dispose();
    _pictures?.dispose();
    widget.launchSeat?.rise(_launchFacts);
    _made?.dispose();
    _menu.removeListener(_tick.tell);
    _menu.dispose();
    _tick.dispose();
    // What the root made that is listened to from outside it, or listens: let go, so a root started over (a reset)
    // does not leave the last one's library reading the notes at every return to the app, nor its trash and
    // workspaces following the preferences. Each is safe to ask after: a save still on its way when the root goes
    // lands in a library that tells nobody. The library and the workspaces a test handed in are the test's; and
    // the ones made in memory hold nothing outside themselves, and are left to be asked by whatever is still
    // finishing.
    _versionsStore.dispose();
    _keptSpaces?.dispose();
    final trash = _trash;
    if (trash is KeptTrash) trash.dispose();
    final library = _library;
    if (widget.library == null && library is CoreLibrary) library.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _smoke();
    _wispEdge.addListener(_smoke);
    // Local only turning on or off changes which plugins are on without a switch moving: the registry is told of
    // that, and not of a tab opened or a note filed, which told everything that draws a plugin to draw again.
    _localOnly.addListener(plugins.preferencesChanged);
    // And lets the fills that were parked under it go on (ai/fills/queue.ts `resumeParked`).
    _localOnly.addListener(_localOnlyMoved);
    // Who Claude's page in Settings reads as signed in (plugins/claude): this build's account, where it has one.
    claudeHandle = () => _services?.session?.handle;
    _guide?.addListener(_changed);
    _libraryChanges.addListener(_reads.changed);
    // What the parts on screen read, each told as it changes (lib/root/selected.dart): after the reads above have
    // been told, so a part built again reads the library as it now is.
    _library.addListener(_tick.tell);
    // A note's menu opening: its part is built with the notes as they are now, before the menu looks its note up.
    _menu.addListener(_tick.tell);
    _workspaces.addListener(_tick.tell);
    _trash.addListener(_tick.tell);
    preferences.addListener(_prefsChanged);
    final services = _services;
    if (services != null) {
      for (final says in _accountSays(services)) {
        says?.addListener(_accountChanged);
      }
      services.engine?.status.addListener(_syncChanged);
    }
    // The updates: drawn again as they change, not while a meeting records, and looked for from now (`useUpdates`).
    widget.updates
      ?..addListener(_updatesChanged)
      ..recording = (() => _voice?.live?.state?.recording ?? false)
      ..start();
    // The launch screen over the root, where there is one, reads the root from here on.
    widget.launchSeat?.sit(_launchFacts, _tick);
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
    // Not on an open by the side key, whose person is already mid-sentence: the recording comes first, as it does
    // for the guide (shell/useAccountGate.ts).
    final byKey = (widget.voice?.assistant ?? widget.voiceMaking?.assistant ?? false) && (widget.voice?.launch ?? widget.voiceMaking?.launch) == 'capture';
    setState(() => _gate = AccountGateState(services: services, launchedByKey: byKey, kept: _stored)..addListener(_changed));
  }

  void _toAccount() => setState(() {
        _settings = true;
        _settingsPage = SettingsTarget('account', nonce: DateTime.now().microsecondsSinceEpoch);
      });

  /// An organization's dashboard or its log: built again with the notes, the account and its sync, who is in its
  /// notes, and the smoke's switch.
  Widget _organizationPage(BuildContext context, AppShellState shell, ScreenOrganization screen) => Selected(
        listenable: _tick,
        name: 'organization',
        select: () => (screen.orgId, screen.page, shell.notes, _workspaces.value, _accountAt, _syncAt, _presenceAt, preferences.value.wispEdge),
        builder: (context, _) => _organizationPageOf(context, shell, screen),
      );

  Widget _organizationPageOf(BuildContext context, AppShellState shell, ScreenOrganization screen) {
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
        _openSettings();
      },
      trashed: _trashed,
      onRestore: _actions.restore,
      onDestroy: _actions.destroy,
      onEmptyTrash: () => _actions.emptyTrash(_trashed),
      notesInWorkspace: _notesIn,
      onTrashNotes: _trashNotes,
      emptyArt: const Ghost(scene: GhostScene.noNotes),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ghostPerf) Perf.count('root.build');
    // A note drawn small anywhere under here (a card on the home page, a row of the sidebar) draws its pictures and
    // a film's still from the app's own (lib/home/note_peek.dart).
    return PeekPictures(store: _pictures, child: _whole);
  }

  /// A part of what is on screen: built when [select] answers another value than it drew, and at no other time
  /// (lib/root/selected.dart).
  Widget _part<T>(String name, T Function() select, WidgetBuilder builder) =>
      Selected<T>(listenable: _tick, name: name, select: select, builder: (context, _) => builder(context));

  static const Widget _nothing = SizedBox.shrink();

  /// A change to what the root holds, and the parts told: for the root's code in its other files
  /// (lib/root/root_commands.dart, root_voice.dart), since `setState` is the framework's to call from the class
  /// itself.
  void _told(VoidCallback change) => setState(change);

  void _openSettings() => setState(() => _settings = true);

  void _openSettingsAt(String page) => setState(() {
        _settings = true;
        _settingsPage = SettingsTarget(page, nonce: DateTime.now().microsecondsSinceEpoch);
      });

  void _closeSettings() => setState(() => _settings = false);

  void _trashNotes(Iterable<String> ids) => ids.forEach(_trash.trashNote);

  void _organizationSettings(String id) => setState(() => _organization = (id: id, from: OrganizationFrom.settings));

  /// Everything the root puts on screen, made once: the shell, and over it Settings, the palette, a note's menu,
  /// the sheets, the walkthrough and the launch screen. Each is a part, built again when what it reads changed; one
  /// that is not there (a sheet that is shut, the launch screen once the app is open) is nothing, in its place.
  late final Widget _whole = AccountScope(
    services: _services,
    child: Stack(
      fit: StackFit.expand,
      children: [
        _part('shell', _shellReads, _shellPart),
        // The phone at work, over the app, while a review is on the note being read (lib/scene/at_work.dart).
        // It reads the note's words, and follows its AI, only while a review is on it: with none the scene is not
        // up, and a save of the note, or its AI finding its model as the note opens, is nothing to it.
        _part('atWork', () {
          final ai = _noteAi, id = _noteAiId;
          if (ai == null || id == null) return null;
          final reviewing = ai.reviewKey != null || ai.reviewStage.value != null;
          return (ai, id, reviewing ? _aiAt : 0, reviewing ? _library.noteOf(id) : null, _voice);
        }, _atWorkPart),
        // Settings is handed what its pages read whether it is open or shut (the models, the tapes' room, the
        // updates), so it is built again as those change; never for a runner's turn or the home page's news.
        _part('settings', () => (_settings, _settingsPage, _voice, _voiceAt, _modelsAt, _updatesAt, _voice == null ? null : _tapeFacts, preferences.value.formatModel), _settingsPart),
        // The palette's commands and a note's menu are made from the notes while each is open; shut, neither
        // draws anything, and each is built with the notes as they are the moment it opens.
        _part('commands', () => ((_commands.currentState?.isOpen ?? false) ? _library.value : null, _workspaces.value, _prefsAt, _capture != null), _commandsPart),
        _part('noteMenu', () => _menu.value == null ? null : _shown, _noteMenuPart),
        // What the + makes (notes/NewSheet.tsx). The rows read where to make it as they are pressed, since the
        // sheet closes first.
        _part(
          'newSheet',
          () => _newSheet ? (_newInto, _shown, _shell.currentState?.shown, _capture != null, _voiceAt, preferences.value.meetingSound) : null,
          _newSheetPart,
        ),
        _part('newBook', () => _bookSheet == null ? null : (_bookSheet, _bookInto, _shown), _newBookPart),
        _part('workspace', () => _workspace, _workspacePart),
        if (_services case final services?) ...[
          _part('organization', () => (_organization, _accountAt, _syncAt), (context) => _organizationSheetPart(services)),
          _part('newOrganization', () => (_newOrganization, _accountAt, _syncAt), (context) => _newOrganizationPart(services)),
          // The way in, the first thing on screen once, on an open that is signed out. Never over a recorder
          // (App.tsx: `accountGate.open && !isRecording(screen)`): it waits under one.
          _part('gate', () => (_gate, _gate?.open ?? false, _shell.currentState?.screen.isRecording ?? false, _accountAt, _syncAt), (context) {
            final gate = _gate;
            return gate != null && gate.open && !(_shell.currentState?.screen.isRecording ?? false) ? AccountGate(services: services, onDone: gate.close) : _nothing;
          }),
        ],
        // An invite link that opened the app, and a code held on this device from before, asked about once
        // someone is signed in: nothing is joined until the person says so. Held back while the way into an
        // account is up at launch.
        _part(
          'join',
          () => (_joinRequest, _gate?.open, _accountAt, _syncAt),
          (context) => JoinInvites(
            services: _services,
            request: _joinRequest,
            hold: _services != null && (_gate?.open ?? true),
            onOpen: (id) => _shell.currentState?.openOrganization(id),
            onAccount: _toAccount,
          ),
        ),
        // The walkthrough, over everything but the way into an account, and never over a recorder: it is taken
        // away while a capture is on screen and comes back, at its page, when the capture ends.
        _part('guide', () {
          final guide = _guide;
          if (guide == null || !guide.open || (_gate?.open ?? false) || (_shell.currentState?.screen.isRecording ?? false)) return null;
          return (guide.page, guide.tooSoon, _capture != null, _modelsForGuide);
        }, _guidePart),
        _part('launch', () => _launching ? (!_read, _shown.length, _updatesAt, _syncAt, _voice) : null, _launchPart),
      ],
    ),
  );

  /// What the shell is handed: built again when one of these is another, and for nothing else. The screens it
  /// holds are parts of their own.
  Object _shellReads() {
    final prefs = preferences.value;
    return (
      _shellDraws,
      _drafts,
      prefs.topBar,
      prefs.sidebarStyle,
      _workspaces.value,
      // Who is signed in and the organizations joined.
      _accountAt,
      prefs.openNotes,
      prefs.tabGroups,
      // Whether there is a recorder, and a meeting's service, to put on screen.
      _voice != null && _capture != null,
      _voice?.live != null,
      readSidebarShown(_stored),
      readAsideShown(_stored),
      _unread,
    );
  }

  /// Whether something unread and wanted waits (`unreadNotifications`). The feed is counted again when the account
  /// said something or Settings › Notifications' switches are others, and at no other time.
  bool get _unread {
    final prefs = preferences.value.notifications;
    if (_unreadAt != _accountAt || !identical(prefs, _unreadFor)) {
      _unreadAt = _accountAt;
      _unreadFor = prefs;
      _unreadNow = unreadNotifications(_services, prefs) > 0;
    }
    return _unreadNow;
  }

  int _unreadAt = -1;
  NotificationPrefs? _unreadFor;
  bool _unreadNow = false;

  Widget _shellPart(BuildContext context) {
    final prefs = preferences.value;
    final services = _services;
    final signedIn = services?.signedIn ?? false;
    final voice = _voice;
    final capture = _capture;
    // What the shell draws from here on, for the next change to be measured against (`_shellDraws`).
    final shown = _shellNotes = _shown;
    return AppShell(
      key: _shell,
      sheet: widget.sheet ?? context.tokens.sheet,
      notes: shown,
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
      // And the walkthrough steps aside for a recorder, so the parts that read the screen are told.
      onScreenChanged: (_) {
        _left();
        _tick.tell();
      },
      untouchedEntryOf: (id) => _untouched.recordOf(id)?.journalId,
      onTabGroupsChanged: (groups) => preferences.update((now) => now.copyWith(tabGroups: groups)),
      onSettings: _openSettings,
      // The people icon with no organization joined, and the picker's last row: Settings › Organizations.
      onOrganizations: () => _openSettingsAt('organizations'),
      onNew: _plus,
      // Whether the bell rings: something unread the person asked to see (`unreadCount`).
      unread: _unread,
      onDeleteNote: _delete,
      onRefresh: _library.refresh,
      noteBuilder: _note,
      // The recorder, the whole window: a fresh mount for each capture, keyed by the shell.
      captureBuilder: voice == null || capture == null
          ? null
          : (context, shell, screen) => _part(
                'capture',
                () => (screen, _voiceAt),
                (context) => CaptureScreen(
                  recorder: voice.recorder,
                  fromAssistant: screen.fromAssistant,
                  stopRequests: screen.stop,
                  noteId: screen.noteId,
                  placing: screen.placing is Placing ? screen.placing as Placing : null,
                  meeting: screen.meeting,
                  onMeeting: voice.canMeet ? () => unawaited(capture.meeting(false)) : null,
                  onFinish: (note, locked, {review, ask, landing}) => unawaited(capture.finished(note, locked, review: review, ask: ask, landing: landing)),
                ),
              ),
      // Ghost.md Academy, the whole window: out by its arrow, and its contents' way to the cheat sheet.
      academyBuilder: (context, shell) => _part(
        'academy',
        () => shell,
        (context) => AcademyScreen(
          onDone: shell.backToList,
          onCheatSheet: () {
            shell.backToList();
            _openSettingsAt('cheatsheet');
          },
        ),
      ),
      meetingBuilder: voice == null || capture == null || voice.live == null
          ? null
          : (context, shell, screen) => _part(
                'meeting',
                () => (screen, _voiceAt),
                (context) => MeetingScreen(
                  noteId: screen.noteId,
                  fromAssistant: screen.fromAssistant,
                  onLeave: capture.leftMeeting,
                  live: voice.live!,
                  host: _meetingHost(voice, voice.live!),
                ),
              ),
      homeBuilder: _home,
      allNotesBuilder: (context, shell, screen) => _part(
        'allNotes',
        () => (shell.notes, !_read, screen.tapes, _workspaces.value, _allNotesGists(shell, screen.tapes), preferences.value.wispEdge),
        (context) => AllNotesScreen(
          // The empty page's hint, as home's: the side key on any Android phone (AllNotesScreen.tsx `isAndroid`).
          sideKey: defaultTargetPlatform == TargetPlatform.android,
          notes: shell.notes,
          loading: !_read,
          workspaces: _workspaces,
          stored: _stored,
          tapes: screen.tapes,
          gists: _allNotesGists(shell, screen.tapes),
          clock: widget.clock,
          onOpen: (id) => _openWhereLeft(shell, id),
          onBack: shell.backToList,
          onRefresh: _library.refresh,
          onNoteMenu: (note, at) => _menu.open(note.id, at),
          notesInWorkspace: _notesIn,
          onTrashNotes: _trashNotes,
          wisp: preferences.value.wispEdge,
        ),
      ),
      sidebarBuilder: (context, shell, close) => _part(
        'sidebar',
        () => _sidebarReads(shell),
        (context) => NotesDrawer(
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
          onSpeak: _capture == null
              ? null
              : () {
                  close();
                  _speak();
                },
          onSettings: () {
            close();
            _openSettings();
          },
          trashed: _trashed,
          onRestore: _actions.restore,
          onDestroy: _actions.destroy,
          onEmptyTrash: () => _actions.emptyTrash(_trashed),
          notesInWorkspace: _notesIn,
          onTrashNotes: _trashNotes,
          emptyArt: const Ghost(scene: GhostScene.noNotes),
        ),
      ),
      dockedSidebarBuilder: (context, shell) => _part('tree', () => _sidebarReads(shell), (context) => _tree(shell)),
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
      asideCardBuilder: (context, shell, close) => AsideCard(content: _asideOf(shell), stored: _stored, onOpen: shell.openNoteWithin, onOpenTitle: _openTitleWithin, onClose: close),
      notificationsBuilder: (context, shell, close) => _part('notifications', () => (preferences.value.notifications, _accountAt, _syncAt), (context) {
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
        return NotificationsDrawer(notifications: const [], prefs: preferences.value.notifications, signedIn: false, onClose: close, onOpenNote: openNote, onOpenOrganization: (_) => close(), onAccount: account);
      }),
    );
  }

  /// What either sidebar reads: the notes and the one on screen, the workspaces, the trash, whether there is a
  /// folder to browse and a recorder to speak to, and the update a wide window's sidebar carries.
  Object _sidebarReads(AppShellState shell) => (shell.notes, shell.shown, _workspaces.value, _trashed, _canBrowse, _capture != null, _updatesAt);

  /// The home page, while it is the screen (the shell takes it down under a note, the grid and an organization's
  /// page, and makes it anew on the way back, as the page's is: lib/shell/app_shell.dart). It is built again for
  /// the notes it shows, its layout, the workspace looked at, a recording, its notices, the gists, and the
  /// organizations with who is in them.
  Widget _home(BuildContext context, AppShellState shell) => _part(
        'home',
        () => (
          shell.notes,
          !_read,
          preferences.value.homeLayout,
          _workspaces.value.current?.id,
          _capture != null,
          _recordingNow,
          _updatesAt,
          _voiceModelLine,
          _homeGists(shell),
          _accountAt,
          _presenceAt,
        ),
        (context) => _homePage(context, shell),
      );

  Widget _homePage(BuildContext context, AppShellState shell) {
    final services = _services;
    final signedIn = services?.signedIn ?? false;
    // The organization the home page is filtered to, for its news.
    final chosen = _workspaces.value.current?.id;
    String? chosenOrg;
    for (final org in services?.joined ?? const <OrgRow>[]) {
      if (orgWorkspaceId(org.id) == chosen) chosenOrg = org.id;
    }
    return HomeScreen(
      notes: shell.notes,
      loading: !_read,
      workspaces: _workspaces,
      layout: homeLayoutOf(preferences.value.homeLayout),
      onOpen: (id) => _openFromHome(shell, id),
      onNew: _plus,
      // The dock's microphone, and the note of the meeting being recorded now.
      onCapture: _capture == null ? null : _speak,
      recording: _recordingNow,
      // `isAndroid ? 'Write it, or hold the side key and say it.'`: the page says the side key on any Android
      // phone, whether or not this build answers it, and the empty page's words are held to the page's.
      sideKey: defaultTargetPlatform == TargetPlatform.android,
      notices: _notices(),
      gists: _homeGists(shell),
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
      onOrganizationSettings: services == null ? null : _organizationSettings,
      onNewOrganization: signedIn ? () => setState(() => _newOrganization = true) : null,
      headerEdge: _headerEdge,
      dockHalo: _dockHalo,
      ghost: _homeGhost,
    );
  }

  /// The art in the seams the home page leaves for it. Each answers from what it is handed and nothing else, and is
  /// the same function every time the page is built: the page does no work for a seam that is the one it had.
  static Widget _headerEdge(BuildContext context, HomeEdge edge, Widget scroller) => WispEdge(under: edge.under, foot: true, child: scroller);

  static Widget _dockHalo(BuildContext context, HomeDock it) => DockSmoke(behind: it.behind, dock: it.dock, alignment: it.alignment, padding: it.padding);

  static Widget _homeGhost(BuildContext context, HomeGhost it) => Ghost(
        scene: switch (it.scene) {
          HomeGhostScene.noNotes => GhostScene.noNotes,
          HomeGhostScene.emptyWorkspace => GhostScene.emptyWorkspace,
          HomeGhostScene.searchNothing => GhostScene.searchNothing,
        },
        size: it.lead ? GhostSize.lead : GhostSize.small,
        heightShare: it.heightShare,
      );

  Widget _atWorkPart(BuildContext context) {
    final noteAi = _noteAi, id = _noteAiId;
    if (noteAi == null || id == null) return _nothing;
    final voice = _voice;
    return AtWork(
      noteId: id,
      opening: noteAi.reviewKey,
      heard: noteAi.handoff?.heard ?? '',
      body: _library.noteOf(id)?.body ?? '',
      hasJob: noteAi.handoff?.job != null,
      stage: noteAi.reviewStage.value,
      refining: voice?.recorder.refining?.refining,
      summaryDue: voice?.summaries?.pendingFor(id),
    );
  }

  Widget _settingsPart(BuildContext context) {
    final services = _services;
    final guide = _guide;
    return SettingsSheet(
      open: _settings,
      toPage: _settingsPage,
      onClose: _closeSettings,
      workspaces: _workspaces,
      notesInWorkspace: _notesIn,
      onTrashNotes: _trashNotes,
      // About's Updates rows, in a build that looks for any (lib/root/update_wiring.dart).
      // An iPhone has no update client: About says whose its updates are (iphone_wiring.dart).
      updates: widget.updates == null ? appStoreUpdates() : settingsUpdatesOf(widget.updates!),
      // A build with no service says so where a way in is pressed; one with an account takes it from the scope.
      features: _features(services),
      onOrganization: services == null ? null : _organizationSettings,
      onOpenLink: widget.openLink == null ? null : (url) => unawaited(widget.openLink!(url)),
      onAcademy: () {
        _closeSettings();
        _shell.currentState?.show(const Screen.academy());
      },
      onGuide: guide == null
          ? null
          : () {
              _closeSettings();
              guide.show(0);
            },
      onGuideBook: () => unawaited(_openGuideBook()),
      // Examples' four rows, which were drawn and could not be pressed: nothing had given them a press.
      onSample: _openExample(() => sampleNoteBody),
      onBoard: _openExample(() => boardNoteBody),
      onCanvas: _openExample(sampleCanvasBody),
      onHowCanvas: _openExample(howCanvasBody),
    );
  }

  Widget _commandsPart(BuildContext context) {
    final guide = _guide;
    return CommandBar.over(
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
        settings: _openSettings,
        settingsPage: _openSettingsAt,
      ),
    );
  }

  Widget _noteMenuPart(BuildContext context) => NoteMenuHost(
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
      );

  Widget _newSheetPart(BuildContext context) {
    final services = _services;
    final voice = _voice;
    final capture = _capture;
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
              on: preferences.value.meetingSound,
              onToggle: () => preferences.update((now) => now.copyWith(meetingSound: !now.meetingSound)),
            )
          : null,
    );
  }

  Widget _newBookPart(BuildContext context) => NewBookSheet(
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
      );

  Widget _workspacePart(BuildContext context) {
    final sheet = _workspace;
    if (sheet == null) return _nothing;
    return WorkspaceManageSheet(
      store: _workspaces,
      editing: sheet.editing,
      onClose: () => setState(() => _workspace = null),
      notesIn: _notesIn,
      onTrashNotes: _trashNotes,
    );
  }

  Widget _organizationSheetPart(AccountServices services) {
    final sheet = _organization;
    if (sheet == null || services.orgs == null) return _nothing;
    return OrganizationSheet(
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
    );
  }

  Widget _newOrganizationPart(AccountServices services) => NewOrganizationSheet(
        services: services,
        open: _newOrganization,
        onClose: () => setState(() => _newOrganization = false),
        onMade: (id) {
          setState(() => _newOrganization = false);
          _shell.currentState?.openOrganization(id);
        },
      );

  Widget _guidePart(BuildContext context) {
    final guide = _guide;
    if (guide == null || !guide.open || (_gate?.open ?? false) || (_shell.currentState?.screen.isRecording ?? false)) return _nothing;
    return Guide(
      index: guide.page,
      tooSoon: guide.tooSoon,
      onIndex: guide.turn,
      recordsVoice: _capture != null,
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
    );
  }

  Widget _launchPart(BuildContext context) {
    if (!_launching) return _nothing;
    return LaunchScreen(
      loading: !_read,
      notes: _shown.length,
      updates: launchUpdatesOf(widget.updates),
      sync: launchSyncOf(_services?.engine?.status.value.phase),
      recording: _meetingRecording,
      onDone: () => setState(() => _launching = false),
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
