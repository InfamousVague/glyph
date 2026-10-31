/// The committed library config, `Library/.glyph/config.json` (docs/MARKDOWN_FIRST.md §6, decision 2): what
/// describes the library and is nobody's secret, written beside the notes so a clone of the folder brings it back.
///
/// Matt, 2026-10-31: "Our value proposition is that we can be hosted anywhere for super cheap since it's all simply
/// markdown files; the whole backup can be done from git." The notes are files already; what was NOT in the folder
/// was everything that describes it: the personal folders (their hues, their ids where an old one differs from the
/// one its place gives it, their order), the organizations' folders (which organization `orgs/Acme/` is, so a
/// restore can match it after sign-in), the daily-notes setup, the smart notebooks, the library's defaults for how
/// geotags render and whether a new note is tagged, and the Slack and Discord channels a rules fence names. Those
/// lived in the synced preferences alone, and a folder opened on a fresh device had none of them.
///
/// The file is version 1, additive, and keeps keys it does not know ([LibraryConfig.more]): a newer build's keys
/// ride through an older one's rewrite. Never a secret: [looksSecret] refuses to write a value whose key names a
/// webhook, a token or a secret, or a URL under `slack`, `discord`, `calendars` or `webhooks`, so a plugin that one
/// day puts a webhook in the preferences cannot leak it into a repository by accident.
///
/// **Who is the truth.** The preferences stay the live source while the app runs: every screen reads them, the
/// account syncs them. The file is written FROM them whenever one of its sections changes ([LibraryConfigKeeper],
/// a couple of seconds after the last change), and read INTO them when the library is opened with no preferences
/// for it (a restore: the folder was cloned, the settings never synced in) or when a section of the file is newer
/// than what this device last wrote or applied.
///
/// **Two devices sharing a chosen folder** (iCloud, Syncthing, a USB drive): each section carries the stamp of its
/// last write ([LibraryConfig.written]), and each device remembers the stamps it last wrote or applied
/// (`glyph-library-config-seen`). A section whose stamp is later than the device's is taken; one that is the same or
/// earlier is left to the preferences, which the account's settings sync already reconciles between the two. So the
/// rule is last writer wins per section, with the synced preferences as the tie-break; and what is taken is taken
/// additively (a folder in the file and not here is made, a hue in the file is worn; nothing here is removed by it),
/// so a file that lagged a deletion cannot undo it.
///
/// **Where the file is.** Through a [ConfigFile]: `<library>/.glyph/config.json` for the app's own folder and for a
/// chosen folder on the Mac ([configFileFor]); an Android SAF tree has no path Dart can reach (its `.glyph/` lives
/// at `<app data>/trees/<key>/`), so there the config is held in memory until the core offers a command to read and
/// write it through the Vault (the seam is [ConfigFile]; nothing else here knows where the bytes go).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../notes/daily_notes.dart' show DailyNotesSetup, dailyNotesIn, dailyNotesKey, withDailyNotes;
import 'library_folder.dart' show LibraryStatus;
import 'note_folders.dart' show folderFor, folderName, orgsFolder, workspacesFolder;
import 'preferences.dart';
import 'smart_notebooks.dart' show smartNotebooksKey;
import 'stored.dart';
import 'workspaces.dart';

/// The file's name inside the library's dot folder.
const String libraryConfigName = 'config.json';

/// The version this build writes; a file of a later version is read for what this build knows and written back
/// with its keys kept.
const int libraryConfigVersion = 1;

/// The device's memory of which stamps it last wrote or applied, by section: `{"workspaces": "<ISO>", …}`.
const String libraryConfigSeenKey = 'glyph-library-config-seen';

/// The sections the file has, in the order they are written. Each is one top-level key with a stamp of its own.
const List<String> libraryConfigSections = ['workspaces', 'orgs', 'dailyNotes', 'smartNotebooks', 'defaults', 'slack', 'discord'];

