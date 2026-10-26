/// What a plugin is, and every place it can reach into Ghost.md. A port of `src/app/plugins/types.ts`.
///
/// A plugin is a module that ships inside the app and arrives with its updates. It says what it is and what it
/// needs in a manifest, and adds itself to the app only through the extension points below. Nothing in the app
/// names a plugin: the note's cog, the list swipe, the recorder, the formatter and Settings each ask the registry
/// (registry.dart) for whatever the switched-on plugins offer there.
///
/// The manifest is enforced, not decorative. A plugin reaches the phone only through its [PluginHost] (host.dart),
/// and the host refuses a storage key, a secret, an outside host or a permission the manifest did not declare.
///
/// What differs:
/// - **No native commands.** The page reached Notion and Slack through Rust (`notion_request`, `slack_post`) only
///   because a WebView has an origin; here a plugin asks the network itself, through [PluginHost.fetch], which the
///   host holds to [PluginManifest.hosts]. `manifest.native` and `host.invoke` are kept as the page has them (the
///   card in Settings still says "Built-in app commands" for a plugin that keeps a secret), and `invoke` refuses
///   everything, since there is nothing to call.
/// - **Secrets have their own door.** A token or a webhook is never in [PluginHost.storage] (SharedPreferences):
///   it is in [PluginHost.secrets], over the device's secure store (lib/account/device_keys.dart `SecureStore`),
///   by a name [PluginManifest.secrets] lists. The page kept GitHub's token in localStorage; a reset clears both.
/// - A component is a builder: [PluginIcon], [NoteLink.picker], [PluginSettings.pane].
/// - `InlineFormat` and `FormatLook` are marks.dart's [GlyphFormat] and [FormatLook], which the editor already
///   reads; [InlineFormat] is the page's name for the first.
library;

import 'package:flutter/widgets.dart';

import '../account/api.dart' show FetchRequest, FetchResponse;
import '../account/ui_state.dart' show AccountServices;
import '../core/notifications.dart' show FeedNotification;
import '../settings/settings_search.dart' show SettingsFindable;
import 'mark_details.dart';
import 'marks.dart';

export 'mark_details.dart';
export 'marks.dart' show EffectLook, FormatLook, GlyphFormat, StyleLook, WispLook;

// ---- the manifest ------------------------------------------------------------------------------------------------

/// What a plugin may do (`Permission`).
enum Permission {
  /// Reads and changes notes other than through the screen showing them.
  notes,

  /// Talks to a service outside the phone (the hosts are listed).
  network,

  /// Runs the phone's language model.
  ai,

  /// Hears commands while a note is being recorded. No extension point takes them any more; kept as the page keeps it.
  voice,

  /// Keeps something inside the app where no page can read it (the page: calls commands built into the binary).
  native,
}

/// Where a plugin stands in Settings › Plugins, which is a catalogue to browse (Matt, 2026-10-18: "rework the plugins
/// page to be a marketplace"): the filter's words, in the order the filter and the catalogue have them. Not on the
/// page, whose Plugins was a list of cards.
enum PluginCategory {
  ai('AI'),
  calendar('Calendar & tasks'),
  imports('Import'),
  connections('Connections'),
  editor('Editor');

  const PluginCategory(this.label);

  /// The filter's word for it, and the caption over its plugins.
  final String label;
}

/// One permission, with the reason shown to the person.
@immutable
class PluginPermission {
  const PluginPermission(this.kind, this.why);
  final Permission kind;
  final String why;
}

/// The binary a plugin needs (`manifest.native`): a native generation at least this, and the commands it called
/// on the page. Kept for the card; nothing here calls them.
@immutable
class PluginNative {
  const PluginNative({required this.generation, this.commands = const []});
  final int generation;
  final List<String> commands;
}

@immutable
class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    required this.standard,
    required this.permissions,
    this.hosts = const [],
    this.native,
    required this.storage,
    this.secrets = const [],
    this.category,
    this.tagline,
    this.adds = const [],
  });

  /// Stable, lowercase: the key its switch and its storage are kept under.
  final String id;
  final String name;

  /// What it does, in a sentence or two: its detail page in Settings › Plugins.
  final String description;
  final String version;
  final String author;

  /// Ships with Ghost.md and is on until switched off.
  final bool standard;

  /// Everything it may do, each with the reason shown to the person.
  final List<PluginPermission> permissions;

  /// The outside hosts it talks to, shown with the network permission, and the only ones [PluginHost.fetch] reaches.
  final List<String> hosts;
  final PluginNative? native;

  /// The stored keys it owns; a reset clears them.
  final List<String> storage;

  /// The names it keeps in the secure store, or the prefixes of them when one ends in `:` (a webhook per channel:
  /// `glyph-slack-webhook:`). A reset forgets them. Not on the page, where Rust or localStorage held them.
  final List<String> secrets;

  /// Its shelf in the catalogue; one with none is found under All alone.
  final PluginCategory? category;

  /// A few words for its card in the catalogue, where [description] is the detail page's; the description when null.
  final String? tagline;

  /// What it puts in the app once added, a phrase each, for its detail page: "Swipe a list item to send it".
  final List<String> adds;

  /// The card's line: [tagline], or the [description] where there is none.
  String get line => tagline ?? description;

  bool declares(Permission kind) => permissions.any((p) => p.kind == kind);
}

