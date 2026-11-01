/// The page tree: the one model of a library's pages that every surface reads (docs/TEAMSPACES.md). The sidebar's
/// tree, a page's breadcrumbs, its previous and next page, "Pages in this page" and a teamspace's home all read
/// this, and nothing here draws.
///
/// Matt, 2026-10-31: "think about how we can build better docs UIs and sidebar navigation for orgs and team members
/// into our app so we better are able to handle a notion like setup in teams". His choices: a space switcher
/// (Personal, then each organization) scoping the tree, and the hierarchy on disk as **a folder and its
/// `index.md`**, Obsidian's folder notes: a page with sub-pages is a folder whose `index.md` is the page itself, and
/// a notebook's chapters are its sub-pages. Everything stays markdown-first (docs/MARKDOWN_FIRST.md §6): the order
/// of a folder's pages is `order:` in its page's front matter, a page's icon its `icon:`, a teamspace's settings its
/// `Home.md`; nothing of the tree is kept in the preferences, so a clone of the Library folder draws the same tree.
///
/// **What a node is.** A [PageNode] is a note (a page) or a folder with no page of its own (a plain folder). Its
/// children are, in order:
///
/// 1. for a notebook, its chapters in the index's order (lib/core/book.dart `chaptersOf`), a chapter indented under
///    the one before nested under it;
/// 2. for a folder's page (or a plain folder), the notes and sub-folders in that folder: those its page's `order:`
///    names first, in that order (each item a title or a file name, `[[links]]` read too), then the rest by title,
///    notes and folders together as Notion lists them.
///
/// A note has one place: a chapter is drawn under its notebook, not in its folder as well. The first notebook to
/// claim a page has it (as `bookIndex` gives a page in two books to the first), a notebook never claims itself or a
/// page it is inside, and a chapter's note must be in the same space; a chapter no note answers to is left out.
///
/// **A folder's page** is, among the notes directly in it: its `index.md`; at an organization's top, its `Home.md`
/// or a note saying `type: teamspace`; else a note named as the folder is (`Plan/Plan.md`). The last two are
/// reality's, not the doc's: in the app's own Library folder a note's file follows its title at every save
/// (tauri/src-tauri/src/library/mod.rs `follows_title`), so `Plan/index.md` titled "Plan" is written back as
/// `Plan/Plan.md` the next time it is saved, and `Home.md` titled anything but Home moves too. Reading all three
/// keeps the page the folder's whatever build wrote it last (docs/TEAMSPACES.md, "Where reality differs").
///
/// **Spaces** ([Space], [spacesFor]): Personal is everything not under `orgs/` (`Inbox/` first, then each personal
/// workspace's folder in the workspaces' order, then any other folder a chosen vault has, and loose files); an
/// organization is `orgs/<its folder>/`, the folder its workspace's name gives it (lib/core/note_folders.dart
/// `folderFor`), whose page is the space's home and whose other contents are its roots. A folder under `orgs/` that
/// no organization on this device answers to is in no space until it does (as lib/core/folder_adopter.dart waits).
///
/// **Cost.** [PageTree.build] reads each note's title and front matter through its kept facts
/// (lib/core/note_facts.dart) and makes one pass over the paths: measured 2026-10-31 on the Mac at 57 to 72 ms for
/// 5,000 notes in 300 folders across three spaces with every note read for the first time, and 14 to 16 ms once
/// their facts are kept, as they are in the running app (test/core/page_tree_test.dart prints both). So it is built
/// whole, not node by node: a sidebar that unfolds lazily draws from it. [PageTreeWatch] builds it only when asked, and
/// again only when a note's place in it could have changed: its path, title, front matter or chapters, or the
/// workspaces; an edit of a page's words alone hands its listeners the tree they have.
///
/// **Writing.** The tree is read-only. What a drag changes is worked out purely here ([orderAfterDrop],
/// [withPageOrder], [folderPageBody], [planMoveInto]) and written by [PageMover], over the library's own move
/// (`NoteLibrary.apply` with a new path: library/mod.rs `apply_note`, which moves the `.versions` file and the
/// `.canvas` beside it; the recording's sidecar is keyed by the note's id and needs no move) and the workspaces'
/// filing (folder_adopter.dart `fileByFolder`), so the pills and the files agree.
library;

import 'package:flutter/foundation.dart';

import 'book.dart' show Chapter;
import 'emoji.dart' show emojiFor;
import 'folder_adopter.dart' show fileByFolder;
import 'front_matter.dart';
import 'library.dart' show NoteLibrary;
import 'note.dart';
import 'note_facts.dart';
import 'note_folders.dart' show folderFor, inboxFolder, orgsFolder, workspacesFolder;
import 'project_tools.dart' show ticketsTool, toolsOn, withNeeds;
import 'properties.dart' show linkTargets, withFrontMatterValue, withProperty, yamlValue;
import 'title_key.dart' show titleKey;
import 'workspaces.dart';

// ---- spaces --------------------------------------------------------------------------------------------------------

/// The id of the personal space: never an organization workspace's id, which opens `org-`.
const String personalSpaceId = 'personal';

/// The file an organization's home page is (docs/TEAMSPACES.md, "Teamspace home").
const String teamspaceHomeFile = 'Home.md';

/// The file a folder's page is (Obsidian's folder-notes convention; docs/TEAMSPACES.md).
const String folderPageFile = 'index.md';

/// Whether a space is the person's own or an organization's.
enum SpaceKind { personal, organization }

/// A space of the switcher: Personal, or one organization (Matt, 2026-10-31: "A space switcher at the top
/// (Personal, then each organization) scoping the tree").
@immutable
class Space {
  /// The person's own space: the inbox, the personal workspaces and anything else not under `orgs/`.
  const Space.personal()
      : kind = SpaceKind.personal,
        orgId = null,
        name = 'Personal',
        folder = null,
        hue = null;

  /// An organization's space: its notes are under [folder], `orgs/<its folder>`.
  const Space.organization({required String this.orgId, required this.name, required String this.folder, this.hue}) : kind = SpaceKind.organization;

  final SpaceKind kind;