/// The plugins' storage keys the `slack` and `discord` sections are read from and written to (lib/plugins/slack/
/// channels.dart, meetings.dart, and the Discord twins): names and ids, never the webhooks, which sit under
/// `glyph-slack-webhook:<id>` and are not read here.
const String slackChannelsKey = 'glyph-slack-channels';
const String slackMeetingsKey = 'glyph-slack-meetings';
const String discordChannelsKey = 'glyph-discord-channels';
const String discordMeetingsKey = 'glyph-discord-meetings';

/// Where the file's bytes are: the seam between the config and the disk.
abstract class ConfigFile {
  /// The file's text, or null where there is none (a library never written by this build, or one that cannot be
  /// read).
  Future<String?> read();

  /// Writes the whole file.
  Future<void> write(String text);
}

/// A real file, written whole beside the index: a temporary file renamed over the old one, so a half-written config
/// is never what the next open reads.
class FileConfigFile implements ConfigFile {
  const FileConfigFile(this.path);

  final String path;

  @override
  Future<String?> read() async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String text) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final part = File('$path.part');
    await part.writeAsString(text, flush: true);
    await part.rename(path);
  }
}

/// Held for this run: a test's, and the place an Android SAF library keeps its config until the core can.
class MemoryConfigFile implements ConfigFile {
  MemoryConfigFile([this.text]);

  String? text;

  /// How many times it was written.
  int writes = 0;

  @override
  Future<String?> read() async => text;

  @override
  Future<void> write(String next) async {
    text = next;
    writes += 1;
  }
}

/// The file for where the library is now: `<library>/.glyph/config.json` for the app's own folder and for a chosen
/// folder that can be reached; null for an Android SAF tree (no path) and for a status that names no folder at all
/// (the web).
ConfigFile? configFileFor(LibraryStatus status) {
  if (status.kind == 'tree') return null;
  final root = status.kind == 'folder' && status.reachable && status.path != null ? status.path : status.own;
  if (root == null || root.isEmpty) return null;
  return FileConfigFile('$root/.glyph/$libraryConfigName');
}

final RegExp _secretKey = RegExp(r'webhook|token|secret|password|sealed', caseSensitive: false);
final RegExp _url = RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false);
const Set<String> _noUrls = {'slack', 'discord', 'calendars', 'webhooks'};

/// Whether anything in [json] looks like a secret: a key naming a webhook, a token, a secret, a password or a sealed
/// value, anywhere; or a URL under `slack`, `discord`, `calendars` or `webhooks`, where a URL is a webhook or a
/// private calendar feed. A file that would is not written (the guard of §6).
bool looksSecret(Object? json, [String? under]) {
  if (json is Map) {
    for (final entry in json.entries) {
      final key = '${entry.key}';
      if (_secretKey.hasMatch(key)) return true;
      if (looksSecret(entry.value, under ?? (_noUrls.contains(key) ? key : null))) return true;
    }
    return false;
  }
  if (json is List) return json.any((each) => looksSecret(each, under));
  return under != null && json is String && _url.hasMatch(json);
}

/// A folder's entry in the `workspaces` section: its hue, its id where it is not the one its place gives it
/// (lib/core/workspaces.dart `folderIdFor`), and its place among its siblings.
@immutable
class ConfigFolder {
  const ConfigFolder({this.id, this.hue, this.order});
  final String? id;
  final String? hue;
  final int? order;

  static ConfigFolder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], hue = raw['hue'], order = raw['order'];
    return ConfigFolder(id: id is String && id.isNotEmpty ? id : null, hue: hue is String && hue.isNotEmpty ? hue : null, order: order is num ? order.toInt() : null);
  }

  Map<String, Object?> toJson() => {if (id != null) 'id': id, if (hue != null) 'hue': hue, if (order != null) 'order': order};
}

/// An organization's entry in the `orgs` section, keyed by its folder (`orgs/Acme`): which organization it is, its
/// raw name and its hue, so a restore matches `orgs/Acme/` to `org-<id>` after sign-in even once the organization
/// has been renamed.
@immutable
class ConfigOrg {
  const ConfigOrg({required this.org, required this.name, this.hue});
  final String org;
  final String name;
  final String? hue;

