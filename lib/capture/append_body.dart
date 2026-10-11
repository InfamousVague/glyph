/// Words on the end of a note's body, with the one blank line between that every writer of a note agrees on. A port
/// of `src/app/capture/appendBody.ts`.
///
/// Two joins. [appendBody] is a capture's words below a note it continues: what a draft, the live page, the better
/// words and the voice suite all write with. [appendBlock] is a block of its own - a table, a list started for spoken
/// items, a left note - put at the end, ending in a line break as a written note does.
///
/// What differs: nothing.
library;

final RegExp _trailing = RegExp(r'\s+$');

/// [addition] below [base], a blank line between, for a note that grew by another recording.
String appendBody(String base, String addition) {
  if (addition.trim().isEmpty) return base;
  if (base.trim().isEmpty) return addition;
  return '${base.replaceFirst(_trailing, '')}\n\n$addition';
}

/// [body] with [block] as its own block at the end, after a blank line when there is anything above it, and a line
/// break after.
String appendBlock(String body, String block) {
  final base = body.replaceFirst(_trailing, '');
  return '$base${base.isNotEmpty ? '\n\n' : ''}$block\n';
}
