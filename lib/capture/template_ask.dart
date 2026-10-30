/// A new note from a template, said (Matt, 2026-10-30, of a list of plain-Markdown features: "add all 12"; "new bug in
/// Kiln"): the template by a word of its name, the notebook or folder it goes in, and a name where one is said.
///
///     new bug in Kiln                        Bug report, in the Kiln notebook or folder
///     a new meeting in Work called Standup   A meeting, in Work, named Standup
///     make a new feature in the Ghost.md notebook
///
/// Only the words are read here. Which template a word is, and which place a name is, is the library's
/// (lib/notes/place_templates.dart `templateSaid`), asked by the root as the note is made; a word no template answers
/// to, or a place nobody has, makes the note as a note of that name, as before. Pure.
library;

/// What was said: the template's word, the place's name, and the note's name where one was given.
typedef TemplateAsk = ({String template, String place, String? title});

final RegExp _ask = RegExp(
  r"^(?:(?:please\s+)?(?:make|create|start|add|open|write)\s+(?:me\s+)?)?(?:a\s+|an\s+)?new\s+([\w’'-]+(?:\s+[\w’'-]+)?)\s+(?:in|into|under)\s+(?:the\s+|my\s+)?(.+?)(?:\s+(?:notebook|folder|workspace))?(?:\s+(?:called|named|titled)\s+(.+?))?[\s.!?]*$",
  caseSensitive: false,
);

/// Words that are a plain note, not a template: "new note in Kiln" is the folder's own template, if it has one.
const Set<String> plainNotes = {'note', 'page', 'one'};

/// A name or a list said where the template's word would be: "a new note called groceries for the week" is a note's
/// name, not a template for a place.
final RegExp _naming = RegExp(r'\b(?:called|named|titled|with|and|list|lists|item|items|entry|entries|line|lines|task|tasks|to-?dos?)\b', caseSensitive: false);

/// The ask in [words], or null where they are not one.
TemplateAsk? templateAsk(String words) {
  final found = _ask.firstMatch(words.trim());
  if (found == null) return null;
  final template = found.group(1)!.trim();
  final place = found.group(2)!.trim();
  final title = found.group(3)?.trim();
  // A place said with a comma is words after it, an item's ("new item for the field guide, Trees"), not a name.
  if (template.isEmpty || place.isEmpty || place.contains(',') || _naming.hasMatch(template)) return null;
  return (template: template, place: place, title: title == null || title.isEmpty ? null : title);
}