  /// The organization's id; null for Personal.
  final String? orgId;

  /// The name the switcher shows: the organization's, or "Personal".
  final String name;

  /// The organization's folder in the library, `orgs/Acme`; null for Personal, which is several folders.
  final String? folder;

  /// The organization's hue (lib/core/workspaces.dart `workspaceHues`), or null.
  final String? hue;

  /// The id a person's choice of space is kept by on the device: [personalSpaceId], or the organization's
  /// workspace id (`org-<orgId>`).
  String get id => orgId == null ? personalSpaceId : orgWorkspaceId(orgId!);

  bool get isPersonal => kind == SpaceKind.personal;

  /// Where an organization's home page is written when one is made: `orgs/Acme/Home.md`; null for Personal.
  String? get homePath => folder == null ? null : '$folder/$teamspaceHomeFile';

  @override
  bool operator ==(Object other) => other is Space && other.kind == kind && other.orgId == orgId && other.name == name && other.folder == folder && other.hue == hue;

  @override
  int get hashCode => Object.hash(kind, orgId, name, folder, hue);

  @override
  String toString() => 'Space($name${folder == null ? '' : ', $folder'})';
}

/// The spaces the switcher lists: Personal, then each organization this device has a workspace for, in the
/// workspaces' order. An organization whose name cleans away to no folder name has no folder and is left out.
List<Space> spacesFor(List<Workspace> workspaces) => [
      const Space.personal(),
      for (final w in workspaces)
        if (w.org != null && folderFor(w) != null) Space.organization(orgId: w.org!, name: w.name, folder: folderFor(w)!, hue: w.hue),
    ];

// ---- a page's icon -------------------------------------------------------------------------------------------------

/// A page's icon, from its `icon:` (docs/TEAMSPACES.md: "an emoji or an icon-pack name"): [emoji] where it is one
/// (written as the character, or as a shortcode lib/core/emoji.dart knows, `:rocket:`), else [name], the icon
/// pack's name as written (`rocket`, `book-open`).
@immutable
class PageIcon {
  const PageIcon._(this.written, this.emoji, this.name);

  /// The value as the front matter says it.
  final String written;
  final String? emoji;
  final String? name;

  /// The icon [value] says, or null for none.
  static PageIcon? of(String? value) {
    final said = value?.trim() ?? '';
    if (said.isEmpty) return null;
    if (said.codeUnits.any((c) => c >= 0x80)) return PageIcon._(said, said, null);
    if (said.length > 2 && said.startsWith(':') && said.endsWith(':')) {
      final emoji = emojiFor(said.substring(1, said.length - 1));
      if (emoji != null) return PageIcon._(said, emoji, null);
    }
    return PageIcon._(said, null, said);
  }

  @override
  bool operator ==(Object other) => other is PageIcon && other.written == written;

  @override
  int get hashCode => written.hashCode;
}

// ---- front matter lists --------------------------------------------------------------------------------------------

final RegExp _listItem = RegExp(r'^\s*-(?:\s+(.*))?$');

/// A list from the page's front matter, each item with its quotes off and a `[[link]]` read as its title: written
/// across (`order: [Plan, "Q4, the rest"]`), with commas, or as lines under the key the way Obsidian writes one
/// (`order:\n  - Plan`), which the one-block reader holds as front matter (front_matter.dart). Empty where the key
/// is not there.
List<String> frontMatterList(String body, String key) {
  final span = frontMatterSpan(body);
  if (span.isEmpty) return const [];
  final said = frontMatterValueIn(body, span, key);
  if (said == null) return const [];
  if (said.trim().isNotEmpty) return linkTargets(said);
  final lines = body.substring(0, span.closing).split('\n');
  final head = RegExp('^\\s*${RegExp.escape(key)}\\s*:', caseSensitive: false);
  final at = lines.indexWhere(head.hasMatch, 1);
  if (at < 0) return const [];
  final items = <String>[];
  for (var n = at + 1; n < lines.length; n += 1) {
    final item = _listItem.firstMatch(lines[n]);
    if (item == null) break;
    items.addAll(linkTargets(unquoted((item.group(1) ?? '').trim())));
  }
  return items;
}

/// The body with front matter list [key] written across as [items] ([withProperty]), the lines of a list written
/// under the key taken off first so no item is left standing under the new line; null, or no items, takes it off.
String withFrontMatterList(String body, String key, List<String>? items) {
  final span = frontMatterSpan(body);
  var text = body;
  if (!span.isEmpty) {
    final lines = body.substring(0, span.closing).split('\n');
    final head = RegExp('^\\s*${RegExp.escape(key)}\\s*:\\s*\$', caseSensitive: false);
    final at = lines.indexWhere(head.hasMatch, 1);
    if (at >= 0) {
      var end = at + 1;
      while (end < lines.length && _listItem.hasMatch(lines[end])) {
        end += 1;
      }
      if (end > at + 1) {
        lines.removeRange(at + 1, end);
        text = lines.join('\n') + body.substring(span.closing);
      }
    }
  }
  return withProperty(text, key, items == null || items.isEmpty ? null : items);
}

// ---- teamspace settings --------------------------------------------------------------------------------------------

/// How a space's pages open (docs/TEAMSPACES.md: "each teamspace says read-first or edit-first in its Home page's
/// front matter").
enum DocsMode { read, edit }

/// A space's settings, from its home page's front matter:
///
///     ---
///     type: teamspace
///     docs: read          # read | edit
///     pins: ["[[Onboarding]]", "[[Roadmap]]"]
///     plugins: [tickets, planning, gantt]
///     icon: 🏠
///     ---
///
/// The defaults: Personal is edit-first (Matt's word); an organization with no home page, or one whose `docs:` says
/// neither word, is edit-first too, since a page that opens to be read where nobody asked for it reads as broken,
/// and `docs: read` is one line to write. The pinned pages are read from `pins:`, and from `pinned:` where that is
/// a list: `pinned` is one of the library's own keys (front_matter.dart `libraryKeys`, a note's pin, `true`), so
/// once the writers put everything in one block (docs/MARKDOWN_FIRST.md §9 slice 7) the library would read a
/// `pinned:` list as the pin and write `pinned` off the note at its next unpinned write. The template writes `pins:`.
///
/// `plugins:` is the project tools the team has turned on (docs/PM_PLUGINS.md; Matt, 2026-11-01: "when starting an org
/// it asks you which of the org based plugins you'd like to enable"): kept here so the whole team shares the list and
/// a clone of the Library folder has it. None said is none on; a word that is no tool's is left out, and a tool that
/// needs Tickets is off where Tickets is not in the list (project_tools.dart [toolsOn]).
@immutable
class TeamspaceSettings {
  const TeamspaceSettings({this.isTeamspace = false, this.docs = DocsMode.edit, this.pinned = const [], this.icon, this.plugins = const {}});