// ---- what a plugin is handed -------------------------------------------------------------------------------------

/// The plugin's own keys, as JSON. A key the manifest does not list is refused (`PluginHost.storage`).
abstract interface class PluginStorage {
  /// Read shared (lib/core/stored.dart `readShared`): what it answers is shared between readers, so a plugin that
  /// changes it copies it first.
  T get<T>(String key, T fallback);
  void set(String key, Object? value);
  void remove(String key);
}

/// The plugin's secrets, by the names its manifest lists. Anything else is refused.
abstract interface class PluginSecrets {
  /// What is kept under [name], or null: none, or a store that will not say.
  Future<String?> read(String name);

  /// Keeps [value]; null forgets it. Whoever draws from the plugin's storage is told, as for a stored key.
  Future<void> write(String name, String? value);

  /// What [read] or [write] last saw for [name], with no wait: null before the first read. For the questions the
  /// page asked synchronously ("is there a token?") on every draw; [warm] makes them true to the store.
  String? held(String name);

  /// Reads every exact name the manifest lists once, so [held] answers. Asked at launch and after a reset.
  Future<void> warm();
}

abstract interface class PluginHost {
  PluginManifest get manifest;

  /// Whether this binary has what the manifest's `native` asks for.
  Future<bool> nativeReady();

  /// The page's door to a native command. Nothing is behind it here: it refuses, naming the plugin.
  Future<T> invoke<T>(String command, [Map<String, Object?>? args]);

  PluginStorage get storage;
  PluginSecrets get secrets;

  /// Asks the network (network permission), only of a host the manifest lists.
  Future<FetchResponse> fetch(FetchRequest request);

  /// Opens a page in the browser (network permission).
  Future<void> openUrl(String url);

  /// Asserts a permission the manifest declares, for plugin code that reaches core modules directly (`require`).
  void need(Permission permission);
}

// ---- extension points --------------------------------------------------------------------------------------------

/// A plugin's mark, drawn [size] pixels square in the colour of the text around it.
typedef PluginIcon = Widget Function(BuildContext context, double size);

/// A row under "Linked to" on a note's cog sheet, and the page it opens.
class NoteLink {
  const NoteLink({required this.id, required this.label, required this.icon, required this.hint, this.unavailable, required this.picker, this.linked});
  final String id;
  final String label;
  final PluginIcon icon;

  /// The row's second line for this note: what it is linked to, or what linking does.
  final String Function(String noteId) hint;

  /// Whether it can be used on this build; a reason when it cannot.
  final Future<String?> Function()? unavailable;

  /// The page, inside the sheet. `onDone` goes back to the note's settings.
  final Widget Function(BuildContext context, String noteId, VoidCallback onDone) picker;

  /// The name of what this note is linked to ("Glyph Tasks", "attackfm/app"), or null when it isn't: the mark the
  /// note carries at its top and in the list (link_marks.dart). Read on every draw; keep it cheap.
  final String? Function(String noteId)? linked;
}

/// The note on screen, for actions that change it: edits go through its editor, so each is an undo step.
abstract interface class NoteEditing {
  String get noteId;
  String body();

  /// Replaces the first line [find] accepts (its text, its 1-based line) with what [next] makes of it. Answers
  /// whether one was found.
  bool replaceLine(bool Function(String text, int line) find, String Function(String text) next);

  /// A sentence shown on the note for a few seconds.
  void say(String message);
}

/// One place a note action can go, drawn as a row on its page of the sheet.
@immutable
class ActionChoice {
  const ActionChoice({required this.id, required this.label, this.hint});
  final String id;
  final String label;
  final String? hint;
}

/// A row under the links on a note's cog sheet: something to do with the note.
class NoteAction {
  const NoteAction({required this.id, required this.label, required this.icon, required this.visible, required this.hint, required this.enabled, this.choices, required this.run});
  final String id;
  final String label;
  final PluginIcon icon;

  /// Whether the row shows for this note at all, by the note as it was when the sheet opened.
  final bool Function(String noteId, String body) visible;
  final String Function(String noteId, String body) hint;
  final bool Function(String noteId, String body) enabled;

