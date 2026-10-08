/// What a command the model read writes: its text as literal Markdown, a new note's body, and the handoff when the
/// note being recorded onto is the one changed. A port of `src/app/capture/instructionMutation.ts`.
///
/// What differs: nothing but the shape of [SameNoteInstructionPreview], a class.
library;

import 'append_body.dart' show appendBody;
import 'list_append.dart' show InstructionArea, placeInstruction;

final RegExp _markdownMarks = RegExp(r'[\\`*_[\]{}()<>#+\-.!|>]');

/// Quotes model-proposed user text as literal Markdown text. The visible text is preserved, but model output cannot
/// create headings, links, images, emphasis, code, tables, HTML, block quotes, or list structure.
String literalMarkdown(String text) => text.replaceAllMapped(_markdownMarks, (m) => '\\${m.group(0)}');

final RegExp _wordStart = RegExp(r'(^|\s)(\p{L})', unicode: true);

/// A new list's title as heard: each word capitalised when it was written all in lower case.
String listTitle(String heard) {
  final title = heard.trim();
  return title == title.toLowerCase() ? title.replaceAllMapped(_wordStart, (m) => '${m.group(1)}${m.group(2)!.toUpperCase()}') : title;
}

/// A new note's body: its title, and what it says under it, both literal.
String instructionCreateBody(String title, String? content) {
  final safeTitle = literalMarkdown(title.trim());
  final safeContent = content == null ? null : literalMarkdown(content.trim());
  return '$safeTitle${safeContent != null && safeContent.isNotEmpty ? '\n\n$safeContent' : ''}';
}

/// What an inferred append to the note being recorded onto comes to (`SameNoteInstructionPreview`).
class SameNoteInstructionPreview {
  const SameNoteInstructionPreview({
    required this.beforeBody,
    required this.afterBody,
    required this.baseAfter,
    required this.captureMarkdown,
    required this.added,
  });

  /// Exact draft body/revision content used by compare-and-swap.
  final String beforeBody;

  /// Exact command result, including the capture transcript already saved.
  final String afterBody;

  /// New stable base beneath this capture's transcript for later autosaves.
  final String baseAfter;
  final String captureMarkdown;
  final List<String> added;
}

/// Applies an inferred append to the stable body below an active capture, then reconstructs the full draft. Keeping
/// baseAfter separate is the key handoff: later autosaves append the transcript once, rather than restoring the old
/// base or duplicating words already captured.
SameNoteInstructionPreview previewSameNoteInstruction(String baseBefore, String captureMarkdown, String content, InstructionArea? placement) {
  final placed = placeInstruction(baseBefore, literalMarkdown(content), placement);
  return SameNoteInstructionPreview(
    beforeBody: appendBody(baseBefore, captureMarkdown),
    afterBody: appendBody(placed.body, captureMarkdown),
    baseAfter: placed.body,
    captureMarkdown: captureMarkdown,
    added: placed.added,
  );
}

/// Compose a later capture draft from the post-command base without loss or duplication.
String resumeSameNoteCapture(String baseAfter, String captureMarkdown) => appendBody(baseAfter, captureMarkdown);