  /// Personal's: edit-first, nothing pinned.
  static const TeamspaceSettings personal = TeamspaceSettings();

  /// Whether the home page says `type: teamspace`.
  final bool isTeamspace;
  final DocsMode docs;

  /// The pinned pages' titles, in order (each `[[link]]`'s title).
  final List<String> pinned;
  final PageIcon? icon;

  /// The project tools on for the team ([toolsOn] of `plugins:`).
  final Set<String> plugins;

  /// The settings a home page's [body] says; the defaults for null (no home page).
  factory TeamspaceSettings.of(String? body) {
    if (body == null) return const TeamspaceSettings();
    final span = frontMatterSpan(body);
    final type = frontMatterValueIn(body, span, 'type')?.trim().toLowerCase();
    final docs = frontMatterValueIn(body, span, 'docs')?.trim().toLowerCase();
    var pins = frontMatterList(body, 'pins');
    if (pins.isEmpty) {
      final pinned = frontMatterValueIn(body, span, 'pinned');
      if (pinned != null && !_isFlag(pinned)) pins = frontMatterList(body, 'pinned');
    }
    return TeamspaceSettings(
      isTeamspace: type == 'teamspace',
      docs: docs == 'read' ? DocsMode.read : DocsMode.edit,
      pinned: List.unmodifiable(pins),
      icon: PageIcon.of(frontMatterValueIn(body, span, 'icon')),
      plugins: Set.unmodifiable(toolsOn(frontMatterList(body, 'plugins'))),
    );
  }

  static bool _isFlag(String value) {
    final low = value.trim().toLowerCase();
    return low == 'true' || low == 'false' || low == 'yes' || low == 'no';
  }

  @override
  bool operator ==(Object other) =>
      other is TeamspaceSettings && other.isTeamspace == isTeamspace && other.docs == docs && listEquals(other.pinned, pinned) && other.icon == icon && setEquals(other.plugins, plugins);

  @override
  int get hashCode => Object.hash(isTeamspace, docs, Object.hashAll(pinned), icon, Object.hashAllUnordered(plugins));
}

/// A home page's [body] with its `docs:` set to [mode] (Matt, 2026-10-31: "A per-space setting": how a teamspace's
/// pages open), every other line as it was; front matter made where the page had none. The teamspace's settings
/// write it over the space's `Home.md` and save that as a note's words are saved; [TeamspaceSettings.of] reads it
/// back. Written through the one front matter writer (properties.dart `withFrontMatterValue`), so it follows the
/// one-block switch wherever that stands.
String withDocsMode(String body, DocsMode mode) => withFrontMatterValue(body, 'docs', mode.name);

/// A home page's [body] with its `plugins:` set to [tools] and what they need (project_tools.dart [withNeeds]), in the
/// suite's order, on one line (a list someone wrote under the key, a line an item, is taken up first); none takes the
/// key off, which reads the same. Every other line as it was; front matter made where the page had none: [withDocsMode]'s
/// way.
String withProjectPlugins(String body, Iterable<String> tools) => withFrontMatterList(body, 'plugins', withNeeds(tools));

/// A page's [body] with its `icon:` set to [icon] (an emoji, a shortcode, an icon pack's name: [PageIcon.of] reads
/// each), quoted where YAML would read it as something else; null or blank takes the key off.
String withPageIcon(String body, String? icon) {
  final said = icon?.trim() ?? '';
  return withFrontMatterValue(body, 'icon', said.isEmpty ? null : yamlValue(said));
}

/// The home page a new organization is given, `orgs/<Org>/Home.md` ([Space.homePath]): the settings' front matter,
/// a short welcome, and two ```query fences, the library's recent changes and its open tickets (lib/core/query/read.dart
/// is their grammar). Titled Home in its front matter, so the app's own folder, which names a file after its title,
/// keeps it `Home.md`. The queries read the whole library: the grammar has no folder to read from yet.
///
/// [plugins] are the project tools the team chose as it was made (docs/PM_PLUGINS.md), written as `plugins:` with what
/// they need; the open tickets' query is written only where Tickets is among them, since with it off that query would
/// be a chip asking for it.
String teamspaceHomeBody(String orgName, {DocsMode docs = DocsMode.edit, String icon = '🏠', Iterable<String> plugins = const []}) {
  final name = orgName.trim().isEmpty ? 'the team' : orgName.trim();
  final tools = withNeeds(plugins);
  return [
    '---',
    'title: Home',
    'type: teamspace',
    'docs: ${docs.name}',
    if (tools.isNotEmpty) 'plugins: [${tools.join(', ')}]',
    'icon: ${yamlValue(icon)}',
    '---',
    '# $name',
    '',
    "Welcome to $name's space. Write here what a new member should read first, and pin the pages everyone needs.",
    '',
    '## Recent changes',
    '',
    '```query',
    'from: notes',
    'sort: updated desc',
    'limit: 10',
    'show: list',
    '```',
    '',
    if (tools.contains(ticketsTool)) ...[
      '## Open tickets',
      '',
      '```query',
      'from: tickets',
      'where: status != Done',
      'sort: priority, due',
      'show: table',
      '```',
      '',
    ],
  ].join('\n');
}

/// An organization's space by its id among [workspaces]; null where this device has no workspace for it, or its
/// name cleans away to no folder ([spacesFor]).
Space? spaceOfOrg(List<Workspace> workspaces, String orgId) {
  for (final space in spacesFor(workspaces)) {
    if (space.orgId == orgId) return space;
  }
  return null;
}

