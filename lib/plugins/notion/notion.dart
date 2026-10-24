/// The Notion plugin, standard in Ghost.md: a note linked to a board sends its list items there as tasks, and each
/// item's words become a link to its task. A port of `src/app/plugins/notion/index.tsx`.
///
/// - On a note's cog: "Notion board" under Linked to ([BoardPicker]), and "Send list to Notion" once one is linked.
/// - In the note: swipe a list item left to send it, or tap the quiet "Notion" after it.
/// - In Settings: signing in, and the boards Notion shared ([NotionPane]).
///
/// What differs:
/// - The link's `unavailable` has one answer left: the page's "Works in the Ghost.md app on your phone." was for a
///   browser.
/// - [notionPlugin] is made the first time it is read (the registry lists it at launch), and making it asks
///   whether Notion can be reached, as loading the page's modules did. The sign-in itself is read when it is
///   needed; `host.secrets.warm()`, which the app's root asks of every plugin's host at launch, is what lets
///   [notionAccountNow] answer without a wait.
library;

import 'dart:async';

import 'package:glacier/glacier.dart' show HapticKind, haptic;

import '../../core/item_links.dart' show unsentItems;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../send_items.dart';
import '../types.dart';
import 'board_picker.dart';
import 'client.dart';
import 'details.dart';
import 'manifest.dart';
import 'marks.dart';
import 'notion_pane.dart';

export 'board_picker.dart' show BoardPicker;
export 'client.dart';
export 'details.dart' show NotionPage, StageMap, StageOptions, detailsOf, forgetTaskDetails, guessStage, notionDetails, pageIdOf, resetNotionDetails, stagesOf, warmNotionDetails;
export 'manifest.dart' show accountSecret;
export 'marks.dart' show NotionMark;
export 'notion_pane.dart' show NotionPane;

/// The plugin's manifest and host, under names that do not meet another plugin's (`manifest`, `host`).
const PluginManifest notionManifest = manifest;
PluginHost get notionHost => host;

/// What has just been sent from a note, so the same words are never made into two tasks (lib/plugins/send_items.dart).
final ItemSender _sender = ItemSender('notion', now: () => notionNow());

/// For the tests: what was sent is otherwise kept in memory for the app's life, five minutes a send.
void forgetSent() => _sender.forget();

/// Sends list items to Notion from the note on screen: each becomes a task on [board], and its words a link to it
/// (lib/plugins/send_items.dart has the rules), then says how many went, or that one was made and its line has gone.
Future<void> _sendItems(Board board, List<SendItem> items, NoteEditing editing) async {
  final done = await _sender.send(items, board.id, editing, (text) async => (await createTask(board, text)).url);
  if (done == null) return;
  final Sent(:sent, :marked) = done;
  if (sent > 0 || marked > 0) {
    haptic(HapticKind.success);
    final made = sent > 0 ? sent : marked;
    editing.say('${made == 1 ? 'Sent 1 task' : 'Sent $made tasks'} to ${board.title}.');
  }
  // A task was made and its words could not be found to mark: said plainly, because a silent nothing is what makes
  // a person press again.
  if (sent > marked) editing.say('Made the task in ${board.title}, but the line has changed, so it isn’t marked.');
}

GlyphPlugin _make() {
  // What the page learned as its modules loaded: whether this build reaches Notion at all.
  notionReadyNow();
  unawaited(warmNotionDetails());
  return GlyphPlugin(
    manifest: manifest,
    icon: 'square-kanban',
    settings: PluginSettings(
      pane: (context) => const NotionPane(),
      summary: () => 'Boards for your lists',
      hue: 'orange',
      // What Settings' search finds on the page (docs/DESIGN.md §138): its cards, by their titles.
      settings: const [
        SettingsFindable('Account', 'sign in connect oauth workspace'),
        SettingsFindable('Boards', 'databases lists'),
      ],
    ),
    noteLinks: [
      NoteLink(
        id: 'notion-board',
        label: 'Notion board',
        icon: (context, size) => NotionMark(size: size),
        hint: (noteId) {
          final board = boardFor(noteId);
          return board != null ? 'Tasks go to ${board.title}.' : 'Choose where this note’s list items go as tasks.';
        },
        unavailable: () async => await notionAvailable() ? null : 'Needs the newest Ghost.md. Update it in Settings.',
        picker: (context, noteId, onDone) => BoardPicker(noteId: noteId, onDone: onDone),
        linked: (noteId) => boardFor(noteId)?.title,
      ),
    ],
    noteActions: [
      NoteAction(
        id: 'notion-send-list',
        label: 'Send list to Notion',
        icon: (context, size) => NotionMark(size: size),
        visible: (noteId, body) => notionReadyNow() && boardFor(noteId) != null,
        hint: (noteId, body) {
          final unsent = unsentItems(body).length;
          return unsent > 0 ? '$unsent ${unsent == 1 ? 'item isn’t' : 'items aren’t'} there yet. Each becomes a task and a link.' : 'Every item is already in Notion.';
        },
        enabled: (noteId, body) => unsentItems(body).isNotEmpty,
        run: (editing, [choice]) async {
          final board = boardFor(editing.noteId);
          if (board != null) await _sendItems(board, [for (final item in unsentItems(editing.body())) (text: item.text, line: item.line)], editing);
        },
      ),
    ],
    itemAction: ItemAction(
      id: 'notion-send-item',
      label: 'Notion',
      busyLabel: 'Sending…',
      available: (noteId) => notionReadyNow() && boardFor(noteId) != null,
      run: (text, editing) async {
        final board = boardFor(editing.noteId);
        if (board != null) await _sendItems(board, [(text: text, line: null)], editing);
      },
    ),
    // The quiet "Notion" after each item not sent yet, once a board is linked.
    suggest: (noteId, body) {
      final board = boardFor(noteId);
      if (!notionReadyNow() || board == null) return const [];
      return [
        for (final item in unsentItems(body))
          Suggestion(line: item.line, label: 'Notion', busyLabel: 'Sending', run: (editing) => _sendItems(board, [(text: item.text, line: item.line)], editing)),
      ];
    },
    marks: notionDetails,
  );
}

/// See the header (`notionPlugin`).
final GlyphPlugin notionPlugin = _make();