  static ConfigOrg? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final org = raw['org'], name = raw['name'], hue = raw['hue'];
    if (org is! String || org.isEmpty || name is! String) return null;
    return ConfigOrg(org: org, name: name, hue: hue is String && hue.isNotEmpty ? hue : null);
  }

  Map<String, Object?> toJson() => {'org': org, 'name': name, if (hue != null) 'hue': hue};
}

/// The file, decoded: each section as JSON this build reads, the stamps, and every key it does not know.
@immutable
class LibraryConfig {
  const LibraryConfig({
    this.workspaces = const {},
    this.orgs = const {},
    this.dailyNotes,
    this.smartNotebooks,
    this.defaults = const {},
    this.slack,
    this.discord,
    this.written = const {},
    this.more = const {},
  });

  /// Nothing at all: the config of a library never written.
  static const LibraryConfig empty = LibraryConfig();

  /// The file's text read; anything but an object is [empty]. A section of the wrong shape is read as absent and
  /// kept in [more] as it was, so a rewrite does not drop it.
  factory LibraryConfig.parse(String? text) {
    if (text == null || text.trim().isEmpty) return empty;
    Object? raw;
    try {
      raw = jsonDecode(text);
    } catch (_) {
      return empty;
    }
    if (raw is! Map) return empty;
    final map = <String, Object?>{for (final entry in raw.entries) '${entry.key}': entry.value};
    final spaces = map['workspaces'], orgs = map['orgs'], daily = map['dailyNotes'], smart = map['smartNotebooks'], defaults = map['defaults'], slack = map['slack'], discord = map['discord'], written = map['written'];
    final known = <String>{'version', 'written', ...libraryConfigSections};
    return LibraryConfig(
      workspaces: Map.unmodifiable({
        if (spaces is Map)
          for (final entry in spaces.entries)
            if (entry.key is String && ConfigFolder.fromJson(entry.value) != null) entry.key as String: ConfigFolder.fromJson(entry.value)!,
      }),
      orgs: Map.unmodifiable({
        if (orgs is Map)
          for (final entry in orgs.entries)
            if (entry.key is String && ConfigOrg.fromJson(entry.value) != null) entry.key as String: ConfigOrg.fromJson(entry.value)!,
      }),
      dailyNotes: daily is Map ? Map.unmodifiable({for (final entry in daily.entries) '${entry.key}': entry.value}) : null,
      smartNotebooks: smart is List ? List.unmodifiable(smart) : null,
      defaults: defaults is Map ? Map.unmodifiable({for (final entry in defaults.entries) '${entry.key}': entry.value}) : const {},
      slack: slack is Map ? Map.unmodifiable({for (final entry in slack.entries) '${entry.key}': entry.value}) : null,
      discord: discord is Map ? Map.unmodifiable({for (final entry in discord.entries) '${entry.key}': entry.value}) : null,
      written: Map.unmodifiable({
        if (written is Map)
          for (final entry in written.entries)
            if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
      }),
      more: Map.unmodifiable({
        for (final entry in map.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
      }),
    );
  }

  /// The config as the preferences and the plugins' storage say it now. [stored] is read for the Slack and Discord
  /// channels; left out, those sections are absent.
  factory LibraryConfig.of(Preferences prefs, {Stored? stored}) {
    final all = [for (final w in prefs.workspaces.list) Workspace.kept(id: w.id, name: w.name, hue: w.hue, parent: w.parent)];
    final spaces = <String, ConfigFolder>{};
    final siblings = <String?, int>{};
    for (final w in all) {
      if (orgOfWorkspace(all, w.id) != null) continue;
      final path = _pathOf(all, w);
      if (path == null) continue;
      final order = siblings[w.parent] ?? 0;
      siblings[w.parent] = order + 1;
      // The id only where it is not the one its place gives it: a folder from before 2026-10-23, or one renamed since.
      final placed = folderIdFor(all, w.name, w.parent);
      spaces[path] = ConfigFolder(id: placed == w.id ? null : w.id, hue: w.hue, order: order);
    }
    final orgs = <String, ConfigOrg>{};
    for (final w in all) {
      final org = orgIdOf(w.id);
      if (org == null) continue;
      final folder = folderName(w.name);
      if (folder.isEmpty) continue;
      orgs['$orgsFolder/$folder'] = ConfigOrg(org: org, name: w.name, hue: w.hue);
    }
    final daily = prefs.more.containsKey(dailyNotesKey) ? _dailyOut(dailyNotesIn(prefs), all) : null;
    final smart = prefs.more[smartNotebooksKey];
    return LibraryConfig(
      workspaces: Map.unmodifiable(spaces),
      orgs: Map.unmodifiable(orgs),
      dailyNotes: daily,
      smartNotebooks: smart is List ? List.unmodifiable(smart) : null,
      defaults: Map.unmodifiable({'geotag': prefs.tagNewNotes, 'mapTiles': prefs.mapTiles, 'placeNames': prefs.placeNames}),
      slack: stored == null ? null : _channelsOut(stored, slackChannelsKey, slackMeetingsKey),
      discord: stored == null ? null : _channelsOut(stored, discordChannelsKey, discordMeetingsKey),
    );
  }

  /// Personal folders by their path under `workspaces/`: `Work`, `Work/Clients`.
  final Map<String, ConfigFolder> workspaces;

  /// Organizations by their folder: `orgs/Acme`.
  final Map<String, ConfigOrg> orgs;

  /// `{"folder": "Daily notes" (a path under `workspaces/`, "" for none), "notebook": "<note id>", "template": "A day"}`.
  final Map<String, Object?>? dailyNotes;

  /// `[{"id", "name", "query"}]`, as lib/core/smart_notebooks.dart keeps them.
  final List<Object?>? smartNotebooks;

  /// `{"geotag": true, "mapTiles": true, "placeNames": true}`.
  final Map<String, Object?> defaults;

  /// `{"channels": [{"id", "name"}], "meetings": {"channel", "share"}}`, names and ids only.
  final Map<String, Object?>? slack;
  final Map<String, Object?>? discord;

  /// When each section was last written, by section, as ISO instants.
  final Map<String, String> written;

  /// Every top-level key this build does not know, kept as it was.
  final Map<String, Object?> more;

  /// One section as JSON, or null where the file has none of it. The maps keyed by path are written shallow first and
  /// then by name, so two configs saying the same thing encode the same bytes.
  Object? section(String name) => switch (name) {
        'workspaces' => workspaces.isEmpty ? null : {for (final key in _byDepth(workspaces.keys)) key: workspaces[key]!.toJson()},
        'orgs' => orgs.isEmpty ? null : {for (final key in _byDepth(orgs.keys)) key: orgs[key]!.toJson()},
        'dailyNotes' => dailyNotes,
        'smartNotebooks' => smartNotebooks,
        'defaults' => defaults.isEmpty ? null : defaults,
        'slack' => slack,
        'discord' => discord,
        _ => more[name],
      };

  /// The file, as JSON: the version, each section that has anything, the stamps, and the unknown keys.
  Map<String, Object?> toJson() => {
        'version': libraryConfigVersion,
        for (final name in libraryConfigSections)
          if (section(name) != null) name: section(name),
        if (written.isNotEmpty) 'written': written,
        ...more,
      };

  /// The file's text, indented, with a line break at the end as a committed file has.
  String encode() => '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// This config with [written] replaced.
  LibraryConfig stamped(Map<String, String> written) => LibraryConfig(
        workspaces: workspaces,
        orgs: orgs,
        dailyNotes: dailyNotes,
        smartNotebooks: smartNotebooks,
        defaults: defaults,
        slack: slack,
        discord: discord,
        written: Map.unmodifiable(written),
        more: more,
      );

  /// This config with the unknown keys of [other] kept, as a rewrite keeps them.
  LibraryConfig keeping(LibraryConfig other) => LibraryConfig(
        workspaces: workspaces,
        orgs: orgs,
        dailyNotes: dailyNotes,
        smartNotebooks: smartNotebooks,
        defaults: defaults,
        slack: slack,
        discord: discord,
        written: written,
        more: other.more,
      );

  /// Whether the two say the same of [name].
  bool sameSection(LibraryConfig other, String name) => jsonEncode(section(name)) == jsonEncode(other.section(name));

  /// Paths shallow first, then by name.
  static List<String> _byDepth(Iterable<String> paths) => paths.toList()
    ..sort((a, b) {
      final da = a.split('/').length, db = b.split('/').length;
      return da != db ? da.compareTo(db) : a.compareTo(b);
    });

  // --- from the preferences ------------------------------------------------------------------------------------------

  /// A personal folder's path under `workspaces/`: `Work/Clients`. Null for one whose name cleans away.
  static String? _pathOf(List<Workspace> all, Workspace w) {
    final folder = folderFor(w, all);
    if (folder == null || !folder.startsWith('$workspacesFolder/')) return null;
    return folder.substring(workspacesFolder.length + 1);
  }

  static Map<String, Object?> _dailyOut(DailyNotesSetup setup, List<Workspace> all) {
    final folder = setup.folder;
    String? path;
    if (folder == null) {
      path = null;
    } else if (folder.isEmpty) {
      path = '';
    } else {
      final w = all.where((each) => each.id == folder).firstOrNull;
      // A folder this device has not got is kept by its id: the next device may have it.
      path = w == null ? folder : (_pathOf(all, w) ?? folder);
    }
    return Map.unmodifiable({'folder': ?path, 'notebook': ?setup.notebook, 'template': ?setup.template});
  }

  static Map<String, Object?>? _channelsOut(Stored stored, String channelsKey, String meetingsKey) {
    final raw = stored.read<Object?>(channelsKey, null);
    final channels = [
      if (raw is List)
        for (final each in raw)
          if (each is Map && each['id'] is String && each['name'] is String) {'id': each['id'], 'name': each['name']},
    ];
    final meetings = stored.read<Object?>(meetingsKey, null);
    final posting = meetings is Map && meetings['channel'] is String ? {'channel': meetings['channel'], 'share': meetings['share'] != false} : null;
    if (channels.isEmpty && posting == null) return null;
    return Map.unmodifiable({if (channels.isNotEmpty) 'channels': channels, 'meetings': ?posting});
  }
}

// --- into the preferences --------------------------------------------------------------------------------------------

/// [prefs] with the file's [section] taken, additively: what the file has and the preferences lack is added, what
/// both have takes the file's word (a hue, the daily-notes template), and nothing in the preferences is removed.
/// [stored] takes the `slack` and `discord` sections, which are the plugins' storage, not the preferences; left
/// out, those sections are passed over. Answers the preferences unchanged for a section the file lacks.
Preferences applyConfigSection(Preferences prefs, LibraryConfig config, String section, {Stored? stored}) {
  switch (section) {
    case 'workspaces':
      return config.workspaces.isEmpty ? prefs : _applyWorkspaces(prefs, config.workspaces);
    case 'orgs':
      return config.orgs.isEmpty ? prefs : _applyOrgs(prefs, config.orgs);
    case 'dailyNotes':
      final daily = config.dailyNotes;
      if (daily == null) return prefs;
      final all = [for (final w in prefs.workspaces.list) Workspace.kept(id: w.id, name: w.name, hue: w.hue, parent: w.parent)];
      final folder = daily['folder'];
      final was = dailyNotesIn(prefs);
      // The file names the folder by its path; a path this device has no folder for yet is left as the file wrote it
      // only where it is an id this device has (a file from before paths), else the choice here stands.
      final String? folderId = folder is! String ? was.folder : (folder.isEmpty ? '' : _workspaceAt(all, folder)?.id ?? (all.any((w) => w.id == folder) ? folder : was.folder));
      final setup = DailyNotesSetup(
        folder: folderId,
        notebook: daily['notebook'] is String ? daily['notebook'] as String : was.notebook,
        template: daily['template'] is String ? daily['template'] as String : was.template,
      );
      return withDailyNotes(prefs, setup);
    case 'smartNotebooks':
      final smart = config.smartNotebooks;
      if (smart == null) return prefs;
      final mine = prefs.more[smartNotebooksKey];
      final ids = <String>{};
      final merged = <Object?>[
        for (final each in smart)
          if (each is Map && each['id'] is String && ids.add(each['id'] as String)) each,
        if (mine is List)
          for (final each in mine)
            if (each is Map && each['id'] is String && ids.add(each['id'] as String)) each,
      ];
      return prefs.copyWith(more: {...prefs.more, smartNotebooksKey: merged});
    case 'defaults':
      final defaults = config.defaults;
      if (defaults.isEmpty) return prefs;
      return prefs.copyWith(
        tagNewNotes: defaults['geotag'] is bool ? defaults['geotag'] as bool : prefs.tagNewNotes,
        mapTiles: defaults['mapTiles'] is bool ? defaults['mapTiles'] as bool : prefs.mapTiles,
        placeNames: defaults['placeNames'] is bool ? defaults['placeNames'] as bool : prefs.placeNames,
      );
    case 'slack':
      if (stored != null && config.slack != null) _applyChannels(stored, config.slack!, slackChannelsKey, slackMeetingsKey);
      return prefs;
    case 'discord':
      if (stored != null && config.discord != null) _applyChannels(stored, config.discord!, discordChannelsKey, discordMeetingsKey);
      return prefs;
    default:
      return prefs;
  }
}

/// The folder at [path] under `workspaces/` (`Work/Clients`), found a name at a time as the team's channel finds an
/// organization's (lib/team/folders.dart `_find`): by the name its folder on disk is given, in any case.
Workspace? _workspaceAt(List<Workspace> all, String path) {
  Workspace? at;
  for (final name in path.split('/')) {
    if (name.isEmpty) return null;
    final wanted = name.toLowerCase();
    Workspace? found;
    for (final w in all) {
      if (w.parent != at?.id || isOrgWorkspace(w.id)) continue;
      if (folderName(w.name).toLowerCase() == wanted) {
        found = w;
        break;
      }
    }
    if (found == null) return null;
    at = found;
  }
  return at;
}

Preferences _applyWorkspaces(Preferences prefs, Map<String, ConfigFolder> folders) {
  final list = [for (final w in prefs.workspaces.list) Workspace.kept(id: w.id, name: w.name, hue: w.hue, parent: w.parent)];
  // Shallow first, so a folder's parent is there before it is.
  for (final path in LibraryConfig._byDepth(folders.keys)) {
    final entry = folders[path]!;
    final names = path.split('/');
    if (names.any((name) => name.isEmpty)) continue;
    final parentPath = names.length > 1 ? names.sublist(0, names.length - 1).join('/') : null;
    final parent = parentPath == null ? null : _workspaceAt(list, parentPath);
    if (parentPath != null && parent == null) continue;
    final found = _workspaceAt(list, path);
    if (found != null) {
      if (entry.hue != null && entry.hue != found.hue) {
        final at = list.indexOf(found);
        list[at] = found.copyWith(hue: entry.hue);
      }
      continue;
    }
    final name = names.last;
    // The id the file keeps, else the one its place gives it, the same on every device (`folderIdFor`); a name that
    // cleans away makes no folder.
    final id = entry.id ?? folderIdFor(list, name, parent?.id);
    if (id == null || list.any((w) => w.id == id)) continue;
    list.add(Workspace(id: id, name: name, hue: entry.hue, parent: parent?.id));
  }
  // Siblings in the file's order where it gives one, the rest after them as they were.
  final orders = <String, int>{};
  for (final entry in folders.entries) {
    final order = entry.value.order, w = _workspaceAt(list, entry.key);
    if (order != null && w != null) orders[w.id] = order;
  }
  final ordered = [...list];
  final index = {for (final (at, w) in list.indexed) w.id: at};
  ordered.sort((a, b) {
    if (a.parent != b.parent) return index[a.id]!.compareTo(index[b.id]!);
    final oa = orders[a.id], ob = orders[b.id];
    if (oa != null && ob != null && oa != ob) return oa.compareTo(ob);
    return index[a.id]!.compareTo(index[b.id]!);
  });
  return prefs.copyWith(workspaces: KeptWorkspaces(list: List.unmodifiable([for (final w in ordered) KeptWorkspace(id: w.id, name: w.name, hue: w.hue, parent: w.parent)]), notes: prefs.workspaces.notes));
}

Preferences _applyOrgs(Preferences prefs, Map<String, ConfigOrg> orgs) {
  final list = [...prefs.workspaces.list];
  for (final org in orgs.values) {
    final id = orgWorkspaceId(org.org);
    final at = list.indexWhere((w) => w.id == id);
    if (at >= 0) {
      // The organization's own name and hue follow the service once signed in (lib/orgs/orgs.dart); the file's are
      // for a device that has not signed in yet, and never overrule what is here.
      continue;
    }
    list.add(KeptWorkspace(id: id, name: org.name, hue: org.hue));
  }
  return prefs.copyWith(workspaces: KeptWorkspaces(list: List.unmodifiable(list), notes: prefs.workspaces.notes));
}

void _applyChannels(Stored stored, Map<String, Object?> section, String channelsKey, String meetingsKey) {
  final channels = section['channels'];
  if (channels is List) {
    final raw = stored.read<Object?>(channelsKey, null);
    final mine = <Map<String, Object?>>[
      if (raw is List)
        for (final each in raw)
          if (each is Map && each['id'] is String) {for (final entry in each.entries) '${entry.key}': entry.value},
    ];
    for (final each in channels) {
      if (each is! Map || each['id'] is! String || each['name'] is! String) continue;
      final at = mine.indexWhere((have) => have['id'] == each['id']);
      if (at >= 0) {
        // Merged by id into the item this device has, never replacing it: the channel's other fields are its own.
        mine[at] = {...mine[at], 'name': each['name']};
      } else {
        mine.add({'id': each['id'], 'name': each['name']});
      }
    }
    if (mine.isNotEmpty) stored.write(channelsKey, mine);
  }
  final meetings = section['meetings'];
  if (meetings is Map && meetings['channel'] is String) {
    final raw = stored.read<Object?>(meetingsKey, null);
    final mine = raw is Map ? {for (final entry in raw.entries) '${entry.key}': entry.value} : <String, Object?>{};
    // The `on` switch stays the account's: the file says which channel and whether to share, never whether to post.
    stored.write(meetingsKey, {...mine, 'channel': meetings['channel'], if (meetings['share'] is bool) 'share': meetings['share']});
  }
}

/// Whether the preferences describe no library at all: no folders, no organizations, none of the file's other
/// sections. What a restored library opens with.
bool preferencesDescribeNoLibrary(Preferences prefs) =>
    prefs.workspaces.list.isEmpty && !prefs.more.containsKey(dailyNotesKey) && !prefs.more.containsKey(smartNotebooksKey);

// --- the keeper --------------------------------------------------------------------------------------------------------

/// Keeps `config.json` and the preferences in step (see the header): read at [open], applied section by section
/// where the file is newer than this device's memory of it, and written a moment after the preferences change.
class LibraryConfigKeeper {
  LibraryConfigKeeper({required this.file, required this.preferences, Stored? stored, this.writeAfter = const Duration(seconds: 2), DateTime Function()? clock, void Function(String message)? log})
      : _stored = stored,
        _clock = clock ?? DateTime.now,
        _log = log ?? debugPrint;