/// An organization's home page among [notes] without building the whole tree, read as [PageTree.homeOf] reads it
/// (`index.md`, else `Home.md`, else a note saying `type: teamspace`, among the notes directly in its folder, out of
/// the trash and the archive): the dashboard asks it at every build, where the tree is built once per change.
Note? teamspaceHomeIn(Iterable<Note> notes, Space space) {
  final folder = space.folder;
  if (folder == null) return null;
  final inIt = [
    for (final note in notes)
      if (note.path case final path? when !note.inTrash && (note.archivedAt ?? 0) == 0 && _dirOf(path) == folder && path.toLowerCase().endsWith('.md')) note,
  ];
  return _Builder._pageOf(folder, inIt, true);
}

// ---- the nodes -----------------------------------------------------------------------------------------------------

/// One row of the tree: a page (a note), a folder's page (a note that is a folder's), or a plain folder (a folder
/// with no page). Made by [PageTree.build] and never changed after.
class PageNode {
  PageNode._(this.space, {this.note, this.folder, required this.title, this.icon, this.isNotebook = false});

  final Space space;

  /// The page's note; null for a plain folder.
  final Note? note;

  /// The folder this node stands for, `workspaces/Work/Plan`; null for a page that is no folder's.
  final String? folder;

  /// The title the row shows: the note's (lib/core/note_text.dart), or the folder's name.
  final String title;

  /// The page's `icon:`, or null.
  final PageIcon? icon;

  /// Whether the note is a notebook (`book: true`), whose chapters are its first children.
  final bool isNotebook;

  PageNode? _parent;
  List<PageNode> _own = <PageNode>[];
  final List<PageNode> _chapters = <PageNode>[];
  List<PageNode>? _children;
  bool _chapter = false;
  int _depth = 0;
  int _at = -1;
  List<PageNode> _order = const [];

  /// A key for the row that holds across builds: the note's id, or `folder:<its path>`.
  String get id => note?.id ?? 'folder:$folder';

  /// Whether this is a folder with no page of its own.
  bool get isPlainFolder => note == null;

  /// Whether this is a folder (with a page or not): its children are its files.
  bool get isFolder => folder != null;

  /// Whether this node is placed under a notebook as one of its chapters.
  bool get isChapter => _chapter;

  /// The note's file, relative to the library; null for a plain folder.
  String? get path => note?.path;

  /// The node it is under; null at the top of its space.
  PageNode? get parent => _parent != null && _parent!._at >= 0 ? _parent : null;

  /// What is under it, in order: a notebook's chapters, then its folder's notes and folders.
  List<PageNode> get children => _children ??= List.unmodifiable([..._chapters, ..._own]);

  /// 0 at the top of its space.
  int get depth => _depth;

  /// The breadcrumbs above it, the top first, itself not among them.
  List<PageNode> get ancestors {
    final up = <PageNode>[];
    for (var at = parent; at != null; at = at.parent) {
      up.add(at);
    }
    return up.reversed.toList();
  }

  /// The page before it in reading order (its space's pages depth first, as the sidebar lists them), plain folders
  /// passed over; null for the first.
  PageNode? get previous {
    for (var i = _at - 1; i >= 0; i -= 1) {
      if (_order[i].note != null) return _order[i];
    }
    return null;
  }

  /// The page after it in reading order; null for the last.
  PageNode? get next {
    for (var i = _at + 1; i < _order.length; i += 1) {
      if (_order[i].note != null) return _order[i];
    }
    return null;
  }

  /// The name an `order:` list writes it by: the page's title, or a plain folder's name.
  String get orderName => note != null ? title : _baseName(folder ?? title);

  @override
  String toString() => 'PageNode($title${folder == null ? '' : ', $folder/'})';
}

String _baseName(String path) {
  final at = path.lastIndexOf('/');
  return at < 0 ? path : path.substring(at + 1);
}

String _dirOf(String path) {
  final at = path.lastIndexOf('/');
  return at < 0 ? '' : path.substring(0, at);
}

String _stemOf(String path) {
  final name = _baseName(path);
  return name.toLowerCase().endsWith('.md') ? name.substring(0, name.length - 3) : name;
}

// ---- the tree ------------------------------------------------------------------------------------------------------

/// Every space's pages, built from the notes the library holds and the workspaces (see the library's doc).
class PageTree {
  PageTree._(this.spaces, this._roots, this._byNote, this._folders, this._order);

  /// A tree of nothing: Personal, empty.
  static final PageTree empty = PageTree.build(const []);

  /// The spaces, Personal first ([spacesFor]).
  final List<Space> spaces;
  final Map<String, PageNode> _roots;
  final Map<String, PageNode> _byNote;
  final Map<String, PageNode> _folders;
  final Map<String, List<PageNode>> _order;

  /// The tree of [notes]: those with a file, out of the trash and the archive, and not in [hidden] (a caller's
  /// own: the Templates' pages, say). [workspaces] gives the spaces, the organizations' folders, the personal
  /// workspaces' order and the folders that have no notes yet.
  factory PageTree.build(Iterable<Note> notes, {List<Workspace> workspaces = const [], Set<String> hidden = const {}}) =>
      _Builder(notes, workspaces, hidden).build();

  /// The space's top rows.
  List<PageNode> rootsOf(Space space) => spaceRoot(space)?.children ?? const [];

  /// The row the space's top rows are the children of, never drawn as a row: an organization's folder (its note
  /// the home page), or Personal's stand-in with no note and no folder. What [orderAfterDrop] and [planMoveInto] are
  /// handed for the top of a space. Null for a space not in [spaces].
  PageNode? spaceRoot(Space space) => _roots[space.id];

  /// The node whose children hold [node]: its parent, or its space's root at the top.
  PageNode? containerOf(PageNode node) => node._parent;

  /// The node of a note, or null where the tree has none (no file, trashed, archived, hidden, or in no space).
  PageNode? nodeOf(String noteId) => _byNote[noteId];

