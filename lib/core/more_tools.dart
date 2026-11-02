/// More tools: six features that were built in and are plugins now, off for a new person and switched on once where
/// they were already in use (docs/PM_PLUGINS.md §10; Matt, 2026-11-01, after the project tools became plugins: "think about
/// other things that can be plugins that might be overwhelming for a new user as well"). Canvas, Meetings, Diagrams
/// and math, Places, Email to a note and Publishing.
///
/// Unlike the project tools they are the person's alone: no organization lists them, so each is one switch of the
/// plugin registry's, synced between the person's devices (lib/sync/connections.dart `syncedSwitches`). The question
/// "is it on" is lib/plugins/more/more_tools.dart's.
///
/// This file is what the core needs of them and nothing that draws: their ids in the Market's order, and which of them
/// a note's words use ([moreToolsUsedIn]), kept per body as `NoteFacts.more`, so the one-time adoption can ask it of a
/// whole library at no cost, and an editor's chips know what to say.
library;

import 'front_matter.dart';
import 'maths.dart' show mathsPattern;

/// `.canvas` notes: JSON Canvas 1.0, cards, lines, groups, workspace hues.
const String canvasTool = 'canvas';

/// Ghost in meetings, a meeting recorded on the device, live transcripts, the shelf of tapes and a meeting's Note and
/// Transcript. A plain voice note is not a meeting and stays built in.
const String meetingsTool = 'meetings';

/// Mermaid diagrams, `$$` formulas and inline maths, and a code block's colouring by its language.
const String diagramsTool = 'diagrams';

/// A note's place: `location:` written on a new note, the map at its top, and place cards in the words.
const String placesTool = 'places';

/// The inbound address that turns an email into a note.
const String emailTool = 'email';

/// Published sites: Publish as a site, and the git backup's website.
const String publishingTool = 'publishing';

/// The six, in the Market's order.
const List<String> moreTools = [canvasTool, meetingsTool, diagramsTool, placesTool, emailTool, publishingTool];

/// Whether [id] is one of the six.
bool isMoreTool(String id) => moreTools.contains(id);

// ---- what a note uses ----------------------------------------------------------------------------------------------

/// A fence's opening line and its info string's first word: ```mermaid, ```dart, ~~~ python.
final RegExp _fenceInfo = RegExp(r'^[ \t]{0,3}(?:`{3,}|~{3,})[ \t]*([^\s`{]+)', multiLine: true);

/// The app's own fences, whose word is no language: the project tools', a query, comments, snippets and buttons, and
/// the words that ask for plain text.
const Set<String> appFences = {
  'query', 'board', 'gantt', 'rules', 'form', 'comments', 'snippets', 'button', 'buttons', 'transcript', 'captions', 'text', 'plain', 'plaintext', 'txt', 'none',
};

/// Whether [info] (a fence's first word) asks for a diagram or a language's colouring: `mermaid`, `math`, or any word
/// that is not one of the app's own fences.
bool fenceUsesDiagrams(String info) {
  final word = info.trim().toLowerCase();
  return word.isNotEmpty && !appFences.contains(word);
}

/// Display maths alone on its line, `$$`, opening or closing a block.
final RegExp _displayEdge = RegExp(r'^[ \t]*\$\$', multiLine: true);

/// A place card's link, `[Name](geo:52.37,4.89)`.
final RegExp _placeLink = RegExp(r'\]\(geo:-?\d');

/// A sender's address in a mail note's `from:` (`Ada <ada@example.com>`, or the address alone).
final RegExp _address = RegExp(r'[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+');

/// Which of the six [body] uses, read from its words: Diagrams and math for a ```mermaid fence, a code fence with a
/// language, `$$` and inline maths; Places for `location:` or a journal entry's `entry-place:` and a place card in the
/// words; Email to a note for a `from:` that is an address (mail_note.dart writes `from: "Ada <ada@example.com>"`);
/// Meetings for a `meeting:` mark (meeting_mark.dart). Canvas is the note's kind, `NoteFacts.isCanvas`, and
/// Publishing is the account's, so neither is read here. [span] where the caller has it. Pure, and cheap for a note
/// with none of them: a look for a fence's mark, a dollar and a `geo:`.
Set<String> moreToolsUsedIn(String body, [FrontMatterSpan? span]) {
  final front = span ?? frontMatterSpan(body);
  final out = <String>{};
  if (!front.isEmpty) {
    String? said(String key) {
      final value = frontMatterValueIn(body, front, key)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    if (said('location') != null || said('entry-place') != null) out.add(placesTool);
    if (said('from') case final from? when _address.hasMatch(from)) out.add(emailTool);
    if (said('meeting') != null) out.add(meetingsTool);
  }
  if (!out.contains(placesTool) && body.contains('](geo:') && _placeLink.hasMatch(body)) out.add(placesTool);
  if (body.contains('```') || body.contains('~~~')) {
    for (final match in _fenceInfo.allMatches(body)) {
      if (fenceUsesDiagrams(match.group(1)!)) {
        out.add(diagramsTool);
        break;
      }
    }
  }
  if (!out.contains(diagramsTool) && body.contains(r'$') && (_displayEdge.hasMatch(body) || mathsPattern.hasMatch(body))) out.add(diagramsTool);
  return out;
}