  final ConfigFile file;
  final PreferencesStore preferences;
  final Stored? _stored;
  final Duration writeAfter;
  final DateTime Function() _clock;
  final void Function(String message) _log;

  Stored get _device => _stored ?? stored;

  /// The file as last read or written.
  LibraryConfig _file = LibraryConfig.empty;
  LibraryConfig get fileConfig => _file;

  Timer? _writing;
  bool _listening = false;
  bool _applying = false;
  Future<void> _work = Future<void>.value();

  Map<String, String> _seen() {
    final raw = _device.read<Object?>(libraryConfigSeenKey, null);
    return {
      if (raw is Map)
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
    };
  }

  void _saveSeen(Map<String, String> seen) => _device.write(libraryConfigSeenKey, seen.isEmpty ? null : seen);

  /// Reads the file and takes what is newer, then listens to the preferences for what to write. Answers the
  /// sections taken, for the log and the tests.
  Future<List<String>> open() async {
    final taken = await reread();
    if (!_listening) {
      _listening = true;
      preferences.addListener(_changed);
    }
    return taken;
  }

  /// Reads the file again: on open, and when the app comes back to a folder another device may have written to.
  Future<List<String>> reread() => _inTurn(() async {
        _file = LibraryConfig.parse(await file.read());
        final seen = _seen();
        final restore = preferencesDescribeNoLibrary(preferences.value) && seen.isEmpty;
        final taken = <String>[];
        var next = preferences.value;
        for (final name in libraryConfigSections) {
          if (_file.section(name) == null) continue;
          final stamp = _file.written[name];
          final mine = seen[name];
          // Last writer wins per section: taken where the file's stamp is later than what this device wrote or applied,
          // or on a restore, where the device has nothing of its own to stand on. A tie, or an older stamp, leaves the
          // preferences, which the account's sync reconciles.
          final newer = stamp != null && (mine == null || stamp.compareTo(mine) > 0);
          if (!newer && !restore) continue;
          next = applyConfigSection(next, _file, name, stored: _device);
          if (stamp != null) seen[name] = stamp;
          taken.add(name);
        }
        if (taken.isEmpty) return taken;
        _applying = true;
        try {
          if (!identical(next, preferences.value)) preferences.value = next;
        } finally {
          _applying = false;
        }
        _saveSeen(seen);
        _log('[glyph] library config read: ${taken.join(', ')}');
        return taken;
      });