  /// The node of a folder, `orgs/Acme/Plan`, or null.
  PageNode? folderNode(String folder) => _folders[folder];

  /// Which space a note is in, or null.
  Space? spaceOf(String noteId) => _byNote[noteId]?.space;

  /// An organization's home page; null for Personal and for an organization with none yet.
  Note? homeOf(Space space) => space.isPersonal ? null : spaceRoot(space)?.note;

  /// The space's settings from its home page ([TeamspaceSettings.of]); Personal's are [TeamspaceSettings.personal].
  TeamspaceSettings settingsOf(Space space) => space.isPersonal ? TeamspaceSettings.personal : TeamspaceSettings.of(homeOf(space)?.body);

  /// Every row of the space depth first, as the sidebar lists them unfolded: reading order, plain folders included.
  List<PageNode> readingOrder(Space space) => _order[space.id] ?? const [];

  /// How many rows the tree holds in every space.
  int get length => _byNote.length + _folders.values.where((f) => f.note == null).length;
}

class _Builder {
  _Builder(Iterable<Note> notes, this.workspaces, this.hidden) : notes = notes.toList(growable: false);

  final List<Note> notes;
  final List<Workspace> workspaces;
  final Set<String> hidden;

  late final List<Space> spaces = spacesFor(workspaces);
  final Map<String, PageNode> folders = {};
  final Map<String, PageNode> byNote = {};
  final Map<String, PageNode> roots = {};

  /// The space a path is in: an organization's by its folder, Personal for anything not under `orgs/`, null for an
  /// organization's folder this device knows no organization for.
  Space? spaceAt(String path) {
    if (path != orgsFolder && !path.startsWith('$orgsFolder/')) return spaces.first;
    for (final space in spaces) {
      final folder = space.folder;
      if (folder != null && (path == folder || path.startsWith('$folder/'))) return space;
    }
    return null;
  }

  PageTree build() {
    // The notes the tree is of, and every folder their paths name or a workspace has.
    final live = <Note>[];
    final dirs = <String>{inboxFolder};
    for (final note in notes) {
      final path = note.path;
      if (path == null || path.isEmpty || note.inTrash || (note.archivedAt ?? 0) != 0 || hidden.contains(note.id)) continue;
      if (!path.toLowerCase().endsWith('.md')) continue;
      live.add(note);
      for (var dir = _dirOf(path); dir.isNotEmpty; dir = _dirOf(dir)) {
        if (!dirs.add(dir)) break;
      }
    }
    for (final w in workspaces) {
      final folder = folderFor(w, workspaces);
      for (var dir = folder ?? ''; dir.isNotEmpty; dir = _dirOf(dir)) {
        if (!dirs.add(dir)) break;
      }
    }
    dirs
      ..remove(workspacesFolder)
      ..remove(orgsFolder);

    // The notes directly in each folder, and each folder's page among them.
    final inDir = <String, List<Note>>{};
    for (final note in live) {
      (inDir[_dirOf(note.path!)] ??= <Note>[]).add(note);
    }
    final orgTops = {for (final space in spaces) if (space.folder != null) space.folder!: space};
    for (final dir in dirs) {
      final space = spaceAt(dir);
      if (space == null) continue;
      final page = _pageOf(dir, inDir[dir] ?? const [], orgTops.containsKey(dir));
      final node = page == null
          ? PageNode._(space, folder: dir, title: _baseName(dir))
          : _noteNode(space, page, folder: dir);
      folders[dir] = node;
      if (page != null) byNote[page.id] = node;
    }
    for (final note in live) {
      if (byNote.containsKey(note.id)) continue;
      final space = spaceAt(note.path!);
      if (space == null) continue;
      byNote[note.id] = _noteNode(space, note);
    }

    // The roots: an organization's folder, and Personal's stand-in.
    final personal = PageNode._(spaces.first, title: spaces.first.name);
    roots[personalSpaceId] = personal;
    for (final space in spaces.skip(1)) {
      roots[space.id] = folders[space.folder!] ?? (folders[space.folder!] = PageNode._(space, folder: space.folder, title: space.name));
    }

    // Each node under the folder it is in.
    void under(PageNode parent, PageNode child) {
      child._parent = parent;
      parent._own.add(child);
    }

    for (final entry in folders.entries) {
      final dir = entry.key, node = entry.value;
      if (orgTops.containsKey(dir)) continue;
      final up = _dirOf(dir);
      final parent = up.isEmpty || up == workspacesFolder ? (node.space.isPersonal ? personal : null) : folders[up];
      if (parent != null) under(parent, node);
    }
    for (final node in byNote.values) {
      if (node.folder != null) continue;
      final dir = _dirOf(node.note!.path!);
      final parent = dir.isEmpty || dir == workspacesFolder ? (node.space.isPersonal ? personal : null) : folders[dir];
      if (parent != null) under(parent, node);
    }

    _claimChapters();

    // Each folder's own in order: what its page's `order:` names, then the rest by title.
    for (final node in [...folders.values, personal]) {
      node._own = node._own.where((child) => identical(child._parent, node) && !child._chapter).toList();
      if (identical(node, personal)) {
        _orderPersonal(node);
      } else {
        _orderFolder(node);
      }
    }
    for (final node in byNote.values) {
      if (node.folder == null) node._own = const [];
    }

    // Depth, reading order, previous and next, a space at a time.
    final order = <String, List<PageNode>>{};
    for (final space in spaces) {
      final root = roots[space.id]!;
      final rows = <PageNode>[];
      root._at = -1;
      void walk(PageNode node, int depth) {
        node._depth = depth;
        node._at = rows.length;
        rows.add(node);
        for (final child in node.children) {
          walk(child, depth + 1);
        }
      }

      for (final child in root.children) {
        walk(child, 0);
      }
      final kept = List<PageNode>.unmodifiable(rows);
      for (final node in rows) {
        node._order = kept;
      }
      order[space.id] = kept;
    }
    // A node reached from no root (a folder of no space) is in no tree; a space's root is, though no row draws it.
    final tops = roots.values.toSet();
    byNote.removeWhere((_, node) => node._at < 0 && !tops.contains(node));
    folders.removeWhere((_, node) => node._at < 0 && !tops.contains(node));
    return PageTree._(List.unmodifiable(spaces), Map.unmodifiable(roots), Map.unmodifiable(byNote), Map.unmodifiable(folders), Map.unmodifiable(order));
  }