  /// Where it could go, when it goes somewhere: a Slack channel to post to. With more than one, pressing the row
  /// opens them as a page of the sheet and the one pressed is handed to [run]; with one, [run] is handed that one
  /// at once. Without, the row simply runs.
  final List<ActionChoice> Function(String noteId)? choices;

  /// `choice` is the id of the choice pressed, for an action with [choices].
  final Future<void> Function(NoteEditing editing, [String? choice]) run;
}

/// Swiping a list item left in a note.
class ItemAction {
  const ItemAction({required this.id, required this.label, required this.busyLabel, required this.available, required this.run});
  final String id;

  /// The word on the tile behind the item, and while it runs.
  final String label;
  final String busyLabel;

  /// Whether swiping does anything on this note right now.
  final bool Function(String noteId) available;

  /// `text` is the item's words; the item's line is found again by them.
  final Future<void> Function(String text, NoteEditing editing) run;
}

/// Something to say, suggested in a pause while recording.
@immutable
class Tip {
  const Tip({required this.say, required this.does});
  final String say;
  final String does;
}

/// Background the formatter hands the model with a note.
class FormatContext {
  const FormatContext({required this.forNote, required this.version});

  /// `for`.
  final String? Function(String noteId) forNote;

  /// Changes when [forNote] would say something new, so the note is formatted again.
  final int Function(String noteId) version;
}

/// A quiet word at the end of a line of the note: what a plugin could do with that line, tapped to do it. "Notion"
/// after a to-do that could be a task (lib/editor/items/suggestions.dart draws them).
class Suggestion {
  const Suggestion({required this.line, required this.label, required this.busyLabel, required this.run});

  /// 1-based line in the note.
  final int line;
  final String label;

  /// The word while it runs: "Sending".
  final String busyLabel;
  final Future<void> Function(NoteEditing editing) run;
}

/// An inline formatting a plugin adds to the Markdown of notes (`InlineFormat`): marks.dart's own class.
typedef InlineFormat = GlyphFormat;

/// A plugin's page in Settings, the page's one-line reading, and its colour there.
class PluginSettings {
  const PluginSettings({required this.pane, required this.summary, this.hue, this.settings = const [], this.simple = false, this.offered, this.accountSummary, this.findable});
  final WidgetBuilder pane;
  final String Function() summary;

  /// One of the hues the settings draw (`[data-hue]`), or grey without one.
  final String? hue;

  /// What the search finds on the page: its cards' titles and rows' labels.
  final List<SettingsFindable> settings;

  /// Kept in Simple, where every other plugin's page waits behind Advanced: the meeting plugins' (Google Meet, Zoom),
  /// which are what Settings › Meetings was, and that was a page of Simple's (Matt, 2026-10-26: "I want settings /
  /// meetings to be broken up into three plugins"). Not on the page.
  final bool simple;

  /// Whether the page is listed for this account at all, the account's services as Settings has them; null is always.
  /// A meeting plugin's page needs a service with Ghost in meetings. Not on the page.
  final bool Function(AccountServices? services)? offered;

  /// The row's reading from the account, in place of [summary]: how many meetings of its kind Ghost is booked for.
  final String Function(AccountServices? services)? accountSummary;

  /// What the search finds on the page as the account has it, in place of [settings].
  final List<SettingsFindable> Function(AccountServices? services)? findable;
}

class GlyphPlugin {
  const GlyphPlugin({
    required this.manifest,
    required this.icon,
    this.settings,
    this.noteLinks = const [],
    this.noteActions = const [],
    this.itemAction,
    this.tips,
    this.formatContext,
    this.suggest,
    this.marks,
    this.formats = const [],
    this.newRows,
  });

  final PluginManifest manifest;

  /// A Lucide icon's name (`@glacier/icons`), drawn by lib/art's `AppIcon`: "square-kanban".
  final String icon;
  final PluginSettings? settings;
  final List<NoteLink> noteLinks;
  final List<NoteAction> noteActions;
  final ItemAction? itemAction;

  /// Things to say in a pause while recording, for the note the routing tip names.
  final List<Tip> Function(String? recentTitle)? tips;
  final FormatContext? formatContext;

  /// The words offered on the lines of a note as it stands (pure: read on every change).
  final List<Suggestion> Function(String noteId, String body)? suggest;

  /// What its item marks link to, read back, for marks named with the plugin's id.
  final MarkDetailsProvider? marks;

  /// Inline formattings of its own in every note.
  final List<InlineFormat> formats;

  /// The bell's rows after each pass of the feed (lib/sync/arrived.dart). Told only while the plugin is on.
  final Future<void> Function(int before, List<FeedNotification> rows)? newRows;
}