  void _changed() {
    if (_applying) return;
    _writing ??= Timer(writeAfter, flush);
  }

  /// Something outside the preferences the file carries changed (a Slack channel renamed): written with the next
  /// flush.
  void touch() => _changed();

  /// Writes what differs now, if anything does. Asked as the app is hidden, and by the timer.
  Future<void> flush() {
    _writing?.cancel();
    _writing = null;
    return _inTurn(_write);
  }

  Future<void> _write() async {
    final now = LibraryConfig.of(preferences.value, stored: _device);
    // The file as it is NOW, not as it was read at open: another device sharing the folder may have written since,
    // and its stamps are what decide which sections this write may touch.
    _file = LibraryConfig.parse(await file.read());
    final seen = _seen();
    final stamps = {..._file.written};
    final stamp = _clock().toUtc().toIso8601String();
    var changed = false;
    for (final name in libraryConfigSections) {
      if (now.section(name) == null && _file.section(name) == null) continue;
      if (now.sameSection(_file, name)) continue;
      // A section the file has and the preferences have not yet taken (its stamp is newer than this device saw) is
      // not overwritten from here: the next reread takes it first.
      final theirs = _file.written[name], mine = seen[name];
      if (theirs != null && (mine == null || theirs.compareTo(mine) > 0)) continue;
      stamps[name] = stamp;
      seen[name] = stamp;
      changed = true;
    }
    if (!changed) return;
    final next = now.stamped(stamps).keeping(_file);
    final json = next.toJson();
    if (looksSecret(json)) {
      _log('[glyph] library config not written: a value looks like a secret');
      return;
    }
    try {
      await file.write(next.encode());
      _file = next;
      _saveSeen(seen);
    } catch (failure) {
      _log('[glyph] library config not written: $failure');
    }
  }

  Future<T> _inTurn<T>(Future<T> Function() step) {
    final next = _work.then((_) => step());
    _work = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  void dispose() {
    _writing?.cancel();
    _writing = null;
    if (_listening) preferences.removeListener(_changed);
    _listening = false;
  }
}