  PageNode _noteNode(Space space, Note note, {String? folder}) {
    final facts = NoteFacts.of(note);
    final title = facts.title.trim().isEmpty ? (folder != null ? _baseName(folder) : _stemOf(note.path!)) : facts.title;
    return PageNode._(space, note: note, folder: folder, title: title, icon: PageIcon.of(frontMatterValueIn(note.body, facts.front, 'icon')), isNotebook: facts.isBook);
  }

  /// The page of the folder [dir] among the notes directly in it: `index.md`; at an organization's top `Home.md`, or
  /// a note that says `type: teamspace`; else the note named as the folder is.
  static Note? _pageOf(String dir, List<Note> inIt, bool orgTop) {
    if (inIt.isEmpty) return null;
    Note? named(String file) {
      for (final note in inIt) {
        if (_baseName(note.path!).toLowerCase() == file) return note;
      }
      return null;
    }

    final index = named(folderPageFile);
    if (index != null) return index;
    if (orgTop) {
      final home = named(teamspaceHomeFile.toLowerCase());
      if (home != null) return home;
      for (final note in inIt) {
        if (frontMatterValue(note.body, 'type')?.trim().toLowerCase() == 'teamspace') return note;
      }
      return null;
    }
    return named('${_baseName(dir).toLowerCase()}.md');
  }

  /// Each notebook's chapters moved under it (see the library's doc), notebooks taken in path order so the same
  /// notes claim the same way on every device.
  void _claimChapters() {
    final books = [for (final node in byNote.values) if (node.isNotebook) node]..sort((a, b) => a.note!.path!.compareTo(b.note!.path!));
    if (books.isEmpty) return;
    // The nodes of each space by title as it is matched, the first by path where two share one.
    final byKey = <String, Map<String, PageNode>>{};
    final sorted = byNote.values.toList()..sort((a, b) => a.note!.path!.compareTo(b.note!.path!));
    for (final node in sorted) {
      final key = NoteFacts.of(node.note!).key;
      if (key.isEmpty) continue;
      (byKey[node.space.id] ??= <String, PageNode>{}).putIfAbsent(key, () => node);
    }
    for (final book in books) {
      final keys = byKey[book.space.id] ?? const <String, PageNode>{};
      final chapters = NoteFacts.of(book.note!).chapters;
      PageNode? last;
      for (final Chapter chapter in chapters) {
        final node = keys[titleKey(chapter.title)];
        if (node == null || identical(node, book) || node._chapter || _isAbove(node, book)) continue;
        final parent = chapter.depth == 1 && last != null ? last : book;
        if (_isAbove(node, parent)) continue;
        node
          .._parent = parent
          .._chapter = true;
        parent._chapters.add(node);
        if (chapter.depth == 0) last = node;
      }
    }
  }

  /// Whether [node] is [of] or above it.
  static bool _isAbove(PageNode node, PageNode of) {
    for (PageNode? at = of; at != null; at = at._parent) {
      if (identical(at, node)) return true;
    }
    return false;
  }

  static int _byTitle(PageNode a, PageNode b) {
    final by = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return by != 0 ? by : a.id.compareTo(b.id);
  }

  void _orderFolder(PageNode folder) {
    final own = folder._own..sort(_byTitle);
    final page = folder.note;
    if (page == null || own.length < 2) return;
    final order = frontMatterList(page.body, 'order');
    if (order.isEmpty) return;
    folder._own = orderedBy(own, order);
  }

  /// Personal's top: the inbox, then the personal workspaces' folders in the workspaces' order, then the rest by
  /// title.
  void _orderPersonal(PageNode root) {
    final rank = <String, int>{inboxFolder: 0};
    for (final w in workspaces) {
      if (w.parent != null || w.org != null) continue;
      final folder = folderFor(w);
      if (folder != null) rank.putIfAbsent(folder, () => rank.length);
    }
    root._own.sort((a, b) {
      final ra = rank[a.folder] ?? rank.length, rb = rank[b.folder] ?? rank.length;
      return ra != rb ? ra.compareTo(rb) : _byTitle(a, b);
    });
  }
}

/// [nodes] with those [order] names first, in its order, then the rest as they were. An item names a node by its
/// title or by its file's or folder's name (`Plan`, `Plan.md`), each as titles are matched (lib/core/title_key.dart).
List<PageNode> orderedBy(List<PageNode> nodes, List<String> order) {
  final keyed = <String, PageNode>{};
  for (final node in nodes) {
    final names = [node.title, if (node.path != null) _stemOf(node.path!), if (node.folder != null) _baseName(node.folder!)];
    for (final name in names) {
      final key = titleKey(name);
      if (key.isNotEmpty) keyed.putIfAbsent(key, () => node);
    }
  }
  final first = <PageNode>[];
  final placed = <PageNode>{};
  for (final item in order) {
    final name = item.toLowerCase().endsWith('.md') ? item.substring(0, item.length - 3) : item;
    final node = keyed[titleKey(name)];
    if (node != null && placed.add(node)) first.add(node);
  }
  return [...first, for (final node in nodes) if (!placed.contains(node)) node];
}

// ---- a drag within a folder ----------------------------------------------------------------------------------------

/// The `order:` list a folder's page is given when [moved] is dropped at [index] among [siblings] (the container's
/// children as they are drawn; [moved] may be one of them or come from elsewhere): every sibling's [PageNode.orderName]
/// in the new order, so the whole folder keeps the order the person sees. A notebook's chapters are its index's
/// lines, not its `order:`, and are left out: their order is the index's (book.dart).
List<String> orderAfterDrop(List<PageNode> siblings, PageNode moved, int index) {
  final rest = [for (final node in siblings) if (node.id != moved.id && !node.isChapter) node];
  final chapters = siblings.where((node) => node.isChapter && node.id != moved.id).length;
  final at = (index - chapters).clamp(0, rest.length);
  rest.insert(at, moved);
  return [for (final node in rest) node.orderName];
}

/// A folder's page with its `order:` set to [order] ([withFrontMatterList]); every other line as it was. The body
/// to save over the page's note ([PageMover.setOrder] does).
String withPageOrder(String body, List<String> order) => withFrontMatterList(body, 'order', order);

/// The page a plain folder is given to hold its `order:`: titled as the folder, written as `<folder>/index.md`
/// ([PageMover.setOrder] does).
String folderPageBody(String title, {List<String> order = const []}) => withPageOrder('# $title\n', order);

// ---- a move into another page --------------------------------------------------------------------------------------

/// Why a move is not planned.
enum MoveRefusal {
  /// The note being moved has no file.
  noFile,

  /// What is moved is a folder (a folder's page or a plain folder): its files are moved by the folders' own move
  /// (lib/core/workspaces.dart `moveWorkspace`), not file by file here.
  isFolder,

  /// The target is the moved page itself, or under it.
  intoItself,

  /// The target is in another space: moving into or out of an organization is sharing, which the filing does
  /// (lib/team), never a drag in the tree.
  acrossSpaces,

  /// The target has nowhere to put a file: Personal's stand-in at the top (drop into Inbox or a workspace).
  noFolder,

  /// The note is in that folder already.
  alreadyThere,
}

/// One file's move: the note, where its file is, where it goes.
@immutable
class PageMove {
  const PageMove(this.noteId, this.from, this.to);
  final String noteId;
  final String from;
  final String to;

  @override
  bool operator ==(Object other) => other is PageMove && other.noteId == noteId && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(noteId, from, to);

  @override
  String toString() => 'PageMove($noteId: $from → $to)';
}

/// What dropping a page into another does to the files (docs/TEAMSPACES.md: "dragging into another page moves the
/// file into that folder (making it a folder page first if it was a plain note: `Plan.md` becomes `Plan/index.md`)"):
/// the moves in the order they are made, the target's first where it becomes a folder's page, and the folder the
/// moved page lands in. [refused] says why there is none.
@immutable
class PageMovePlan {
  const PageMovePlan._(this.moves, this.folder, this.refused);

  const PageMovePlan.refused(MoveRefusal why) : this._(const [], null, why);

  final List<PageMove> moves;
  final String? folder;
  final MoveRefusal? refused;

  bool get ok => refused == null;

  @override
  String toString() => ok ? 'PageMovePlan(${moves.join(', ')})' : 'PageMovePlan.refused(${refused!.name})';
}

/// `Stem.md`, or `Stem 2.md` and on while [taken] (lower case) has it, as the library names a file (names.rs
/// `unique_name`).
String _freeName(String stem, String ext, Set<String> taken) {
  var name = '$stem$ext';
  for (var n = 2; taken.contains(name.toLowerCase()); n += 1) {
    name = '$stem $n$ext';
  }
  return name;
}

/// The plan for dropping [moved] into [target] (see [PageMovePlan]); pure. Into a folder, or a folder's page, the
/// file goes into that folder. Into a plain note, the note becomes a folder's page first: `D/Plan.md` to
/// `D/Plan/index.md` (`Plan 2/` where a folder of that name has a page already), and the file goes in beside it. A
/// file whose name is taken in the folder is given the next free one, as the library would (`Stem 2.md`).
PageMovePlan planMoveInto(PageTree tree, PageNode moved, PageNode target) {
  final from = moved.note?.path;
  if (moved.isFolder) return const PageMovePlan.refused(MoveRefusal.isFolder);
  if (from == null) return const PageMovePlan.refused(MoveRefusal.noFile);
  if (moved.space != target.space) return const PageMovePlan.refused(MoveRefusal.acrossSpaces);
  for (PageNode? at = target; at != null; at = tree.containerOf(at)) {
    if (identical(at, moved)) return const PageMovePlan.refused(MoveRefusal.intoItself);
  }
  final moves = <PageMove>[];
  String folder;
  if (target.folder != null) {
    folder = target.folder!;
  } else if (target.note?.path != null) {
    final at = target.note!.path!;
    final dir = _dirOf(at);
    final stem = _stemOf(at);
    var name = stem;
    for (var n = 2; tree.folderNode(dir.isEmpty ? name : '$dir/$name')?.note != null; n += 1) {
      name = '$stem $n';
    }
    folder = dir.isEmpty ? name : '$dir/$name';
    moves.add(PageMove(target.note!.id, at, '$folder/$folderPageFile'));
  } else {
    return const PageMovePlan.refused(MoveRefusal.noFolder);
  }
  if (_dirOf(from) == folder) return const PageMovePlan.refused(MoveRefusal.alreadyThere);
  // The names taken in the folder: its page's, and every file of the space in it, a chapter drawn elsewhere too.
  final taken = <String>{
    for (final m in moves) _baseName(m.to).toLowerCase(),
    if (tree.folderNode(folder)?.note?.path case final page?) _baseName(page).toLowerCase(),
    for (final node in tree.readingOrder(moved.space))
      if (node.path != null && _dirOf(node.path!) == folder) _baseName(node.path!).toLowerCase(),
  };
  final name = _baseName(from);
  final ext = name.toLowerCase().endsWith('.md') ? name.substring(name.length - 3) : '';
  moves.add(PageMove(moved.note!.id, from, '$folder/${_freeName(_stemOf(from), ext, taken)}'));
  return PageMovePlan._(List.unmodifiable(moves), folder, null);
}

// ---- writing what was planned --------------------------------------------------------------------------------------

/// Writes what a drag planned, through the library's own move and the workspaces' filing (see the library's doc).
class PageMover {
  PageMover({required this.library, required this.workspaces, this.orgFolders = const {}});

  final NoteLibrary library;
  final WorkspaceStore workspaces;

  /// The committed config's `orgs` section as folder to organization id (lib/core/library_config.dart), for an
  /// organization whose workspace is not named as its folder.
  final Map<String, String> orgFolders;

  /// Makes [plan]'s moves, one after another: each note read whole (`get`, never the list's copy: docs/STAGE3.md),
  /// given its new path (`apply`), then filed in the workspace its new folder is (`fileByFolder`). False where the
  /// plan was refused or a note has moved on since it was made (its file is not where the plan found it), and the
  /// moves after it are not made.
  Future<bool> run(PageMovePlan plan) async {
    if (!plan.ok) return false;
    for (final move in plan.moves) {
      final note = await library.get(move.noteId);
      if (note == null || note.path != move.from) return false;
      final moved = await library.apply(note.copyWith(path: () => move.to));
      if (moved.path != move.to) return false;
      fileByFolder(workspaces, move.noteId, _dirOf(move.to), orgFolders: orgFolders);
    }
    return true;
  }

  /// Makes an organization's home page, `orgs/<Org>/Home.md` ([teamspaceHomeBody] with [docs]), filed in the
  /// organization's workspace so it is the team's and syncs to every member (Matt, 2026-10-31, the teamspace home:
  /// "Create the home page"). The note made, or null where the library did not put it where it was asked; null too
  /// for Personal, which has no home page.
  Future<Note?> createHome(Space space, {DocsMode docs = DocsMode.edit, Iterable<String> plugins = const []}) async {
    final folder = space.folder, to = space.homePath;
    if (folder == null || to == null) return null;
    final made = await library.createNote(teamspaceHomeBody(space.name, docs: docs, plugins: plugins));
    final whole = await library.get(made.id) ?? made;
    final placed = await library.apply(whole.copyWith(path: () => to));
    if (placed.path != to) return null;
    fileByFolder(workspaces, made.id, folder, orgFolders: orgFolders);
    return placed;
  }

  /// Writes [order] as the `order:` of [container]'s page ([orderAfterDrop] gives it): over the page where it has
  /// one; for a plain folder a page is made for it first, `<folder>/index.md` ([folderPageBody]), filed with the
  /// folder, and for an organization's top with no home page yet its `Home.md` ([teamspaceHomeBody]). False for
  /// Personal's stand-in, whose top is ordered by the workspaces (and the inbox first), and where the library did
  /// not put the new page where it was asked.
  Future<bool> setOrder(PageNode container, List<String> order) async {
    final page = container.note;
    if (page != null) {
      final whole = await library.get(page.id);
      if (whole == null) return false;
      final body = withPageOrder(whole.body, order);
      if (body != whole.body) await library.save(page.id, body);
      return true;
    }
    final folder = container.folder;
    if (folder == null) return false;
    final home = container.space.folder == folder;
    final made = await library.createNote(home ? withPageOrder(teamspaceHomeBody(container.space.name), order) : folderPageBody(container.title, order: order));
    final whole = await library.get(made.id) ?? made;
    final to = home ? container.space.homePath! : '$folder/$folderPageFile';
    final placed = await library.apply(whole.copyWith(path: () => to));
    if (placed.path != to) return false;
    fileByFolder(workspaces, made.id, folder, orgFolders: orgFolders);
    return true;
  }
}

// ---- listening -----------------------------------------------------------------------------------------------------

/// The page tree as a [ValueListenable], for the sidebar and every surface beside it. It listens to the notes and
/// the workspaces only while something listens to it (as lib/core/library.dart's `NoteWatch` does), builds the tree
/// the first time [value] is asked after a change, and tells its listeners only when a change could move something
/// in the tree: a note come or gone, or one whose path, archive, title, front matter or chapters changed, or the
/// workspaces. An edit of a page's words alone keeps the tree it has, object for object.
class PageTreeWatch extends ChangeNotifier implements ValueListenable<PageTree> {
  PageTreeWatch(this.notes, this.workspaces, {this.hidden});

  final ValueListenable<List<Note>> notes;
  final ValueListenable<Workspaces> workspaces;

  /// Notes to leave out, asked at each build (the Templates' pages, say).
  final Set<String> Function()? hidden;

  PageTree? _tree;
  List<Note>? _notes;
  Workspaces? _workspaces;
  Map<String, (Note, String)> _shapes = const {};

  /// How many times the tree was built, for a test.
  int debugBuilt = 0;

  @override
  PageTree get value {
    if (!hasListeners && (!identical(_notes, notes.value) || !identical(_workspaces, workspaces.value))) _take();
    return _tree ??= _build();
  }

  PageTree _build() {
    debugBuilt += 1;
    return PageTree.build(_notes ?? notes.value, workspaces: (_workspaces ?? workspaces.value).list, hidden: hidden?.call() ?? const {});
  }

  /// What of a note the tree is built from: where its file is, whether it is archived, its title, its front matter
  /// (its icon, its order, a home page's settings) and a notebook's chapters.
  static String _shape(Note note) {
    final facts = NoteFacts.of(note);
    final front = facts.front.isEmpty ? '' : note.body.substring(0, facts.front.offset);
    return '${note.path}\u0000${note.archivedAt ?? 0}\u0000${facts.title}\u0000$front\u0000${facts.isBook ? facts.chapterKeys.join('\u0001') : ''}';
  }

  /// Reads the notes and workspaces as they are now; true where the tree may have changed.
  bool _take() {
    final list = notes.value, spaces = workspaces.value;
    var changed = !identical(spaces, _workspaces);
    if (!identical(list, _notes)) {
      final shapes = <String, (Note, String)>{};
      for (final note in list) {
        final had = _shapes[note.id];
        final shape = had != null && identical(had.$1, note) ? had.$2 : _shape(note);
        if (had == null || had.$2 != shape) changed = true;
        shapes[note.id] = (note, shape);
      }
      if (shapes.length != _shapes.length) changed = true;
      _shapes = shapes;
    }
    _notes = list;
    _workspaces = spaces;
    if (changed) _tree = null;
    return changed;
  }

  void _heard() {
    if (_take()) notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) {
      _take();
      notes.addListener(_heard);
      workspaces.addListener(_heard);
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      notes.removeListener(_heard);
      workspaces.removeListener(_heard);
    }
  }

  @override
  void dispose() {
    notes.removeListener(_heard);
    workspaces.removeListener(_heard);
    super.dispose();
  }
}
